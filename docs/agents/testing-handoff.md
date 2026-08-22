# Testing handoff

Trials Mode cannot be fully verified without a person watching the screen. Rendering,
positioning, fades, glyph alignment, menu navigation and anything requiring controller
input are all human-verified. The maintainer runs those; the agent runs everything
else.

**Whenever an implementation is ready to test, the agent produces a test checklist
before saying it is done.** Delivering code without one is an incomplete handoff.

## The split

| Agent verifies | Maintainer verifies |
| --- | --- |
| Module loads with no Lua error or motif warning | Anything drawn on screen |
| Resolved state, via `debug/t_trials.txt` and `tools/check-trials-dump.py` | Menu position and navigation |
| Parsing: Trials, Steps, Parts, language resolution | Step advancement from real inputs |
| Config layering — which layer won each key | Dummy behaviour |
| Anything assertable at startup with no interaction | Timing, fades, layout at 4:3 and 16:9 |

The boundary is interaction, not importance. Module load is startup-time and needs no
input, so it automates. Everything from character select onward needs a controller.

## Checklist format

One checklist per slice, posted in the response *and* as a comment on the issue so it
survives the session. Structure:

**Setup** — the exact commands, including anything non-obvious about this machine.

**Watch for** — ordered by how early it appears, so a failure stops the run rather
than wasting the rest of it. Each item states the expected result concretely enough to
be judged without reading the code. "TRIALS appears above OPTIONS" — not "menu entry
works".

**Known-suspect** — anything the agent could not verify, and specifically anything
changed after the last successful run. This is the part that earns the checklist:
these items are where a failure is most likely, and the maintainer should look at them
first.

**Already verified** — stated briefly, so time is not spent re-checking it.

**If it fails** — what to capture. Usually the console output and
`testbuild/debug/t_trials.txt`, since those are what the agent can act on afterwards.

## Rules

- Never mark an item verified that only the maintainer can see. Say "needs a
  foreground run".
- Order by dependency: if step 2 cannot be judged when step 1 fails, say so.
- Keep it to what changed. A regression sweep of the whole mode every slice is not
  worth the maintainer's time; call out regression risk explicitly when it exists.
- If something was verified and later changed, it moves back to known-suspect.

## Running the build

`tools/run-testbuild.sh` launches `testbuild/` and tees output to
`testbuild/save/logs/run.log`.

Two environment notes:

- The shipped macOS binary links `/opt/homebrew/opt/sdl2-compat/`. If only `sdl2` is
  installed the script substitutes it via `DYLD_FALLBACK_LIBRARY_PATH`; the two share
  a compatibility version. `brew install sdl2-compat` removes the need.
- The engine blocks in `gfx.BeginFrame` when launched from a background session, so
  the agent frequently cannot run it at all. Assume the maintainer is the only
  reliable path to a running build.

`Debug.DumpLuaTables = 1` in `testbuild/save/config.ini` is required for the dump seam
and therefore for `tools/check-trials-dump.py`.
