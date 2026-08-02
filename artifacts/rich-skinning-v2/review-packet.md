# rich-skinning-v2 review packet — irreducible human/physical rows

**Status: COMPLETE for the automated rows** (skeleton created 2026-07-25 at stage
start; procedures, capture lists and decision packets filled in by the closing
sessions — last by build package P6). Ledger: `acceptance-ledger.md` §D. Nothing
here is closable by emulator or headless evidence.

**RS-A16 IS `PASS_AUTOMATED` AS OF 2026-07-26 — the FIFTH attempt (take 8) at the
final matrix drive measured ALL NINETEEN rows CLEAN and replaced ALL NINETEEN canonical
captures at the final stamp `66599d58-1744436` (suite 1757).** Five view rows ×
{`studio-neutral`, `fantasy-ornate`, `pixel-quest`} plus the four RS-A14 platform-pair swap
rows. Every capture is the WHOLE emulated screen at true aspect, sha-pinned, paired with a
full machine-readable trace in `rows/`. Full evidence: `rs-a16-matrix.json`.

**The honesty debt is CLEARED.** No canonical `RS-A16_*` capture predates this drive; the six
take-5 phone/pair images and take-7's thirteen are all replaced. `b-a13-matrix.json` from Step
3.5 is superseded as CURRENT matrix evidence and stands only as pre-fix history.

**D1, D1b, D2, D3, D4 and D5 are all independently re-confirmed FIXED** by a driver that wrote
none of them — on all nineteen rows. The D5 headline: on both phone presets under both art
packages `undecodedJudgeable = 0`, `failedAssets = []`, `fallbackSlots = []` and ZERO nodes wear
`luau-chrome-fallback`/`luau-chrome-mute`, read at +2.5 s and again past the 5 s grace deadline,
while 16–105 art instances are correctly spared as `clipped`. `compact-phone-landscape/`
`fantasy-ornate` — the row that stopped take 7 — now draws the ornate CROWN mid-bar in its own
capture instead of a flat gold slab.

**One NON-product finding, `RS-A16-E1` (`FAIL_ENVIRONMENT`).** The `theme_authoring` scenario
leaks its theme controller across `api.reset()`, so the library's one-controller-per-environment
guard correctly refuses every later install in that Play session — and the scenario swallows the
refusal into a string while still committing the decoration and metric halves, leaving ornate
decorations under a `pixel-quest` sheet (127 art instances with reason `noSource`, two value slots
UNPAINTED, 8 unfit text nodes, and three different answers to "which package is live"). The
framework side is right; the fix is owed in the harness. The drive recovered by re-booting the
session and never resetting after an install, and every claimed row now carries a verified live
sheet name plus a `paintController == "controller"` assertion, so a stale paint authority cannot
hide inside a claimed row again. Details in `rs-a16-matrix.json` → `environmentFindings`.

---

## RS-P1 — Director readability/feel review (E5)

**Judgment requested:** do these read well — hierarchy, contrast in practice,
pixel crispness — and does "the art IS the interface" hold up?

Every file is under `artifacts/rich-skinning-v2/captures/`. Open them in this
order; it goes centerpiece → pixel → platform pair → the earlier per-capability
reads.

### The four reference packages (P5 — the nine captures this row exists for)

| # | File | What it shows | What to judge |
|---|---|---|---|
| 1 | `RS-A12_adaptive_desktop_fantasy-ornate_grand-hall.png` | the whole control gallery under Fantasy Ornate, Grand Hall theme | the six-layer panel: does the frame read as one carved object, or as five stickers? Is the plaque legible where it overhangs? Do the corner ornaments fight the content? |
| 2 | `RS-A12_adaptive_desktop_fantasy-ornate_crypt.png` | the same tree, Crypt theme (palette-only swap) | same geometry, different light. Does Crypt hold contrast where Grand Hall does? The weakest measured pair is 6.38:1 — but a number is not a read. |
| 3 | `RS-A13_adaptive_desktop_pixel-quest_quest.png` | the gallery under the pixel package | is it crisp at 1:1? Do the plates read as pixel art or as blurry pixel art? Is the selected row obviously a *different plate* rather than a highlight? |
| 4 | `RS-A13_zoom9x_pixel-quest_pixelated-vs-default.png` | a 9× zoom of the LIVE resolved asset, `Pixelated` beside `Default` | the crispness claim itself. Left should be hard-edged; right visibly blurred. |
| 5 | `RS-A14_adaptive_desktop_glossy-touch_sky.png` | the touch package on the desktop row | 44 px gel rows on a big screen: too big? The striped progress trough is the one layer stack in this package. |
| 6 | `RS-A14_adaptive_desktop_compact-pointer_aqua.png` | the pointer package on the desktop row | ~22–24 px controls with hairlines. Is this the density a docked player wants? |
| 7 | `RS-A14_adaptive_phone-portrait_glossy-touch_sky.png` | the touch package on a phone-portrait rect (samsung_galaxy_a06, 360×800, scale 2) | the pair's intended home. HONEST LIMIT: the phone captures are cropped by the Studio window; their paired geometry traces carry the layout claim. |
| 8 | `RS-A14_adaptive_phone-portrait_compact-pointer_aqua.png` | the *pointer* package on the phone rect | deliberately wrong-on-purpose: this is what NOT swapping would look like. Is the difference obvious enough to justify `selectBy`? |
| 9 | `RS-A14_gallery-picker_desktop_compact-pointer_aqua.png` | the gallery theme picker, ten shipping packages, wrapping grid | the surface RS-P2 uses on hardware. Are the chips readable and all on-screen? |

### The FLAT default, which this stage also changed (fix round)

| # | File | What it shows | What to judge |
|---|---|---|---|
| 9b | `RS-A1_flat_desktop_studio-neutral_stepper-disclosure.png` | the stepper and a disclosure group under the unskinned Studio Neutral default | the ASCII glyph change. The stepper's minus is now `-` (was `\u{2212}`) and the disclosure caret is `>` / `v` (was `\u{25B8}` / `\u{25BE}`). Do the affordances still read as affordances at a glance, and does the caret still say "there is more under here"? This is the DEFAULT every unskinned screen gets, so it matters more than any package. |

### Rung 3 — the custom control (P6)

| # | File | What it shows | What to judge |
|---|---|---|---|
| 10 | `RS-A15_gauge_desktop_fantasy-ornate_rung3.png` | the OrnateGauge — a control the framework does not know about, with its own three pictures — inside Fantasy Ornate's panel | does a third-party control *belong* on a themed screen, or does it read as pasted on? |
| 11 | `RS-A15_gauge_desktop_pixel-quest_rung3.png` | the same control after a live package swap | the dial is shorter and its radius tighter (56→48 px, 8→4). **The needle's glow is still amber** — a known, documented seam (`UI.shadow` normalizes at build time), not a defect. Is that acceptable, or should a control be able to re-tint a shadow live? |

### Rung 2 — the per-view gradient (P6b)

| # | File | What it shows | What to judge |
|---|---|---|---|
| 12 | `RS-A15_rung2-gradient_desktop_classic-desktop_wash.png` | one card carrying `UI.gradient` + `UI.shadow`, on a flat package | does a per-view wash read as *deliberate* beside theme-painted siblings? The caption sits on the ramp's darkest stop — a fixture contrast choice, not a framework one, but say if it bothers you. |
| 13 | `RS-A15_rung2-gradient_desktop_fantasy-ornate_wash.png` | the SAME card under the layered package | the measured interaction: the node's own plate is suppressed by the image-is-the-element posture, so the ornate frame wins and the wash paints nothing. Is "the art wins" the right default, or should a per-view wash reach the decoration? |

### The earlier per-capability reads (P2/P3, worth the pass)

| File | Why it is worth a look |
|---|---|
| `RS-A2_adaptive_desktop_layered-test_default.png` | the six-layer ladder in isolation — corners pinned, rails inset, plaque overhanging by 20 px |
| `RS-A3_save-button_desktop_layered-test_hover.png` + `RS-A3_save-button_desktop_layered-test_pressed.png` | per-state ART on one button, under a real injected mouse. Is the state change readable *as a state change*? |
| `RS-A4_layer-probe_desktop_layered-test_rung1-vs-rung2.png` | two sliders, one tree, one theme, one per-view override — the rung-1/rung-2 difference made visible |
| `RS-A5_valueprobe_desktop_layered-test_pct50-on.png` + `RS-A5_valueprobe_desktop_flat_pct50-on.png` | the image bar beside the flat bar at the same value. Note: flat bars gained the value-family corner and hairline this stage (decision packet P3 §3) — that change is here to be approved or rejected. |
| `RS-A6_valueprobe_desktop_layered-test_pct01-off.png` | the switch OFF at 1 % — a different picture, not a tint |

Also stored, from P4, if the pass has appetite:
`RS-A7_glyph-probe_desktop_scifi-hud_caret.png` (the tofu fix: real characters
where two empty boxes used to be), `RS-A8_valueprobe_desktop_pixel-quest-test_zoom8x.png`,
`RS-A11_adaptive_desktop_layered-test_tile.png`.

### The director round's own captures (added 2026-07-26 — they were only cited inside their narrative sections, never in this list)

These are the *after* pictures for the seven defects the live review found, plus the
extraction smoke. Every one is at a stamp later than captures 1–13 above, so where
two pictures disagree these are the current ones.

| # | File | What to judge |
|---|---|---|
| 14 | `RS-DIR1_adaptive_desktop_pixel-quest_bar-clear.png` | defect 1 fixed: do the bar's ornaments now clear their neighbours without the row reading loose? |
| 15 | `RS-DIR2_stepper-focus_desktop_fantasy-ornate.png` + `_pixel-quest.png` + `_studio-neutral.png` | defect 2: the focus visual now rides the ART, not the padded solved rect. Compare the three — does the ring/glow hug the plate on each? |
| 16 | `RS-DIR3_toolbar_desktop_compact-pointer_play-nowrap.png` | defect 3: "Play" on one line at pointer density. |
| 17 | `RS-DIR4_adaptive_desktop_glossy-touch_bar.png` | defect 4: the re-cut glossy trough/gel/stripe at a 24 px desktop bar. Muddy or clean? |
| 18 | `RS-DIR5_adaptive_desktop_fantasy-ornate_bar.png`, `RS-DIR5_adaptive_desktop_pixel-quest_bar.png`, `RS-DIR5_adaptive_desktop_studio-neutral_flat-value.png`, `RS-DIR5_slider_desktop_fantasy-parchment_wax-seal.png`, `RS-DIR5_rung2-thumb_desktop_glossy-touch_no-plate.png`, `RS-DIR5_zoom6x_rung2-thumb_before-after.png` | defect 5: a skinned value slot no longer paints its own solid backing. The flat one is the control: it must look unchanged. |
| 19 | `RS-DIR5b_adaptive_desktop_glossy-touch_bar-ends-clean.png`, `RS-DIR5b_zoom8x_glossy-touch_bar-ends_before-after.png`, `RS-DIR5_zoom8x_glossy-touch_bar-end-stripe-ab.png`, `RS-M9_probe_ends_plain-vs-masked.png` | defects 5b/5c: the glossy bar's ends. Pill-masked stripes, inset 2 — are the ends clean at 1:1, not just at 8×? |
| 20 | `RS-DIR6_valueprobe_glossy-touch_toggles-clean.png` | defect 6: the toggle track's blobs were a real `UICorner` on sliced art. Clean capsules now? |
| 21 | `RS-DIR6-F1_disabled-fallback_fantasy-ornate.png` | the disabled-control fallback edge: a fallback node must stay hidden while the control is disabled. |
| 22 | `RS-DIR7_status_desktop_fantasy-ornate_text-fits.png` | defect 7: a layered recipe's `contentInsets` never reached the solver, so ornate status labels were absent. They fit now — do they sit right inside their controls? |
| 23 | `RS-EXT_smoke_fantasy-ornate.png` | the chrome-module extraction smoke at stamp `407f3c9c-1705480`: Fantasy Ornate on the extracted build, census intact. Nothing should look different from #1. |

### The matrix drive's own captures — THE COMPLETE NINETEEN (2026-07-26, take 8, stamp `66599d58-1744436`)

These nineteen are the matrix. Every one was measured clean on the full assertion set and
captured at the same stamp, and every one is the whole emulated screen at true aspect — no
Studio-window crops anywhere. Read them as a set: the same fixture, five viewports, five
packages. Anything earlier that disagrees with these is history.

