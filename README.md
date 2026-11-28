<div align="center">

<img src="https://github.com/user-attachments/assets/b2d52969-1f5e-40f9-b874-c5b130b117cf" alt="Ikemen GO Trials Mode Logo" width="240" />

---

**The Ikemen GO Dojo** delivers a complete experience for Trials, Game Tutorial and Character Guides.
</div>

## Overview
The Ikemen GO Dojo Module adds three game modes to Ikemen GO:

- **Trials**: per-character combo trials. Each character's trials are defined in a `trials.def`; the player works through trials, and clears and best times are saved.
- **Game Tutorial**: lessons about your game's systems and gameplayer features, such as movement, offense and defense. You write your game's tutorial in a single file and you can force specific characters on a per-lesson basis. You can make the tutorials interactive (player has to clear tutorials) or you can do demonstration-only tutorials.
- **Character Guides**: lesson plans that teach one character, such as their specials, their combos and the way they are meant to be played. Defined in a `tutorial.def`.

This markdown file is best viewed on GitHub or in your favourite markdown viewer. 
For more detail on authoring and customization, see this readme or [the wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki). 
Sample dojo files for some of my favourite characters are in [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).

## Preview

https://github.com/user-attachments/assets/c0d08e4e-ea2b-4c0e-bd4c-ca88552f112c

## Features
- The Dojo enables four modes, all operating off a common core: **Trials**, **Game Tutorial**, **Character Guides** and **Combined Tutorial**, allowing you to create **trials** and **lessons** for your game and characters.
- Per-character trial and lesson authoring. Creators add a `trials = trials.def` and/or `tutorial = tutorial.def` line to a character's def file, and define any number of trials or lessons in those files. 
- Multi-step trials and lessons can be condensed in a single step, and steps can accept multiple valid values using an `|` "or" operand for flexible move recognition. 
- All text supports language-suffixed keys for multilingual releases.
- Per-trial and lesson setup. You can set the dummy's stance, automatic guarding, dummy button presses, and life totals for both dummy and player. It can also place both fighters at named stage positions, which the player can snap back to at any time by pressing the associated key combination.
- Recordable /replayable demonstrations for trials and tutorials, as well as complex dummy action sequences.
- Every aspect of the Dojo Mode UI is customizable - fonts, backgrounds for all elements (like titles, upcoming/current/completed trial steps,etc.), animations, defaults, etc. Sprites and sounds for Trials Mode can be neatly packaged in the module's own `trials.sff` and `trials.snd`, or merged into the screenpack's `system.sff` and `system.snd`. Trials Mode also ships with an engine-native pause menu. 
- Trials and lessons can be displayed as a vertical readout (step text plus input glyphs) and a horizontal readout in the style of KOF XIV.
- Persistent progress. Per-character progress (cleared status and best times) is saved and keyed so that it is resilient to changes in trials and tutorial definition files. Also logs clearing time for the included Speedrun mode.
- Configurable Select screen. Trials Mode ships a selection menu that appears either right after stage select or just before the fight begins. Trials can optionally be grouped by difficulty (Beginner, Intermediate, Advanced, Expert), which the player cycles through and which tracks a cleared tally per category.


