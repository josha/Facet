# Post-rename Studio canary — the Facet tree, live (2026-08-17)

Session: the open showcase place (never saved), old-name tree deleted in the
session copy, then the Facet gallery injected from `tools/lune/studio_sync`
(stamp `2a804f5b-6363652`, 320 nodes, 291 sources patched, 0 refused, 0 failed,
`Facet_SourceStale = 0`).

| Check | Result |
|---|---|
| Gallery boot under Facet names | `[Facet Gallery] running 0.9.0; focus=/GallerySettings/Music`; ScreenGuis `Facet_GallerySettings`, `Facet_GalleryThemePicker`; zero console errors |
| Renamed dev attributes | `Facet_SourceStamp` set by inject; theme picker instructs `Facet_NativeStyle = true` |
| Scenario drive | `workspace.Facet_Scenario = "adaptive_controls"` in Edit → Play → `workspace.FacetScenarioAPI` present with report/freezeEnv/setEnv/list/steps/measureNow/step/reset |
| Scenario report | sourceStamp `2a804f5b-6363652`, scenario `adaptive_controls`, focusPath `/AdaptiveScreen/BodyScroll/Body/Settings/Volume/Dec`, 12 ledger rows, `diagnostics: []` |
| Mounted screen | `Facet_AdaptiveScreen`; capture `facet_canary_adaptive_controls` reviewed: same all-controls board as the pre-rename baseline capture (stepper focus ring, Brightness 40, segmented quality, Save/Reset/Delete) |

What this does NOT claim: no physical input, no device rows, no Rascal Rally
canary (that runs in the session that opens the RR place). The showcase-place
`.rbxl` on disk was rebuilt by the rename task; this session verified the same
sources through injection, not the rebuilt file itself — the clean-clone check
(RC-6) opens the rebuilt artifacts.
