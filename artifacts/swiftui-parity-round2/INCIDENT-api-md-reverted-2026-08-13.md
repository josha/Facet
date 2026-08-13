# INCIDENT — `docs/reference/api.md` was reverted to HEAD at 05:58:31, 2026-08-13

Recorded by the Phase-3 (`sensoryFeedback` + haptics) agent, because the loss is
not mine to repair and the list of what went missing would otherwise have to be
re-derived from red gates.

## What happened

At `05:58:31` on 2026-08-13 `docs/reference/api.md` stopped being a modified file
(`git status` no longer lists it) and its content became byte-identical to
`HEAD` (`ff7501e`). It had been modified — and green — continuously before that:
the full LuauUI suite ran **4447 passed / 0 failed** at 05:0x and **4532 passed /
0 failed** at 05:5x, both against the modified file. The most likely cause is a
`git checkout -- docs/reference/api.md` (or an equivalent restore) by a
concurrently running agent. The file has been stable at HEAD content since; it
was not a mid-write.

## What was lost

Everything uncommitted in that file, from at least three separate pieces of
round-2 work:

| Missing | Owner |
|---|---|
| `### \`GridRow\`` heading + the class entry | round 2 §2.2 |
| `### \`containerRelativeFrame\`` heading | round 2 §2.5 |
| shared props `gridSpan`, `layoutPriority`, `lineAlign`, `shrinkWeight` in the `### UI` section | round 2 §2.2 / §2.4 |
| `distribute` in the `Screen` / `VStack` / `HStack` / `AdaptiveStack` entries | round 2 §2.6 |
| the word "deprecated" beside `newVirtualList(spec.rowHeight)` (api.md:2965 as it now stands) | round 2 §2.3 |
| `### \`sensoryFeedback\`` and `#### \`client.haptics\`` | round 2 §3.3 — **already re-applied** by that agent |

## Consequences, live

Five suite cases and two of the checkers are red **for this reason alone**:

```
✗ api.md mentions every deprecated surface, and says 'deprecated' beside it
✗ the live repository passes every registration rule
✗ the live repository proves the four-input story for every interactive control
✗ the live repository proves the PARADIGM axis for every interactive control
✗ the live repository passes the property-parity check
check_registration: FAIL — 2 problem(s)   (GridRow, containerRelativeFrame)
check_prop_parity:  FAIL — 9 problem(s)
```

`check_docs`, `check_boundary` and `check_surface_ledger` still PASS.

## Recovery

The content is **not** on disk anywhere: it was uncommitted, `.dropbox.cache`
holds no copy, and the only stale copies
(`.superpowers/sdd/row-actions-implementation/recovery/api.md.*`) are from
2026-08-10 and predate all of it. Each owning agent has to re-write its own
entry. The Phase-3 agent deliberately did **not** write replacements for the
other rows: inventing reference documentation for a surface someone else built
risks documenting behaviour that does not exist, and would collide with the real
restore.

## The lesson worth keeping

A shared, uncommitted file is not a safe place for parallel agents to hold work.
`git checkout -- <path>` on a file another agent is editing destroys work with no
undo, and nothing in the gate machinery notices until a checker names a symbol
that no longer has documentation. Commit early, or reach for `git stash push --
<path>` (recoverable) over `checkout` (not).
