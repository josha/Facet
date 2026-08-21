# Interim Studio pass (director-ordered, 2026-08-20, live session + emulator)

Session: open Facet-Showcase, sources injected from the live tree (final stamp
`b13ae47e-6816578`, tree ≈ HEAD post-INT fixes; 338 nodes, 0 refused).

| Check | Result |
|---|---|
| Demo sweep, first injection (pre-INT fixes) | 34/36 — card-rail + sorted-entries refused (INT-1 caught live) |
| Demo sweep, after c247f1b + b9e19da | **36/36 mounted** |
| §5 scenario surface in the showcase | LIVE for the first time (INT-2's boot-order defect was latent since the initial commit): `FacetScenarioAPI` up, `Facet_ScenarioState = "ready"`, steps served |
| Negative control | `Facet_Scenario = "nope"` → stamped `failed:unknown-scenario:nope`, no API, loud not silent |
| Selector precedence | scenario > showcase verified live (same place, attribute-driven) |
| Ten-foot type floor (ADAPT-7/TEN-FOOT groundwork) | Emulated console row: sampled labels scale exactly 1.5x (16→24, 22→33) |
| Device emulation | compact-phone-portrait (360x691), compact-phone-landscape, console-ten-foot (1920x1080) all driven via the matrix driver |

Instrument limits hit and recorded: VirtualInputManager lacks capability in
this VM (XP-B3 standing limit) — drag/tap interactions are not scriptable here;
the examples scenario exposes no resize verb yet. Therefore still owed to the
BATCHED pass: a scripted `resize` step for ex02 (prep item), the expand-plate
keyboard walk, carousel settle/snap rows (§12a-c), and the device half's real
input. The collapse/expand/snap behaviors remain fully proven headless through
the shipped gesture paths.
