# Ikemen GO Trials Mode v1.0
> Compatible with Ikemen GO 1.00 RC3 and newer.

> Note: for older Ikemen GO Builds, check releases tab for a compatible release of Trials Mode.

> Module developed by two4teezee
---
This external module offers a universal solution for Trials Mode. 
This markdown file is best viewed in Github or your favorite markdown file viewer. 
For greater detail on how to create trials definitions, or the customization options supported, please consult this readme, or [the wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki). 
You can find sample trials files for some of my favorite characters in [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).

## Installation
1. Extract archive content into your Ikemen directory - you should see new content in "./external/mods/trials/"
2. (Optional but probably highly desired) Modify your screenpack's `system.def` to show Trials Mode in the main menu where you would like it to. 
Check the module's `+system.def` file for instructions. 
4. (Optional) Add sprites to your screenpack's `system.sff`, or alternatively, to the module's `trials.sff`, as required.
5. (Optional) Add sounds to your screenpack's `system.snd`, or alternatively, to a module-specific `trials.snd` placed beside `trials.lua`, as required.
6. Create new trials for your character(s). 
As a starting point, you can use the templates found in the trials mode readme to create a `trials.def` file and edit `kfm_zss.def`, both in `"./chars/kfm_zss"`. 
You can follow the instructions in the readme to create trials for any character you would like. 
I also often create new trials files for my favorite characters and share them [here](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).
7. Share your trials definition files with others!

## Package Contents and Optional Files
Everything below ships inside `external/mods/trials/`.

| File | Role | Contents |
|---|---|---|
| `trials.lua` | The module itself — the only file the engine loads directly. Implements the game mode: parses each character's `trials.def`, checks trial steps against match state, draws the Trial Select/pause menus, and reads/writes `config.ini` and `save/trials.json`. | Lua source - you likely won't change any of this code. |
| `system.def` | The mode's own UI configuration, loaded by `trials.lua` (not by the screenpack). Everything under `[Trials Mode]`: title text, layout (vertical/horizontal), Trial Select banner and rows, glyph/anim wiring, textbox styling. | This file is how you configure Trials Mode's appearance. |
| `+system.def` | The hand-off into the *screenpack's* menus. Provides the main-menu entry (`[Title Info]`, `[Select Info]`) and the `[Trials Pause Menu]` section the engine turns into the in-match pause menu. | This file contains Menu item names, value labels (Auto-Advance/Repeat, Vertical/Horizontal, difficulty labels, etc.), and instructions for merging into the screenpack's own `system.def`. |
| `trials.zss` | Engine-side state and helper functions the mode depends on (camera framing, dummy/player repositioning, button-jam handling). Loaded automatically by `trials.lua`; not part of the screenpack. | Global states - you won't edit this file. |
| `trials.sff` | The mode's bundled sprite sheet, auto-detected on load. Supplies default art (backgrounds, banners, clear markers) so the mode looks right even if the screenpack's own `system.sff` doesn't carry matching sprites. | Sprite data - you can drop your sprites for the Trials Mode UI in this file, or in your `system.sff`. |
| `config.ini` | Per-install storage for player preferences (Advancement, Layout, Reset on Success, Textboxes, timers). Rewritten by the module the moment a player changes one in the pause menu, so hand edits/comments here don't persist. | Contains options key/value pairs - you likely will not edit this file. |
| `README.md` | This file — a reference for you to follow. | Installation steps, the `trials.def` authoring reference (trial and trial-step parameters), UI/menu customization guide, Speedrun and Progress behavior. |
| `LICENSE` | The module's license terms. | GNU LGPL v2.1 text. |

Not shipped, but referenced by the README: a sample `trials.def` (and matching character `.def` edit) for `kfm_zss`, and additional community trials files at the [Sample Trials Definition Files repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files). `trials.snd` and `trials.air` are optional files a creator may drop in beside `trials.lua`; the module ships neither.

