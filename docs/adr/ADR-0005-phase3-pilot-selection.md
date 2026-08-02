# ADR-0005: Which surface is the Phase 3 production pilot: card management or garage? (design §17 Phase 3)

- **Status:** Accepted (2026-07-19)
- **Decision:** `garage` (weighted 86.00)
- **Context:** Neither surface exists yet in RascalRally. Card management = deck curation + collection (GameDesign §5/§6.12: deck-validity floors, Card Tokens, hand-of-cards; 'lands with Mission 14') and per the LuauUI design §9.4 card pick-and-place is an explicitly DEFERRED (Phase 5) interaction pattern. Garage = kart ownership/equip over the existing pure, Lune-tested semantic schema code/src/shared/CarInventory.luau (owned set + equipped id; grant/equip validated; 5-kart roster). Rubric axes from §17 Phase 3, higher = better for the pilot.

## Scores (0-5, weighted; evidence per cell)

| criterion (weight) | garage | card-management |
|---|---|---|
| fewer-bespoke-interactions (5) | 5 — grid + focus + activate + one typed mutation; zero gesture patterns | 2 — deck curation implies pick-and-place / drag idioms and validity-constrained composition UI |
| less-deferred-feature-dependency (5) | 5 — needs only shipped primitives (Grid/ForEach/Button/focus/mutation); 5 items => no virtualization (documented) | 1 — pick-and-place is explicitly Phase 5 (design §9.4); deck rules + card pool land with game Mission 14 — the semantic state does not exist yet |
| smaller-rollback-risk (4) | 4 — new surface, no default entry point; debug-flag construction; semantic schema already shipped + tested (CarInventory) | 3 — would front-run Mission 14's design surface |
| future-pattern-coverage (4) | 5 — keyed collection + adaptive grid + selection + validated equip mutation = the shop/list/loadout shape of most future surfaces | 4 — rich, but the patterns it exercises are the deferred ones |

## Totals

- garage: 86.00
- card-management: 43.00

**garage:** Kart grid over CarInventory semantic state: select, pick/equip mutation, equipped badge, owned/earnable states.

**card-management:** Deck curation + card collection (hand, validity floors, Tokens).

- **Consequences:** Garage pilot is built as a new flag-gated surface over CarInventory; no new framework primitives are demanded (recorded in the ADR — §17 Phase 3 requires an ADR per NEW primitive; zero were needed). Virtualization not required at 5 fixed-height items. Card management remains the natural second adopter after Mission 14 lands its semantics.

## Pilot build record (2026-07-19)

- Files: `games/RascalRally/code/src/client/GaragePilotScreen.luau` (pure) + `GaragePilotGui.luau` (glue; opt-in workspace attribute `UseLuauUIGaragePilot`, no default entry until the Paddock lobby) + `tests/luauui_garage_pilot.spec.luau` (8 specs; game suite 2392).
- **No new framework primitives were demanded** (§17 Phase 3 rule: ADR per new primitive — zero added). At five fixed-height cards a full-width card list is the correct adaptive shape; the solver already carries a grid algebra (`grid` kind, layout_v1-tested); exposing a `UI.Grid` blueprint primitive for larger rosters is a future ADR per the §17 primitive rule; **virtualization not required** at this size (design §10.5), documented here.
- One framework defect surfaced and was **fixed in the framework, not worked around in screen code** (Phase 3 acceptance): ScrollView did not stretch cross-axis `fill` children (same class as the Phase 2 ZStack finding D2); fixed in `src/layout/solver.luau` scroll arrange, covered by the pilot's multi-viewport spec, library suite stays 113 green.
- Transport note: until the lobby's replication wiring exists, the glue validates picks through the same `CarInventory` functions the server uses, against a client-local profile; the Lune spec drives the identical flow through a loopback server. The swap to the real remote is a contained change in `GaragePilotGui.onActivate`.
