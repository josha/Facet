# Paired evidence index for the ui-designer integrated review (round 1)

**Assembled:** 2026-07-30. Layers L1 (entry/lifecycle), L2 (table/list/map/
poses), L3 (cards) are live behind `UseLuauUISponsor`. All captures below were
taken at the SAME device presets with states held by the shared scenario rig
(`RascalSponsorScenarioAPI`); the rig drives both presenters through the same
replicated seams, one mounted at a time.

Suites at assembly: game 2627 / LuauUI 2611, green. Legacy checksums 11/11.

## Capture pairs (legacy ↔ luauui), all in this directory

| Surface/state | Legacy | LuauUI |
|---|---|---|
| Table max, phone portrait | `PS-B3-legacy-max-iphone16-portrait.png` | `PS-T1-luauui-max-iphone16-portrait.png` |
| Table max, phone landscape | `PS-B3-legacy-max-iphone16-landscape.png` | `PS-T1-luauui-max-iphone16-landscape.png` |
| Table max, tablet | `PS-B3-legacy-max-ipad9-landscape.png` | `PS-T1-luauui-max-ipad9-landscape.png` (pre-glyph-fix labels; geometry valid) |
| Table max, desktop 1080 | `PS-B3-legacy-max-desktop1080.png` | `PS-T1-luauui-max-desktop1080.png` (pre-glyph-fix labels) |
| Table max, TV 1080 (44 dpi) | `PS-B3-legacy-max-androidtv1080.png` | `PS-T1-luauui-max-androidtv1080.png` (pre-glyph-fix labels) |
| Follow/min, phone portrait | `PS-B3-legacy-min-iphone16-portrait.png` | `PS-T1-luauui-min-iphone16-portrait.png` |
| Follow/min, phone landscape | `PS-B3-legacy-min-iphone16-landscape.png` | `PS-T1-luauui-min-rawpane.png` (raw pane; re-shoot at phone preset cheap if needed) |
| Armed card + aim affordances | `PS-C1-armed-hand-legacy-iphone16-landscape.png` | `PS-C1-armed-hand-luauui.png` (raw pane) |
| Sponsor results, phone landscape | `PS-R1-legacy-results-sponsor-iphone16-landscape.png` | — (L6 not built yet) |
| Sponsor results, phone portrait | `PS-R1-legacy-results-sponsor-iphone16-portrait.png` | — (L6 not built yet) |

Geometry/state companions: `baseline/studio/*.geometry.json` (legacy),
`LuauUISponsorDevReport` JSON snapshots quoted in `PS-L1-L6-entry-lifecycle-live.md`,
`PS-T-table-list-live.md`, `PS-C-cards-live.md`. Command traces + counters in
those files.

## Open items already queued for this review

1. Split-axis keying at extreme desktop aspects (options + recommendation in
   `PS-T-table-list-live.md` finding 3) — ruling requested.
2. CoreGui player list occludes the racer list's top-right on phone (legacy
   identical) — game-policy question, not presenter.
3. OWN-D13 (server-rejection fly-home) — needs the legacy live observation +
   a ruling; see `PS-C-cards-live.md`.
4. UI_SPEC §12 Q1–Q5 remain provisional as built (Q1 no-op Cancel via
   cancelPolicy; Q3 selection=watched) — confirm or amend.
5. `disconnected` row state exists in the new build with NO legacy expression
   — record as intentional difference or drop.

## Known evidence gaps at assembly (do not mistake for parity claims)

- LuauUI tablet/desktop/TV captures predate the label-glyph fix (geometry
  unaffected); re-shoot alongside the L4-L6 sweeps.
- Racer-role results (both presenters) not yet captured.
- Live tap-commit/drag/toast rows ride the human/physical pass (injection
  limits recorded in `PS-C-cards-live.md`).
