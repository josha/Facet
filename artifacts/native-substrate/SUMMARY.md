# native-substrate evidence bundle — human summary

**Stage:** roadmap Step 1 (Roblox-native substrate adoption) · **Date:** 2026-07-23
**Gate:** `tools/gate.sh native-substrate` → **PASS** (15/15 automated checks; `physical-device-confirmation` FAIL_ENVIRONMENT non-blocking) — `gate.json`
**Ledger:** `acceptance-ledger.md` (per-row honest statuses; contract `fable-execution-contract.md`)

## What changed (one paragraph)

LuauUI now hands Roblox the mechanisms Roblox owns — scroll physics/clipping/bars
(`ScrollingFrame` hosts under every `UI.ScrollView`, with Table + VirtualList riding a
full-height native canvas), four-edge safe-area measurement (`GetInsetArea`), stroked
paths (`UI.Path`/Path2D), drag acquisition (`UIDragDetector`, CustomOffset), native
touch recognition (normalized, engine-recognized), preferred-text rendering (painted by
the engine exactly once; LuauUI reserves via injected facts), image transport
(`PreloadAsync` statuses; honest logical-only cancellation), and an opt-in modal-only
engine-selection bridge — while every deterministic decision (layout geometry,
windowing, focus identity, drag payload/drop legality, gesture arbitration, async state
machines, shape math) stays pure Luau under the 656-test Lune suite. `UIPageLayout`
was evaluated and REJECTED with measured authority-conflict evidence (ADR-0017 §3).

## Evidence map

| Row(s) | Artifact | Live proof highlight |
|---|---|---|
| NS-M0 | `docs/research/2026-07-23-native-adoption-docs-grounding.md` | 17 official pages fetched this run; 7 disagreements flagged, 2 confirmed live (no `Path2D.Transparency`, no `ImageLabel.LoadingImageFailed`) |
| NS-M1..M10 | `feasibility/m*.json` | ten Studio spikes; canvases to 600k px, detector lifecycle+cancel, 100-point Path2D limit, selection reassignment warning, PreloadAsync statuses |
| NS-A1 | `a1-safe-area.json` | four-edge facts live; frozen-env notch injection re-solved the running screen (root → x=47, 1640×988) and reverted |
| NS-A2 | `a2-scroll-host.json` | real wheel moved a running LuauUI list's canvas 0→300; programmatic clamp at 476; fallback run clip-only |
| NS-A3/A4 | `a3-table.json`, `a4-virtuallist.json` | 2,000 rows → 72,000px canvas over 14 mounted; keep-visible target 53,640 exact; example 02 intact on the native body |
| NS-A5/A6 | `a5-drag.json` | native detector drop/reject/cancel traces; separate pointer-fallback run, same pure session; touch normalization headless (firing → physical) |
| NS-A7/A8 | `a7-path.json` + ADR-0017 §3 | live ring+needle, bound 25%→65% sweep matches pure math to the pixel; UIPageLayout rejected on measured evidence |
| NS-A9/A10 | `a9-preferred-text.json` | reserved rect grew 44→63 under injected pref while painted TextSize stayed 18; live calibration fractions 0.367–0.451 vs 0.62 |
| NS-A11/A12 | `a12-bridge.json` | base nil; bridged modal followed focus, native-autoscrolled canvas 0→236, cleared on dismiss |
| NS-A13/A14 | `a13-resources.json` | real avatars ready / bad asset failed / stale completion rejected after release |
| NS-I1..I4 | `../test.json`, `game-suite.txt`, `prior-gates.txt` | suite 655 green; RascalRally 2404 green with zero game edits; prior gates re-run |
| NS-I5 | `verifier-architecture.json`, `verifier-platform.json` | 11 findings total, all fixed or dispositioned: billboard drag-fallback gating, authority entries, fake-clamp fidelity, **additive text-reservation reshape** (engine applies the preference as a fixed px offset — the multiplicative model under-reserved small text), default-size coverage, Selectable-restore, totalOffset rename; bridge slice re-driven live post-fix |
| NS-P1..P3 | `review-packet.md` | ONE ordered physical/assisted pass closes every remaining row |

## New durable engine truths (docs/lessons/)

- `uidragdetector-event-truths.md` — Drag events pass **Vector2 in LayerCollector space**; CustomOffset preserves Position authority; Enabled=false cancels.
- `mcp-vm-isolation-bindablefunction-bridge.md` — `_G` does not cross the MCP↔LocalScript VM boundary; bridge with BindableFunctions.
- Measured against docs: selection is NOT auto-cleared offscreen; selecting offscreen NATIVELY autoscrolls; `GuiState` of a selected object = `Hover`.

## Honest remainders

`PENDING_PHYSICAL` / assisted rows and their exact closing procedures live in
`review-packet.md`: physical-gamepad bridge contract (NS-P1), physical touch +
emulator-assisted checks (notch values, preferred-text sweep, touch-event firing,
scroll feel — NS-P2), device-floor performance smoke (NS-P3, full lab = Step 7),
and the reorder-while-actively-scrolling live interleave. The stage reports
**automation complete**; it is not "fully complete" until those rows close.
