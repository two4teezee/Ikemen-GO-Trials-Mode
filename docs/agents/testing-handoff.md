# Testing handoff

Trials Mode cannot be fully verified without a person watching the screen. Rendering,
positioning, fades, glyph alignment, menu navigation and anything requiring controller
input are all human-verified. The maintainer runs those; the agent runs everything
else.

**When an implementation reaches something the maintainer can test, the agent relabels
the ticket `ready-for-human-testing` and produces a test checklist.** Delivering code
without both is an incomplete handoff — the label says whose turn it is, the checklist
says what to do.

## Handing off

Once the slice is implemented, reviewed, fixed and committed:

1. Swap the label — remove whatever it currently carries, add `ready-for-human-testing`:
   `gh issue edit <n> --remove-label "<current>" --add-label "ready-for-human-testing"`
2. Post the checklist as an issue comment, and repeat it in the response.
3. Wait for the maintainer's report. On confirmation, close the ticket; if their testing
   found something, fix it and swap the label back to `ready-for-agent` while it is
   being worked.

## When not to hand off

Only hand off when there is genuinely something to test. Skip the label *and* the
checklist for docs-only changes, tooling, refactors with no visible effect, and anything
the agent already verified end to end — asking the maintainer to confirm something they
cannot observe wastes the one testing resource this project has.

Hand off if *any* part of the change needs a person at the screen, even when other parts
of the same slice were verified headlessly. Most slices are mixed.

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
survives the session.

**Every item is a `- [ ]` checkbox.** The maintainer ticks them in place as they go, so
a half-finished run still records exactly how far it got. Prose the maintainer cannot
tick is not a checklist item; put it in the surrounding text.

Title the comment `## Test checklist — #<n> (commit \`<sha>\`)`, then:

**### Setup** — the exact commands in a bash block, including anything non-obvious
about this machine or fixtures that had to be installed by hand.

**### Watch for — in order** — grouped under numbered bold headings, ordered by how
early each appears so a failure stops the run rather than wasting the rest of it. Mark a
group with ⚠️ when it is new or the likeliest thing to break, and add a short italic note
saying why. Under each heading, one `- [ ]` per observable result, stated concretely
enough to judge without reading the code — "TRIALS appears above OPTIONS", not "menu
entry works". Where a failure explains itself, follow the group with a line saying what
that failure means.

**### Known-suspect** — anything the agent could not verify, and specifically anything
changed after the last successful run. This is the part that earns the checklist: these
items are where a failure is most likely, and the maintainer should look at them first.

**### Already verified** — stated briefly, so time is not spent re-checking it.

**### If something fails** — what to capture. Usually the console output and
`testbuild/debug/t_trials.txt`, since those are what the agent can act on afterwards.

**### Not in scope** — what this slice deliberately does not do, so a missing feature is
not reported as a bug.

Prior art to copy: the checklist on #35.

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