## General info
The Trials Mode provides new screenpack features and engine features so that creators can create trials for their character creations, and fully customize the way the trials are presented. 
The Trials Mode ships with several options for display of trials data inside the game mode, a variety of pause menu options to navigate the trials for each character, and the ability to apply palfx to character portraits in the Select Screen to easily convey which characters have valid Trials definition files.

## system.def and UI Customization
The Trials Mode external module supports full customization UI through the included `system.def`, with background sprites and animations pulled directly from your screenpack's `system.sff`, or from a separately bundled module-specific `trials.sff`, if so desired. 
The module ships with a `trials.sff` and it is automatically detected on load when included in the module folder.

Sounds work the same way. Every `snd` parameter in the module's `system.def` — `success.snd` and `allclear.snd` — is read from a `trials.snd` placed beside `trials.lua`, and from your screenpack's `system.snd` when there is none.
The module ships no `trials.snd`, so out of the box those sounds come from the screenpack; drop one in and it is detected on load, exactly as `trials.sff` is.
It is the whole file that switches, not one sound at a time: once a `trials.snd` is present, a `group,number` missing from it plays nothing rather than falling back to `system.snd`.

The pause menu's own sounds are not affected either way. `cursor.move`, `cursor.done`, `enter` and `cancel` are read from the screenpack's `[Trials Pause Menu]` (or `[Pause Menu]`) section and always play out of `system.snd`, so the trials list answers like every other menu in the screenpack.

