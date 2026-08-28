# A Trial Definition is parsed in the module, not by `loadIni`

## Context

docs/adr/0001 has the module read every configuration file it owns through the engine's
`loadIni`, and that is still true of Trials Config. A Trial Definition is now the one
exception.

A Trial Definition may declare more than one `[TrialDef, <title>]` with the same title,
and each is a separate Trial. This is not an author's slip: it is how a character with
modes or grooves spells the same combo once per mode, with `trial.showforvarvalpairs`
(docs/adr/0003) deciding which variant the player is offered. `cvsryu` on the test
roster does exactly this — 38 `[TrialDef]` sections, eight of them repeating a title.

`loadIni` cannot express that. go-ini merges same-named sections as it parses
(`parser.go:432`, `f.NewSection` returning the section it already holds), so by the time
`loadIni` returns there is one table with the keys of both bodies fighting over the same
names. The duplicate was *detectable* only because the module also scanned the raw text
for its section headers to recover the authored order, and could compare the two counts
— which is what the warning `readTrialDefinition` used to print was doing. The bodies
themselves were gone.

The umbrella spec (#46) originally decided that duplicate titles would be "detected and
warned rather than silently dropped". That was the right call while nothing needed
duplicates. #51 is where something did.

## Decision

The module parses a Trial Definition itself, from the text `loadText` returns, and hands
back its sections as a list in authored order rather than as a table keyed by name. Two
headers with the same name stay apart.

The parser is a deliberate copy of the engine's, not an improvement on it. It
reproduces:

- go-ini's line parser under exactly the options `loadIni` passes it
  (`src/script.go:4396`): `SkipUnrecognizableLines`, `PreserveSurroundedQuote`,
  `UnescapeValueDoubleQuotes` off — which is what decides that `=` and `:` are both
  delimiters, that `#` and `;` start a comment anywhere in an unquoted value, and that a
  section name runs to the *last* `]` on its line;
- `parseIniLuaValue`, `setNestedLuaKey` and `iniToLuaTable` (`src/script.go:450-630`)
  with `normalizeSections` off and `keepMeta` on — the arguments the module used to hand
  `loadIni` — so dotted keys nest, comma-separated values become arrays, `__order` and
  `__value` are where they were, and a number is typed the way Go types it.

The one intended difference is the merge. Sections are not merged, and neither are keys
across sections. Keys *within* one section still are, last-wins in first-written
position, because that is what go-ini does inside a body.

## Considered options

**Rewrite the headers and re-parse the text.** Read the file, rename each repeated
`[TrialDef, <title>]` to something go-ini keeps distinct, hand the rewritten text back
to the ini parser, and carry the authored title separately. This was the preferred route
in #51 and it is closed: `loadIni` takes a *filename* (`src/script.go:4396`, `LoadText`
then `LoadINIText`), and the engine exposes no Lua entry point that parses ini out of a
string. Nothing else in `src/script.go` does either.

**Write the rewritten text to a temporary file and `loadIni` that.** The same idea with
a disk round-trip standing in for the missing entry point. Rejected: it puts a file
write on a read path that runs for every character on the roster at startup, in a module
whose install is "copy a folder", and it fails or leaves droppings on exactly the
machines least able to report why. A parser that is wrong is a bug to fix; a game that
cannot read its own characters because a directory is not writable is worse.

**Keep warning and leave the pattern unsupported.** What #46 decided, and what shipped
until #51. It costs a third of `cvsryu`'s definition and it makes `showforvarvalpairs`
unable to tell mode variants apart, which is the pattern the two features exist to
support together.

## Consequences

The module now owns an ini parser — some 550 lines with its commentary — which
ADR-0001 deliberately avoided, and it will drift from the engine's if the engine's
changes. Two things are in place
against that:

- every helper names the Go function it reproduces and the file and line it is at, so a
  change on the engine side has somewhere to land;
- the harness diffs the module's parse against the real `loadIni` for every Trial
  Definition the test roster can reach, section by section, merging the module's
  same-named sections the way go-ini would have merged them first. A divergence fails as
  a path and two values (`TrialDef, Scalars.probe.rounded: 0.12345678 vs 0.123457`)
  rather than as a wrong Trial three slices later. `fixture/torture-trials.def` exists to
  give that diff the lines a Trial Definition is least likely to carry — continuations,
  backquotes, inline comments, hex and octal, a scalar and its children under one key.

That diff has already earned itself: gopher-lua's `tonumber` is not `strconv.ParseFloat`
— it reaches ParseFloat only for a string containing a `.`, so `1e3` comes back `nil`
from it and a base is ignored when a `.` is present (`baselib.go:412`) — and both
divergences that caused were found by the diff rather than by reading. The escape
handling in `unquote` was widened to Go's full set (`\xNN`, `\NNN`, `\uNNNN`,
`\UNNNNNNNN`) for the same reason: the fixture spells them, so a fallback would fail
the diff rather than reach an author.

A Trial title is a label from here on, not an identity. The Trial's index in the file is
the identity — it is what completion is recorded against and what keeps a player on the
Trial they were on across a re-evaluation (docs/adr/0003) — and nothing else keys off the
title. The pause menu's trials list shows one entry per Trial, so a character declaring
the same title twice shows it twice; where the pair is a mode variant, `showforvarvalpairs`
is what leaves only the applicable one on screen.

`tools/check-trials-dump.py` asserts the Trial count against the file's own
`[TrialDef]` count, read off the raw text. That comparison is the acceptance test for
this decision, and it is deliberately not a number written into the checker: the failure
this ADR is about leaves a dump that agrees with itself.
