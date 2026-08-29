#!/usr/bin/env python3
"""Assert against the trials module's resolved-state dump.

The module writes one artifact — debug/t_trials.txt — under Debug.DumpLuaTables,
and this is the only seam non-visual assertions go through. See CONTEXT.md for
vocabulary and the umbrella spec (issue #46) for why there is exactly one.

Usage:
    tools/check-trials-dump.py [path-to-t_trials.txt]
    tools/check-trials-dump.py --self-test

Exits non-zero if any check fails, so it can gate CI later.

--self-test asserts the checker itself, against dumps written inline. It exists
because a check here can fail in a way that looks like passing: f_printTable prints
each table once and back-references it thereafter, so a check reading the elided side
compares nothing to nothing and reports green (#50). Run it after touching parse_dump,
dig or Checks.
"""

import math
import os
import re
import sys
from collections import namedtuple

DEFAULT_PATH = "testbuild/debug/t_trials.txt"


class Elided:
    """A table the dump could not show, standing in for its contents.

    `main.f_printTable` prints each table once and replaces every later appearance
    with a back-reference — `*table: 0x…` — so a table reached by two paths has real
    contents under one of them and nothing under the other. Parsed as a plain dict
    that would be `{}`, and `{} == {}`, so a check comparing two such reads passed
    while testing nothing (#50).

    This type exists to make that impossible. It is deliberately hostile:

    - never equal to anything, including itself, so no comparison can pass through it
    - truthy, so `x or {}` cannot quietly substitute an empty dict for it
    - not a dict, so `isinstance(x, dict)` guards reject it
    - no length, so `len(x)` raises rather than reporting a plausible 0
    - `keys()` raises, so `dict(x)` and `{**x}` cannot flatten it to {}
    - indexing propagates, so reading further along the path stays marked

    It cannot cover every reduction — `bool(x)` is True, and a caller who discards it
    before comparing gets no help. Checks.unreadable() is how a call site that reduces
    before comparing asks the question explicitly.

    It carries the path it was found at, which is what a failure reports.
    """

    __slots__ = ("parts", "addr")

    def __init__(self, parts, addr):
        # The same shape dig() takes, so `dig(tree, *e.parts)` reaches it again. `path`
        # below is the readable rendering, for messages.
        self.parts = tuple(parts)
        self.addr = addr

    @property
    def path(self):
        return ".".join(str(p) for p in self.parts)

    def __bool__(self):
        return True

    def __eq__(self, other):
        return False

    def __hash__(self):
        # Distinct rather than unhashable: a set built over dug values should not
        # raise, it should simply never collapse two elided reads into one.
        return id(self)

    def __iter__(self):
        return iter(())

    def __contains__(self, key):
        return False

    def keys(self):
        # Raises rather than returning (), because `dict(e)` and `{**e}` go through
        # keys() and would otherwise produce {} — reopening the very hole this type
        # closes. Nothing in the checker calls keys() on a dug value.
        raise TypeError(
            f"cannot expand {self!r}: the dump elided this table, so it has no "
            f"contents here. Read it where it prints in full.")

    def values(self):
        return ()

    def items(self):
        return ()

    def get(self, key, default=None):
        # `default` is deliberately ignored: substituting it here is exactly the
        # silent fallback this type exists to prevent.
        return self[key]

    def __getitem__(self, key):
        return Elided(self.parts + (key,), self.addr)

    def __repr__(self):
        return f"<elided {self.path} -> {self.addr}>"


def is_elided(value):
    return isinstance(value, Elided)


def find_elided(value):
    """Every Elided reachable inside a value, in encounter order."""
    if is_elided(value):
        return [value]
    out = []
    if isinstance(value, dict):
        for v in value.values():
            out.extend(find_elided(v))
    elif isinstance(value, (list, tuple, set)):
        for v in value:
            out.extend(find_elided(v))
    return out


def elided_paths(tree):
    """Every path in a parsed dump that carries only a back-reference."""
    return sorted(e.path for e in find_elided(tree))


def parse_dump(text):
    """Parse main.f_printTable output into nested dicts.

    The format is: ["key"] => value, where value is a scalar or `table: 0x… {`
    opening a block that closes on a lone `}`. Scalars arrive as quoted strings,
    bare numbers, booleans, or `function: 0x…`.

    A block whose only line is `*table: 0x…` is one f_printTable had already printed
    elsewhere. It becomes an Elided rather than an empty dict, so nothing downstream
    can mistake "hidden" for "empty".
    """
    entry = re.compile(r'^\s*\[(.+?)\]\s*=>\s*(.*)$')
    elision = re.compile(r'^\s*\*(table: 0x[0-9a-fA-F]+)\s*$')
    root = {}
    # One frame per open block: the dict being filled, the parent and key it hangs
    # off, and the path it sits at. The root has no parent, so an elision at top level
    # — which f_printTable cannot emit — is ignored rather than crashing.
    Frame = namedtuple("Frame", "table parent key parts")
    stack = [Frame(root, None, None, ())]

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        m = elision.match(line)
        if m:
            frame = stack[-1]
            if frame.parent is not None:
                # Replaces the block in its parent. The frame's own dict is left
                # orphaned, which is safe only because f_printTable writes nothing
                # else inside an elided block — the back-reference is the whole body.
                frame.parent[frame.key] = Elided(frame.parts, m.group(1))
            continue

        if stripped == "}" or stripped.endswith("}") and "=>" not in stripped:
            if len(stack) > 1:
                stack.pop()
            continue

        m = entry.match(line)
        if not m:
            continue
        raw_key, raw_val = m.group(1), m.group(2).strip()

        key = raw_key[1:-1] if raw_key.startswith('"') and raw_key.endswith('"') else raw_key
        try:
            key = int(key)
        except ValueError:
            pass

        if raw_val.startswith("table:"):
            child = {}
            parent = stack[-1]
            parent.table[key] = child
            stack.append(Frame(child, parent.table, key, parent.parts + (key,)))
        else:
            stack[-1].table[key] = parse_scalar(raw_val)

    return root


def parse_scalar(raw):
    raw = raw.rstrip("{").strip()
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    if raw == "true":
        return True
    if raw == "false":
        return False
    if raw == "nil":
        return None
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    return raw


def trialdef_sections(path):
    """The [TrialDef] headers a Trial Definition declares, in order.

    Read the way go-ini reads a header — from the opening bracket to the LAST closing
    bracket on the line — so a header carrying a comment with a bracket in it is
    counted here the same way the module counts it.

    This is a second, independent reading of the file. That is the point: the failure
    it guards against is two same-named sections merging in the ini parser, which
    leaves a dump agreeing with itself. Eight of cvsryu's 38 Trials were unreachable
    that way and nothing in the parsed state said so (#51).
    """
    out = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.lstrip()
            if not line.startswith("["):
                continue
            close = line.rfind("]")
            if close < 0:
                continue
            name = line[1:close].strip()
            if name.lower().startswith("trialdef"):
                out.append(name)
    return out


def trialdef_titles(path):
    """The Trial titles a definition declares, in order.

    The module's own rule, reproduced: whatever follows the FIRST comma of the section
    name, and where that carries a `;` — which go-ini's last-bracket rule swallows into
    the name along with the header's own closing bracket — the comment and the bracket
    come back off (`trialTitle`, trials.lua).

    Titles may repeat (#51), so this is a list and never a set.
    """
    out = []
    for name in trialdef_sections(path):
        title = name.split(",", 1)[1].strip() if "," in name else ""
        if ";" in title:
            title = re.sub(r"\s*;.*$", "", title)
            title = re.sub(r"\s*\]\s*$", "", title)
        out.append(title.rstrip())
    return out


def char_def_trials_key(path):
    """The key a character def spells its Trial Definition with, as authored.

    Returns 'Trials', 'TRIALS', 'trials' — whatever the [Files] section wrote — or
    None when the def names no Trial Definition at all.

    A second, independent reading of the def, for the reason trialdef_sections is one:
    the failure it guards against is discovery matching on key case (#47), and a dump
    built from the same case-sensitive read would agree with itself.
    """
    in_files = False
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("["):
                close = line.rfind("]")
                if close >= 0:
                    # go-ini's last-bracket rule, the way trialdef_sections reads one.
                    in_files = line[1:close].strip().lower() == "files"
                continue
            # A commented-out `;trials = …` declares nothing, so the comment comes off
            # before the key is read.
            line = line.split(";", 1)[0].strip()
            if not in_files or "=" not in line:
                continue
            key = line.split("=", 1)[0].strip()
            if key.lower() == "trials":
                return key
    return None


def dig(tree, *path):
    cur = tree
    for part in path:
        # Reading further along an elided path stays elided, rather than collapsing
        # to the None that a genuinely absent key returns.
        if is_elided(cur):
            return cur[part]
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


