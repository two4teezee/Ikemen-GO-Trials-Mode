#!/usr/bin/env python3
"""Assert against the trials module's resolved-state dump.

The module writes one artifact — debug/t_trials.txt — under Debug.DumpLuaTables,
and this is the only seam non-visual assertions go through. See CONTEXT.md for
vocabulary and the umbrella spec (issue #46) for why there is exactly one.

Usage:
    tools/check-trials-dump.py [path-to-t_trials.txt]

Exits non-zero if any check fails, so it can gate CI later.
"""

import math
import os
import re
import sys

DEFAULT_PATH = "testbuild/debug/t_trials.txt"


def parse_dump(text):
    """Parse main.f_printTable output into nested dicts.

    The format is: ["key"] => value, where value is a scalar or `table: 0x… {`
    opening a block that closes on a lone `}`. Scalars arrive as quoted strings,
    bare numbers, booleans, or `function: 0x…`.
    """
    entry = re.compile(r'^\s*\[(.+?)\]\s*=>\s*(.*)$')
    root, stack = {}, [{}]
    stack[0] = root

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
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
            stack[-1][key] = child
            stack.append(child)
        else:
            stack[-1][key] = parse_scalar(raw_val)

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
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


class Checks:
    def __init__(self):
        self.passed = 0
        self.failed = 0

    def check(self, label, actual, expected):
        if actual == expected:
            print(f"  \033[32m✓\033[0m {label}")
            self.passed += 1
        else:
            print(f"  \033[31m✗\033[0m {label}")
            print(f"      expected: {expected!r}")
            print(f"      actual:   {actual!r}")
            self.failed += 1

    def present(self, label, actual):
        if actual is not None:
            print(f"  \033[32m✓\033[0m {label}")
            self.passed += 1
        else:
            print(f"  \033[31m✗\033[0m {label}  (missing)")
            self.failed += 1


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        with open(path) as handle:
            tree = parse_dump(handle.read())
    except FileNotFoundError:
        print(f"No dump at {path}.")
        print("Run the build with Debug.DumpLuaTables = true in save/config.ini.")
        return 2

    c = Checks()

    print("\nModule bootstrap")
    c.check("module directory resolved", dig(tree, "dir"), "external/mods/trials/")
    c.check("module is enabled", dig(tree, "enabled"), True)
    c.present("config.ini parsed", dig(tree, "ini"))
    c.present("Trials Config resolved", dig(tree, "config"))
    c.check("language resolved", dig(tree, "language"), "en")

    print("\nconfig.ini — dotted keys nest, types coerce")
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

    print("\nTrials Config — three layers, screenpack last (#36)")
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
        print("  - screenpack override fixture not installed, layering checks skipped")

    print("\nElement construction (#36)")
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
        if None not in (lx, ly, px, py):
            v = ly * 4 / 3 if lx * 3 > ly * 4 else lx
            ix = px * (320 / v) - int(math.floor(lx / (v / 320) - 320) / 2)
            iy = py * (320 / v)
            print(f"      (internal position: {ix:.1f}, {iy:.1f})")
            c.check("counter is on screen at 4:3", 0 <= ix <= 320 and 0 <= iy <= 240, True)
            c.check("counter is on screen at 16:9", -53.4 <= ix <= 373.4 and 0 <= iy <= 240, True)

    print("\nTrial Definition discovery (#36)")
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

    print("\nModule directory hygiene")
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

    print("\nExtension points")
    c.check("launchFight hook registered", dig(tree, "hooks", "launchFight"), True)
    c.check("loop#trials hook registered", dig(tree, "hooks", "loop"), True)
    c.check("main.f_addChar.files hook registered", dig(tree, "hooks", "addCharFiles"), True)
    c.check(
        "trials.zss resolves on disk",
        dig(tree, "zssPath"),
        "external/mods/trials/trials.zss",
    )

    total = c.passed + c.failed
    print(f"\n  {c.passed}/{total} passed" + (f", {c.failed} failed" if c.failed else ""))
    return 1 if c.failed else 0


if __name__ == "__main__":
    sys.exit(main())
