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


def run_checks(tree, quiet=False):
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
    opts = dig(tree, "ini", "Options", "Trials")
    c.check("Options.Trials.Layout", dig(opts, "Layout") if opts else None, "vertical")
    c.check("Options.Trials.Advancement", dig(opts, "Advancement") if opts else None, "autoadvance")
    c.check("Options.Trials.ResetOnSuccess is bool", dig(opts, "ResetOnSuccess") if opts else None, False)
    c.check("Options.Trials.TotalTimer is bool", dig(opts, "TotalTimer") if opts else None, True)
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

    c._print("\nStep text, vertical layout (#37)")
    block = dig(tree, "steps")
    c.present("Step block resolved at load", block)
    c.check("vertical layout", dig(block, "layout") if block else None, "vertical")
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
        c.check("Advancement resolved",
                dig(match, "advancement") in ("autoadvance", "repeat"), True)
        # Both count up from zero, so a freshly resolved match legitimately reads 0 and
        # the value itself says nothing. What is assertable here is that they exist and
        # are counts at all — that they advance is item 4 of the test checklist.
        c.check("both timers resolved to tick counts",
                isinstance(dig(match, "totalTicks"), (int, float))
                and isinstance(dig(match, "trialTicks"), (int, float)), True)

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

    c = run_checks(tree)
    total = c.passed + c.failed
    print(f"\n  {c.passed}/{total} passed"
          + (f", {c.failed} failed" if c.failed else "")
          + (f", {c.skipped} skipped" if c.skipped else ""))
    return 1 if c.failed else 0


if __name__ == "__main__":
    sys.exit(main())