class Checks:
    def __init__(self, quiet=False):
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.quiet = quiet
        self.reasons = []

    def _print(self, *lines):
        if not self.quiet:
            for line in lines:
                print(line)

    def skip(self, label, reason):
        """Record a check that could not run, so the suite cannot shrink in silence.

        A suite that quietly reports five fewer checks than last time is the same
        failure as a check that quietly passes (#50): the total is the only tell.
        """
        self.skipped += 1
        self._print(f"  \033[33m-\033[0m {label}  ({reason})")

    def unreadable(self, label, *values):
        """Fail instead of comparing, when a value was read through an elided table.

        Without this the comparison still happens, and two reads that both saw
        nothing agree — reporting green for something the dump never showed.

        Public because a call site that reduces before comparing — `len(x)`, a set
        comprehension, arithmetic — throws the Elided away before check() could see
        it, and has to ask first. Returns True when it has already failed.
        """
        hidden = [e for v in values for e in find_elided(v)]
        if not hidden:
            return False
        reason = "read through a table the dump elided: " + ", ".join(
            f"{e.path} (back-reference to {e.addr})" for e in hidden)
        self._print(
            f"  \033[31m✗\033[0m {label}",
            f"      {reason}",
            "      f_printTable prints this table's contents under another path and "
            "leaves only a back-reference here,",
            "      so the check cannot see it. Read it where it prints in full, or "
            "have f_dumpState copy the values.")
        self.reasons.append(reason)
        self.failed += 1
        return True

    def check(self, label, actual, expected):
        if self.unreadable(label, actual, expected):
            return
        if actual == expected:
            self._print(f"  \033[32m✓\033[0m {label}")
            self.passed += 1
        else:
            self._print(f"  \033[31m✗\033[0m {label}",
                        f"      expected: {expected!r}",
                        f"      actual:   {actual!r}")
            self.failed += 1

    def present(self, label, actual):
        if self.unreadable(label, actual):
            return
        if actual is not None:
            self._print(f"  \033[32m✓\033[0m {label}")
            self.passed += 1
        else:
            self._print(f"  \033[31m✗\033[0m {label}  (missing)")
            self.failed += 1


# A dump of a table reached twice, as f_printTable writes it. `chars.1.dummy` prints
# in full; `match.dummy` is the same Lua table, so it opens its block and immediately
# closes it with a back-reference to the address already printed.
# A dump of a table reached twice, as f_printTable writes it. `chars.1.dummy` prints
# in full; `match.dummy` is the same Lua table, so it opens its block and immediately
# closes it with a back-reference to the address already printed.
ELIDED_FIXTURE = """table: 0x1 {
  ["chars"] => table: 0x2 {
                 [1] => table: 0x3 {
                          ["name"] => "Kung Fu Man"
                          ["dummy"] => table: 0x9 {
                                         ["mode"] => 1
                                         ["guard"] => 2
                                       }
                        }
               }
  ["match"] => table: 0x4 {
                 ["current"] => 2
                 ["dummy"] => table: 0x9 {
                                *table: 0x9
                              }
               }
}
"""

# The same dump with nothing shared, so the elision machinery has nothing to mark.
CLEAN_FIXTURE = ELIDED_FIXTURE.replace("""["dummy"] => table: 0x9 {
                                *table: 0x9
                              }
""", "")


def raises(exc, fn):
    """True when calling fn() raises exc. Used to assert that Elided refuses a read."""
    try:
        fn()
    except exc:
        return True
    return False


def run_self_tests():
    """Assert the checker cannot report green on something it cannot see.

    There is no test framework in this repo and #46 rules one out, so the checker
    carries its own. These are the cases from #50: before it, a comparison between
    two elided tables passed because both parsed to nothing.
    """
    t = Checks()

    t._print("\nParsing an elided table")
    tree = parse_dump(ELIDED_FIXTURE)
    visible = dig(tree, "chars", 1, "dummy")
    hidden = dig(tree, "match", "dummy")
    t.check("the table that printed in full is readable", visible, {"mode": 1, "guard": 2})
    t.check("the table that was elided is marked, not empty", is_elided(hidden), True)
    t.check("  ... and names where it was elided", hidden.path, "match.dummy")
    t.check("  ... in the shape dig() takes", hidden.parts, ("match", "dummy"))
    t.check("  ... and the address it points back to", hidden.addr, "table: 0x9")

    t._print("\nReading through an elided table")
    t.check("digging into one propagates rather than returning None",
            is_elided(dig(tree, "match", "dummy", "mode")), True)
    t.check("  ... and is not silently falsy", bool(hidden), True)
    t.check("  ... and does not pretend to be a dict", isinstance(hidden, dict), False)
    t.check("  ... and cannot be flattened to an empty dict",
            raises(TypeError, lambda: dict(hidden)), True)
    t.check("  ... and has no plausible-looking length",
            raises(TypeError, lambda: len(hidden)), True)

    t._print("\nA check that reads an elided table fails")
    # The #38 regression: both sides dug to nothing and compared equal.
    c = Checks(quiet=True)
    c.check("two elided reads must not agree",
            [dig(tree, "match", "dummy", f) for f in ("mode", "guard")],
            [dig(tree, "match", "dummy", f) for f in ("mode", "guard")])
    t.check("comparing two elided reads fails", c.failed, 1)
    # Asserted on the reason, not just the count: Elided.__eq__ alone would fail this
    # comparison, so a count-only assertion would stay green with the guard removed.
    t.check("  ... attributed to the elision, naming the path",
            c.reasons and "match.dummy" in c.reasons[0], True)

    c = Checks(quiet=True)
    c.check("elided against a real value", dig(tree, "match", "dummy", "mode"), 1)
    t.check("an elided actual fails against a real expected", c.failed, 1)
    t.check("  ... also attributed to the elision",
            c.reasons and "match.dummy.mode" in c.reasons[0], True)

    c = Checks(quiet=True)
    c.present("an elided value is not 'present'", dig(tree, "match", "dummy"))
    t.check("present() rejects one too", (c.passed, c.failed), (0, 1))

    t._print("\nA dump with nothing elided is unaffected")
    clean = parse_dump(CLEAN_FIXTURE)
    t.check("nothing is marked", elided_paths(clean), [])
    c = Checks(quiet=True)
    c.check("a real value still passes", dig(clean, "chars", 1, "dummy", "mode"), 1)
    c.check("a wrong value still fails", dig(clean, "chars", 1, "dummy", "mode"), 2)
    t.check("normal checks behave exactly as before", (c.passed, c.failed), (1, 1))

    t._print("\nElided paths are reported")
    t.check("the elided fixture lists its one alias", elided_paths(tree), ["match.dummy"])

    # The parser and Checks are only half the story: what matters is that the real
    # assertions in run_checks fail when the dump hides what they read. Driven over a
    # real dump when one is on disk, since no synthetic fixture exercises all of them.
    t._print("\nThe real checks, over a dump with a table elided")
    # Newest wins, not a fixed order: a dump left on disk by an older build of the
    # module legitimately fails checks written after it, which says nothing about the
    # checker and would report here as a self-test failure.
    candidates = [p for p in (DEFAULT_PATH, DEFAULT_PATH.replace(".txt", ".harness.txt"))
                  if os.path.exists(p)]
    dump = max(candidates, key=os.path.getmtime) if candidates else None
    if dump is None:
        t.skip("the real checks fail when what they read is elided",
               "no dump on disk; run the build first")
    else:
        with open(dump) as handle:
            text = handle.read()
        base = run_checks(parse_dump(text), quiet=True)
        t.check(f"{dump} passes as it stands", base.failed, 0)

        # The alias #50 is about: chars and match reach the same Dummy tables, and
        # today chars wins. Elide the chars side to simulate pairs() ordering flipping.
        flipped = parse_dump(text)
        n = 0
        for row in (dig(flipped, "chars") or {}).values():
            for trial in (dig(row, "trials") or {}).values():
                if isinstance(trial, dict) and isinstance(trial.get("dummy"), dict):
                    trial["dummy"] = Elided(("chars", "?", "trials", "?", "dummy"),
                                            "table: 0xfeedface")
                    n += 1
        t.check("the fixture elided something the checks read", n > 0, True)
        after = run_checks(flipped, quiet=True)
        t.check("  ... and the checks fail rather than passing", after.failed > 0, True)
        t.check("  ... naming the elision as the cause",
                any("elided" in r for r in after.reasons), True)
        # The #50 failure in its other costume: a suite that quietly reports fewer
        # checks than it did before.
        t.check("  ... without the suite quietly shrinking",
                after.passed + after.failed + after.skipped,
                base.passed + base.failed + base.skipped)

    t._print("")
    if t.failed:
        t._print(f"  {t.failed} self-test(s) failed")
        return 1
    t._print(f"  {t.passed} self-tests passed"
             + (f", {t.skipped} skipped" if t.skipped else ""))
    return 0


