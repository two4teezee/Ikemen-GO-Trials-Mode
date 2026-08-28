# Ikemen GO Trials Mode v0.99.5
> Compatible with Ikemen GO Nightly Builds newer than 10/10/2025.

> Note: for older Ikemen GO Builds, check releases tab for a compatible release of Trials Mode .

> Module developed by two4teezee
---
This external module offers a universal solution for Trials Mode. 
This markdown file is best viewed in Github or your favorite markdown file viewer. 
For greater detail on how to create trials definitions, or the customization options supported, please consult this readme, or [the wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki). 
You can find sample trials files for some of my favorite characters in [this repo](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).

## Installation
1. Extract archive content into "./external/mods/trials" directory
2. Add DEF code to your screenpack's `system.def`. 
Use the sample DEF code additions from this file to your `system.def`. 
The sample settings from this readme works with the `mugen1` screenpack included with the [base asset pack for Ikemen GO](https://github.com/ikemen-engine/Ikemen_GO-Elecbyte-Screenpack).
Note that `mugen1` was made for a 1280x720 resolution.
3. Add `external/mods/trials/trials.zss` to `States` under `[Common]` in "./save/config.ini".
4. Add sprites to system.sff, or alternatively, create a `trials.sff`, as required.
5. Add sounds to system.snd, as required.
6. Create new trials for your character(s). 
As a starting point, you can use the templates found in the trials mode readme to create a `trials.def` file and edit `kfmZ.def`, both in `"./chars/kfmZ"`. 
You can follow the instructions in the readme to create trials for any character you would like. 
I also often create new trials files for my favorite characters and am sharing them [here](https://github.com/two4teezee/Ikemen-GO-Sample-Trials-Definition-Files).
7. Share your trials definition files with others!

## General info
The Trials Mode provides new screenpack features and engine features so that creators can create trials for their character creations, and fully customize the way the trials are presented. 
The Trials Mode ships with several options for display of trials data inside the game mode, a variety of pause menu options to navigate the trials for each character, and the ability to apply palfx to character portraits in the Select Screen to easily convey which characters have valid Trials definition files.

## system.def Template and Customization
Using this external module allows full customization of the trials mode in `system.def`, with sprites in `system.sff` or in `trials.sff`, if so desired. 
If you are using `trials.sff`, make sure you point to it in the system.def's [Files] section as `trialsbgdef = trials.sff`.

The universal trials mode supports **vertical** trials readouts, and **horizontal** readouts as seen in KOF XIV, among other games. 
The sample `system.def` included in this file can be configured to support either or both layouts, but shared in this readme, it should work "out of the box" with the `mugen1` screenpack found [here](https://github.com/ikemen-engine/Ikemen_GO-Elecbyte-Screenpack). 
Below you'll find a brief summary of screenpack features supported by trials mode. 
For more detail, please consult the example `system.def` templates provided in this file for both vertical and horizontal layouts.
The [Trials Mode wiki](https://github.com/two4teezee/Ikemen-GO-Trials-Mode/wiki) goes into great depth on all supported features.

## system.def Example

```
[Trials Mode]
; NOTE: Values provided in this sample meant for `mugen1` screenpack, 1280x720 resolution.
;
; GENERAL TRIALS OPTIONS ---------------------------------------------------
; Reset on Success and Layout are no longer screenpack settings. They are Player
; Preferences: the player changes them from the trials pause menu and the module writes
; them to its own external/mods/trials/config.ini, under [Options] as
; Trials.ResetOnSuccess and Trials.Layout. A screenpack that still sets
; trialsresetonsuccess or trialslayout here is ignored — a value the player owns cannot
; also be authored, or neither side can tell who won.
;
; The fade that accompanies a reposition IS still a screenpack setting: fadeout.time,
; fadeout.col, fadein.time, fadein.col, further down.
; --------------------------------------------------------------------------

; SELSCREENPALFX -----------------------------------------------------------
; Sets specified palfx color to character portraits WITHOUT trials files in the trials select screen. See definition for palfx for different fields and options.
; --------------------------------------------------------------------------
selscreenpalfx.color = 0
; selscreenpalfx.invertall = 0
; selscreenpalfx.sinadd = 0, 0, 0, 0
selscreenpalfx.mul = 100, 100, 100
; selscreenpalfx.add = 0, 0, 0

; RESETONSUCCESS FADES -----------------------------------------------------
; Used when "trialsresetonsuccess" is set to "true"
; --------------------------------------------------------------------------
; fadein.time = 40
; fadein.col = {0, 0, 0}
; fadein.anim = -1
; fadeout.time = 40
; fadeout.col = {0, 0, 0}
; fadeout.anim = -1

; TRIALTITLE OPTIONS -------------------------------------------------------
; TRAILTITLE options can be specified for both vertical and horizontal layouts simultaneously.
; TRIALTITLE VERTICAL ------------------------------------------------------
trialtitle.vertical.pos = 140,140
trialtitle.vertical.text.offset = 0,-17
trialtitle.vertical.text.font = 2,0,1, 255, 200, 100
; trialtitle.vertical.text.text = "Trial: %s"
; trialtitle.vertical.text.scale = 
; trialtitle.vertical.text.font.height =
; trialtitle.vertical.bg.offset = 
; trialtitle.vertical.bg.spr = 
; trialtitle.vertical.bg.anim = 
; trialtitle.vertical.bg.scale = 
; trialtitle.vertical.bg.facing = 
; trialtitle.vertical.bg.displaytime = 
; trialtitle.vertical.front.offset = 
; trialtitle.vertical.front.spr = 
; trialtitle.vertical.front.anim = 
; trialtitle.vertical.front.scale = 
; trialtitle.vertical.front.facing = 
; trialtitle.vertical.front.displaytime = 
; TRIALTITLE HORIZONTAL ----------------------------------------------------
trialtitle.horizontal.pos = 140,140
trialtitle.horizontal.text.offset = 0,-17
trialtitle.horizontal.text.font = 2,0,1, 255, 200, 100
; trialtitle.horizontal.text.text = "Trial: %s"
; trialtitle.horizontal.text.scale = 
; trialtitle.horizontal.text.font.height =
; trialtitle.horizontal.bg.offset =
; trialtitle.horizontal.bg.spr = 
; trialtitle.horizontal.bg.anim =
; trialtitle.horizontal.bg.scale = 
; trialtitle.horizontal.bg.facing = 
; trialtitle.horizontal.bg.displaytime = 
; trialtitle.horizontal.front.offset = 
; trialtitle.horizontal.front.spr = 
; trialtitle.horizontal.front.anim = 
; trialtitle.horizontal.front.scale = 
; trialtitle.horizontal.front.facing = 
; trialtitle.horizontal.front.displaytime = 

; TRIALSTEPS OPTIONS -------------------------------------------------------
; TRIALSTEPS options can be specified for both vertical and horizontal layouts simultaneously.
; trialsteps.<layout>.pos: local origin from which trial steps are drawn. Other elements have their own origin specifications.
; trialsteps.<layout>.spacing: spacing between trial steps. For horizontal layout, the second argument determines the spacing between rows.
; trialsteps.<layout>.window: X1,Y1,X2,Y2: display window for trials--will create automated scrolling or line returns, depending on the trial layout of choice
; trialsteps.horizontal.padding: horizontal layouts only - padding between glyphs and edges of the background element along the x (horizontal) axis.
; trialsteps.<layout>.bg. ...: optional background displayed behind all other trial step text, background elements, etc.
; TRIALSTEPS VERTICAL ------------------------------------------------------
trialsteps.vertical.pos = 140,150
trialsteps.vertical.spacing = 0,25
trialsteps.vertical.window = 100,175, 1180,550
trialsteps.vertical.window.withtextbox = 100,175, 1180,550
; trialsteps.vertical.bg.offset = 
; trialsteps.vertical.bg.spr = 
; trialsteps.vertical.bg.anim = 
; trialsteps.vertical.bg.scale = 
; trialsteps.vertical.bg.facing = 
; trialsteps.vertical.bg.displaytime =   
; TRIALSTEPS HORIZONTAL ----------------------------------------------------
trialsteps.horizontal.pos = 140,175
trialsteps.horizontal.spacing = 1,40
trialsteps.horizontal.window = 100,175, 1180,550
trialsteps.horizontal.window.withtextbox = 100,175, 780,550
trialsteps.horizontal.padding = 10
; trialsteps.horizontal.bg.offset = 
; trialsteps.horizontal.bg.spr = 
; trialsteps.horizontal.bg.anim = 
; trialsteps.horizontal.bg.scale = 
; trialsteps.horizontal.bg.facing = 
; trialsteps.horizontal.bg.displaytime =  

; UPCOMINGSTEP -------------------------------------------------------------
; UPCOMINGSTEP options can be specified for both vertical and horizontal layouts simultaneously.
; UPCOMINGSTEP VERTICAL ----------------------------------------------------
upcomingstep.vertical.text.offset = 0,0
upcomingstep.vertical.text.font = 2,0,1, 200, 200, 200
; upcomingstep.vertical.text.scale = 
; upcomingstep.vertical.bg.offset = 
; upcomingstep.vertical.bg.anim = 
; upcomingstep.vertical.bg.spr = 
; upcomingstep.vertical.bg.scale = 
; upcomingstep.vertical.bg.facing =
; upcomingstep.vertical.bg.displaytime = 
upcomingstep.vertical.bg.palfx.color = 200
; upcomingstep.vertical.bg.palfx.invertall = 0
; upcomingstep.vertical.bg.palfx.sinadd = 0, 0, 0, 0
upcomingstep.vertical.bg.palfx.mul = 200, 200, 200
; upcomingstep.vertical.bg.palfx.add = 0, 0, 0
; upcomingstep.vertical.glyphs.palfx.color = 256
; upcomingstep.vertical.glyphs.palfx.invertall = 0
; upcomingstep.vertical.glyphs.palfx.sinadd = 0, 0, 0, 0
; upcomingstep.vertical.glyphs.palfx.mul = 0, 0, 0
; upcomingstep.vertical.glyphs.palfx.add = 0, 0, 0
; UPCOMINGSTEP HORIZONTAL --------------------------------------------------
; upcomingstep.horizontal.bg.offset =
; upcomingstep.horizontal.bg.anim = 
; upcomingstep.horizontal.bg.spr =
; upcomingstep.horizontal.bg.scale = 
; upcomingstep.horizontal.bg.facing = 
; upcomingstep.horizontal.bg.displaytime = 
upcomingstep.horizontal.bg.tail.offset = 0,-14
; upcomingstep.horizontal.bg.tail.anim = 
upcomingstep.horizontal.bg.tail.spr = 402,0
; upcomingstep.horizontal.bg.tail.scale = 
; upcomingstep.horizontal.bg.tail.facing = 
; upcomingstep.horizontal.bg.tail.displaytime = 
; upcomingstep.horizontal.bg.head.offset = 
; upcomingstep.horizontal.bg.head.anim = 
; upcomingstep.horizontal.bg.head.spr = 
; upcomingstep.horizontal.bg.head.scale = 
; upcomingstep.horizontal.bg.head.facing = 
; upcomingstep.horizontal.bg.head.displaytime = 
upcomingstep.horizontal.bg.palfx.color = 200
; upcomingstep.horizontal.bg.palfx.invertall = 
; upcomingstep.horizontal.bg.palfx.sinadd = 
upcomingstep.horizontal.bg.palfx.mul = 200, 200, 200
; upcomingstep.horizontal.bg.palfx.add =
upcomingstep.horizontal.glyphs.palfx.color = 200
; upcomingstep.horizontal.glyphs.palfx.invertall = 
; upcomingstep.horizontal.glyphs.palfx.sinadd =
upcomingstep.horizontal.glyphs.palfx.mul = 200, 200, 200
; upcomingstep.horizontal.glyphs.palfx.add = 


; CURRENTSTEP --------------------------------------------------------------
; CURRENTSTEP options can be specified for both vertical and horizontal layouts simultaneously.
; CURRENTSTEP VERTICAL -----------------------------------------------------
currentstep.vertical.text.offset = 0,0
currentstep.vertical.text.font = 2,0,1
; currentstep.vertical.text.scale = 
; currentstep.vertical.text.font.height = 
; currentstep.vertical.bg.offset = 
; currentstep.vertical.bg.anim = 
; currentstep.vertical.bg.spr = 
; currentstep.vertical.bg.scale = 
; currentstep.vertical.bg.facing = 
; currentstep.vertical.bg.displaytime = 
; currentstep.vertical.bg.displaytime = 
; currentstep.vertical.bg.palfx.color = 
; currentstep.vertical.bg.palfx.invertall = 
; currentstep.vertical.bg.palfx.sinadd = 
; currentstep.vertical.bg.palfx.mul = 
; currentstep.vertical.bg.palfx.add = 
; currentstep.vertical.glyphs.palfx.color = 
; currentstep.vertical.glyphs.palfx.invertall = 
; currentstep.vertical.glyphs.palfx.sinadd = 
; currentstep.vertical.glyphs.palfx.mul = 
; currentstep.vertical.glyphs.palfx.add = 
; CURRENTSTEP HORIZONTAL ---------------------------------------------------
; currentstep.horizontal.bg.offset = 
; currentstep.horizontal.bg.anim = 
; currentstep.horizontal.bg.spr = 
; currentstep.horizontal.bg.scale = 
; currentstep.horizontal.bg.facing = 
; currentstep.horizontal.bg.displaytime = 
currentstep.horizontal.bg.tail.offset = 0,-14
; currentstep.horizontal.bg.tail.anim = 
currentstep.horizontal.bg.tail.spr = 402,0
; currentstep.horizontal.bg.tail.scale = 
; currentstep.horizontal.bg.tail.facing = 
; currentstep.horizontal.bg.tail.displaytime = 
; currentstep.horizontal.bg.head.offset = 
; currentstep.horizontal.bg.head.anim = 
; currentstep.horizontal.bg.head.spr = 
; currentstep.horizontal.bg.head.scale = 
; currentstep.horizontal.bg.head.facing = 
; currentstep.horizontal.bg.head.displaytime = 
currentstep.horizontal.bg.palfx.color = 200
; currentstep.horizontal.bg.palfx.invertall = 
; currentstep.horizontal.bg.palfx.sinadd = 
currentstep.horizontal.bg.palfx.mul = 255, 255, 50
; currentstep.horizontal.bg.palfx.add = 
; currentstep.horizontal.glyphs.palfx.color = 
; currentstep.horizontal.glyphs.palfx.invertall = 
; currentstep.horizontal.glyphs.palfx.sinadd = 
; currentstep.horizontal.glyphs.palfx.mul = 
; currentstep.horizontal.glyphs.palfx.add = 

; COMPLETEDSTEP -------------------------------------------------------------
; COMPLETEDSTEP options can be specified for both vertical and horizontal layouts simultaneously.
; COMPLETEDSTEP VERTICAL ----------------------------------------------------
completedstep.vertical.text.offset = 0,0
completedstep.vertical.text.font = 2,0,1, 100, 100, 100
; completedstep.vertical.text.scale = 
; completedstep.vertical.text.font.height = 
; completedstep.vertical.bg.offset = 
; completedstep.vertical.bg.anim = 
; completedstep.vertical.bg.spr = 
; completedstep.vertical.bg.scale = 
; completedstep.vertical.bg.facing =
; completedstep.vertical.bg.displaytime = 
; completedstep.vertical.bg.palfx.color = 
; completedstep.vertical.bg.palfx.invertall = 
; completedstep.vertical.bg.palfx.sinadd = 
; completedstep.vertical.bg.palfx.mul = 
; completedstep.vertical.bg.palfx.add = 
completedstep.vertical.glyphs.palfx.color = 0
; completedstep.vertical.glyphs.palfx.invertall = 
; completedstep.vertical.glyphs.palfx.sinadd = 
; completedstep.vertical.glyphs.palfx.mul = 
; completedstep.vertical.glyphs.palfx.add = 
; COMPLETEDSTEP HORIZONTAL  --------------------------------------------------
; completedstep.horizontal.bg.offset =
; completedstep.horizontal.bg.anim = 
; completedstep.horizontal.bg.spr = 
; completedstep.horizontal.bg.scale = 
; completedstep.horizontal.bg.facing = 
; completedstep.horizontal.bg.displaytime = 
completedstep.horizontal.bg.tail.offset = 0,-14
; completedstep.horizontal.bg.tail.anim = 
completedstep.horizontal.bg.tail.spr = 402,0
; completedstep.horizontal.bg.tail.scale =
; completedstep.horizontal.bg.tail.facing = 
; completedstep.horizontal.bg.tail.displaytime = 
; completedstep.horizontal.bg.head.offset = 
; completedstep.horizontal.bg.head.anim = 
; completedstep.horizontal.bg.head.spr = 
; completedstep.horizontal.bg.head.scale = 
; completedstep.horizontal.bg.head.facing = 
; completedstep.horizontal.bg.head.displaytime = 
completedstep.horizontal.bg.palfx.color = 0
; completedstep.horizontal.bg.palfx.invertall = 
; completedstep.horizontal.bg.palfx.sinadd = 
completedstep.horizontal.bg.palfx.mul = 100, 100, 100
; completedstep.horizontal.bg.palfx.add = 
completedstep.horizontal.glyphs.palfx.color = 0
; completedstep.horizontal.glyphs.palfx.invertall = 
; completedstep.horizontal.glyphs.palfx.sinadd =
completedstep.horizontal.glyphs.palfx.mul = 100, 100, 100
; completedstep.horizontal.glyphs.palfx.add = 

; GLYPHS -------------------------------------------------------------------
; GLYPHS options can be specified for both vertical and horizontal layouts simultaneously.
; glyphs.<layout>.offset: x,y offset of the glyph run. In the vertical layout it is measured
;   from trialsteps.vertical.pos, so the run forms a column beside text of varying length. In
;   the horizontal layout a step sits wherever the flow put it, so it is measured from the end
;   of that step's own text and is also what separates the two.
; glyphs.<layout>.scale: x,y MULTIPLIER, not a size. A glyph is sized from the font height and
;   text scale of the step status drawing it - the same way the engine sizes movelist glyphs -
;   and this is applied on top. The old scalewithtext key is gone - glyphs always scale with
;   the text now, which is what scalewithtext = true used to ask for. An existing screenpack
;   that set an absolute scale alongside scalewithtext = false (e.g. 0.3125) should set it to
;   1,1, or its glyphs will come out at a third of the text height.
; glyphs.<layout>.spacing: gap between one glyph and the next. First argument only; a run is a
;   row, so a vertical gap between glyphs means nothing.
; glyphs.vertical.align: 1 grows the run right from its anchor, -1 ends it there, 0 centres
;   it on it. Vertical only, as before - aligning against an anchor only means something
;   where the anchor stands still. A horizontal run is anchored at the end of its own step's
;   text and always grows right from there.
; glyphs.<layout>.layerno, glyphs.<layout>.localcoord: as on any other element.
; <status>step.<layout>.glyphs.palfx.<color|mul|add|sinadd|invertall>: how each step status
;   styles the glyphs beside its text, so upcoming, current and completed read apart as icons
;   as well as words.
; A step declaring no glyphs draws as text alone, with no gap reserved for them, and a token
; this screenpack has no glyph for is skipped rather than drawn.
; GLYPHS VERTICAL ----------------------------------------------------------
glyphs.vertical.offset = 244,3
glyphs.vertical.scale = 1,1
glyphs.vertical.spacing = 4,0
glyphs.vertical.align = -1
; GLYPHS HORIZONTAL --------------------------------------------------------
glyphs.horizontal.offset = 12,-3
glyphs.horizontal.scale = 1,1
glyphs.horizontal.spacing = 4,0

; TRIALS COUNTER AND TIMERS ------------------------------------------------
; trialcounter shows the current trial number
; totaltrialtimer shows the total time for the trial. It is erased if the pause menu is used to skip or rewind.
; currenttrialtimer shows the time spent on the current trial attempt.
; --------------------------------------------------------------------------
trialcounter.pos = 10,690
trialcounter.font = 1,0,1
trialcounter.scale = 2,2
; trialcounter.font.height	=
trialcounter.text = "Trial %s of %t"
trialcounter.allclear.text = "All Trials Clear"
trialcounter.notrialsdata.text = "No Trials Data Found"
totaltrialtimer.pos	= 1270,690
totaltrialtimer.font = 1,0,-1
totaltrialtimer.scale = 2,2
; totaltrialtimer.font.height =
totaltrialtimer.text = "Trial Timer: %s"
currenttrialtimer.pos = 1270,710
currenttrialtimer.font = 1,0,-1
currenttrialtimer.scale = 2,2
; currenttrialtimer.font.height	=
currenttrialtimer.text = "Current Trial: %s"

; REPOSITIONING ------------------------------------------------------------
; A trial places the player and the dummy where trial.playerpos and trial.dummypos ask for when that trial starts. Two things soften and extend that:
;
; fadeout / fadein wrap the move, so the pair arriving in position is a cut rather than a teleport. The screen fades out, the characters are placed while it is dark, and it fades back in. This runs when the player moves between trials and when the key combination below is held - never on the first placement of a round, which the round's own fade already covers. Set both times to 0 for an instant cut. col is r, g, b.
;
; trialresetenabled allows the player to put both characters back where the current trial wants them, mid-trial, after a combo has carried them across the stage. A trial that names no playerpos or dummypos still has somewhere to go back to - the stage's own start positions, which is where the engine puts the pair when the round begins - so this is worth offering on every trial and not only the ones that ask for a corner. Set it to false and the keys do nothing and the reminder is not drawn.
;
; trialresetkeys is the combination that does it, spelled in the engine's own input names: B D F U L R (directions), a b c x y z s (buttons), d w m. Any number of them; all must be held at once. An unrecognised name is dropped with a warning rather than arming a combination the player can never complete.
;
; trialresetreminder is the on-screen reminder of that combination. Keep its text in step with trialresetkeys yourself - nothing derives one from the other. Leave the text empty and nothing is drawn.
; --------------------------------------------------------------------------
fadeout.time = 12
fadeout.col = 0,0,0
fadein.time = 12
fadein.col = 0,0,0
trialresetenabled = true
trialresetkeys = d, w
trialresetreminder.pos = 10,710
trialresetreminder.font = 1,0,1
trialresetreminder.scale = 2,2
; trialresetreminder.font.height	=
trialresetreminder.text = "Hit d + w to reset position"

; TRIALS TEXT BOX ----------------------------------------------------------
; A textbox can accompany each trial if it is specified within the trials definition file.
; The only element defined within the trials definition file is the text to be displayed for that trial.
; textbox.pos: local origin from which other textbox elements are drawn. 
; textbox.text.<options>: specify text window, offset, font type, and drawspeed
; textbox.title.<options>: specify text, offset, font type, scale
; textbox.overlay.<options>: draw an overlay behind any other bg, text or front element
; textbox.bg.<options>: optional background displayed behind text but over overlay; standard options for background elements, etc.
; textbox.front.<options>: optional background displayed in front of text; standard options for background elements, etc.
; textbox.portrait.<options>: allows a portrait to be drawn with or in the textbox. Sprite can be sourced from the character or the screenpack.
; --------------------------------------------------------------------------
textbox.visible = true
textbox.pos = 740,120
textbox.text.window = 50,0, 300,50
textbox.text.offset = 10,10
textbox.text.font = 1,0,1
textbox.text.drawspeed = 2
; textbox.text.font.height = -1
textbox.text.scale = 2,2
textbox.title.offset = 0,0
textbox.title.font = 2,0,1
textbox.title.text = ;%s is  trial number, %n is trial name
; textbox.title.font.height = -1
textbox.title.scale = 1,1
textbox.overlay.visible = true
textbox.overlay.window = 0,0, 350,50
textbox.overlay.col = 0, 0, 0
textbox.overlay.alpha = 0, 128
textbox.bg.anim = -1
textbox.bg.spr = 
textbox.bg.offset = 0, 0
textbox.bg.facing = 1
textbox.bg.scale = 1.0, 1.0
textbox.bg.displaytime = -1
textbox.front.anim = -1
textbox.front.spr = 
textbox.front.offset = 0, 0
textbox.front.facing = 1
textbox.front.scale = 1.0, 1.0
textbox.front.displaytime = -1
textbox.portrait.source = "char" ; valid options are "system" or "char"
textbox.portrait.spr = 9000, 0
textbox.portrait.offset = 5,5
textbox.portrait.window = 0,0, 40, 40
textbox.portrait.facing = 1
textbox.portrait.scale = 0.5, 0.5

; TRIAL SUCCESS BANNER -----------------------------------------------------
; --------------------------------------------------------------------------
success.pos	= 640,360
success.snd	= 600,0 
success.text.text = "SUCCESS"
success.text.offset = 0,0
success.text.font = 4,0,0, 255, 100, 100
success.text.displaytime = 70
success.text.scale = 3,3
; success.text.font.height =
; success.bg.offset = 
; success.bg.anim = 
; success.bg.scale = 
; success.bg.spr = 
; success.bg.displaytime = 
; success.front.offset = 
; success.front.anim = 
; success.front.scale = 
; success.front.spr = 
; success.front.displaytime	= 

; TRIALS ALL CLEAR BANNER --------------------------------------------------
; --------------------------------------------------------------------------
allclear.pos = 640,360
allclear.snd = 900,0
allclear.text.text = "ALL CLEAR"
allclear.text.offset = 0,0
allclear.text.font = 4,0,0, 255, 100, 100
allclear.text.displaytime	= 70
allclear.text.scale	= 3,3
; allclear.text.font.height	=
; allclear.bg.offset = 
; allclear.bg.anim = 
; allclear.bg.scale = 
; allclear.bg.spr = 
; allclear.bg.displaytime = 
; allclear.front.offset = 
; allclear.front.anim = 
; allclear.front.scale = 
; allclear.front.spr = 
; allclear.front.displaytime = 

[Trials Pause Menu]
; RENAMED. This section was [Trials Info] before the rebuild, and that is the one
; breaking change in the whole refactor. The engine turns any system.def section
; matching ^(?i).*pause.*menu$ into a pause menu and resolves which one to open from
; the game mode's name, so [Trials Pause Menu] is a pause menu the engine registers by
; itself and [Trials Info] is not.
;
; A screenpack that still ships [Trials Info] keeps working: the module reads it and
; folds it into this section, warning once on the console. That compatibility goes away
; in a later release — rename the section.
;
; Everything this section does not define is topped up from the screenpack's own
; [Pause Menu], so a menu that only wants to reorder the items writes only itemnames.
;
; Trials specific parameters:
menu.valuename.trialadvancement_autoadvance = "Auto-Advance"
menu.valuename.trialadvancement_repeat = "Repeat"
menu.valuename.trialresetonsuccess_enabled = "Yes"
menu.valuename.trialresetonsuccess_disabled = "No"
menu.valuename.trialslayout_vertical = "Vertical"
menu.valuename.trialslayout_horizontal = "Horizontal"
menu.valuename.trialstextboxes_show = "Show"
menu.valuename.trialstextboxes_hide = "Hide"

; https://github.com/ikemen-engine/Ikemen-GO/wiki/Screenpack-features#submenus
; If a custom menu is not declared, the module's own is loaded:
; menu.itemname.back = "Continue"
; menu.itemname.trialslist = "Trials"
; menu.itemname.trialslist.back = "Back"
; menu.itemname.trialadvancement = "Advancement"
; menu.itemname.trialresetonsuccess = "Reset on Success"
; menu.itemname.trialslayout = "Layout"
; menu.itemname.trialstextboxes = "Textboxes"
; menu.itemname.menuinput = "Button Config"
; menu.itemname.menuinput.keyboard = "Key Config"
; menu.itemname.menuinput.gamepad = "Joystick Config"
; menu.itemname.menuinput.spacer = "-"
; menu.itemname.menuinput.inputdefault = "Default"
; menu.itemname.menuinput.back = "Back"
; menu.itemname.commandlist = "Command List"
; menu.itemname.characterchange = "Character Change"
; menu.itemname.exit = "Exit"
;
; Two more items exist but are not shipped, because the trials list replaces them:
; menu.itemname.nexttrial = "Next Trial"
; menu.itemname.previoustrial = "Previous Trial"
;
; The trials list is filled in per character when the match starts, so its entries are
; never authored. It keeps whatever items the section declares under it — the Back
; above — underneath the Trials, and a character shipping none leaves those alone.
;
; DO NOT add a dummy submenu (dummy control, guard mode, dummy mode, fall recovery,
; distance, button jam). Dummy behaviour is prescribed by the Trial Definition so that
; a Trial plays the same way for everyone, and the engine only initialises those items
; under gameMode('training') — cycling Dummy Control in a Trials match raises
; "Argument 1 is not a number" from setAILevel.

; The pause menu's background. Optional: leave it out and the screenpack's own
; [PauseBgDef] is used.
; [TrialsPauseBgDef]

[TrialsBgDef]
spr 			= ""
bgclearcolor 	= 0, 0, 0
```

## Creating a Character's Trials Definition File

Trials data is created on a per-character basis. To specify new trials for a character, you'll want to create a new file in the character's folder to hold the trials data. For the purposes of this tutorial, I name this file `trials.def`, but you can call it whatever you want. As mentioned before, each character gets its own `trials.def`. You can specify as many trials as you want, in any order you want.

A sample `trials.def` for kfmZ is provided below. The trials are presented to the player in the order in which they are listed in `trials.def`. Detailed information for each configurable parameter can be found in this template.

```
; KFMZ TRIALS LIST ---------------------------

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
; trialstep.1.hitcount =
; trialstep.1.isthrow =
; trialstep.1.iscounterhit =
; trialstep.1.ishelper =
; trialstep.1.isproj =
; trialstep.1.validforvarvalpairs = 
; trialstep.1.validfortickcount = 

; TrialDef Parameter Descriptions
; ===============================
; [TriafDef, TrialTitle] - [TrialDef] mandatory - trial title after the comma is optional.

; trial.dummymode - optional - valid options are stand (default), crouch, jump, wjump. Defaults to stand if unspecified.
; trial.guardmode - optional - valid options are none, auto. Defaults to none if unspecified.
; trial.dummybuttonjam - optional - valid options are none, a, b, c, x, y, z, start, d, w. Defaults to none if unspecified.
; trial.dummylife - optional - (whole number of life points). Sets the dummy's life total. Life recovery holds it there rather than refilling to the character's maximum. Defaults to the character's maximum.
; trial.playerlife - optional - (whole number of life points). Sets the player's life total. Useful for trials that involve desparation moves or require a specific life state. Defaults to the character's maximum.
; trial.dummypos - optional - sets where the dummy starts. Valid options are left-corner, right-corner, far, medium, close. Defaults to the stage's own start positions.
; trial.playerpos - optional - sets where the player starts. Same five options.
;
;   The two keys are read separately, and the five words split into two kinds:
;
;   * left-corner and right-corner are places, and belong to the character whose key named them. Only one character can stand in a corner - a trial naming two keeps the dummy's and warns about the other.
;   * close, medium and far are distances, and describe the gap between the two characters rather than either one's position. Either key may name one and it means the same thing. Two different distances keep the dummy's and warn about the other.
;
;   So `trial.dummypos = left-corner` puts the dummy in the left corner with the player a medium gap away, and adding `trial.playerpos = far` widens that gap without moving anyone out of the corner. A distance on its own, with no corner named, starts the pair that far apart around centre stage.
;
;   Positions and life totals are applied when the trial starts, and re-applied when the player moves to another trial or the round restarts. A trial that names none of them gets the stage's own start positions and full life, never the previous trial's.
;
;   Mid-trial, the player can put both characters back where the trial wants them by holding the key combination the screenpack sets as trialresetkeys - see REPOSITIONING in the system.def section above.
; trial.showforvarvalpairs - optional - (comma-separated integers, specified in pairs, can specify 0..n pairs). Used to determine whether a trial should be displayed based on the specified variable and value pair(s) in this field. Useful if a trial should only be displayed when character has a specific variable/value pair set, such as being in a specific groove or mode. If specified, the trial will only be displayed if all variable-value pairs return true. These variable-value pairs should only be for the character (not for helpers). Finally, variables can have multiple specified values to test against, which should be separated by the "|" character (e.g. `trial.showforvarvalpairs = 12, 0|2|4` would test var(12) for values 0, 2, and 4).
;
;   A trial that is not displayed is not offered at all: it is not counted by the trial counter, not reached by advancement, and not part of all-clear - exactly as if the character did not ship it. A character whose every trial is gated out shows the same no-data message as a character shipping no trials file.
;
;   The pairs are read ONCE PER ROUND, on the first frame after the round state resets. A character whose mode variable changes mid-round keeps the trials it started the round with; restarting the round picks up the new mode. This is what the pre-refactor version did, and it is why a trial the player is part-way through can never disappear underneath them.
; trial.textbox - optional - multilingual - displays specified text in a box specified in the textbox settings in system.def under [Trials Mode]. Supports specification as trial.textbox, or trial.textbox.en, trial.textbox.es, etc. for multilingual support. Will default to trial.textbox.en (or trial.textbox) if selected language cannot be matched.
;
; TWO WAYS TO SPELL A LANGUAGE, and they are not interchangeable. This file — a
; character's Trials Definition — spells one as a KEY SUFFIX:
;
;   trial.textbox.es = Este es un cuadro de texto en español.
;   trialstep.1.text.es = Rodillazo + patada extra
;
; A screenpack's system.def spells one as a SECTION PREFIX instead, which is the
; engine's own convention for motif sections:
;
;   [ES.Trials Mode]
;   trialcounter.text = "Prueba %i de %s"
;
; Both are intended. The two files are read by different parsers: a Trials Definition is
; read key by key by this module, while system.def sections follow the engine. Resolution
; is the same either way — the selected language, then en, then the unsuffixed or
; unprefixed form.

; The options above are defined once per trial. The other parameters can be defined for each trial step - notice the syntax, where X is the trial number.

; trialstep.X.text - optional - multilingual - (string). Text for trial step (only displayed in vertical trials layout). Supports specification as trialstep.X.text, or trialstep.X.text.en, trialstep.X.text.es, etc. for multilingual support. Will default to trialstep.X.text.en (or trialstep.X.text) if selected language cannot be matched.
; trialstep.X.glyphs - optional - (string, see Glyph documentation [https://github.com/ikemen-engine/Ikemen-GO/wiki/Miscellaneous-info#movelists] for syntax). Same syntax as movelist glyphs. Glyphs are displayed in vertical and horizontal trials layouts.
; trialstep.X.stateno - mandatory - (integer or comma-separated integers). State to be checked to pass trial. This is the state whether it's the main character, a helper, or even a projectile.

; trialstep.X.animno - optional - (integer or comma-separated integers). Identifies animno to be checked to pass trial. Useful in certain cases.
; trialstep.X.hitcount - optional - (integer or comma-separated integers), will default to 1 if not defined. In some instances, you might want to specify a trial step to meet a hit count criteria before proceeding to the next trial step. Useful for multi-hit moves, or for moves that don't hit (e.g. taunts).
; trialstep.X.isthrow - optional - (true or false, or comma-separated true/false), will default to false if not defined. Identifies whether the trial step is a throw. Should be 'true' is trial step is a throw.
; trialstep.X.iscounterhit - optional - (true or false, or comma-separated true/false), will default to false if not defined. Identifies whether the trial step should be a counter hit. Typically does not work with helpers or projectiles.
; trialstep.X.ishelper - optional - (true or false, or comma-separated true/false), will default to false if not defined. Identifies whether the trial step is a helper. Should be 'true' is trial step is a hit from a helper.
; trialstep.X.isproj - optional - (true or false, or comma-separated true/false), will default to false if not defined. Identifies whether the trial step is a projectile. Should be 'true' is trial step is a hit from a projectile.
; trialstep.X.validforvarvalpairs - optional - (comma-separated integers, specified in pairs, can specify 0..n pairs). Sister functionality to "showforvarvalpairs". These variable-value pairs are used to optionally check a trial step. Useful if you are forcing the trial step to be completed when certain var-val pairs are met (for instance, while in a custom combo state). Variable-value pairs are considered valid for entire trial step (regardless if the trial step is specified using condensed terminology).
; trialstep.X.validfortickcount - optional (integer, or comma-separate integers), will default to nil if not defined. Makes the trials checking logic pause until the next hit is registered for the tickcount specified.

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
; stateno, animno, hitcount, isthrow, iscounterhit, ishelper, isproj
; If one parameter on the trial step is defined using comma separated values, all parameters on that trial step must be defined similarly.

;---------------------------------------------

[TrialDef, KFM Kung Fu Palm]
; In this trial, we use the "or" operand, specified by using the | character, to let the user specify multiple different stateno or animno for which the trialstep or microstep is valid.

trialstep.1.text = Kung Fu Palm
trialstep.1.glyphs = _QDF^P
trialstep.1.stateno = 1000|1010

;---------------------------------------------

[TrialDef, Kung Fu Juggle Combo]
; In this trial, the dummy starts in the right corner, with the player a medium gap away.
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

## Editing the Character's Def File

Finally, you'll want to modify the character's definition file so that Ikemen knows to read the trials data for that character. 
In the character's definition file (i.e. `kfmZ.def` for kfmZ), under `[Files]`, add the line `trials = trials.def`.

```
[Files]
trials = trials.def        ;Ikemen feature: Trials mode data
```

## Pause Menu Options

Pausing during a Trials match opens the trials pause menu. It is an engine-native pause
menu: the module ships a `[Trials Pause Menu]` section and the engine registers it,
which is why no screenpack edit is needed to get one. A screenpack customises it by
defining the same section in its own `system.def` — see the template above.

- **Trials**: the Trials the selected character ships. Picking one jumps to it, starts
  its progress over and places the pair at its authored positions.
- **Advancement**: Auto-Advance moves to the next Trial on Success; Repeat plays the
  same one again, so it can be drilled.
- **Reset on Success**: what a finished Trial does to where the two characters stand.
  On, completing one puts the pair back at the next Trial's authored positions, behind a
  fade. Off, the run carries straight on from wherever the combo ended — the next Trial
  begins in place, with no move and no fade between the two. It governs every Success:
  advancing, repeating the same Trial, and the All-Clear that finishes the set.
  It does **not** govern a reposition the player asks for. The mid-Trial key combination,
  and picking a Trial out of the **Trials** list above, place the pair either way.
- **Layout**: Vertical or Horizontal trials layout. The setting is live and persists;
  only the vertical layout is drawn today, so switching it changes nothing on screen
  until the horizontal one lands.
- **Textboxes**: whether a Trial's textbox is shown. Hiding it also gives the Steps
  their full-width window back, on the Trial already running.

Plus the engine's own Button Config, Command List, Character Change and Exit.

The four settings below **Trials** are Player Preferences: the module writes them back to
its own `external/mods/trials/config.ini` under `[Options]` the moment they are changed,
so they survive a restart. That file is rewritten whole, which keeps every value in it
and none of the comments — the copy in this repository is the documented one.

There is deliberately **no dummy submenu**. Dummy behaviour comes from the Trial
Definition and nowhere else, so a Trial plays the same way for everyone; a screenpack
that adds one will also hit a crash, because the engine initialises those items only
under `gameMode('training')`.