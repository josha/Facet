# Rascal Rally consumer-impact ledger — api-architecture-consistency (v0.8.0)

Both Rascal Rally Rojo projects mount `GameStudio/ui/LuauUI/src` directly, so every
contract change below was audited against the game's callers. Verdict per change:
**game code untouched** — every fix is either invisible to the game's usage or a
strictly-diagnosed upgrade no game call site trips. The game suite proves it at the
final source: **3000 passed, 0 failed** (`games/RascalRally/code/run-tests.sh`,
re-run after the last library change of the stage; see `game-suite.txt`).

| Change (dispositions.md) | Game callers audited | Impact |
|---|---|---|
| F-8/F-10 collection resnapshot/gap fixes | none — the game uses `replication.snapshot` only (`GaragePilotGui.luau:51`); no `collection` caller in `code/src` | unreachable |
| F-9/F-11 mutation quarantine + reset | `GaragePilotGui.luau:55` builds `mutation(core, nil)` — no optimistic opts; its `reset()` (:89) runs only from terminal states | byte-identical behavior for this caller |
| F-12 provider strict opts | no `newResourceProvider` caller in the game | unreachable |
| F-13 `scope:own` refusal | every `:own(` in `code/src` audited (pkg1): all functions or dispose-bearing objects | no trip |
| F-14 focus-graph copies | game reaches the graph only via `presenter.focus`; presenter passes fresh literals; game never re-reads pushed tables | behavior-identical; input paths pinned by the game suite's sponsor/settings integration tests |
| F-15 `responder`/`scrim` validation | game's `present()` opts grepped: `responder = "passive"` ×2 (HudScreen.luau:210, LuauUISponsor/init.luau:570), `scrim = "none"` ×2 — all legal values | no trip |
| F-17 touch-gesture payloads | the game consumes no `setTouchGestureHandlers` seam | unreachable (its drag rides `UI.draggable`) |
| F-23 Label `semanticText` Readable | no `newLabel` caller in the game | unreachable |
| F-27 Table header alignment | `LuauUIRacerListScreen.luau:159` — its columns declare no `alignment`, and leading titles keep the same inset arithmetic (cellPadding both sides) | visually equivalent; pinned headless by the new table.spec geometry cases; Studio canary row in `studio-disposition.md` |
| F-1/F-2 Popup/Chip build guards | no game caller of either control | unreachable |
| F-19 `overflow="clip"` | zero string-valued `overflow =` UI props in `code/src` (the word's 64 hits are unrelated game logic/comments) | unreachable |
| F-22 deep-frozen blueprints | game never mutates a constructed blueprint (grep: no `.props[` / `table.insert(bp` writes) | no trip |
| DEP `retryAttempts` / `contentWidth` | no game caller of either spelling (`conditions(...).contentWidth` grep: 0) | nothing to migrate |
| Type re-exports, text.measure overload, Fit.state, inputHint opts.scope, target-contract THEME group | additive | none |
| v0.8.0 + new DEPRECATIONS entries | game reads `LuauUI.VERSION` nowhere | none |

**Why no game edit is correct (per the lockstep rule):** every change is compatible
for the game's shipped call sites; manufacturing churn would violate the same rule.
The game-side compatibility evidence is (a) the full game suite at the final
library source (3000/0 — the suite includes the LuauUI integration/contract specs
for the sponsor surfaces, racer list, settings, garage pilot), and (b) the audits
above, each grep/file:line recorded in the package reports and ledger fragments.
Rojo mappings unaffected: no LuauUI file moved, added, or deleted from `src/`
(exports changed in place; `git status` shows no new/removed src files).

Documentation-only game impact: none — no Rascal Rally doc states a claim this
stage changed.
