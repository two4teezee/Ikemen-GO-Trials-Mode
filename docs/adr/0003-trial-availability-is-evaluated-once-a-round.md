# A Trial's `showforvarvalpairs` is evaluated once a round

## Context

`trial.showforvarvalpairs` gates a whole Trial on the player's character variables, so
that a character with modes or grooves offers only the Trials belonging to the one the
player is actually in (#52, user story 37 of #46). A Trial whose pairs do not hold is
not offered at all: not drawn, not counted by the Trial Counter, not reachable by
Advancement, not in the pause menu's trials list, and not part of All-Clear.

The variables it reads can change while the match is running — that is what a groove
system *is* — so the module has to decide when it looks at them. Three answers were
available and the diff shows none of them, which is why this is written down:

- **Once a match.** Trivial, and wrong on its own terms: the module resolves the match
  on its first frame, which is `roundState` 0. The character's own round-start
  initialisation has not run yet, so every variable reads 0 and every gated Trial
  resolves against a value its author never meant. `cvsryu` makes the point exactly:
  its groove is picked by a helper spawned under `trigger roundstate = 0`, from the
  arrows the player presses before the round begins.
- **Every frame.** What the feature sounds like it is for, and what makes the available
  set follow the player as they switch. But the Trial the player is *on* can then
  become unavailable underneath them, mid-combo, and something has to yank them
  somewhere else and throw away the progress they were making. It also makes the Trial
  Counter's total, the trials list and All-Clear all move while the player is reading
  them.
- **Once a round**, on the first frame past the round-state reset — which is what the
  pre-refactor module did (`start.f_trialsBuilder`, called on the first frame of
  `roundstate() == 2`, with `start.trials` rebuilt from scratch at every `roundstart()`).

## Decision

**Availability is evaluated once per round, on the first frame at `roundState >= 1`,
and marked stale whenever the round state falls back to 0.**

This is the same gate and the same staleness marker `applyDummy` and `applySetup`
already use, and for the same reason ADR-0002 gives: `trials.zss` clears the shared
maps for the whole of `roundState` 0, so nothing the module resolves is worth anything
until the round is past that reset. Availability is evaluated *before* both of them in
the loop, so the Dummy settings and the pair's positions are never written from a Trial
that is not on offer.

It is one gate earlier than the pre-refactor module's `roundstate() == 2`. The
selection it is reading has already happened either way — `cvsryu` picks its groove
during `roundState` 0 — and evaluating at `roundState >= 1` means the first Dummy write
of the round is already made from the available list, rather than made from the
unfiltered one during the intro and corrected with a visible reposition once the round
went live.

Two consequences follow deliberately:

- A player who switches mode mid-match keeps the list they started the round with. The
  Trial they are on cannot vanish under them, and the counter's total cannot change
  while they are reading it.
- Restarting the round re-evaluates. That is the recovery path, and it is a key press
  rather than leaving the match.

## Consequences

Completion is keyed by the Trial's index in the character's **declared** list, not by
its position in the available one, because the available list is rebuilt every round
and positions shift under it. `m.completed` therefore survives a re-evaluation
correctly: a Trial completed in one groove is still completed if the next round offers
it again, and does not count towards All-Clear in a round that does not.

All-Clear can be *lost* by a re-evaluation but never silently gained. It is recomputed
against the new available set, and only ever cleared by that — a set the player has in
fact already completed does not fire a banner they did not earn, and a set that grew
goes back to being unfinished.

The player is kept on the same Trial across a re-evaluation wherever that Trial is
still available, found by its declared index rather than by its position. Where it is
not, the match falls back to the first available Trial.

`readVarPairs` and the matching loop are shared with `trialstep.X.validforvarvalpairs`
rather than duplicated: the format is the same, so the parser and the evaluator are the
same two functions. The evaluator reads `var(n)` through a P1 redirect it puts back,
exactly as `applyDummy` does with P2.

A character whose every Trial is gated out is the no-data case, and reads `nodata.text`
— the same thing a character shipping no Trial Definition at all shows. That is
correct and it is also indistinguishable from a missing file at the Trial Counter, so
the resolved-state dump carries both the declared count and the available one.