| # | File | What to judge |
|---|---|---|
| 24 | `RS-A16_adaptive_desktop-standard_studio-neutral.png` (sha `cf3658fa06792a7a`, 2404×2082) | the flat default: **the control image every skinned row should be compared against**, and the row where the Download bar has a trough and the Brightness slider has a rail and a thumb (D4). Is the unskinned default good enough to ship as a default? |
| 25 | `RS-A16_adaptive_desktop-standard_fantasy-ornate.png` (sha `49297ba9ccd0f2ea`, 2404×2082) | Fantasy Ornate at desktop. The plaque above the Media frame **clears** "Save changes" (D2). Does the six-layer frame read as one carved object, or as five stickers? |
| 26 | `RS-A16_adaptive_desktop-standard_pixel-quest.png` (sha `e1c20a74773128a2`, 2404×2082) | pixel-quest at 1:1. The Download bar has real height with both heart caps and a red fill (D3). Crisp, or blurry pixel art? |
| 27 | `RS-A16_pair_desktop-standard_glossy-touch.png` (sha `b4f33aa4ec94d138`, 2404×2082) | the touch package on a big screen: 44 px gel rows, striped trough with clean ends. Too big for a pointer? |
| 28 | `RS-A16_pair_desktop-standard_compact-pointer.png` (sha `b02aa24bbe9eab34`, 2404×2082) | the pointer package: ~24 px controls, 13 px body, hairlines. "Play" still fits one line. Is this the density a docked player wants? |
| 29 | `RS-A16_adaptive_console-ten-foot_studio-neutral.png` (sha `df7d1df8f3d09453`, 2414×1356) | a real `xbox` preset with **genuine** `preferredInput = Gamepad`, ten-foot distance profile and ×1.5 typography. Is ten-foot sizing and hierarchy right? |
| 30 | `RS-A16_adaptive_console-ten-foot_fantasy-ornate.png` (sha `3db54ca5bbf20057`, 2414×1356) | Ornate at ten-foot. Do the corner ornaments and the bar's crown still read at distance, or become noise? |
| 31 | `RS-A16_adaptive_console-ten-foot_pixel-quest.png` (sha `41f0b355e7109df8`, 2414×1356) | pixel-quest at ten-foot: the same plates blown up 1.26×. Does pixel art survive a television? |
| 32 | `RS-A16_adaptive_tablet-landscape_studio-neutral.png` (sha `dba685cbb6e80e30`, 1988×1490) | the iPad row. Mid-size reflow: two columns, action bar pinned. |
| 33 | `RS-A16_adaptive_tablet-landscape_fantasy-ornate.png` (sha `20a48449d41d08a4`, 1988×1490) | Ornate on the tablet — the frame, the plaque and all four corner ornaments at a middle size. |
| 34 | `RS-A16_adaptive_tablet-landscape_pixel-quest.png` (sha `f71cde63c6c361ab`, 1988×1490) | pixel-quest on the tablet: is the unit still a whole number of screen pixels to the eye? |
| 35 | `RS-A16_adaptive_compact-phone-portrait_studio-neutral.png` (sha `d0639a687092f8a9`, 849×1696) | the flat default on the narrowest supported phone. Single column, Quality stacked, two-line action labels that fit. Judge the compact hierarchy. |
| 36 | `RS-A16_adaptive_compact-phone-portrait_fantasy-ornate.png` (sha `e3aa9332aaec60a1`, 849×1696) | **the picture take 7 could not produce.** Ornate on a phone: gold stepper plates, the wax-seal slider thumb, framed option plates and the gold-and-green selection art on *Balanced*. NOT one flat fallback plate anywhere, with 105 art instances off-window and correctly spared. Does ornate survive 359 px? |
| 37 | `RS-A16_adaptive_compact-phone-portrait_pixel-quest.png` (sha `b4a20cc767eb3e2e`, 849×1696) | pixel-quest on a phone: **every** button plate carries its art (take 7's `control`-slot flip is gone). Watch item `RS-A16-W1` lives here: the action labels wrap mid-word (`Save chang/es`) — `TextFits = true`, so it is a readability call, not a solver failure. Acceptable, or does the compact body metric need to shrink? |
| 38 | `RS-A16_pair_compact-phone-portrait_glossy-touch.png` (sha `ae43d8914015dd70`, 849×1696) | the pair's intended home: 44 px gel rows on the device they were cut for. |
| 39 | `RS-A16_pair_compact-phone-portrait_compact-pointer.png` (sha `76a791264442fe05`, 849×1696) | deliberately wrong-on-purpose: the *pointer* package on a touch screen. Is the difference from #38 obvious enough to justify `selectBy`? |
| 40 | `RS-A16_adaptive_compact-phone-landscape_studio-neutral.png` (sha `2e8f1d168824dbb9`, 1931×927) | the flat default at 705×338 — a 280 px canvas. Two columns, the scroll region cutting a row mid-height, action bar pinned. Is this survivable? |
| 41 | `RS-A16_adaptive_compact-phone-landscape_fantasy-ornate.png` (sha `e54d756d9dd3d6ca`, 1931×927) | **the row that stopped take 7, now clean.** The Download bar's centrepiece is the ornate CROWN, not a flat gold slab; every visible control is framed. This is the D5 fix in one picture. |
| 42 | `RS-A16_adaptive_compact-phone-landscape_pixel-quest.png` (sha `62d16b8d2a735746`, 1931×927) | pixel-quest at the same rect: pixel plates on every control, heart caps on the bar. |
| 43 | `RS-A16-WATCH_toggles_desktop-standard_glossy-touch.png` (sha `dfc5bec608e15f0b`, 2404×2082) | the glossy toggles ON and OFF, reached by a **real injected click** on the Advanced disclosure with the raw event paired. Two DIFFERENT loaded track pictures, not a tint; knob inside track both ways. |

### Drive #4's own captures (2026-07-26) — the two files that recorded RS-A16-D5, now history

| # | File | What it recorded |
|---|---|---|
| 44 | `RS-A16-D5_scroll-clipped-art-flipped-to-fallback_compact-phone-landscape_fantasy-ornate.png` (sha `82b961f04321b71d`) | **RS-A16-D5** in situ before the fix: the Media panel stripped of its frame, ornaments and plaque; the tile badges flat circles. Compare with #41 above, the same preset and package after the fix. |
| 45 | `RS-A16-D5_control-slot-flipped-to-fallback_compact-phone-landscape_pixel-quest.png` (sha `a146f4036184f894`) | **RS-A16-D5** under a second package: the `control` slot flipped, so every button plate went flat. Compare with #42. |
| 46 | `RS-A16-D5_fixed_phone-portrait_fantasy-ornate.png` (sha `523c6949c024cdf6`) + `RS-A16-D5_fixed_phone-portrait_pixel-quest.png` (sha `f4c08bcf125e2d1e`) | the fix round's own after-pictures, taken with a real injected scroll so the previously off-window art is on screen and painting. The matrix rows above are at the top of scroll, so these two are the ones that show the scrolled-in half. |

### Earlier drives' captures — history, not product states

#### Drive #3's captures (RS-A16-D4, now fixed)

| # | File | What it recorded |
|---|---|---|
| H1 | `RS-A16-BLOCKED_value-controls-unpainted_desktop-standard_studio-neutral.png` (sha `c8db8907c97e22cc`) | **RS-A16-D4** in situ: the whole `desktop-standard` / `studio-neutral` row at the current stamp `1de8a15c-1722217`, untinted, exactly cropped to the emulated 1232×1067 screen, CoreGui player list/chat off. Look at the **Download** row — label, `0.35`, and nothing between them — and at **Brightness** — an accent fill with no rail and no thumb. This is the *default, unskinned* look, so it matters more than any package. |
| H2 | `RS-A16-BLOCKED_value-controls-unpainted-vs-bespoke_desktop-standard_studio-neutral.png` (sha `38630471d6a7ce95`) | **RS-A16-D4**, 1.7× zoom, two postures stacked, same fixture and viewport one config flag apart. TOP = StyleSheet paint authority (the posture this stage is built on). BOTTOM = the adapter's bespoke paint. The judgement asked is not *whether* the top is wrong but whether the bottom is the right target: should the base seed simply carry the same four `Slot — <slot>` rules a package gets (the fix proposed below), or should an unskinned value control look different from a flat *package's*? |

**Procedure (one pass):** open the files in order, approve or list changes per
package. Anything actionable becomes a fix round before the gate closes, exactly
like the Step 3.5 TP-P3 round.

---

## RS-P2 — Physical device (E4)

**Judgment requested:** the ornate and pixel packages on a real phone —
nearest-neighbour crispness at real DPI, finger targeting *through* ornament
layers, how a per-state art swap feels under a thumb, and `selectBy` on a REAL
dock/undock (a hardware profile change, not a forced env fact).

### Exact procedure

1. **Build and open the gallery place.** From the library root, with Studio open
   on the gallery place:
   ```sh
   lune run tools/lune/studio_sync            # serves the sources on :8642
   # then, in Studio's EDIT datamodel, run tools/studio/inject.luau via the MCP
   ```
   The injector stamps `workspace.LuauUI_SourceStamp`; record it with the run.
2. **Set the fixture before Play:** workspace attribute
   `LuauUI_Scenario = "theme_authoring"`. Optionally `LuauUI_ThemePackage` /
   `LuauUI_ThemeName` to choose what it opens under. Leave
   `LuauUI_ThemePicker` unset (it defaults on) — the picker is how you change
   package on hardware, where there is no command bar.
3. **Publish and open on the phone.** Studio's device emulator is not this row;
   this row is a real handset.
4. **Swap packages from the picker.** It is a passive top-right overlay listing
   Studio Neutral first, then every package under
   `ReplicatedStorage.LuauUIThemes` that is not `testOnly`, each with its themes
   underneath. The four to walk, by package id:

   | Package id | What to check on glass |
   |---|---|
   | `fantasy-ornate` | can you hit a button whose corners are ornaments? The measured hit floor is 47 px across 17 interactive nodes, but a finger is the test. Does the plaque overhang catch taps it should not? |
   | `pixel-quest` | is it crisp at the phone's real DPI (not just at 1:1 in Studio)? Does the selected row's plate change read at arm's length? |
   | `glossy-touch` | the package designed for this device. 44 px rows, striped progress, sliding switch. |
   | `compact-pointer` | deliberately wrong here — ~22 px controls on a phone. This is the "before" for `selectBy`. |

   The picker is **examples-only code**
   (`examples/gallery/client/theme_picker.luau`), goes through the public
   surface only, and re-themes itself along with everything else — if the picker
   still reads after a swap, the swap worked. Set `LuauUI_ThemePicker = false`
   to hide it.
5. **`selectBy` on real hardware.** The pair is declared in
   `examples/gallery/scenarios/theme_authoring.luau` (`selectByPair` step) as
   `selectBy = { touch = glossy-touch, pointer = compact-pointer, gamepad = compact-pointer }`.
   On a phone this must install `glossy-touch` at mount. Then pair a Bluetooth
   keyboard/mouse (a REAL paradigm change) and watch for exactly one swap after
   the 0.25 s settle — not a flap, not a storm. Unpair and watch it come back.
6. **The two named RS-P2 items** (platform verifier F8 — the Studio device seam
   drives the VIEWPORT fact only, so neither of these has any Studio evidence at
   all and neither may be closed by a screenshot):

   | Item | What Studio cannot answer | What to do on glass |
   |---|---|---|
   | **Real-DPI nearest-neighbour crispness** | the device seam sets a viewport RECT; it does not set `resolutionScale`, so every pixel-mode capture in this packet is a 1:1 desktop render. Whether `Pixelated` survives a phone's real device-pixel ratio is unmeasured. | open `pixel-quest` on the handset, hold it at reading distance and at arm's length, and look for soft edges on the plate borders and the icon glyphs. Compare against the 9x zoom capture (#4), which is what "crisp" is supposed to look like. |
   | **Safe-area / topbar geometry under a layered or plaque skin** | no safe-area or topbar claim is made by any row in this stage. The layered panel's plaque OVERHANGS its rect by 20px, and the topbar inset is not physical space on a notched device (standing RascalRally lesson). | open `fantasy-ornate` on a notched handset in BOTH orientations. Does the plaque overhang under the notch or the status bar? Does any corner ornament fall outside the safe area? Is the top row of controls reachable with the phone in one hand? |

7. **Record:** targeting successes/failures per package, crispness at real DPI,
   how the art swap *feels* on press (Studio measured no hitch; a phone on a cold
   CDN is the open question — `PreloadAsync` is the default policy precisely
   because Studio cannot reproduce that), and the number of swaps observed per
   real dock/undock.

---

## RS-P3 — Low-end performance (deferred)

Explicitly NOT claimed this stage; Step 7's named physical row. Recorded so the
omission is a decision, not an oversight. The layered census
(`rs-a17-cost.json`) is the guard in the meantime: Fantasy Ornate's 60 declared
layers are **139 actual instances**, and that number is the thing a low-end pass
must be run against.

---

## RS-P4 — Capture readability stays a human row

No automated contrast/legibility digest substitutes for the director's read of
the final captures (standing Step 3.5 lesson). Same pass as RS-P1.

---

## Automatable follow-ups (not defects; not this stage's scope)

Each of these is a real, bounded piece of work that a later package could take.
None blocks the gate; each is recorded so it is a decision rather than a hole.

| # | Item | Found | What it would take | Why it was not done now |
|---|---|---|---|---|
| 1 | **`table.luau` sort-mark glyph hazard** | P4 | give the Table's ascending/descending sort marks the same treatment R4 gave icons: a semantic name, a theme asset, and an ASCII-safe fallback glyph | the sort marks are not in the v2 slot vocabulary and no reference package skins them. They are the *same hazard class* as the sci-fi tofu carets, so they are named here rather than left to be rediscovered. |
| 2 | **Per-state icon art in the adapter** | P4 | the schema already normalizes a variant map on an icon reference; the adapter would need the per-state tag rules an icon picture does not yet emit | resolvable but unrequested — no shipped package declares a per-state icon, so building it would ship an untested path. |
| 3 | **`rtl` / `ttb` / `btt` bar fill directions** | P3 | drive a vertical or right-to-left bar in a fixture and capture it | the geometry is shipped and asserted headlessly in all four directions (`chrome_slots.barFillBox` / `barCapBox`); the shipped `ProgressView` is horizontal, so only `ltr` has a LIVE proof. Recorded as a limit, not claimed. |
| 4 | **Slider-thumb hover/press are unreachable** | P3/P4 | make the thumb an interactive class, or publish thumb hover/press through the controller seam | a slider thumb is a `Frame` and never leaves `GuiState.Idle`, so `hover`/`pressed` variants on a thumb cannot fire at EITHER rung. Those states are proven on the layered `control` slot instead. Documented in `docs/reference/api.md` under `newSlider`. |
| 5 | **Per-state and pixel `tile` layers** | P4/P5 | a package that declares one, plus its capture | composition is structural in emission and was measured at the engine in rs-m1, but no shipped fixture declares a per-state or pixel tile layer. Building one purely to be able to claim it would be a fixture written to flatter the feature. |
| 6 | **The declarations-vs-instances multiplier** | P5/P6 | (done, docs) — `docs/guide/10-rich-skinning.md` §10.1 now teaches that the cap of 8 is a cap on DECLARATIONS worth up to ~4× in instances, with the live 60→139 number | listed here because it was the census's most useful finding and the reason the census exists. |
| 7 | ~~A per-view gradient modifier~~ **SHIPPED (P6b)** | P6 | — | The charter (cap 11) is the stage's source of truth, so it shipped rather than being dispositioned: `UI.gradient` follows `UI.shadow`'s architecture (bounded data, one reused adapter-owned `LuauUIGradient` child, never a rule), refuses a value control's chrome and a text-bearing node at construction, and survives a package swap with the same child. Evidence in `rs-a15-ladder-docs.json` → `gradientModifier`. One residual, documented not deferred: a wash needs a fill, so under a package that skins that slot the R9 suppression has already removed it and the art wins. |
| 8 | **A namespaced `number` need has one legal home** | P6 | either open another scalar metric section to namespaced keys, or say so in the schema errors | `metrics.controls` is a closed family list and rejects `["ns:role"]`; a bare number in `metrics.controlSizes` compiles and then throws inside `themes.resolve`. `metrics.radii` / `metrics.space` work. Documented in `docs/extending/skinned-control.md` §1 and `new-theme.md` §2 so nobody rediscovers it, but the *error messages* do not yet point the way. |

---

## Known limitations of the evidence itself (fix round)

Neither of these is a defect. Both are places where a number in this stage's
artifacts means slightly less than it looks like it means, recorded so a reader
does not over-read it.

- **An `error`-state variant rule is counted as EMITTED, not as MATCHED**
  (architecture verifier F5). `error` is the one variant state with no engine
  `GuiState`: it rides the `luau-state-error` tag, which the renderer only sets
  when a control publishes an error. So a package that declares `error` art for
  a slot no control ever errors on still contributes rules to
  `census.stateRules`, and nothing distinguishes "emitted and reachable" from
  "emitted and unreachable" except reading the census beside the fixture. The
  cost is real (the rules exist on the sheet); the *effect* may not be.
- **The layered state-rule count scales with `3 x (nineSliceSlots + layers)`**
  (architecture verifier F7). This is by construction, is what the cost model
  measures, and is the number `RS-A17` reports — but it means a package's rule
  count is driven by its layer ladder far more than by its palette.

---

## Decision packet — the FLAT default's ASCII glyphs (fix round)

**The change.** Three characters that every *unskinned* screen renders moved:

| Where | Was | Is | Why |
|---|---|---|---|
| Stepper decrement | `\u{2212}` (MINUS SIGN) | `-` (HYPHEN-MINUS) | R4's fallback-glyph table is ASCII by construction |
| Disclosure, collapsed | `\u{25B8}` (BLACK RIGHT-POINTING SMALL TRIANGLE) | `>` | the same table; and this exact character measured at the tofu placeholder's advance in Michroma |
| Disclosure, expanded | `\u{25BE}` (BLACK DOWN-POINTING SMALL TRIANGLE) | `v` | ditto |

**Why it is a decision and not an implementation detail.** The tofu fix could
have been scoped to *skinned* packages — keep the typographically nicer
characters by default and swap them only under a package with an unusual font.
It was not, deliberately: a package may name **any** font, the framework cannot
know which characters that font contains, and a default that is correct only
until someone picks a display face is the same bug with a longer fuse. So the
ASCII table is the default everywhere and `themes.isSafeGlyph` refuses anything
else.

**What it costs.** `-` is thinner and lower than `\u{2212}`, and `>` / `v` are
letterforms rather than filled triangles — at a glance the disclosure caret
reads slightly less like an arrow. A package that cares ships caret art and the
glyph never renders (Fantasy Ornate and Pixel Quest both do). The *default* is
what capture #9b is for.

**Reversible.** One table, `themes.ICON_FALLBACK_GLYPHS`. Reverting it would
reopen the tofu class, which is why it is being shown rather than asked about.

---

## Decision packet — P3 (image value displays), for Fable 5 / the director

Three calls in this package went past routine implementation. Each is reversible
and each is recorded here rather than buried in a diff.

### 1. The bar's percent still re-solves; the ART does not

**What ADR-0020 R3 says:** "Percent maps to ONE window `Size` write — no
re-solve, art byte-stable", and rs-m4's consequence adds "track rect solved once;
window is paint plumbing".

**What shipped:** the window IS the fill node's solved rect. The adapter parents a
`ClipsDescendants` window over the node the solver already sizes to the percent,
with the art inside at FULL TRACK SIZE. Measured live at stamp
`580dba2c-1470884`: per value change the adapter writes NOTHING (creates +0,
propWrites +0), the art's size, origin, `Image`, `ScaleType` and `SliceCenter` are
identical at 0/1/50/99/100%, and the caps and crown do not move — every property
rs-m4 actually cared about. The one rectWrite per value is the solver's existing
write on that node, and the one solve is the ProgressView's percent dim.

**Why not the literal reading (an adapter-written window driven by a published
fraction):** it would have required the control to stop driving a solver dim,
which means deleting the `Fill` node. That node is the flat bar's fill; it is what
four shipped headless tests assert (`/S/Load/Bar/Fill` rect =
`floor(track * f + 0.5)`), and the headless adapter has no chrome machinery at all
— so removing it would have made a flat progress bar's fill invisible to the
suite, traded a solver-owned rect for an adapter-owned one, and added an
always-built instance per bar in every theme. The ledger's "relayout counter zero
across the sweep" is therefore reported as what it is: **zero adapter writes and
zero art re-derivation per value; one solve, which predates this stage and is
unchanged by it.**

**To reverse:** publish the fraction through the controller seam
(`attachDragDetector` is the precedent) and build the window on the track instead.
The pure geometry (`barFillBox`, `barCapBox`, `barCenterBox`) is already
direction-driven and would not change.

### 2. The toggle knob moved out of the track

Per-state art on the knob is an RS-A6 requirement, and every per-state rule a
package emits is a child combinator off the INTERACTIVE node
(`.luau-interactive:Press > .luau-chrome-*`). With the knob parented inside the
track it sat one level too deep: the rules would have been emitted and never
matched — the exact defect class this stage exists to remove. The deliberate
minimal change is that the knob is now a direct child of the Toggle button, at the
same two absolute stops (`TOGGLE_KNOB_OFF/ON`, i.e. the track's left edge +2 and
+22, 20px of travel), proven byte-identical against a flat package live. Track and
Knob also became ImageLabels, which is what lets a recipe paint them without a
second instance each.

The alternative considered and rejected: a chained or descendant selector
(`… > .luau-toggle-chrome > .luau-chrome-toggleKnob`). It would have shipped a
selector shape no probe in this repository has measured.

### 3. Flat bars gain the value-control family's corner and hairline

`barTrack`/`barFill` join `OWN_PAINT_SLOTS` (P1's ruling), so a flat bar's two
nodes are now painted by `Slot — barTrack`/`Slot — barFill` instead of by the
`control`/`accent` surfaces they used to borrow. The fills are the same tokens
($Control / $Accent), and the bar picks up the same corner radius and hairline the
slider rail and thumb took in the Step 3.5 fix round. That is a visible change to
FLAT bars — small, and the same family treatment one control down, but a change.
Flagged for the RS-P1 read rather than asserted away.

## Decision packet — P6 (ladder docs + the rung-3 control)

### 1. `layers` on `barFill` is now a compile error

Found in the P5 review: a recipe could declare a layer stack on `barFill`, it
compiled clean, and it painted **nothing** — the adapter takes the value-display
branch for that slot (the fill's art lives inside the percent window at full track
size, rs-m4) and returns before the stack branch ever runs. That is the
silently-inert class this whole stage exists to remove, so it is loud now: a
compile error naming the slot, the reason, and the fix (put the decoration on
`barTrack`; `glossy-touch` is the shipped precedent). Red-first: the spec failed
before the compiler change. **Reversible** by deleting the rejection — but then
the silent-inert path comes back.

### 2. The rung-3 example is a CONTROL, not an interactive control

`ornate_gauge.luau` publishes no input contribution and is not registered in the
controls registry. RS-A15's subject is the theme-contribution and art half of
rung 3 — namespaced roles, `checkCoverage` both directions, own art, re-theming —
and a player-facing custom control additionally owes `new-control.md`'s four-input
and affordance bars. Mixing the two would have made this example a worse teacher
of either. The playbook says so in §0. **To extend:** attach a contribution
bundle and register it, exactly as `new-control.md` describes.

### 3. Its art is the CONTROL's, and the manifest says so

`assets/themes/ornate-gauge/upload-manifest.json` carries `"package": null` and
names the control module instead. Every other folder under `assets/themes/`
belongs to a package, and a reader who assumed this one did too would look for a
theme that owns it and find none. The suite asserts that no covering package names
a gauge asset id, so the ownership split is enforced rather than described.

### 4. What the docs deliberately do NOT claim

- **A namespaced decoration slot.** Chrome slots are a closed vocabulary and
  `chrome.myThing` is a compile error. The rung-3 walkthrough teaches the shipped
  alternative — reach the existing slots through the public `surface` prop, paint
  your own art with `UI.Image` — rather than describing a contribution shape the
  build does not have.
- **A control that re-themes its shadow live.** `UI.shadow` and `UI.corners`
  normalize eagerly. The pixel-quest capture SHOWS the amber glow surviving the
  swap, and both the chapter and the playbook explain why. Hiding it would have
  made the example a nicer story and a worse manual.

## Decision packet — P6b (the rung-2 gradient modifier)

The charter's cap 11 promises shadow AND gradient modifiers at rung 2. P6
reported the gradient half as unshipped; P6b shipped it. Three calls in it are
worth the director's eye.

### 1. It is an INSTANCE, not a rule — and that is the whole rung-2 argument

A theme's gradients are phantom `::UIGradient` rules with zero child instances,
which is right for a theme because a rule matches a CLASS of nodes. A per-view
wash must win on exactly one node, so it follows `UI.shadow`'s architecture
instead: bounded normalized data under the style authority, materialized as one
bespoke `LuauUIGradient` child that is REUSED rather than re-created. Measured
live, the same child (debugId `0_32941573`) survived three package installs with
`gradientCount == 1` every time. **To reverse:** nothing to reverse — removing
the modifier removes the prop, the child and the docs anchor together.

### 2. A text-bearing node is REFUSED, not accommodated

`UIGradient` multiplies the parent's own rendering, its engine-drawn glyphs
included — so a wash on a Button darkens its label with its fill. The two
options were "restrict it to the decoration surface" (the slot shadow's shipped
behaviour) and "reject". The restrict option is not available to a per-view
modifier: under a flat theme there is no decoration to fall back on, so the
effect's LOCATION would depend on the installed package, and a modifier that
moves when the theme changes is worse than a refusal. It therefore errors at
construction, exactly as `surface = "control"` on a `UI.Text` does, and names the
fix (put the wash on the `UI.Box` behind the label). **To reverse:** allow it and
accept tinted labels, or route to the decoration and accept theme-dependent
placement.

### 3. A wash under an art-driven package paints nothing — documented, not patched

The image-is-the-element posture sets a skinned node's own
`BackgroundTransparency` to 1 and moves the paint into decoration CHILDREN, which
a `UIGradient` does not reach. So on `fantasy-ornate` the card's ornate frame
wins and the wash has nothing to multiply; on `classic-desktop` and
`glossy-mobile` it paints. Both states are captured. The alternative — parenting
the child to the decoration when one exists — was rejected for the same reason as
§2. The guide carries the three-package table so an author meets this in the
documentation rather than on a device.

---

## Director round (live review, 2026-07-25)

The director reviewed the live renders and the matrix captures and reported four
visual defects, then a fifth on the re-look (§5 below), then a sixth and seventh
(§6, §7). All seven are fixed and proven live — §5 leaves one ART decision open as
§5b, and §6 **falsified its own reported diagnosis** (Roblox clamps overlapping
slice caps; the blob was a real `UICorner` on a sliced ImageLabel) — the captures
below are the
**RS-P1 re-look** set for this round, and they sit alongside (not instead of) the
per-capability captures above. The five-view matrix re-drives after this round at
the new final stamp, so every `RS-A16_*` capture listed earlier is pre-fix history
for the bar row, the stepper focus ring, the toolbar label and the glossy bar.

Live session for all of them: Studio `0.731.0.7310942`, Play Solo (Client), viewport
`1233x1067`, scenario `theme_authoring`, one `LuauUI_AdaptiveScreen` mounted,
CoreGui player list/backpack/chat disabled for the captures. Source stamps:
`9a5dbf1b-1674581` (defect 1), `2c44a5f6-1675566` (defects 2–4; the second
stamp only adds the `focusNode` scenario step) and `e62c3bce-1677772` (defect 5).

### 1. Bar ornaments overlapped their neighbours

**Reported:** *caps/centrepiece imagery overlaps the value/label text at either
end of the bar AND the row above* — seen on the pixel-quest download bar and
elsewhere.

**Root cause (measured, not inferred).** Neither the art nor the anchoring was
wrong: `barCapBox` centres a cap ON the track's edge on purpose and `barCenterBox`
centres the crown. The declared extents simply never reached the SOLVER. Measured
live at the pre-fix stamp under pixel-quest: a 40x40 heart on an 8px track spanned
20px past each end and 16px past each edge, so it painted over 12px of the word
"Download", 12px of "0.35", 2px of the toolbar row above and 2px of the row below.

**Fix.** The reservation consequence a plaque's `overhang` already has (rs-m3),
one rung down and DERIVED rather than authored:
`chrome_slots.barReservation(package, crossPx)` reads the declared cap/centrepiece
boxes against the track's own cross extent, the snapshot publishes it as
`chromeOutsets[slot]` (after the pixel snap, so it sees the resolved
`controls.progress.trackHeight`), and the renderer adds it to the node's MARGIN at
the same classification seam that adds `chromeInsets` to its padding. Insets
reserve inward for this node's content; outsets reserve outward so the solver
moves the neighbours. A package with neither ornament publishes an empty table and
the whole block is a no-op — which is what keeps flat byte-identical.

**Live proof (stamp `9a5dbf1b-1674581`).** pixel-quest: every neighbour clear by
the row's own 8px gap (capStart left 677 vs label right 669; capEnd right 1190 vs
value left 1198; caps y143..183 against toolbar bottom 135 and SaveLabel top 191),
the row grown 20 -> 40 to contain them exactly. fantasy-ornate: caps 28x36 on a
28px track reserve 14/14/4/4 and clear by the same gap. glossy-touch,
compact-pointer and flat declare no ornaments and are byte-unchanged.

**Capture:** `RS-DIR1_adaptive_desktop_pixel-quest_bar-clear.png`
(sha256 `03c8ab8e681bf377`) — judge whether
"Download" and "0.35" now read cleanly and whether the hearts sit comfortably
between the toolbar row and "Save changes".

### 2. The stepper's selection outline had excessive horizontal negative space

**Reported:** the (green) selection/focus outline around the volume-down stepper
wraps the padded solved rect, not the drawn plate art.

**Root cause.** A Button carries a `UIPadding` so its ENGINE label clears the
edges — and a decoration is a CHILD, so that padding insets the plate too.
Measured live under pixel-quest: the Dec button solved to **53x68** while its
plate painted **29x68**, i.e. 12px of empty air on each side of the thing the ring
was outlining.

**Fix.** The ring and the glow now hang off the instance that DRAWS the plate, not
off the node. Which instance is a pure decision (`chrome_slots.focusArtLayer`):
the one nine-slice decoration, or the back-most FULL-BLEED layer of a stack — a
corner ornament or an overhanging plaque is a detail ON the plate, and ringing one
of those would be worse than the defect. A node with no art keeps today's
solved-rect ring. Hit geometry is untouched: the 47px floor lives on the
`LuauUIHitExpander` sibling and on the node's own Size, neither of which the focus
path reads or writes.

**Live proof (stamp `2c44a5f6-1675566`).** With focus parked on
`/AdaptiveScreen/BodyScroll/Body/Settings/Volume/Dec` through the new `focusNode`
scenario step, the subtree dump reports the `UIStroke`/`UIShadow` on the ART:

| package | node | plate | focus visual |
|---|---|---|---|
| pixel-quest | 53x68 @265,68 | 29x68 @277,68 | `FocusRing` on `LuauUIChrome` |
| fantasy-ornate | 44x55 @272,67 | 20x55 @284,67 | `FocusGlow` on `LuauUIChrome` |
| glossy-touch | 44x55 @274,66 | 20x55 @286,66 | `FocusGlow` on `LuauUIChrome` |
| compact-pointer | 44x45 @271,65 | 20x45 @283,65 | `FocusRing` on `LuauUIChrome` |
| **studio-neutral** | 44x46 @275,64 | *(no art)* | `FocusRing` on the NODE — **unchanged** |

**Capture pair:** `RS-DIR2_stepper-focus_desktop_pixel-quest.png`
(`f501cb91905d0bb6`), `RS-DIR2_stepper-focus_desktop_fantasy-ornate.png`
(`b4ba2e1cf9f7b869`) and `RS-DIR2_stepper-focus_desktop_studio-neutral.png`
(`0b95e7b527086488`) — judge that the ring/glow now
reads as an outline OF the plate under the two skins, and that neutral looks
exactly as it did.

### 3. The "Play" button label wrapped in the compact-pointer package

**Reported:** the label wraps on the compact-phone-portrait row
(`RS-A16_pair_compact-phone-portrait_compact-pointer`) — the same fit-defect class
as the 3.5 sci-fi "Pla/y" wrap.

**Root cause (and it was not a width).** The fixture forces nothing and the metric
does not under-reserve. The measure seam resolved the class's typography ROLE from
the snapshot (`type.control.size`) while the PAINT seam ignored it: the adapter
wrote a hardcoded `TextSize = 16` at creation and no rule and no prop ever moved
it. So a package's control size was accepted at compile, reserved by the solver,
and then not drawn — the accepted-and-ignored class. Measured live at the pre-fix
stamp: compact-pointer draws its control text at 13, the solver therefore reserved
20px for "Play" and sized the button 60x45, and the engine drew the label at 16
(24px wide) into a 20px lifted box. It wrapped at **desktop** too, so the phone row
was where it was noticed rather than what caused it.

**Fix.** One published table — `snapshot.INTRINSIC_TEXT_ROLE` (Text -> body,
Button -> control, Toggle -> body, TextField -> control) — read by the renderer's
measure seam AND written by its paint seam, exactly as `applyPadding` already does
for a Button's engine text inset. A content button (which draws no text of its
own) is excluded. `textScale` still multiplies AUTHORED sizes only and the
preferred-text offset stays out of paint, both unchanged.

**Live proof (stamp `2c44a5f6-1675566`).** `TbPlay`, one line in every package:

| package | node | drawn TextSize | engine TextBounds | lifted box | lines |
|---|---|---|---|---|---|
| compact-pointer | 60x45 | 13 | 20x13 | 20x41 | 1 |
| glossy-touch | 77x63 | 17 | 25x17 | 25x47 | 1 |
| pixel-quest | 80x76 | 16 | 24x16 | 24x44 | 1 |

...and at the compact-phone-portrait content rect (359x660, driven through the
declared `setEnv` seam) compact-pointer's `TbPlay` is 60x45 at TextSize 13 with
bounds 20x13 in a 20-wide lift — one line, the row the defect was reported on.

**Capture:** `RS-DIR3_toolbar_desktop_compact-pointer_play-nowrap.png`
(`f5b4114892194a47`).

**HONEST LIMIT.** Device SELECTION is plugin-locked from `execute_luau`, so the
compact-phone-portrait row itself is re-captured by the RS-A16 matrix re-drive;
what is proven here is the mechanism plus that row's exact layout facts.

### 4. The glossy-touch bar read poorly at desktop scale

**Reported:** the glossy download/progress bar on the desktop-standard row reads
poorly against the quality bar of the compact/macOS-class reference imagery.

**Fix — an art pass, regenerated procedurally at a new recorded seed `0x6E27`**
(`assets/themes/glossy-touch/source/generate_art.py`; the other eleven textures
regenerate byte-identically). Three defects, all geometry rather than taste, all
written up in `assets/themes/glossy-touch/provenance.md` under "The bar re-cut":

1. **The trough was not a trough.** It was drawn between `y=2` and `y=h-3`, so
   only 20 of the 24 authored pixels carried art, and its ramp ran 196 -> 248 — a
   spread that is invisible beside a near-white page. Now full height, 138 -> 245
   with the DARK end at the top, a deeper top inner shadow, a hard 1px rim and a
   1px lit bottom lip: two crisp lines, which is what survives at 24px.
2. **The gel step sat inside a stretched band.** The fill was authored 20px tall
   and DRAWN 24 (`controls.progress.trackHeight`), so nine-slicing stretched its
   middle 4 rows to 8 and the hard gloss step smeared into a soft gradient — the
   package's own provenance note 1, one control down from the button it was
   written for. Authored at 24 it is 1:1 vertically at every width; the ramp also
   deepened. Its `sliceCenter` moved to `{8, 8, 88, 16}`.
3. **The stripe was one low-contrast cycle.** 12px period at 0.55 white over a
   24px bar. The period is now 8 (3 cycles per tile, still an exact divisor of the
   24px tile, so both axes still seam — verified on the contact sheet's 10x3 seam
   check), and each stripe is a PAIR: a 3px lit band at 0.55 white with a 2px
   shaded leading edge at 0.30, which keeps the trough recessed rather than
   brighter than the page.

The contact sheet's striped-progress row was also wrong and is fixed: it
composited the stripe over the FILL while the package declares it as `barTrack`'s
second layer. It now composes as shipped.

The package's content stamp therefore moved: **`e297a9d0` -> `26c59728`**. Every
glossy-touch stamp recorded in `rs-a14-platform-pair.json` outside its
`directorArtRound` section is pre-art-round.

**Re-uploaded** via Studio MCP `upload_image`: `glossy_bar_track.png` ->
`rbxassetid://90291950996149`, `glossy_bar_fill.png` ->
`rbxassetid://121908556097885`, `glossy_stripe_tile.png` ->
`rbxassetid://131357884608814`. Manifest and package updated; all three read
`IsLoaded = true` live on the desktop bar at 496x24.

**Capture:** `RS-DIR4_adaptive_desktop_glossy-touch_bar.png`
(`39ddadb0907876f0`) — judge the trough
depth, the gel's dome, and whether the hatch reads crisply rather than muddily at
this height.

### 5. A skinned value slot still painted its own solid backing

**Reported:** the glossy-touch download bar shows opaque, blocky ends.

**Alpha diagnosis first — the art is clean.** `glossy_bar_track.png` and
`glossy_bar_fill.png` both carry a smooth anti-aliased corner ramp (track corner
alphas `2, 5, 13, 34, 45, 76, 187, 242`; fill `0, 0, 9, 0, 0, 163, 242, 252`), so
nothing about the end geometry is baked into the pictures.

**Root cause (measured live, stamp `e62c3bce-1677772`, and it is bigger than one
package).** R9's suppression was keyed on the PACKAGE declaring a recipe for the
slot, while the tag it selects on — `luau-skinned-<slot>` — is earned by the NODE,
from three routes: a nine-slice recipe, a layer stack, and the **rung-2 per-view
override**. Only the first two run through the emission loops. A view that supplies
its own image for a value slot the installed package says nothing about therefore
got the tag and no rule, and the `Slot — <slot>` solid slab kept painting under the
art. Measured on `/LayerProbe/ViewSlider/TrackHost/Groove/Thumb` under
`glossy-touch` (which declares `barTrack`/`barFill` and **no slider recipe at
all**): pre-fix `GetStyled("BackgroundTransparency") = 0` with the skinned tag
present — a round-cornered override sitting on a square opaque plate.

**Fix.** The four `OWN_PAINT_SLOTS` suppression sets are **pre-armed** — emitted by
every package, flat ones included, in the chrome group after the `Slot — <slot>`
paint they lift, and idempotent so a package that also declares the recipe emits
one rule per name rather than two. Flat is untouched by construction: an unskinned
node never carries the tag, so its solid paint, corner and hairline are byte
identical. The gradient ban carries the original 3.5 hazard and is still a compile
error. ADR-0020 R9 amended.

**Live proof (stamp `e62c3bce-1677772`, Studio `0.731.0.7310942`, Play Solo,
viewport 1233x1067, scenario `theme_authoring`, one `LuauUI_AdaptiveScreen`).**
`GetStyled` on every `luau-slot-*` node, all five packages — skinned ⇒ 1,
unskinned ⇒ 0, with no exceptions:

| package | sliderTrack | sliderThumb | barTrack | barFill |
|---|---|---|---|---|
| studio-neutral (flat) | 0 (unskinned) | 0 | 0 | 0 |
| pixel-quest | 0 | 0 | **1** skinned | **1** skinned |
| fantasy-ornate | **1** | **1** | **1** | **1** |
| fantasy-parchment | **1** | **1** | 0 | 0 |
| glossy-touch | 0 | 0 | **1** | **1** |

...and the defect node itself: `/LayerProbe/ViewSlider/.../Thumb` under
glossy-touch, skinned by a rung-2 override, **0 → 1**.

**Capture to judge first:** `RS-DIR5_zoom6x_rung2-thumb_before-after.png`
(sha256 `320e6f239a56e5ce`) — the same node, same crop, at 6x, pre-fix beside
post-fix. On the left the round `$SurfaceStrong` plate rings the art on all four
sides; on the right the art sits on the rail with the page behind it. The
"before" panel was re-driven for this comparison on the pre-fix source
(stamp `62e5827e-1677734`) rather than reconstructed.

**Other captures:** `RS-DIR5_rung2-thumb_desktop_glossy-touch_no-plate.png` (the
fixed node in context),
`RS-DIR5_slider_desktop_fantasy-parchment_wax-seal.png`,
`RS-DIR5_adaptive_desktop_fantasy-ornate_bar.png`,
`RS-DIR5_adaptive_desktop_pixel-quest_bar.png`,
`RS-DIR5_adaptive_desktop_studio-neutral_flat-value.png`,
`RS-DIR5_adaptive_desktop_glossy-touch_bar-ends.png`.

**Parchment thumb, before and after: UNCHANGED, and that is the correct result.**
Fantasy Parchment declares `sliderTrack` + `sliderThumb`, so the recipe loop
already emitted its suppression; measured `GetStyled = 1` at both stamps. The
wax seal was never on a plate and still is not — the scalloped seal edge reads
clean against the page in the capture. The packages this round actually moves are
the ones that DON'T declare the slot.

### 5b. FIXED — the glossy bar's ends were the STRIPE TILE, not the backing

Reported with defect 5 and separated because the measurement said so. At the
defect-5 stamp the glossy `barTrack`/`barFill` backings both already read
`GetStyled("BackgroundTransparency") = 1` — they were suppressed before that
round (their recipes are declared) and the defect-5 capture is pixel-identical to
`RS-DIR4` at the bar ends. What squared those ends is the package's own second
layer: `glossy_stripe_tile.png` is a `tile` layer with alpha up to 141 at its own
corners, so it painted edge to edge over the trough's rounded, correctly
anti-aliased end.

**Diagnostic evidence:** `RS-DIR5_zoom8x_glossy-touch_bar-end-stripe-ab.png` —
the same bar end at 8x, shipped on the left and with layer L2 hidden on the
right. The right panel is the trough's true end: a clean round cap with the page
showing through. Nothing else changed between the two.

**Fix (lead ruling): the layer vocabulary gains a bounded extension rather than
an art round.** `inset = { x = px, y = px }`, optional on the three FULL-BLEED
kinds (`fill` / `frame` / `tile`) and a compile error on the other three, whose
boxes are already anchored by their own geometry. It shrinks the layer's box
SYMMETRICALLY per axis — the rectangle an `edges` rail already gets from
`margin`, on both axes. Validated like every other geometry field: a table with
only `x`/`y`, finite and non-negative, or a `layerField` rejection naming the
field, the rule and the fix. Absent (or `{ x = 0, y = 0 }`) is the identical box
full bleed always produced, so every package that declares none is unchanged.

`glossy_touch.luau`'s stripe layer now declares `inset = { x = 10, y = 2 }`, and
both numbers are the ART's rather than taste: `generate_art.py`'s `bar_track`
draws its rounded rect at **radius 10**, so the hatch starts exactly where the
end arc finishes, and `y = 2` clears the 1px hard rim at the top and the 1px lit
lip at the bottom — the two lines that make the well read as inset. No texture
was regenerated and no asset was re-uploaded; the package's content stamp moved
`26c59728` -> `034aac88`.

**Live proof (stamp `d5f1fd92-1682699`, Studio `0.731.0.7310942`, Play Solo,
viewport 1233x1067).** The track solves 496x24 at 687,132 and its two layers
report `L1 687,132 496x24` (the trough, still full bleed) and
`L2 697,134 476x20` — inset by exactly 10 on x and 2 on y, both `IsLoaded`, both
`GetStyled BackgroundTransparency = 1`. The bar's top-right corner run now reads
`115,140,158 / 120,151,170 / 126,160,180 / …` into the page — **byte-identical to
the L2-hidden diagnostic**, i.e. the shipped bar now renders exactly the trough's
own anti-aliased round end. The defect-5 invariant still holds at this stamp
(skinned ⇒ 1, unskinned ⇒ 0 on all four value slots).

**Other packages unchanged, measured not asserted.** No other reference package
declares an inset (headless sweep over all seven: exactly one declaration,
`glossy_touch.barTrack.L2`). Live, the pixel-quest download-bar row re-captured
after the change differs from its pre-change capture by a **maximum of 1 per
channel with zero pixels above a luma delta of 8** across 1090x120 px — the ±1 is
the sky gradient through the bar's transparent pixels.

**Captures:** `RS-DIR5b_adaptive_desktop_glossy-touch_bar-ends-clean.png` and
`RS-DIR5b_zoom8x_glossy-touch_bar-ends_before-after.png` (both ends at 8x,
full-bleed stripe beside the inset one). Judge the right end in particular: the
hatch now stops ~10px short and the trough's end cap catches the light instead of
being hatched over.

### 5c. The stripes now FOLLOW the trough — a real pill mask, not an inset

**Director:** replace the 5b inset stopgap with a true mask so the stripes follow
the rounded silhouette and sit closer to the ends.

**Probed first** — `feasibility/rs-m9-canvasgroup-mask.json`, schema
`luauui-studio-spike/1`. CanvasGroup + UICorner over a *tiled* child under a
rule-owned paint model is an unmeasured engine combination, so it got the rs-m1..m8
treatment before a line of framework code moved. **Verdict: GO.**

| # | question | verdict | the number |
|---|---|---|---|
| Q1 | does a pill mask clip a TILED child along the arc, anti-aliased? | **YES** | visual, on the real glossy trough + stripe art: `RS-M9_probe_ends_plain-vs-masked.png` |
| Q2 | do style rules reach a tagged child INSIDE a canvas? | **YES, identically** | `GetStyled` resolves Image / ScaleType=Tile / TileSize {0,24},{0,24} / BackgroundTransparency 1, while plain reads stay blind (`""`, Stretch) — the defeat instrument still works in there |
| Q3 | UIScale + non-integer sizes — does the canvas blur? | **GO, with a rider** | in-place A/B at identical geometry: the region the mask does NOT clip deviates by max **11/255** (330x24), **10/255** (301.52x21.93) and **8/255 with zero pixels over 6** (UIScale 2). More canvas resolution converges — the opposite of a fixed-resolution artifact. No geometry moved. |
| Q4 | does GroupTransparency compositing alter the alpha blend? | **NO** | the same middle-region deltas: max 11/255, mean 1.9/255, no inversion, no seam halo |
| Q5 | cost | real, countable, small | 60 bar-sized rows: 1.766 ms / +0.05 MB plain vs 2.818 ms / +0.48 MB masked → **~7 KB and ~18 µs per canvas**, Studio-derated |

**Shipped.** `mask = "pill"` joins `inset` on the three FULL-BLEED layer kinds
(`fill` / `frame` / `tile`) and is a compile error on the other three. A closed
set of **one** value, for the reason `PLAQUE_EDGES` is one edge: rs-m9 measured a
pill and nothing else. The adapter wraps a masked layer in an adapter-owned
`CanvasGroup` carrying the layer's BOX and a scale-0.5 `UICorner`, with the art
full-bleed inside it. **The wrapper is a shape, never paint:** untagged, so every
existing rule path still selects the same `ImageLabel`; `Active = false`; and its
own transparency is a class rule (`Canvas default`), not an adapter write.
Censused as `canvasMasks`, because a canvas is a real cost.

`glossy_touch`'s stripe layer now declares `mask = "pill", inset = { x = 2, y = 2 }`.
The inset drops from 10 to 2 and finally means only what an inset should: the
trough's rim is a 1px hard EDGE ring and its bottom lip a 1px lit bevel
(`generate_art.py`, `bar_track`), so 2px clears both — and a 20px-tall pill at
radius 10 is a full capsule, so the mask sits inside the trough's own arc rather
than crossing it. No texture regenerated, no re-upload; content stamp
`034aac88` -> `a520c5a8`.

**A defect this round found in its own work, live.** At stamp `62b6cdeb-1689276`
the wrapper read `GetStyled("BackgroundTransparency") = 0` — a fresh CanvasGroup
is opaque and no class rule reached it, so the mask was painting a solid pill
behind the very art it was shaping. Fixed by adding `CanvasGroup` to the class
defaults the sheet already emits (`Canvas default`), which is where every other
class default lives and the only place an explicit write would not be defeated
later. Verified at the next stamp: `styledBT = 1`.

**Live proof (stamp `57f3fc50-1689767`, Studio `0.731.0.7310942`, Play Solo).**
The mounted glossy bar's subtree:

```
/…/Download/Bar        [Frame]       z=47  78,612 223x24  luau-slot-barTrack|luau-skinned-barTrack  styledBT=1
  LuauUIChromeL1       [ImageLabel]  z=1   78,612 223x24  luau-chrome-barTrack-1                    styledBT=1
  LuauUIChromeL2Mask   [CanvasGroup] z=2   80,614 219x20  (no tags)  UICorner 0.5,0                 styledBT=1
    LuauUIChromeL2     [ImageLabel]  z=1   80,614 219x20  luau-chrome-barTrack-2                    styledBT=1
```

...i.e. the wrapper is inset by exactly 2/2, carries the pill, holds no tag, and
the tagged art is full-bleed inside it.

**Other packages: measured unchanged.** Across all seven reference packages the
census and the DataModel agree and there is exactly **one CanvasGroup in the whole
library** — `glossy-touch` 1/1, every other package 0/0. A five-step swap sweep
(glossy → neutral → glossy → ornate → glossy) returns 1/0/1/0/1 with the census
tracking the DataModel every time, so the wrapper neither leaks nor survives a
swap.

**HONEST LIMIT — two instrument faults, both named, neither diagnosed from.**

1. **The Studio Device Emulator was ON all session** (viewport 359x718 instead of
   the desktop 1233x1067) and is not reachable from `execute_luau` in this build:
   `StudioDeviceSimulatorService` exposes no readable or writable member. The
   quick-access monitor button was tried, proved to be the game-view *mode*
   switch, and was restored to its original state (verified by capture). All 5c
   live numbers above are therefore from the phone-emulated viewport. The
   mechanism is viewport-independent, but the **desktop row** is not re-captured.
2. **Screen capture went down mid-round.** `screencapture -l<window>` began
   returning "could not create image from window" and the MCP `screen_capture`
   began timing out; both persisted across retries and a 20s settle. Full-screen
   capture still works, but `tools/studio/capture_viewport.sh` forbids
   full-screen and region capture *by design* (they read screen pixels and can
   pull in unrelated windows), so it was not used and the one test file it
   produced was deleted.

**Consequence:** `RS-DIR5c_adaptive_desktop_glossy-touch_bar-pill.png` and its
8x A/B against the 5b capture are **NOT produced** — status `FAIL_ENVIRONMENT`.
What stands in for them is the rs-m9 probe capture, which shows the identical
CanvasGroup + UICorner(0.5) pill clipping the identical glossy stripe tile over
the identical trough art, beside the 5b inset shape for comparison. That proves
the mechanism and the look; it is not a capture of the shipped bar in the gallery.

**To close it (one pass, ~2 minutes):** turn the Device Emulator off in Studio,
confirm `workspace.CurrentCamera.ViewportSize` reads `1233, 1067`, confirm
`tools/studio/capture_viewport.sh /tmp/x.png` succeeds (granting Screen Recording
to the terminal if it does not), then run scenario `theme_authoring` step
`installGlossyTouch` and capture. The 5b capture
(`RS-DIR5b_adaptive_desktop_glossy-touch_bar-ends-clean.png`) is the before.

### 6. The toggle track's blobs were a real `UICorner`, not overlapping slice caps

**Reported:** circular/blob artifacts on the `glossy-touch` toggle track, on both
fixture toggles.

**THE LEAD DIAGNOSIS WAS FALSIFIED BY MEASUREMENT, and that is the finding.**
The reading was compelling: the track art is 72x32 with a 14px slice border all
round and the switch paints it into 44x24, so 14 + 14 of vertical cap does not
fit in 24px and the caps must be overlapping into a smear. The isolating probe
says otherwise. The same art rendered at 44x24, 44x8 and 20x8, each at
`SliceScale = 1` and at the exactly-fitting scale (`extent / 28`), gives six
clean capsules in three indistinguishable pairs. **Roblox clamps overlapping
nine-slice caps itself.**

A `SliceScale` clamp was written to the ruling, measured against the engine and
then deleted. Keeping it would have been a regression, not a no-op: a pixel
package's clamp has to floor to a clean integer-decimation step, and
pixel-quest's bar track would have rendered its caps at `0.25` where the engine
renders them at `6/16 = 0.375`.

**Root cause (one variable, changed alone).** A REAL `UICorner` child on a
`ScaleType = Slice` ImageLabel makes the engine round **each of the nine patches
independently** — the four corner patches become diamonds, the two middle
patches become lenses, and the picture disintegrates into exactly the cluster of
rounded shapes the director reported.

| row | `SliceScale` | `UICorner` | result |
|---|---|---|---|
| Z1 | 1 | no | clean capsule |
| Z2 | 24/28 | no | clean capsule |
| Z3 | 1 | **yes** | **six rounded blobs** |
| Z4 | 24/28 | **yes** | **six rounded blobs** |

A `UIStroke` alone is harmless to the image.

**Why R9's suppression missed it.** "The image is the element" turns a skinned
node's corner off through a phantom `::UICorner` rule, and a REAL child of that
class suppresses the phantom (`docs/lessons/stylesheet-defeat-order-sensitive.md`).
The toggle is the ONE slot whose chrome is real children — `buildToggleVisual`
gives the track and knob a `UICorner` and a `Hairline` so the palette-true switch
has its pill and its edge — so no rule could ever reach them.

**Fix.** `setTogglePartChrome(target, skinned)`: a skinned part's real corner goes
to radius 0 and its hairline to thickness 0 / transparency 1, **in both modes**,
because in native mode there is no rule that could; an unskinned part gets
`style.radii.pill` and the package's own hairline back. It sits inside the
real-child exception the authority manifest already declares for this assembly,
and it writes no `Position` and no `Size` — travel is untouched.

**Live proof (stamp `d45f712f-1695256`, Studio `0.731.0.7310942`, Play Solo).**
All four parts of both fixture toggles: `CornerRadius (0, 0)`, hairline `0 / 1.00`,
`SliceScale 1`, art resolved. A five-step package sweep
(neutral → ornate → pixel → compact → glossy → neutral) reads corner `0,0` +
hairline off + art on under every skinned package, and **`0, 999` + hairline
`1 / 0.92` under studio-neutral both before and after** — the palette-true switch
is byte-unchanged and the restore is proven rather than assumed.

**A second defect this round found in its own work, live.** Every `panel` and
`control` decoration in the value fixture carried `luau-chrome-fallback` while
reading `IsLoaded = true`: `watchChromeAsset` listens on the IsLoaded CHANGE
signal, and an image that is already resident never changes — so a decoration
built after its texture arrived reported nothing, and an asset marked failed
during a cold start stayed failed for the session. The consequence was visible in
the same capture: the disabled toggle row drew its control art at the
`:NonInteractable` `ImageTransparency 0.4` **over** the fallback's native fill and
its rounded phantom corner, which is the identical nine-patch artifact arriving
through a rule instead of a real child. The grace-deadline check now reads
`IsLoaded` in both directions; the deadline is the right place because by then
the rule that sets `Image` has applied. After the fix there is no
`luau-chrome-fallback` tag anywhere in the fixture and the glossy panel, bar and
button plates paint their art.

**RS-DIR6-F1 — FIXED (close-out round, 2026-07-25).** A node in FALLBACK still
took the `:NonInteractable` `ImageTransparency` dim, which re-revealed the art
the fallback had hidden, over its own native fill and rounded phantom corner.

**The cascade choice, and why.** Both rules write the SAME property, and the
cascade is Priority first, then insertion order, with NO selector specificity
(ADR-0018; `sheet_model` pins Priority as `index * 10`, so GROUP ORDER is the
answer). `Chrome — <slot> fallback` rides the `chrome` group and the disabled
rule rides `disabled`, so the dim won. The other candidate shape — scoping the
disabled rule off fallback-tagged nodes — is **not expressible**: a StyleSheet
selector has no negation, so "everything except a fallback node" cannot be
written. The fix is therefore by PRIORITY, in the same idiom the fallback rule
already uses to beat the resting art: one extra rule per chrome tag,
`Chrome — <slot> fallback over states` (and `… L<n> <kind> fallback over
states` per layer), emitted into the `disabled` group immediately after that
tag's disabled rule, carrying `ImageTransparency = 1` **and nothing else** —
the fill and the corner stay the chrome-group rule's, and nothing contests
those. Emitted per entry, so one slot's protection can never be undercut by a
later slot's disabled rule (different tag, different instance).

**Headless (red-first, 4 specs):** `tests/theme_chrome.spec.luau` (ordering +
pinned Priority + one-property + every-skinned-slot/flat-package-none) and
`tests/theme_layer_application.spec.luau` (all six layers of a stack). All four
fail with the emit removed and pass with it.

**Live proof** (stamp `407f3c9c-1705480`, Fantasy Ornate, `/LayerProbe`,
phone-emulator viewport 359x718). `DisabledField/Field` is a real
`disabled = true` TextInput — `Interactable = false`,
`GuiState = NonInteractable` — on the layered `field` slot:

| state | tags on `LuauUIChromeL1` | GetStyled `ImageTransparency` | GetStyled `BackgroundTransparency` / `BackgroundColor3` |
|---|---|---|---|
| disabled, art OK | `luau-chrome-field-1` | **0.45** (the dim) | 1 / — |
| disabled + fallback | `luau-chrome-field-1`, `luau-chrome-fallback` | **1** | **0** / `0.329, 0.243, 0.165` |
| recovered | `luau-chrome-field-1` | 0.45 | 1 / — |

The enabled `ProbeField` in the same fallback reads the identical 1 / 0 pair, so
the disabled node is no longer distinguishable from it in the fallback state,
which is the whole proposition. Recovery is symmetric (`recoverAsset` →
`fallbackSlots []`).

**New verification-surface step (contract §5).** `failAsset:<assetName>` /
`recoverAsset:<assetName>` on the `theme_authoring` scenario. `failMissingAsset`
swaps to the stub package and can only break its `panel`; proving this row needs
the slot a disabled control actually wears. Same ledger edge a real decode
failure reaches — no new machinery.

**Capture:** `RS-DIR6-F1_disabled-fallback_fantasy-ornate.png`.

**Capture:** `RS-DIR6_valueprobe_glossy-touch_toggles-clean.png`
(sha256 `5199f9748e3c5441`) — judge that both switches read as glossy capsules
with a round knob and that the disabled one differs only in weight.

**Lesson recorded:** `docs/lessons/roblox-slice-and-uicorner.md` — both engine
facts, so the next agent does not re-derive the wrong one.

### 7. A layered recipe's `contentInsets` never reached the solver

**Reported:** fantasy-ornate status-area button text overflowing the control, or
missing.

**Root cause (measured, and it is one table key).** `snapshot.resolve` published
`chromeInsets` for `kind == "nineSlice"` recipes ONLY, while the adapter boxes a
decorated node's lifted label by `contentInsets` for a LAYERED recipe too
(`chrome_slots.liftGeometry`, fed the stack plan). So a layered package's insets
were applied at PAINT and reserved by NOBODY.

Measured live at the pre-fix stamp `57f3fc50-1689767` on
`/AdaptiveScreen/BodyScroll/Body/Hud/Toolbar/TbPlay`: the button solved to
**48x47**, the adapter's own `UIPadding` is 12 each side and fantasy-ornate's
`control` stack declares `contentInsets = { 10, 14, 10, 14 }` — so the lift,
which resolves against the button's PADDED content box, came out at
**-4.0 x 27.0**. A negative box draws nothing, which is why the label was not
clipped but **absent**. The wide buttons in the same package were the same defect
with a survivable sign: a lift 28px narrower than the box the solver measured for.

It surfaced now because of the zero-slack property this packet recorded in round 5
— once a content button measures exactly its engine bounds, an inset applied at
paint and not at measure has nowhere left to hide.

**Fix.** `chromeInsets` (and the slot's own `insets`) are composed for every
recipe kind that materializes art — `nineSlice` **and** `layered`. Not a fixture
tweak and not a hardcoded size: the measurer now reserves exactly what the paint
seam consumes. Reverting the one added table key turns three propositions red,
including the `liftWidth > 0` invariant.

**Live proof (stamp `d45f712f-1695256`).** The ornate status toolbar:

| node | box | lift | engine bounds | label |
|---|---|---|---|---|
| `TbBack` | 65x67 | 13.0x47.0 | 12.5x17.0 | `◀` |
| `TbPlay` | **76x67** | **24.0x47.0** | 23.5x17.0 | **`Play`** |
| `TbMore` | 61x67 | 9.0x47.0 | 8.5x17.0 | `…` |

**Sweep of the other packages' status areas — same class, all clear.**
glossy-touch (layered) 65x63 / 77x63 / 61x63 with lifts 13.0 / 25.0 / 9.0;
pixel-quest (layered) 67x76 / 80x76 / 65x76 with lifts 11.0 / 24.0 / 9.0;
compact-pointer (nineSlice) unchanged at 49x45 / 60x45 / 48x45, because a
nine-slice recipe always reserved. Every lift holds its engine bounds on one line.

**A second orphan this found.** After a layered → flat swap the toolbar's three
buttons each kept a `LuauUIChromeText` still boxed at `{1, -28}` inside a 36px
button — **-16.0 px wide**. It drew nothing at that size, which is exactly why it
survived: the node's own engine text was doing the drawing. `destroyChromeStack`
never called `destroyChromeText`; the nine-slice rebuild path always had. Fixed,
and a stack being rebuilt gets its lift back on the next line.

**Preferred-text axis.** The headless axis is green, including
`a preference BELOW 1 never reserves less than the painted size` and
`the reservation floor composes with the ten-foot paint scale`. The LIVE axis is
`FAIL_ENVIRONMENT`: the scenario `setEnv` seam reported `applied = []` for
`preferredTextSize` in this build, frozen and unfrozen alike.

**Capture:** `RS-DIR7_status_desktop_fantasy-ornate_text-fits.png`
(sha256 `e371059d0ff961a0`) — every status-area label intact and inside its
control. **Honest limit:** the Studio Device Emulator was ON for the whole
session and is not reachable from `execute_luau` in this build, so the capture is
the phone-emulated viewport (359x718) with the body scrolled to the Status
section, not the desktop row the filename names. Every number above is solved px
and viewport-independent.

**What these two rounds supersede.** Every `RS-A16` five-view row for
fantasy-ornate, glossy-touch and pixel-quest is now pre-fix history for CONTROL
geometry: a layered package's buttons grew by their recipe's insets. The five-view
matrix was deliberately not re-driven this round.

### What this round changed for FLAT themes

`check_flat_baseline` stays PASS: **1506 flat nodes compared, 0 rect changes, 0
hit-rect changes, 0 class changes, 0 nodes disappeared.** Defect 1 adds nothing
for a package with no ornaments. Defect 2 leaves a node with no art on today's
solved-rect ring. Defect 3 is the one characterized change: a `textSize` prop now
appears on every text-bearing node, carrying the class's intrinsic role size.
Studio Neutral's own roles are `body = 16` / `control = 18` and the solver ALREADY
measured those, so no geometry moves — what moves is the size the engine draws a
Button/TextField label at (16 -> 18), which is the size its box was always
reserved for. It is enumerated in `check_flat_baseline`'s new `ALLOWED_ADDED_PROPS`
list with that reason; every other prop, on every node, still has to match byte
for byte.

**Standing item for the next matrix drive.** A content-sized button's box is its
measured text by construction, so `TbPlay` now measures exactly its engine bounds
(20 = 20) with no slack. That is correct — the measurer's documented policy is to
over-reserve, never under — but it is the number to watch on the five-view rows
and under preferred-text.

**Rounds 6 and 7 add nothing here.** Defect 6 acts only on a toggle part that
carries `luau-skinned-toggle*`, which a flat package never earns — and the sweep
above proves the flat pill and hairline are byte-identical before and after a full
skinned round trip. Defect 7 composes `chromeInsets` for a recipe kind flat
packages do not declare, so `chromeInsets` stays EMPTY under Studio Neutral and
the whole block is a no-op. `check_flat_baseline` re-run at the round-7 stamp:
**PASS — 1506 flat nodes, 6 characterized prop deltas, 4 characterized new nodes,
1 characterized added prop key, 0 rect / 0 hit-rect / 0 class changes**, i.e. the
same characterized set round 5 left, with nothing added.

---

## Close-out round (2026-07-25) — the chrome module extraction

**The hazard, measured.** `src/client/screen_target.luau` had reached **199 613
bytes**. `tools/studio/inject.luau` syncs by assigning `ModuleScript.Source`, and
a live Studio probe pins the ceiling exactly: 199 999 assigns, **200 000 and
above raise** `Unable to assign property Source. Provided string length (N) is
greater than or equal to max length (200000)`. The file had **386 bytes** of
headroom; the next addition would have broken Studio sync for the whole stage.

**The cut.** The chrome/decoration subsystem moved verbatim to a sibling,
`src/client/screen_chrome.luau`, along the seams the fix rounds already named —
decoration slots, semantic icons, the chrome text lift, slot shadows, layer
stacks, the bar assembly, toggle art, the rung-2 per-view override, and
`syncChrome`/`syncChromeInner` themselves.

| file | before | after |
|---|---|---|
| `src/client/screen_target.luau` | 199 613 | **116 936** |
| `src/client/screen_chrome.luau` | — | **90 042** |

`screen_target` requires `screen_chrome` and never the reverse
(`docs/lessons/lune-circular-require-hangs.md`); everything the module needs
arrives as an explicit `Context` (style, nativeMode, hasUIShadow, chromeState,
instancesByPath, handlesByPath, focusedHandles, palette, assertBespokePaint,
syncTags) plus the two seams that cannot be upvalues — `snapshot()` (reassigned
inside `setThemePackage`'s swap transaction) and `setFocusVisual` (defined below
the subsystem in the target). The thirteen exports are re-bound to locals of
their original names in `screen_target`, so every call site — and every source
contract that anchors on one — is byte-unchanged.

**Behaviour-neutrality.** The suite is **1699 before → 1699 after** the move
(the four new specs in this round belong to RS-DIR6-F1, taking it to 1703).
`check_flat_baseline`, `check_docs_cli`, `check_prop_parity`,
`check_registration`, `check_boundary`, `check_theme_drift`, `bench` and the
RascalRally game suite (2404) are all green. The source-contract specs that
anchored on `screen_target.luau` function text (`theme_layer_application`,
`theme_icons_applied`, `native_style_scenario`, `theme_value_displays`) keep
every assertion; only the file their anchor resolves in moved.

**Live smoke** (stamp `407f3c9c-1705480`, capture
`RS-EXT_smoke_fantasy-ornate.png`). Injection created the new node and patched
with **zero failures**. Fantasy Ornate installs on the extracted build and the
census is intact: **73 live decorations, 60 layers over 30 layered nodes, 139
actual layer instances, 26 shadows = 26 actual, 17 text lifts, 3 icon art, 1
focus glow = 1 actual, 0 canvas masks**. `GetStyled` still detects suppression
where a plain read is blind — on `TbPlay`, plain `BackgroundTransparency = 0`
while `GetStyled` reads **1**. Focus placed on the Quality stepper's first
option parents a `FocusGlow` `UIShadow` (BlurRadius 26, colour
`0.973, 0.808, 0.424`) to **`LuauUIChromeL1`**, the art host — not the node —
which is `focusArtHost` deciding from the extracted module.

**Session facts, recorded honestly.** The Device Emulator was ON (viewport
359x718, phone portrait with a notch); the five-view matrix was deliberately not
driven. In this Studio session `ornate_bar_fill` and `ornate_bar_center` (shared
by `badge`) never decoded — `IsLoaded = false` on visible, non-zero-area nodes at
non-zero opacity — so those slots sit in their declared native fallback. That is
the asset-failure ledger working, not a regression: the census immediately after
install is clean and the flags appear only once the 5 s grace deadline passes.
No `RSV2_AssetCheck` scratch GUI existed in the Edit or Client DataModels.

---

## Final matrix drive (2026-07-26) — STOPPED at row 1: RS-A16 is `FAIL_PRODUCT`

Final stamp **`407f3c9c-1705480`** (library 0.7.0, suite 1703). The tree was frozen
at the post-5e state; this drive changed no source, no example and no doc.

**The clean inject at the final stamp:** 120 nodes, **0 created / 0 patched / 104
unchanged / 0 failures**. The open place already matched the frozen source byte for
byte, including the extracted `src/client/screen_chrome.luau` node — so the
inject proof here is *zero drift at the final stamp*, not *the new node was created
here* (the close-out round created it).

**Preflight passed in full.** Stamp identical across every read in the session
(sync manifest, workspace attribute, scenario report); viewport non-`1×1`;
exactly one LuauUI `ScreenGui` mounted; log boundary clean of framework
warnings/errors (the only two errors in the window are this driver's own probe
scripts); canary capture cross-checked against the MCP `screen_capture`, which
showed the same live frame and was **not** stale; and a canary **input** that
paired a real `UserInputService.InputBegan` `MouseButton1` `Begin` at (388, 87),
`gameProcessedEvent = true`, with its application effect — stepper 6 → 7,
`semanticText "7 of 0 to 10"`.

### The instrument moved: device selection now works from `execute_luau`

Every earlier row in this repository recorded that `StudioDeviceSimulatorService`'s
**setters** were absent at this security level, which is why preset viewports had to
be driven through the runner's declared `setEnv` seam and why the RS-A14 phone
captures and the Step-3 console capture were cropped by the Studio window. That is
no longer true. `SetDeviceAsync`, `SetOrientationAsync` and `SetResolutionAsync` are
all present **and effective**, in both the Edit and the Client (Play) datamodels;
`ConfigurationChanged` fires, the engine viewport really changes, and the framework's
**live** env binding follows it — so this session used **no `setEnv` injection at
all** (`envFrozen = false`).

All five presets were discovered at runtime (`GetDeviceListAsync` → 42 entries, no
hard-coded ids) and driven at real viewports:

| Row | Preset | Orientation | Reported viewport | Derived |
|---|---|---|---|---|
| `compact-phone-portrait` | `samsung_galaxy_a06` (800×360, scale 2, 262 dpi) | Portrait | **359×718** | compact / Small / near |
| `compact-phone-landscape` | same | LandscapeLeft | **705×338** | regular / Small / near |
| `tablet-landscape` | `ipad_9th_generation` (1080×810, scale 2, 264 dpi) | LandscapeLeft | **1079×809** | wide / Small / near |
| `desktop-standard` | `hd_1080` + `SetResolutionAsync(1233, 1067)` | default | **1232×1067** | wide / Medium / near, `PreferredInput = KeyboardAndMouse` |
| `console-ten-foot` | `xbox` (1920×1080) | default | **1920×1078** | regular / **Large** / **ten-foot**, typography ×1.5, screen inset **90×60** overscan, **`PreferredInput = Gamepad`** |

Three honest limits of the new instrument, all newly measured:

- **The emulator's reported viewport is a *fitted* size, not always the catalog
  resolution.** `samsung_galaxy_a06` (catalog 800×360) reports 359×718 portrait;
  `iphone_7` (667×375) reports 374×666 exactly. Both numbers are recorded per row;
  the framework laid out for the **reported** viewport, which is the one the picture
  shows, so trace and capture agree. The desktop row additionally pins 1233×1067 so
  it stays the project's standard development viewport.
- **Touch is a boot-time fact; gamepad is not.** `TouchEnabled` /
  `PreferredInput = Touch` are decided at Play start from the then-selected preset
  and do **not** follow a mid-session `SetDeviceAsync` — a session booted on
  `hd_1080` keeps `touch = false` while showing a 359×718 phone viewport. The
  `xbox` preset, by contrast, *does* flip mid-session and really publishes
  `PreferredInput = Gamepad`. Consequence: the 19 rows must be driven in **two Play
  sessions** (boot desktop for desktop/console/pair-desktop, boot phone for
  phone/tablet/pair-phone), flat rows first in each because `studio-neutral` is the
  built-in default and `installNeutral` has no module to load.
- **`deviceSafeInsets` read 0 on every preset**, even where the emulator draws a
  notch. Only `coreSafeInsets` (top 58) and `TopbarInset` are real, so a genuine
  notch-inset row is **not** closed by this instrument. `VirtualInput` is still
  unusable from `execute_luau` (it exists; it exposes no `Send*` methods), so native
  input evidence still comes from MCP injection. The console row's gamepad class is
  **emulated** — hardware delivery, arbitration, overscan and console performance
  stay E4.

### RS-A16-D1 — the defect that stopped the drive

**MAJOR, user-visible, under the FLAT default.** A losing `ViewThatFits` candidate
keeps **live hit expanders** that cover the visible winning candidate.

`/Actions/ActionsColumn` is `Visible = false` at 0×0, but three
`LuauUIHitExpander` `TextButton`s for its zero-width buttons sit at the **ScreenGui
root** — `Visible = true`, `BackgroundTransparency = 1`, `Active = true`, 44×68 /
44×89 / 44×68 at x = 284, `ZIndex` 108/109/110, i.e. **above** the winning row's
103–105.

- `PlayerGui:GetGuiObjectsAtPosition(315, 970)` — a point **inside the visible
  "Save changes"** — returns `LuauUIHitExpander z=108` **first**, ahead of
  `/Actions/ActionsRow/Save z=105`.
- Two **real injected clicks** settle it: (315, 970) fired **only**
  `LuauUIHitExpander.MouseButton1Click` / `.Activated` — the visible button
  received nothing — while (400, 970) on the same button fired
  `ActionsRow/Save.MouseButton1Click` / `.Activated` correctly.
- So the left **22 px** of a visible button is dead, and the click **activates a
  control that is not on screen** (the expander's guard only checks
  `Interactable ~= false`, and the hidden control's is `true`).
- It reproduces at 359×718 (expanders at x = −6, the same 22 px strip, on the touch
  form factor) and the third expander is **outside the viewport** on both rows.
- It is under **`studio-neutral`**, so it is neither theme-specific nor caused by
  this stage; `check_flat_baseline`'s "0 hit-rect changes" is consistent with it
  being pre-existing. The session **booted and `reset()` at the desktop preset**, so
  it is steady state, not an orientation leftover.

**Root cause, two places.** `pushHitRects` in `src/render/renderer.luau` walks the
whole tree without consulting the `nextHidden` map that `pushVisible` built one
block earlier, so a hidden candidate's zero-width controls fall under the 44 px
floor and the renderer *asks* for an expander; and `adapter.setHitRect` in
`src/client/screen_target.luau` parents that expander to `instance.Parent`, which
for a non-clip-hosted node is the ScreenGui root — so `Visible = false` on the
candidate never reaches it, and `targetZ − 1` still out-ranks the winner. The
source comment states the intent it violates: *"a transparent expander BEHIND the
control (lower ZIndex) … so the control still wins where they overlap."*

Diagnostic capture:
`captures/RS-A16-BLOCKED_hit-expander-overlay_desktop-standard_studio-neutral.png`
— the three expanders tinted red by the driver (restored to transparent
immediately after), so the red rectangle straddling the left edge of "Save changes"
is the otherwise-invisible defect.

**Nothing was superseded.** No stored capture was overwritten. All 19 canonical
`RS-A16_*` PNGs remain the 2026-07-25 pre-director-round images, and
`artifacts/theme-packages-and-skinning/b-a13-matrix.json` still stands. Because the
matrix cannot pass, `rs-a16-matrix.json` carries `rows: []` on purpose so the gate's
`studio-matrix-final-stamp` check **fails loudly** rather than passing on a partial
matrix.

**Owed to close RS-A16:** fix D1 red-first (an E1 regression for the renderer
decision plus a Studio scenario read for the adapter half), then re-drive all 19
rows at the new final stamp in two Play sessions, with the asset-decode `IsLoaded`
guard before every ornate/pixel/glossy capture, and replace all 19 canonical
captures.

---

## RS-A16-D1 — FIXED (2026-07-26, stamp `a7da3802-1708708`, suite 1703 → 1710)

Fixed in a separate implementer round. **The matrix was NOT driven** — this round
closes the blocker only, so `rs-a16-matrix.json` keeps `rows: []` and RS-A16 goes
back to `PENDING`, not `PASS`. Full evidence lives in that file under `defectFixed`.

### The two source changes

| File | Change |
|---|---|
| `src/render/renderer.luau` | `pushHitRects` now carries the `nextHidden` verdict **down the walk** exactly as `pushVisible` does (the solver marks the candidate root only), and a hidden node takes the **same diff path** with `want = nil`. One gate closes both paths: a hidden candidate's controls never request hit geometry, and a node that *becomes* hidden gets `adapter.setHitRect(handle, nil)` — a real retraction, not a stale cache. |
| `src/client/screen_target.luau` | The structural half. `adapter.setVisible` carries `handle.hitExpander.Visible` with its host; a newly created expander is born at `instance.Visible`; and the `Activated` guard refuses a host whose `Visible` is false. |
| `src/client/screen_target.luau` | `adapter.setZOrder` carries `handle.hitExpander.ZIndex = z - 1` with the control. A structural sync re-assigns z from the tree walk without necessarily moving any rect, and an expander that stopped being exactly one behind its control would start swallowing that control's own clicks — the D1b invariant at the other seam that can break it. |

**The shape chosen for the structural half, and why not parenting.** Parenting the
expander *under* its control would inherit `Visible` for free — and would break the
feature: under `ZIndexBehavior.Sibling` a descendant renders **above** its ancestor
regardless of `ZIndex`, so the expander would cover the control it exists to serve
and swallow that control's own hover, press and `Activated`. The expander must stay a
**sibling behind** the control (the source comment's stated intent). So visibility is
mirrored explicitly — three lines, one per lifecycle point (birth, change, activation)
— and the class dies structurally without moving the instance.

### Live proof at the fix stamp

Preflight passed: stamp identical across sync manifest / workspace attribute /
scenario report; one LuauUI `ScreenGui`; viewport 1232×1067 non-`1×1`; **real
`hd_1080` preset with `SetResolutionAsync(1233, 1067)`, `envFrozen = false`** (no
`setEnv` anywhere in the proof); console clean of framework warnings and errors; 0
solver diagnostics.

- **Expander census:** 2 in the whole tree, both for **visible** sub-floor toolbar
  buttons (`TbBack` 36→44, `TbMore` 34→44), each exactly centred on its host. The
  three ScreenGui-root expanders belonging to the hidden `/Actions/ActionsColumn`
  are **gone**.
- **`GetGuiObjectsAtPosition(315, 970)`** — the driver's exact probe — now returns
  `/Actions/ActionsRow/Save z=105` **first**, identical to `(400, 970)`.
  `(284, 970)`, where the expander used to be, returns only `/AdaptiveScreen z=1`.
- **Real injected clicks:** `(315, 970)` → `RAW MouseButton1 Begin (315,970)
  processed=true` → `CLICK` + `ACTIVATED` on **`ActionsRow/Save`** and nothing else
  (the hidden `ActionsColumn/Save`, armed on the same run, received nothing).
  `(400, 970)` unchanged. `(284, 970)` → `processed=false`, no activation anywhere.
- **The 44 px floor still works:** a real click at `(1179, 78)` — inside the
  `TbMore` expander, *outside* the 34 px-wide button — fired the expander and the
  framework moved focus to `/Toolbar/TbMore`.
- **Phone row, second Play session booted on `samsung_galaxy_a06` portrait**
  (359×718, `TouchEnabled = true`, `PreferredInput = Touch`, `primary = touch` — a
  genuine touch form factor, unlike the blocked drive's pointer boot): 2
  host-centred expanders, 0 for the hidden column, and
  `GetGuiObjectsAtPosition(25, 610)` — the driver's phone probe that returned the
  expander first — now returns `ActionsRow/Save` first. A real injected **touch** at
  `(25, 621)` fired `DOWN` + `ACTIVATED` + `CLICK` on `ActionsRow/Save`.

Captures (all sha-pinned in `rs-a16-matrix.json`):
`RS-A16-D1_fixed_desktop_studio-neutral.png` (product state),
`RS-A16-D1_fixed-tinted-expanders_desktop_studio-neutral.png` (the **same**
diagnostic instrument the blocked drive used — the red frame now sits only around the
two toolbar buttons that own it, and no red rectangle straddles the left edge of
"Save changes"), and `RS-A16-D1_fixed_phone-portrait_studio-neutral.png`.

### RS-A16-D1b — a second defect of the same family, found by this fix's own live proof

**MAJOR: a hit expander placed 74 px away from its control.** After `api.reset()` at
1232×1067 the `TbBack` expander sat at **636,129** for a host at **624,55** — it used
`ox,oy = 0,−58` instead of the ScrollView's `16,16`. Deterministic: wrong after every
reset, correct again after any re-solve that *moved* the wanted rect, wrong again
after the next reset.

`pushHitRects` runs **before** the commit loop that writes rects, so on a fresh build
a clip host's origin is not yet current when the expander is first placed; and
because the renderer caches only the *wanted* rect, it never asks again.
`adapter.setRect` re-bases every clip-host **child** when the host's rect lands — but
the expander was not one. It only looked correct on a cold boot because the
text-premeasurement re-solve happens to move the wanted rect there; after a reset the
widths are already learned, so nothing follows the first commit. **Every re-driven
matrix row would have carried misplaced expanders**, which is why it is fixed here.

Fix: the placement moved into a shared `applyHitExpander(handle)` that reads
`handle.hitRectWant` and the current clip-host origin, and **`applyRect`** — the one
function that re-bases a node, including when its host's rect arrives late — now
calls it. `setHitRect` stores the want and delegates. The expander and its control
can no longer disagree about the origin. Proven live on the fresh boot **and** after
two consecutive `reset()` calls: both expanders exactly centred at `(620,55)` and
`(1177,55)`; same at the phone preset.

### One fixture observation for the matrix owner (recorded, not changed)

`/Actions` is a `ViewThatFits` whose **both** candidates declare `width = fill`, and
`solver.chosenCandidate` accepts the first candidate that fits: a `fill` candidate
measures to at most the available width, so `fitsW` is unconditionally true. The
`ActionsColumn` candidate is therefore **unreachable at every viewport driven here** —
w ∈ {1232, 359, 240, 160, 120, 90} and h ∈ {1067, 718, 900, 400, 260, 200} all kept
the row, down to 14 px-wide buttons. Two consequences: the live sweep could not
**flip** the winner (the flip is proven headlessly instead — `tests/adaptive.spec.luau`
drives the choice both directions and probes hit geometry each way), and it explains
the defect's severity — the loser was always the column, always hidden, so its dead
expanders were always live. Whether the fixture should declare a non-flexible first
candidate is the fixture/matrix owner's call.

### The regressions this round adds

`tests/adaptive.spec.luau`, `describe "RS-A16-D1: a hidden ViewThatFits candidate
requests no hit geometry"` — 7 specs written red-first (5 of 6 failed on the pre-fix
tree; the 7th, D1b, failed on the pre-fix adapter): a hidden candidate asks for no hit
rect; the visible winner's hit geometry is unchanged; a node hidden **after** expansion
is retracted (asserted on the adapter's op log, not just the cache); re-choosing back
re-expands; hiddenness reaches a **deep** descendant; the adapter mirrors host
visibility; the expander is placed by the same path that places its control. Two
existing source-anchor specs (`value_controls` V11, `theme_layer_application`
focus/hit) were re-anchored to the moved code with their claims intact.

`check_flat_baseline` **PASS, unchanged**: 1506 flat nodes, 6 characterized prop
deltas, 4 characterized new nodes, 1 characterized added prop key, **0 rect / 0
hit-rect / 0 class changes**, stored dump still byte-reproducible. The absence of a
delta is verifiable rather than lucky: **none of the eight baseline fixtures uses
`ViewThatFits`**, so no baseline node was ever a hidden candidate — which is also why
the blocked drive's "0 hit-rect changes" was consistent with a pre-existing defect.

New durable instrument truth recorded in
`docs/lessons/injected-mouse-coords-are-gui-space.md`: on a **touch-booted** emulator
session an injected click arrives as `UserInputType.Touch` with the routed position
offset from the injected one (measured −47 px in y, preset-dependent), so the offset
must be **discovered** per session rather than assumed 1:1.

---

## Final matrix drive #2 (2026-07-26) — STOPPED at row 4 of 19: `FAIL_PRODUCT` again

Final stamp **`a7da3802-1708708`** (library 0.7.0, suite 1710). The tree was frozen
post-D1/D1b; this drive changed **no source, no example and no doc** — writes were
limited to `artifacts/rich-skinning-v2/`.

**Clean inject at the final stamp:** 120 nodes, **0 created / 0 patched / 104
unchanged / 0 failures** — zero drift. The stamp read identically from the sync
manifest, the workspace attribute and every scenario report in the session.

**Preflight passed in full.** One LuauUI `ScreenGui` mounted (`LuauUI_AdaptiveScreen`);
viewport non-`1×1`; scenario ready with 61 steps; log boundary clean of framework
warnings and errors (the single error in the window is this driver's own probe script
attempting to *read* `BindableFunction.OnInvoke`, which is set-only); canary capture
cross-checked against the MCP `screen_capture` on the same frame (same live state,
**not** stale); and a canary **input** pairing a real `UserInputService.InputBegan`
`MouseButton1` `Begin` at (388, 87) `gameProcessed = true` with its application effect
(stepper `6 → 7`). `GetMouseLocation` read 145 for an injected 87 — the documented
+58 inset, exactly as `docs/lessons/injected-mouse-coords-are-gui-space.md` predicts
for a desktop-booted session.

### RS-A16-D1 / D1b, independently confirmed fixed

The fix was written and proven by the implementer who wrote it; this is the first
*independent* read. After `api.reset()`: exactly **2** `LuauUIHitExpander`s in the
whole tree, both on **visible** sub-floor toolbar buttons, each exactly host-centred
(`centreDelta 0`, `hostVisible = true`); the hidden `/Actions/ActionsColumn`'s three
are gone. `GetGuiObjectsAtPosition` 9 px inside the visible **Save changes** returns
`/Actions/ActionsRow/Save z=105` **first** on both driven viewports and under both
driven packages. Under Fantasy Ornate there are **zero** expanders at all, because
every ornate control clears the 44 px floor unaided. And a solved-vs-actual
reconstruction — declared `UDim2` + parent box + `UIPadding` + `CanvasPosition`
against `AbsolutePosition`/`AbsoluteSize`, which is precisely the invariant D1b broke
— found **0 mismatches over 195 visible nodes**.

### RS-A16-D2 — a plaque's `overhang` is painted and published but never RESERVED

**FIXED (2026-07-26, stamp `1de8a15c-1722217`, lead-driven live proof after the fix agent's API-interrupted round landed the code).** `chromeOutsets` is now written per ornament kind from the same extent table the census reads (publish-without-reserve structurally impossible). Live at the current stamp: the Media nameplate's top edge clears the "Save changes" title above it by exactly the row's 8px gap; a full-tree sweep found ZERO text nodes intersecting the plaque rect. Capture `RS-A16-D2_fixed_desktop_fantasy-ornate.png` (sha16 `b952491f117dc8b7`).

Observation (benign, for the fixture owner): the hidden ViewThatFits loser's zero-width buttons carry degenerate −4px-wide text lifts — invisible by ancestry, no hit surface (D1 removed their expanders), inert; noted here so nobody rediscovers them as a mystery.

Original finding follows for the record.

**MAJOR, user-visible, Fantasy Ornate.** The 16:9 Media panel's ornate nameplate
(`LuauUIChromeL6`, 176×40 at y 187) hangs 20 px above the panel's own box, straight
through the **"Save changes"** label that sits above it.

| | desktop-standard 1232×1067 | console-ten-foot 1920×1078 |
|---|---|---|
| plaque rect | `[832, 187, 176, 40]` | `[1303, 270, 176, 40]` |
| victim row `/Hud/SaveLabel` | `[887, 177, 66, 22]` | `[1342, 249, 98, 33]` |
| overlap | `[887, 187, 66, 12]` = **792 px²** | `[1342, 270, 98, 12]` = **1176 px²** |

It paints *above* the label because the plaque descends from the Media node
(`ZIndex 52`) while `SaveLabel/Title` is `ZIndex 51`, and `ZIndexBehavior` is
`Sibling`. The solver believes the rows are clear: SaveLabel ends at y 199, Media's
solved box starts at y 207 — the Hud stack's own 8 px gap. Nothing ever asked for
those 20 px.

**Root cause.** `out.chromeOutsets` in `src/themes/snapshot.luau` is the one seam that
turns "this slot paints outside its rect" into a solver margin, and it has exactly one
writer: the `barTrack` branch the director round added ("*Only the bar family
publishes one today*"). A plaque's `overhang` is validated in `src/themes/package.luau`,
turned into a real box in `src/tokens/chrome_slots.luau` (anchor y = 0, offset
`-overhang`) and published for **inspection** in `census.overhang` — but never
converted into an outset, so the renderer's margin seam never sees it. The director
round's defect-1 note calls the bar reservation *"the reservation consequence a
plaque's `overhang` already has (rs-m3)"*; the shipped code never implemented it.
Same accepted-and-ignored class as Step 3's container `align` and director defect 7's
layered `contentInsets`.

**Also measured, same cause:** 21 further 84 px² overlaps — the Stat plates' `corners`
ornaments are centred *on* their plate's corners and so hang 6 px above their row into
the Media panel's bottom border. Cosmetic (ornament over frame, not over text), but it
belongs to the same decision.

**Smallest fix:** publish a stack's declared `overhang` as `chromeOutsets[slot]`
beside the barTrack reservation — `chrome_slots.hasOverhang` already computes it for
the census — so the existing renderer margin seam moves the neighbours. Deterministic,
so red-first E1 regression plus a Studio scenario read.

**Capture:** `RS-A16-BLOCKED_plaque-overhangs-neighbour_desktop-standard_fantasy-ornate.png`
(sha256 `08189d99365538c2`) — a 3× zoom of the **product state**, nothing tinted and
nothing moved: "Save changes" with its lower half behind the plaque.

### RS-A16-D3 — pixel-quest's progress fill solves to ZERO height

**FIXED (2026-07-26, same stamp/session).** pixel-quest declares `controls.progress.trackHeight = 28` (integer-unit, chosen against the art) and the framework now diagnoses insets that zero a value-display's content box. Live: track 691×28, clip window 236×12 at value 0.35 (height no longer 0), full-width art loaded inside. Capture `RS-A16-D3_fixed_desktop_pixel-quest.png` (sha16 `6890c3b56e6000a2`).

Original finding follows for the record.

**MAJOR, user-visible, pixel-quest.** The download bar draws its trough and both heart
end-caps and **no fill at all**. At value 0.35 the left 35 % of the trough is
indistinguishable from the right 65 %, so the control communicates nothing.

- `/Hud/Download/Bar` = `[696, 159, 473, **8**]`
- `/Hud/Download/Bar/Fill` = `[704, 167, 160, **0**]`, and `LuauUIBarWindow` and
  `LuauUIBarFill` are both `h = 0` too. The fill starts at y 167 — the track's *bottom*
  edge — and is zero tall.
- Identical arithmetic at the console row: `Bar [1058, 230, 691, 8]`,
  `Fill [1066, 238, 236, 0]`. Viewport-independent.
- Width still works: 473 − 16 = 457 usable × 0.35 = 160, exactly the fill's width.
  Only the cross axis collapses.

**Root cause.** `examples/themes/pixel_quest.luau` declares
`barTrack.contentInsets = { 8, 8, 8, 8 }` and never overrides
`controls.progress.trackHeight`, so the track inherits the framework default 6
(`src/themes/snapshot.luau`) which the package's own pixel snap (unit 4) raises to
**8**. The director round made a layered recipe's `contentInsets` reach the solver as
the node's padding, so the fill's height is `max(0, 8 − (8 + 8)) = 0`. Two places it
could be fixed, and the choice is the owner's: **package** — give pixel-quest a
`progress.trackHeight` its own insets can afford (≥ 24 on a 4 px grid); **framework** —
refuse or diagnose a `contentInsets` pair that exceeds the host's resolved cross
extent (`solverDiagnostics` stayed 0, so the framework did not consider this worth
mentioning). `LuauUIBarFill.IsLoaded = false` is a *symptom* — a 0-px node never
decodes — not an asset failure.

**Why no earlier row caught it.** RS-A5's percent sweep and the `barSweep` step drive
`/ValueProbe` under `layered_test` and Fantasy Ornate, both of which declare **zero**
`barTrack` insets; and defect 1's live proof measured the pixel bar's *cap and label
clearances*, never the fill's cross extent. No stored assertion has ever read it.

**Capture:** `RS-A16-BLOCKED_bar-fill-zero-height_desktop-standard_pixel-quest.png`
(sha256 `8b1853309946752d`) — a 2× zoom of the product state.

### Scope, measured live per package

| Package | `census.overhang` | neighbour overlaps | `barTrack` insets | verdict |
|---|---|---|---|---|
| studio-neutral | — (0 ornaments) | 0 | — | clean; neither defect can reach flat |
| fantasy-ornate | `{panel:{top:20}}` | **22** | `0,0,0,0` | **D2** |
| pixel-quest | `{}` | 0 | `8,8,8,8` on an 8 px track | **D3** |
| glossy-touch | `{}` | 0 | — | clean |
| compact-pointer | `{}` | 0 | — | clean |

`grep` over `examples/themes/` agrees: only `fantasy_ornate.luau` (and the
`layered_test` *schema* fixture, not a matrix package) declares a plaque `overhang`.
So **11 of the 19 planned rows** — ornate × 5 views and pixel × 5 views, plus the
ornate re-look — would have stored a picture of a known defect.

### What the four driven rows did prove

Recorded in `rs-a16-matrix.json` as `rowsMeasuredNotClaimed`, never as rows:

- **Both flat rows fully clean:** 39 text nodes with **0 unfit**, 0 multi-line, 0 clip
  bleed, 0 nodes outside the viewport, 0 solver diagnostics, 112 mount-identity
  entries, scroll canvas not short, focus on `/Volume/Dec`.
- **Ornate desktop clean on everything except D2:** the asset-decode guard settled
  **140** visible image-bearing nodes over **22** distinct assets with **0 not loaded**;
  13 lifted chrome status texts, every one **inside** its control (defect 7 holds); the
  bar's own caps and crown clear every neighbour by **0 px²** (defect 1 holds); the
  focus visual rides the **art** — `FocusScale` (UIScale) on the button plus
  `FocusGlow` (UIShadow) parented to its `LuauUIChrome` (defect 2 holds); "Play" on one
  line at every driven density, including compact-pointer's 13 px text (20×13 bounds in
  a 60×45 box, defect 3 holds).
- **Style authority proven by disagreement.** On `/Actions/ActionsRow/Save`:
  `BackgroundTransparency` plain `0` vs styled **1**, `TextColor3` plain `#1b2a35` vs
  styled `#f6eace`. On its `LuauUIChromeL1`: `Image` plain `""` vs styled
  `rbxassetid://112835782358182`, `ScaleType` plain `Stretch` vs styled **`Slice`**,
  `SliceCenter` plain `0,0,0,0` vs styled **`16,16,48,48`**. Through
  `LuauUIStyleLink` → `LuauUITheme fantasy-ornate` under a 42-rule `LuauUIStyle` sheet
  parented to `PlayerGui`. The image *is* the button and the sheet is the authority.

### Instrument gain — captures are now exact, and three probe blind spots are closed

- **Magenta calibration.** Per preset the driver photographs one full-viewport magenta
  `Frame` in a top-most `ScreenGui`; its bbox **is** the emulated screen's rect in
  capture pixels, aspect-checked against the viewport the DataModel reported. Measured:
  `hd_1080` @1232×1067 → origin (36, 42), size 2404×2076, scale 1.9513 capture px per
  viewport px; `xbox` @1920×1078 → origin (36, 386), size 2414×1356, scale 1.2573
  (aspect 1.7801 vs 1.7811). No Studio chrome, no luminance guessing, and the overlay
  comes down before the row capture. A first attempt using a luminance bbox read
  Studio's own game-view scrollbars as content.
- **A zoom crop must add the 58 px GUI inset.** The LuauUI `ScreenGui` sits below
  `coreSafeInsets`, so a node's `AbsolutePosition` y is 58 less than its physical y,
  while the calibration frame (`IgnoreGuiInset = true`) measures physical space. The
  first plaque diagnostic was mis-framed by exactly that and was re-taken.
- **The asset-decode guard was blind.** Classifying image-bearing nodes by `.Image`
  reports **0** under a package with 139 layer instances, because a plain read under a
  sheet is `""`. It now classifies by `GetStyled("Image")` and then checks `IsLoaded`.
- **Focus visuals are not `GuiObject`s.** The first probe only tested instance names
  inside its GuiObject branch, so it reported zero focus visuals on every row —
  including flat, where the ring is a `UIStroke`.
- **An adapter-owned clip window is *meant* to overflow.** `LuauUIBarWindow` exists to
  clip art deliberately wider than itself; a naive containment check called the ornate
  bar fill a 312 px bleed. Only a LuauUI *node's* clip host can bleed.
- **`contentUnderBarBy` only counts when the bar is shown.** `src/layout/solver.luau`
  reserves the scrollbar's thickness off the cross axis only when content overflows —
  exactly when the engine draws it — so on rows whose canvas equals the window content
  legitimately reaches the full width.

### Honesty debt this round leaves behind

> **SUPERSEDED BY DRIVE #4 (2026-07-26).** Take 7 replaced **13** of the nineteen at the
> final stamp `7d681bed-1726959`, so the shas in this table are history. The current
> inventory is in "Final matrix drive #4" and in `rs-a16-matrix.json`
> (`capturesWrittenThisRound`). Six PNGs — the art-bearing phone rows and the two
> phone-portrait pair rows — are still take-5 images.

Three of the nineteen canonical `RS-A16_*` PNGs were **replaced** before the defects
were found, and there is no VCS in this directory to restore the originals:

| File | new sha256 | state |
|---|---|---|
| `RS-A16_adaptive_desktop-standard_studio-neutral.png` | `9c15772a325b2634` | post-fix, measured clean |
| `RS-A16_adaptive_console-ten-foot_studio-neutral.png` | `27e2ba51357bda19` | post-fix, measured clean |
| `RS-A16_adaptive_desktop-standard_fantasy-ornate.png` | `9a1b5d0288cfb324` | post-fix, **contains RS-A16-D2** |

The other sixteen are still the 2026-07-25 pre-director-round images. Three current
rows plus sixteen stale rows is **not** a matrix and nothing here is claimed as one;
`artifacts/theme-packages-and-skinning/b-a13-matrix.json` still stands unsuperseded.
The re-drive must replace all nineteen in **one** pass and record the supersession,
which is what closes this.

---

## Final matrix drive #3 (2026-07-26, take 6) — STOPPED at row 1 of 19: `FAIL_PRODUCT` again

Driven at the post-D2/D3 stamp **`1de8a15c-1722217`** (library 0.7.0, suite 1724,
Studio 0.731.0.7310942). Full trace: `rs-a16-matrix.json`. Source tree untouched;
writes limited to `artifacts/rich-skinning-v2/`.

Clean inject at the final stamp: 120 nodes, **0 created / 0 patched / 104 unchanged /
0 failures** — zero drift. Preflight PASSED in full: stamp identical across the sync
manifest, the workspace attribute and every scenario report in all four Play sessions;
viewport non-1×1; **one** LuauUI `ScreenGui` mounted; log boundary clean of *any*
LuauUI warning or error; a canary capture cross-checked against the live frame (it
shows the stepper at 7 immediately after the canary moved it 6→7, so not a stale
buffer); and a canary INPUT pairing a real `InputBegan` `MouseButton1` `Begin` at
(388,87) `gameProcessed = true` with its application effect (stepper 6 → 7).

### D1, D1b, D2 and D3 — all independently re-confirmed fixed

By a driver that wrote none of them:

| Defect | Independent read at `1de8a15c-1722217` |
|---|---|
| **D1** (a losing candidate's hit expanders cover the winner) | exactly **2** `LuauUIHitExpander`s in the whole tree, both `Visible`, both on VISIBLE sub-floor toolbar buttons (`[1177,55,44,46]`, `[620,55,44,46]`); the hidden `/Actions/ActionsColumn`'s three are **gone**; `GetGuiObjectsAtPosition` 9 px inside the visible **Save changes** returns `/Actions/ActionsRow/Save` **first** |
| **D1b** (expanders placed against a stale clip origin) | a solved-vs-actual reconstruction — declared `UDim2` + parent box + `UIPadding` + `AnchorPoint` + `CanvasPosition` vs `AbsolutePosition`/`AbsoluteSize` — found **0 mismatches over 100 checked visible nodes** |
| **D2** (a plaque's `overhang` painted but never reserved) | under fantasy-ornate the full-tree chrome sweep found **0** neighbour overlaps. Take 5's 22 — the 792 px² plaque-over-"Save changes" *and* the 21 corner-ornament 84 px² hangs — are all gone |
| **D3** (pixel-quest's fill solves to zero height) | the bar track resolves **473×28** with a **160×12** `LuauUIBarWindow` fill window and loaded art. **0** zero-area value boxes on any driven row |

### RS-A16-D4 — the built-in default paints no value controls at all

**MAJOR, user-visible, `studio-neutral` (i.e. every unskinned screen).** Posture:
native StyleSheet paint authority enabled (`LuauUI_NativeStyle = true`, which is the
posture this whole stage is built on and is persisted in the place). Reproduces with
**no theme package installed** — which is exactly what five of the nineteen rows are.

The four `chrome_slots.OWN_PAINT_SLOTS` value-control surfaces — `sliderTrack`,
`sliderThumb`, `barTrack`, `barFill` — are selected by **no rule in any live sheet**,
so `Frame default` (`BackgroundTransparency = 1`) wins and they paint nothing.

| Measured live at `hd_1080` 1232×1067 | |
|---|---|
| `Slot …` rules in the live `LuauUIStyle` sheet | **0** (of 42 rules total) |
| `.luau-slot-sliderTrack` `[95,139,457,6]` | styled `BackgroundTransparency` = **1** |
| `.luau-slot-sliderThumb` `[270,132,20,20]` | styled `BackgroundTransparency` = **1** |
| `.luau-slot-barTrack` `[683,116,503,6]` | styled `BackgroundTransparency` = **1** |
| `.luau-slot-barFill` `[683,116,176,6]` | styled `BackgroundTransparency` = **1** |
| art children on any of the four | **none** — `studio-neutral`'s census is 0 decorations / 0 layers |

So: no own-paint rule + no art + `Frame default` transparent = an invisible control.
**What the player gets:** the **Download** row shows a label, `0.35`, and *nothing*
between them — the bar is pixel-identical at 0 % and 100 %, so it cannot communicate
anything at all; the **Brightness** row shows its accent fill with **no rail** behind
or after it and **no thumb**, so there is no grip to aim at and no indication of the
track's extent.

**Viewport-independent.** Re-measured at `xbox` 1920×1078 in the same session: still 0
`Slot` rules, still transparency 1 on all four. A missing rule is not geometry, so all
five `studio-neutral` rows carry it identically.

**The control that makes it a defect rather than a design.** Same fixture, same
viewport, same theme, `LuauUI_NativeStyle` toggled to `false` and the session
re-booted: `barTrack` `#292d3a` @ 0, `barFill` `#2c62d2` @ 0, `sliderTrack` `#292d3a`
@ 0, `sliderThumb` `#1c1f28` @ 0, `sliderFill` `#2c62d2` @ 0 — the adapter's bespoke
path (`src/client/screen_chrome.luau:140–141`) paints all five opaque and correct. The
intended appearance is therefore not in dispute; the StyleSheet posture is missing it.
Capture #30 is the two postures side by side.

**Root cause.** `src/tokens/sheet_model.luau` has two builders and only one emits the
family. `sheet_model.buildPackage` (line 1001) loops `chrome_slots.OWN_PAINT_SLOTS`
(`chrome_slots.luau:420`) at **line 1414** and emits `Slot — <slot>`,
`Slot — <slot> corner` and `Slot — <slot> outline`, keyed on the hint tag, drawing
colour from `SLOT_FILL_TOKEN` (`barTrack → $Control`, `barFill → $Accent`,
`sliderTrack → $Control`, `sliderThumb → $SurfaceStrong`). The BASE seed
`sheet_model.build` (line 357, rules from line 392) emits **none** of them, and does
emit `Frame default → BackgroundTransparency 1`. Under the built-in default no package
sheet is built, so the 12 rules do not exist and the four hint tags select nothing.

**The code already states the requirement it misses**, in the comment directly above
the emitting loop (lines 1412–1413): *"Emitted for every package including the flat
ones — a value control has to be visible under Studio Neutral too."* The one path
where it is not emitted is Studio Neutral. `screen_chrome.luau:1154–1155` makes the
same assumption from the other side: *"A FLAT bar builds NOTHING here: with no
`barFill` recipe the fill node's own `luau-slot-barFill` rules paint it solid, which is
what a progress bar is."* Those rules are what is absent.

This is the **emit-without-application** family again — D2 published an `overhang`
nothing reserved, director defect 7 accepted `contentInsets` nothing applied, Step 3
accepted a container `align` nothing honoured. Here the adapter emits the hint TAG on
every package including none, and the rule that gives the tag meaning is emitted on a
different path (`docs/lessons/conditional-emission-is-a-tag-with-no-rule.md`).

**Why nothing caught it.** Every earlier rich-skinning-v2 row installed a package
before measuring, and installing **any** package — including the flat
`classic_desktop` — creates the 12 rules (measured: `installFlat` → 12 `Slot` rules,
all four slots at styled transparency **0**). RS-A5's "flat" bar capture is
`classic_desktop`, *not* the built-in default. And the headless twin
`tests/theme_matrix_audit.spec.luau` cannot see this by construction: it says plainly
that it "cannot see paint", and the bar's box is a healthy 503×6, so (a)–(d) all pass
at 1724. Take 5's flat rows measured text, clipping, geometry and mount identity, and
never asked whether a value control was *visible*.

### Scope across the matrix, measured live per package

| Package | `Slot` rules | The four slots | Row verdict |
|---|---|---|---|
| `studio-neutral` (no package) | **0** | all four invisible | **TAINTED — 5 rows** |
| `classic_desktop` | 12 | all four painted by rule (transparency 0) | clean |
| `fantasy_ornate` | 12 | all four transparent **but** each carries a **loaded** art child (`LuauUIChrome` on the slider track and thumb and the bar track, plus `LuauUIBarCapStart`/`CapEnd`/`BarCenter`) — the art *is* the element, so transparent is correct | clean |
| `pixel_quest` | 12 | slider painted by rule; bar skinned by loaded art over a 473×28 track | clean |
| `glossy_touch` | 12 | slider painted by rule; bar skinned by art | clean |
| `compact_pointer` | 12 | slider painted by rule; bar skinned by art | clean |

So **5 of the 19 rows** would have stored a picture of an unusable progress bar and a
railless, thumbless slider; the other 14 are unaffected by this defect.

**Smallest fix.** Emit the four `Slot — <slot>` families from `sheet_model.build`'s
base seed as well, from the same `SLOT_FILL_TOKEN` map, so a value control's flat
appearance is one decision instead of one reachable down only one of two paths. Pure
and deterministic, so red-first: a spec over the BASE model asserting a rule exists per
hint tag, plus a Studio read of the four styled transparencies under no package. Worth
adding to the headless twin too — it cannot see pixels, but it **can** assert that
every hint tag the adapter emits is selected by at least one rule in the model that
will be live, which is exactly what would have caught this at suite speed.

---

## RS-A16-D4 — **FIXED** (2026-07-26, implementer round; stamp `7d681bed-1726959`)

Suite **1724 → 1741**, library 0.7.0. Fixed exactly as the diagnosis proposed, plus
the structural guard it asked for.

### The fix: ONE emitter, both builders

`src/tokens/sheet_model.luau` no longer has a copy of this family inside
`buildPackage`. Two file-scope functions above **both** builders own it:

- **`emitOwnSlotPaint(slot, metrics, hairlineT, hairlineW, emit, fromMetric?)`** —
  the three rules that make one value slot visible without art: `Slot — <slot>`
  (`.luau-slot-<slot>` → `BackgroundColor3 = SLOT_FILL_TOKEN[slot]`,
  `BackgroundTransparency = 0`), `Slot — <slot> corner` (phantom `::UICorner`;
  `0.5` scale for the round thumb, else `radii.control`) and `Slot — <slot> outline`
  (phantom `::UIStroke` at the sheet's own hairline). `emit` is a callback so the
  caller decides the ordered group; `fromMetric` is optional because only the package
  builder can push a live metric edit onto a baked literal.
- **`emitSlotSuppression(slot, emit)`** — the mirror three (`Skinned — <slot>` /
  ` corner` / ` outline`), which the base seed now **pre-arms** for the same reason a
  flat package does: `planFor(nil, slot, { image = … })` returns a plan, so a Slider's
  rung-2 `thumbImage` skins a node with **no package installed at all**.

`SLOT_FILL_TOKEN`, `SLOT_ROUND` and `slotRadius` moved above `build` so one emitter can
reach them. `buildPackage` now calls both functions (its `emitSuppression` keeps its
dedupe and its census `+= 3`); `build` calls them at the matching cascade positions —
paint after the surface fills and before `Scrim backdrop`/`Grip focus`, suppression
after the role rules and before `Control — hover`. Base rules stay legacy-shaped (no
`group`, no `priority`; the materializer derives them), so nothing else about the base
sheet moved.

### Red-first, proven by mutation

Ten specs go **red** when the two base-seed loops are stubbed out and green with them
(measured both ways this round, not asserted):

| Where | What |
|---|---|
| `tests/sheet_model.spec.luau` (8 new) | the base model selects all four slots at transparency 0 with the right token; the token resolves to the exact colour the bespoke path writes; corner + hairline match the package path; the suppression pre-arm exists and `planFor(nil, …)` proves why; paint-before-suppression-before-states ordering; one rule per name; legacy rule shape; and **prop-for-prop equality of all 24 rules between `build` and `buildPackage(neutralPackage())`** — the guard against a second copy drifting |
| `tests/theme_matrix_audit.spec.luau` (7 new) | **(e)** for each of the nineteen canonical rows, every tag the row's own tree carries is selected by ≥1 rule in the sheet *that row runs* (base seed for the five flat rows, package model for the fourteen); the flat rows are asserted to really run the base seed; plus a **sweep of the whole `classifyTags` vocabulary** against the base sheet and all four reference-package sheets |

The vocabulary sweep is the class guard the diagnosis asked for. It enumerates from
`classifyTags` itself — a new tag lands in the required set by construction — and the
only exemptions are tags that can *only* land on a node a package decorated, each one's
reachability **computed** from the same `chrome_slots` functions the adapter uses
(`hasOwnPaint`/`planFor`/`layerPlanFor` for `luau-skinned-<slot>`, a layered `field`
recipe for `luau-chrome-yield`, toggle art for `luau-toggle-on`, an `error` variant for
`luau-state-error`), never from a list of package names. A companion spec asserts the
corpus really does apply every exempted tag somewhere, so an exemption cannot hide a
rule nobody wrote.

Under the mutation, (e) names the defect in the driver's own words on all five flat
rows, e.g. `desktop-standard/studio-neutral: /AdaptiveScreen/BodyScroll/Body/Hud/`
`Download/Bar carries the tag 'luau-slot-barTrack' that NO rule in the live sheet`
`selects`.

### Live proof — studio-neutral LEADING a fresh session

Preflight: clean inject at the new stamp (120 nodes, 0 created / **1 patched** /
103 unchanged / 0 failures), `LuauUI_SourceStamp = 7d681bed-1726959` identical in the
sync manifest, the workspace attribute and the scenario report; `LuauUI_NativeStyle =
true`; viewport 1232×1067 (non-1×1); **one** LuauUI `ScreenGui`; scenario report
`packageId = studio-neutral` (no package had been installed in this session — the
driver's truth that `api.reset()` does not restore the built-in default is respected by
leading with it); log boundary clean of any LuauUI warning or error.

The live `LuauUIStyle` sheet: **66 rules** (was 42), of which **12 `Slot …`** and
**12 `Skinned …`** — the family exists in the sheet that is actually linked.

| Slot | live rect | styled `BackgroundTransparency` | styled `BackgroundColor3` | plain read | art |
|---|---|---|---|---|---|
| `.luau-slot-sliderTrack` | `[95,139,457,6]` | **0** (was 1) | `#292d3a` = `$Control` | `#a3a2a5` | none |
| `.luau-slot-sliderThumb` | `[270,132,20,20]` | **0** (was 1) | `#1c1f28` = `$SurfaceStrong` | `#a3a2a5` | none |
| `.luau-slot-barTrack` | `[683,116,503,6]` | **0** (was 1) | `#292d3a` = `$Control` | `#a3a2a5` | none |
| `.luau-slot-barFill` | `[683,116,176,6]` | **0** (was 1) | `#2c62d2` = `$Accent` | `#a3a2a5` | none |

Those four colours are byte-identical to the bespoke control experiment
(`screen_chrome.luau:140–141`), and the plain-vs-`GetStyled` disagreement
(`#a3a2a5` — the untouched Roblox `Frame` default, i.e. never explicitly written) proves
the paint is the SHEET's, not a bespoke write. Every rect is unchanged from the take-6
measurement: this fix moves paint, not geometry.

**The bar communicates a value again.** `barSweep` over the value fixture, styled reads
after settle: at **0 %** the fill is `0×6` on a `1190×6` track, at **35 %** it is
`417×6` (1190 × 0.35 = 416.5), at **100 %** `1190×6` — track opaque `#292d3a`, fill
opaque `#2c62d2` at every stop. Before the fix both were transparency 1, which is what
made 0 % and 100 % pixel-identical.

**Capture:** `captures/RS-A16-D4_fixed_desktop_studio-neutral.png` (sha256-16
`8a2dceb4da5bb0bc`), 2404×2076 = exactly the emulated 1232×1067 screen, cropped from a
fresh magenta-bbox calibration (bbox size `2404×2076`, scale 1.9513 — **byte-identical
to take 5's and take 6's**, so the Studio window layout has not moved), overlay
destroyed before the real frame, untinted, CoreGui PlayerList/Chat off. The Download row
now shows a dark trough with a blue 35 % fill; the Brightness row shows the accent fill,
the rail continuing past the thumb, and the round thumb.

### Per-package regression sweep, same session, after the flat reads

| Posture | The four slots | Verdict |
|---|---|---|
| `studio-neutral` (base seed, 66 rules / 12 `Slot` / 12 `Skinned`) | all four styled transparency **0** at the tokens above, no `luau-skinned-*` tag, no art | **the fix** |
| `classic_desktop` (`installFlat`) | all four painted by rule at transparency **0** in its own palette (`#e2dfd8` track / `#10367a` fill / `#f0eee8` thumb), no skinned tag, no art | unchanged |
| `fantasy_ornate` (`installOrnate`) | all four carry `luau-skinned-<slot>` and styled transparency **1**, each with **loaded** art (`LuauUIChrome` on rail/thumb/track + `LuauUIBarCapStart`/`CapEnd`/`BarCenter`) | suppression still wins where art exists |

**Why there is no cross-sheet hazard:** installing a package REPOINTS
`LuauUIStyleLink.StyleSheet` at `LuauUITheme <id>` (measured: the link pointed at
`LuauUITheme fantasy-ornate`, 289 rules). The base `LuauUIStyle` stays in `PlayerGui`
but is no longer linked, so the base seed's new rules are live only under the built-in
default — structurally, not by luck.

### End sweep at this stamp

Library suite **1741 passed** (floor raised in `gate_manifest.luau`); RascalRally suite
**2404 passed**; `check_flat_baseline` **PASS** — 1506 flat nodes, the same 6 prop
deltas / 4 new nodes / 1 added prop key, **0 rect / 0 hit-rect / 0 class changes** (the
FakeTarget sees no rules, so a base sheet gaining 24 of them cannot move the flat dump,
and it did not); `check_docs` PASS; `check_prop_parity` PASS; `check_registration` PASS
(85 specs registered); `check_boundary` PASS (66 files); `check_theme_drift` PASS;
`bench` PASS.

### What row 1 otherwise proved

Recorded in `rs-a16-matrix.json` as `rowsMeasuredNotClaimed`, never as a row: 111
nodes / 107 visible / 39 text; **0** unfit text; **0** clip bleed; **0** outside the
canvas; **0** solved-vs-actual mismatches over 100 checked; **0** chrome instances to
overlap; **0** assets unloaded; the focus visual a real enabled `UIStroke` on the
focused control (correct for a package with no art host); "Play" on one line; and style
authority proven by plain-vs-`GetStyled` disagreement on the Save button
(`BackgroundColor3` `#a3a2a5` — the untouched Roblox `Frame` default, i.e. never
explicitly written — vs `#292d3a`; `TextColor3` `#1b2a35` vs `#eceff5`) through
`LuauUIStyleLink` into the 42-rule `LuauUIStyle` sheet with `Theme Dark` / `Theme
Light` children and a `StyleDerive`. Three nodes report a 0×0 box at the scroll origin
(`/Advanced/Header/CaretOpen`, `/CaretShut`, `/Advanced/Content`) — structural `When`
regions, which the renderer treats as transparent containers and never lays out, the
same class the headless audit excludes; their painted children carry real boxes.
Benign, recorded so nobody rediscovers it.

### Instrument notes from this round

- take 5's **magenta-bbox calibration re-verified byte-identical** (`hd_1080` → offset
  (36,42), size 2404×2076), so the Studio window layout has not moved;
- the 58 px GUI-inset rule for zoom crops **re-measured directly**: an
  `IgnoreGuiInset = true` frame reports `AbsolutePosition.Y = −58` while the LuauUI
  ScreenGui's nodes start at y 0, so `capture_y = originY + (absY + 58) × scaleY`;
- **`api.reset()` does NOT restore the built-in default.** After `installFlat` +
  `reset()` the snapshot still reported `classic-desktop` with 12 `Slot` rules live:
  the package's theme sheet survives a scenario rebuild. So a `studio-neutral` row can
  only be driven in a Play session where no package has yet been installed — the flat
  rows must **lead** their session. Measured, not assumed;
- the calibration overlay must be **destroyed before any `GetGuiObjectsAtPosition`
  read**; the round's first hit-order read reported `Mag` ahead of the button, which
  was the instrument, not a defect;
- CoreGui **PlayerList and Chat are now disabled for captures** — the player list drew
  a panel over the toolbar's overflow button in the top-right of every desktop capture,
  which a director could mistake for a layout defect. The 58 px topbar stays, because
  the framework really reserves it.

### Honesty ledger for this round

**Zero** canonical `RS-A16_*` PNGs were touched **by drive #3**, so it left no new
honesty debt (drive #4 then replaced thirteen of them — see its own ledger). The standing
debt from drive #2 (three replaced files) is unchanged. Two new diagnostics were added,
both untinted product states: `RS-A16-BLOCKED_value-controls-unpainted_desktop-standard_studio-neutral.png`
(`c8db8907c97e22cc`) and `RS-A16-BLOCKED_value-controls-unpainted-vs-bespoke_desktop-standard_studio-neutral.png`
(`38630471d6a7ce95`). Nothing is superseded; `b-a13-matrix.json` still stands.

---

## Final matrix drive #5 (2026-07-26, take 8) — ALL 19 ROWS CLEAN: RS-A16 is `PASS_AUTOMATED`

Driven at the post-D5-fix stamp **`66599d58-1744436`** (library 0.7.0, suite 1757, Studio
0.731.0.7310942). Full trace: `rs-a16-matrix.json`; every row's complete probe output is a real
file in `rows/`. Source tree untouched; writes limited to `artifacts/rich-skinning-v2/`.

**Frozen tree, measured.** The injector reported **0 created / 0 patched / 104 unchanged / 0
failed** with an empty drift list — and because it writes `.Source` only when the served file
differs, that IS the byte comparison of all 104 script bodies against disk. The stamp read
identically from the sync manifest, the workspace attribute and every scenario report in all
three Play sessions. `tools/test.sh 1757` passed against that tree immediately before the drive.

**Three sessions, not two, and every one of them booted fresh with the flat rows leading.**
Session A on `hd_1080` drove the 8 pointer/gamepad rows; session B1 on `samsung_galaxy_a06`
Portrait drove the three `studio-neutral` rows plus both tablet package rows; session B2 (a fresh
boot forced by `RS-A16-E1`) drove the six remaining phone art/pair rows. All three assert the same
stamp and the same tree, all three preflights PASSED in full including a canary input that paired
a **raw** engine event with its application effect, and all three logs contain **zero** LuauUI
warnings or errors.

### The nineteen rows

| Row | preset | viewport | live sheet (rules) | capture | sha | `byReason.clipped` |
|---|---|---|---|---|---|---|
| `desktop-standard/studio-neutral` | hd_1080 + SetResolutionAsync(1233,1067) | 1232×1067 | LuauUIStyle (66) | `RS-A16_adaptive_desktop-standard_studio-neutral.png` | `cf3658fa06792a7a` | — |
| `desktop-standard/fantasy-ornate` | hd_1080 + SetResolutionAsync(1233,1067) | 1232×1067 | LuauUITheme fantasy-ornate (303) | `RS-A16_adaptive_desktop-standard_fantasy-ornate.png` | `49297ba9ccd0f2ea` | — |
| `desktop-standard/pixel-quest` | hd_1080 + SetResolutionAsync(1233,1067) | 1232×1067 | LuauUITheme pixel-quest (217) | `RS-A16_adaptive_desktop-standard_pixel-quest.png` | `e1c20a74773128a2` | — |
| `desktop-standard/glossy-touch` | hd_1080 + SetResolutionAsync(1233,1067) | 1232×1067 | LuauUITheme glossy-touch (199) | `RS-A16_pair_desktop-standard_glossy-touch.png` | `b4f33aa4ec94d138` | — |
| `desktop-standard/compact-pointer` | hd_1080 + SetResolutionAsync(1233,1067) | 1232×1067 | LuauUITheme compact-pointer (193) | `RS-A16_pair_desktop-standard_compact-pointer.png` | `b02aa24bbe9eab34` | — |
| `console-ten-foot/studio-neutral` | xbox | 1920×1078 | LuauUIStyle (66) | `RS-A16_adaptive_console-ten-foot_studio-neutral.png` | `df7d1df8f3d09453` | — |
| `console-ten-foot/fantasy-ornate` | xbox | 1920×1078 | LuauUITheme fantasy-ornate (303) | `RS-A16_adaptive_console-ten-foot_fantasy-ornate.png` | `3db54ca5bbf20057` | — |
| `console-ten-foot/pixel-quest` | xbox | 1920×1078 | LuauUITheme pixel-quest (217) | `RS-A16_adaptive_console-ten-foot_pixel-quest.png` | `41f0b355e7109df8` | — |
| `tablet-landscape/studio-neutral` | ipad_9th_generation LandscapeLeft | 1079×809 | LuauUIStyle (66) | `RS-A16_adaptive_tablet-landscape_studio-neutral.png` | `dba685cbb6e80e30` | — |
| `tablet-landscape/fantasy-ornate` | ipad_9th_generation LandscapeLeft | 1079×809 | LuauUITheme fantasy-ornate (303) | `RS-A16_adaptive_tablet-landscape_fantasy-ornate.png` | `20a48449d41d08a4` | — |
| `tablet-landscape/pixel-quest` | ipad_9th_generation LandscapeLeft | 1079×809 | LuauUITheme pixel-quest (217) | `RS-A16_adaptive_tablet-landscape_pixel-quest.png` | `f71cde63c6c361ab` | — |
| `compact-phone-portrait/studio-neutral` | samsung_galaxy_a06 Portrait | 359×718 | LuauUIStyle (66) | `RS-A16_adaptive_compact-phone-portrait_studio-neutral.png` | `d0639a687092f8a9` | — |
| `compact-phone-portrait/fantasy-ornate` | samsung_galaxy_a06 Portrait | 359×718 | LuauUITheme fantasy-ornate (303) | `RS-A16_adaptive_compact-phone-portrait_fantasy-ornate.png` | `e3aa9332aaec60a1` | 105 |
| `compact-phone-portrait/pixel-quest` | samsung_galaxy_a06 Portrait | 359×718 | LuauUITheme pixel-quest (217) | `RS-A16_adaptive_compact-phone-portrait_pixel-quest.png` | `b4a20cc767eb3e2e` | 26 |
| `compact-phone-portrait/glossy-touch` | samsung_galaxy_a06 Portrait | 359×718 | LuauUITheme glossy-touch (199) | `RS-A16_pair_compact-phone-portrait_glossy-touch.png` | `ae43d8914015dd70` | 20 |
| `compact-phone-portrait/compact-pointer` | samsung_galaxy_a06 Portrait | 359×718 | LuauUITheme compact-pointer (193) | `RS-A16_pair_compact-phone-portrait_compact-pointer.png` | `76a791264442fe05` | 16 |
| `compact-phone-landscape/studio-neutral` | samsung_galaxy_a06 LandscapeLeft | 705×338 | LuauUIStyle (66) | `RS-A16_adaptive_compact-phone-landscape_studio-neutral.png` | `2e8f1d168824dbb9` | — |
| `compact-phone-landscape/fantasy-ornate` | samsung_galaxy_a06 LandscapeLeft | 705×338 | LuauUITheme fantasy-ornate (303) | `RS-A16_adaptive_compact-phone-landscape_fantasy-ornate.png` | `e54d756d9dd3d6ca` | 99 |
| `compact-phone-landscape/pixel-quest` | samsung_galaxy_a06 LandscapeLeft | 705×338 | LuauUITheme pixel-quest (217) | `RS-A16_adaptive_compact-phone-landscape_pixel-quest.png` | `62d16b8d2a735746` | 38 |

Every row: `textUnfit = 0` over 39 text nodes · 0 solved-vs-actual mismatches over 100 checked
visible nodes · 0 clip bleed · 0 nodes outside the canvas · 0 zero-area value or painted boxes ·
0 flow-neighbour overlaps · the visible `Save` returned FIRST by `GetGuiObjectsAtPosition` ·
exactly 2 hit expanders under flat and 0 under every package, 0 bad anywhere · a real enabled
focus visual · plain-vs-`GetStyled` disagreement on every probed control · 0 uncovered `luau-*`
tags · 0 undecoded ON-WINDOW images after a bounded retry that never had to wait · and the D5
signature clean.

### D1, D1b, D2, D3, D4 and D5 — all independently re-confirmed fixed

| Defect | Independent read at `66599d58-1744436` |
|---|---|
| **D1 / D1b** (hit-expander ownership and placement) | exactly **2** `LuauUIHitExpander`s under the flat package on all five flat rows, both `Visible`, both hosted by visible nodes; **0** under every package; **0** bad anywhere. Hit order returns the visible **Save** first on **all 19** rows and all five form factors; **0** solved-vs-actual mismatches over 100 checked nodes **per row** |
| **D2** (plaque `overhang` reserved) | **0** flow-neighbour overlaps on all 19 rows, including five fantasy-ornate rows at five viewports |
| **D3** (pixel-quest's bar fill) | **0** zero-area value displays on any row; the bar resolves with loaded art and a real fill window at all five viewports |
| **D4** (the built-in default's value controls) | all four `OWN_PAINT_SLOTS` surfaces at styled `BackgroundTransparency` 0 under the built-in default on **all five** `studio-neutral` rows; base sheet 66 rules / 12 `Slot` / 12 `Skinned`; trough, fill, rail and thumb in the pixels of five captures |
| **D5** (art clipped away read as art that failed) | **the headline.** `undecodedJudgeable = 0`, `failedAssets = []`, `fallbackSlots = []`, `luau-chrome-fallback` 0, `luau-chrome-mute` 0 on **all 19** rows — and on the phone rows read twice, at +2.5 s and again past the 5 s grace deadline — while 16–105 instances are spared as `clipped`. The two pictures that prove it: `compact-phone-landscape/fantasy-ornate` draws the ornate **crown** mid-bar where take 7 had a flat gold slab, and `compact-phone-portrait/pixel-quest` keeps pixel art on **every** button plate where take 7 flipped the whole `control` slot flat |

### `RS-A16-E1` — the harness leaks its theme controller across `reset()` (`FAIL_ENVIRONMENT`)

Not a product defect, and worth stating precisely because it looked exactly like one for the
length of one row.

`examples/gallery/scenarios/theme_authoring.luau`'s `dispose` releases its probe screens and the
fixture but **never uninstalls `installed.controller`**. So `api.reset()` leaves a live theme
controller in the environment while the scenario forgets it owns one, and the next install takes
the `tc.install(...)` branch again. The library refuses — correctly, and with the whole diagnosis
in the message:

> `theme_controller.install: this environment already has a live theme controller (package 'pixel-quest', theme 'Quest'), and the ThemeSnapshot rides the single 'themeMetrics' fact — the two would overwrite each other. Uninstall that controller first, or give this target its own environment. Nothing was installed and the environment is unchanged`

The last sentence is true *of the controller*. The scenario then changes the environment anyway:
`commit()` records the refusal as the **string** `paintController = "error:…"` and still commits
the decoration half (`themeChrome.setPackage`) and the metric half (`themes.resolve` +
`env:set("themeMetrics")`). Measured result on `compact-phone-landscape/fantasy-ornate`: 154
ornate decorations and 53 ornate tag kinds live under a `LuauUITheme pixel-quest` sheet — 20
uncovered tags, **127 of 155** art instances with reason `noSource` (the pixel sheet has no rule
that sets an `Image` for ornate's slots), `sliderTrack` and `sliderThumb` **UNPAINTED**, 8 unfit
text nodes, and three different answers to "which package is live" (the scenario record said
`neutral`, the snapshot said `fantasy-ornate`, the paint authority said `pixel-quest`).

**It cannot heal in-session:** three further installs (ornate, glossy, ornate) and another reset
all left the live link on `LuauUITheme pixel-quest`.

**Why it is not a product risk:** a game installs the controller once per environment and never
resets a scenario, and the controller exposes the uninstall seam the message names. It takes a
harness that tears a scenario down while leaving its controller installed.

**Recovery, and the hardening that came with it:** the session was re-booted (a fresh environment
has no controller) and the six remaining rows were driven with no `reset()` after any install.
The drive now asserts `paintController == "controller"` **and** the expected live sheet name on
every install before a row is measured, and records both per row — which is why all nineteen rows
carry a verified live sheet in the table above. The five rows already claimed from session B1 are
unaffected and their traces prove it: `LuauUIStyle` (66) on the flat rows, `LuauUITheme
fantasy-ornate` (303) and `LuauUITheme pixel-quest` (217) on the tablet rows.

**Owed fix (harness, not library):** `theme_authoring`'s `dispose` should uninstall
`installed.controller`, and `commit()` should treat a paint-controller error as a **failed**
install rather than a string in the result — a half-applied package is worse than a rejected one.
Cheap rider: the runner's `reset()` could assert that no theme controller survives teardown.

### New instrument notes from this round

- **The asset-decode guard is now ON-WINDOW only**, which is the honest twin of the D5 fix: an
  image is judged for decode only when its rect survives the engine's real clip chain (every
  `ClipsDescendants` ancestor, including `LuauUIBarWindow`/`LuauUICanvasMask` and any ScrollView)
  intersected with the canvas. Off-window art is counted (`imagesClippedAway`) and never waited on
  or failed. Take 7 judged every `Visible` image, which is why a real phone preset made 98 of 140
  nodes look broken. The same rule spares a value slot whose own box is off-window (`offWindow`
  instead of `UNPAINTED`).
- **The D5 signature is read from the framework's own instrument** (`adapter.chromeArtJudgement`
  via the `artJudgement` step) and paired with independent `CollectionService` counts of both
  fallback tags. That pair — `undecodedJudgeable` 0 with a large `byReason.clipped` — is the
  signature, present or gone, in one call.
- **Calibration reproduced.** Three markers per preset, solved per axis, residuals 0.1–0.9 px.
  Four of the five transforms are byte-identical to take 7's; the desktop fit differs only in `sy`
  (1.9513 against take 7's 1.9456), and this round's is the provably uniform one (`sx` and `sy`
  within 0.005 %, 0.2 px residual), so the desktop captures are 2404×2082 rather than 2404×2076 —
  six more rows of the same emulated screen.
- **`SetDeviceAsync` clears a prior `SetResolutionAsync` override**, so `hd_1080`'s 1233×1067 was
  re-applied on every return to that preset. `SetOrientationAsync` still errors on a desktop
  preset.
- **A runtime-created `Script` in `ServerScriptService` and `LocalScript` in `PlayerGui` both run**
  in a Play session, which is what lets the trace path (client → `RemoteEvent` → server → local
  sink) and the canary recorder exist without touching the source tree.

### Honesty ledger for this round

**All nineteen** canonical `RS-A16_*` PNGs replaced at the final stamp, each sha-pinned and paired
with a full trace; **zero** left from any earlier take. The take-5 and take-7 capture debt is
**cleared**, and `b-a13-matrix.json` is superseded as current matrix evidence. What is *not*
claimed: every viewport fact is the emulator's; the injected pointer is a real
`UserInputType.Touch` but not physical touch; `preferredTextSize = 1` and preferred text was not
swept; the rows are captured at the top of scroll, so they assert that off-window art is correctly
**spared**, not that it paints once scrolled in (the D5 fix round proved that with a real injected
scroll); and RS-P1..RS-P4 remain open by construction.

---

## Final matrix drive #4 (2026-07-26, take 7) — 13 of 19 rows CLEAN and captured, then STOPPED at row 14: `FAIL_PRODUCT`

> **SUPERSEDED BY DRIVE #5 (take 8) ABOVE.** Take 8 replaced all nineteen captures at the
> post-D5-fix stamp `66599d58-1744436`, so every sha in this section is history. Kept for the
> defect it found and the instrument truths it established.

Driven at the post-D4 stamp **`7d681bed-1726959`** (library 0.7.0, suite 1741, Studio
0.731.0.7310942). Full trace: `rs-a16-matrix.json`; every row's complete probe output is
a real file in `rows/`. Source tree untouched; writes limited to
`artifacts/rich-skinning-v2/`.

**Frozen tree, proven rather than asserted.** All 104 served script bodies were compared
byte-for-byte against the files on disk: 0 differences. The injector then reported
**0 created / 0 patched / 104 unchanged / 0 failed**, and the stamp read identically from
the sync manifest, the workspace attribute and every scenario report in both sessions.
`tools/test.sh 1741` passed against that tree immediately before the drive.

**Two sessions, each booted fresh, flat rows leading.** Session A booted on `hd_1080`
for the 8 pointer/gamepad rows; Session B booted on `samsung_galaxy_a06` in Portrait for
the touch rows, because `TouchEnabled`/`PreferredInput` are boot-time facts. Both
preflights PASSED in full, including a canary input that paired a **raw** engine event
with its application effect, and a canary capture cross-checked against MCP
`screen_capture` of the same frame. Zero LuauUI warnings or errors in either session's
log; the three errors that do appear are the driver's own and are named in the artifact.

### D1, D1b, D2, D3 and D4 — all independently re-confirmed fixed

| Defect | Independent read at `7d681bed-1726959` |
|---|---|
| **D1 / D1b** (hit-expander ownership and placement) | exactly **2** `LuauUIHitExpander`s under the flat package on all five flat rows, both `Visible`, both hosted by visible nodes; **0** under every package; **0** bad expanders anywhere. `GetGuiObjectsAtPosition` returns the visible **Save** button **first** on all 13 rows and all five form factors. A solved-vs-actual reconstruction found **0 mismatches over 100 checked visible nodes per row** |
| **D2** (plaque `overhang` now reserved) | **0** flow-neighbour overlaps on all 13 rows, including three fantasy-ornate rows at three viewports. The plaque clears "Save changes" at desktop, tablet and console |
| **D3** (pixel-quest's bar fill) | **0** zero-area value displays on any row; the bar resolves with loaded art and a real fill window at all three viewports it was driven at |
| **D4** (the built-in default's value controls) | **the headline.** All four `OWN_PAINT_SLOTS` surfaces read styled `BackgroundTransparency = 0` under the built-in default on **all five** `studio-neutral` rows — desktop, console, phone portrait, phone landscape, tablet. The live `LuauUIStyle` base sheet carries **66** rules of which **12 `Slot`** and **12 `Skinned`**. The trough, the fill, the rail and the thumb are in the pixels of five separate captures |

### The two assertions this stage owed, now live on every row

- **Value-control paint.** Each `OWN_PAINT` slot is either painted by rule at styled
  transparency 0 **or** skinned with **loaded** art — never unpainted. `studio-neutral`:
  all four painted by rule. `fantasy-ornate`: all four skinned with loaded art.
  `pixel-quest` / `glossy-touch` / `compact-pointer`: slider painted by rule, bar skinned.
- **Tag → rule coverage, live.** Every `luau-*` tag the live tree carries is selected by
  ≥1 rule in the sheet **that row runs**: 0 uncovered on all 13 rows — 15 tag kinds
  against the base seed's 66 rules on the flat rows, 53 against ornate's 289, 34 against
  pixel's 207, 29 against glossy's 190, 28 against compact-pointer's 184. This is the
  live twin of the headless audit's check (e), and it is what would have caught D4.

### RS-A16-D5 — art that is merely scrolled out of view is recorded as art that FAILED

**MAJOR, user-visible, package-independent, phone-only.** `screen_chrome.luau`'s
`chromeEffectivelyVisible` (line 675) already knows four ways an image is legitimately
undecodable, and says so in its own comments: a hidden ancestor (669–674), styled
`ImageTransparency ≥ 1` (676–683), zero area (694–699), an empty source (704–711). It
does not know the fifth — **the decoration is inside an ancestor whose
`ClipsDescendants` is true and lies entirely outside it.** A ScrollView's off-window
child is `Visible`, opaque, sized and sourced, so the guard returns true, the 5 s grace
timer (747) calls `setChromeAssetLoaded(asset, false)`, and `refreshChromeFallback` (652)
re-tags **every** live decoration of that shared asset — the on-screen ones included.

| Measured at `705×338` under fantasy-ornate | |
|---|---|
| image-bearing nodes reporting `IsLoaded = false` | **98 of 140** (88 lie entirely outside the canvas) |
| the framework's own `census.failedAssets` | `ornate_bar_center, ornate_edge_rail, ornate_panel_fill, ornate_panel_frame, ornate_plaque, ornate_selection_default, ornate_velvet_tile` |
| `census.fallbackSlots` | `panel, selection, badge, barCenter` |
| nodes carrying `luau-chrome-fallback` | **19** |
| scroll window vs canvas | 673×169 window, 673×507 canvas — two thirds off-window |

**It is visible without scrolling.** In the row's own top-of-scroll frame the Download
bar's centrepiece is a **flat rounded gold slab** where every desktop/tablet/console row
draws the ornate crown.

**It is package-independent.** `pixel-quest` at the same preset read `failedAssets = []`
at +2.5 s and `[pixel_blank, pixel_panel, pixel_plate_default]` with
`fallbackSlots = [panel, control, selection]` and 46 tagged nodes at +8 s — the delay is
the grace period, not immunity, and `control` flipping means every button plate goes
flat. `glossy-touch` at `359×718` portrait read
`failedAssets = [glossy_bar_fill, glossy_bar_track, glossy_stripe_tile]`,
`fallbackSlots = [barTrack, barFill]`.

**It cannot heal, and that was tested rather than assumed.** A real injected scroll
(`CanvasPosition` 0 → 338) decoded **65** of the undecoded nodes, but the 10 already
flipped stayed `IsLoaded = false` with styled `ImageTransparency = 1` and the
`luau-chrome-fallback` tag through two later re-reads. That is the trap the file
documents one clause up: the fallback rules set every layer of the stack to
`ImageTransparency = 1`, and a fully transparent image is never decoded, so `IsLoaded`
can never become true and the one-shot grace-deadline recovery has already passed.

**Why no earlier round saw it.** Take 5's phone rows were driven through the runner's
`setEnv` seam while the **engine** viewport stayed desktop-sized, so nothing was ever
clipped away. This round selected real presets, and it appeared on the first art-bearing
phone row. It is the fourth face of one rule the code states at line 669: *"the engine
never DECODES an image the player cannot see."*

**Smallest fix.** Add the clipped-away clause to `chromeEffectivelyVisible`, red-first
(a spec that puts a decoration outside a clipping host and asserts the timer does **not**
mark the asset failed). Two riders worth the same round: make the flip recoverable, since
the transparency clause makes a false positive permanent; and reconsider whether one
off-window consumer should be able to condemn a shared asset for every on-screen consumer
at all — the generalisation of the hidden-button case already fixed.

### RS-A16-D5 — FIXED (fix round 2026-07-26, stamp `66599d58-1744436`, suite 1757)

Two halves, both falsifiability-checked, both proven live at one asserted stamp. Full
trace: `rs-a16-d5-fix.json`. Lesson:
[`docs/lessons/engine-never-decodes-invisible-images.md`](../../docs/lessons/engine-never-decodes-invisible-images.md).

**1. The judgement gained its fifth clause, and the deadline DEFERS instead of
skipping.** `chrome_slots.judgeArt` is now the pure, clause-ordered decision over five
facts — attached, `Visible` up the whole chain, effective (styled) transparency,
effective source, and the art's rect against **one rect per ancestor whose
`ClipsDescendants` is true**. It returns the FIRST failing clause as `reason`
(`detached` / `hidden` / `transparent` / `muted` / `zeroArea` / `noSource` / `clipped`),
so a probe reports *why* art was spared. The adapter's only job is the one ancestor walk
that gathers those facts. And "not judgeable" is not "healthy": an unjudgeable
decoration re-arms the same grace window and is judged the moment it becomes judgeable,
because a skinned node's own plate is suppressed under its art — art that is never
judged would leave a genuinely broken package drawing nothing at all.

**2. The fallback's hide no longer silences the art it condemns.** The fill and the
hide were one rule on one tag, and `ImageTransparency = 1` is the engine's own "do not
decode" signal — so the framework's own fallback destroyed the only instrument that
could report the asset arriving late. `luau-chrome-fallback` now carries the FILL and
lands on every art instance of a fallen-back slot; the new `luau-chrome-mute` carries
the hide and lands on every instance **except the condemned asset's own UNDECODED art**.
Undecoded art draws nothing, so sparing it costs no pixels and keeps its `IsLoaded`
armed. Art the engine has already decoded is not an instrument (its signal cannot change
again), so it hides exactly as before — RS-DIR6-F1 unchanged. One decision,
`chrome_slots.isArtMuted(slot, assetName, artDecoded)`, is asked by all three flip sites
(nine-slice, layer stack, bar part), so they cannot drift.

**No oscillation, by construction.** The ledger the deadline can drive is a monotone
lattice: `unknown → failed → loaded`, with `loaded` terminal, because positive decode
evidence is durable — a picture the engine decoded once is resident for the session, so
later silence is never evidence that the *asset* is broken. Each asset moves at most
twice per installed package, so a decoration is tagged and untagged at most twice and a
flip/unflip cycle on the grace cadence is unreachable. The app's resource provider keeps
its unconditional edge in both directions; only the inference is latched.

| Live at `3aba44d7-1744426`, `samsung_galaxy_a06` Portrait (359×718), real preset, `envFrozen = false` (the ornate headline re-asserted identically at the final stamp `66599d58-1744436`, whose only delta is one type annotation) | fantasy-ornate | pixel-quest |
|---|---|---|
| `census.failedAssets` at +1 s / +9 s (past the 5 s deadline) | `[]` / `[]` | `[]` / `[]` |
| `census.fallbackSlots` | `[]` | `[]` |
| nodes tagged `luau-chrome-fallback` / `luau-chrome-mute` | 0 / 0 | 0 / 0 |
| art instances / judgeable / **undecodedJudgeable** | 155 / 35 / **0** | 55 / 31 / **0** |
| spared as `clipped` (the fifth face doing its job) | 105 | 21 |
| before the fix, same preset and mechanism | 7 assets, 4 slots, 19 tagged | 3 assets, 3 slots, 46 tagged — every button plate |

**The scroll, injected for real.** `moveTo(179,326)` + five `scrollDown` (one raw
`UserInputType.MouseWheel` observed), `CanvasPosition` 0 → 452: six named off-window
instances (`LuauUIChromeL2BottomLeft/Right` of `TbBack`, `TbPlay`, `TbMore`) moved from
`AbsolutePosition.y` 585 to 133 and every one re-read **by identity** as
`IsLoaded = true`, `ImageTransparency 0`, no fallback tag, no mute tag. `clipped` fell
105 → 10, `judgeable` rose 35 → 130, `undecodedJudgeable` stayed 0, and the ledger
stayed empty. Take 7's same scroll decoded 65 nodes and left the 10 already-flipped ones
failed forever.

**The mute split, both branches measured live** on the Media panel's ten-instance
ladder, driven through the same ledger edge a provider uses: with the panel off-window
and its art undecoded, `LuauUIChromeL3` — whose own asset is the condemned one — carries
the fallback tag, **no** mute tag and styled `ImageTransparency 0` (the instrument is
alive) while its nine healthy siblings carry both at 1 (10 / 9). With the panel scrolled
in and its art resident, all ten carry both at 1 (10 / 10) — nothing to recover, so the
slot reads flat. Recovery clears both tags on every instance (0 / 0).

**Desktop spot check** (1232×1067, fantasy-ornate): 140 judgeable, **no `clipped`
entry at all**, 15 undecoded and all of them the hidden `ViewThatFits` losers the FIRST
clause spares; ledger empty. That is why the thirteen non-phone rows were never tainted.

**Captures** (whole emulated screen, three-marker calibrated, crop `814 545 849 1696`,
solved scale 2.3609/2.3642 against take 7's recorded 2.3642/2.3616 — the Studio window
has not moved):
`RS-A16-D5_fixed_phone-portrait_fantasy-ornate.png` (sha `523c6949c024cdf6`) and
`RS-A16-D5_fixed_phone-portrait_pixel-quest.png` (sha `f4c08bcf125e2d1e`).

**New instrument, reusable.** `adapter.chromeArtJudgement` / scenario step
`artJudgement` pairs the framework's own failure ledger with a judgement over every art
instance the target owns. `undecodedJudgeable` is the number that matters — art the
target is entitled to call broken — and on a phone under an ornate package it must be 0
while `byReason.clipped` is large. That pair is the D5 signature, present or gone, and
any future drive can read it in one call.

**Headless half:** suite 1741 → 1757, `tests/theme_asset_judgement.spec.luau` (15 cases,
the take-7 reproduction geometry). Falsifiability measured, not asserted: deleting the
clipped clause turns 6 cases red (1750/6); reverting the mute split and the
observed-failure latch turns 3 red (1753/3).

**The take-7 diagnosis's third rider, dispositioned.** "Should one off-window consumer
be able to condemn a shared asset for every on-screen consumer at all?" — after this fix
it cannot: an off-window decoration is not judgeable, so it condemns nothing. The verdict
stays per ASSET rather than per consumer, and that is deliberate: a judgeable decoration
that has drawn its art for a full grace window and still has nothing IS evidence about the
content id, and every consumer of that id shares the same picture. Narrowing the ledger to
"failed for this node only" would give one slot flat art and its twin real art from the
same asset, which is the half-painted state the fallback exists to avoid.

**Not claimed:** the five-view matrix. This round drove two phone-portrait rows plus a
desktop spot check to prove the defect gone; RS-A16 still owes its nineteen rows at one
stamp.

### Instrument notes from this round

- **The single magenta bbox was wrong for phones, and take 5/6's phone calibration with
  it.** A full-viewport frame gives one bbox, and a bbox cannot tell a uniform fit from a
  stretched one: on phone-portrait it measured 843×1878 (aspect 0.449) against a
  359×718 viewport (aspect 0.500), because the emulator paints a device band outside the
  framework's coordinate space. Calibration is now **three markers at known LuauUI-space
  positions**, blob-labelled and solved per axis, with the marker-size residual reported
  (0.5–0.9 px) — so linearity is proven, not assumed. The desktop transform it returns is
  byte-identical to take 5's and take 6's, so the Studio window has not moved.
- **The phone captures are therefore real.** 849×1696 portrait, 1931×927 landscape,
  1988×1490 tablet — the whole emulated screen at true aspect, no Studio-window crop.
- **Injected-pointer offset is per preset.** On `hd_1080` an injected coordinate equals
  node `AbsolutePosition` space; on `samsung_galaxy_a06` portrait it is **47 units
  higher**, and the first canary at the un-offset position produced a raw `Touch` event at
  the wrong place, no application effect, and a Studio `hits CoreGUI` notice. The offset
  is the same device band the calibration measures.
- **In a TouchEnabled session the injected pointer arrives as `UserInputType.Touch`** —
  more than take 5 could claim, still not physical touch.
- **Play Solo is TWO DataModels.** A server-created `ReplicatedStorage` node replicates to
  the client; a client-created `workspace` instance is invisible to the server. Since the
  probe needs `LocalPlayer` and `HttpService` is server-only, traces travel
  client → `RemoteEvent` → server → local sink, which is why all 14 row traces are files.
- **`SetDeviceAsync` clears a prior `SetResolutionAsync` override**, and
  `SetOrientationAsync` errors on a desktop preset — both recorded rather than worked
  around.
- **Flow vs overlay containers.** A raw chrome-vs-node sweep reports 79 overlaps under
  ornate; **78** have a common ancestor that is a declared layering host (60 under the
  twelve `StatN+background` plates, 16 under the four `tN+overlay` tiles, 2 under the
  Slider's `Groove`), where overlapping is the mechanism. The one flow case is the
  Advanced disclosure's 32 px icon art box overhanging the 8 px caret host by 8 px into
  the label's box — and its **ink** does not: measured column by column, the chevron ends
  at GUI x 136 and the label's first glyph starts at 139, a 2 px gap inside a 10 px
  transparent margin, with the label drawing above it. Bucketed and reported, never
  dropped, and only while it stays inside that margin.

### Honesty ledger for this round

**13** canonical `RS-A16_*` PNGs replaced at the final stamp, each sha-pinned and paired
with a full trace; **6** left untouched because they are exactly the rows RS-A16-D5
taints. Take-5's three-file debt is **reduced, not cleared**. Two new diagnostics
(`RS-A16-D5_*`) and one watch capture (`RS-A16-WATCH_toggles_*`) added, all untinted
product states. Nothing is superseded; `b-a13-matrix.json` still stands.

---

## Final-stamp assertions — what was re-asserted at the final stamp, and what was not

The stage accumulated twenty-two source stamps. **The final stamp is `66599d58-1744436`** (the
RS-A16-D5 fix round, suite 1757); `7d681bed-1726959` (D4, suite 1741), `1de8a15c-1722217` (D2/D3,
suite 1724), `a7da3802-1708708` and `407f3c9c-1705480` are the four before it.

**What was re-observed at `66599d58-1744436` (matrix drive #5, take 8):** **all nineteen matrix
rows**, each with a replaced sha-pinned capture and a full trace; D1/D1b/D2/D3/D4/**D5**
independently re-confirmed; the preflight of **three** fresh Play sessions with their canary
inputs and per-preset three-marker calibrations. **Nothing in the matrix now stands on an earlier
stamp.** The per-capability rows below the matrix (RS-A1..RS-A15, RS-DIR*, RS-EXT) still stand on
their own stamps, listed further down — a later stamp does not invalidate an earlier row, but it
does mean the row's picture and trace were taken on a different build.

### Re-asserted at the CURRENT final stamp `66599d58-1744436` (matrix drive #5, take 8)

| What | How |
|---|---|
| **RS-A16** | **`PASS_AUTOMATED`**: 19 of 19 rows clean, `rows[]` full, all nineteen canonical captures replaced and sha-pinned, `studio-matrix-final-stamp` passing |
| **RS-A16-D5** (art clipped away read as failed) | independently re-read on both phone presets under both art packages, at +2.5 s and again past the 5 s grace deadline: `undecodedJudgeable = 0`, `failedAssets = []`, `fallbackSlots = []`, `luau-chrome-fallback` 0, `luau-chrome-mute` 0 on **all 19** rows, with 16–105 instances spared as `clipped`. Two pictures carry it: the ornate crown mid-bar at 705×338, and pixel art on every plate at 359×718 |
| **RS-A16-D4** (the built-in default's value controls) | independently re-read on **all five** `studio-neutral` rows: all four `OWN_PAINT_SLOTS` surfaces at styled `BackgroundTransparency` 0, base sheet 66 rules / 12 `Slot` / 12 `Skinned`, trough/fill/rail/thumb visible in five captures |
| **RS-A16-D1 / D1b** | independently re-read a fourth time: 2 expanders under flat (both hosted by visible nodes), 0 under every package, 0 bad; hit order returns the visible `Save` first on **all 19** rows; **0** solved-vs-actual mismatches over 100 checked nodes **per row** |
| **RS-A16-D2** | independently re-read: **0** flow-neighbour overlaps on all 19 rows including five ornate rows at five viewports |
| **RS-A16-D3** | independently re-read: **0** zero-area value displays on any row; pixel-quest's bar has loaded art and a real fill window at all five viewports |
| **RS-A1** (the flat default unchanged) | live on **five** viewports: 111 nodes / 107 visible / 39 text, 0 unfit, 0 clip bleed, 0 outside canvas, 0 overlaps, census all zeros, and its value controls painting |
| **RS-A12 / A13 / A14** (the four reference packages) | live and **clean at all five viewports**, phones included: ornate 154 chrome instances / 22 assets / 0 undecoded on-window, pixel 62 / 12 / 0, glossy 45 / 8 / 0, compact-pointer 43 / 6 / 0, each with 12 `Slot` rules and its own `LuauUITheme <id>` sheet verified live per row |
| **Style authority** | plain-vs-`GetStyled` disagreement on every probed control on every row, through `LuauUIStyleLink` into `LuauUIStyle` (flat, 66 rules) or `LuauUITheme <id>` (193–303 rules) |
| **Adaptive input paradigms** | measured per row rather than injected: desktop `KeyboardAndMouse` / Medium / wide; console **`Gamepad`** / Large / ten-foot / ×1.5; phone + tablet `Touch` / Small / compact & regular & wide — all from real presets, `envFrozen = false`, no `setEnv` anywhere in the drive |
| **Tag → rule coverage, live** | 0 uncovered `luau-*` tags on all 19 rows (15 kinds against the flat seed's 66 rules, 53 against ornate's 303, 34 against pixel's 217, 29 against glossy's 199, 28 against compact-pointer's 193) |
| Preflight ×3, the five per-preset calibrations, the canary inputs | this drive (see "Final matrix drive #5") |
| **RS-A16-E1** | recorded as `FAIL_ENVIRONMENT` with its verbatim library message, its measured consequences and its owed harness fix |

### Re-asserted at the previous final stamp `7d681bed-1726959` (matrix drive #4, take 7)

Superseded as current matrix evidence by drive #5 above; kept because it is where D1–D4 were
independently re-confirmed for the first time and where RS-A16-D5 was found.

### Re-asserted at the previous final stamp `1de8a15c-1722217` (matrix drive #3)

| What | How |
|---|---|
| **RS-A16-D1 / D1b** (hit-expander ownership and placement) | independently re-read a second time: exactly 2 expanders, both `Visible`, both on visible sub-floor toolbar buttons; the hidden candidate's three gone; hit order returns the visible `Save` first; **0 solved-vs-actual mismatches over 100 checked visible nodes** |
| **RS-A16-D2** (plaque `overhang` now reserved) | independently re-read: under fantasy-ornate the full-tree chrome sweep finds **0** neighbour overlaps — take 5's 22, including both the 792 px² plaque-over-label and the 21 corner 84 px² hangs, are gone |
| **RS-A16-D3** (pixel-quest's bar fill) | independently re-read: track **473×28**, fill window **160×12**, art loaded; **0** zero-area value boxes on any driven row |
| **RS-A1** (the flat default unchanged) | live: the `studio-neutral` desktop row measures 111 nodes / 107 visible / 39 text, 0 unfit, 0 clip bleed, 0 outside canvas, 0 overlaps, 0 assets unloaded, census all zeros — **but it is the row that found RS-A16-D4, and its value controls do not paint** |
| **RS-A12 / A13 / A14** (the four reference packages), scope only | all four install at this stamp and each carries the 12 `Slot` rules; fantasy-ornate's and pixel-quest's bar and slider slots carry **loaded** art children. No row is claimed and no capture was replaced |
| **Style authority** | plain-vs-`GetStyled` disagreement on every probed property through `LuauUIStyleLink` into the 42-rule `LuauUIStyle` sheet with `Theme Dark`/`Theme Light` children and a `StyleDerive` |
| Preflight, the magenta calibration, the canary capture and the canary input | this drive (see "Final matrix drive #3") |
| **RS-A16** | still `FAIL_PRODUCT`; `rows: []` |

### Re-asserted at the previous final stamp `a7da3802-1708708` (matrix drive #2)

| What | How |
|---|---|
| **RS-A16-D1 / D1b** (hit-expander ownership and placement) | independently re-read: 2 expanders, both on visible sub-floor toolbar buttons, host-centred (`centreDelta 0`); the hidden candidate's three gone; hit order returns the visible `Save` first on both driven viewports and both driven packages; **0 solved-vs-actual mismatches over 195 visible nodes** |
| **RS-A1** (the flat default unchanged) | `check_flat_baseline` PASS inside the gate at this stamp; and live: the flat desktop and console rows measure 39 text nodes / 0 unfit / 0 clip bleed / 0 outside viewport / 0 solver diagnostics / 112 mount-identity entries, with a census of all zeros |
| **RS-A12** (Fantasy Ornate), partially | census intact at this stamp (73 decorations, 60 layers over 30 layered nodes, 139 layer instances, 26 shadows, 17 text lifts, 3 icon art, 1 focus glow, 0 failed assets); asset-decode guard 140 visible image nodes / 22 assets / **0 not loaded**; style authority proven by plain-vs-`GetStyled` disagreement. **But the row is NOT clean — it is the row that found RS-A16-D2.** |
| **Director defects 1, 2, 3 and 7** | live at this stamp: the bar's own caps and crown clear every neighbour by 0 px²; the focus visual rides the art (`FocusScale` + `FocusGlow` on `LuauUIChrome`); "Play" on one line at every driven density including compact-pointer's 13 px; 13 lifted chrome status texts all inside their controls |
| **RS-A14** (the platform pair), partially | glossy-touch and compact-pointer both install, paint and measure clean at this stamp (0 unfit, 0 clip bleed, 0 overlaps, 0 solver diagnostics, all art decoded) — but only at the desktop viewport, and no row is claimed |
| **RS-A13** (pixel-quest), NEGATIVE | installs and measures clean on text, clipping, geometry and ornament clearance — and **fails on RS-A16-D3**: its progress fill is zero-height |
| **RS-A16** | still `FAIL_PRODUCT`; `rows: []` |

### Re-asserted at the previous final stamp `407f3c9c-1705480`

| What | How |
|---|---|
| **RS-A1** (image-is-the-element / the flat default unchanged) | `tools/lune/check_flat_baseline` runs inside the gate and cmp-compares **1506 flat nodes** against the 0.6.0 dump: 6 characterized prop deltas, 4 characterized new nodes, 1 characterized added prop key, **0 rect / 0 hit-rect / 0 class changes, 0 nodes disappeared** |
| **RS-EXT** (the chrome-module extraction) | live smoke at this exact stamp: Fantasy Ornate installs on the extracted build, census intact (73 decorations, 60 layers over 30 layered nodes, 139 actual layer instances, 26 shadows, 17 text lifts, 3 icon art, 1 focus glow, 0 canvas masks), `GetStyled` still detects suppression where a plain read is blind, focus glow parents to `LuauUIChromeL1`. Capture `RS-EXT_smoke_fantasy-ornate.png` |
| **RS-A6** (toggle slots) | the round-6 `UICorner`-on-sliced fix landed at this stamp |
| Preflight, device-preset resolution, the canary input, and the `studio-neutral` desktop row's geometry/text/census digest | this drive (see above) — but the row itself is **not** claimed, because it is the row that found RS-A16-D1 |

### Standing on their original stamps (not re-observed at the final stamp)

| Stamp | Rows |
|---|---|
| `c45e7e28` | RS-A1, RS-A2, RS-A3, RS-A4 |
| `34ccc33a` | RS-A5, RS-A6 |
| `fc818bcb` | RS-A7, RS-A8, RS-A9, RS-A11 |
| `02d6dd89` | RS-A7, RS-A10 |
| `0b8ddf06` | RS-A12, RS-A13, RS-A14, RS-A17 |
| `4d7e87c7` | RS-A15 |
| `2df72101` | RS-A15 (the rung-2 gradient half) |
| `9e091340` | RS-A7, RS-A17 (the memory-delta fix round) |
| `38ee8cf3` | RS-A2, RS-A5 |
| `9a5dbf1b`, `e62c3bce`, `d5f1fd92`, `57f3fc50` | RS-A5 (the successive bar/value rounds) |
| `2c44a5f6` | RS-A14 (the glossy bar re-cut) |
| `62b6cdeb` | not an acceptance row — the round's own CanvasGroup-opacity finding, recorded in `rs-a5-image-bars.json` |
| `d45f712f` | RS-A6, RS-A12 (director round 7) |

**RS-A16 was the row whose whole job was to close this gap** — to re-observe the five-view
matrix under all three packages at one final stamp — and after five attempts it is
**closed**: nineteen rows, one stamp (`66599d58-1744436`), nineteen replaced captures, nineteen
traces. The rows in the stamp table below therefore remain evidenced at their own stamps for the
per-capability claims they made, but the MATRIX claim no longer depends on any of them.

Two seam limits belong on the record with this inventory:

- **Device selection.** Every row in the stamp table above that carries a phone or console
  viewport was driven through the runner's declared `setEnv` seam, because device selection was
  unavailable from `execute_luau` when those rows ran — so those rows' viewport facts were
  *framework-side* facts, never engine-side ones, their geometry traces rather than their pictures
  carried the layout claim, and their phone/console pictures were cropped by the Studio window.
  **The nineteen matrix rows are not in that class:** every one of them selected a real preset
  through `StudioDeviceSimulatorService` with `envFrozen = false`, and every one of their captures
  is the whole emulated screen solved from three markers.
- **The `preferredTextSize` seam.** Preferred text is a fixture axis driven through the same
  declared env seam, not an OS accessibility setting. Every preferred-text claim in this stage —
  including the standing "watch `TbPlay`'s zero-slack box" item — is an **injected**-fact result.
  On the final drive `preferredTextSize = 1` on all nineteen rows and `TbPlay` fits one line at
  every density (24–27 px of engine bounds in a 51–80 px box, `TextFits = true`), but the axis
  itself was not swept. A real OS text-size change remains E4 (RS-P2).

---

## Director round, second pass (live review, 2026-07-26) — defects 8 to 11

Four more reported defects, all four fixed and proven live. Three of them turned
out to be the SAME class the last round kept finding — a decision made once at
construction and then never re-asked, or a rule set that REPLACES rather than
composes — and two of them were native-mode divergences from the bespoke path
that the flat default could not show.

**Live session for all of them:** Studio `0.731.0.7310942`, Play Solo (Client),
viewport `1233x1067` (Device Emulator OFF, real desktop), CoreGui player list
visible in the top-right corner of the captures. The picker rows ran on the
**DEMO** path (`LuauUI_Scenario = ""`, `LuauUI_ThemePicker = true`, the
director's own state, restored at the end of this round); the segmented-control
row ran on scenario `theme_authoring`. Pre-fix stamp `66599d58-1744436`,
post-fix stamp **`dbd2170f-1766414`** (suite 1757 -> 1789; the intermediate
stamps `56a8cdb1-1761880` and `3b0e32bc-1763466` carry the per-defect proofs
quoted below, and every claim was re-observed at the final stamp).

### 8. The glossy switch was GREEN, and its SELECTED label was unreadable

Two halves, reported together, with different owners.

#### 8a — the ON capsule (an ART defect, and the art said so)

**Reported:** the toggle's ON highlight is green; it should be blue, the
package's own accent identity.

**Root cause.** `assets/themes/glossy-touch/source/generate_art.py`'s
`toggle_track("on")` painted the `GREEN` gel ramp with a `GREEN_BOT` rim. Green
appears **nowhere else in this package**: `accent` is `rgb(18, 92, 190)`, the
selection plate is the `BLUE` gel, the pressed stepper plate is `BLUE_DEEP` and
the progress fill is `BLUE_GEL`. It was a borrowed traffic light in a package
whose whole identity is one cool blue action colour.

**Fix — one substitution, re-cut procedurally at a new recorded seed `0x6E43`**
(the 5b/5c precedent): the ON capsule now uses the same `BLUE` ramp and
`BLUE_BOT` rim the selection plate uses, at the same sheen. Geometry, slice
border (14), size (72x32), the OFF state and the chrome knob are untouched.
**Byte scope verified rather than asserted:** at the new seed exactly one texture
moves (`glossy_toggle_track_on.png`, sha256 `162394fd…` -> `06f2e80a…`); the
other thirteen re-generate byte-identically, checked by hashing the whole
directory before and after. Re-uploaded through Studio MCP `upload_image`:
`rbxassetid://108229882767307` -> **`rbxassetid://98206529376640`**; manifest,
provenance and the package's content ID all updated.

**Live proof.** Both fixture switches resolve the new asset through the
toggle-on rule with `IsLoaded = true` at 44x24, and the demo's Music switch reads
blue at the desktop viewport.

**Captures:** `RS-DIR8a_toggle-on_before-after_glossy-touch.png` (the same switch,
same crop, green above and blue below), `RS-DIR8a_toggle-on_desktop_glossy-touch_blue.png`,
`RS-DIR8a_valueprobe_glossy-touch_toggle-blue.png`.

#### 8b — a SELECTED button drew DARK text on saturated blue

**Reported:** the segmented "Balanced" option, on its blue gel plate, is barely
legible.

**Root cause, measured at the palette seam.** ADR-0019 gates exactly two pairs
per theme — surface/content and accent/onAccent — and **nothing ever carried a
pairing to the SELECTED state.** A selected skinned node paints its `selected`
art tinted by `$ChromeTintSelected`, and its lifted label kept whatever
`Text default` gave it, which is `$Content`. Measured live at the pre-fix stamp
on `/Settings/Quality/Options/Opt2`: the lift's `GetStyled TextColor3` =
`$Content` `(0.094, 0.118, 0.165)` over a plate whose glyph band measures
`rgb(66, 116, 215)` — **3.74:1**, under the 4.5 floor, while white on the same
pixels measured 4.46.

**Fix — one derived token, read by both paint paths.**
`sheet_model.selectedContentColor(theme)` is a pure resolver in the same idiom as
the 3.5 `togglePalette` ruling, and `$OnSelected` is the token it publishes on
every theme of both builders:

| | value | why |
|---|---|---|
| `content` | the status quo | taken wherever content still clears **4.5:1 against the theme's own selected surface** (`extra.controlSelected`, the colour the framework already paints for an unskinned selected row). True for every reference theme but one, which is what keeps Studio Neutral and every flat package byte-identical — neutral reads content at 9.74:1 and onAccent at 11.22:1, and preferring the HIGHER one would have been a visible change with no defect behind it. |
| `onAccent` | the guaranteed partner | taken only when content fails. It is the one colour a theme promises is readable against its accent, and a selected surface is an accent-washed control by construction (`effectiveExtra` derives it as control lerped 35 % toward accent). |

Two rules read it, so the skinned and the unskinned paths cannot drift:
`Chrome text — selected` (`.luau-selected > .luau-chrome-text`, emitted FIRST
among the lift's colour rules so a role/surface tint still wins the label exactly
as it wins the picture) and `Selected row`, which gains `TextColor3` beside the
`BackgroundColor3` it already had.

**And the package had to tell the truth.** The resolver reads
`extra.controlSelected`, and glossy-touch declared `rgb(188, 214, 250)` — a pale
blue it draws **nowhere**. Its selection plate is `glossy_selection_selected`
under `$ChromeTintSelected`, measured `rgb(36, 78, 186)` live in the rows a
lifted label occupies. The palette is now that colour, so the framework resolves
`onAccent` and the label goes white. This is the honest half of the seam: a
package whose palette claims one selected surface while its art paints another
gets a label nobody can read, and no framework resolver can see art.

**The sweep the director asked for, headless, over every reference package.**
`tests/sheet_model.spec.luau` walks Studio Neutral plus all nine example packages
(13 themes) and refuses any theme whose selected surface can carry NEITHER
content role at 4.5:1. It also pins the two it MOVES, so a silent third shows up
in a diff rather than only in a capture:

| package / theme | selected surface | content | onAccent | resolved |
|---|---|---|---|---|
| studio-neutral / Dark | `#2d3a5c` | 9.74 | 11.22 | content (unchanged) |
| classic-desktop / Day, Night | `#b4c6e2`, `#384a68` | 10.24, 7.17 | 1.73, 2.13 | content |
| compact-pointer / Aqua | `#cee0f8` | 12.46 | 1.34 | content |
| fantasy-ornate / Grand Hall, Crypt | `#765a2c`, `#4a5c60` | 5.38, 5.58 | 2.77, 2.70 | content |
| fantasy-parchment / Daylight, Candlelight | `#d4ba84`, `#70562c` | 7.62, 5.46 | 1.72, 2.59 | content |
| glossy-mobile / Daylight | `#bed8fa` | 11.69 | 1.46 | content |
| **glossy-touch / Sky** | `#1451c2` | **2.37** | **7.03** | **onAccent** |
| **pixel-quest / Quest** | `#d7a860` | **1.75** | **8.47** | **onAccent** |
| scifi-hud / Nightwatch | `#143a4e` | 9.33 | 1.64 | content |

pixel-quest is the package the sweep caught on its own: its gold selected plate
was carrying near-white content text at 1.75:1 and now carries `onAccent` at
8.47:1.

**Live proof (stamp `3b0e32bc-1763466`).** `Opt2` — the only node tagged
`luau-selected` — resolves `GetStyled TextColor3 = 1, 1, 1`; `Opt1` and `Opt3`
are unchanged at `$Content`. Measured on the shipped plate, plate pixels only,
across the 18 rows the glyphs occupy: **white 7.31:1 median (4.45–7.96 per row)
against content 2.28:1 (2.10–3.75 per row)** — white is the better partner on
every single row, and the median clears the floor by 1.6x.

**HONEST LIMIT.** The top two rows of that band read 4.45–4.5 for white, because
a *gel* is a vertical gradient and its lit end is always the worst case. Dark
text was worse there too (3.75), so the fix is strictly better everywhere; a
deeper `BLUE_DEEP` cut of `glossy_selection_selected` would clear 4.5 across the
whole band (measured offline: 5.92–10.09) and is left as an ART decision for the
director rather than taken here.

**Captures:** `RS-DIR8b_segmented_before-after_glossy-touch.png` (the same three
options, same crop, dark "Balanced" above and white below) and
`RS-DIR8b_segmented_desktop_glossy-touch_onselected.png`.

### 9. Controls and the picker clipped and overlapped their text

Reported as one defect; measurement found **four independent causes**, three of
them framework and one of them the example.

#### 9a-i — a Toggle's label column was built from BOOT metrics

**Root cause (measured).** The renderer's measure seam built the row's box from
the LIVE snapshot (`trackInset`, `trackWidth`, `space.m`) while
`buildToggleVisual` boxed the label from `style.space.s + 4` and `style.space.m`
— the style captured when the **ScreenTarget was constructed** — and drew it at a
hardcoded `TextSize = 16`. Under Studio Neutral the two agree to the byte
(`space.s + 4 = 12 = trackInset`, `space.m = 16`), which is why it survived four
stages. Under classic-desktop (`space.m = 8`, body 13) the solver reserved a
**28 px** label column and the adapter drew **20**, at size 16 where "Music"
needs 35 — the label read **"Mu"**. Under sci-fi (`space.m = 14`, body 14,
Michroma) it reserved **40** and drew **38** at size 16 where "Music" needs 45.5
— **"Musi"**, the director's own screenshot.

**Fix.** One description, two consumers: `themeSnapshot.toggleRowPadding(snap)`
is what the renderer's measure seam uses and what the adapter's label box is
derived from, re-applied inside `setThemePackage` so a swap moves the column; and
the label's `TextSize` now follows the node's published `textSize` prop — the
same `INTRINSIC_TEXT_ROLE` size the solver measured with — instead of the 16 it
was born at. The neutral answer is byte-identical to the constants it replaces,
which is asserted rather than assumed.

**Live proof.** classic-desktop, same node, same box: `Music` 104x28 with
`Label 28x28 @ TextSize 13, TextFits = true, bounds 28x13` — exactly the reserved
column. Pre-fix: `Label 20x28 @ TextSize 16, TextFits = false`.
**Capture:** `RS-DIR9a_toggle-label_before-after_classic-desktop.png` ("Mu" above,
"Music" below, same 104x28 box).

#### 9a-ii — the per-word sum could reserve LESS than the engine draws

**Root cause (measured live, and it is half a pixel).** `GetTextBoundsAsync`
answers on a **0.5 px grid**, and the engine lays a whole line out in one pass
while `text_metrics` sums the parts. The space probe (`"x x"` minus `"xx"`) is a
DIFFERENCE of two quantized answers, so it can land one step low: at
BuilderSans@13 it returns **2.50** where the engine's own inter-word advance
inside "Classic Desktop" is **3.00** — reproducibly, linear over `n = 2..8`, and
−0.5 **per gap** on a four-word string ("one two three four": word-sum 90.00,
engine 91.50).

Half a pixel is not a curiosity when the box is `ceil(width)`: under
classic-desktop it put **five of the picker's ten chips** on the wrong integer,
and they were exactly the five whose true width ends in `.5` —
`Classic Desktop` 74.5, `Compact Pointer` 80.5, `Fantasy Ornate` 73.5,
`Pixel Quest` 54.5 and the stub — while `Studio Neutral` (69.0) and
`Glossy Touch` (63.0) fitted by luck. Each of those five wrapped a single-line
label and clipped it: the chips read "Classic", "Compact", "Fantasy",
"Sci-Fi HU".

**Fix.** One grid step is reserved per word JOINT, and only where the widths came
from the engine at all — an estimated line already carries the conservative
full-em bound, and a headless solve never has engine widths, which is what keeps
the flat baseline reproducible.

#### 9a-iii — a container measured its children in the box its PARENT offered

**Found by this round's own fix, live.** `ViewThatFits` was given exactly this
fix in director round 3 ("measuring the candidates at the parent's 1200 picks a
row that then has to arrange inside 620"); every OTHER container still measured
against the offer. The picker's panel is `percent(1, offset = -16, max = 560)`
inside a 1217 px dock, so its chip Grid was **MEASURED** with 1201 px available
(two rows) and **ARRANGED** with 544 (five rows): the raised plate ended 65 px
above its own last row of chips. It is **pre-existing** — the stored 2026-07-25
picker capture shows two rows of chips outside the card — and the intrinsic
columns below made it three.

**Fix.** The same clamp `fits` already carried, generalized: a container whose
own width is definite (`fixed` or `percent`) measures its children inside THAT,
never inside the offer. `fill`, `minMax`, `aspect` and content are left alone —
none of them can answer without the content being measured. `check_flat_baseline`
is unmoved: **0 rect / 0 hit-rect / 0 class changes.**

**Live proof:** Panel `560x331` containing a Grid `544x246`; **0 chips outside
the panel** under all four driven packages, where the pre-fix tree had five.

#### 9b — the picker's own two guesses

`examples/gallery/client/theme_picker.luau`, both in the example rather than the
library:

1. **the chip height was `fixed`**, and a fixed row cannot hold a wrapped label.
   Under classic-desktop the compact height is 22 px where two lines need 30, so
   the label clipped; under sci-fi the 32 px row could not hold two lines of 14 px
   at its 1.45 leading, so the label **OVERFLOWED its plate** into the rows above
   and below — which is the "spills past plate edges into neighbours" in the
   report. It is now `minMax { min = compact.height }`: a long name grows its chip.
2. **`minColumnWidth` was the literal `132`**, which is a guess about a FONT.
   `UI.Grid` now accepts `minColumnWidth = "intrinsic"` — no column narrower than
   the widest child MEASURES, under the active theme's own font, recomputed every
   solve — so the grid re-columns itself on a swap with nothing to update. The
   picker asks for it.

#### 9c — `itemSizing`, the opt-in uniform mode (director ruling, same round)

Intrinsic columns fixed the clipping and left the picker **ragged**: ten plates
of ten different widths. The director's ruling: the layout system gains a
container option, `itemSizing = "natural"` (the default) `| "uniform"`, and the
picker uses it.

`uniform` reuses the measurement machinery the rest of this defect already
wires — it measures every child in the column it will occupy, **max-reduces**
across all of them per axis, and hands that one size to every cell. Both the
measure and the arrange pass call the same helper, so a grid cannot measure
ragged rows and arrange uniform ones — which is the exact class of defect §9a-iii
was. `natural` stays the framework-wide default and nothing else opts in this
round: content sizing is what every existing grid was authored against, and a
layout that silently equalised its cells would move geometry nobody asked to
move.

The property that makes it a THEME feature rather than a cosmetic one: the max is
a measurement, so a wider display face grows all ten cells together on the next
solve. Headlessly: the same grid at TextSize 12 and 24 gives 179 px and 253 px
cells, all equal within each solve; `natural` and an absent option are identical
and still ragged, which is the assertion that keeps the default honest.

**Live proof, all four packages at 1233x1067 — one cell size per package:**

| package | panel | chip size (all ten) | unfit labels | chips outside the panel | box overlaps | text overflowing its plate |
|---|---|---|---|---|---|---|
| studio-neutral | 560x331 | **196x46** | 0 | 0 | 0 | 0 |
| classic-desktop | 560x232 | **148x39** | 0 | 0 | 0 | 0 |
| sci-fi HUD | 560x326 | **198x45** | 0 | 0 | 0 | 0 |
| glossy-mobile | 560x353 | **179x48** | 0 | 0 | 0 | 0 |

Four packages, four different cell sizes, ten identical plates inside each — the
font decides the size and the option decides that they agree.

**Captures:** `RS-DIR9b_picker_desktop_studio-neutral_uniform.png`,
`RS-DIR9b_picker_desktop_classic-desktop_uniform.png`,
`RS-DIR9b_picker_desktop_scifi-hud_uniform.png`, plus the pre-fix pair
`RS-DIR9b_picker_desktop_classic-desktop_BEFORE.png` and
`RS-DIR9b_picker_desktop_scifi-hud_BEFORE.png`. (The intermediate
variable-width captures `…_no-clip.png`, `…_no-overlap.png` and
`…_contained.png` are kept: they are the step where the clipping was fixed and
the raggedness was still there, which is what the ruling was made against.)

**Trade-off, recorded rather than hidden.** Uniform intrinsic cells are the
widest chip's width, so the picker falls from four narrow columns to two or three
wide ones and the panel is taller. That is the cost of never clipping; the
alternative is a literal that only suits one type ladder.

### 10. Picking Classic made OTHER text go blurry

**Diagnosed live before a line of code moved, and the mechanism is one engine
default.** Candidates were checked and eliminated first: every `UIScale` in the
tree reads exactly `1.000000`, there are **0** fractionally-positioned or
fractionally-sized nodes in either LuauUI ScreenGui, and no node carries
`TextScaled`.

**Root cause.** `UIStroke.ApplyStrokeMode` defaults to **`Contextual`**, which on
a TextButton or TextLabel strokes the **GLYPHS**, not the border. Every hairline
this compiler emits is a border — and the bespoke path always said so
(`hairline()` in `screen_target` writes `ApplyStrokeMode.Border` explicitly)
while the rule-owned path inherited the engine default. Under Studio Neutral the
hairline is white and the label is white, so it was invisible; under
classic-desktop Day the hairline is `rgb(96, 94, 90)` at 0.55 and the label is
near-black on a light chip, so every glyph grew a dark halo. Under sci-fi the
hairline is bright cyan and the halo bled past the plate — the *same* defect the
director read as "spills into neighbours".

**Proven by changing exactly one variable, live.** Setting
`ApplyStrokeMode = Border` on the live `Chip — outline` rule and re-capturing the
identical frame:

| | shipped (Contextual) | Border |
|---|---|---|
| mid-tone (halo) pixel fraction | **0.1877** | **0.0560** |
| ink fraction | 0.0605 | 0.0540 |
| mean glyph edge gradient | 10.06 | **11.77** |
| pixels differing by > 16/255 | — | 1602 of 8184 |

The halo collapses by 3.35x and the edges sharpen 17 %. The rule was then
reverted and the fix written at the seam.

**Fix.** **Every** `::UIStroke` rule either builder emits carries
`ApplyStrokeMode = Border` — the surface hairlines, the field outline, the chip
outline, the value-slot outlines, the asset-failure fallback hairline and the
skinned suppression. One invariant, one spec, no exception to remember.
`ApplyStrokeMode` was already on the phantom-property allowlist, so the rule
cannot be inert.

**A second thing the fix restored.** The chips' outline had never drawn at all —
the stroke was going onto the text instead — so `Chip — outline` is now visible
for the first time in the picker's life. Both are in the capture.

**Capture:** `RS-DIR10_chip-text_before-after_classic-desktop.png` (the same
chips at 3x, haloed-and-borderless above, crisp-and-outlined below).

### 11. Selected buttons went SQUARE under glossy-mobile

**Root-caused live, and the prime suspects were both wrong.** No real `UICorner`
child exists on the node (`FindFirstChildOfClass("UICorner") == nil`, so nothing
suppresses a phantom), and `setTogglePartChrome` never runs here — glossy-mobile
paints every slot natively and has no toggle art at all.

**Root cause (from the live rule dump).** The selected picker chip swaps
`surface = "chip"` for `surface = "accent"`, and **per-surface rules REPLACE,
they do not compose**: `.luau-surface-chip::UICorner` stops matching, and the
accent rule set carried a fill, a label colour, a hover and a pressed rule —
and **no corner at all**. The bespoke path never showed it because
`wireInteractiveStates` gives every Button a REAL `UICorner` before
`applySurface` runs, so this was a pure native-mode divergence. It reads worst
under glossy-mobile because its `radii.control` is 16 and its slots are native,
so nothing else rounds the plate.

**Fix.** `Primary button — corner` (`.luau-surface-accent::UICorner`) at the
theme's `radii.control`, emitted by both builders, wired through `fromMetric` so
a live metric edit repaints it, and positioned with the other surface corners so
the skinned suppression still beats it.

**Live proof.** Under glossy-mobile the rule reads `CornerRadius = 0, 16` on
`.luau-surface-accent::UICorner`, and the selected chip is a pill identical to
its siblings — at the round's final stamp it is one of ten identical 179x48
pills, so "identical to its siblings" is a measurement rather than a look.
**Captures:** `RS-DIR11_selected-corner_before-after_glossy-mobile.png` (square
above, rounded below) and
`RS-DIR11_picker_desktop_glossy-mobile_uniform-rounded.png`.

### What this round changed for FLAT themes

`check_flat_baseline` stays **PASS, byte-unchanged: 1506 flat nodes, 6
characterized prop deltas, 4 characterized new nodes, 1 characterized added prop
key, 0 rect / 0 hit-rect / 0 class changes** — the same characterized set the
previous rounds left, with nothing added. Every one of the four defects is a
no-op under Studio Neutral **by construction, not by luck**:

- **8a** touches one package's PNG. **8b** resolves `$OnSelected` to `$Content`
  for every flat theme (neutral 9.74:1), so both rules paint what they painted.
- **9a-i**'s shared description returns the neutral constants to the byte
  (`left = 12`, `right = 44 + 12 + 16`), which is a spec, not a claim.
- **9a-ii** applies only where a word width came from the ENGINE; a headless
  solve has none, so the dump is bit-reproducible.
- **9a-iii** clamps a container to its own definite width, and no baseline
  fixture has a container narrower than its offer with content-measured children
  — measured, not assumed: 0 rect changes.
- **10** and **11** are rule properties. A phantom stroke that was already a
  border-only shape (a Frame) is unaffected, and Studio Neutral's white hairline
  on white text was invisible either way; the accent corner matches what the
  bespoke path already drew.

### The regressions this round adds

**Twenty-one specs, all written red-first and each proven red against the pre-fix
tree** (the two containment specs were additionally proven by mutation — disabling
the clamp turns both red and nothing else). `tests/sheet_model.spec.luau`: every `::UIStroke` rule of both builders
carries Border (2), the phantom-property allowlist admits it (1), the accent
corner exists in both builders with its metric wiring and its cascade position
(3), `selectedContentColor`'s two-way decision plus `$OnSelected` on every theme
of both builders and both rules that read it (4), and the reference-package sweep
with its two pinned rescues (2). `tests/renderer.spec.luau`: the toggle row's
padding is one description with the neutral answer pinned, the classic and sci-fi
numbers that clipped, a package that moves the track, and a source anchor that
both seams read it and the boot-constant expression is gone (4).
`tests/layout.spec.luau`: the joint's grid step, per gap, once, never on a single
word, never on an estimate, and inside the wrap decision (5).
`tests/layout_vocabulary.spec.luau`: intrinsic columns from the widest child,
from the FONT rather than a literal, the numeric path untouched, the schema's
closed string set (4), containment for a percent-capped and a fixed-width
container (2), and `itemSizing` — max on both axes, the default byte-unchanged
and still ragged, a bigger font growing every cell together, the grid's own
measured height counting uniform rows, and the schema's two modes (5).

### End sweep at this stamp

`./run-tests.sh` **1789 passed** (floor raised 1757 -> 1789);
`check_flat_baseline` PASS; `check_docs_cli` PASS; `check_prop_parity` PASS
(22 classes, 329 properties); `check_registration` PASS; `check_boundary` PASS
(66 files); `check_theme_drift` PASS; `bench` PASS; the RascalRally game suite
**2404 passed**; and `lune run tools/lune/gate rich-skinning-v2` **PASS, exit 0**.

**One bench honesty note.** `mounted-slice-update-storm` flapped over its
1.5x p95 threshold on a loaded machine (a live Studio session, two local HTTP
servers and image work running beside it) and settled back under it once the
machine was idle — three consecutive PASS runs at p95 0.1495–0.1563 against a
0.1584 threshold. The load was machine-wide rather than targeted:
`hud-binding-storm-imperative` (the imperative adapter) and
`sparse-update-under-load-fusion` (the Fusion adapter), neither of which this
round touches at any level, moved by the same 1.05–1.33x factor in the same runs.
Disabling this round's only per-node solver addition (the §9a-iii clamp) changed
nothing: p50 stayed at 0.088. The final recorded `artifacts/bench.json` is a PASS
from the settled machine.

### Honesty ledger for this round

- **The five-view matrix was NOT re-driven.** All nineteen `RS-A16_*` captures
  still verify by sha and none is re-claimed, but they are pre-fix history for
  the five behaviours above; the note is recorded in `rs-a16-matrix.json`.
- **The desktop viewport only.** Every row here ran at 1233x1067 with the Device
  Emulator off. The phone and console rows of these behaviours are not driven.
- **The picker's density dropped** (four columns to two or three). That is the
  measured consequence of never clipping and of the uniform ruling, and it is a
  judgement the director may want to revisit — a `max` on the intrinsic column
  would trade legibility back for density.
- **`itemSizing` has exactly one consumer.** The picker. Nothing else in the
  library or the examples opts in this round, deliberately, so `natural` remains
  provably the default everywhere it already was.
- **The capture instrument gained a required argument.** A second Studio window
  (a game place) was open for part of this round, and `capture_viewport.sh` picked
  the FIRST large Studio window — which produced one capture of the wrong place
  that looked exactly like a capture of the right one. It now takes
  `STUDIO_WINDOW_MATCH` (a window-title substring) and every capture stored here
  was taken from window `2011`, `Place1`, verified in the tool's own output.
- **The glossy selected plate's top two glyph rows** sit at 4.45–4.5:1 for white.
  Better than the 3.75 dark text managed there, still the worst case of a gel,
  and left as an open ART decision rather than taken unilaterally.
- **The stub package is still in the picker.** `fantasy_parchment_stub` declares
  no `testOnly`, so it lists — and at 196 px it is what forces the neutral grid to
  two columns. Whether it belongs there is the fixture owner's call; this round
  did not change it.

---

## Step 3.5 carry-over note

The stale pre-fix `b-a13` matrix rows from theme-packages-and-skinning describe
the pre-fix build (stamps moved; badge geometry changed). RS-A16's take-8 re-drive
**has now re-observed the five-view matrix at this stage's final stamp**
(`66599d58-1744436`, 19/19 rows), so those rows are superseded as CURRENT evidence
and the 3.5 captures remain valid only as pre-fix history.
TP-P1/TP-P2/TP-P3-re-look remain Step 3.5's own open human rows in its review
packet — this stage does not close them and does not reopen them.

---

## Post-gate feature round — THE CIRCLE BUTTON (director-requested, 2026-07-26)

Landed **after** the `rich-skinning-v2` gate passed, at source stamp
`6bede3e1-1794467`, suite **1789 → 1839**. The gate is re-run PASS exit 0 at this
stamp and its library-suite floor is raised to 1839.

**What shipped.** `UI.Button{ shape = "circle" }` — the iOS floating round "…"
action. A closed two-value enum defaulting to the rectangle every Button already
was, so nothing that predates it moves by a pixel (`check_flat_baseline`: 1506
flat nodes, 0 rect/hit/class changes). The diameter is the control metric
`controls.button.height`; the solver enforces the 1:1 box through the existing
`aspect` dimension, so one authored axis drives the other and neither means the
metric. Content is ONE semantic `icon` or up to three characters. The pill and the
rim are phantom `::UICorner` / `::UIStroke` rules on a `luau-shape-circle` tag —
**zero new instances on a flat theme**, measured live: `realUICorner = 0` on every
disc under all four packages.

**Evidence:** `rs-circle.json` (preflight, four-package trace, six claims, three
observations) + `tests/button_shape.spec.luau` (40 assertions, falsifiability-checked).

### RS-CIRCLE-P1 — director readability call (E5, `PENDING_HUMAN`)

Open these four in order. All are at stamp `6bede3e1-1794467`, desktop
1233x1067, native StyleSheets on.

| # | File | What to judge |
|---|---|---|
| 1 | `RS-CIRCLE_desktop_studio-neutral.png` | the FLAT default, and the one that matters most because every unskinned screen gets it. Five true discs — `...`, `x`, `=`, a 72 px `9+`, an accent `OK` — beside a rectangular A/B button. Do they read as *buttons*, and is the hairline rim doing anything useful at this size? |
| 2 | `RS-CIRCLE_desktop_fantasy-ornate.png` | the same declarations under the layered package. **The art is the silhouette**, so the discs wear ornate SQUARE carved frames. Is "a package's `control` art decides the shape" the right ruling, or should a circle refuse a square skin? The Close disc's ornate cross is the icon path working. |
| 3 | `RS-CIRCLE_desktop_glossy-touch.png` | the touch package's rounded gel plates over the same boxes, with the framework's own glyphs (glossy-touch ships no icon map). |
| 4 | `RS-CIRCLE_statewalk_desktop_studio-neutral.png` | rest / hover / pressed on the "…" disc at 3x under a real injected mouse. Does the state change read *as* a state change on a shape this small? |

**The one design question this round wants answered (observation O2).** A
rectangle grows to absorb a skin's `contentInsets`; a fixed-diameter disc cannot,
so under Fantasy Ornate (10/14) and Glossy Touch (14) the lifted label's box on a
44 px disc is **16x24** — the accent disc's "OK" reads as a blob under ornate and
clips to "O" under glossy (visible in captures 2 and 3). The icon path is
unaffected by construction and looks right in the same frame. Three ways out, and
the choice is the director's:

1. **Ship it as documented** (current): a skinned disc should carry an `icon`, and
   the API reference says so. Costs nothing, and the failure is visible to the
   author on their first capture.
2. **Exempt a fixed-diameter disc from its slot's `contentInsets`** — more room,
   but the label then sits on the package's painted rim, which is exactly what
   those insets exist to prevent.
3. **Grow the disc by its insets** — the content room stays constant, but the
   diameter stops being the control metric and a metric package loses control of
   the size, which is the property the whole feature is built on.

### RS-CIRCLE-P2 — physical device (E4, `PENDING_PHYSICAL`)

A 44 px disc is the touch-target floor exactly, and its hit rect is the **full
square** (the engine rounds paint, never the input rect). What no emulator can
answer: whether a thumb hitting the *corner* of that square — visually outside the
circle — reading as a hit is right or wrong on hardware. Procedure: install the
review build, run the `theme_authoring` scenario, `presentCircleFixture`, and tap
each disc's corner and centre in turn on a phone.

### Instrument note from this round

Two Studio windows were open (the LuauUI place and RascalRally). The first
capture came back with the *racetrack* in it and was otherwise
indistinguishable from a valid one — `capture_viewport.sh` picks the first large
Studio window unless `STUDIO_WINDOW_MATCH` is set. Every capture above was taken
with `STUDIO_WINDOW_MATCH="Place1"`. The script already warns about this in its
header; this round is the second time it has bitten, so treat the variable as
mandatory whenever a game place is also open.

## Director dispositions — 2026-07-26, closing the post-gate review round

1. **Picker uniform grid: APPROVED at 3 columns.** Follow-up styling directed: negative
   space between the grid's bottom row and the Day/Night toggle beneath it, and chip
   heights reduced (they read taller than needed, especially at desktop density) —
   landed as the picker-polish round below.
2. **Glossy selected-plate top band at 4.45:1 vs the 4.5 strict floor: ACCEPTED by the
   director as-is.** Recorded as a sanctioned deviation on the glossy-touch package
   (white text everywhere on the selected plate; median 7.31:1; the 4.45 band is the
   top two glyph rows under the gel highlight). The deeper-BLUE_DEEP art option stays
   available if it ever bothers anyone.
3. **Text-in-skinned-circle-buttons: ACCEPTED as designed** — icons are the answer for
   discs under heavily-inset skins; the three text options in RS-CIRCLE-P1 are closed
   without action. Round declared done by the director.

## Picker polish — the two director items (2026-07-26)

Disposition 1 above, landed at source stamp `82f165e1-1800164`, suite **1839 →
1848**, gate re-run **PASS exit 0** with its library-suite floor raised to 1848.
Everything below is `examples/gallery/client/theme_picker.luau` except one
library defect the work uncovered. The uniform 3-column grid is untouched: every
chip's **width is byte-identical** to the round-9 numbers under every package,
which is the property that decides the column count.

### 1. Negative space between the grid and the Day/Night row

The picker asks two questions — which package, then which of that package's
themes — and they were one `xs` step apart, the same order as the gap *between*
chips, so the Day/Night row read as one more row of the grid.

The panel's own gap is now `m` (`theme_picker.SECTION_GAP`), and the caption +
grid are grouped into one `Choose` container that keeps the tight `xs` so the
title stays attached to the grid it labels. A container gap, in the space ladder,
not a spacer: it moves with the installed package like everything else in the
picker.

| package | grid → theme row, before | after | the grid's own row gap |
|---|---|---|---|
| studio-neutral | 4 | **16** | 4 |
| classic-desktop | 2 | **8** | 4 |
| sci-fi HUD | 4 | **14** | 4 |
| glossy-mobile | 6 | **18** | 4 |

### 2. Chip height from the active package's control metric

**What was actually wrong.** The chip's `minMax { min = controlSizes.compact.height }`
floor never decided anything. A Button's default padding is
`controls.button.padding` — 12 px on **all four** sides, and no reference package
authors it — so every chip sat 24 px above its own line box: under
classic-desktop a 39 px chip on a package whose whole control ladder tops out at
32.

**The fix** is one authored `padding`: vertical `xs` (the package's own smallest
step), horizontal still `controls.button.padding` **by name**, so the height falls
to the control metric and the measured width — the thing round 9's intrinsic
uniform columns reason about — does not move a pixel. The floor stays a floor: a
label that wraps still grows its chip, which is round 9's defect and is re-guarded
headlessly.

Live, desktop 1233x1067, native StyleSheets on, each package installed by a real
injected click on its own chip:

| package | chip before | chip after | = its `controlSizes.compact.height` | columns | unfit labels | overlaps | chips outside the panel |
|---|---|---|---|---|---|---|---|
| studio-neutral | 196x46 | **196x36** | 36 | 2 | 0 | 0 | 0 |
| classic-desktop | 148x39 | **148x22** | 22 | 3 | 0 | 0 | 0 |
| sci-fi HUD | 198x45 | **198x32** | 32 | 2 | 0 | 0 | 0 |
| glossy-mobile | 179x48 | **179x44** | 44 | 2 | 0 | 0 | 0 |

Desktop packages get desktop-density chips; the touch package keeps its 44 px
target exactly. **Hit geometry is untouched** — under classic-desktop the chip
paints 22 px and its hit rect is still the 44 px floor (12 hit expanders,
`minHitHeight = 44`), because the expander was never the plate.

Headless, all nine reference packages including the nine-slice ones (the skinned
chips land on `compact` + the skin's own `contentInsets`, which is the room the
carved border needs): 46→36, 39→22, 45→32, 48→44, 63→51 (glossy-touch), 45→25
(compact-pointer), 67→51 (fantasy-ornate), 76→60 (pixel-quest), 63→47
(fantasy-parchment) — **width unchanged in all nine**.

### The library defect this uncovered

`padding = { top = "xs" }` is an ordinary authored value on every container the
schema declares, **Button included** — and the adapter's engine write handed the
table straight to `UDim.new`, which errors on a table. A crash on documented
input, on the paint seam, on every solve, reachable by any consumer who ever
wanted a tighter row. `screen_target` now spends the horizontal pair (the engine
inset is horizontal by construction — the label centres inside the box the solver
reserved) and reads an unwritten side as 0, exactly as `solver.sides` measured it.
Live proof: `UIPadding` reads `L/R = 12, T/B = 0` on every chip under all four
packages, and the session log is clean.

**Evidence:** `rs-picker-polish.json` (preflight, four-package trace, before/after
per package) + 7 headless cases in `tests/gallery_theme_picker.spec.luau` (the
real overlay mounted through the real presenter onto a headless target under each
package's snapshot — chip box, A/B against the old 12 px padding, line-box fit
across all nine packages, the wrap floor, the section gap, the caption grouping,
and that every value is a metric NAME) + 2 in `tests/renderer.spec.luau` for the
per-side padding seam. `check_flat_baseline` PASS unmoved (1506 flat nodes, 0
rect/hit/class changes); `check_docs_cli` PASS.
**Captures:** `RS-PICKER-POLISH_desktop_classic.png`,
`RS-PICKER-POLISH_desktop_scifi.png` — both taken at the final stamp with
`STUDIO_WINDOW_MATCH="Place1"`. (The four-package drive above ran at
`903e51e0-1800163`; the source was re-synced after a one-word comment
correction and classic-desktop and sci-fi were re-driven at the final stamp
with byte-identical geometry.)

---

## Director round, third pass (live review, 2026-07-26) — findings 12 to 14

Three reported defects, all three root-caused live before a line of source moved,
all three fixed and proven live. **Two of the three root causes are not the ones
the report named**, and both are recorded that way below rather than quietly
re-aimed: finding 12's illegible label never went through the `$OnSelected`
resolver at all, and finding 13's row never reflowed.

**Live sessions:** Studio `0.731.0.7310942`, Play Solo (Client), viewport
`1233x1067`, Device Emulator OFF, native StyleSheets on, the director's own
attribute state (`LuauUI_Scenario = ""`, `LuauUI_ThemePicker = true`) — restored
at the end of the round. Pre-fix stamp `82f165e1-1800164`, post-fix stamp
**`a6383ae2-1811312`**. Suite 1848 -> **1868**. Evidence:
`rs-dir12-13-14.json`. (The first post-fix drive ran at `aa7e7d6a-1811320`; the
source was then run through stylua and every live claim below was re-observed
and re-captured at the final stamp with byte-identical geometry.)

### 12. The Fantasy Ornate selected row's label was invisible

**Reported:** a selected row is a dark plum plate with gold corners and the label
cannot be read against it. **Hypothesis in the report:** the round-8b
`$OnSelected` resolver pairs against `extra.controlSelected`, and ornate's
selected ART is not the colour that token claims.

**The hypothesis names a real lie. It is not the seam that fired.** Measured at
the pre-fix stamp on the node itself
(`…/Choose/Packages/P_fantasy-ornate`):

| | measured |
|---|---|
| tags | `luau-interactive, luau-pointer-live, luau-skinned-control, **luau-surface-accent**` |
| `luau-selected` | **absent** — `$OnSelected` never resolved on this node |
| `GetStyled TextColor3` | `rgb(32, 22, 8)` = **`$OnAccent`** |
| `GetStyled BackgroundColor3` | `rgb(219, 180, 103)` = `$Accent` — the fill the surface promises and the skin never paints |

**Root cause.** The picker's active chip declared `surface = "accent"`, and a
surface is a promise about a **fill**. On a skinned package that fill is replaced
by chrome ART, which `Chrome role — accent` only **multiplies** toward the accent
(`$ChromeTintAccent`) — and a multiply can never lighten — while
`Chrome text — accent` still paints the lifted label `$OnAccent`. Grand Hall's
`onAccent` is near-black and ornate's control art samples `rgb(55, 27, 44)`:
**1.06:1**. The pairing was computed against a colour the node does not paint,
exactly as the report says — one surface earlier than the report guessed.

**Fix — the example says what it means.** The active chip declares `selected`,
the framework's own state for "this is the chosen row", and keeps
`surface = "chip"`. `chrome_slots.classify` then routes it to the package's
`selection` slot, so ornate paints the plate it cut for exactly this, the art
takes `$ChromeTintSelected`, and the label pairs through `$OnSelected` — which
`selectedContentColor` resolves against `extra.controlSelected`, the number the
report is about.

**And the packages had to tell the truth**, which is the director's ask,
generalized to every package whose selection slot is image art. `tools/sample_plates.py`
samples the alpha-weighted mean of each asset's **nine-slice centre rect** — the
pixels a lifted label is read against — into `assets/themes/plate-samples.json`
with the file's sha256 beside it, and the reference-package sweep re-hashes every
PNG so a re-cut texture that was never re-sampled fails as a test instead of
drifting. The band is **0.12 in unit RGB** (~31/255) against the sample
**multiplied by that theme's `$ChromeTintSelected`** — what a player sees, and
what the framework paints in the art's place when it is absent.

| package / theme | declared before | the art actually paints | distance | now |
|---|---|---|---|---|
| **fantasy-ornate / Grand Hall** | `rgb(118, 90, 44)` | `rgb(38, 74, 50)` | **0.321** | corrected |
| **fantasy-ornate / Crypt** | `rgb(74, 92, 96)` | `rgb(33, 75, 58)` | **0.229** | corrected |
| **pixel-quest / Quest** | `rgb(215, 168, 96)` | `rgb(163, 148, 71)` | **0.240** | corrected |
| **compact-pointer / Aqua** | `rgb(206, 224, 248)` | `rgb(163, 191, 230)` | **0.225** | corrected |
| glossy-touch / Sky | `rgb(20, 81, 194)` | `rgb(27, 89, 201)` | 0.051 | already true (round 8b measured it live) |

Four of the five were fictions; the one that was honest is the one a previous
round had already measured against the running engine. **No pairing decision
moved** — the resolver picks the same role it picked before, and it now clears
the floor against the art rather than against the claim: compact-pointer
content 8.9, ornate Crypt content 7.8, ornate Grand Hall content 8.3,
glossy-touch onAccent 6.3, pixel-quest onAccent 6.0. All five are pinned, so a
silent flip shows in a diff.

**The class the root cause exposed is CENSUSED, with numbers.** `$OnAccent` over
a skinned control's art is unearned for every package, not only ornate. The
sweep computes it against each package's sampled control plate and gates the
honest half — *some* content role must clear 4.5:1:

| package / theme | onAccent | content |
|---|---|---|
| fantasy-ornate / Grand Hall | **1.06** | 14.09 |
| fantasy-ornate / Crypt | **1.09** | 13.84 |
| pixel-quest / Quest | **2.43** | 6.11 |
| compact-pointer / Aqua | **3.64** | 4.60 |
| glossy-touch / Sky | **4.57** | 3.65 |
| fantasy-parchment / Daylight | 5.29 | 2.47 |
| fantasy-parchment / Candlelight | 5.28 | 2.68 |

Which role the framework picks is **not** asserted, because nothing in the
library or the examples enters that combination any more — and because the two
parchment rows are the reason a resolver cannot be written from the palette
alone: one art set serves both themes, so a package's `extra.control` is
deliberately not the art's colour in the dark one. Fixing that needs the sampled
plate inside the package, and that is a decision for the director rather than a
change to take under a review finding.

**Live proof (stamp `a6383ae2-1811312`, fantasy-ornate / Grand Hall).** The
selected chip carries `luau-selected` + `luau-skinned-selection`, resolves
`Image = rbxassetid://74679464509477` (`ornate_selection_selected` — the gilded
emerald plate with its four ruby cabochons) where every sibling resolves
`…101901876687967` (the plum velvet default), and its lift resolves
`TextColor3 = rgb(246, 234, 206)`, the theme's cream content, with
`TextFits = true`. The state is a different **picture**, not a tint, and the
label is legible on both.
**Capture:** `RS-DIR12_picker_desktop_fantasy-ornate_selected-legible.png`.

### 13. Toggling a value changed the control's size, and the label wrapped

**Reported:** flipping Music on/off under classic-desktop resizes the row, and
the label then wraps `"Musi c"`. **Suspected in the report:** round 9's
`toggleRowPadding` / label-box fix, or the palette path's on/off swap.

**Measured, and neither.** There is no solved reflow, and round 9 did not
introduce one:

- `value` dirties `paint` + `semantics` and never `measure` — now asserted at the
  schema, where it is decided;
- headless, a flip is **byte-stable across all nine reference packages** (every
  rect of a settings-shaped screen, three flips each);
- live, `setToggle:off|on|off` under all nine packages left the toggle box, its
  label box, its drawn bounds and `TextFits` **identical in every one**.

**What does move is the press affordance.** `extra.pressedScale` = `0.985` puts a
`UIScale` on the control while the press animates — measured live under
classic-desktop at `104x28 -> 102.75x27.66 -> 102.44x27.58 -> 103.70x27.92 ->
104x28` over ~0.5 s, with the label re-rasterizing at the scaled size
(`TextBounds 28x13 -> 25.5x12`). It is paint, it is symmetric, and every Button
has it. **It is also a guaranteed one-pixel perturbation of the label's box on
every single flip** — which is what meets the actual defect.

**The actual defect: the label column has ZERO slack, and the label was allowed
to break a word.** The reserved column is `ceil(the engine's own measurement of
the same words at the same size)` and the engine draws exactly that, so under
four of the nine reference packages the column and the drawn bounds are equal to
the pixel — Studio Neutral **35/35**, classic-desktop **28/28**, and the
ValueProbe's "Candlelight" at **67/67** (neutral) and **73/73** (sci-fi). With
`TextWrapped = true`, a one-pixel shortfall does not clip a pixel; it breaks the
word.

**Isolation probe, one variable, live.** Perturbing the classic-desktop Music row
to `103x28`:

| | `TextBounds` | reads |
|---|---|---|
| `TextWrapped = true` (the shipped draw mode) | **22.5 x 26** — two lines | `Musi` / `c`, second line clipped by a 28 px row |
| `TextWrapped = false` | **22.5 x 13** — one line | one line, ellipsized |

That is the director's `"Musi c"` exactly, reproduced and then removed by
changing one property.

**Fix, at both seams so they cannot disagree.** The adapter draws the toggle's
label `TextWrapped = false` + `TextTruncate = AtEnd` — one line, ellipsize where
the row cannot grow, never a mid-word break — and the solver **measures** one
line too, through a new `singleLine` layout-node flag that measures the text
unbounded and clamps the result to the offer. A single-line paint with a
two-line measure is the same class of defect rounds 3 and 9 landed on from the
other side; it is closed here by construction.

**Live proof (stamp `a6383ae2-1811312`, classic-desktop).** Resting row
`16,77 104x28`, `Label 28x28 @ TextSize 13`, bounds `28x13`, `TextFits = true`,
`TextWrapped = false`, `TextTruncate = AtEnd`, **one line**. Four real injected
clicks: **11 rects compared**, and in the ON state exactly two differ — neither
of them solved geometry — the Knob's own
`66,81 -> 86,81` travel (the switch's two stops, an adapter-owned bespoke
position) and the sibling `/GallerySettings/Status` re-measuring `112x17 ->
109x17` because its own **text** changed.

**And the invariant is now instrumented on the walk itself:** the
`theme_authoring` `setToggle` step returns a `noReflow` verdict — six watched
paths diffed before and after — plus the label's bounds, wrap mode, truncation
and line count, so a matrix row reads the invariant instead of joining two dumps.

**Captures:** `RS-DIR13_toggle-label_before-after_classic-desktop.png` (the same
103x28 box twice — `Musi`/`c` above, one ellipsized line below) and
`RS-DIR13_toggle_desktop_classic-desktop_one-line.png` (the shipped row at its
real box).

### 14. The picker grid's rows were cramped

**Reported:** more vertical space between rows, especially studio-neutral and
compact-pointer.

**Root cause, measured live.** A grid's **column** pitch is
`innerWidth / columns`; its **row** pitch **is** the gap. Under studio-neutral at
`1233x1067` the ten 196x36 chips sat in a 544 px grid with rows **4 px** apart
and columns **78 px** apart. One number was doing two jobs whose consequences are
not comparable, and the literal was there to protect the approved column count
(`minColumnWidth` divides by `minCol + gap`) — so opening the rows meant risking
the ruling.

**Fix.** `rowGap` on `UI.Grid`: resolved through the same space ladder as `gap`,
**defaulting to `gap`** so every existing grid in the library, the examples and
the fixtures is byte-unchanged, and never entering the column arithmetic. The
picker spends `"s"` for its rows and keeps the literal `4` for its columns.

`"s"` rather than `"xs"`, and the reason is a measurement: `xs` is **2** under
classic-desktop and compact-pointer, which would have made the packages the
director named *tighter* than the literal they were already cramped at.

| package | row gap before | after |
|---|---|---|
| **studio-neutral** | 4 | **8** |
| classic-desktop | 4 | 4 |
| **compact-pointer** | 2 | **6** |
| sci-fi HUD | 4 | **8** |
| glossy-mobile / glossy-touch | 4 | **10** |
| fantasy-ornate / fantasy-parchment | 4 | **8** |
| pixel-quest | 4 | **8** |

**Live proof, desktop 1233x1067, each package installed by a real injected click
on its own chip:**

| package | row gap | chip box | columns | unfit labels | box overlaps | chips outside the panel |
|---|---|---|---|---|---|---|
| studio-neutral | **8** | 196x36 (unchanged) | 2 | 0 | 0 | 0 |
| compact-pointer | **6** | 156x25 | 3 | 0 | 0 | 0 |
| fantasy-ornate | **8** | 177x43 | 2 | 0 | — | — |

**Captures:** `RS-DIR14_picker_desktop_studio-neutral_rowgap.png`,
`RS-DIR14_picker_desktop_compact-pointer_rowgap.png`.

### What this round changed for FLAT themes

`check_flat_baseline` stays **PASS, byte-unchanged: 1506 flat nodes, 6
characterized prop deltas, 4 characterized new nodes, 1 characterized added prop
key, 0 rect / 0 hit-rect / 0 class changes.** Every library change is a no-op
under Studio Neutral by construction: `rowGap` falls back to `gap` when absent
and no fixture declares one; `singleLine` is set only on a Toggle, and a
baseline Toggle's label was already one line; the palette corrections touch four
example packages and no flat theme.

**One visible change is NOT a no-op and is not hidden:** the gallery picker's
active chip. It used to be the accent fill with `$OnAccent` text and is now the
theme's selected row (`$ControlSelected` + `$OnSelected`) — under Studio Neutral
`#2d3a5c` with cream text instead of the accent blue. It is the honest idiom (the
active row is a selection, not a primary action) and it is what makes ornate
legible, but it is a look the director approved in its previous form and may want
to re-judge.

### The regressions this round adds

**Twenty specs, written red-first and proven red against the pre-fix tree.**
`tests/layout_vocabulary.spec.luau`: `rowGap` opens the rows without moving a
column, counts in the grid's own measured height, is byte-identical to `gap`
when absent, cannot reach the column count, and is a spacing metric at the
boundary (5). `tests/gallery_theme_picker.spec.luau`: the row gap is the active
package's `s` step in all nine reference packages, never narrower than the
literal it replaces, leaves the chip box and column count A/B-identical, spends a
metric name for rows and a literal for columns, and keeps the grid's own height
honest (5). `tests/renderer.spec.luau`: a value flip is byte-stable across every
reference package, `value`'s dirty classes are asserted at the schema, the
adapter draws the toggle label single-line with an end ellipsis, the solver
reserves one line, and a long label still grows a row that can grow (5).
`tests/theme_reference_packages.spec.luau`: every sampled PNG re-hashes, every
image-selection package declares its art's colour, the resolved pairing clears
4.5:1 **against the art** with all five pinned, the accent-over-art census with
its seven pinned rows and its floor, and the picker's active row is a selection
(5).

### End sweep at this stamp

`./run-tests.sh` **1868 passed** (floor raised 1848 -> 1868);
`check_flat_baseline` PASS unmoved; `check_docs_cli` PASS; `check_prop_parity`
PASS (22 classes, 333 properties); `check_registration` PASS; `check_boundary`
PASS (66 files); `check_theme_drift` PASS; `bench` PASS; the RascalRally game
suite **2423 passed**; and `lune run tools/lune/gate rich-skinning-v2`
**PASS, exit 0**.

### Honesty ledger for this round

- **The desktop viewport only.** Every row ran at 1233x1067 with the Device
  Emulator off. The phone, tablet and console rows of these three behaviours are
  not driven.
- **Finding 12's pre-fix appearance is recorded by MEASUREMENT, not by a
  capture.** The first live session ran at the pre-fix stamp before the fix
  existed and no before/after pair was taken there; what is stored is the styled
  read (`TextColor3 = rgb(32, 22, 8)`, no `luau-selected` tag, the control art)
  and the after capture.
- **Finding 13's before/after is an A/B of the two DRAW MODES at the same
  one-pixel-short box**, not a capture of a shipped defect: at the real solved
  box the shipped label reads "Music" and always did. What it proves is that the
  mid-word break is gone and that the perturbation the press affordance applies
  on every flip can no longer produce it.
- **`TextTruncate.AtEnd` costs more than one glyph.** At a 27 px box a 28 px
  "Music" reads "Mu…". That is the ellipsize half of the ruling; the grow half is
  the row's own rules, and at the real box nothing truncates.
- **The accent-over-skinned-art pairing is censused, not fixed.**
  `Chrome text — accent` still promises `$OnAccent` over art a multiply can only
  darken. glossy-touch/Sky is the one reference theme where neither content role
  clears 4.5 against its own accent-tinted control plate (onAccent 4.57 clears;
  content 3.65 does not — so the framework's choice is the right one there).
  Fixing the class properly needs the sampled plate inside the package, because
  fantasy-parchment proves the palette alone cannot answer: one art set serves
  both its themes.
- **The picker's active chip changed colour under flat themes** (see above).
- **The compact-pointer capture has the CoreGui player list** overlapping the
  active chip's top-right corner; the geometry trace beside it is complete.
- **stylua reformatted two library files this round did not otherwise change** —
  `src/tokens/chrome_slots.luau` and `src/tokens/sheet_model.luau`. The
  repository carries no stylua config and no gate check runs it, so that pass was
  not part of this repo's discipline. It is whitespace only, and the full suite,
  `check_flat_baseline`'s 1506-node byte compare, every other check, the game
  suite and the gate all ran green after it — but it is an unrequested diff and
  is recorded as one.