## Contents
- [Overview](#overview)
- [Preview](#preview)
- [Features](#features)
- [Contents](#contents)
- [Installation](#installation)
  - [Package contents](#package-contents)
  - [Upgrading](#upgrading)
  - [Where content comes from](#where-content-comes-from)
- [Trial and Tutorial Definition Files](#trial-and-tutorial-definition-files)
  - [General Trial or Tutorial Parameter](#general-trial-or-tutorial-parameter)
  - [Trial or Tutorial Teaching Aid Parameters](#trial-or-tutorial-teaching-aid-parameters)
  - [Dummy Actions and Modes](#dummy-actions-and-modes)
  - [Trial or Tutorial Filtering](#trial-or-tutorial-filtering)
  - [Step parameters](#step-parameters)
    - [Condensed Steps and the `|` Operator](#condensed-steps-and-the--operator)
    - [Blocking, blocked moves and the Dummy's State](#blocking-blocked-moves-and-the-dummys-state)
  - [Input scripts: demos and dummy routines](#input-scripts-demos-and-dummy-routines)
  - [Recording a demo](#recording-a-demo)
  - [Demonstrations only](#demonstrations-only)
  - [Projectiles and helpers](#projectiles-and-helpers)
  - [Example: a trials.def](#example-a-trialsdef)
  - [Example: a character lesson file](#example-a-character-lesson-file)
- [Playing](#playing)
  - [The list](#the-list)
  - [The pause menus](#the-pause-menus)
  - [Speedrun](#speedrun)
  - [Progress](#progress)
- [Configuration](#configuration)
  - [config.ini](#configini)
  - [dojo.def: the look](#dojodef-the-look)
- [License](#license)

## Installation
1. Extract the archive into your Ikemen GO folder. The module lives in `external/mods/dojo/`.
2. The module's `+system.def` adds a **Dojo** submenu at the end of the main menu, holding Trials, Game Tutorial and Character Guides. To place the modes elsewhere, see [Main menu entries](#main-menu-entries).
3. (Optional) Change how the modes look by editing `dojo.def`, `dojo.sff` and an optional `dojo.snd`. You can also add sprites and sounds to your screenpack's `system.sff` and `system.snd` instead.
4. The module ships a set of game-wide lessons in `gametutorial.def`, so the Game Tutorial has something to play straight away.
5. Write trials and lessons for your characters (see [Writing trials and lessons](#writing-trials-and-lessons)), and share them!

### Package contents
Everything below is in `external/mods/dojo/`.

| File | What it is |
|---|---|
| `dojo.lua` | The module itself, contains all of the logic. It reads every trials and lesson file, checks steps against the match, drives demos and dummy scripts, draws the HUD and menus, and saves progress. |
| `gametutorial.lua` | The Game Tutorial's match script. |
| `dojo.zss` | Global states for the Dojo. |
| `+system.def` | The main-menu entries, and the `[Trials Pause Menu]` and `[Tutorial Pause Menu]` sections that define each mode's in-match pause menu. |
| `dojo.def` | Defines UI elements all modes supported by the Dojo: positions, fonts, sprites, anims and sounds. **Ships with a reference implementation for `ikemen1` - you'll likely edit this.**|
| `config.ini` | Carries mode configurations and the player's saved preferences. The module rewrites this file when the player changes an option, and the comments are lost when it does. |
| `dojo.sff` | The module's own sprites, detected automatically. If omitted, will look in the screenpack's `system.sff`. |
| `gametutorial.def` | Sample game-wide lessons, in two chapters (Movement and Defence), that work with any MUGEN-standard character. |
| `dojo.snd`, `dojo.air` (not included) | Optional. Drop them beside `dojo.lua` and the modes' sounds and animations come from them instead of the screenpack. |

### Upgrading
See [MIGRATION.md](MIGRATION.md) for a step-by-step guide if you are upgrading from a legacy version of the Ikemen GO Trials Mode.

### Where content comes from
**Trials** live in a file the character's `.def` points to, same for **Character Guides**.

```
[Files]
trials = trials.def
tutorial = tutorial.def
```
**Game-wide Tutorial** are defined in a file identified in `config.ini`:

```ini
[Config]
SystemTutorial = external/mods/dojo/gametutorial.def
```

## Trial and Tutorial Definition Files
Trials and Tutorial definition files are very similar. 
A trial is introduced by specifying `[TrialDef, <name>]` while a tutorial lesson is introduced by specifying `[Lesson, <name>]`. 
After a trial or tutorial lesson is introduced this way, it is followed by a set of parameters that allow the engine to display and monitor all of the information that it should.
A variety of parameters are avialable to you as a creator to define the different trials or lessons, the steps that make up the trial or lesson, and so on.
In this section, we'll briefly look at all of the parameters available to you as an author.

Trials and tutorial definition files share the same parameters, but you'll probably want to lay them out differently, and certain parameters only make sense for one mode or another.
This section enumerates all of the different parameters available to you as an author.

### General Trial or Tutorial Parameter
Set these parameters to better organize your trials or parameters, or to force specific characters or dummies to be used for your System Tutorial lesson.

| Parameter | Format | Default | Description |
|---|---|---|---|
| `chapter` | text | — | The chapter it belongs to. Whenever any entry names a chapter, the list is filtered by chapter. Entries without a chapter go under "Other". Useful to group trials or tutorials together in "Chapters". Chapters would be things like Movement, Offense, Defense, or Combos. |
| `difficulty` | `Beginner`, `Intermediate`, `Advanced`, `Expert` | — | Shown on its row. When no entry in the list names a chapter, the list is filtered by difficulty instead. An unknown value is ignored, with a warning. Think of this as an orthogonal component to Chapters - you could have "Beginner" and "Expert" difficulty tutorials all in a Movement chapter. |
| `playerchar` | character, as `select.def` lists it | `TutorialPlayerChar` | **Game-wide lessons only:** the character P1 plays it with in the Game Tutorial. Ignored elsewhere, where P1 is whoever was picked. This would be useful if you want to demonstrate a specific gameplay mechanic with a specific character. |
| `dummychar` | character, as `select.def` lists it | `TutorialDummy` | **Game-wide lessons only:** the dummy (P2) it's played against in the Game Tutorial. When the next lesson needs a different dummy, the match reloads with it. Ignored elsewhere, with a warning. similar as above, but forcing a dummy character in your System Tutorial. For instance, maybe you can to force Ryu as a dummy to throw fireballs for a parry tutorial. |
| `showforchars` | comma-separated list | everyone | **Game-wide lessons only:** the characters it's offered to. Each entry is matched, case-insensitively, against the character's display name, folder, def file name and def path. You can use this if you want only certain characters in your roster to have access to a systems tutorial, but you probably won't really use this option often. For example: `kfm, chars/ryu/ryu.def`. |

### Trial or Tutorial Teaching Aid Parameters
A variety of features have been introduced to facilitate helping aids for the player.
These include **Pages**, **Hints**, **Textboxes**, **Repeat** and **Demos**.
- **Pages**: think of instruction pages that can be shown to the player when introducing a lesson. If a trial or lesson has any number of `page` parameters specified, the player has to clear the page(s) before attempting or viewing the trial or tutorial.
- **Hints**: if specified, will be be shown to the player after a certain number of failed attempts.
- **Textbox**: if specified, shown on-screen as the player attempts the trial or tutorial.
- **Repeat**: if specified, the trial or tutorial must be successfully cleared that number of times.
- **Demo**: if a `demoscript` is specified, it can be triggered to player after a certrain number of failures, it can be triggered from the pause menu, or if the trial / tutorial is set to `demonstrationonly` it can play automatically.

| Parameter | Format | Default | Description |
|---|---|---|---|
| `page.N.title` | multilingual text | its name | The title of instruction page N. |
| `page.N.text` | multilingual text | — | The body of instruction page N. Pages are shown in order when it starts, and play is held until they've been read. Write `\n` for a line break. |
| `page.N.portrait.spr` | group, number | `instructions.portrait.spr` | A sprite to show as page N's portrait instead of the default. `-1` shows none on this page. |
| `page.N.portrait.anim` | action number | `instructions.portrait.anim` | An action to show as page N's portrait instead. Setting either `spr` or `anim` on a page replaces both defaults. |
| `page.N.portrait.source` | `system`, `char` | `instructions.portrait.source` | Where page N's portrait comes from: the module's own sprites and actions, or P1's own `.sff` and `.air`. |
| `page.N.snd` | group, number | `instructions.page.snd` | A sound played when page N is shown. `-1` plays nothing. |
| `hint` | multilingual text | — | Help shown once the player has failed it `hintafter` times. |
| `hintafter` | whole number | `0` | How many failures before the hint appears. `0` shows it from the start. |
| `textbox` | multilingual text | — | A short note shown beside the steps while it's played. The Textboxes option hides it. |
| `repeat` | whole number | `1` | How many times it must be cleared before it counts. A counter shows the clears made. |
| `demoscript` | [input script](#input-scripts-demos-and-dummy-routines) | — | What the CPU does when the player picks Watch Demo. |
| `demoafter` | whole number | `0` | How many failures before the player is pointed at Watch Demo. `0` never prompts; Watch Demo is still in the pause menu if the screenpack lists it. |

A **failure** is an attempt that got partway and was dropped, such as a combo that ends early. In a blocking lesson, being hit instead of blocking is also a failure. Standing around doesn't count.

### Dummy Actions and Modes
Often, we want the dummy to simply stand there and get hit - no need to specific anything!
But in other cases, we want the dummy to perform specific actions, or perhaps even perform a complex series of actions.
The Dojo Module supports a ton of options to customize your dummy actions.

| Parameter | Format | Default | Description |
|---|---|---|---|
| `dummymode` | `stand`, `crouch`, `jump`, `wjump`, `fjump`, `bjump`, `fwjump`, `bwjump` | `stand` | What the dummy does. `fjump`/`bjump` jump forward/back relative to the way the dummy faces; the `w` modes add an air jump. |
| `guardmode` | `none`, `auto`, `afterhit`, `random` | `none` | `auto` blocks everything. `afterhit` blocks for a moment after being hit, so a combo can be started but not continued. `random` blocks about half the time. `all` is a synonym for `auto`. |
| `dummybuttonjam` | `none`, `a`, `b`, `c`, `x`, `y`, `z`, `s` (or `start`), `d`, `w` | `none` | A button the dummy presses over and over. With a jump `dummymode` it's pressed once per jump, after takeoff (a jump attack), instead of just spamming the attack. |
| `dummybuttondelay` | whole number (frames) | `11` (`0` with a jump mode) | Frames between presses of `dummybuttonjam`. With a jump mode, it's instead the frames after takeoff before the press. |
| `dummyjumpdelay` | whole number (frames) | `0` | Frames the dummy waits on the ground between jumps. The air jump of the `w` modes isn't delayed. |
| `dummyscript` | [input script](#input-scripts-demos-and-dummy-routines) | — | A scripted routine for the dummy, for attacks a button jam can't express (mixups, specials, throws). While it plays, `dummymode`, `dummybuttonjam` and the distance keeping are off (except as `dummyscriptloop` describes); `guardmode` still works. A reset (the reset key, or Reset on Success) starts it over from the top. |
| `dummyscriptloop` | `true` / `false` | `false` | Starts `dummyscript` over each time it ends. With `dummypos` set to `close`, `medium` or `far`, the dummy walks back to that distance during the script's idle (`_`) frames, and an attack it reaches out of place waits for it to get there, then the script starts over from the top (cooperative dummy control only). |
| `dummyscriptdelay` | whole number (frames) | `0` | Frames between loops of `dummyscript`. |
| `dummylife` / `playerlife` | whole number | full | Life totals for the dummy and the player. They refill to this value after a moment. |
| `dummypos` / `playerpos` | `left-corner`, `right-corner`, `far`, `medium`, `close` | centre stage | Where each side starts. The player can return both sides to these positions at any time with d+w. A dummy placed `close`, `medium` or `far` that has something to do (a jump mode or a button jam) walks back to that distance between actions. |
| `dummyposoffset` / `playerposoffset` | `x, y` | `0, 0` | A nudge from the position above. |

### Trial or Tutorial Filtering
Several or Mugen's and Ikemen's most exciting characters do some time of mode selection when entering the fight, like a Groove or ISM select.
Because these modes often alter gameplay mechanics, not all trials or tutorials are valid for all modes.
Character modes are almost always detectable by monitoring pairs of variables and values.
Therefore, you can choose to show a trial or tutorial only when a specific variable/value pair condition is met using this parameter.

| Parameter | Format | Description |
|---|---|---|
| `showforvarvalpairs` | `var, value[, var, value...]` | Shows it only while each of the player's listed variables holds its value. Use this for grooves, modes or stances. A value can list alternatives with `\|`: `12, 0\|2\|4` shows it when var(12) is 0, 2 or 4. `showvarvalpairs` is accepted too. |

### Step parameters
Each trial or lesson is a sequence of steps, written `step.N.<parameter>`, with N counting from 1. 
Steps may be written in any order in the file. 
A missing number is reported in the debug flow, and the steps after it move up.

| Parameter | Format | Default | Description |
|---|---|---|---|
| `text` | multilingual text | — | The step's description (only shown in vertical layout). |
| `glyphs` | [glyph string](https://github.com/ikemen-engine/Ikemen-GO/wiki/Miscellaneous-info#movelists) | — | The input, drawn as glyphs (both layouts). |
| `stateno` | number(s) | — | **MANDATORY** - The state the player (or helper) must be in when other conditions are met (hit or otherwise, see below) in order to pass this step. For a projectile step, the state the projectile was fired from. |
| `animno` | number(s) | — | The animation the player (or helper, or projectile) must be in. |
| `hitcount` | number(s) | `1` | Hits needed. `0` passes on entering the state with no hit at all, for movement, taunts, or moves that don't connect. On a [blocking step](#blocking-blocked-moves-and-the-dummys-state), it's the number of blocks needed. |
| `isthrow` | `true` / `false` | `false` | The step is a throw. |
| `iscounterhit` | `true` / `false` | `false` | The hit must be a counter-hit. |
| `ishelper` | `true` / `false` | `false` | The hit comes from a helper. |
| `isproj` | `true` / `false` | `false` | The hit comes from a projectile (not needed with `projid`). |
| `projid` | number(s) | — | The projectile's ID (its `Projectile` sctrl's `ProjID`). The step passes when that projectile hits. |
| `isguarded` | `true` / `false` | `false` | The player's move (from `stateno` / `animno`) must be **blocked** by the dummy. If a trial has consecutive steps with `isguarded = true` then those steps must constitute a true blockstring to pass, unless `validfortickcount` is set (see below). |
| `validforvarvalpairs` | `var, value[, ...]` | — | The step only counts while each of the player's listed variables holds its value. |
| `validfortickcount` | number(s) | — | After this step passes, frames during which the combo counter may drop to 0 without resetting, as long as the next hit lands inside them. Use it for links and other moves the combo counter doesn't join up. If the window runs out before the next step passes, the attempt resets and counts as a failure: always when the next step is a `guard`, `isguarded` or `p2stateno` step, and otherwise once no combo is still running. Blocking and blocked steps can open a window too. |
| `guard` | `any`, `high`, `low`, `air` | — | The player must **block** an attack: standing, crouching, in the air, or any of them. Useful for tutorials. |
| `p2stateno` | number(s) | — | The dummy's state. On its own, the step passes when the dummy enters it; on a hit step, the hit only counts while the dummy is in it. Rarely used. |

#### Condensed Steps and the `|` Operator
Separate values with commas to fold several moves into one step. 
Each one has to be met in turn before the step passes:

```
step.1.text = Standing Light to Strong Punch
step.1.glyphs = ^X_-^Y
step.1.stateno = 200, 210
step.1.hitcount = 1, 1
```

When one parameter of a step is condensed, give every other condensed-capable parameter on that step the same number of entries. 
The only exceptions to this rule are the `text` and `glyphs` which only need to be specified once per step.

Use `|` to accept any of several values in one place, for example any strength of a special:

```
step.1.stateno = 1000|1010|1020
```

#### Blocking, blocked moves and the Dummy's State
`guard`, `isguarded` and `p2stateno` steps are judged on what happens, not on the combo counter, so they work where nothing ever hits.
Here is an example of a lesson teaching the player how to block low - notice that the

```
[Lesson, Block Low]
dummymode = crouch
dummybuttonjam = a
repeat = 3
step.1.text = Block the crouching attack
step.1.guard = low
```

- **`guard`** passes when the player blocks: `high` is a standing block, `low` a crouching block, `air` an air block. `hitcount` sets how many blocks are needed. Being hit instead resets the attempt and counts as a failure. Blocks are read from the common guard-hit states 150–155.
- **`isguarded`** passes when the player's own move is blocked. Use it to teach pressure that's safe on block, with `guardmode = auto` so the dummy blocks. `hitcount` sets how many blocked hits are needed. With `projid`, the step passes when one of those projectiles is blocked, and `stateno` is the state it was fired from. Only projectiles fired by the character itself count, not by its helpers.
- **Blockstrings.** Two or more `isguarded` steps in a row (or comma-separated parts of one step) must be a true blockstring: each block has to land while the dummy is still in blockstun from the one before (guard-hit states 150–155). If the dummy recovers in between, the attempt resets and counts as a failure.
- **`p2stateno`** on its own passes when the dummy enters one of the listed states, for example `5100` (knocked down). On a hit step, the hit only counts while the dummy is in that state.

A step that hits can follow one of these steps, or any other step that doesn't hit, such as block then punish, or dash then attack. A combo that drops still sends the player back to the first step.

### Input scripts: demos and dummy routines
`demoscript` (what the CPU does for Watch Demo) and `dummyscript` (the dummy's routine) use the same notation: comma-separated `frames:inputs`.

```
demoscript = 6:D, 3:D+F, 3:F+x, 40:_   ; quarter circle forward + x, then wait
dummyscript = 50:_, 1:x, 50:_, 6:D, 1:D+a, 6:D
```

- **Frames** is how long the inputs are held. Leave it off (`D+F`) for a single frame.
- **Inputs** are `U`, `D`, `F`, `B` and the buttons `a`, `b`, `c`, `x`, `y`, `z`, `s`, `d`, `w`, joined with `+`. `_` means nothing held.
- **`F` and `B`** are relative to the way the character faces, exactly as in a command.
- **Limits.** A script can be at most 3600 frames (one minute). A script that can't be read is reported when the file loads and is ignored.

The scripted inputs go through the character's command buffer like real button presses. A motion written out frame by frame therefore comes out as the special. Allow a frame or two more than the command's minimum, the same slack a player needs.

**Watch Demo** restarts the trial or lesson, switches the player's controller off and plays `demoscript` under a DEMO banner. The steps light up as the CPU performs them, but nothing is recorded. When the script ends, or the player presses the menu's done or cancel key, the controller comes back on and the attempt restarts for the player.

### Recording a demo
Writing a demo by hand is fiddly, so the module can record one for you, in any mode:

1. Set `RecordDemo = true` in `config.ini`. A **Record Demo** item appears in the pause menu.
2. Pick it and perform the trial or lesson. Recording starts with your first input, so you don't need to time the pause, and the press that closed the menu isn't included.
3. The take ends by itself on a clear, or pause to end it early.
4. The console prints a ready-made line, which is also written to `save/dojo_demo.txt`:

```
demoscript = 3:D, 2:D+F, 2:F+x, 1:_
```

Set `RecordDemo` back to `false` before you ship.

### Demonstrations only
With `TutorialDemonstrationsOnly = true` in `config.ini`, the tutorial modes (Game Tutorial, Character Guides, Combined Tutorial) only show lessons; the player never plays them. Trials is unaffected.

- Each lesson shows its instruction pages, then plays its `demoscript` on a loop under the DEMO banner. The player's controller stays off.
- On the pages, the menu's done key turns the page and the cancel key goes back one.
- During the demo, any button (`a` `b` `c` `x` `y` `z` `d` `w`) moves on to the next lesson. After the last lesson it opens the lesson list. The press never reaches the character playing the demo: P1's character stays cut off until the button is let go.
- The demo's character is cut off from P1's controller, so the press is read through a spare controller that has no character on it. This needs `Players` set to 3 or more in `save/config.ini` (the default is 4).
- Nothing is cleared or recorded, so gated lessons are all open. Speedrun, Watch Demo and the record rows are left out of the pause menu. Restart, Next / Previous and the lesson list still work.
- Every lesson needs a `demoscript`. A lesson without one, or with one that can't be read, is left out of the list, and the console names it.

The prompt under the demo is `demoonlyprompt.*` in `dojo.def`. `demoonlyprompt.text.last` replaces `demoonlyprompt.text.text` on the last lesson.

**Record Dummy** records a `dummyscript` the same way:
- For the take, your controller drives the dummy. A second controller, if one is connected, drives P1.
- The dummy's own settings (`dummymode`, button jam, distance) and its script are off while you record. Its guard mode stays.
- Pause to end the take. The controllers are handed back, and the attempt restarts with the dummy's settings in place.
- `F` and `B` are recorded relative to the way the dummy faces, which is how a dummy script plays them back.

### Projectiles and helpers
- A `projid` on its own makes a step a projectile step; `isproj` isn't needed alongside it.
- Use `|` when a move can fire more than one ID, or when the ID is an expression. For example, `projid = 3005|3006` covers `ID = 3005+(var(5)=2)`.
- Add `stateno` when one ID is shared by several moves. CvS Sagat, for example, fires ProjID 1000 from states 1000, 1050 and 1070; `projid = 1000` with `stateno = 1070` picks out the heavy Tiger Shot.
- A projectile with no `ProjID` has ID 0, so `projid = 0` matches every such projectile. Pair it with `stateno`.
- `isproj = true` without `projid` matches on `stateno` alone and still needs the projectile to hit. `projid` has no effect when `hitcount = 0`.
- For a projectile fired by a helper, `stateno` is the *root's* state when it was fired.
- `ishelper = true` marks a hit scored by a helper. Counter-hits are generally not detected for helpers or projectiles.

### Example: a trials.def
A sample `trials.def` for `kfm_zss`, referenced from its def with `trials = trials.def`. Trials are presented in the order they're listed.

```
[TrialDef, KFM's First Trial]
difficulty = Beginner
dummymode = stand
guardmode = none
dummybuttonjam = none
; textbox = This is KFM's first trial. Good luck!

step.1.text = Strong Kung Fu Palm
step.1.glyphs = _QDF^Y
step.1.stateno = 1010

;---------------------------------------------

[TrialDef, Kung Fu Throw]
step.1.text = Kung Fu Throw
step.1.glyphs = [_B/_F]_+^Y
step.1.stateno = 810
step.1.isthrow = true

;---------------------------------------------

[TrialDef, Kung Fu Taunt]
textbox.en = This is an English textbox!
textbox.es = Este es un cuadro de texto en español.

step.1.text.en = Kung Fu Taunt
step.1.text.es = Kung Fu Pulla
step.1.glyphs = ^S
step.1.stateno = 195
step.1.hitcount = 0

;---------------------------------------------

[TrialDef, Condensed Standing Punch Chain]
; A condensed step: both moves must be met, in turn, before the step passes.
step.1.text = Standing Light to Strong Punch Chain
step.1.glyphs = ^X_-^Y
step.1.stateno = 200, 210
step.1.hitcount = 1, 1

;---------------------------------------------

[TrialDef, KFM Kung Fu Palm]
; The | operator: either strength passes.
step.1.text = Kung Fu Palm
step.1.glyphs = _QDF^P
step.1.stateno = 1000|1010

;---------------------------------------------

[TrialDef, Kung Fu Juggle Combo]
; The dummy starts in the right corner; d+w puts both sides back.
dummypos = right-corner
page.1.text = Juggle the dummy in the corner. Start with the Kung Fu Knee.
hint = Cancel the crouching jab into the palm as soon as it hits.
hintafter = 3

step.1.text = Kung Fu Knee and Extra Kick
step.1.glyphs = _F_F_+^K_.^K
step.1.stateno = 1060, 1055

step.2.text = Crouching Jab
step.2.glyphs = _D_+^X
step.2.stateno = 400

step.3.text = Weak Kung Fu Palm
step.3.glyphs = _QCF_+^X
step.3.stateno = 1000

;---------------------------------------------

[TrialDef, Kung Fu Super Cancel]
difficulty = Advanced

step.1.text = Jumping Strong Kick
step.1.glyphs = _AIR^B
step.1.stateno = 640

step.2.text = Standing Kick Chain
step.2.glyphs = ^A_-^B
step.2.stateno = 230, 240

step.3.text = Fast Kung Fu Zankou
step.3.glyphs = _QDF^A^B
step.3.stateno = 1420

step.4.text = Triple Kung Fu Palm
step.4.glyphs = _QDF_QDF^P
step.4.stateno = 3000
step.4.hitcount = 3
```

### Example: a character lesson file
```
; chars/kfm/tutorial.def - referenced from kfm.def with: tutorial = tutorial.def

[Lesson, Kung Fu Palm]
chapter = Basics
difficulty = Beginner
repeat = 3

page.1.title = Kung Fu Palm
page.1.text = Kung Fu Man's main special. It travels forward and knocks the opponent away.\nLight is fast; strong reaches further.

hint = Quarter circle forward: down, down-forward, forward - then punch.
hintafter = 2

demoscript = 4:D, 3:D+F, 3:F, 1:F+x, 40:_
demoafter = 3

step.1.text = Kung Fu Palm (any strength)
step.1.glyphs = _QCF^P
step.1.stateno = 1000|1010

[Lesson, Punish a Block]
chapter = Basics
dummypos = close
dummybuttonjam = b
dummybuttondelay = 60

page.1.text = When an attack is blocked, the attacker is open for a moment. Block the dummy's kick, then hit back before it recovers.

step.1.text = Block the kick
step.1.glyphs = _B
step.1.guard = high
step.2.text = Punish with a crouching jab
step.2.glyphs = _D_+^X
step.2.stateno = 400

[Lesson, Kung Fu Juggle]
chapter = Combos
difficulty = Intermediate
dummypos = right-corner

step.1.text = Kung Fu Knee, Extra Kick
step.1.glyphs = _F_F_+^K_.^K
step.1.stateno = 1060, 1055

step.2.text = Crouching Jab
step.2.glyphs = _D_+^X
step.2.stateno = 400

step.3.text = Light Kung Fu Palm
step.3.glyphs = _QCF_+^X
step.3.stateno = 1000
```

`gametutorial.def` is a fuller example of game-wide lessons, with pages, repeats, hints, demos, blocking steps and a scripted dummy mixup.

## Playing

### The list
After choosing a character, the player picks a trial or lesson from a list. `listdisplay` in `dojo.def` decides when it appears (set it under `[Trials Mode]` or `[Tutorial Mode]` to differ per mode):

- `select`: between stage select and the fight.
- `start`: once the match is up.
- `off`: the match starts on the first entry.

Left and right step through the filters: All, each chapter (or difficulty), and Other. The banner shows how many of the filter's entries are cleared, and what percentage.

Each row is marked cleared, uncleared or locked, with its best time. The cursor starts on the first entry not yet cleared.

### The pause menus
Pausing during a match opens the mode's own pause menu. Trials opens `[Trials Pause Menu]`; the Game Tutorial and Character Guides open `[Tutorial Pause Menu]`. Both are defined in `+system.def`, and a screenpack overrides either by declaring the same section in its own `system.def`.

Both menus list the same items and offer every feature in every mode. Each section uses its own mode's itemnames: `trials*` ones in `[Trials Pause Menu]` (Trials Mode 1.x's, where a row already had one), `tutorial*` ones in `[Tutorial Pause Menu]`. `[Trials Pause Menu]` also accepts the `tutorial*` names. A row that would do nothing for the entry being played is left out of the menu: Show Instructions without pages, Watch Demo without a `demoscript` (or during a speedrun), the list during a speedrun, and the record rows unless `RecordDemo = true`.

| Trials itemname | Tutorial itemname | Label (Trials / tutorials) | What it does |
|---|---|---|---|
| `trialsinstructions` | `tutorialinstructions` | Show Instructions | The current entry's pages again. |
| `trialsdemo` | `tutorialdemo` | Watch Demo | The CPU performs it (needs a `demoscript`). |
| `trialsrestart` | `tutorialrestart` | Restart Trial / Restart Lesson | Back to the first step and the start positions. |
| `trialslist` | `tutoriallist` | Trials List / Lesson List | Every entry, as on the list screen. Picking one starts it. |
| `nexttrial`, `previoustrial` | `tutorialnext`, `tutorialprevious` | Next / Previous | Neither will move onto a locked entry. Not in the default menus. |
| `trialsopts` | `tutorialopts` | Trials Mode Options / Tutorial Options | A submenu holding the rows below. |
| `trialsspeedrun` | `tutorialspeedrun` | Speedrun Mode | See below. |
| `trialadvancement` | `tutorialadvancement` | Advancement | Auto-Advance moves on after a clear; Repeat replays it. |
| `trialresetonsuccess` | `tutorialresetonsuccess` | Reset on Success | Returns both sides to their start positions after each clear. |
| `trialslayout` | `tutoriallayout` | Layout | The vertical or horizontal step readout, switchable mid-match. |
| `trialstextboxes` | `tutorialtextboxes` | Textboxes | Shows or hides `textbox`. |
| `trialshints` | `tutorialhints` | Hints | Shows or hides `hint`. |
| `trialsprogress` | `tutorialprogress` | Clear Progress | Erases this character's records, or everything in this mode's save file. |
| `trialsrecord`, `trialsrecorddummy` | `tutorialrecord`, `tutorialrecorddummy` | Record Demo, Record Dummy | Only with `RecordDemo = true` (see [Recording a demo](#recording-a-demo)). |

Advancement, Reset on Success, Layout, Textboxes and Hints are player preferences. They're saved to `config.ini` as soon as they change, separately for Trials (`Trials.*`) and the tutorials (`Tutorial.*`).

### Speedrun
Speedrun plays every entry in order against one timer. Turning it on:

- removes the list from the pause menu;
- holds Advancement at Auto-Advance;
- restarts from the first entry with the run timer going;
- skips instruction pages (they can still be opened from the pause menu).

Clearing every entry in one unbroken run records the character's best run time, shown next to the Speedrun item. Jumping to an entry or restarting one voids the run, and Watch Demo isn't available during one.

Speedrun isn't saved. It turns itself off when the player returns to character select, whether through Character Change, the end of a match, or leaving the mode.

### Progress
Each mode family has its own save file, written the moment something is cleared:

- **Trials:** `save/trials.json`, as in earlier versions.
- **The tutorial modes:** `save/tutorial.json`.

```json
{
  "version": 1,
  "chars": {
    "chars/kfm/kfm.def": {
      "trials": { "KFM's First Trial": { "cleared": true, "besttime": 214 } },
      "speedrun": { "cleared": true, "besttime": 4820 }
    }
  }
}
```

`save/tutorial.json` keeps a character's records under `lessons` rather than `trials`. It also holds the game-wide lessons and the Game Tutorial's speedrun:

```json
{
  "version": 1,
  "chars": { "chars/kfm/kfm.def": { "lessons": { "Kung Fu Palm": { "cleared": true, "besttime": 180 } } } },
  "system": { "external/mods/dojo/gametutorial.def": { "lessons": { "Walking": { "cleared": true, "besttime": 95 } } } },
  "game": { "speedrun": { "cleared": true, "besttime": 3105 } }
}
```

- **Characters** are keyed by their def path, so renaming a character keeps its progress.
- **Trials and lessons** are keyed by name, so they can be reordered, added or removed freely. Two with the same name in one file are told apart as `Name` and `Name #2`. Renaming one starts it a fresh record.
- **Game-wide lessons** are recorded once for everyone, keyed by their file. Clearing "Walking" with one character clears it for all, and in the Game Tutorial too.
- **Times** are in ticks, 60 to the second.
- **Resetting.** Deleting a save file resets that mode's progress.

## Configuration

### config.ini
**`[Modes]`** switches each mode `on` or `off`. `0`, `false` and `no` also mean off, and `1` on, so an older `config.ini` still works. A mode that is off is hidden from every menu, even when the screenpack's `system.def` lists it. When every mode of a family is off, the module doesn't read that family's files. A mode left out of `[Modes]` is on.

| Key | Mode |
|---|---|
| `Trials` | `trials` |
| `SystemTutorial` | `systemtutorial` (Game Tutorial) |
| `CharacterGuides` | `characterguides` |
| `CombinedTutorial` | `combinedtutorial` |

**`[Config]`** is set by hand; the pause menu never changes it. Characters are written the way `select.def` lists them (e.g. `kfm`). A character that isn't in `select.def` is still loaded, excluded from random selection, as the engine does for `TrainingChar`. A path that can't be loaded prints a warning and falls back to the select screen (character) or the default stage (stage).

| Key | Mode | Description |
|---|---|---|
| `TrialsDummy` | Trials | A character always loaded as the dummy (P2). Blank: picked on the select screen. Formerly `TrialsChar`, which is still read. |
| `TrialsStage` | Trials | A stage always used (e.g. `stages/stage0.def`), even over a dummy's `stage` parameter in `select.def`. Blank: picked on the select screen. |
| `TutorialDummy` | tutorials | The dummy (P2). Blank: picked on the select screen, or a mirror of P1 in a Game Tutorial without one. A game-wide lesson can override it with `dummychar`. Formerly `TutorialChar`, which is still read. |
| `TutorialPlayerChar` | Game Tutorial | The character P1 plays the game-wide lessons with. A lesson can override it with `playerchar`. Ships as `kfm_zss`, so the Game Tutorial opens straight on its lesson list. Blank, or a character that can't be loaded: picked on the select screen before the lesson list. |
| `TutorialStage` | tutorials | A stage always used. Blank: picked on the select screen. |
| `SystemTutorial` | tutorials | Game-wide lesson files, comma-separated, relative to the Ikemen folder. Blank: character lessons only. |
| `RecordDemo` | all | `true` adds Record Demo and Record Dummy to the pause menus. For authors; leave it `false` when shipping. |
| `TutorialDemonstrationsOnly` | tutorials | `true` turns every tutorial mode into a walkthrough the player watches rather than plays (see [Demonstrations only](#demonstrations-only)). Default `false`. |

These settings are independent of training mode's `TrainingChar` and `TrainingStage`.

**`[Gating]`** opens a source's files one entry at a time: each entry is locked until the one before it, from the same file, has been cleared. Locked entries are shown but can't be picked. `on` or `off` per source, off when left out:

| Key | Files it applies to |
|---|---|
| `Trials` | Character trial files (`trials = trials.def`). |
| `SystemTutorial` | The game-wide lesson files in `[Config] SystemTutorial`. Shipped `on`. |
| `CharacterGuides` | Character lesson files (`tutorial = tutorial.def`). |

The Combined Tutorial follows the setting of the file each lesson came from.

**`[Options]`** holds the player preferences: `Advancement`, `Layout`, `ResetOnSuccess`, `Textboxes`, `Hints` and `TotalTimer`, plus `TrialTimer` (Trials) or `LessonTimer` (tutorials). Each is prefixed `Trials.` or `Tutorial.`. The values shipped are the defaults; edit them to set your screenpack's defaults.

### dojo.def: the look
Every mode is styled by `dojo.def`, which documents each block in detail. The shipped values suit the [ikemen1 screenpack](https://github.com/ikemen-engine/Ikemen_GO-Elecbyte-Screenpack) at 1280×720.

- **`[Dojo]`** is the look all three modes share. Restyle everything here once.
- **`[Trials Mode]`** is laid over it for Trials, and **`[Tutorial Mode]`** for the Game Tutorial and Character Guides. Each only needs the keys that differ; the shipped ones hold just the labels (titles, counter, timers, list title), "Trial" in one and "Lesson" in the other. Repeat any `[Dojo]` key in a mode section to style that mode differently: a value replaces the shared one, and a block (`title.vertical`, say) is merged key by key.
- A def with no `[Dojo]` section, such as a Trials Mode 1.x `trialsmode.def` renamed `dojo.def`, uses its `[Trials Mode]` as the shared look instead.

Key names are mode-neutral. The older spellings are still read in any section, so a file or section copied from an earlier version works unchanged. That covers Trials Mode's names (`trialtitle`, `trialsteps`, `trialcounter`, `totaltrialtimer`, `currenttrialtimer`, `trialreset`, `trialsmenu`, `trialslocalcoord`, `trialslistdisplay`, `trialcounter.notrialsdata`) and the old standalone `tutorialmode.def`'s (`lessontitle`, `lessonsteps`, `lessoncounter`, `tutorialmenu`, ...).

| Block | What it draws |
|---|---|
| `localcoord`, `listdisplay` | The canvas the def is authored on; when the list appears. |
| `title.*`, `steps.*`, `upcomingstep.*`, `currentstep.*`, `completedstep.*`, `glyphs.*` | The title and step readout, per layout (vertical / horizontal). |
| `counter.*`, `totaltimer.*`, `currenttimer.*`, `reset.*` | The counter, the timers and the position-reset reminder (d+w). |
| `textbox.*` | `textbox`, with an optional portrait. |
| `instructions.*` | The instruction pages: overlay, title, wrapped body text that types itself out, page number, prompt, portrait and page sound. Pages can override the portrait and sound. |
| `hint.*`, `repcounter.*`, `demo.*`, `demoprompt.*`, `demoonlyprompt.*` | The hint, the repetition counter, the DEMO banner (REC while recording), the prompt pointing at Watch Demo, and the controls prompt under a demonstrations-only demo. |
| `success.*`, `allclear.*` | The banners for a clear and for clearing everything. |
| `menu.*` | The list: rows, cursor, filter banner, cleared/uncleared/locked markers, best times, scroll arrows. |
| `selscreenpalfx.*`, `fadein.*`, `fadeout.*` | Greying out characters with nothing to play, and the reposition fade. |

A few conventions apply throughout:

- **Fonts** are `font = bank, colour bank, align[, r, g, b]`, with align `1` left, `0` centre, `-1` right.
- **Art elements** (`bg`, `front`, markers) take `spr` or `anim`, `offset`, `scale`, `facing`, `displaytime` and `layerno`.
- **List rows** can be styled per chapter or per difficulty by naming the category after `item` or `header`, e.g. `menu.item.movement.text.font = 1,0,1, 120,200,255`. A chapter's id is its name in lowercase, with anything other than letters and digits turned into `_`.
- **Translations:** a chapter's name can be translated in the pause menu section with `menu.valuename.tutorialchapter_<id>`.
- **Sprites** come from `dojo.sff` when it's present, and from the screenpack's `system.sff` otherwise.
- **Sounds** come from `dojo.snd` when present, and from `system.snd` otherwise. The switch applies to the whole file: once the module's `.snd` exists, a sound missing from it plays nothing.
- **Pause-menu sounds.** The pause menu's own sounds (`cursor.move`, `cursor.done`, `enter`, `cancel`) always come from the screenpack's pause menu section and `system.snd`, so the list answers like every other menu.

## License
GNU LGPL v2.1. See `LICENSE`.

Module developed by two4teezee.
