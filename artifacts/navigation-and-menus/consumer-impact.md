# Consumer-impact ledger — Rascal Rally

Root `CLAUDE.md` / execution contract §"Rascal Rally consumer lockstep": both Rascal Rally
Rojo projects mount `GameStudio/ui/LuauUI/src` directly, so **a LuauUI gate cannot pass
while its consumer is stale, failing or unaudited.** Every stage of this round carried its
own rider in the same task.

**No production game code changed, and that is the correct outcome** — nothing in Rascal
Rally builds a menu, a tab view, a callout or an anchored surface yet. The rule is explicit
that a compatible internal change must not be given a manufactured edit; what it requires
instead is evidence that the direct consumer still works. That evidence is eight new or
extended contract specs, each driving the change through the game package's own framework
require and presenter rather than through LuauUI's fixtures.

Game behaviour, content ownership and feature flags are unchanged, including the production
LuauUI Sponsor default and the `UseLuauUISponsor = false` legacy rollback.

## The trail

| Stage | Rider | Game-side proof | Production caller changed? |
|---|---|---|---|
| D0 | `07ee5ad`, `7b92724` | `tools/suite_transcript.sh` — its fingerprint covers `$LUAUUI/{src,tests}`, because these specs require LuauUI modules directly | no (tooling) |
| D1 | `14aabf4` | `luauui_anchored_surface_contract.spec.luau` | no — **measured** zero `presentAnchored` hits under the game's `src/`, so restraint is proved rather than asserted |
| D2 | `36b9e7a` | `luauui_menu_contract.spec.luau` (8 cases) | no |
| D3 | `df47d57` | `luauui_help_callout_contract.spec.luau` | no |
| D4 | `6230a91` | `luauui_selection_indicator_contract.spec.luau` | no |
| D5 | `557e02c` | tab-view contract spec | no |
| D6 | `ce56b2a` | `luauui_segmented_picker_contract.spec.luau` | no |
| D7 | `2375f06` | region-recovery contract spec | no |
| D8 | `4a1b4f1` | `luauui_racer_list.spec.luau` already covered `api.columnWidthOverrides` | no (comment-only) |

## What the riders caught that the framework suite could not

This is the argument for the rule, and it earned itself twice in one round.

- **D4.** An indicated picker inside a **content-sized wrapper** solved its options to
  **0 px**. Every framework fixture used fixed-width segments, so nothing headless could see
  it. Fixed by having the wrapper inherit the strip's dimension; the regression compares an
  indicated control against a plain one.
- **D6.** The rider went red (**3289 / 1**) on the old-default assertion *before any D6 spec
  existed* — the game's contract test noticed the segmented picker's default indicator had
  moved before the framework's own coverage did.

## The one behaviour the riders exist to protect

Ten shipped Sponsor surfaces declare `UI.Text{ disclose = true }` and depend on the
full-value plate still owning **long-press** outside a menu trigger. D2 scoped `newMenu`'s
claim to its own trigger subtree precisely so that stays true, and D2's rider pins it. D3's
rider pins the `focus_graph.pushScope` change in both directions (a non-trapping scope
asking `initialFocus = "none"` no longer blanks the ring; a trapping one still does).

## Suites

Rascal Rally: **3320 passed / 0 failed** at round close, from 3280 at round open — 40 new
cases, all of them consumer contracts.
