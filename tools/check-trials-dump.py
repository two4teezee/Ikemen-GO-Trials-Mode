#!/usr/bin/env python3
"""Assert against the trials module's resolved-state dump.

The module writes one artifact — debug/t_trials.txt — under Debug.DumpLuaTables,
and this is the only seam non-visual assertions go through. See CONTEXT.md for
vocabulary and the umbrella spec (issue #46) for why there is exactly one.

Usage:
    tools/check-trials-dump.py [path-to-t_trials.txt]

Exits non-zero if any check fails, so it can gate CI later.
"""

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
    c.present("config.ini parsed", dig(tree, "config"))
    c.present("system.def defaults parsed", dig(tree, "system"))

    print("\nconfig.ini — dotted keys nest, types coerce")
    opts = dig(tree, "config", "Options", "Trials")
    c.check("Options.Trials.Layout", dig(opts, "Layout") if opts else None, "vertical")
    c.check("Options.Trials.Advancement", dig(opts, "Advancement") if opts else None, "autoadvance")
    c.check("Options.Trials.ResetOnSuccess is bool", dig(opts, "ResetOnSuccess") if opts else None, False)
    c.check("Options.Trials.TotalTimer is bool", dig(opts, "TotalTimer") if opts else None, True)
    c.check(
        "Common.States points at the module's zss",
        dig(tree, "config", "Common", "States"),
        "external/mods/trials/trials.zss",
    )

    print("\nsystem.def — trials sections survive the engine's closed motif struct")
    c.check(
        "[Trials Mode] menu.itemname.trials",
        dig(tree, "system", "trials_mode", "menu", "itemname", "trials"),
        "TRIALS",
    )
    c.present("[Trials Mode] nodata.text", dig(tree, "system", "trials_mode", "nodata", "text"))
    c.present("authored key order preserved (__order)", dig(tree, "system", "trials_mode", "__order"))

    print("\nZSS injection (#35)")
    c.check("launchFight hook registered", dig(tree, "hooks", "launchFight"), True)
    c.check(
        "start.launchFight.selected hook registered",
        dig(tree, "hooks", "launchFightSelected"),
        True,
    )
    c.check(
        "trials.zss resolves on disk",
        dig(tree, "zssPath"),
        "external/mods/trials/trials.zss",
    )

    print("\nResolved values")
    c.check("main-menu label resolves", dig(tree, "menuItemname"), "TRIALS")
    c.check("module is enabled", dig(tree, "enabled"), True)

    total = c.passed + c.failed
    print(f"\n  {c.passed}/{total} passed" + (f", {c.failed} failed" if c.failed else ""))
    return 1 if c.failed else 0


if __name__ == "__main__":
    sys.exit(main())
