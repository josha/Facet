# Release-candidate review — close-out (RC-24), 2026-08-21

## The batched Studio pass (controller-run, this session)

Place: the rebuilt `Facet-Showcase.rbxl` opened fresh (byte-verified against
HEAD: renderer 198,974; init 36,159; boot_mode present). Driver installed from
the served tree.

| Row | Result |
|---|---|
| §14a oracle sweep, 36 demos x 5 views (portrait 360x691, landscape 678x339, tablet 1080x810, desktop 677x338, ten-foot 1920x1080) | **180/180 clean** — zero settled no-fit, zero zero-boxes, zero true off-viewport (oracle corrected mid-pass for scroll canvases and the inset band; both corrections are recorded instrument lessons) |
| §14b rotation round-trip (hud, portrait->landscape->portrait) | Every zone present both ways; **back-to-portrait byte-identical to the original portrait**; Feed alive in landscape (DIR-5 closed live) |
| DIR2-1 pills paint | Clock "2:14 ›", Health "84 ›", Tasks "Tasks 1/3 ›", Feed line — values + chevrons, "11 of 11 painting" (capture `pass_hud_portrait_neutral`, controller-eyeballed) |
| §14c theme axis (fantasy-ornate portrait: hud, all-controls, ex02, callout, menu) | One finding: the menu demo's blocked card sits 23px below the fold under ornate metrics on a non-scrolling page — a live instance of the audit's CONTESTED overflow-default cell (renderer-extraction charter), recorded not re-fixed. hud ornate portrait captured (`pass_hud_portrait_ornate`, eyeballed: DIR-2/DIR-3 cured; eye-note: ammo values snug against the declared crown-art overhang — director's call) |
| DIR4 live verify (console row, stamp e35325e0-6907328) | Chips INSIDE the safe band at (102,72) vs (12,12) before — the body stays at its overscan inset (no double-inset dead band); LB/RB glyphs painted beside their chips under gamepad (18px text = 12 × the 1.5 ladder); the full section state machine proven at the action layer: switch demos↔settings without closing, same-shoulder closes, either shoulder opens from closed — all six transitions. Raw key→IAS delivery could NOT be exercised this session (every injected key including Backquote failed to deliver — a session-level condition; the instance census shows all contexts/bindings correct and sink=true live), so raw shoulder delivery joins the device packet, where the matrix row's E4 already places it |
| §13a ladder live (console row, Large) | themeMetrics live: density ten-foot, spaceM **24**, controlHeight **66**, typographyScale 1.5, distanceProfile ten-foot; engine paint agrees (chips 146/117×69, controls 66-69px tall) |
| §13c overscan composes once | env: authored overscanInsets 0, **effectiveOverscanInsets 90/60/90/60** — applied once, never 135/90 |
| §13d lane cap + row rung (console vs desktop) | virtual_grid: console 1920px = **4 lanes @404** (scaled minColumnWidth; naive would pack ~6 @287), desktop 1280px = 4 @289, gap 18→27 = ×1.5 proportion held; table_virtualized console rows take the **84px distance rung** |
| §13e paint authority off glass | GetStyled on the Large surface: hairline UIStroke Thickness **1** (not 1.5), scrim token **0.45**, authored capsule radius passes through unscaled (999, not 1498) — the paint channel is metric-untouched; no plain-read used. The showcase's default (image-paint) path mounts no panel UICorner to read; the radius-authority pin stays the TEN-FOOT wave's headless spec |
| item 5: haptics calibration surface (sensory scenario, desktop + live bridge) | Adapter installs on macOS Studio and answers honestly: state **refused** ("a gamepad IS connected and reports no vibration motor"), support() unsupported, **decorated 12** buttons holding a press effect. Per-phase counters MOVE through the scripted route: defaults profile plays contact/settle/tick, release 2 / select 1 / plays 3; **fallback profile reachable** (UIClick/UIHover/UIHover, plays counted). Pool: one HapticEffect per distinct sensation (3), defaults arm builds **Custom**-type effects. The sub-44px none-control expander: host carries Facet_ActivationFeedback="none" with PressHapticEffect nil live; the expander mirror is pinned headless (haptics.spec "a hit expander feels EXACTLY like the control") — no sub-44 instance materialized at this viewport to read directly |
| item 5's find: the scripted calibration route was DEAD | Driving the driver half found it: the runner invokes steps as fn(session, payload) and the sensory scenario's three parameterized steps declared ONE parameter — setPlayHaptics:true left the adapter off, setProfile poisoned a signal with the session table, and the cycle-blind serializer stack-overflowed on it. Fixed red-first (3ad40b0): canonical (_session, payload) arity, the spec now drives the runner's own call shape, serializer names a cycle instead of dying. The headless suite was green the whole time because the spec called the steps payload-first — the call shape the bridge never uses |
| §13 ten-foot eye row | `pass_allcontrols_tenfoot` captured (1.5x type + controls, proportions held) for the director's judgment |
| style-editor-sync re-capture | theme_authoring scenario driven live (installPackage:fantasy_parchment stamp 9a3b8dd8 → exportDump via controller); 99 tokens; `--check` **PASS** with no source change, exactly as the row's note predicted |
| §5 scenario surface | Alive in the showcase for the first time (boot_mode); negative control `Facet_Scenario="nope"` stamps `failed:unknown-scenario:nope` loudly |
| RascalRally canary | Built place (default.project.json + finished Facet tree) boots clean: track, AI grid, client driving online, zero Facet errors. Sponsor surface unreachable in an unpublished place (SponsorService requires DataStore before creating its remotes) — those rows move to the published-place device half, honestly |

## Instrument limits hit (recorded, not worked around)

VirtualInputManager lacks capability in this VM (XP-B3), so raw input rows
(DF-7 keyboard measurement, expand-plate click, carousel flick, pad
arbitration) and the sponsor rows ride the device half. The scenario registry
has no `expand` step yet (follow-up noted).

## Suites and gates at close

Suite endpoints: framework **6854**, RascalRally **3449** (clean git-archive
exports). Prior-gate sweep: 14/16 gates PASS standalone; theme-packages'
style-editor-sync row closed live above; its derivative prior-gates row closes
with it. The release-candidate-review gate's remaining non-PASS rows are the
honest device/report rows (df7 PENDING, device similarity
FAIL_ENVIRONMENT/non-blocking) and this file's own row.

## The device half (the director's packet)

Republish the rebuilt showcase (manual), then: the DIR device recheck (themed
HUD, rotation, chip edge), the expand-plate click + X close feel, carousel
flick/peek, adaptive_controls at Largest, the haptics paired-iPhone packet,
the shoulder raw-delivery re-check on a real pad (L1/R1 open/switch/close the
showcase sections; the old-session "R1 dead" observation was never reproduced by
anything headless and both bindings are provably live — one press must do ONE
thing), ButtonB closing the panel (CoreGui-bound, injection refuses it),
DF-7 with a real keyboard, RR sponsor cancel/skip on pad + touch driving §7c
server reads, and the ten-foot 1.5x judgment on a real television if
available. Every row's exact procedure is in
`.superpowers/sdd/release-candidate-review/batched-studio-pass-plan.md` and
the haptics packet.
