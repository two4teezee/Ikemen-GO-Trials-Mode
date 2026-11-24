<div align="center">

<img src="https://github.com/user-attachments/assets/b2d52969-1f5e-40f9-b874-c5b130b117cf" alt="Ikemen GO Trials Mode Logo" width="240" />

---

**The Dojo Module** for Ikemen GO: Trials, a Game Tutorial and Character Guides, delivered from one shared core.
</div>

## Overview
The Dojo adds three game modes to Ikemen GO:

- **Trials**: per-character combo trials. Each character ships a `trials.def`, the player works through its trials one by one, and clears and best times are saved.
- **Game Tutorial**: lessons about your game rather than about one character, such as walking, jumping, running, or blocking high and low. You write them once, in files listed in `config.ini`.
- **Character Guides**: lessons that teach one character, such as their specials, their combos and the way they are meant to be played. Each character ships a `tutorial.def`.

By default the three modes sit together in one main-menu submenu, **Dojo**. Any of them can be listed on its own instead, or switched off.

All three modes run on the same engine. A trial and a lesson are the same thing, a sequence of steps checked against the live match. So every feature is available in every mode:

- step checking (states, anims, hit counts, throws, counter-hits, helpers, projectiles, blocks, the dummy's state);
- condensed steps and the `|` operator;
- a configurable dummy, including scripted attack routines;
- instruction pages, hints, demos the CPU performs, and repetitions;
- chapters and difficulties, and lessons that open one at a time;
- vertical and horizontal step readouts, textboxes;
- a select list, a pause menu, Speedrun, and saved progress.

The modes differ only in where their content comes from and where their progress is saved. They share one look, `[Dojo]` in `dojo.def`, and each mode overrides just its labels. Each family keeps its own pause menu, player preferences and save file.

This markdown file is best viewed on GitHub or in your favourite markdown viewer. For more detail on authoring and customization, see this readme or [the wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki). Sample trials files for some favourite characters are in [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).

## Preview

https://github.com/user-attachments/assets/c0d08e4e-ea2b-4c0e-bd4c-ca88552f112c

## Contents
- [Installation](#installation)
- [Package contents](#package-contents)
- [Upgrading](#upgrading)
- [Writing trials and lessons](#writing-trials-and-lessons)
  - [Where content comes from](#where-content-comes-from)
  - [File layout](#file-layout)
  - [Trial and lesson parameters](#trial-and-lesson-parameters)
  - [Step parameters](#step-parameters)
  - [Condensed steps and the `|` operator](#condensed-steps-and-the--operator)
  - [Blocking, blocked moves and the dummy's state](#blocking-blocked-moves-and-the-dummys-state)
  - [Input scripts: demos and dummy routines](#input-scripts-demos-and-dummy-routines)
  - [Recording a demo](#recording-a-demo)
  - [Common state numbers](#common-state-numbers)
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

## Installation
1. Extract the archive into your Ikemen GO folder. The module lives in `external/mods/dojo/`.
2. The module's `+system.def` adds a **Dojo** submenu at the end of the main menu, holding Trials, Game Tutorial and Character Guides. To place the modes elsewhere, see [Main menu entries](#main-menu-entries).
3. (Optional) Change how the modes look by editing `dojo.def`, `dojo.sff` and an optional `dojo.snd`. You can also add sprites and sounds to your screenpack's `system.sff` and `system.snd` instead.
4. The module ships a set of game-wide lessons in `gametutorial.def`, so the Game Tutorial has something to play straight away.
5. Write trials and lessons for your characters (see [Writing trials and lessons](#writing-trials-and-lessons)), and share them!

### Main menu entries
The screenpack decides which modes the player sees by the main-menu items it lists:

| Item | Mode |
|---|---|
| `trials` | **Trials.** The select screen, with every character that has no trials file greyed out, then that character's trials. |
| `tutorialgame` | **Game Tutorial.** A list of the game-wide lessons, each going straight into a match. P1 is `TutorialPlayerChar`, or the lesson's own `playerchar`. With no `TutorialPlayerChar`, P1 is picked on the select screen first. |
| `tutorialchars` | **Character Guides.** The select screen, with every character that has no lesson file of its own greyed out, then only that character's lessons. |
| `tutorial` | **Combined tutorial.** The select screen, then the game-wide lessons and the character's own lessons in one list. Not in the default menu. |

The shipped `+system.def` lists the first three as a submenu:

```ini
[Title Info]
menu.itemname.dojo = "Dojo"
menu.itemname.dojo.trials = "Trials"
menu.itemname.dojo.tutorialgame = "Game Tutorial"
menu.itemname.dojo.tutorialchars = "Character Guides"
menu.itemname.dojo.back = "Back"
```

To put them somewhere else, copy the lines you want into your screenpack's `system.def` and comment them out in `+system.def`. Each item can also stand at the top level, for example `menu.itemname.trials = "Trials Mode"`. `[Modes]` in `config.ini` hides any mode, even when the screenpack lists it.

In the Game Tutorial, the dummy is chosen in this order:
1. `TutorialDummy`;
2. the character picked on the select screen, if there was one;
3. otherwise, a mirror of P1.

A blank `TutorialStage` is the engine's pick when there is no select screen.

Exit returns to the main menu, and Character Change returns to the lesson list. The next lesson can need a different P1, whether you reach it from the Lesson List, Next/Previous Lesson or Auto-Advance. When it does, the match reloads with that character. For the same reason, Speedrun Mode is off in a Game Tutorial whose lessons don't all share one P1.

## Package contents
Everything below is in `external/mods/dojo/`.

| File | What it is |
|---|---|
| `dojo.lua` | The module itself. It reads every trials and lesson file, checks steps against the match, drives demos and dummy scripts, draws the HUD and menus, and saves progress. You shouldn't need to edit it. |
| `gametutorial.lua` | The Game Tutorial's match script. The engine runs it in place of its own `default.lua` when the Game Tutorial is picked; it does nothing at any other time. |
| `dojo.zss` | Global states the modes need: holding both sides still, repositioning, the dummy's behaviour, and pressing scripted inputs. Loaded automatically. |
| `+system.def` | The main-menu entries, and the `[Trials Pause Menu]` and `[Tutorial Pause Menu]` sections that define each mode's in-match pause menu. |
| `dojo.def` | The look of every mode: every position, font, sprite and sound under `[Dojo]`, and each mode's labels under `[Trials Mode]` and `[Tutorial Mode]`. |
| `config.ini` | Which modes are on, the `[Config]` settings, and the player's saved preferences. The module rewrites this file when the player changes an option, and the comments are lost when it does. |
| `dojo.sff` | The module's own sprites, detected automatically. |
| `gametutorial.def` | Sample game-wide lessons, in two chapters (Movement and Defence), that work with any MUGEN-standard character. |
| `dojo.snd`, `dojo.air` (not included) | Optional. Drop them beside `dojo.lua` and the modes' sounds and animations come from them instead of the screenpack. |

## Upgrading
The Dojo replaces both Trials Mode and the standalone Tutorial Mode module. **Delete `external/mods/trials/` and `external/mods/tutorial/` before installing it**: left in place, they register the same menu items and pause menus and break the Dojo. It prints a warning at startup if it finds either one.

**From Trials Mode 1.x**

See [MIGRATION.md](MIGRATION.md) for a step-by-step guide. In short:

- Your characters' `trials.def` files, `save/trials.json`, the `TrialsChar` / `TrialsStage` settings and the `Trials.*` preferences all carry over unchanged.
- A screenpack `system.def` that lists `menu.itemname.trials` keeps working.
- Move your `config.ini` preferences across: the keys keep their names.
- A customised `trialsmode.def` keeps working: rename it `dojo.def`. With no `[Dojo]` section, its `[Trials Mode]` is used as the look of every mode. Its key names are all still read, though the shipped file now uses mode-neutral ones (see [dojo.def: the look](#dojodef-the-look)).
- A screenpack's own `[Trials Pause Menu]` that uses the old itemnames (`trialslist`, `trialsopts`, `trialadvancement`, `trialslayout`, `nexttrial`, ...) keeps working too. Both pause menus now share one set of itemnames (see [The pause menus](#the-pause-menus)). Replace your `+system.def` to pick up the new items.
- Trials gain every tutorial feature. They also follow the tutorials' parsing rules:
  - **Keys must be written in full.** Trials used to accept any line that contained the key's name.
  - **A language suffix always wins.** The suffixed version of a step's text now always beats the plain one.
  - **All `validforvarvalpairs` pairs are checked.** Trials could ignore all but the first.
  - **A hit step can follow a step that doesn't hit.** Before, such a step reset to step 1 straight away, so "dash, then attack" couldn't be cleared. Combos that drop reset exactly as before.
  - **`guardmode` gains two values:** `afterhit` and `random`.

**From the standalone Tutorial Mode module**
- Move your settings from `external/mods/tutorial/config.ini` into the Dojo's `config.ini`. The tutorial keys keep their names: `TutorialDummy`, `TutorialPlayerChar`, `TutorialStage`, `SystemTutorial`, `RecordDemo` and `Tutorial.*`.
- Point `SystemTutorial` at the files' new location, for example `external/mods/dojo/gametutorial.def`.
- `save/tutorial.json`, characters' `tutorial = ...` lines and `[Tutorial Pause Menu]` overrides carry over unchanged.
- `tutorialmode.def` and `tutorial.sff` are gone; every mode now uses `dojo.def` and `dojo.sff`. If you customised `tutorialmode.def`, copy the keys you changed into the `[Tutorial Mode]` section at the end of `dojo.def`. Both spellings of the key names are read there, so they can be pasted unchanged.

## Writing trials and lessons

### Where content comes from
**Trials** live in a file the character's def points to. In the character's `.def`, under `[Files]`, add:

```
[Files]
trials = trials.def        ; Trials
```

**Character Guides** work the same way, with their own key:

```
[Files]
tutorial = tutorial.def    ; Character Guides
```

A character can have both. The two files are read by the same parser, so either key may point at a file written either way.

**Game-wide lessons** live in files listed in `config.ini`:

```ini
[Config]
SystemTutorial = external/mods/dojo/gametutorial.def, data/my_screenpack_lessons.def
```

These are lessons about the game, not about one character. They make up the Game Tutorial, and the combined `tutorial` mode offers them to every character ahead of its own.

`chars` limits a game-wide lesson to some characters, which makes it character content. It then leaves the Game Tutorial and moves to the Character Guides of the characters it names. Game-wide lessons are never part of Trials.

On the select screen, a character with nothing to play in the current mode is greyed out.

### File layout
Every file is written the same way, whichever mode it is for:

```
[Tutorial]                        ; optional: settings for this whole file
tutorial.gated = true

[Chapter, Movement]               ; optional: declares a chapter and its subtitle
chapter.text = Getting around the stage.

[TrialDef, Dashing]               ; one trial or lesson; the name after the comma is its title
trial.chapter = Movement
trial.page.1.text = Tap forward twice to dash.
trialstep.1.text = Forward Dash
trialstep.1.glyphs = _F_F
trialstep.1.stateno = 100
trialstep.1.hitcount = 0
```

- **Two spellings.** `[TrialDef, ...]`, `trial.*` and `trialstep.*` are the same as `[Lesson, ...]`, `lesson.*` and `lessonstep.*`. Use whichever reads better; the tables below give the parameter names without the prefix.
- **Order.** Trials and lessons are listed in the order they appear in the file. One with no name after the comma is called "Trial N" (Trials) or "Lesson N" (tutorials).
- **Keys.** Keys are case-insensitive and must be written in full. An unknown key or section prints a warning to the console, with the file and line number.
- **Comments.** `;` starts a comment.
- **Languages.** Text keys can take a language suffix (`trial.textbox.es`, `trialstep.1.text.ja`). The module uses the language set in Ikemen's options, then `.en`, then the key with no suffix.

**`[Tutorial]` parameters**

| Parameter | Format | Default | Description |
|---|---|---|---|
| `tutorial.gated` | `true` / `false` | `false` | Opens this file's entries one at a time. Each is locked until the one before it, from the same file, has been cleared. Locked entries are shown but can't be picked. |

**`[Chapter, <name>]` parameters**

| Parameter | Format | Description |
|---|---|---|
| `chapter.text` | multilingual text | A subtitle for the chapter. |

A chapter doesn't have to be declared: `chapter = Combos` creates one called "Combos". Declare it to give it a subtitle, or to fix its display name.

### Trial and lesson parameters
Set once per trial or lesson, written `trial.<parameter>` or `lesson.<parameter>`.

**What it is**

| Parameter | Format | Default | Description |
|---|---|---|---|
| `chapter` | text | — | The chapter it belongs to. Whenever any entry names a chapter, the list is filtered by chapter. Entries without a chapter go under "Other". |
| `difficulty` | `Beginner`, `Intermediate`, `Advanced`, `Expert` | — | Shown on its row. When no entry in the list names a chapter, the list is filtered by difficulty instead. An unknown value is ignored, with a warning. |
| `chars` | comma-separated list | everyone | Game-wide lessons only: the characters it's offered to. Each entry is matched, case-insensitively, against the character's display name, folder, def file name and def path. For example: `kfm, chars/ryu/ryu.def`. |
| `playerchar` | character, as `select.def` lists it | `TutorialPlayerChar` | Game-wide lessons only: the character P1 plays it with in the Game Tutorial. Ignored elsewhere, where P1 is whoever was picked. |

**Teaching**

| Parameter | Format | Default | Description |
|---|---|---|---|
| `page.N.title` | multilingual text | its name | The title of instruction page N. |
| `page.N.text` | multilingual text | — | The body of instruction page N. Pages are shown in order when it starts, and play is held until they've been read. Write `\n` for a line break. |
| `page.N.portrait.spr` | group, number | `instructions.portrait.spr` | A sprite to show as page N's portrait instead of the default. `-1` shows none on this page. |
| `page.N.portrait.anim` | action number | `instructions.portrait.anim` | An action to show as page N's portrait instead. Setting either `spr` or `anim` on a page replaces both defaults. |
| `page.N.portrait.source` | `system`, `char` | `instructions.portrait.source` | Where page N's portrait comes from: the module's own sprites and actions, or P1's own `.sff` and `.air`. |
| `page.N.snd` | group, number | `instructions.page.snd` | A sound played when page N is shown. `-1` plays nothing. |
| `textbox` | multilingual text | — | A short note shown beside the steps while it's played. The Textboxes option hides it. |
| `hint` | multilingual text | — | Help shown once the player has failed it `hintafter` times. |
| `hintafter` | whole number | `0` | How many failures before the hint appears. `0` shows it from the start. |
| `repeat` | whole number | `1` | How many times it must be cleared before it counts. A counter shows the clears made. |
| `demoscript` | [input script](#input-scripts-demos-and-dummy-routines) | — | What the CPU does when the player picks Watch Demo. |
| `demoafter` | whole number | `0` | How many failures before the player is pointed at Watch Demo. `0` never prompts; Watch Demo is still in the pause menu if the screenpack lists it. |

A **failure** is an attempt that got partway and was dropped, such as a combo that ends early. In a blocking lesson, being hit instead of blocking is also a failure. Standing around doesn't count.

**The dummy**

| Parameter | Format | Default | Description |
|---|---|---|---|
| `dummymode` | `stand`, `crouch`, `jump`, `wjump`, `fjump`, `bjump`, `fwjump`, `bwjump` | `stand` | What the dummy does. `fjump`/`bjump` jump forward/back relative to the way the dummy faces; the `w` modes add an air jump. |
| `guardmode` | `none`, `auto`, `afterhit`, `random` | `none` | `auto` blocks everything. `afterhit` blocks for a moment after being hit, so a combo can be started but not continued. `random` blocks about half the time. `all` is a synonym for `auto`. |
| `dummybuttonjam` | `none`, `a`, `b`, `c`, `x`, `y`, `z`, `s` (or `start`), `d`, `w` | `none` | A button the dummy presses over and over. With a jump `dummymode` it's pressed once per jump, after takeoff (a jump attack). |
| `dummybuttondelay` | whole number (frames) | `11` (`0` with a jump mode) | Frames between presses of `dummybuttonjam`. With a jump mode, it's instead the frames after takeoff before the press. |
| `dummyjumpdelay` | whole number (frames) | `0` | Frames the dummy waits on the ground between jumps. The air jump of the `w` modes isn't delayed. |
| `dummyscript` | [input script](#input-scripts-demos-and-dummy-routines) | — | A scripted routine for the dummy, for attacks a button jam can't express (mixups, specials, throws). While it plays, `dummymode`, `dummybuttonjam` and the distance keeping are off; `guardmode` still works. |
| `dummyscriptloop` | `true` / `false` | `false` | Starts `dummyscript` over each time it ends. |
| `dummyscriptdelay` | whole number (frames) | `0` | Frames between loops of `dummyscript`. |
| `dummylife` / `playerlife` | whole number | full | Life totals for the dummy and the player. They refill to this value after a moment. |
| `dummypos` / `playerpos` | `left-corner`, `right-corner`, `far`, `medium`, `close` | centre stage | Where each side starts. The player can return both sides to these positions at any time with d+w. A dummy placed `close`, `medium` or `far` that has something to do (a jump mode or a button jam) walks back to that distance between actions. |
| `dummyposoffset` / `playerposoffset` | `x, y` | `0, 0` | A nudge from the position above. |

**Showing it only some of the time**

| Parameter | Format | Description |
|---|---|---|
| `showforvarvalpairs` | `var, value[, var, value...]` | Shows it only while each of the player's listed variables holds its value. Use this for grooves, modes or stances. A value can list alternatives with `\|`: `12, 0\|2\|4` shows it when var(12) is 0, 2 or 4. `showvarvalpairs` is accepted too. |

### Step parameters
Each trial or lesson is a sequence of steps, written `trialstep.N.<parameter>` or `lessonstep.N.<parameter>`, with N counting from 1. Steps may be written in any order in the file. A missing number is reported, and the steps after it move up.

| Parameter | Format | Default | Description |
|---|---|---|---|
| `text` | multilingual text | — | The step's description (vertical layout). |
| `glyphs` | [glyph string](https://github.com/ikemen-engine/Ikemen-GO/wiki/Miscellaneous-info#movelists) | — | The input, drawn as glyphs (both layouts). |
| `stateno` | number(s) | — | The state the player (or helper) must be in. For a projectile step, the state the projectile was fired from. |
| `animno` | number(s) | — | The animation the player (or helper, or projectile) must be in. |
| `hitcount` | number(s) | `1` | Hits needed. `0` passes on entering the state with no hit at all, for movement, taunts, or moves that don't connect. On a [blocking step](#blocking-blocked-moves-and-the-dummys-state), it's the number of blocks needed. |
| `isthrow` | `true` / `false` | `false` | The step is a throw. |
| `iscounterhit` | `true` / `false` | `false` | The hit must be a counter-hit. |
| `ishelper` | `true` / `false` | `false` | The hit comes from a helper. |
| `isproj` | `true` / `false` | `false` | The hit comes from a projectile (not needed with `projid`). |
| `projid` | number(s) | — | The projectile's ID (its `Projectile` sctrl's `ProjID`). The step passes when that projectile hits. |
| `guard` | `any`, `high`, `low`, `air` | — | The player must **block** an attack: standing, crouching, in the air, or any of them. |
| `isguarded` | `true` / `false` | `false` | The player's move (from `stateno` / `animno`) must be **blocked** by the dummy. |
| `p2stateno` | number(s) | — | The dummy's state. On its own, the step passes when the dummy enters it; on a hit step, the hit only counts while the dummy is in it. |
| `validforvarvalpairs` | `var, value[, ...]` | — | The step only counts while each of the player's listed variables holds its value. |
| `validfortickcount` | number(s) | — | After this step passes, frames during which the combo counter may drop to 0 without resetting, as long as the next hit lands inside them. Use it for links and other moves the combo counter doesn't join up. |
| `iconanim`, `iconanimoffset`, `iconanimscale`, `iconanimwindow` | numbers | portrait sprite | The portrait shown in the textbox while this step is current. |

### Condensed steps and the `|` operator
Separate values with commas to fold several moves into one step. Each one has to be met in turn before the step passes:

```
trialstep.1.text = Standing Light to Strong Punch
trialstep.1.glyphs = ^X_-^Y
trialstep.1.stateno = 200, 210
trialstep.1.hitcount = 1, 1
```

When one parameter of a step is condensed, give every other condensed-capable parameter on that step the same number of entries. That is every parameter except `text` and `glyphs`.

Use `|` to accept any of several values in one place, for example any strength of a special:

```
trialstep.1.stateno = 1000|1010|1020
```

### Blocking, blocked moves and the dummy's state
`guard`, `isguarded` and `p2stateno` steps are judged on what happens, not on the combo counter, so they work where nothing ever hits.

```
[Lesson, Block Low]
lesson.dummymode = crouch
lesson.dummybuttonjam = a
lesson.repeat = 3
lessonstep.1.text = Block the crouching attack
lessonstep.1.guard = low
```

- **`guard`** passes when the player blocks: `high` is a standing block, `low` a crouching block, `air` an air block. `hitcount` sets how many blocks are needed. Being hit instead resets the attempt and counts as a failure. Blocks are read from the common guard-hit states 150–155.
- **`isguarded`** passes when the player's own move is blocked. Use it to teach pressure that's safe on block, with `guardmode = auto` so the dummy blocks.
- **`p2stateno`** on its own passes when the dummy enters one of the listed states, for example `5100` (knocked down). On a hit step, the hit only counts while the dummy is in that state.

A step that hits can follow one of these steps, or any other step that doesn't hit, such as block then punish, or dash then attack. A combo that drops still sends the player back to the first step.

### Input scripts: demos and dummy routines
`demoscript` (what the CPU does for Watch Demo) and `dummyscript` (the dummy's routine) use the same notation: comma-separated `frames:inputs`.

```
trial.demoscript = 6:D, 3:D+F, 3:F+x, 40:_   ; quarter circle forward + x, then wait
trial.dummyscript = 50:_, 1:x, 50:_, 6:D, 1:D+a, 6:D
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
4. The console prints a ready-made line, which is also written to `save/tutorial_demo.txt`:

```
lesson.demoscript = 3:D, 2:D+F, 2:F+x, 1:_
```

Set `RecordDemo` back to `false` before you ship.

**Record Dummy** records a `dummyscript` the same way:
- For the take, your controller drives the dummy. A second controller, if one is connected, drives P1.
- The dummy's own settings (`dummymode`, button jam, distance) and its script are off while you record. Its guard mode stays.
- Pause to end the take. The controllers are handed back, and the attempt restarts with the dummy's settings in place.
- `F` and `B` are recorded relative to the way the dummy faces, which is how a dummy script plays them back.

### Common state numbers
These come from `common1.cns`, so they're the same for every MUGEN-standard character unless the character overrides them. They're useful with `hitcount = 0` for movement lessons.

| State | Meaning | State | Meaning |
|---|---|---|---|
| 0 | standing | 100 | running forward |
| 10 / 11 | crouching (start / held) | 105 | hopping back |
| 20 | walking | 120 | starting to block |
| 40 | jump start | 150 / 152 / 154 | blocking a hit: standing / crouching / air |
| 50 | in the air | 5000+ | being hit |
| 52 | landing | 5100 | knocked down (hitting the ground) |

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
trial.difficulty = Beginner
trial.dummymode = stand
trial.guardmode = none
trial.dummybuttonjam = none
; trial.textbox = This is KFM's first trial. Good luck!

trialstep.1.text = Strong Kung Fu Palm
trialstep.1.glyphs = _QDF^Y
trialstep.1.stateno = 1010

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

[TrialDef, Condensed Standing Punch Chain]
; A condensed step: both moves must be met, in turn, before the step passes.
trialstep.1.text = Standing Light to Strong Punch Chain
trialstep.1.glyphs = ^X_-^Y
trialstep.1.stateno = 200, 210
trialstep.1.hitcount = 1, 1

;---------------------------------------------

[TrialDef, KFM Kung Fu Palm]
; The | operator: either strength passes.
trialstep.1.text = Kung Fu Palm
trialstep.1.glyphs = _QDF^P
trialstep.1.stateno = 1000|1010

;---------------------------------------------

[TrialDef, Kung Fu Juggle Combo]
; The dummy starts in the right corner; d+w puts both sides back.
trial.dummypos = right-corner
trial.page.1.text = Juggle the dummy in the corner. Start with the Kung Fu Knee.
trial.hint = Cancel the crouching jab into the palm as soon as it hits.
trial.hintafter = 3

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

[TrialDef, Kung Fu Super Cancel]
trial.difficulty = Advanced
trialstep.1.text = Jumping Strong Kick
trialstep.1.glyphs = _AIR^B
trialstep.1.stateno = 640

trialstep.2.text = Standing Kick Chain
trialstep.2.glyphs = ^A_-^B
trialstep.2.stateno = 230, 240

trialstep.3.text = Fast Kung Fu Zankou
trialstep.3.glyphs = _QDF^A^B
trialstep.3.stateno = 1420

trialstep.4.text = Triple Kung Fu Palm
trialstep.4.glyphs = _QDF_QDF^P
trialstep.4.stateno = 3000
trialstep.4.hitcount = 3
```

### Example: a character lesson file
```
; chars/kfm/tutorial.def - referenced from kfm.def with: tutorial = tutorial.def

[Chapter, Basics]
chapter.text = Kung Fu Man's tools.

[Chapter, Combos]

[Lesson, Kung Fu Palm]
lesson.chapter = Basics
lesson.difficulty = Beginner
lesson.page.1.title = Kung Fu Palm
lesson.page.1.text = Kung Fu Man's main special. It travels forward and knocks the opponent away.\nLight is fast; strong reaches further.
lesson.repeat = 3
lesson.hint = Quarter circle forward: down, down-forward, forward - then punch.
lesson.hintafter = 2
lesson.demoscript = 4:D, 3:D+F, 3:F, 1:F+x, 40:_
lesson.demoafter = 3
lessonstep.1.text = Kung Fu Palm (any strength)
lessonstep.1.glyphs = _QCF^P
lessonstep.1.stateno = 1000|1010

[Lesson, Punish a Block]
lesson.chapter = Basics
lesson.page.1.text = When an attack is blocked, the attacker is open for a moment. Block the dummy's kick, then hit back before it recovers.
lesson.dummypos = close
lesson.dummybuttonjam = b
lesson.dummybuttondelay = 60
lessonstep.1.text = Block the kick
lessonstep.1.glyphs = _B
lessonstep.1.guard = high
lessonstep.2.text = Punish with a crouching jab
lessonstep.2.glyphs = _D_+^X
lessonstep.2.stateno = 400

[Lesson, Kung Fu Juggle]
lesson.chapter = Combos
lesson.difficulty = Intermediate
lesson.dummypos = right-corner
lessonstep.1.text = Kung Fu Knee, Extra Kick
lessonstep.1.glyphs = _F_F_+^K_.^K
lessonstep.1.stateno = 1060, 1055
lessonstep.2.text = Crouching Jab
lessonstep.2.glyphs = _D_+^X
lessonstep.2.stateno = 400
lessonstep.3.text = Light Kung Fu Palm
lessonstep.3.glyphs = _QCF_+^X
lessonstep.3.stateno = 1000
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

Both menus use the same itemnames, list the same items, and offer every feature in every mode; only the labels differ. A row that would do nothing for the entry being played is left out of the menu: Show Instructions without pages, Watch Demo without a `demoscript` (or during a speedrun), the list during a speedrun, and the record rows unless `RecordDemo = true`.

| Itemname | Label (Trials / tutorials) | What it does |
|---|---|---|
| `tutorialinstructions` | Show Instructions | The current entry's pages again. |
| `tutorialdemo` | Watch Demo | The CPU performs it (needs a `demoscript`). |
| `tutorialrestart` | Restart Trial / Restart Lesson | Back to the first step and the start positions. |
| `tutoriallist` | Trials List / Lesson List | Every entry, as on the list screen. Picking one starts it. |
| `tutorialnext`, `tutorialprevious` | Next / Previous | Neither will move onto a locked entry. Not in the default menus. |
| `tutorialopts` | Trials Mode Options / Tutorial Options | A submenu holding the rows below. |
| `tutorialspeedrun` | Speedrun Mode | See below. |
| `tutorialadvancement` | Advancement | Auto-Advance moves on after a clear; Repeat replays it. |
| `tutorialresetonsuccess` | Reset on Success | Returns both sides to their start positions after each clear. |
| `tutoriallayout` | Layout | The vertical or horizontal step readout, switchable mid-match. |
| `tutorialtextboxes` | Textboxes | Shows or hides `textbox`. |
| `tutorialhints` | Hints | Shows or hides `hint`. |
| `tutorialprogress` | Clear Progress | Erases this character's records, or everything in this mode's save file. |
| `tutorialrecord`, `tutorialrecorddummy` | Record Demo, Record Dummy | Only with `RecordDemo = true` (see [Recording a demo](#recording-a-demo)). |

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
**`[Modes]`** switches each mode on (`1`) or off (`0`, `false`, `no`, `off`). A mode that is off is hidden from every menu, even when the screenpack's `system.def` lists it. When every mode of a family is off, the module doesn't read that family's files. A mode left out of `[Modes]` is on.

| Key | Mode |
|---|---|
| `Trials` | `trials` |
| `GameTutorial` | `tutorialgame` |
| `CharacterGuides` | `tutorialchars` |
| `Tutorial` | `tutorial` (combined) |

**`[Config]`** is set by hand; the pause menu never changes it. Characters are written the way `select.def` lists them (e.g. `kfm`). A character that isn't in `select.def` is still loaded, excluded from random selection, as the engine does for `TrainingChar`. A path that can't be loaded prints a warning and falls back to the select screen (character) or the default stage (stage).

| Key | Mode | Description |
|---|---|---|
| `TrialsChar` | Trials | A character always loaded as the dummy (P2). Blank: picked on the select screen. |
| `TrialsStage` | Trials | A stage always used (e.g. `stages/stage0.def`), even over a dummy's `stage` parameter in `select.def`. Blank: picked on the select screen. |
| `TutorialDummy` | tutorials | The dummy (P2). Blank: picked on the select screen, or a mirror of P1 in a Game Tutorial without one. Formerly `TutorialChar`, which is still read. |
| `TutorialPlayerChar` | Game Tutorial | The character P1 plays the game-wide lessons with. A lesson can override it with `playerchar`. Blank: picked on the select screen before the lesson list. |
| `TutorialStage` | tutorials | A stage always used. Blank: picked on the select screen. |
| `SystemTutorial` | tutorials | Game-wide lesson files, comma-separated, relative to the Ikemen folder. Blank: character lessons only. |
| `RecordDemo` | all | `true` adds Record Demo and Record Dummy to the pause menus. For authors; leave it `false` when shipping. |

These settings are independent of training mode's `TrainingChar` and `TrainingStage`.

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
| `hint.*`, `repcounter.*`, `demo.*`, `demoprompt.*` | The hint, the repetition counter, the DEMO banner (REC while recording) and the prompt pointing at Watch Demo. |
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
