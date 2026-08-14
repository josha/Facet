# Consumer impact — LuauUI rulings 2 / 8 / 9 → Rascal Rally

**Ledger rows:** O-7 (ruling 2), O-27 (ruling 8), O-28 (ruling 9)
**Contract:** `docs/plans/agent-execution-contract.md` § "Rascal Rally consumer lockstep"
**Game source:** `games/RascalRally/code`

Rascal Rally's two Rojo projects mount `GameStudio/ui/LuauUI/src` directly, so
every changed contract is audited here against the game's real callers with
file:line evidence.

---

## 1. Changed contracts, and what each does to the game

| # | Changed contract | Kind | Production callers in `games/RascalRally/code/src` | Action |
|---|---|---|---|---|
| 1 | `ViewThatFits` judges candidates with the measure-side shrink suppressed | behavioural | **none can be affected**: `grep -rn shrinkWeight src/` finds nothing, and `luauui_stack_arrange_contract.spec.luau` already asserts that ("Rascal Rally declares no `shrinkWeight` anywhere"). No candidate in the game can report a shrunk extent, so no winner can change | none |
| 2 | Solver findings may carry `designed: boolean?` | additive, optional | `ResultsScreen.luau:3931` returns `controller.diagnostics()` verbatim; the game's screen checks read `issue`/`node` | none in production; **the game's own check now reads the new field** (§2) |
| 3 | A declared adjust axis's directional keys move from the `Adjust` action to a new `AdjustAxis` action | behavioural, scoped to targets that declare `adjustAxis` | `ResultsScreen.luau:3204` and `:3726` declare `adjustTargets`/`handleAdjust` and **no `adjustAxis`** | none — see §1.1 |
| 4 | A declared adjust axis yields its arrow when `handleAdjust` returns false | behavioural | same two sites | none — see §1.1 |
| 5 | `handle.actions.adjustAxis` on the present handle | additive | **none** (`grep -rn "actions.adjust" src/` finds nothing) | none |

### 1.1 Why #3 and #4 are structurally unreachable here

Both game sites declare `adjustTargets` and `handleAdjust` and deliberately do
**not** declare `adjustAxis` (§S16.11: "Adjust: scroll the field" — the standings
scroll on the bumpers and the arrows stay with Navigate). A target with no
declared axis is the presenter's `legacy` state, and `legacy` never routes a key
to `AdjustAxis`:

- on a **grouped** screen (which the results surface is — its contribution
  declares `focusGroups`) the arrows stay bound to `NavigateH` and nothing is
  suspended at all;
- on a flat screen they bind to `Adjust`, the un-yieldable action.

So the game's arrows were never taken from navigation, and there is nothing for
the ruling to give back. That is a structural reason, not a lucky one, and §2
pins it from the game side in both directions.

Independently: the game's `handleAdjust` returns `true` whenever a controller is
bound (it asks the scroller for a position and reports success), so even a
future declared axis would not yield through today's handler. That is a second,
weaker reason and is *not* what the test rests on.

## 2. Game-side checks added or updated

| File | Case | What it holds |
|---|---|---|
| `code/tests/luauui_sponsor_results.spec.luau` | **`LOCKSTEP: the arrow-yield ruling cannot move this surface's ring (LuauUI ruling 9)`** | (1) the game source declares `adjustTargets` twice and `adjustAxis` zero times — so the day somebody adds one, this surface's arrows silently become yieldable and the case says so; (2) behaviourally, arrows move the ring and bumpers scroll without moving it, at the scroll limit as well as away from it |
| `code/tests/luauui_large_text_results.spec.luau` | `NOTHING PAINTS OVER ANYTHING at any preference` | reads `entry.designed ~= true` instead of matching the sentence `"no declared arrangement is legal"`. Same exclusion, now the same decision the framework's own sweep reads |
| `code/tests/luauui_large_text_results.spec.luau` | `RECORDED FINDING: 667x375 has no legal arrangement above Large` | requires **both** the `designed` mark and the sentence — a case that checked only the mark would pass on any future designed report and stop pinning this surface's real limit |

**Mutation evidence (the obligation, not a claim).** Adding
`adjustAxis = "vertical"` to `ResultsScreen.luau`'s first contribution reddens
the LOCKSTEP case by name (`expected adjustTargets=2 adjustAxis=1`), and removing
`designed = true` from `src/layout/solver.luau` reddens the framework-side
composition cases; both were run and restored.

## 3. Suite

| | before | after |
|---|---|---|
| Rascal Rally (`code/run-tests.sh`) | 3160 passed (session baseline) | **3170 passed, 4 failed** |

The four failures are **not** from this work and are named here so nobody has to
re-derive that: `...and the shrink pass reaches the MEASURE pass`,
`a ticker entry's target NAME may truncate`, and `the surface still RESPONDS to
each geometry fact` (plus its sibling) belong to two other agents' in-flight
rounds — the degrade-cascade/wrap-rule change (rulings 1 and 5) and the L-31
geometry-feed change, both live in the shared tree while this was written.
