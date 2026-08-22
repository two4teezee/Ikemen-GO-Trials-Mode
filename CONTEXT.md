# Trials Mode

Trials Mode is an Ikemen GO external module that adds a combo-trial game mode: a
player picks a character, and works through a list of authored input sequences,
each one verified against the engine's own state as it is performed.

The module is universal — it ships no character content of its own. Characters
opt in by supplying a Trial Definition, and screenpacks opt in to styling it by
defining Trials Config sections.

## Language

### The trial hierarchy

**Trial**:
One named challenge, authored as a single `[TrialDef, <name>]` section of a Trial
Definition. Has its own dummy settings, optional textbox, and an ordered list of
Steps.
_Avoid_: challenge, combo, trial def (that's the file)

**Step**:
One requirement within a Trial, authored as `trialstep.X.*`. Carries the text and
glyphs shown to the player, and the conditions that verify it.
_Avoid_: move, input, trial step

**Part**:
One element of a Step whose condition fields are comma-separated lists, so that a
single Step requires a short sequence of states rather than one. A Step with
`stateno = 200, 210` has two Parts. A Step always has at least one Part.
_Avoid_: microstep, substep, condensed step

**Step Status**:
Where a Step sits relative to the player's progress: *upcoming*, *current*, or
*completed*. Each status is styled independently.
_Avoid_: step state (collides with the engine's `stateno`)

### Configuration and data

**Trial Definition**:
The per-character file (conventionally `trials.def`) declaring that character's
Trials. Authored by character authors. Discovered through the character's own def
file.
_Avoid_: trials.def, trials data, trials file

**Trials Config**:
The module's presentation and behaviour settings — fonts, positions, colours,
windows, layouts. Resolved from three layers: the module's `+system.def`, the
module's `config.ini`, then the screenpack's `system.def`.
_Avoid_: trials settings, motif data, trials_mode

**Player Preference**:
A Trials Config value the player changes at runtime through the pause menu and
which persists to the module's `config.ini` — layout, textbox visibility, trial
advancement, reset on success. Distinct from authored config, which a player
never edits.
_Avoid_: option, setting

### Presentation

**Layout**:
The arrangement of Steps on screen — *vertical* (a stacked list) or *horizontal*
(a flowing row). A Player Preference; each Layout has its own independent config
block.
_Avoid_: orientation, view, mode

**Textbox**:
Optional per-Trial explanatory prose, with an optional accompanying portrait.
When shown, the Step block shifts to its with-textbox window so the two do not
overlap.
_Avoid_: tooltip, description, hint

**Glyph**:
A sprite standing in for one input token in a Step's notation, drawn from the
screenpack's shared glyph vocabulary — the same one the engine's movelists use.
_Avoid_: icon, button, symbol

### Progress

**Advancement**:
What happens when a Trial is completed — *auto-advance* to the next Trial, or
*repeat* the current one. A Player Preference.
_Avoid_: progression, next

**Success**:
The moment every Step of one Trial is completed.
_Avoid_: completion, clear, win

**All-Clear**:
The moment every Trial for the selected character is completed. Distinct from
Success, and styled separately.
_Avoid_: full clear, 100%, perfect

### Surroundings

**Trials Mode**:
The game mode itself — what `gameMode()` returns as `trials`. Capitalised and
singular-as-a-unit; an individual challenge is a Trial.
_Avoid_: trials (ambiguous with the plural of Trial)

**Dummy**:
The opponent character in a Trials match, driven by the shared training dummy
controls rather than by AI. Configured per-Trial.
_Avoid_: opponent, P2, CPU

**Screenpack**:
The user's active motif — the `system.def` and assets defining the game's look.
May override Trials Config, but is never required to know Trials Mode exists.
_Avoid_: motif (reserve that for the engine's own `motif` table), theme
