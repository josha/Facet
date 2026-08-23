# Owed live work — task G8+G9 (band policy + lane exclusions)

Everything this round proved HEADLESSLY, and the half a headless proof cannot
make. Written at landing rather than after, so the list is what was owed rather
than what was remembered. Round: framework-gaps-phase2 task G8+G9, 2026-08-22/23.
Decision record: [ADR-0046](../adr/ADR-0046-band-safe-content-and-lane-exclusions.md);
register row ADR-0040 §B-24.

## 1. The showcase HUD, under the policy that replaced its hand-roll

**What changed.** `examples/gallery/scenarios/hud.luau` presents
`rootPolicy = "bandSafeContent"` instead of `edgeToEdge`, and the framework now
places its `topbar` row into `platformChrome.band` — where the fixture used to
hold the platform's cluster open with two `Spacer`s and pin the row's height to a
memo. The three per-column reserve regions and the whole give-way apparatus
(epoch token, monotone latch, sampled `onGeometry` reading) are gone, replaced by
one declared `exclusions` prop.

**Why a screen is owed.** The headless proofs are `tests/hud_composition.spec`,
`tests/hud_chrome_rotation.spec` and `tests/hud_paint_probe.spec` — 116 cases
between them, all green — but every one of them measures RECTS. The claim the
fixture exists to make is that the objective chip sits *level with the platform's
own buttons and never on them*, and that is a claim about pixels beside CoreGui,
which no headless target can see.

**Take:** the showcase place, Play, at two sizes (a wide window and a narrow one),
with the ride switch ON and OFF, and with the demo/settings chip row visible so
the exclusion is doing something. Captures via `tools/studio/capture_viewport.sh`.

**Before trusting anything read in Studio:** restart `studio_sync` (a stale server
serves old sources through a clean-looking inject) and probe a commit marker in
the injected source (rojo on CloudStorage can serve a stale framework under a
current game).

**And rebuild the places first** — the fixture changed, and the open copy predates
it: `tools/build_places.sh`.

## 2. Rascal Rally's Studio canary (controller ruling R5)

**What changed game-side.**

* `GearDockModel.placeInBand` is new and PURE, and `FacetSettingsGui` now docks
  the settings gear through it off `platformChrome.band` — three raw engine reads
  (`GuiService.TopbarInset.Height` and the difference of two `GetInsetArea`
  calls) and three manual connections (`TopbarInset`, the gear gui's own
  `AbsoluteSize`, the camera's `ViewportSize` re-bound per `CurrentCamera`)
  became one observation of one fact.
* `HudZoneModel.sponsorTopStrip` takes the band rect and spends it where it used
  to assume one (`y = 0`, a right edge of `vpW - MARGIN`).

**Why a screen is owed, specifically.** The gear is **raw Instances in a
`ScreenInsets = None` gui**, so no Lune spec can mount it. What IS proven
headlessly is that the arithmetic is identical — `band.h` is the strip height the
old code read, `band.x` the cluster offset it added, `band.y` the strip's top, and
`placeLocal` decides the rest unchanged (`tests/gear_dock_model.spec.luau`, four
new cases including the no-band control and a purity scan). What is NOT proven is
that the fact carries the same numbers the two engine calls did **on this game's
own client**, which is the one thing the 2026-08-14 live correction was about.

**Take:** Rascal Rally in Play, the settings gear beside the engine's own cluster,
desktop and one narrow shape. The gear must sit exactly where it does today.

**And the sponsor chip row beside it**, because `sponsorTopStrip` now clamps its
band to the platform's free strip: on a notched landscape that is 51px narrower
than the window margin it used to use, which is a FIX and therefore a visible
change on exactly that device class. Every shipped desktop viewport is unmoved by
construction (the live engine's strip reaches the window edge) and the spec pins
that as its control.

## 3. Owed, not done — the Rascal Rally chip band's own cutover

`FacetSponsor/HudScreen.CHIP_PRESENT_OPTS` still presents `rootPolicy =
"edgeToEdge"`, and `buildChipBand` still places the row with four hand-computed
Readables (`offsetX`, `offsetY`, `bandWidth`, `bandHeight`). Its own header names
the hole this round closed: *"That row is the PLATFORM'S TOPBAR STRIP, and it is
outside every content-safe root policy by definition."*

The cutover is now one policy string plus a `UI.Composition` with a `topbar`
region, and the four Readables die with it. It was NOT taken in this round because
it moves a **shipped HUD surface's placement** and the honest verification for
that is a device look, not a headless rect — and this session could not take one.
It is a contained, well-specified follow-up.

## 4. Booked, control-side: `Controls.Stepper` at a narrow content box

Measured while the all-policy gutter floor was built (§5): at a **343px content
box** (a 359px phone under it) `Controls.Stepper`'s own row overflows by **7px
under Glossy Touch**. The control has no shrink term at all — a label and three
fixed affordances — so the row cannot give way. The finding is recorded here rather than lost with the
arm that produced it; the matrix itself is back at its own 359x718.

This belongs to the Stepper, not to the band policy. It is a real narrow-phone
finding for the roomiest shipped package.

## 5. DEFERRED WITH ITS NUMBER — the gutter floor on the other two content policies

**The audit's §9 asks for `themeMetrics.space.gutter` to floor EVERY content
policy. This round ships it on `bandSafeContent` only, and the reason is a
measurement rather than a preference.**

It was BUILT the audit's way first, and run. Flooring `coreSafeContent` (the
default) and `deviceSafeContent` too costs every surface 16px of measure, and the
shipped example corpus does not have it:

* `tests/overflow_sweep.spec.luau`: **255 findings across 51 of its 95
  scenarios** — content that no longer fits its own box. **249 of them are at the
  two narrowest swept viewports** (320x640 and 640x320), which is the device class
  the gutter exists to protect.
* `tests/theme_matrix_audit.spec.luau`: two rows red at its compact phone, one of
  them a shipped CONTROL (§4).
* The fast tier alone: 77 assertions across 35 spec files, every one a clean
  ±8/±16 shift — all of them re-pinned in the arm that was built, then reverted
  with the narrowing.
* Rascal Rally is nearly untouched: three pins, one of them a latent coincidence
  rather than a number.

**What it would take.** Fifty-one example scenarios re-tuned for a 16px-narrower
content box at the narrowest phone, plus the ~120 characterisation numbers across
both repos. That is a round of its own, and the trade it is making — content
never touches the glass, against content that no longer fits — is a director's
call rather than an implementer's.

**What it takes to land it.** ONE branch condition, in `renderer.luau`'s policy
resolver: `if rootPolicy == "bandSafeContent" then` becomes `if rootPolicy ~=
"edgeToEdge" then`, and the top stays exempt only for the band policy. The comment
above it carries this measurement so the next reader does not have to re-derive
it.

**What is NOT deferred** is the finding underneath the clause: the HUD demo's
hand-rolled version had the floor and the shipped policy did not. The surface it
rides is `bandSafeContent`, which has it now — which is why the hand-roll could be
deleted rather than copied.
