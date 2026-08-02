# PS-C rows — layer L3 (cards/input) live Studio evidence + status

**Date:** 2026-07-30 · bench, `UseLuauUISponsor=true`, rig live. Suites: game
**2627** / LuauUI **2611**, stylua clean, 11/11 legacy checksums OK,
namespace audit clean (1 sanctioned `Instance.new` = the dev report fn).
Sanctioned-changes stamp refreshed (adds the ADDITIVE
`SponsorHudModel.strings.director` semantic-label table — legacy behavior
untouched, its specs green in-suite).

## Proven live this session

- **Tap-arm (pointer/GUI path):** injected click on `HandDock.Slots.[1].CardSlot`
  → session `armed`, `heldSlot=1`, focus handed into the racer list
  (`.../RacerList/Canvas/W/[AIKart_1]/Row/Hit`), source slot emptied
  (framework `dragHeld`). Capture: `PS-C1-armed-hand-luauui.png`.
- **Aim + legality pipeline:** with the card armed, pointer moves over rows
  updated the aim verdict live — `verdictKey=AIKart_2, legal=true`, then
  `verdictKey=AIKart_6, legal=false, reason="shielded"` — a REAL block code
  from the shared rules (`SemanticModel.legality` → SponsorStatusModel), no
  presenter-side legality anywhere.
- **Zero spurious commands:** `commands.play=0` on the server trace and the
  client counters throughout the aim churn — aiming never fires anything.

## Instrument boundary hit (recorded; NOT closed as product truth)

Injected clicks do NOT deliver Activate to buttons inside the virtual list's
nested scroll host (hover/aim delivered; click did not — `watch.enter`
unchanged, no commit, no reject toast). Slot/dot/toggle buttons outside the
scroll host DO receive injected clicks. Consequence: **live tap-commit,
tap-reject-with-toast, drag flows, fly-home and commit-flight motion are NOT
provable by injection** — they are covered by:
- headless: `luauui_sponsor_cards.spec` (26 cases: verb matrix incl. pointer
  drag, armOnTap tap-tap, gamepad arm→navigate→commit, exactly-one-play incl.
  mashing, rejection revert + one-toast-per-attempt, absorb-on-regrab, flight
  retarget on re-sort, touch decline-capture, RM forms);
- owed live: the paired human/physical pass (PS-G4/G5) and the director build
  — first REAL-pointer click in Studio during the review sitting will close
  the tap-commit row.

## L3 ledger outcomes (responsibility-ledger.md)

OWN-D11 (virtual-list navigation groups — framework API added),
OWN-D12 (draggable `enabled` acquisition gate — framework API added),
OWN-D13 (**OPEN ESCALATE**: server-rejection fly-home needs either a detached
framework return-flight verb or a ruling that flash+refill+toast is the
ratified server-revert; resolve with live legacy evidence in the paired
session — watch what legacy actually does on a server `blocked` beat),
OWN-D14 (canvasGroup transition refusal — authoring lesson recorded).

## Status per ledger row

- PS-C1: PARTIAL — states headless-complete; armed/held/emptied live; commit/
  land/reject live rows owed to real-input pass.
- PS-C2: headless (velocity/interruption specs); live motion = real-input pass.
- PS-C3: PARTIAL — legality delegation live-proven (real block code);
  one-toast-per-attempt headless; live toast owed.
- PS-C4/C5: verb matrix headless-complete; scheme rows = physical.
- PS-T4: autoscroll+drag wiring headless-complete; live drag = real-input pass.
