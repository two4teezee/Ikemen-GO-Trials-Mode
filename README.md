# Ikemen GO Universal Trials Mode
> Last tested on Ikemen GO v0.99 and Nightly Build (02/10/2024).

> Note: for Ikemen GO Night Builds older than 12/27/2024, use Trials Mode v0.99 (check releases tab).

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
Below you'll find a brief summary of screenpack features supported by trials mode. For more detail, please consult the example `system.def` templates provided in this file for both vertical and horizontal layouts.

You can make the trials mode look as fancy or as basic as you want. 
The `system.def` trials mode example included in this readme only leverage "stock" Ikemen fonts and sprites in the most minimal way possible.

- A window must be specified in which the trial steps are drawn. This feature enables long trial lists that need to scroll (for vertical layouts) or have line returns and potentially scrolling (for horizontal layouts).
- The trial title name can optionally be displayed. Text and two background elements (bg and front) can be specified.
- Trial steps come in three flavors: Upcoming, Current, and Completed. Text and background elements can be specified for each type. 
	- For horizontal layouts, the background elements are handled differently. Background elements are tiled dynamically to fit the width and height of the glyphs and desired padding around the glyph for that step. Each trial step type has "tail" and a "head" that sandwiches the main background element. Tail, head, and background elements are specified for Upcoming, Current, and Completed steps. Note that trial step text is not displayed in horizontal layouts.
	- palFX can be specified for Upcoming, Current, and Completed steps, as well as for the displayed glyphs associated with each step type.
- A static or animated background can be displayed for all trial steps. This background is independent of all trial step backgrounds, and is only displayed when a trial is active.
- Glyphs can be automatically scaled according to the font used (especially useful for vertical layouts).
	- Glyphs are optional for vertical layouts, but they are mandatory for horizontal layouts as text is not displayed in horizontal layouts. Trials definition files with missing glyphs will crash horizontal layouts.
- For Success and All Clear events, text and sound elements, as well as two background elements (bg and front) can be specified.
- Two timers are available: one keeps track of the entire time spent on the trials, while the other keeps track of the time spent on the current trial. Display of the timers is optional. Utilization of the various pause menu functions (such as skipping to the nex trial) will void the total timer, for instance.
- A text string that shows the current trial can optionally be displayed.
- Other features:
	- The user can choose to apply palFX in the Trials Select Screen to portraits of characters who do not have trials definition files.

## system.def Example

```
[Trials Mode]
; GENERAL TRIALS OPTIONS ---------------------------------------------------
; trialsresetonsuccess: set to "true" to reset character positions after each trial success (except the final one). Can optionally specify fadein and fadeout parameters - will default to shown values.
; trialslayout: "vertical" or "horizontal" are the only valid values. Defaults to "vertical" if not specified. Affects scrolling logic, as stated above, also enables dynamic step width. Can be changed via the pause menu if screenpack author leaves the option in.
; --------------------------------------------------------------------------
trialsresetonsuccess = false
trialslayout = vertical

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
; glyphs.<layout>.offset: x,y offset from current trialstep position
; glyphs.<layout>.scale: x,y scale for glyphs
; glyphs.<layout>.spacing: x,y spacing from one glyph element to another on the same trialstep
; glyphs.vertical.align: alignment for glyphs (vertical layout only)
; glyphs.vertical.scalewithtext: true or false; scales glyphs according to font height - ignores scale parameter when set to true.
; GLYPHS VERTICAL ----------------------------------------------------------
glyphs.vertical.offset = 244,3
glyphs.vertical.scale = 0.3125,0.3125
glyphs.vertical.spacing = 0,0
glyphs.vertical.align = -1
glyphs.vertical.scalewithtext = false
; GLYPHS HORIZONTAL --------------------------------------------------------
glyphs.horizontal.offset = 0,-3
glyphs.horizontal.scale = 0.4, 0.4
glyphs.horizontal.spacing = 0,0

; TRIALS COUNTER AND TIMERS ------------------------------------------------
; trialcounter shows the current trial number
; totaltrialtimer shows the total time for the trial. It is erased if the pause menu is used to skip or rewind.
; currenttrialtimer shows the time spent on the current trial attempt.
; --------------------------------------------------------------------------
trialcounter.pos = 10,710
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

[Trials Info]
; If not overridden, values used for [Menu Info] are shared with this group.
; Trials specific parameters:
menu.valuename.trialslist = ""
menu.valuename.trialdvancement.autoadvance = "Auto-Advance"
menu.valuename.trialadvancement.repeat = "Repeat"
menu.valuename.trialresetonsuccess.yes = "Yes"
menu.valuename.trialresetonsuccess.no = "No"
menu.valuename.trialslayout.vertical = "Vertical"
menu.valuename.trialslayout.horizontal = "Horizontal"

; https://github.com/ikemen-engine/Ikemen-GO/wiki/Screenpack-features#submenus
; If custom menu is not declared, following menu is loaded by default:
; menu.itemname.back = "Continue"
; menu.itemname.nexttrial = "Next Trial"
; menu.itemname.previoustrial = "Previous Trial"
; menu.itemname.menutrials = "Trials Menu"
; menu.itemname.menutrials.trialslist = "Trials List"
; menu.itemname.menutrials.trialadvancement = "Trials Advancement"
; menu.itemname.menutrials.trialresetonsuccess = "Reset to Center on Success"
; menu.itemname.menutrials.trialslayout = "Trials Layout"
; menu.itemname.menutrials.back = "Back"
; menu.itemname.menuinput = "Button Config"
; menu.itemname.menuinput.keyboard = "Key Config"
; menu.itemname.menuinput.gamepad = "Joystick Config"
; menu.itemname.menuinput.empty = ""
; menu.itemname.menuinput.inputdefault = "Default"
; menu.itemname.menuinput.back = "Back"
; menu.itemname.commandlist = "Command List"
; menu.itemname.characterchange = "Character Change"
; menu.itemname.exit = "Exit"

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
; trial.showforvarvalpairs = 

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
; trial.showvarvalpairs - optional - (comma-separated integers, specified in pairs, can specify 0..n pairs). Used to determine whether a trial should be displayed based on the specified variable and value pair(s) in this field. Useful if a trial should only be displayed when character has a specific variable/value pair set, such as being in a specific groove or mode. If specified, the trial will only be displayed if all variable-value pairs return true. These variable-value pairs should only be for the character (not for helpers). Finally, variables can have multiple specified values to test against, which should be separated by the "|" character (e.g. `trial.showforvarvalpairs = 12, 0|2|4` would test var(12) for values 0, 2, and 4).

; dummymode, guardmode, and dummybuttonjam are defined once per trial. The other parameters can be defined for each trial step - notice the syntax, where X is the trial number.

; trialstep.X.text - optional - (string). Text for trial step (only displayed in vertical trials layout).
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
trialstep.1.text = Kung Fu Taunt
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

[TrialDef, Kung Fu Juggle Combo]
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

Trials Mode ships with the several pause menu options. Customizing the pause menu must be done by editing the `motif.setBaseTrialsInfo()` in `trials.lua`.
- **Next Trial**: advance to the next trial
- **Previous Trial**: return to the previous trial
- **Trials List**: view a list of the trials, and select which one to activate
- **Trial Advancement**: toggles between either Auto-Advance or Repeat, allows the player to play a single trial on repeat if desired
- **Reset on Success**: resets the players to center stage when the trial is cleared. This can be set in the `system.def`, but the player can modify it in-game as well.
- **Trials Layout**: toggles between Vertical and Horizontal trials layout. This can be set in the `system.def`, but the player can modify it in-game as well.