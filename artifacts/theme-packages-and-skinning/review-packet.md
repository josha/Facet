# theme-packages-and-skinning — review packet (physical + human rows)

**Gate:** `theme-packages-and-skinning` · **Ledger:** `acceptance-ledger.md` §D · **Updated:** 2026-07-25
Automation cannot close these rows. Each section is one focused pass with the exact
fixtures and files named — nothing here requires assembling state or reading logs.

Driving recipe (used by every Studio section): `lune run tools/lune/studio_sync`,
run `tools/studio/inject.luau` via the MCP in Edit, set
`workspace.LuauUI_Scenario = "theme_authoring"`, press Play. Steps run through
`workspace.LuauUIScenarioAPI.step` (`"installPackage:fantasy_parchment"`,
`"swapTheme"`, `"editMetricLive"`, `"exportDump"`, `"failMissingAsset"`, …).

## TP-P1 — Style Editor authoring workflow (E5, human, ~10 min)

Judgment requested: can a designer find and edit the theme without guidance, and does
`docs/guide/09-custom-themes.md`'s labeling match what they experience?

1. Play the gallery with the theme scenario; run step `installPackage:fantasy_parchment`.
2. Style Editor → sheet **`LuauUITheme fantasy-parchment`** → child sheet **`Theme Daylight`**.
3. Edit a paint token (`Surface`) → the running screen repaints immediately.
4. Edit the metric attribute **`Space_m`** (16 → 32) → spacing re-solves live, no remount.
5. Edit **`Type_body_font`** → text re-measures and repaints in the new face (nothing clips).
6. Run step `exportDump`, save the JSON, run
   `lune run tools/lune/theme_sync_cli -- --dump <dump.json> --package examples/themes/fantasy_parchment.luau --check`
   → PASS confirms the one-export workflow.
7. Record found/not-found per step and any label that mismatched the guide.

**Ready.** (The automated halves of steps 3–6 are already proven —
`b-a6-editor-sync.json`; this pass judges *discoverability*.)

## TP-P2 — Fantasy Parchment on a real phone (E4, physical)

1. Publish/run the gallery on a physical phone (retail client); install `fantasy_parchment`.
2. Finger-target every control (steppers, slider, chips, action row) — comfort at the 47 px floor.
3. Swap Daylight ↔ Candlelight and Parchment ↔ Neutral; record perceived cost/hitches
   (Studio-derated swap step is 5.1 ms — the device number is what matters).
4. Judge nine-slice crispness at device DPI and Fondamento rasterization at body size.
5. Focus a TextField under the field skin and type — the chrome yields while editing;
   confirm caret and glyphs are visible and the skin returns on blur.

**Ready.**

## TP-P3 — Readability/feel review of the stored captures (E5, human, ~5 min)

Open these files in `artifacts/theme-packages-and-skinning/captures/` and say whether
each reads well (hierarchy, practical contrast, platform feel, ornate chrome vs legibility):

| File | What it shows |
|---|---|
| `TP-A13_compact-phone-portrait_parchment_daylight.png` | Parchment, phone portrait |
| `TP-A13_compact-phone-landscape_parchment_daylight.png` | Parchment, phone landscape |
| `TP-A13_tablet-landscape_parchment_daylight.png` | Parchment, tablet |
| `TP-A13_desktop-standard_parchment_daylight.png` | Parchment, desktop |
| `TP-A13_console-ten-foot_parchment_daylight.png` | Parchment, ten-foot (type ×1.5) |
| `TP-A13_desktop-standard_parchment_candlelight.png` | Candlelight theme swap |
| `TP-A10_desktop_classic-desktop_day.png` | Classic-desktop reference |
| `TP-A10_desktop_glossy-mobile_daylight.png` | Glossy-mobile reference (post gradient retune) |
| `TP-A10_desktop_scifi-hud.png` | Sci-fi HUD reference (post gradient retune) |
| `TP-A12_desktop_parchment_asset-fallback.png` | Missing-asset native fallback |

Style observations already logged for this pass (`b-a13-matrix.json` observations):
Picker option rows are the ink-wash *selection* slot (deliberately not nine-sliced);
disclosure headers are plain-surface and undecorated; narrow stepper buttons render
the button art as a tall slot. Say keep or change.

**Ready.**

## TP-P4 — Low-end performance (deferred by decision)

Not claimed this stage. Step 7's performance lab owns the low-end Android row for the
most expensive skin. The Studio-derated numbers on record: swap step 5.1 ms,
`SetDerives` 0.039 ms @ 600 nodes, parchment = 33 decorations + 11 text lifts vs 0 flat.

## Open follow-ups this packet also carries (automatable, honestly not yet done)

- **Locale axis (TP-A13):** the all-controls fixture has fixed English labels and no
  locale seam, so the localized/long-string axis of the pairwise matrix was NOT
  driven. Follow-up: add a long-string/pseudo-locale axis to the fixture and drive it
  at phone-portrait under Parchment. Until then the wrap/preferred-text evidence is
  the nearest coverage.
- **TextBox editing-yield live row:** the fixture mounts no TextField, so the
  chrome-yield-while-editing path is headless-spec'd but not live-driven; TP-P2 step 5
  is the physical check, and a fixture TextField is the automatable follow-up.
- **Engine probes queued for the next Studio session:** `StyleRule:GetProperties()`
  round-trip of `$Token` refs (the metric-rule push assumes verbatim round-trip);
  bare `:NonInteractable > .luau-chrome-*` selector matching on a disabled control;
  live mutation of a `Gradient*` theme token; a two-frame capture across a swap to
  bound paint/geometry tearing; whether `.luau-selected > .luau-chrome-*` tint rules
  are reachable given selection-slot classification.
- **Sci-fi typography defects (pre-existing, seen in both the pre- and post-fix
  captures, NOT from the director fix round):** the toolbar "Play" wraps to
  "Pla / y" (the Michroma face is wider than the button's offer at the toolbar's
  minMax height — a preferred-text/measure follow-up), and the Advanced
  disclosure caret renders as tofu (the glyph is missing from Michroma; the
  caret should come from a glyph-safe set or a semantic icon asset, which is
  charted in rich-skinning v2 §5).
- **Five-view matrix re-drive at the post-fix stamp:** the director fix round
  moved the parchment spec stamp (26444f50 → 54b99b50) and changed fixture
  geometry (badge tiles are now real 28px badges), so the stored b-a13 rows and
  captures describe the PRE-fix build. Desktop-view evidence was re-taken fresh
  (captures/fixround/, sha-pinned in the TP-P3 ledger row); the full five-view
  re-drive rides with the physical pass (TP-P1..P4) rather than blocking the
  fix round.
