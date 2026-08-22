# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker, plus one label this repo adds of its own.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

## Repo-specific: `ready-for-human-testing`

| Label                     | Meaning                                  |
| ------------------------- | ---------------------------------------- |
| `ready-for-human-testing` | Requires human testing and verification  |

This repo adds a sixth label with no counterpart in the skills' vocabulary, because
Trials Mode cannot be fully verified without a person watching the screen.

**Apply it when, and only when, there is something for the maintainer to test.**

- Apply it if any part of the change needs a person at the screen — even when the agent
  verified other parts of the same slice headlessly. Most slices are mixed.
- **Do not apply it** when there is nothing for the maintainer to test, or nothing they
  could verify even if they tried: docs-only changes, tooling, refactors with no visible
  effect, or anything the agent already proved end to end. Those go straight to closed.

**Swap, never add.** Remove whatever label the ticket is currently carrying at the same
time — `ready-for-agent` in the usual case, but whatever is actually there. A ticket
holding two state labels is ambiguous about whose court it is in.

```
gh issue edit <n> --remove-label "<current>" --add-label "ready-for-human-testing"
```

The label change and the test checklist go together — see `testing-handoff.md`. Neither
is complete on its own: the label says whose turn it is, the checklist says what to do.
If a change does not warrant the label, it does not warrant a checklist either.

The label comes off when the maintainer reports back — the ticket is either closed, or
returns to `ready-for-agent` if their testing found something to fix.

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.
