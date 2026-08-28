# Trials Config is read via `loadIni`, not from the engine's `motif` table

## Context

Before the late-2025 engine refactor, `external/script/motif.lua` parsed `system.def`
in Lua and handed back a table containing *every* section it found, including ones
the engine knew nothing about. Trials Mode relied on that: it declared
`[Trials Mode]`, `[Trials Info]` and `[TrialsBgDef]` in the screenpack, and read them
back as `motif.trials_mode` and friends.

The engine now parses the motif in Go (`src/motif.go`) into a fixed `Motif` struct,
and `motif = loadMotif()` builds the Lua table from that struct by reflection. The
struct has no catch-all field. Unknown sections survive on the Go side in
`m.IniFile`, but **never reach Lua**. `motif.trials_mode` is `nil` and always will be.

## Decision

The module reads its own configuration with `loadIni`, in three layers merged in
this order:

1. `external/mods/trials/system.def` — the module's trials-specific defaults.
2. `external/mods/trials/config.ini` — Player Preferences, written back with `saveIni`.
3. `gameOption('Config.Motif')` — the screenpack's `system.def`, which wins.

Engine-native keys live in a *separate* file, `external/mods/trials/+system.def`,
which the engine discovers and concatenates into the motif parse automatically
(`motif.go:1570`). So `[Select Info] title.trials.text`, `[Trials Pause Menu]` and
`[Hiscore Info] ranking.trials` land in `motif` for free.

**The two files must stay separate.** The engine parses `+system.def` against its
motif struct and logs a warning for every key it cannot assign:

```
Warning: Failed to assign key [trials mode.nodata.text]: field 'trials_mode' not found
```

Trials-specific keys placed in `+system.def` therefore produce one warning line per
key on every boot — for the full Trials Config, hundreds. This was found by running
the build, not by reading the source, and it is why the `ikemen-engine/modules` `ratio`
module names its defaults file `system.def` with no `+` prefix. That detail reads as
incidental and is not.

## Considered options

**Patch the engine** to add a `TrialsMode` field to the `Motif` struct. Rejected:
it would require every user to run a custom build, which defeats the copy-a-folder
install model, and it puts one mode's config in the engine's core schema.

**Piggyback on the engine's generic map sections.** `ResultsScreen`
(`^(?i).+results.*screen$`) and `PauseMenu` (`^(?i).*pause.*menu$`) accept
arbitrarily-named sections and get full element construction for free. We use this
for the pause menu, where it fits exactly. We do *not* use it for Success/All-Clear:
`ResultsScreenProperties` looks like an ideal fit, but the results screen has **no Lua
entry point** — it is driven from Go at match end, and Success fires mid-match.

## Consequences

Existing screenpacks need no changes. Authors were always documented to write dotted
keys (`trialsteps.vertical.bg.anim`); the flat underscored form only ever existed
inside old `motif.lua`, which did `param:gsub('[%. ]', '_')`. `loadIni` splits dotted
keys into nested tables, so existing sections parse into the shape we want.

Two merge conventions are in play and they are opposites: the engine's `+system.def`
concatenation is **first-instance-wins** with the screenpack concatenated first, while
`main.f_tableMerge` is **last-wins**. Argument order has to be deliberate.

One file is no longer read this way: a Trial Definition is parsed inside the module,
because go-ini merges the same-named sections a character with modes depends on. See
docs/adr/0004, which is scoped to that file and does not revisit anything here.

A screenpack that defines trials sections in its *own* `system.def` will still trigger
these warnings, because the engine parses the screenpack file regardless. That is
outside a pure-Lua module's control and should be documented rather than worked around.
