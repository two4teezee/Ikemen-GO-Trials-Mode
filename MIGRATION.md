# Migrating from Trials Mode to the Dojo Module

The Dojo Module replaces Trials Mode 1.x. Trials is still there, and works the way you're used to. It now sits beside two new modes, the Game Tutorial and Character Guides, which run on the same engine.

Most of what you already have carries over without changes:

- your characters' `trials.def` files;
- your saved clears and best times (`save/trials.json`);
- your `config.ini` settings;
- a customised `trialsmode.def`;
- a screenpack's own `[Trials Pause Menu]`.

What you do have to do is replace the module folder and copy a few files across. This guide covers that, and the few behaviour changes trial authors should know about.

## Contents
- [Quick checklist](#quick-checklist)
- [1. Remove the old module](#1-remove-the-old-module)
- [2. Install the Dojo](#2-install-the-dojo)
- [3. Carry over your settings](#3-carry-over-your-settings)
- [4. Carry over a customised look](#4-carry-over-a-customised-look)
- [5. Screenpacks: main menu and pause menu](#5-screenpacks-main-menu-and-pause-menu)
- [6. Trial authors: what changed in trials.def](#6-trial-authors-what-changed-in-trialsdef)
- [What stays the same](#what-stays-the-same)
- [Name changes at a glance](#name-changes-at-a-glance)
- [Troubleshooting](#troubleshooting)

## Quick checklist
1. Back up `external/mods/trials/`, then delete it.
2. Extract the Dojo into your Ikemen GO folder, so you have `external/mods/dojo/`.
3. Copy your `Trials.*`, `TrialsChar` and `TrialsStage` values from the old `config.ini` into the new one.
4. If you customised the look, copy your old `trialsmode.def` to `external/mods/dojo/dojo.def`, and your own `trials.sff` / `trials.snd` / `trials.air` to `dojo.sff` / `dojo.snd` / `dojo.air`.
5. Leave `save/trials.json` and your characters' `trials.def` files where they are.
6. Start the game and look at the console. The Dojo warns you there if the old folder is still installed.

## 1. Remove the old module
Delete `external/mods/trials/` before you install the Dojo. Back it up first if you've edited anything in it.

You can't keep both installed. Ikemen GO loads every module under `external/mods/`, and the two would register the same `trials` menu item and the same `[Trials Pause Menu]`. Whichever loads last would break the other. If the Dojo finds `external/mods/trials/trials.lua` at startup, it prints this warning:

```
Dojo: external/mods/trials/trials.lua is still installed; remove its folder, the Dojo replaces it.
```

The same applies to the standalone Tutorial Mode module (`external/mods/tutorial/`), if you had that too.

## 2. Install the Dojo
Extract the archive into your Ikemen GO folder. Everything lives in `external/mods/dojo/`:

| Trials Mode 1.x | Dojo | Notes |
|---|---|---|
| `trials.lua` | `dojo.lua` | The module itself. |
| `trials.zss` | `dojo.zss` | Loaded automatically. |
| `trialsmode.def` | `dojo.def` | The look of every mode. See [step 4](#4-carry-over-a-customised-look). |
| `trials.sff` | `dojo.sff` | The module's sprites. |
| `trials.snd`, `trials.air` (optional, not shipped) | `dojo.snd`, `dojo.air` | Still optional. |
| `+system.def` | `+system.def` | Now adds a **Dojo** submenu, not a single Trials Mode item. |
| `config.ini` | `config.ini` | Same keys, plus new ones for the tutorial modes. |
| | `gametutorial.lua`, `gametutorial.def` | New: the Game Tutorial and its sample lessons. |

By default the main menu gains a **Dojo** submenu holding Trials, Game Tutorial and Character Guides. If you only want Trials, switch the others off in `config.ini`:

```ini
[Modes]
Trials          = 1
GameTutorial    = 0
CharacterGuides = 0
Tutorial        = 0
```

A mode that's off is hidden from every menu, even if a screenpack lists it.

## 3. Carry over your settings
Use the new `config.ini` and copy your values into it. Don't drop the old file in its place: the old file lacks the new sections, such as `[Modes]` and `SystemTutorial`, so the Game Tutorial would have no lessons to offer.

Every Trials key kept its name:

| Section | Keys |
|---|---|
| `[Config]` | `TrialsChar`, `TrialsStage` |
| `[Options]` | `Trials.Advancement`, `Trials.Layout`, `Trials.ResetOnSuccess`, `Trials.Textboxes`, `Trials.TotalTimer`, `Trials.TrialTimer` |

There is one new Trials option, `Trials.Hints` (default `true`). It shows or hides a trial's hint, for trials that have one.

The module still rewrites `config.ini` when a player changes an option in the pause menu, and the comments are lost when it does. Keep a copy of the commented file if you want the legend.

## 4. Carry over a customised look
If you never edited `trialsmode.def` or `trials.sff`, skip this step. The shipped `dojo.def` and `dojo.sff` look the same as before.

### Quickest: drop your old file in
Copy your `trialsmode.def` to `external/mods/dojo/dojo.def`. It works as it is:

- An old file has no `[Dojo]` section, so its `[Trials Mode]` section is used as the look of **every** mode, the tutorials included.
- Every old key name is still read (`trialtitle`, `trialsteps`, `trialsmenu`, `trialcounter`, ...).

To give the tutorials their own labels, add a `[Tutorial Mode]` section at the end. Copy it from the shipped `dojo.def`, or write your own; it only needs the keys that differ.

Two things to check:

- **Sprites.** If you made your own `trials.sff`, rename it `dojo.sff`. The shipped `dojo.sff` has a narrower tail sprite for the horizontal step readout (6552,2: 9px wide, was 16px). If your layout was tuned to the old sprite, keep your own file.
- **Sounds and actions.** Rename a `trials.snd` to `dojo.snd`, and a `trials.air` to `dojo.air`.

### Recommended: move your changes into the new layout
The shipped `dojo.def` is split into three sections:

- **`[Dojo]`** is the look every mode shares. Positions, fonts, sprites, sounds and the list all go here.
- **`[Trials Mode]`** is laid over it for Trials. Shipped, it holds only the labels ("Trial: %s", "Trial %s of %t", ...).
- **`[Tutorial Mode]`** is laid over it for the Game Tutorial and Character Guides. It holds the "Lesson" labels.

To move across, take the keys you changed in your old file and put them in the matching place:

- Changes that should apply everywhere go into `[Dojo]`.
- Label text that should say "Trial" goes into `[Trials Mode]`.

A mode section only needs the keys that differ. A value there replaces the shared one, and a block (`title.vertical`, say) is merged key by key.

The shipped file also uses shorter, mode-neutral key names. You don't have to rename your keys, because the old names still work in any section. If you do use both spellings for the same setting in one section, the new name wins.

| Trials Mode 1.x key | Dojo key |
|---|---|
| `trialslocalcoord` | `localcoord` |
| `trialslistdisplay` | `listdisplay` |
| `trialtitle.*` | `title.*` |
| `trialsteps.*` | `steps.*` |
| `trialcounter.*` | `counter.*` |
| `trialcounter.notrialsdata.*` | `counter.nodata.*` |
| `totaltrialtimer.*` | `totaltimer.*` |
| `currenttrialtimer.*` | `currenttimer.*` |
| `trialreset.*` | `reset.*` |
| `trialsmenu.*` | `menu.*` |

Every other key (`upcomingstep`, `currentstep`, `completedstep`, `glyphs`, `textbox`, `success`, `allclear`, `selscreenpalfx`, `fadein`, `fadeout`) is unchanged.

The new file also has blocks your old one won't have, for the new features: `instructions`, `hint`, `demo`, `demoprompt`, `repcounter`, and the locked rows in the list. Without them, each feature falls back to built-in defaults when a trial uses it. Copy the blocks from the shipped `dojo.def` to style them for your screenpack.

## 5. Screenpacks: main menu and pause menu

### Main menu
Trials Mode 1.x added a single `menu.itemname.trials = "Trials Mode"` item. The Dojo's `+system.def` adds a submenu instead:

```ini
menu.itemname.dojo = "Dojo"
menu.itemname.dojo.trials = "Trials"
menu.itemname.dojo.tutorialgame = "Game Tutorial"
menu.itemname.dojo.tutorialchars = "Character Guides"
menu.itemname.dojo.back = "Back"
```

If your screenpack's own `system.def` already lists `menu.itemname.trials`, that line still works. In that case, comment out the Dojo lines in `+system.def`, or remove `trials` from the submenu, so Trials isn't listed twice. Any of the Dojo's items can stand at the top level or in another submenu.

### Pause menu
A screenpack's own `[Trials Pause Menu]` that uses the old itemnames keeps working. They're renamed when the module loads, and so are their `menu.valuename.*` labels:

| Old itemname | New itemname |
|---|---|
| `trialslist` | `tutoriallist` |
| `trialsopts` | `tutorialopts` |
| `trialsspeedrun` | `tutorialspeedrun` |
| `nexttrial` / `previoustrial` | `tutorialnext` / `tutorialprevious` |
| `trialadvancement` | `tutorialadvancement` |
| `trialresetonsuccess` | `tutorialresetonsuccess` |
| `trialslayout` | `tutoriallayout` |
| `trialstextboxes` | `tutorialtextboxes` |
| `trialsprogress` | `tutorialprogress` |
| `trialsclearcharprogress` / `trialsclearcharconfirm` | `tutorialclearcharprogress` / `tutorialclearcharconfirm` |
| `trialsclearprogress` / `trialsclearconfirm` | `tutorialclearprogress` / `tutorialclearconfirm` |
| `trialsdifficulty` | `tutorialdifficulty` |

An old section won't offer the new rows. To get them, use the shipped `[Trials Pause Menu]` in `+system.def`, or copy its lines into your own:

- **Show Instructions** (`tutorialinstructions`). It only appears for a trial that has instruction pages.
- **Watch Demo** (`tutorialdemo`). It only appears for a trial that has a demo, and never during a speedrun.
- **Hints** (`tutorialhints`), in the options submenu.
- **Record Demo / Record Dummy** (`tutorialrecord`, `tutorialrecorddummy`). They're authoring aids, only listed with `RecordDemo = true` in `config.ini`.

Rows that would do nothing for the current trial are hidden automatically. Shipping them in your section costs nothing.

## 6. Trial authors: what changed in trials.def
Existing `trials.def` files load as they are, and keep using the `trial.` and `trialstep.` prefixes. Trials now run on the same engine as the tutorials, though, so a few parsing rules are stricter or different:

- **Keys must be written in full.** Trials Mode used to accept any line that merely contained a key's name. A misspelt or abbreviated key is now ignored, so check the console for warnings.
- **A language suffix always wins.** If a step has both a plain and a language-suffixed version of its text, the suffixed one is now always used.
- **All `validforvarvalpairs` pairs are checked.** Trials Mode could ignore every pair after the first. A trial with several pairs might now be hidden where it used to show.
- **A hit step can follow a step that doesn't hit.** Before, such a step reset the trial to step 1 straight away, so a trial like "dash, then attack" couldn't be cleared. Combos that drop still reset exactly as before.
- **`guardmode` has two more values:** `afterhit` and `random`.

Trials can now also use everything the tutorials can. These are all optional, and a trial without them behaves as before:

- instruction pages shown before the trial starts (`trial.page.N.*`);
- a hint (`trial.hint`, `trial.hintafter`);
- a demo the CPU performs (`trial.demoscript`), and scripted dummy routines (`trial.dummyscript`);
- repetitions (`trial.repeat`);
- chapters (`trial.chapter`), alongside difficulties;
- trials that open one at a time (`tutorial.gated = true` in a `[Tutorial]` section of the file).

With `RecordDemo = true` in `config.ini`, Record Demo in the pause menu captures your inputs and prints a ready-to-paste `trial.demoscript = ...` line. See the README's [Writing trials and lessons](README.md#writing-trials-and-lessons) for the full reference.

## What stays the same
- **Progress.** `save/trials.json` keeps its layout and location. Clears and best times carry over, and the pause menu's progress options still clear only Trials progress. The tutorial modes keep theirs separately, in `save/tutorial.json`.
- **Characters.** The `trials = trials.def` line in a character's def file is unchanged.
- **Game mode.** Trials still runs as the `trials` game mode, so anything keyed on it keeps working, such as a character's `gameMode = "trials"` checks or a `[Trials Pause Menu]`.
- **Select screen title.** `title.trials.text` in `[Select Info]` is unchanged.

## Name changes at a glance

| What | Trials Mode 1.x | Dojo |
|---|---|---|
| Module folder | `external/mods/trials/` | `external/mods/dojo/` |
| UI def | `trialsmode.def`, `[Trials Mode]` | `dojo.def`: `[Dojo]` + `[Trials Mode]` + `[Tutorial Mode]` |
| Sprites / sounds / actions | `trials.sff` / `.snd` / `.air` | `dojo.sff` / `.snd` / `.air` |
| Main menu | `trials` item, top level | `dojo` submenu holding `trials`, `tutorialgame`, `tutorialchars` |
| Pause menu itemnames | `trialslist`, `trialsopts`, ... | `tutoriallist`, `tutorialopts`, ... (old ones still read) |
| Console messages | | Prefixed `Dojo:` |

The game mode (`trials`), save file (`save/trials.json`), config keys (`TrialsChar`, `TrialsStage`, `Trials.*`), char def key (`trials =`) and pause section (`[Trials Pause Menu]`) are unchanged.

## Troubleshooting
- **Trials is listed twice, or the menu misbehaves.** The old `external/mods/trials/` folder is probably still installed; delete it. Or your screenpack lists `trials` itself as well as the Dojo submenu; see [Main menu](#main-menu).
- **The Game Tutorial says there are no lessons.** `SystemTutorial` is missing from `config.ini`, probably because an old config file was copied over the new one. Set it back to `SystemTutorial = external/mods/dojo/gametutorial.def`.
- **My custom look is gone.** The Dojo reads `dojo.def`, not `trialsmode.def`. Copy yours across under the new name (see [step 4](#4-carry-over-a-customised-look)).
- **The tutorials use my Trials labels.** Your `dojo.def` is an old `trialsmode.def`, so its `[Trials Mode]` is the shared look. Add a `[Tutorial Mode]` section with the lesson labels, copied from the shipped `dojo.def`.
- **A trial that used to work no longer clears or no longer shows.** Check the console for warnings, then see [step 6](#6-trial-authors-what-changed-in-trialsdef). An abbreviated key, or a second `validforvarvalpairs` pair that doesn't match, are the usual causes.
