# Trials Mode shares the `_iksys_training*` map namespace

## Context

`trials.zss` needs the same Dummy behaviour training mode has: guard mode, dummy
mode, fall recovery, distance, button jam. The obvious move is to fork those maps
into a private `_iksys_trials*` namespace, which is what the pre-refactor module did.

But the engine's own pause-menu handlers write the `_iksys_training*` map names
**unconditionally**, without checking the game mode. A private namespace therefore
means reimplementing all six dummy handlers in module Lua purely to write differently
named maps that do the same thing.

## Decision

Trials Mode writes the engine's `_iksys_training*` maps directly. Only genuinely
trials-specific state keeps a `_iksys_trials*` name: reposition, camera position,
player and dummy positions, camera reset, and set-life.

`trials.zss` is a fresh fork of the current engine `data/training.zss` with the trials
deltas applied on top, rather than a carried-forward copy, so it tracks upstream
common-state changes.

## Consequences

The built-in dummy control, guard mode, dummy mode, fall recovery, distance and button
jam pause-menu items work in Trials Mode with **no module code at all** — they only
need listing as item names in `[Trials Pause Menu]`.

`IkSys_JustDefend` in the engine's `functions.zss` reads the shared guard-mode map
unconditionally, so a guarding Trials Dummy also becomes eligible for Just Defend.
This matches training mode's existing behaviour and is accepted.

`training.zss` and `trials.zss` are both loaded during a Trials match. Both gate on
`gameMode`, so blocks that check it no-op correctly — but any block that *doesn't*
check will fire in both modes. This is a known risk to be caught in testing rather
than audited up front.
