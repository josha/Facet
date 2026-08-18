# Studio baseline — pre-rename representative scenarios (2026-08-17)

Captured before any rename/source edit, against the tree at `fe920dc` (source
modules unchanged since `cc01667`; registration commits touched no `src/`).

## Preflight (execution contract §4)

| Fact | Value |
|---|---|
| Place | `LuauUI-Showcase.rbxl`, open session, Edit → Play via Studio MCP |
| Studio version | 0.734.0.7340915 |
| Viewport | 749x380 (> 1,1; game view visible; command execution and canary capture worked) |
| Source-state proof | Session `ReplicatedStorage.LuauUI.render.renderer` Source = 199665 bytes and `controls.table` = 196790 bytes, byte-equal to `src/render/renderer.luau` and `src/controls/table.luau` on disk |
| Presenter mounted once | PlayerGui carried exactly one `LuauUI_ShowcaseBackdrop`, one `LuauUI_ShowcaseChrome`, one `LuauUI_AdaptiveScreen`, sheet `LuauUIStyle`, theme sheet `LuauUITheme studio-neutral` |
| Canary | `LuauUIShowcaseAPI.current` → `{current: all-controls, mounted: all-controls, ok: true}` |

## Demo sweep — all 36 catalogue demos

`showNext` walked the full catalogue once. Every row returned
`current == mounted` and `ok = true` (the API distinguishes what was ASKED from
what is ON SCREEN, so this is a delivered-mount claim, not an ask claim):

row-actions, card-rail, with-animation, preferred-transparency, progress-ring,
flow-wrap, lifecycle-hidden, row-capabilities, text-degrade, variable-extents,
measured-extents, table-virtualized, virtual-grid, virtual-hgrid,
sensory-feedback, hud, surface-overlap, branch-scope, sorted-entries,
time-curves, foreign-content, async-images, canvas-group, level-picker,
callout, menu, tab-view, nested-tree, ex01–ex07, all-controls.

Raw sweep JSON: `demo-sweep.json`. On the final all-controls mount the adaptive
screen held 126 GuiObjects with root `/AdaptiveScreen` at 749x260.

## Theme swap

`themes` listed 9 player-facing entries (the test-only stub correctly absent).
`pickTheme("fantasy-parchment")` → `{ok: true}`; the theme StyleSheet
`LuauUITheme fantasy-parchment` appeared beside the base sheet and the current
package read `fantasy-parchment`/`Daylight`. Reverted to `studio-neutral`
(`ok: true`) and stopped Play.

## Captures

Two MCP screen captures were taken and reviewed live by the controller
(capture ids `baseline_all_controls_neutral`, `baseline_all_controls_parchment`):
studio-neutral showed the dark all-controls board (steppers, sliders at
Brightness 40, segmented chips, Save/Reset/Delete row, focus ring on the Volume
minus stepper); fantasy-parchment showed the same board re-chromed in
nine-slice parchment with the wax-red destructive button. The MCP transport
returns capture bytes to the session rather than a file path, so the paired
machine-readable facts above (sweep JSON, sheet names, theme package ids,
geometry) are the stored oracle for post-rename comparison; post-rename
captures must be reviewed against the same states.

## What this baseline does NOT claim

Studio evidence only: no physical-device, real-touch, real-gamepad, or feel
claim. The gallery device-matrix rows and the Rascal Rally Studio canary are
captured in their own sessions (the RR canary immediately before the RR-side
rename lands, same session as its post-change verification).