def run_checks(tree, quiet=False, dump_path=DEFAULT_PATH):
    """Every assertion, against one parsed dump. Returns the Checks that ran them.

    Separate from main() so the self-tests can drive the real assertions — not just
    the parser — over a dump with a table elided, which is what #50 asks be verified.
    """
    c = Checks(quiet=quiet)

    # Informational, not a failure. A table reached by two paths is normal — the dump
    # is a snapshot of live state and state is shared. What is not survivable is a
    # check reading the elided side, and that fails on its own wherever it happens.
    # Listing them here is what makes such a failure diagnosable in one look.
    hidden = elided_paths(tree)
    if hidden and not quiet:
        c._print("\nElided by f_printTable — printed in full elsewhere, empty here")
        for path in hidden:
            c._print(f"  ·   {path}")
        c._print("      Any check reading these fails rather than passing. To assert on "
              "one, read it")
        c._print("      where it prints in full, or have f_dumpState copy the values out "
              "(see dummyWritten).")

    c._print("\nModule bootstrap")
    c.check("module directory resolved", dig(tree, "dir"), "external/mods/trials/")
    c.check("module is enabled", dig(tree, "enabled"), True)
    c.present("config.ini parsed", dig(tree, "ini"))
    c.present("Trials Config resolved", dig(tree, "config"))
    c.check("language resolved", dig(tree, "language"), "en")

    c._print("\nconfig.ini — dotted keys nest, types coerce")
    # Every key under [Options] is a Player Preference the trials pause menu writes back
    # (#40), so the value is the player's and not the module's. What is assertable is
    # that the key is still there and still of the type its reader expects — a dotted
    # key that stopped nesting, or a boolean that came back as the word for one, is what
    # this block is watching for.
    opts = dig(tree, "ini", "Options", "Trials")
    c.check("Options.Trials.Layout is one the module knows",
            (dig(opts, "Layout") if opts else None) in ("vertical", "horizontal"), True)
    c.check("Options.Trials.Advancement is one the module knows",
            (dig(opts, "Advancement") if opts else None) in ("autoadvance", "repeat"), True)
    c.check("Options.Trials.ResetOnSuccess is bool",
            isinstance(dig(opts, "ResetOnSuccess") if opts else None, bool), True)
    c.check("Options.Trials.TotalTimer is bool",
            isinstance(dig(opts, "TotalTimer") if opts else None, bool), True)
    c.check(
        "Common.States points at the module's zss",
        dig(tree, "ini", "Common", "States"),
        "external/mods/trials/trials.zss",
    )

    c._print("\nTrials Config — three layers, screenpack last (#36)")
    c.check("layer 1 is the module's defaults", dig(tree, "layers", 1, "name"), "defaults")
    c.check("layer 2 is the module's config.ini", dig(tree, "layers", 2, "name"), "config.ini")
    c.check("layer 3 is the screenpack", dig(tree, "layers", 3, "name"), "screenpack")
    c.check(
        "[Trials Mode] menu.itemname.trials",
        dig(tree, "config", "trials_mode", "menu", "itemname", "trials"),
        "TRIALS",
    )
    c.present("[Trials Mode] nodata.text", dig(tree, "config", "trials_mode", "nodata", "text"))
    c.present("authored key order preserved (__order)", dig(tree, "config", "trials_mode", "__order"))
    c.check(
        "counter text comes from the module by default",
        dig(tree, "configSource", "trials_mode.trialcounter.font"),
        "defaults",
    )

    # These two need the #36 fixture appended to testbuild/data/ikemen1/system.def.
    # Without it the screenpack defines no trials sections and both checks are skipped.
    source = dig(tree, "configSource") or {}
    if source.get("trials_mode.trialcounter.text", "").startswith("screenpack"):
        c.check(
            "screenpack overrides the module's counter text",
            dig(tree, "config", "trials_mode", "trialcounter", "text"),
            "Screenpack: Trial %i of %s",
        )
        c.check(
            "a language-prefixed section beats the unprefixed one",
            dig(tree, "configSource", "trials_mode.nodata.text"),
            "screenpack [en]",
        )
        c.check(
            "and supplies its value",
            dig(tree, "config", "trials_mode", "nodata", "text"),
            "Screenpack EN: no trials for this character.",
        )
        # The fixture's base section spells the no-data message the pre-refactor way.
        # Under Config.Language = es the EN section drops out and that is what wins.
        nodata_src = str(dig(tree, "configSource", "trials_mode.nodata.text") or "")
        c.check(
            "the legacy trialcounter.notrialsdata.text spelling is still read",
            "via trialcounter.notrialsdata.text" in nodata_src
            or nodata_src == "screenpack [en]",
            True,
        )
    else:
        c.skip("screenpack layer wins over the module's own",
               "screenpack override fixture not installed")

    c._print("\nElement construction (#36)")
    counter = dig(tree, "elements", "trialcounter")
    c.present("trial counter built at load", counter)
    c.check("counter reads a layer number", dig(counter, "layerno") if counter else None, 0)
    c.present("counter localcoord resolved", dig(counter, "localcoord") if counter else None)
    c.present("counter position resolved", dig(counter, "pos") if counter else None)
    if counter:
        # A match can render at the stage's aspect rather than the screenpack's. At 4:3
        # only x in [0,320] of the engine's internal space is on screen; at 16:9 it is
        # [-53.3, 373.3]. Reproduces TextSprite.SetLocalcoord/SetPos (src/font.go:850).
        lc = counter.get("localcoord") or {}
        pos = counter.get("pos") or {}
        lx, ly = lc.get(1), lc.get(2)
        px, py = pos.get(1), pos.get(2)
        if c.unreadable("counter geometry is readable", lx, ly, px, py):
            pass
        elif None not in (lx, ly, px, py):
            v = ly * 4 / 3 if lx * 3 > ly * 4 else lx
            ix = px * (320 / v) - int(math.floor(lx / (v / 320) - 320) / 2)
            iy = py * (320 / v)
            c._print(f"      (internal position: {ix:.1f}, {iy:.1f})")
            c.check("counter is on screen at 4:3", 0 <= ix <= 320 and 0 <= iy <= 240, True)
            c.check("counter is on screen at 16:9", -53.4 <= ix <= 373.4 and 0 <= iy <= 240, True)

    c._print("\nTrial Definition discovery (#36)")
    chars = dig(tree, "chars") or {}
    rows = [v for v in chars.values() if isinstance(v, dict)]
    checked = [r for r in rows if r.get("checked")]
    with_trials = [r for r in rows if r.get("trialCount")]
    # Discovery runs at module load, so this is assertable from the startup dump with
    # no interaction — see the umbrella spec's testing decisions.
    c.check("the roster was swept at load", bool(checked), True)
    c.check("every playable character was checked", len(checked), len(rows))
    c.check("at least one character ships a Trial Definition", bool(with_trials), True)
    c.check(
        "characters without one are detected as such",
        bool([r for r in checked if not r.get("trialCount")]),
        True,
    )
    for r in with_trials:
        c.present(f"{r.get('name')}: Trial Definition resolved", r.get("trialsDef"))
        c.present(f"{r.get('name')}: Trials read in authored order", dig(r, "titles", 1))

    # Every [TrialDef] section is a Trial, whatever the titles are (#51). A title is a
    # label and not an identity: a character with modes spells the same combo once per
    # mode, and trial.showforvarvalpairs decides which of them the player is offered.
    # The dump is compared against the file rather than against a number written here,
    # so a definition that grows a Trial does not need this checker edited.
    # The engine's own working directory, climbed out of the dump's path: the dump is
    # written to <build>/debug/t_trials.txt and a Trial Definition's path is recorded
    # relative to <build>. A fixture outside it is recorded absolute and needs no root.
    build_root = os.path.dirname(os.path.dirname(os.path.abspath(dump_path)))
    for r in with_trials:
        name = r.get("name")
        defpath = r.get("trialsDef")
        label = f"{name}: one Trial per [TrialDef] section"
        if not isinstance(defpath, str):
            c.skip(label, "the dump does not name the file")
            continue
        full = defpath if os.path.isabs(defpath) else os.path.join(build_root, defpath)
        if not os.path.exists(full):
            c.skip(label, f"{defpath} is not on this machine")
            continue
        declared = trialdef_sections(full)
        c.check(label, r.get("trialCount"), len(declared))
        # The titles themselves, in order, not just how many: a parse that reached
        # every section but lost the order of a repeated pair would pass on the count
        # alone, and authored order is what the player is offered them in.
        titles = r.get("titles")
        order_label = f"  {name}: in the order the file declares them"
        if not c.unreadable(order_label, titles):
            found = ([titles[i] for i in sorted(titles) if isinstance(i, int)]
                     if isinstance(titles, dict) else None)
            c.check(order_label, found, trialdef_titles(full))
        # Named separately from the count so a definition that has no repeated title
        # says so rather than looking like it was not checked.
        repeated = len(declared) - len(set(declared))
        c._print(f"      ({len(declared)} sections, {repeated} of them a repeated title)")

    # Discovery lowercases the def's [Files] keys, so a character whose def writes
    # `Trials =` or `TRIALS =` is found rather than silently recorded as shipping none
    # (#47). Asserted against the def files themselves rather than against a fixture,
    # so it holds on any roster: whatever case a def spells the key in, a character
    # that declares one must carry a resolved Trial Definition.
    # Paired with the row rather than looked up by name: two characters on a stock
    # roster are both called Kung Fu Man, and matching on the name would ask one of
    # them about the other's def.
    declaring = []
    for r in rows:
        defpath = r.get("def")
        if not isinstance(defpath, str):
            continue
        full = defpath if os.path.isabs(defpath) else os.path.join(build_root, defpath)
        if not os.path.exists(full):
            continue
        key = char_def_trials_key(full)
        if key is not None:
            declaring.append((r, key))
    for r, key in declaring:
        c.check(f"{r.get('name')} ({os.path.basename(str(r.get('def')))}): "
                f"declares `{key} =` and its definition resolved",
                isinstance(r.get("trialsDef"), str), True)
    if declaring:
        spellings = {}
        for _, key in declaring:
            spellings[key] = spellings.get(key, 0) + 1
        c._print("      (spellings on this roster: " + ", ".join(
            f"{k} ×{n}" for k, n in sorted(spellings.items())) + ")")
    # Named separately, because the checks above only exercise the fix when a def on
    # this roster actually spells the key with a capital. A roster that spells it
    # lowercase throughout has nothing to prove — it says so rather than passing.
    mixed = [(r, key) for r, key in declaring if key != key.lower()]
    if mixed:
        c.check("every def spelling the key with a capital was still resolved",
                [key for r, key in mixed if not isinstance(r.get("trialsDef"), str)],
                [])
    else:
        c.skip("case-insensitive discovery exercised",
               "no def on this roster spells the key other than all-lowercase")

    c._print("\nStep text, vertical layout (#37)")
    block = dig(tree, "steps")
    c.present("Step block resolved at load", block)
    # The block in the dump is whichever Layout the player has selected (#41), so this
    # asserts the two agree rather than that either one is vertical. Lowercased on the
    # config.ini side because stepLayout() lowercases before it matches: a hand-edited
    # `Trials.Layout = Horizontal` selects the horizontal block, and comparing it raw
    # would report that working case as a failure.
    preferred = dig(tree, "ini", "Options", "Trials", "Layout")
    c.check("the block in use is the Layout the preference names",
            dig(block, "layout") if block else None,
            str(preferred).lower() if isinstance(preferred, str) else preferred)
    c.present("row spacing resolved", dig(block, "spacing") if block else None)
    c.present("clipping window resolved", dig(block, "window") if block else None)
    c.present("with-textbox window resolved", dig(block, "windowWithTextbox") if block else None)
    for status in ("upcoming", "current", "completed"):
        el = dig(tree, "elements", f"{status}step.vertical.text")
        c.present(f"{status} Step element built at load", el)
        if el:
            # All three sit on the one trialsteps.<layout> block, so a font colour is
            # what distinguishes them and the origin must be identical.
            c.present(f"  {status}: font resolved", el.get("font"))
            c.present(f"  {status}: origin inherited from the block", el.get("pos"))
            # Sharing another element's localcoord table is exactly what makes
            # f_printTable elide it here, so that is now detected outright rather
            # than inferred from an empty table.
            lc = el.get("localcoord")
            if not c.unreadable(f"  {status}: localcoord is its own", lc):
                c.check(f"  {status}: localcoord resolved to a pair", len(lc or {}), 2)
    statuses = ("upcoming", "current", "completed")
    positions = [dig(tree, "elements", f"{s}step.vertical.text", "pos") for s in statuses]
    if not c.unreadable("all three Step Statuses share one origin", positions):
        c.check("all three Step Statuses share one origin",
                len({tuple((p or {}).values()) for p in positions}), 1)
    fonts = [dig(tree, "elements", f"{s}step.vertical.text", "font") for s in statuses]
    if not c.unreadable("and are styled apart", fonts):
        c.check("and are styled apart",
                len({tuple(list((f or {}).values())[3:7]) for f in fonts}), 3)

    c._print("\nHorizontal Layout (#41)")
    # Both Layouts are built at load and the preference picks between them, so the
    # horizontal elements are in the dump whichever one is being drawn. Their absence
    # means a player switching Layout mid-match gets no Steps at all.
    for status in ("upcoming", "current", "completed"):
        c.present(f"{status} Step element built for the horizontal Layout",
                  dig(tree, "elements", f"{status}step.horizontal.text"))
    hpos = [dig(tree, "elements", f"{s}step.horizontal.text", "pos")
            for s in ("upcoming", "current", "completed")]
    if not c.unreadable("all three sit on the horizontal block's origin", hpos):
        c.check("all three sit on the horizontal block's origin",
                len({tuple((p or {}).values()) for p in hpos}), 1)
    # Reported rather than asserted: a screenpack is free to put both Layouts in the same
    # place, so the two origins differing is informative and not a rule.
    vpos = dig(tree, "elements", "currentstep.vertical.text", "pos")
    c._print(f"      (vertical origin {list((vpos or {}).values())}, "
             f"horizontal {list((hpos[1] or {}).values())})")
    # Padding is the horizontal Layout's own key — the gap between a Step's text and the
    # edges of its item — and a row is laid out from it every frame. Only the Layout in
    # use has its block geometry in the dump, so on a vertical run there is nothing here
    # to read and the check says so rather than passing on an absent value.
    if block and dig(block, "layout") == "horizontal":
        c.present("row padding resolved", dig(block, "padding"))
        c.present("wrapping window resolved", dig(block, "window"))
    else:
        c.skip("row padding resolved", "the vertical Layout is the one selected")
        c.skip("wrapping window resolved", "the vertical Layout is the one selected")
    # The horizontal origin has to be on screen at both aspects for the same reason the
    # counter does: a match may render at the stage's aspect, not the screenpack's.
    lc = dig(tree, "elements", "currentstep.horizontal.text", "localcoord") or {}
    pos = dig(tree, "elements", "currentstep.horizontal.text", "pos") or {}
    lx, ly, px, py = lc.get(1), lc.get(2), pos.get(1), pos.get(2)
    if c.unreadable("horizontal origin is readable", lx, ly, px, py):
        pass
    elif None not in (lx, ly, px, py):
        v = ly * 4 / 3 if lx * 3 > ly * 4 else lx
        ix = px * (320 / v) - int(math.floor(lx / (v / 320) - 320) / 2)
        iy = py * (320 / v)
        c._print(f"      (internal position: {ix:.1f}, {iy:.1f})")
        c.check("the horizontal origin is on screen at 4:3",
                0 <= ix <= 320 and 0 <= iy <= 240, True)
        c.check("the horizontal origin is on screen at 16:9",
                -53.4 <= ix <= 373.4 and 0 <= iy <= 240, True)

    c._print("\nSteps parsed from the Trial Definition (#37)")
    parsed = [t for r in with_trials for t in (r.get("trials") or {}).values()
              if isinstance(t, dict)]
    c.check("every Trial parsed to at least one Step",
            bool(parsed) and all(t.get("stepCount", 0) >= 1 for t in parsed), True)
    c.check("Steps carry the text they render",
            bool(parsed) and all(t.get("firstStepText") for t in parsed), True)
    multi = [t for t in parsed if t.get("stepCount", 0) > 1]
    c.check("at least one Trial has several Steps", bool(multi), True)

    c._print("\nDummy settings parsed per Trial (#38)")
    # Every Trial carries the whole triple whether or not it named one, which is what
    # stops a setting leaking from the Trial before it. A Trial that named nothing has
    # an empty word in `authored` next to the default value.
    dummies = [t.get("dummy") for t in parsed]
    c.check("Trials were found to read Dummy settings from", bool(dummies), True)
    # The unreadable ones are passed through rather than counted, so that an elided
    # table arrives at the check and reports its own path. Reduced to a bool first,
    # this failure would say only `False`. `chars` and `match` reach these same tables,
    # so which side is readable depends on pairs() ordering — this is the check most
    # exposed to it.
    c.check("every Trial resolved its Dummy settings",
            [d for d in dummies if not isinstance(d, dict)], [])

    # Deliberately not guarded on the check above passing. Skipping the rest when the
    # Dummy settings are unreadable would shrink the suite from seven checks to two
    # with nothing but the total to say so — which is the #50 failure wearing a
    # different hat. Every check below fails cleanly on an Elided instead.
    #
    # Spelled out here rather than read from the module: an expected value that was
    # computed the way the code computes it could never disagree with it. This is the
    # independent copy of what README.md documents.
    vocabulary = {
        "mode": {"stand": 0, "crouch": 1, "jump": 2, "wjump": 3},
        "guard": {"none": 0, "auto": 2},
        "buttonjam": {"none": 0, "a": 1, "b": 2, "c": 3, "x": 4,
                      "y": 5, "z": 6, "start": 7, "d": 8, "w": 9},
    }
    c.check("every Trial carries the whole triple",
            [d for d in dummies if not all(k in d for k in vocabulary)], [])
    c.check("values stay inside the vocabulary trials.zss reads",
            [d for d in dummies
             if any(d.get(f) not in words.values() for f, words in vocabulary.items())],
            [])

    def mismatches(d):
        """Fields of one resolved Dummy that disagree with the word behind them."""
        authored = d.get("authored")
        if not isinstance(authored, dict):
            return list(vocabulary)
        out = []
        for field, words in vocabulary.items():
            # An unnamed setting takes the default; a named one resolves to its own
            # value and to nothing else.
            word = authored.get(field, "")
            expected = 0 if word == "" else words.get(word)
            if d.get(field) != expected:
                out.append(field)
        return out

    c.check("each value matches the word it was resolved from",
            [d for d in dummies if mismatches(d)], [])

    # Parsing is only half of it. The maps are written during the match, and the
    # module rewrites this artifact the moment it does, so a dump taken after a real
    # run also says what reached the Dummy.
    written = dig(tree, "dummyWritten")
    if written is None:
        c.skip("the Dummy was configured for the Trial the match is on",
               "no match in this dump reached roundstate 1")
        c.skip("the values written to the shared maps match their words",
               "no match in this dump reached roundstate 1")
    else:
        c.check("the Dummy was configured for the Trial the match is on",
                dig(written, "trial"), dig(tree, "match", "current"))
        c.check("the values written to the shared maps match their words",
                mismatches(written) if isinstance(written, dict) else written, [])

    c._print("\nSteps verify, advance, and fire Success (#39)")
    # The parsed matcher is assertable from the startup dump with no interaction: it is
    # what the Trial Definition resolved to, before anybody plays anything.
    dumped_steps = [st for t in parsed for st in (t.get("steps") or {}).values()
                    if isinstance(st, dict)]
    c.check("Steps parsed to Parts", bool(dumped_steps), True)
    c.check("every Step has at least one Part",
            [st for st in dumped_steps if not (st.get("partCount") or 0) >= 1], [])
    c.check("a comma-separated Step parsed to several Parts",
            bool([st for st in dumped_steps if (st.get("partCount") or 0) > 1]), True)

    c._print("\nGlyphs beside the Step text (#42, closes #3)")
    # Tokenised at parse time against the screenpack's [Glyphs] vocabulary, so what a
    # Step resolved to is assertable from the startup dump with no interaction.
    c.check("every Step resolved its Glyphs to a list, declared or not",
            [st for st in dumped_steps if not isinstance(st.get("glyphs"), str)], [])
    c.check("Steps declaring Glyphs tokenised to at least one",
            bool([st for st in dumped_steps if (st.get("glyphCount") or 0) > 0]), True)
    # The whole of #3: a Step with no Glyphs is an empty list and not a missing one, and
    # the horizontal Layout lays such a Step out with no room reserved for them. There is
    # nothing here to assert on a roster where every Step declares Glyphs, so say so
    # rather than pass on an absent case.
    bare = [st for st in dumped_steps if (st.get("glyphCount") or 0) == 0]
    if bare:
        c.check("a Step declaring no Glyphs parsed to an empty list, not a nil",
                [st for st in bare if st.get("glyphs") != ""], [])
    else:
        c.skip("a Step declaring no Glyphs parsed to an empty list, not a nil",
               "every Step on this roster declares Glyphs")
    # A token count that disagrees with the tokens is the tokeniser losing one silently,
    # which on screen is a run one Glyph short and nothing else.
    c.check("the token count matches the tokens",
            [st for st in dumped_steps
             if (st.get("glyphCount") or 0) != len([t for t in str(st.get("glyphs") or "").split("|") if t])],
            [])

    glyphs = dig(block, "glyphs") if block else None
    c.present("Glyph geometry resolved for the Layout in use", glyphs)
    if glyphs and not c.unreadable("Glyph geometry is its own", glyphs):
        c.present("  run offset resolved", dig(glyphs, "offset"))
        c.present("  run spacing resolved", dig(glyphs, "spacing"))
        c.check("  scale is a multiplier, so it defaults to 1",
                list((dig(glyphs, "scale") or {}).values()), [1, 1])
        c.check("  align is one the run knows",
                dig(glyphs, "align") in (-1, 0, 1), True)
        # Counted over the Trials of the character the match is on, so it is empty until
        # a match has selected one. An unknown token is not a failure — a Trial
        # Definition written for another screenpack is a supported case — but it is the
        # first thing to read when a run draws short.
        known, unknown = dig(glyphs, "known"), dig(glyphs, "unknown")
        if (known or 0) + (unknown or 0) == 0:
            c.skip("the screenpack has a Glyph for the tokens in use",
                   "no Trial selected in this dump, so no tokens were resolved")
        else:
            c._print(f"      ({known} of {(known or 0) + (unknown or 0)} tokens have a "
                     f"Glyph in this screenpack)")
            c.check("the screenpack has a Glyph for the tokens in use", unknown, 0)

    c._print("\nStep backgrounds (#53)")
    # The graphical layer under the Steps, for the Layout in use. What is assertable
    # from a startup dump is what it resolved TO -- whether it built, out of which file,
    # and how wide -- not how it looks, which needs a person at the screen.
    bg = dig(block, "bg") if block else None
    c.present("the Step display's graphical layer resolved", bg)
    if bg and not c.unreadable("the graphical layer is its own", bg):
        # Not a failure. A screenpack is free to style the Steps with no artwork behind
        # them at all, and the module ships defaults only so a stock one has some.
        if dig(bg, "block") is not True:
            # `art` says which of the two it is: a screenpack that styled the Steps with
            # no artwork behind them, or one that repositioned the block and so had the
            # module's own 320x240 artwork dropped rather than drawn at the wrong scale.
            c.skip("a background is drawn behind the whole Step list",
                   dig(bg, "art") or "this configuration declares none for the "
                   "Layout in use")
        else:
            c.check("a background is drawn behind the whole Step list",
                    dig(bg, "block"), True)
            # A screenpack that meant a sprite in its OWN sff and got the module's would
            # otherwise show up only as artwork nobody recognises, and only on screen.
            c.check("  its sprite came from a file that could have meant it",
                    dig(bg, "art") in ("module", "screenpack"), True)
            # Nothing else can say this. A dropped or unloadable one reports as no
            # background at all, which is the skip above, and both read on screen
            # exactly like a screenpack that asked for none.

            c._print(f"      (resolved against the {dig(bg, 'art')}'s sff)")
        # Every width here is an input to where a row wraps in the horizontal Layout, so
        # a background that failed to load reads as the zero that made rows wrap early --
        # which on screen looks like a layout bug rather than a missing file.
        for status in ("upcoming", "current", "completed"):
            row = dig(bg, status)
            if not row:
                c.check(f"{status} Step background resolved", bool(row), True)
                continue
            widths = [dig(row, k) for k in ("body", "tail", "head")]
            c.check(f"{status} Step background has widths, declared or zero",
                    [w for w in widths if not isinstance(w, (int, float))], [])
            if any(w for w in widths):
                # The pre-refactor module read the head's width from the TAIL's
                # animation (old trials.lua:790). Identical widths do not prove the bug
                # is back -- a symmetric pair is a legitimate choice -- so this reports
                # rather than fails.
                if dig(row, "head") and dig(row, "head") == dig(row, "tail"):
                    c._print(f"      ({status}: head and tail are both "
                             f"{dig(row, 'head')} wide -- symmetric, or measured from "
                             f"the wrong sprite?)")
                c.check(f"  {status} tints its background under a palfx",
                        bool(dig(row, "mul")), True)
            else:
                c.skip(f"  {status} tints its background under a palfx",
                       "this Step Status declares no background")
        # In the horizontal Layout the tail and head are part of the width that decides
        # where a row wraps. A body with no tail and no head is a legitimate style; a
        # tail or head with no body is artwork with nothing between it.
        for status in ("upcoming", "current", "completed"):
            row = dig(bg, status)
            if row and not dig(row, "body") and (dig(row, "tail") or dig(row, "head")):
                c.check(f"{status} has a body to go with its head and tail",
                        False, True)

    c._print("\nTrial Textbox (#43)")
    # The Textbox is one element set both Layouts share. What is assertable from a
    # startup dump is what it resolved to; whether it looks right needs a person.
    tb = dig(tree, "textbox")
    c.present("the Textbox resolved", tb)
    if tb and not c.unreadable("the Textbox is its own", tb):
        c.check("the title carries a format string", bool(dig(tb, "titleText")), True)
        # The window is doing two jobs — what the prose clips to and what it wraps
        # inside (src/font.go:995) — so an empty one means prose that runs to the edge
        # of the coordinate space before it turns.
        win = list((dig(tb, "textWindow") or {}).values())
        if win and any(win):
            c.check("the prose has a window to wrap and clip inside", len(win), 4)
        else:
            c.skip("the prose has a window to wrap and clip inside",
                   "no window set, so the prose wraps at the edge of the screen")
        c.check("wrap resolved to a boolean", isinstance(dig(tb, "wrap"), bool), True)
        # Frames per character; 0 is the whole of it at once, which is the default.
        c.check("the typed reveal resolved to a number",
                isinstance(dig(tb, "delay"), (int, float)), True)
        src = dig(tb, "portraitSource")
        c.check("the portrait source is one the module knows",
                src in ("char", "system"), True)
        if src == "char":
            # Nothing resolves until a match names a character, so a count of zero here
            # is only meaningful once one has.
            c._print(f"      (character portraits built so far: "
                     f"{dig(tb, 'portraitsBuilt')})")
        else:
            c.check("a system portrait resolved its sprite", dig(tb, "portrait"), True)

    # The prose on screen belongs to the Trial being shown, which across a Success is the
    # finished one rather than the one the match has moved on to.
    live = dig(tree, "match")
    if live:
        # Both of these are the Trial ON SCREEN. Comparing against match.textbox instead
        # would be comparing two different Trials: f_dumpState runs from completeTrial,
        # inside the lag where the match has advanced and the display has not.
        shown, showing = dig(live, "shownText"), dig(live, "shownTextbox")
        c.check("a Textbox is only drawn for a Trial that carries prose",
                not showing or bool(shown), True)
    else:
        c.skip("a Textbox is only drawn for a Trial that carries prose",
               "no match in this dump")

    c._print("\nTrial Title (#63)")
    # Off unless a screenpack sets trialtitle.<layout>.text.text, so an absent block is
    # a configuration, not a fault. What is assertable is that a Layout which declares
    # one built it, and that the element it built has something to say.
    titles = dig(tree, "trialtitles")
    if titles is None:
        c.skip("the Trial Title resolved for the Layouts that declare one",
               "no Layout declares a Trial Title, which is the shipped default")
    elif not c.unreadable("the Trial Title is its own", titles):
        declared = [k for k in ("vertical", "horizontal") if dig(titles, k)]
        c.check("a declared Trial Title belongs to a Layout the module draws",
                sorted(set(titles) - {"vertical", "horizontal"}), [])
        c.check("the Trial Title resolved for the Layouts that declare one",
                bool(declared), True)
        for layout in declared:
            e = dig(titles, layout)
            if c.unreadable(f"the {layout} Trial Title is its own", e):
                continue
            # The text format is what switches the element on, so an element that
            # resolved without one is one the module built when it should not have.
            c.check(f"the {layout} Trial Title carries a format string",
                    bool(dig(e, "text")), True)
            # Both Layouts configure it apart. Sharing one origin is legal, but a
            # Layout that declares nothing of its own resolves to 0,0 and draws in the
            # top-left corner, which is never what anybody meant.
            pos = list((dig(e, "pos") or {}).values())
            c.check(f"the {layout} Trial Title is positioned",
                    len(pos) == 2 and any(pos), True)
            c.check(f"the {layout} Trial Title resolved a coordinate space",
                    len(list((dig(e, "localcoord") or {}).values())), 2)

    c._print("\nStep Parts and match progress")
    all_parts = [pt for st in dumped_steps for pt in (st.get("parts") or {}).values()
                 if isinstance(pt, dict)]
    c.check("Parts were found to check", bool(all_parts), True)
    # Spelled out rather than read from the module, the same way the Dummy vocabulary
    # above is: an expectation computed the way the code computes it can never disagree.
    flags = ("isthrow", "iscounterhit", "ishelper", "isproj")
    c.check("every Part carries the four Step flags as booleans",
            [pt for pt in all_parts
             if any(not isinstance(pt.get(f), bool) for f in flags)], [])
    c.check("every Part carries a hit count",
            [pt for pt in all_parts if not isinstance(pt.get("hitcount"), (int, float))], [])
    c.check("hit count defaults to 1 where the author wrote none",
            bool([pt for pt in all_parts if pt.get("hitcount") == 1]), True)
    c.check("at least one Part names a state to verify against",
            bool([pt for pt in all_parts if pt.get("stateno")]), True)
    # "|" is how the format spells alternatives, and the dump keeps them that way.
    c.check("a Part accepting several states keeps them all",
            bool([pt for pt in all_parts if "|" in str(pt.get("stateno") or "")]), True)

    # Runtime progress needs a person to start a match, so this half is skipped on a
    # startup dump rather than failed — see the umbrella spec's automation boundary.
    match = dig(tree, "match")
    if match is None:
        c.skip("the match tracks which Step and Part the player is on",
               "no match in this dump")
        c.skip("Advancement resolved", "no match in this dump")
        c.skip("both timers resolved to tick counts", "no match in this dump")
    else:
        step, count = dig(match, "step"), dig(match, "stepCount")
        if not c.unreadable("the match tracks which Step and Part the player is on",
                            step, count):
            c.check("the match tracks which Step and Part the player is on",
                    isinstance(step, (int, float)) and isinstance(count, (int, float))
                    and 1 <= step <= max(1, count), True)
        # The Trial on screen lags the one the match is on across a Success, but only
        # ever by one Trial and never out of range.
        shown, total = dig(match, "shownTrial"), dig(match, "total")
        c.check("the Trial on screen is one of the ones the match holds",
                isinstance(shown, (int, float)) and isinstance(total, (int, float))
                and 1 <= shown <= max(1, total), True)
        c.check("Advancement resolved",
                dig(match, "advancement") in ("autoadvance", "repeat"), True)
        # Both count up from zero, so a freshly resolved match legitimately reads 0 and
        # the value itself says nothing. What is assertable here is that they exist and
        # are counts at all — that they advance is item 4 of the test checklist.
        c.check("both timers resolved to tick counts",
                isinstance(dig(match, "totalTicks"), (int, float))
                and isinstance(dig(match, "trialTicks"), (int, float)), True)

    c._print("\ntrial.showforvarvalpairs gates which Trials are offered (#52)")
    # The gate is parsed at load, so a startup dump carries every Trial's, and the
    # format is flattened to a string here for the reason the Parts' state lists are:
    # a nested table would be a second path the dump elides (#50).
    gates = [str(t.get("showfor") or "") for t in parsed]
    c.check("every Trial carries a gate field, empty or not", len(gates), len(parsed))
    # `12=0|2|4, 20=3` — one pair per variable, comma-separated, "|" between values.
    shape = re.compile(r"^-?\d+=-?\d+(\|-?\d+)*(, -?\d+=-?\d+(\|-?\d+)*)*$")
    malformed = [g for g in gates if g and not shape.match(g)]
    c.check("a gate that is written parses to variable/value pairs", malformed, [])
    c.check("an ungated Trial has an empty gate, not a broken one",
            bool([g for g in gates if g == ""]), True)

    if match is None:
        c.skip("the offered Trials are a subset of the declared ones",
               "no match in this dump")
        c.skip("the Trial Counter's total is what is on offer", "no match in this dump")
    else:
        total, declared = dig(match, "total"), dig(match, "declared")
        offered = str(dig(match, "available") or "")
        # Parsed leniently: anything that is not a number is kept as itself and fails
        # the membership check below, rather than raising out of the whole suite. A
        # checker that crashes on a bad dump reports nothing at all, which is worse
        # than reporting one failure.
        indices = []
        for token in (t.strip() for t in offered.split(",")):
            if token == "":
                continue
            try:
                indices.append(int(token))
            except ValueError:
                indices.append(token)
        c.check("the offered Trials are a subset of the declared ones",
                isinstance(total, (int, float)) and isinstance(declared, (int, float))
                and 0 <= total <= declared, True)
        # `total` is what the Trial Counter renders and what All-Clear is measured
        # against, so the two readings of "how many" have to be the same number.
        c.check("the Trial Counter's total is what is on offer", len(indices), total)
        c.check("every offered Trial is one the character declared",
                [i for i in indices
                 if not (isinstance(i, int) and isinstance(declared, (int, float))
                         and 1 <= i <= declared)], [])
        numeric = [i for i in indices if isinstance(i, int)]
        c.check("the offering is in declared order, with no repeats",
                numeric, sorted(set(numeric)))
        # A dump taken before the round is live legitimately shows the unthinned list:
        # the pairs are evaluated once a round (docs/adr/0003). What must not happen is
        # an offering thinner than the file that nothing evaluated.
        resolved = dig(match, "availableResolved")
        c.check("an offering thinner than the file has actually been evaluated",
                not (total != declared and resolved is False), True)
        # The reading taken at roundState 1 is provisional, because a character can
        # still be choosing the mode this gate reads — cvsryu seeds its groove with
        # `random%7` and settles it as the round goes live. The one at roundState 2 is
        # what stands, and it cannot be the standing one without having happened.
        c.check("a final offering is one that was evaluated",
                not (dig(match, "availableFinal") and resolved is False), True)
        current = dig(match, "current")
        c.check("the Trial the match is on is one of the offered ones",
                total == 0 or (isinstance(current, (int, float)) and 1 <= current <= total),
                True)
        done = dig(match, "completedCount")
        c.check("no more Trials are completed than are offered",
                isinstance(done, (int, float)) and 0 <= done <= max(0, total or 0), True)
        c.check("All-Clear is not claimed with Trials still on offer uncompleted",
                not dig(match, "allclear") or (total or 0) > 0 and done >= total, True)

    c._print("\nPlayer and Dummy life and position are set per-Trial (#49)")
    # Both blocks are resolved at parse time, so a startup dump carries the whole set.
    placements = [t.get("positions") for t in parsed if isinstance(t.get("positions"), dict)]
    lives = [t.get("life") for t in parsed if isinstance(t.get("life"), dict)]
    c.check("every Trial resolved its positions", len(placements), len(parsed))
    c.check("every Trial resolved its life totals", len(lives), len(parsed))

    # Spelled out here rather than read from the module, for the reason the Dummy
    # vocabulary above is: an expectation computed the way the code computes it can
    # never disagree with it.
    corners = {"left-corner": "left", "right-corner": "right"}
    gaps = {"close": 10, "medium": 130, "far": 260}

    def placement_faults(pos):
        """Ways one resolved placement disagrees with the words behind it."""
        authored = pos.get("authored")
        if not isinstance(authored, dict):
            return ["authored"]
        out = []
        if pos.get("corner") not in ("", "left", "right"):
            out.append("corner")
        if pos.get("cornered") not in ("", "player", "dummy"):
            out.append("cornered")
        # A corner and the character in it are one fact, so neither is legible alone.
        if (pos.get("corner") == "") != (pos.get("cornered") == ""):
            out.append("corner/cornered")
        if pos.get("gap") not in gaps.values():
            out.append("gap")
        if not isinstance(pos.get("spaced"), bool):
            out.append("spaced")
        # The Dummy's key is read first, so hers wins a Trial that names two corners.
        wanted = ""
        for side in ("dummy", "player"):
            if authored.get(side, "") in corners and wanted == "":
                wanted = side
        if wanted != pos.get("cornered", ""):
            out.append("cornered from the word")
        elif wanted != "" and corners[authored[wanted]] != pos.get("corner"):
            out.append("corner from the word")
        # A distance is the gap, from whichever key named it; unnamed means untouched.
        named = [authored.get(s, "") for s in ("dummy", "player")
                 if authored.get(s, "") in gaps]
        if bool(named) != bool(pos.get("spaced")):
            out.append("spaced from the word")
        elif named and gaps[named[0]] != pos.get("gap"):
            out.append("gap from the word")
        return out

    c.check("each placement matches the words it was resolved from",
            [p for p in placements if placement_faults(p)], [])

    def life_faults(life):
        authored = life.get("authored")
        if not isinstance(authored, dict):
            return ["authored"]
        out = []
        for side in ("player", "dummy"):
            v = life.get(side)
            # 0 is the map's own word for lifeMax, and is what an unwritten or
            # unusable total falls back to.
            if not isinstance(v, (int, float)) or v < 0 or v != int(v):
                out.append(side)
                continue
            word = authored.get(side, "")
            try:
                wanted = int(word)
            except (TypeError, ValueError):
                wanted = 0
            if wanted < 1:
                wanted = 0
            if v != wanted:
                out.append(side + " from the word")
        return out

    c.check("each life total matches the word it was resolved from",
            [l for l in lives if life_faults(l)], [])

    # As with the Dummy, parsing is only half of it: the maps are written during the
    # match, and the module rewrites this artifact the moment it does.
    setup = dig(tree, "setupWritten")
    if setup is None:
        c.skip("the pair was placed for the Trial the match is on",
               "no match in this dump reached roundstate 1")
        c.skip("the positions written are stage coordinates",
               "no match in this dump reached roundstate 1")
    else:
        c.check("the pair was placed for the Trial the match is on",
                dig(setup, "trial"), dig(tree, "match", "current"))
        coords = ("playerx", "playery", "dummyx", "dummyy", "camerax",
                  "playerlife", "dummylife")
        c.check("the positions written are stage coordinates",
                [k for k in coords
                 if not isinstance(dig(setup, k), (int, float))], [])

    # The mid-Trial reposition: its key combination, the fade around it, and the words
    # reminding the player it exists.
    repos = dig(tree, "reposition")
    if repos is None:
        c.check("the reposition config resolved", "<missing>", "a reposition block")
    else:
        # The engine's own inputTime vocabulary, spelled out here rather than read from
        # the module for the reason the Dummy vocabulary is.
        input_keys = set("B D F U L R a b c x y z s d w m".split())
        c.check("whether the player can reposition is a flag",
                isinstance(dig(repos, "enabled"), bool), True)
        keys = str(dig(repos, "keys") or "")
        named = [k for k in keys.split("+") if k != ""]
        c.check("every key in the combination is one the engine answers for",
                [k for k in named if k not in input_keys], [])
        c.check("  ... and the count agrees with the combination",
                dig(repos, "keyCount"), len(named))
        # A feature switched on with no usable key is a feature that cannot fire, and
        # is worth catching here rather than on a controller.
        c.check("a reposition that is on has a combination to trigger it",
                not dig(repos, "enabled") or len(named) > 0, True)
        c.check("both fade times are tick counts",
                [k for k in ("fadeout", "fadein")
                 if not isinstance(dig(repos, k), (int, float))
                 or dig(repos, k) < 0], [])
        c.check("the reminder resolved to a string",
                isinstance(dig(repos, "reminder"), str), True)
        # An animation on a fade REPLACES its colour wipe rather than joining it — the
        # engine takes the overlay's duration from colorFadeTime, which is 0 whenever an
        # anim is present (src/rect.go:47). The module holds the sprite for the
        # configured time so the fade lasts that long either way, which is what keeps
        # `time` above the whole gate on whether a fade runs. So these flags say which
        # of the two a fade draws, not whether it happens.
        c.check("both fade animation flags are flags",
                [k for k in ("fadeoutAnim", "fadeinAnim")
                 if not isinstance(dig(repos, k), bool)], [])
        for end in ("fadeout", "fadein"):
            if not dig(repos, end + "Anim"):
                c.skip(f"  {end} has no animation layer",
                       f"set {end}.spr in your screenpack to exercise this")
                continue
            # A fade is the one element with no pos, so the rule the others resolve
            # their coordinate space by — who positioned it — answers "nobody" and
            # falls back to this module's 320x240. A screenpack's sprite drawn there
            # covers four screens and hangs off the corner. The space has to follow
            # whoever supplied the ARTWORK, so a screenpack-supplied sprite must not
            # be sitting in the module's own space.
            lc = dig(tree, "elements", end, "localcoord")
            if c.unreadable(f"  {end} animation localcoord", lc):
                continue
            c.check(f"  {end} animation resolved a coordinate space",
                    isinstance(lc, dict) and len(lc) == 2, True)
            if str(dig(tree, "configSource", f"trials_mode.{end}.spr") or "") \
                    .startswith("screenpack"):
                c.check(f"  ... a screenpack's sprite is not in the module's 320x240",
                        [lc.get(1), lc.get(2)] != [320, 240], True)

    c._print("\nThe presentation layer — background, overlay, select-screen palfx (#44)")
    # The mode's own backdrop. Absent is the shipped state and is not a failure: the
    # module declares no [TrialsBgDef] of its own, so a stock install draws no backdrop
    # and this asserts only that the two answers stay consistent with each other.
    bg = dig(tree, "background")
    if bg is None:
        c.check("the background block reached the dump", bg, "<missing>")
    else:
        declared = dig(bg, "declared")
        c.check("whether a [TrialsBgDef] was declared is a flag",
                isinstance(declared, bool), True)
        c.check("a background that loaded was one that was declared",
                not dig(bg, "loaded") or declared is True, True)
        if declared:
            c.check("a declared background names the file it was parsed out of",
                    isinstance(dig(bg, "def"), str) and dig(bg, "def") != "", True)
            # An spr the section asked for and searchFile could not find falls back to
            # the screenpack's own sff, which draws the wrong artwork or none — and looks
            # exactly like a section that named no spr at all. The pair is what tells
            # them apart.
            c.check("an spr the section named was found on disk",
                    dig(bg, "spr") == "" or dig(bg, "sprResolved") != "", True)
            # Loading is the part that can fail on a malformed section, and the module
            # degrades to no backdrop rather than to no mode. Worth stating either way.
            if not dig(bg, "loaded"):
                c.check("a declared background parsed", dig(bg, "loaded"), True)
        else:
            c.skip("no [TrialsBgDef] in any layer",
                   "the module ships none; define one in your screenpack to exercise this")

    # The select-screen effect. Always configured — the module ships a default, which is
    # what makes the feature work in a stock install — so this asserts the shape rather
    # than the presence, plus the one thing that would silently disable it.
    palfx = dig(tree, "selectPalFX")
    if palfx is None:
        c.check("the select-screen palfx resolved", palfx, "<missing>")
    else:
        for key, count in (("add", 3), ("mul", 3), ("sinadd", 4)):
            value = dig(palfx, key)
            c.check(f"selscreenpalfx.{key} resolved to {count} components",
                    isinstance(value, str) and len(value.split(",")) == count, True)
        c.check("selscreenpalfx.color is a number",
                isinstance(dig(palfx, "color"), (int, float)), True)
        c.check("selscreenpalfx.invertall is a number",
                isinstance(dig(palfx, "invertall"), (int, float)), True)
        # mul 256,256,256 with color 256 is the engine's identity, which is the effect
        # doing nothing at all. Legal — it is how a screenpack turns the feature off —
        # but it is also what a mistyped key silently degrades to, so it is named.
        neutral = (dig(palfx, "mul") == "256,256,256"
                   and dig(palfx, "add") == "0,0,0"
                   and dig(palfx, "color") == 256
                   and dig(palfx, "invertall") == 0)
        if neutral:
            c.skip("the effect is the engine's identity",
                   "configured to do nothing — characters without Trials will not be dimmed")
        else:
            c.check("the effect changes something", neutral, False)
        # A startup dump is written before any select screen has run, so nothing is
        # applied yet; the count is here for a dump taken after one.
        c.check("the applied count is a count",
                isinstance(dig(palfx, "applied"), (int, float)), True)

    # The panel behind the Step block, for the Layout in use. nil is the shipped state:
    # the module draws artwork behind the Steps instead, and switching the panel on
    # under it would darken a background authored at the alpha it wanted.
    overlay = dig(tree, "steps", "bg", "overlay")
    if overlay is None:
        c.skip("no Step block overlay configured",
               "set trialsteps.<layout>.bg.overlay.visible = true to exercise this")
    else:
        for key in ("window", "windowWithTextbox", "activeWindow"):
            rect = dig(overlay, key)
            if c.unreadable(f"overlay {key} is a rect", rect):
                continue
            c.check(f"overlay {key} is a rect of four",
                    isinstance(rect, dict) and len(rect) == 4, True)
            # A rect IS the panel's geometry, so an empty one is an invisible panel —
            # and rectSetWindow refuses an all-zero rect outright rather than storing
            # it (src/rect.go:331), which would leave the other variant's geometry in
            # place on a switch. Both are silent on screen; neither is silent here.
            if isinstance(rect, dict) and len(rect) == 4:
                x1, y1, x2, y2 = (rect.get(i) for i in (1, 2, 3, 4))
                c.check(f"  ... and encloses some area",
                        x2 > x1 and y2 > y1, True)
        # The active window is whichever variant the Trial on screen selected, so it has
        # to be one of the two and not a third thing.
        active = dig(overlay, "activeWindow")
        c.check("the overlay is clipping to one of its two variants",
                active in (dig(overlay, "window"), dig(overlay, "windowWithTextbox")), True)
        c.check("the overlay resolved a colour and an alpha",
                isinstance(dig(overlay, "col"), str)
                and len(str(dig(overlay, "alpha")).split(",")) == 2, True)

    c._print("\nNative trials pause menu (#40)")
    pause = dig(tree, "pauseMenu")
    if pause is None:
        c.check("the pause menu block reached the dump", pause, "<missing>")
    else:
        # The section reaching the motif is the whole of the registration: the engine
        # turns any ^(?i).*pause.*menu$ section into a pause menu and resolves the one to
        # open from the game mode's name. Nothing in Lua registers it.
        c.check("[Trials Pause Menu] reached the motif", dig(pause, "registered"), True)
        items = dig(pause, "items")
        named = [i for i in str(items or "").split("|") if i]
        c.check("  ... with items in it", bool(named), True)
        # Spelled out rather than read back from +system.def: an expectation computed
        # the way the code computes it can never disagree with it.
        for item in ("trialslist", "trialadvancement", "trialresetonsuccess",
                     "trialslayout", "trialstextboxes"):
            c.check(f"  ... including {item}", item in named, True)
        c.check("  ... and its Back, so the trials list is never empty",
                "trialslist_back" in named, True)
        # Dummy behaviour comes from the Trial Definition and nowhere else
        # (docs/adr/0002), and the engine initialises those items only under
        # gameMode('training') — one in a Trials match is a crash waiting on a cursor.
        c.check("no dummy items, which would both invalidate Trials and crash",
                [i for i in named
                 if i.split("_")[-1] in ("dummycontrol", "ailevel", "dummymode",
                                         "guardmode", "fallrecovery", "distance",
                                         "buttonjam")], [])
        c.check("the legacy [Trials Info] fold is reported either way",
                isinstance(dig(pause, "legacy"), bool), True)
        if dig(pause, "legacy") is True:
            c._print("      (this screenpack still defines [Trials Info] — rename it)")

    if match is None:
        c.skip("the trials list is filled in from the selected character",
               "no match in this dump")
        c.skip("the Player Preferences the menu writes resolved",
               "no match in this dump")
    else:
        # The list is the one part of the menu the module builds rather than the engine,
        # and the tail it keeps is what a character shipping no Trials sits on.
        entries = [e for e in str(dig(pause, "list") or "").split("|") if e]
        total = dig(match, "total")
        trials_named = [e for e in entries if not e.startswith("<")]
        tail = [e for e in entries if e.startswith("<")]
        c.check("the trials list is filled in from the selected character",
                len(trials_named), total if isinstance(total, (int, float)) else 0)
        c.check("  ... keeping the items the section declared under it", bool(tail), True)
        c.check("the Player Preferences the menu writes resolved",
                (dig(match, "advancement") in ("autoadvance", "repeat")
                 and isinstance(dig(match, "resetOnSuccess"), bool)
                 and dig(match, "layout") in ("vertical", "horizontal")
                 and dig(match, "textboxes") in ("show", "hide")), True)
        # Reset on Success latches the same request the mid-Trial combination does, and
        # writeSetup clears it. A request still standing with no Trial change pending and
        # nothing in the way is one nothing is going to act on.
        # A Success either asks for the pair to be placed or asks for the Trial to be
        # taken on where they stand. Never both, and never one while the preference says
        # the other.
        c.check("a Success asks for a placement or for the Trial in place, not both",
                not (dig(match, "reposRequest") and dig(match, "adoptPending")), True)
        c.check("  ... and only asks to take it on in place with the preference off",
                not dig(match, "adoptPending") or dig(match, "resetOnSuccess") is False,
                True)
        setup = dig(tree, "setupWritten")
        if setup is None:
            c.skip("a setup that was not a placement says so", "no setup in this dump")
        else:
            c.check("a setup that was not a placement says so",
                    isinstance(dig(setup, "placed"), bool), True)
        c.check("a standing reposition request has something that will act on it",
                not dig(match, "reposRequest") or dig(match, "banner") is not None
                or dig(tree, "reposition", "enabled") is not False, True)

    c._print("\nModule directory hygiene")
    # The engine walks external/mods recursively and require()s every *.lua it finds,
    # so any second .lua here is executed as a module at boot. A match launcher named
    # fight.lua panicked the engine before the title screen exactly this way.
    module_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "..", "external", "mods", "trials")
    if os.path.isdir(module_dir):
        luas = sorted(f for f in os.listdir(module_dir) if f.endswith(".lua"))
        c.check("only trials.lua is auto-required by the engine", luas, ["trials.lua"])
    else:
        c.check("module directory found", module_dir, "<missing>")

    c._print("\nExtension points")
    c.check("launchFight hook registered", dig(tree, "hooks", "launchFight"), True)
    c.check("loop#trials hook registered", dig(tree, "hooks", "loop"), True)
    c.check("main.f_addChar.files hook registered", dig(tree, "hooks", "addCharFiles"), True)
    c.check("start.f_selectScreen hook registered", dig(tree, "hooks", "selectScreen"), True)
    c.check("menu.menu.loop hook registered", dig(tree, "hooks", "pauseMenuLoop"), True)
    c.check(
        "trials.zss resolves on disk",
        dig(tree, "zssPath"),
        "external/mods/trials/trials.zss",
    )

    return c


def main():
    if "--self-test" in sys.argv[1:]:
        return run_self_tests()
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        with open(path) as handle:
            tree = parse_dump(handle.read())
    except FileNotFoundError:
        print(f"No dump at {path}.")
        print("Run the build with Debug.DumpLuaTables = true in save/config.ini.")
        return 2

    c = run_checks(tree, dump_path=path)
    total = c.passed + c.failed
    print(f"\n  {c.passed}/{total} passed"
          + (f", {c.failed} failed" if c.failed else "")
          + (f", {c.skipped} skipped" if c.skipped else ""))
    return 1 if c.failed else 0


if __name__ == "__main__":
    sys.exit(main())
