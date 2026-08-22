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

The module writes the shared maps directly from Lua when a Trial starts, and
`trials.zss` executes them. No dummy logic is duplicated in Lua, and no dummy items
appear in the trials pause menu.

An earlier revision of this ADR justified the shared namespace on the grounds that the
engine's built-in dummy *menu items* would then work for free. That is no longer the
payoff: dummy behaviour is prescribed by the Trial Definition and nowhere else, so
every Trial plays the same way for everyone, and exposing the same maps as menu items
would let a player silently invalidate the Trial its author designed. The decision to
share the namespace still stands on its own — writing the names the engine's own
`functions.zss` and pause-menu handlers already understand is what avoids forking the
dummy logic.

One consequence of *not* shipping those menu items is that a live crash is avoided:
the engine calls `menu.f_trainingReset()` only under `gameMode('training')`
(`start.lua:1739`), so in a Trials match `menu.ailevel` is never initialised and
cycling Dummy Control raises `Argument 1 is not a number` from `setAILevel`. A
screenpack that adds a dummy submenu to its own `[Trials Pause Menu]` will hit this.

`IkSys_JustDefend` in the engine's `functions.zss` reads the shared guard-mode map
unconditionally, so a guarding Trials Dummy also becomes eligible for Just Defend.
This matches training mode's existing behaviour and is accepted.

`training.zss` and `trials.zss` are both loaded during a Trials match. Both gate on
`gameMode`, so blocks that check it no-op correctly — but any block that *doesn't*
check will fire in both modes. This is a known risk to be caught in testing rather
than audited up front.
