# tvOS / gamepad review of 618b4d95 — decisions and Studio evidence (2026-09-11)

Decisions: Alert action placement is role-driven (cancel leads a row, closes a
stack); the stack form is used for >2 actions, compact widths, ten-foot displays
and accessibility text sizes; the region is one keyed `AdaptiveStack` so a live
flip moves the mounted buttons. The inferred-layout directional search now shares
the focus-section scorer. Ten-foot type calibration (audit item 6: Facet body
24px vs tvOS 29pt at 1080p) is left for a physical-display measurement.


Place: `build/Facet-Showcase-task1.rbxl` built from branch `task1-tvos-review`
(stamp `task1 51248627`), opened with `RobloxStudio -localPlaceFile`, driven
through `workspace.FacetShowcaseAPI` and `InputAction:Fire` edges (VirtualInput
refuses the DPad keys: "permanently bound to a CoreGUI core action").

Evidence class: `studio-emulated` (StudioDeviceSimulatorService, ActualResolution).
Screenshots were read inline through the Studio MCP and are not stored.

| Cell | Device preset | Observed |
|---|---|---|
| Alerts and confirmations, open | `ps5` 1920x1080, distance inferred `ten-foot` | Card centered; actions STACKED full width, `Replace save` (destructive, red) on top, `Keep previous` (cancel) last with the ten-foot focus ring; title 27px-class heading with caution mark |
| Navigate up (Fire -1 on `Nav-ReplaceSave/Navigate`) | `ps5` | Focus ring moves to `Replace save`; nothing activates |
| Cancel (Fire true/false on `Nav-ReplaceSave/Cancel`) | `ps5` | Alert dismissed, `report().status = "Previous save kept."`, `presented = false` |
| Live `distance("near")` while open, then `distance("ten-foot")` | `ps5` | Same `TextButton` instances before/after both flips (`/ReplaceSave/Center/Card/Actions/Order/[Cancel]/Cancel`, `…/[Replace]/Replace`); row form with cancel LEADING at near (119x46 + 111x46, textSize 18), stack at ten-foot (textSize 27) |
| Alerts and confirmations, open | `generic_handheld_720` 1280x720, distance `near` | Row form, cancel leading, focus on cancel; card 382x158 |
| Tabs, nested | `ps5` | App bar placement `topBar` (policy), centered hugging strip with focus ring on the selected pill; nested page bar below |
| Tabs, nested | `generic_handheld_720` | App bar placement `sidebar` (policy; emulator reports KeyboardAndMouse — the emulator cannot publish a gamepad preferred input, so the near-gamepad home is headless evidence only: `tests/adaptive_presentation.spec.luau`) |

Not established here (needs a physical device): gamepad `preferredInput` on a
handheld, physical TV overscan, ten-foot readability at distance.
