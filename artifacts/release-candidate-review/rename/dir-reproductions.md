# Director-round reproductions (2026-08-17, rebuilt Facet-Showcase.rbxl, Studio emulator)

Session: second Studio instance opened by the controller on
`examples/places/Facet-Showcase.rbxl` (byte-verified against `664d974`:
renderer 199,650 / table 196,778). Post-rename sweep first: all 36 demos
`current == mounted, ok` through `FacetShowcaseAPI` — the rebuilt artifact
itself now has live proof.

## DIR-2 / DIR-3 — themed HUD overflow + overlap: REPRODUCED, current build

fantasy-ornate (Grand Hall), hud demo, topbar strip ON.

At 749x380 AND at emulated compact-phone-portrait 360x691:
- Weapon rail overlaps the showcase Settings chip: rail x=262..352 y=0..119 vs
  chip x=196..290 y=8..75 (28px x-overlap; matches the director's photo).
- Settled TextFits=false: ammo labels in 3-4px-wide boxes; "+50/+120/+300" in
  12x21; `"Tasks 1/3"` painting inside a 48x0 (ZERO-HEIGHT) box.
- Captures `dir23_ornate_hud_749x380` reviewed: clock plates pile over the
  Settings chip; Rifle plate overlaps the FPS readout; crown icon overflows the
  task plate.
- Mechanism (two layers): the beside-chrome top band (Clock/Rail placed beside
  the showcase chips) has NO give-way when themed chips consume the row (chips
  under ornate are 67px tall, 282px wide → free strip is smaller than the
  band's need), and zone extent math does not spend the active package's chrome
  insets (the exact O-25 class the Table already fixed). The themed overflow
  sweep is blind because it runs the hud fixture without the showcase chrome
  (no appChromeRects) and its oracle has no painted-text-fits / zero-box check.

## DIR-5 — rotation loses left content: REPRODUCED, live emulator rotation

hud + ornate; driver row `compact-phone-portrait` (360x691) →
`compact-phone-landscape` (pinned samsung_galaxy_s22_ultra, 678x339):
- Feed zone before: y=455..472 x=8..85 (visible, "Ravi eliminated Mo").
- After rotation: y=-58..-58 x=8..8 — 0x0 at the inset corner. Debug panel:
  `13 of 14 rows wanted · skipped: Feed`.
- Theme swap (studio-neutral and back, full repaint + metrics) does NOT
  restore Feed — so the give-way DECISION latches; only a composition INPUT
  change (the URL-bar toggle, on the director's device) re-decides.
- Combined with the green model-level spec (tests/hud_chrome_rotation.spec
  proves flipped == fresh when all six platform facts arrive in ONE batch),
  the live divergence isolates to the real adapter's rotation fact
  delivery/ordering (the PLAT-3 stale-inset family) feeding a give-way
  decision that is not re-evaluated when the facts settle.
- Capture `dir5_feed_collapsed_landscape` reviewed.

## DIR-1 — chip left-edge clip: NOT reproduced in emulation

Chip left margins measured at 360x691: fantasy-parchment x=8, compact-pointer
x=6, classic-desktop x=4 (no skin image extends left of any chip rect;
classic-desktop has no skin image). The device clip therefore rides a
device-only difference (ScreenInsets/SafeAreaCompatibility never being set —
PLAT-17 — is the standing suspect). Fix direction regardless: floor the
screen-edge gutter at 8px under every package; device recheck after republish.

## DIR-2 addendum — the text-overflow mechanism, pinned (A/B vs the pre-rename artifact)

The pre-rename showcase artifact (extracted from git at `cc01667`) and the
rebuilt Facet place were both driven on the same machine. Both carry the
native-style attribute in the built place (`LuauUI_NativeStyle` /
`Facet_NativeStyle = true` — set by the build tooling) and both paint the
ornate font through StyleSheets: `GetStyled("FontFace")` = Fondamento while the
plain `FontFace` property reads LegacyArial — the documented sheet-paint
instrument trap, which this session initially fell into (recorded as an
instrument lesson; the extended sweep's oracle must use STYLED reads).

So there is NO font-application regression and no rename regression here. The
real text-overflow mechanism, measured: plate/chip WIDTH math does not spend
the effective styled typography — under fantasy-ornate the styled "Round 3 ·
Capture" measures 70px and its plate solved 72px at landscape (1px slack; the
narrower device portrait plate spills — the photographed overflow), the topbar
objective chip's width-swap logic measures with neutral metrics, and the
give-way squeeze produces degenerate boxes ("24/90" in 4px, "Tasks 1/3" in a
48x0 box) instead of flooring/eliding. Engine `TextFits=false` on the styled
font is the honest painted-overflow signal in every case.

## Fix contracts derived (queued for the DIR wave after R1 lands)

1. Zone extent math consumes active-package chrome metrics (O-25 class).
2. Beside-chrome band gives way (wrap/disclose) when free width < need; solved
   rects never overlap app chrome.
3. A zone the give-way pass skips is DISCLOSED (reachable via the overflow),
   never painted at 0x0; text never paints in a zero-extent box.
4. Give-way decisions re-evaluate when platform facts settle: headless
   regression publishes the six rotation facts UNBATCHED in device order and
   asserts the settled decision equals the batched decision.
5. Themed overflow sweep gains the showcase-chrome axis (appChromeRects +
   strip-on) and a painted-text-fits/zero-box oracle; negative control = the
   pre-fix tree must FAIL the extended sweep.
6. Gutter floor ≥ 8px per package (DIR-1) + explicit ScreenInsets decision
   (PLAT-17); DIR-1 device recheck after republish.
7. Width/extent math for text-bearing plates and width-swapped labels measures
   with the EFFECTIVE styled typography (themed font + size + lineHeight), and
   the extended sweep asserts painted styled TextBounds fit inside the box
   interior (chrome insets spent) per package per viewport — using GetStyled
   reads, never plain property reads.
