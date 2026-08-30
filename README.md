# Ikemen GO Trials Mode v1.0

> Requires an Ikemen GO nightly newer than the late-2025 motif refactor.
> Verified against engine revision `fb3750f4` (v1.00 RC3).

> For older engine builds, use [Trials Mode v0.99.5](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/releases).

> Module developed by two4teezee

---

Trials Mode is an external module that adds a combo-trial game mode to Ikemen GO: a player picks a character and works through a list of authored input sequences, each one verified against the engine's own state as it is performed.

The module is universal — it ships no character content of its own. Characters opt in by supplying a **Trial Definition**, and screenpacks opt in to styling the mode by defining **Trials Config** sections.

Sample Trial Definitions for a number of characters live in [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files). The [wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki) covers the same ground as this file at greater length.

## Installation

Copy the `external/mods/trials/` folder into your Ikemen GO installation, so that you end up with `<ikemen>/external/mods/trials/`.

That is the whole installation. 
**There is nothing to paste into a screenpack's `system.def`, and nothing to add to `save/config.ini`.** 
The engine walks`external/mods` recursively and loads what it finds; the module merges its own engine-native defaults into the motif through `+system.def`, and injects its state file into the match's common states for the duration of a Trials match only.

To give a character trials, write a Trial Definition and point the character's def file at it — see [Creating a Character's Trial Definition](#creating-a-characters-trial-definition).

## What Ships in the Module

| File | What it is |
| --- | --- |
| `trials.lua` | The module core, contains all logic. |
| `+system.def` | Engine-native motif defaults — only sections the engine's own motif struct understands: the select-screen title and `[Trials Pause Menu]`. |
| `system.def` | Trials Mode UI configuration — every trials-specific setting. This is where you will configure Trials Mode to look a certain way. |
| `config.ini` | The module's own configuration: the state file to inject, where to read defaults from, and the `[Options]` block holding Player Preferences. |
| `trials.zss` | The state file that keeps a Trials match a practice session — no KO, life and power recovery, no round or fight announcements, dummy behaviour, and the repositioning of the pair. |
| `trials.sff` | The module's sprite file. You can use this file as a template for your screenpack. |
| `glyphs.sff` | (Optional) Trials Mode can use a standalone glyphs file. If not specified or provided, Trials Mode will use the screenpack's glyphs. |
| `fight.luascript` | The match launcher for Trials matches, so that `Config.TrainingStage` is honoured. The extension is deliberate — a file named `.lua` here would be `require`d at boot and launch a match with no context. |

## Upgrading from Versions Prior to 1.0

One breaking change: `[Trials Info]` is now `[Trials Pause Menu]`. 
If your screenpack defines `[Trials Info]`, rename the section — the body is unchanged. 
The engine turns any m`system.def` section matching `*pause*menu*` into a pause menu and resolves which one to open from the game mode's name, so the old name cannot be registered as one. The module still reads `[Trials Info]` and folds it into the pause menu, warning once on the console; that alias goes away in a later release.

- **Trial Definitions are unchanged.** Every existing `trials.def` still runs, key for key — the format did not change. 
  The section below documents it, with new notes on [hit count](#hit-count) and on projectile Steps.
- **Screenpack Trials Config sections still resolve.** 
  Authors were always documented to write dotted keys (`trialsteps.vertical.bg.anim`), and the new parser splits dotted keys into nested tables. 
  Section names are matched case- and whitespace-insensitively, so `[Trials Mode]` resolves the same as it always did.
- **`trialtitle.<layout>.*` is read again**, for both Layouts, key for key. 
  One change: the pre-refactor module declared `text.text` and then drew the bare Trial name, ignoring the format. 
  It is applied now — `%i` is the Trial's number and `%s` its name — so a screenpack carrying `"Trial: %s"` reads `Trial: <name>` where it used to read `<name>`. 
  Write `"%s"` alone for the old wording. 
  The three layers also draw in the order `bg`, words, `front`, where the pre-refactor module drew the words first and both animations over them.

### Retired Keys

| Retired | Now |
| --- | --- |
| `trialsresetonsuccess`, `trialslayout` | Player Preferences in `config.ini` — a value the player owns cannot also be authored. |
| `textbox.visible` | The `Trials.Textboxes` Player Preference. |
| `textbox.overlay.*` | `trialsteps.<layout>.bg.overlay.*` — the overlay belongs to the Step block, because it is what has to reshape when a Textbox appears. |
| `success.bg.*`, `success.front.*`, and the same on `allclear` | Text, sound and display time only. |
| `trialcounter.notrialsdata.text` | `nodata.text`. Still read under the old spelling. |
| `textbox.text.drawspeed` | `textbox.text.delay`. Still read under the old spelling. |

**Expect boot warnings if your screenpack defines trials sections.** The engine parses
your `system.def` against its own motif struct regardless of what the module does, and
logs a line per trials key it cannot assign:

```
Warning: Failed to assign key [trials mode.<key>]: field 'trials_mode' not found as struct or map field
```

This is cosmetic. The module reads those sections itself, and your overrides still apply.
It is outside a pure-Lua module's control.

## Creating a Character's Trial Definition

Trials are authored per character, in a file in the character's own folder. 
This file is conventionally called `trials.def`, but the name is yours to choose. 
A character can have as many Trials as you like, presented in the order the file declares them.

You should consult [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files) for sample trials definition files.
Here is an excerpt from the sample trial file provided for KFM:

```
[TrialDef, KFM's First Trial]

trial.dummymode = stand
trial.guardmode = none
trial.dummybuttonjam = none
; trial.dummylife =
; trial.playerlife =
; trial.dummypos =
; trial.playerpos =
; trial.showforvarvalpairs =
; trial.textbox = This is KFM's first trial. Good luck!

trialstep.1.text = Strong Kung Fu Palm
trialstep.1.glyphs = _QDF^Y
trialstep.1.stateno = 1010
; trialstep.1.animno =
; trialstep.1.projid =
; trialstep.1.hitcount =
; trialstep.1.isthrow =
; trialstep.1.iscounterhit =
; trialstep.1.ishelper =
; trialstep.1.isproj =
; trialstep.1.validforvarvalpairs =
; trialstep.1.validfortickcount =
```

Each `[TrialDef, <title>]` section is one Trial. `[TrialDef]` is mandatory; the title
after the comma is optional.

Trial parameters are split into two categories - parameters that inform general attributes of that trial, and per-step definitions.

### General Trial Parameters

All of these parameters are optionally defined.
If undefined, the default value is selected.

| Key | Values | Default |
| --- | --- | --- |
| `trial.dummymode` | `stand`, `crouch`, `jump`, `wjump` | `stand` |
| `trial.guardmode` | `none`, `auto` | `none` |
| `trial.dummybuttonjam` | `none`, `a`, `b`, `c`, `x`, `y`, `z`, `start`, `d`, `w` | `none` |
| `trial.dummylife` | Whole number of life points | The character's maximum |
| `trial.playerlife` | Whole number of life points | The character's maximum |
| `trial.dummypos` | `left-corner`, `right-corner`, `far`, `medium`, `close` | The stage's start positions |
| `trial.playerpos` | The same five | The stage's start positions |
| `trial.showforvarvalpairs` | Comma-separated var/value pairs | Always shown |
| `trial.textbox` | String, multilingual | No Textbox |

#### About `trial.dummypos` and `trial.playerpos`
The two position keys are read separately, and the five words split into two kinds:

- `left-corner` and `right-corner` are **places**, and belong to the character whose key named them. Only one character can stand in a corner — a Trial naming two keeps the dummy's and warns about the other.
- `close`, `medium` and `far` are **distances**, describing the gap between the two characters rather than either one's position. 
  Either key may name one and it means the same thing. 
  Two different distances keep the dummy's and warn about the other.

So `trial.dummypos = left-corner` puts the dummy in the left corner with the player a medium gap away, and adding `trial.playerpos = far` widens that gap without moving anyone
out of the corner. 
A distance on its own, with no corner named, starts the pair that far apart around centre stage.

Positions and life totals are applied when the Trial starts, and re-applied when the player moves to another Trial or the round restarts. 
A Trial that names none of them gets the stage's own start positions and full life, never the previous Trial's. Mid-Trial, the player can put both characters back where the Trial wants them with the `trialresetkeys` combination.

#### About `trial.showforvarvalpairs`

**`trial.showforvarvalpairs`** takes comma-separated integers in pairs, and the Trial is offered only when *all* of them hold. 
It is how a Trial is scoped to one groove or mode.
The pairs are for the character, never for a helper, and a variable can name several acceptable values with `|` — `trial.showforvarvalpairs = 12, 0|2|4` tests `var(12)` against 0, 2 and 4.
The cvsryu [sample trials definition file](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files) provides a great example of how `trial.showforvarvalparis` can be used to maximum effect.

### Trial Step Parameters

Steps are numbered: `trialstep.X.<key>`, where X starts at 1.

| Key | Values | Default |
| --- | --- | --- |
| `trialstep.X.text` | String, multilingual | No text |
| `trialstep.X.glyphs` | Glyph notation, same syntax as [movelists](https://github.com/ikemen-engine/Ikemen-GO/wiki/Miscellaneous-info#movelists) | No glyphs |
| `trialstep.X.stateno` | Integer — mandatory, except on a projectile Step | — |
| `trialstep.X.animno` | Integer | Not checked |
| `trialstep.X.projid` | Integer — mandatory on a projectile Step, meaningless elsewhere | Not checked |
| `trialstep.X.hitcount` | Integer | `1` |
| `trialstep.X.isthrow` | `true`, `false` | `false` |
| `trialstep.X.iscounterhit` | `true`, `false` | `false` |
| `trialstep.X.ishelper` | `true`, `false` | `false` |
| `trialstep.X.isproj` | `true`, `false` | `false` |
| `trialstep.X.validforvarvalpairs` | Comma-separated var/value pairs | Not checked |
| `trialstep.X.validfortickcount` | Integer | Not set |

`stateno` and `animno` are the state and animation of the character or of a
helper — never of a projectile. 
A Step declaring no glyphs draws as text alone, with no gap reserved for them, and a token the glyph set has no sprite for is skipped rather than drawn.

### Where the glyphs come from

By default Trials Mode uses the screenpack's glyphs.
The module can also draw them out of its own file. 
Drop a `glyphs.sff` into the module folder beside `trials.sff` and the module uses that artwork instead; remove it and the screenpack's glyphs come back. 
Nothing else changes — the glyph vocabulary is still the
screenpack's, so `_QDF`, `^P` and the rest keep meaning what they always meant. 
Only the artwork those tokens resolve to swaps.
A `glyphs.sff` follows the same sprite numbering wherever it came from, so an ordinary one drops straight in. 
Any token whose sprite your file happens to lack is skipped and reported once at load, the same as a token the screenpack has no sprite for.

`validforvarvalpairs` is the sister of `showforvarvalpairs`, applied to a Step rather
than a Trial: useful when a Step should only clear while the character is in a custom
combo state. It holds for the whole Step, including every Part of a condensed one.

`validfortickcount` grants a grace window of that many ticks after the previous Part was
satisfied. Inside it, the Step is only dropped if the combo counter moves on without the
Step registering — which is what a link with a gap in it needs in order not to be judged
as a drop while waiting for the next hit.

### Hit count

`hitcount` is how many hits a Step waits for before the Trial moves on. It defaults to
`1`, and it is checked against the combo counter as the Step's conditions hold — so a
multi-hit move that should be confirmed in full names its real count:

```
trialstep.5.stateno = 3000
trialstep.5.hitcount = 3
```

**`hitcount = 0` does not mean "any number of hits".** It means *no hit is required*: the
Step passes the moment its conditions are met, whether or not anything connects, and it
can never be dropped by the combo ending. That is what a taunt, a stance change or any
other non-hitting move needs:

```
trialstep.1.text = Kung Fu Taunt
trialstep.1.stateno = 195
trialstep.1.hitcount = 0
```

Setting `hitcount = 0` also disables `iscounterhit` on that Step, since there is no hit
to be a counter.

**Hit count and helpers.** A helper's hits are credited to the character who owns it, so
they land in the same combo counter as everything else — `hitcount` on a helper Step
therefore counts exactly the way it does anywhere else. A helper move that hits six times
and should be confirmed in full is `hitcount = 6`:

```
trialstep.2.text = Pink Attack
trialstep.2.glyphs = _B^H
trialstep.2.stateno = 502
trialstep.2.ishelper = true
trialstep.2.hitcount = 6
```

The one thing to know is what `stateno` means on such a Step: it is the **helper's own
state at the moment its hit lands**, read off the hit rather than off the player. So the
count runs from the first hit the helper lands while in that state. If a helper Trial
passes earlier than expected, check that the helper is not passing through the named
state twice, or entering it a frame before the hit you meant.

### Projectile Steps

**A projectile is not identified by a state.** The usual fireball is a helper running a
`Projectile` controller, and the engine credits the hit to whoever *owns* the projectile
— the root character, not the helper, unless the helper declared `ownprojectile`. The
helper's state number never reaches the hit, so a projectile Step written as
`stateno = 7000` cannot pass. Neither can its animation: a projectile with the usual
`projremove` is already gone by the time the module is asked about the hit, and
characters routinely draw every fireball they own with the same `projanim`.

Name its **ProjID** instead, matched against `gethitvar(projid)` on the dummy. The ProjID
is the one thing that survives the hit and tells the moves apart, and characters already
give theirs distinct values because their own CNS counts them with `NumProjID`. Read it
out of the `Projectile` controller in the character's CNS.

Where a move fires more than one projectile, or picks its ProjID with an expression, list
every value it can take with `|` — `trialstep.1.projid = 3005|3006` for a ProjID written
as `3005+(var(5)=2)`.

A Step naming a `projid` is treated as a projectile Step whether or not `isproj` is also
spelled.

### Alternatives, and condensing several Steps into one

Two different syntaxes, and it is worth keeping them apart.

**`|` is *or*.** It offers alternatives for one value, on `stateno`, `animno`, `projid`
and the var/value pair keys. `trialstep.1.stateno = 1000|1010` passes on either state.

**A comma condenses several checks into a single Step.** Each comma-separated position is
one *Part*, checked in sequence, and the Step only clears once every Part has been
satisfied in order. It keeps a multi-state move on one line of the readout instead of
spreading it over several:

```
trialstep.1.text = Standing Light to Strong Punch Chain
trialstep.1.glyphs = ^X_-^Y
trialstep.1.stateno = 200, 210
trialstep.1.hitcount = 1, 1
```

Condensing works on `stateno`, `animno`, `projid`, `hitcount`, `isthrow`, `iscounterhit`,
`ishelper`, `isproj` and `validfortickcount`. **If one of those keys on a Step is written
with commas, every one of them on that Step must be.** `validforvarvalpairs` is the
exception — it belongs to the whole Step, and applies to every Part of it.

## Editing the character's def file

Finally, tell Ikemen where to find the Trial Definition. In the character's own def file
(`kfmZ.def` for kfmZ), under `[Files]`:

```
[Files]
trials = trials.def        ;Ikemen feature: Trials mode data
```

The path is resolved relative to the character's folder.

## Pause menu options

Pausing during a Trials match opens the trials pause menu. It is an engine-native pause
menu: the module ships a `[Trials Pause Menu]` section and the engine registers it, which
is why no screenpack edit is needed to get one. A screenpack customises it by defining
the same section in its own `system.def`, and anything it leaves out is topped up from
the screenpack's `[Pause Menu]` — so a menu that only wants to reorder the items writes
only itemnames.

- **Trials**: the Trials the selected character ships. Picking one jumps to it, starts its
  progress over and places the pair at its authored positions.
- **Advancement**: Auto-Advance moves to the next Trial on Success; Repeat plays the same
  one again, so it can be drilled.
- **Reset on Success**: what a finished Trial does to where the two characters stand. On,
  completing one puts the pair back at the next Trial's authored positions, behind a fade.
  Off, the run carries straight on from wherever the combo ended — the next Trial begins
  in place, with no move and no fade between the two. It governs every Success:
  advancing, repeating the same Trial, and the All-Clear that finishes the set.
  It does **not** govern a reposition the player asks for. The mid-Trial key combination,
  and picking a Trial out of the **Trials** list above, place the pair either way.
- **Layout**: Vertical or Horizontal. Switching re-lays out the Trial already on screen.
- **Textboxes**: whether a Trial's Textbox is shown. Hiding it also gives the Steps their
  full-width window back, on the Trial already running.

Plus the engine's own Button Config, Command List, Character Change and Exit.

The four settings below **Trials** are [Player Preferences](#authored-config-versus-player-preferences):
the module writes them back to `external/mods/trials/config.ini` the moment they change,
so they survive a restart.

There is deliberately **no dummy submenu**. Dummy behaviour comes from the Trial
Definition and nowhere else, so a Trial plays the same way for everyone; a screenpack that
adds one will also hit a crash, because the engine initialises those items only under
`gameMode('training')`.