The universal trials mode supports **vertical** trials readouts, and **horizontal** readouts as seen in KOF XIV, among other games. 
The `system.def` included with this module is configured to support both layout types "out of the box" with the `ikemen1` screenpack found [here](https://github.com/ikemen-engine/Ikemen_GO-Elecbyte-Screenpack). 
Below you'll find a brief summary of screenpack features supported by trials mode. 
For more detail on how you can configure every aspect of the UI for trials mode, please consult the included `system.def` file.
The [Trials Mode wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki) also goes into great depth on all supported features.

## Creating a Character's Trials Definition File

Trials data is created on a per-character basis. To specify new trials for a character, you'll want to create a new file in the character's folder to hold the trials data. For the purposes of this tutorial, I name this file `trials.def`, but you can call it whatever you want. As mentioned before, each character gets its own `trials.def`. You can specify as many trials as you want, in any order you want.

### Editing the Character's def File

First you'll want to modify the character's definition file so that Ikemen knows to read the trials data for that character. 
In the character's definition file (i.e. `kfmZ.def` for kfmZ), under `[Files]`, add the line `trials = trials.def`.

```
[Files]
trials = trials.def        ;Ikemen feature: Trials mode data
```

### Creating the first trial in your `trials.def` file
Declares the trial's section header, e.g. `[TrialDef, KFM's First Trial]`. `TrialDef` is mandatory; the trial title after the comma is optional.

### Trial Definition Parameters 
The options below are defined once per trial. 

| Parameter | Required | Format | Default | Description |
|---|---|---|---|---|
| `trial.difficulty` | Optional | `Beginner`, `Intermediate`, `Advanced`, `Expert` (case-insensitive) | — (uncategorized) | Puts the trial behind that filter in the Trial Select view, which the player cycles with left and right, and counts towards that filter's cleared tally. Trials that don't declare one are collected under "Other". If no trial in the file declares a difficulty, there is nothing to filter by and the list stays flat and in def order, exactly as before. An unrecognised value is ignored, with a warning printed to the console. |
| `trial.dummymode` | Optional | `stand`, `crouch`, `jump`, `wjump` | `stand` | Sets the dummy's stance/mode for the trial. |
| `trial.guardmode` | Optional | `none`, `auto` | `none` | Sets whether the dummy blocks automatically (`auto`) or not (`none`). |
| `trial.dummybuttonjam` | Optional | `none`, `a`, `b`, `c`, `x`, `y`, `z`, `start`, `d`, `w` | `none` | Sets a button for the dummy to hold during the trial. |
| `trial.dummylife` | Optional | integer | — | Sets the dummy's life total. |
| `trial.playerlife` | Optional | integer | — | Sets the player's life total. Useful for trials that involve desperation moves or require a specific life state. |
| `trial.dummypos` | Optional | `left-corner`, `right-corner`, `far`, `medium`, `close` | center stage | Sets the dummy's position on the stage. If enabled, the player can reset positioning according to this information by hitting the d and w keys simultaneously. |
| `trial.playerpos` | Optional | `left-corner`, `right-corner`, `far`, `medium`, `close` | center stage | Sets the player's position on the stage. If enabled, the player can reset positioning according to this information by hitting the d and w keys simultaneously. |
| `trial.showvarvalpairs` | Optional | comma-separated integers, in pairs (0..n pairs) | — | Determines whether a trial should be displayed based on the specified variable and value pair(s). Useful if a trial should only be displayed when the character has a specific variable/value pair set, such as being in a specific groove or mode. If specified, the trial only displays if all variable-value pairs return true. These pairs are for the character only (not for helpers). Variables can test multiple values, separated by `\|` (e.g. `trial.showforvarvalpairs = 12, 0\|2\|4` tests var(12) for values 0, 2, and 4). |
| `trial.textbox` | Optional | multilingual (string) | — | Displays specified text in a box specified in the textbox settings in `system.def` under `[Trials Mode]`. Supports specification as `trial.textbox`, or `trial.textbox.en`, `trial.textbox.es`, etc. for multilingual support. Defaults to `trial.textbox.en` (or `trial.textbox`) if the selected language cannot be matched. |

### Trial Step Definition Parameters
These parameters are used to defined each trial step, where 'X' is the trial step number starting at '1'.

| Parameter | Required | Format | Default | Description |
|---|---|---|---|---|
| `trialstep.X.text` | Optional | multilingual (string) | — | Text for trial step (only displayed in vertical trials layout). Supports specification as `trialstep.X.text`, or `trialstep.X.text.en`, `trialstep.X.text.es`, etc. for multilingual support. Defaults to `trialstep.X.text.en` (or `trialstep.X.text`) if the selected language cannot be matched. |
| `trialstep.X.glyphs` | Optional | string (see [Glyph documentation](https://github.com/ikemen-engine/Ikemen-GO/wiki/Miscellaneous-info#movelists)) | — | Same syntax as movelist glyphs. Glyphs are displayed in vertical and horizontal trials layouts. |
| `trialstep.X.stateno` | Mandatory* | integer or comma-separated integers, or integers separated by vertical separator | — | State to be checked to pass trial, whether it's the main character or a helper. On a projectile step it means the state the projectile was FIRED FROM, which the module records when the projectile spawns — note that for a projectile fired by way of a helper this is the root's move state (e.g. 1000 for a Hadoken thrown by a helper out of state 1000), not the helper's own state number. *Optional, and safely omitted, on a step whose `projid` already identifies the projectile on its own. |
| `trialstep.X.animno` | Optional | integer or comma-separated integers, or integers separated by vertical separator | — | Identifies animno to be checked to pass trial. Useful in certain cases. |
| `trialstep.X.hitcount` | Optional | integer or comma-separated integers | `1` | Specifies a hit count criteria to meet before proceeding to the next trial step. Useful for multi-hit moves, or for moves that don't hit (e.g. taunts). |
| `trialstep.X.isthrow` | Optional | `true`/`false`, or comma-separated true/false | `false` | Identifies whether the trial step is a throw. |
| `trialstep.X.iscounterhit` | Optional | `true`/`false`, or comma-separated true/false | `false` | Identifies whether the trial step should be a counter hit. Typically does not work with helpers or projectiles. |
| `trialstep.X.ishelper` | Optional | `true`/`false`, or comma-separated true/false | `false` | Identifies whether the trial step is a hit from a helper. |
| `trialstep.X.isproj` | Optional | `true`/`false`, or comma-separated true/false | `false` | Identifies whether the trial step is a hit from a projectile. The step passes only when the projectile actually connects with the dummy, not when it is fired. Not needed alongside a `projid` (which already identifies the step as a projectile) — only required when the projectile is identified by `stateno` instead. Setting both is harmless. |
| `trialstep.X.projid` | Optional | integer or comma-separated integers, or integers separated by vertical separator | — | The ID given to the projectile by the character's `Projectile` sctrl (authors spell it `ProjID`, `projid`, or plain `id`). The step passes on the frame a projectile with that ID hits the dummy.<br>• Use `\|` where a character fires more than one projectile for the same move, or the ID is an expression (e.g. `projid = 3005\|3006` for `ID = 3005+(var(5)=2)`).<br>• A `projid` alone is enough to mark a step as a projectile step; `isproj` isn't needed alongside one.<br>• Add `stateno` too when a character reuses one ID across several moves (e.g. CvS Sagat's ProjID 1000 across states 1000/1050/1070 — `projid = 1000` with `stateno = 1070` isolates the heavy Tiger Shot).<br>• If the sctrl declares no ID, it defaults to 0, so `projid = 0` matches every ID-less projectile — pair with `stateno` to narrow it down.<br>• A step with `isproj = true` and no `projid` matches on `stateno` alone and still requires a connect. `projid` has no effect when `hitcount = 0`. |
| `trialstep.X.validforvarvalpairs` | Optional | comma-separated integers, in pairs (0..n pairs) | — | Sister to `showforvarvalpairs`. Optionally checks a trial step against var-value pairs — useful when forcing completion under specific conditions (e.g. a custom combo state). Pairs are valid for the entire trial step, regardless of condensed terminology. |
| `trialstep.X.validfortickcount` | Optional | integer, or comma-separated integers | nil | Pauses the trials checking logic until the next hit is registered for the specified tickcount. |

### Sample Trial Definition File

A sample `trials.def` for kfm_zss is provided below. The trials are presented to the player in the order in which they are listed in `trials.def`. Detailed information for each configurable parameter can be found in this template.

```
[TrialDef, KFM's First Trial]

trial.difficulty = Beginner
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

;---------------------------------------------

[TrialDef, Kung Fu Throw]
trialstep.1.text = Kung Fu Throw
trialstep.1.glyphs = [_B/_F]_+^Y
trialstep.1.stateno = 810
trialstep.1.isthrow = true

;---------------------------------------------

[TrialDef, Kung Fu Taunt]
trial.textbox.en = This is an English textbox!
trial.textbox.es = Este es un cuadro de texto en español.

trialstep.1.text.en = Kung Fu Taunt
trialstep.1.text.es = Kung Fu Pulla
trialstep.1.glyphs = ^S
trialstep.1.stateno = 195
trialstep.1.hitcount = 0

;---------------------------------------------

[TrialDef, Standing Punch Chain]
trialstep.1.text = Standing Light Punch
trialstep.1.glyphs = ^X
trialstep.1.stateno = 200

trialstep.2.text = Standing Strong Punch
trialstep.2.glyphs = ^Y
trialstep.2.stateno = 210

;---------------------------------------------

[TrialDef, Condensed Standing Punch Chain]
; The next two trials show examples of condensed trial steps which check a series of parameters sequentially by using comma separated values as part of a single trial step. In other words, think of being able to specify multiple trial steps in a single step.
; For instance, this trial is the same as the previous, but the two steps are condensed into one.
; The next trial uses a combination of condensed steps and normal steps to provide a concise trial.
; Condensed steps can be very practical for multi-state moves where the trial step should only clear if all of the states are met, without having to create multiple trial steps.

trialstep.1.text = Standing Light to Strong Punch Chain		
trialstep.1.glyphs = ^X_-^Y			
trialstep.1.stateno = 200, 210		
trialstep.1.hitcount = 1, 1

; When desired, you can collapse multiple steps into a single one but using comma separated values in the following parameters:
; stateno, animno, projid, hitcount, isthrow, iscounterhit, ishelper, isproj
; If one parameter on the trial step is defined using comma separated values, all parameters on that trial step must be defined similarly.

;---------------------------------------------

[TrialDef, KFM Kung Fu Palm]
; In this trial, we use the "or" operand, specified by using the | character, to let the user specify multiple different stateno or animno for which the trialstep or microstep is valid.

trialstep.1.text = Kung Fu Palm
trialstep.1.glyphs = _QDF^P
trialstep.1.stateno = 1000|1010

;---------------------------------------------

[TrialDef, Kung Fu Juggle Combo]
; In this trial, the position for the dummy on the stage is set. The player can reset positioning by hitting d + w.
trial.dummypos = right-corner 

trialstep.1.text = Kung Fu Knee and Extra Kick
trialstep.1.glyphs = _F_F_+^K_.^K
trialstep.1.stateno = 1060, 1055

trialstep.2.text = Crouching Jab
trialstep.2.glyphs = _D_+^X
trialstep.2.stateno = 400

trialstep.3.text = Weak Kung Fu Palm
trialstep.3.glyphs = _QCF_+^X
trialstep.3.stateno = 1000

;---------------------------------------------

[TrialDef, Kung Fu Fist Four Piece]
trialstep.1.text = Jumping Strong Punch
trialstep.1.glyphs = _AIR^Y
trialstep.1.stateno = 610

trialstep.2.text = Standing Light Punch
trialstep.2.glyphs = ^X
trialstep.2.stateno = 200

trialstep.3.text = Standing Strong Punch
trialstep.3.glyphs = ^Y
trialstep.3.stateno = 210

trialstep.4.text = Strong Kung Fu Palm
trialstep.4.glyphs = _QDF^Y
trialstep.4.stateno = 1010

;---------------------------------------------

[TrialDef, Kung Fu Super Cancel]
trialstep.1.text = Jumping Strong Kick
trialstep.1.glyphs = _AIR^B
trialstep.1.stateno = 640

trialstep.2.text = Standing Light Kick
trialstep.2.glyphs = ^A
trialstep.2.stateno = 230

trialstep.3.text = Standing Strong Kick
trialstep.3.glyphs = ^B
trialstep.3.stateno = 240

trialstep.4.text = Fast Kung Fu Zankou
trialstep.4.glyphs = _QDF^A^B
trialstep.4.stateno = 1420

trialstep.5.text = Triple Kung Fu Palm
trialstep.5.glyphs = _QDF_QDF^P
trialstep.5.stateno = 3000
trialstep.5.hitcount = 3
```

## Pause Menu Options

Pausing a Trials match opens the mode's own pause menu. It is engine-native: the
`[Trials Pause Menu]` section shipped in `+system.def` is the whole of the registration, because
the engine turns any section matching `*pause*menu` into a pause menu and opens the one named
after the current game mode. A screenpack customizes it by declaring the same section in its own
`system.def` — there is nothing to edit in `trials.lua`.

- **Trials List**: the character's trials, one per line, with the current one marked. Selecting
  one jumps to it, starts its progress over and recenters the pair.
- **Advancement**: Auto-Advance or Repeat — whether clearing a trial moves to the next one or
  replays it, so a single trial can be drilled.
- **Reset on Success**: recenters the players when a trial is cleared. If dummy and/or player
  positions are specified for the trial, they are moved accordingly.
- **Layout**: Vertical or Horizontal, switchable mid-match.
- **Textboxes**: shows or hides a trial's explanatory text, for trials that carry any.
- **Speedrun**: On or Off. See below.
- **Progress**: erases recorded progress, for this character or for everyone. See below.

Speedrun apart, the last four are **player preferences**: `system.def` provides the screenpack's
authored default, the player's choice is saved to `external/mods/trials/config.ini` the moment it
changes, and that file wins on the next launch. Note that the module rewrites `config.ini`
whenever a preference changes, so comments added to it will be lost.

Next Trial and Previous Trial remain supported for screenpacks that would rather list them than
use the Trials List, but neither is part of the default menu.

## Trial Select

Loading into a Trials match opens the Trial Select view: every one of the character's trials, one
per line, with whether it has been cleared and the best time on the right. Picking one starts it.
The cursor opens on the first trial the player has yet to clear, so re-entering a character you
have been working through resumes where you left off; confirming without moving starts that one.

Up and down move between trials; **left and right cycle a difficulty filter**. The filters are
**All**, then each difficulty that character actually uses, then **Other** for trials whose def
declares none. Filters with nothing in them are skipped, so a character with only Beginner and
Expert trials cycles All → Beginner → Expert.

A banner pinned above the list shows the filters. It does not scroll with the rows.
`trialsmenu.headerdisplay` picks its shape:

| Value | Banner |
|---|---|
| `default` | One entry, naming the filter on show, with `< >` arrows when there are others to reach: `< Beginner >   1/2` |
| `sidebyside` | Every filter on one line, `trialsmenu.header.spacing` apart, the one on show wearing the `trialsmenu.header.active` elements. No arrows — the other filters are already visible |

`trialsmenu.header.active.*` styles the filter on show and **inherits from the plain header
elements**, so a `system.def` that only ever set `header.text` still describes both and `default`
looks exactly as it did. `sidebyside` needs a highlight declared before it reads as one.

`trialsmenu.header.value.text` formats the tally (`"%s"`); set it to `""` to leave counts off,
which side by side often wants once six of them share a line.

If no trial in the file declares a difficulty there is only one filter, so the banner shows `All`
and its count, and the list is flat and in def order, unchanged from previous versions.

This is the same view the pause menu's **Trials List** opens, so the two can never disagree.

`trialslistdisplay` in `[Trials Mode]` decides when, if ever, the player is asked:

| Value | When the menu appears |
|---|---|
| `select` | Between stage select and the fight loading, on the select screen's own background |
| `start` (default) | Once the match is up, over the frozen pair |
| `off` | Never — the match starts on the first trial |

The pause menu's **Trials List** is unaffected by all three, so the menu is always reachable.

`select` runs before any match exists, so it reads the character's parsed trials rather than match
state, and carries the choice into the fight by trial *name* — `trialsBuilder` drops trials whose
`showforvarvalpairs` don't match, so parsed positions need not survive into the match. Backing out
of it settles for whichever trial the cursor opened on, so there is always an answer.

That name is how a pick crosses into the match, but it can't make a pick *correct*: out there P1
doesn't exist yet, so no variable can be read and the list can't be filtered. A character with even
one `showforvarvalpairs` trial is therefore never asked early — under `select` it gets the `start`
menu instead, once the match is up and the groove or mode is settled. Everyone else keeps the
pre-fight menu. Should a pick be gated away anyway, the match-load menu opens rather than starting
some other trial.

### Configuring it

The menu is drawn by the module, so its appearance is configured in `[Trials Mode]` alongside
everything else, under `trialsmenu.*` — not in the screenpack's `[Trials Pause Menu]` section. See
the shipped `system.def` for the annotated list; in outline:

| Key | What it sets |
|---|---|
| `trialsmenu.pos`, `.spacing`, `.visibleitems` | Where rows start, how far apart, how many at once |
| `trialsmenu.layerno` | The layer every element in the block sits on unless it names its own. Defaults to `2`, above the in-match HUD; keep `glyphs.<layout>.layerno` below it |
| `trialsmenu.bg.*`, `.front.*` | Backdrop behind the rows and art over them |
| `trialsmenu.overlay.*` | The rect dimming the match behind the menu. `alpha` is source,destination as everywhere else in the engine, so `0,128` halves what is behind it |
| `trialsmenu.title.*` | The heading over the list |
| `trialsmenu.headerdisplay` | `default` or `sidebyside` |
| `trialsmenu.header.offset`, `.header.spacing` | Where the pinned filter banner sits, and the gap between entries when side by side |
| `trialsmenu.header.text.*`, `.header.value.*`, `.header.bg.*` | A filter's label, its cleared tally, and its background |
| `trialsmenu.header.active.*` | The same three, for the filter on show. Inherits from the above |
| `trialsmenu.item.text.*`, `.item.active.text.*`, `.item.selected.text.*` | A trial's name: normal, under the cursor, and the trial in play |
| `trialsmenu.item.bg.*`, `.item.active.bg.*`, `.cursor.*` | Per-row background and the cursor drawn on the active row |
| `trialsmenu.item.active.overlay.*` | The highlight bar under the row the cursor is on. Same `visible`/`window`/`col`/`alpha`/`layerno` as `trialsmenu.overlay`, except its `window` is `x1,y1,x2,y2` from that row's origin rather than the screen, so it follows the cursor. A window with no area, or `visible = false`, leaves it off |
| `trialsmenu.status.*` | The cleared / not-cleared marker (see below) |
| `trialsmenu.besttime.*` | The best clear time beside each row. Set its `text` to `""` to leave times off |
| `trialsmenu.arrow.up.*`, `.arrow.down.*` | Shown when the list runs past `visibleitems`. Art or a label, the same way as the clear marker |

#### Styling one difficulty differently

Any of the row and banner elements can be respecified for a single difficulty, by putting the
category name straight after `item` or `header`:

```
trialsmenu.item.<category>.text.*            a trial of that difficulty, at rest
trialsmenu.item.<category>.active.text.*     ...under the cursor
trialsmenu.item.<category>.selected.text.*   ...when it is the trial in play
trialsmenu.item.<category>.bg.*              its row background
trialsmenu.item.<category>.active.bg.*       ...under the cursor
trialsmenu.item.<category>.active.overlay.*  its highlight bar, under the cursor
trialsmenu.header.<category>.text.*          that filter's banner entry
trialsmenu.header.<category>.active.*        ...while it is the filter on show
trialsmenu.header.<category>.value.*         its cleared tally
trialsmenu.header.<category>.bg.*            its background
```

Row categories are `beginner`, `intermediate`, `advanced`, `expert` and `other` — `other` being the
trials whose def declares no `trial.difficulty`. The banner adds `all`, the unfiltered view.

**Declare only what differs.** Anything a category leaves out is inherited from the shared element
it overrides, so a colour change is one line and a category with no block at all is drawn exactly as
before. Offsets are relative to the row, so a category can sit somewhere else along the line, and a
category only gets its own anim if it names one — otherwise it shares the common node's.

```
; Expert trials in red, shifted right, with their own banner sprite. Nothing else changes.
trialsmenu.item.expert.text.font = 1,0,1, 255, 90, 90
trialsmenu.item.expert.text.offset = 12,0
trialsmenu.item.expert.active.text.font = 1,0,1, 255, 160, 160
trialsmenu.header.expert.bg.spr = 6570,0
```

Only the key bindings and the menu sounds still come from `[Trials Pause Menu]` — `menu.next.key`,
`menu.previous.key`, `menu.add.key`, `menu.subtract.key`, `menu.done.key`, `menu.cancel.key` and
the `cursor.*` sounds — so the menu answers to whatever the screenpack already uses everywhere else.

### The clear marker

`trialsmenu.status.cleared` and `trialsmenu.status.uncleared` each take either art or a label.
Name a sprite (or an anim) and it is drawn; leave both unset and the element's `text` is drawn
instead. That is how you replace the default `CLEAR` label with a sprite of your own:

```
trialsmenu.status.offset = 300,0        ; where the marker sits, from the row's origin
trialsmenu.status.cleared.spr = 6800,0  ; your sprite, in trials.sff or the screenpack's system.sff
trialsmenu.status.cleared.scale = 1.0, 1.0  ; scale applies to whichever of art/text is drawn
; trialsmenu.status.cleared.text is ignored once a sprite is named
trialsmenu.status.uncleared.spr =       ; no art, so its text shows
trialsmenu.status.uncleared.text = "----"
```

Set a state's `text` to `""` and leave its art unset to show nothing at all for that state.

`trialsmenu.arrow.up` and `trialsmenu.arrow.down` work the same way — they default to `^` and `v`
labels, and naming a sprite replaces them.

### Where `anim` numbers come from

Any element taking a sprite takes an `anim` instead, and the action behind that number is read from
three files, each overriding the numbers declared before it: the screenpack's own def, an optional
`trials.air` beside `trials.lua`, and this module's `system.def` (its `ANIMATIONS` section near the
bottom, which is where anims meant for trials mode belong). Sprites are always resolved out of
`trials.sff` when the module ships one, so an action written in any of the three numbers its frames
out of that file. `anim` wins over `spr`, and once either is named the element's `text` is never
drawn — an `anim` pointing at a number no file declares therefore shows nothing at all rather than
falling back to the label.

## Speedrun

Speedrun is a run at the whole character, in order, against the clock. Turning it on from the pause
menu:

- takes **Trials List** off the pause menu, so no trial can be skipped;
- holds **Advancement** at Auto-Advance, since Repeat would stall a run;
- restarts from the first trial with the total timer running.

With Speedrun on, loading into a match skips the Trial Select view and starts on the first trial.
Clearing every trial in one uninterrupted run records the total as that character's best run time;
jumping to a trial invalidates the run, so a run only counts if it was played straight through.
Individual clears and best times are recorded during a speedrun exactly as they are outside one.

The character's best run time is shown beside the Speedrun item in the pause menu once they have
one.

Speedrun is **not** saved: it belongs to the sitting it was started in, and turns itself off
whenever the player returns to the character select screen — via Character Change, the end of a
match, or leaving the mode. Recorded clears and best run times are of course kept.

## Progress

Progress is saved per character to `save/trials.json`, next to the engine's own save data. For each
trial it records whether it has been cleared and the best time; for each character it also records
the best full-run time from Speedrun. It is written the moment a trial is cleared.

```json
{
  "version": 1,
  "chars": {
    "chars/kfmz/kfmz.def": {
      "trials": {
        "KFM's First Trial": { "cleared": true, "besttime": 214 }
      },
      "speedrun": { "cleared": true, "besttime": 4820 }
    }
  }
}
```

Characters are keyed by their def path, so renaming a character's display name keeps its progress.
Trials are keyed by the name in `[TrialDef, <name>]`, so trials can be reordered, added or removed
without losing anything; renaming a trial starts it a fresh record and leaves the old one orphaned,
which is harmless. Times are in ticks (60 to the second).

Deleting `save/trials.json` resets all progress.

### Clearing progress from the pause menu

Two rows, both writing `save/trials.json`. **Neither can be undone.** The match itself is untouched:
the current trial carries on, and only what has been recorded about it goes.

- **`trialsclearcharprogress`** — drops the record of whoever is loaded into P1, leaving every other
  character's alone.
- **`trialsclearprogress`** — empties the file: every clear, best time and speedrun record, for
  every character.

The pause menu is drawn over a frozen match, so there is nowhere to put a warning dialog. The
confirmation is the menu structure instead: **each of those is a submenu, not an action**, and the
rows inside it are the question. `trialsclearcharconfirm` and `trialsclearconfirm` are what erase.

```
menu.itemname.trialsprogress = Progress
menu.itemname.trialsprogress.trialsclearcharprogress = Clear This Character's Progress
menu.itemname.trialsprogress.trialsclearcharprogress.trialsclearcharconfirm = Yes, Erase This Character
menu.itemname.trialsprogress.trialsclearcharprogress.back = No
menu.itemname.trialsprogress.trialsclearprogress = Clear All Progress
menu.itemname.trialsprogress.trialsclearprogress.trialsclearconfirm = Yes, Erase Everything
menu.itemname.trialsprogress.trialsclearprogress.back = No
menu.itemname.trialsprogress.spacer = -
menu.itemname.trialsprogress.back = Back
```

The outer `trialsprogress` level is optional and its name is arbitrary — nest these wherever suits
the screenpack. Only the four `trialsclear*` itemnames are the module's, and they work at any depth.

Declare both halves of a pair. An outer row with nothing under it gets an English Yes/No pair filled
in rather than being left as the empty submenu the engine would otherwise hand it, which would take
the game down when stepped into.

Once used, a pair's rows read back **Cleared** until the pause menu is reset — the only feedback
there is that it worked. The two pairs track that separately, so clearing one character does not
leave the other row claiming to have cleared everything. Rename the label with
`menu.valuename.trialsclearprogress_cleared`; both pairs share it.