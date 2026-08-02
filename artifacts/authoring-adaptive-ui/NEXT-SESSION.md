# Next session — start here

**Context:** LuauUI roadmap **Step 3** (`authoring-adaptive-ui`).
Gate: **19 PASS, 1 PENDING, no release-blocking check open.** Suite **956** green.
The single PENDING is `physical-and-human-rows` — P1..P5, which automation can never close.

**Since this file was written, the exact-text-measurement milestone landed
(2026-07-24, stamp `76b3b386-851491`).** Text boxes are now measured per WORD by
the engine instead of estimated: worst over-reservation on any intrinsic label is
**0.5px** across all five device rows, down from ~35px, and `TextFits` holds on
every painted node. The five-view matrix was re-driven and re-captured at that
stamp — so **the capture files below are the new ones**, and §1's note about
ragged 68/89/68 action buttons is superseded (they are equal-height everywhere,
and where they are 68px the engine genuinely draws two lines).

Two things that milestone found are worth carrying:
`GetTextBoundsAsync` answers **wrongly but stably** during the first moments of a
session, so a cached width taken at boot is permanently wrong unless it is
re-asked later; and tightening the measurer **exposed a spacing bug it had been
hiding** (the Slider's thumb landed on the final "s" of "Brightness"). Full
write-up: `docs/plans/text-measurement-milestone.md` §"What actually happened".

Work from `GameStudio/ui/LuauUI`. Read `SUMMARY.md` for what landed, `HANDBACK.md` for
the resume detail. This file is only the plan for the next hour.

---

## 0. What last session did

The preferred-text / reduced-motion sweep ran, the missing captures were taken, and taking
them found a broken fixture. You chose to fix it and re-baseline, so that happened too.
Write-up: `artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json`.

**The compression result is now defined** — and it was none of the three options: text
always wraps and never clips, but **containers do not compress at all**. Per-shape table
in the artifact under `theCompressionResult`. `reducedMotion` swept as a regression:
geometry byte-identical, which is the correct answer.

**Five MAJOR framework defects found and fixed**, every one invisible to the suite that was
green at the time, every one with a regression proven to fail against the pre-fix source:

| | What was wrong |
|---|---|
| **PT-1** | A text preference **below 1** reserved a box *smaller* than the engine was told to paint. 10 nodes clipped live at `preferredTextSize=0.5`. Measure now takes `max` of the measure and paint scales. |
| **PT-2** | Stack overflow was **completely silent** — content painted over its siblings and off the viewport with no clip, no scroll, no diagnostic. Now reported with node and exact px. Hidden `ViewThatFits` candidates exempt (they paint nothing). |
| **PT-3** | `report()` carried geometry but never the solver's complaints about it. Now returns `diagnostics` — which is how PT-2 became visible per-row. |
| **PT-5** | An hstack measured **every** child at its full inner width, including `fill` children that only get a share. Under-reported height → a scroll canvas that could not reach its own tail (**151px unreachable** on phone landscape; a column reporting 39px while holding 77px of text). Both the measure and arrange passes had it. |
| **PT-6** | An `aspect` box paired with `width = fill` measured **0×0**, because `fill` reports *content* at measure time and a Box has none. Cost exactly the 185px media box on phone portrait. |

**The fixture is fixed and the matrix is re-baselined.** The body now sits in a
`UI.ScrollView` taking `fill` with the action bar pinned outside it. All five device rows
re-driven and re-captured at stamp `0cd49ad1-814757`. In every row: the action bar is
pinned below the scroll region and on screen, the canvas reaches the full content extent,
the solver reports **zero** diagnostics, the 44px hit floor holds at 46px, and the 16:9
media box measures 1.773–1.779. The gate check `adaptive-fixture-fits-one-screen` re-reads
those rows and fails if any of it regresses — verified by simulating both regressions.

---

## 1. `P5` — the only thing I need from you (5 minutes, from stored captures)

This is now the only open item automation can't close, and the fixture finally fits, so
it is worth looking at. Say whether the adaptive results **read well** — readability,
visual hierarchy, and whether each profile feels right for its platform:

Open these files — they are real PNGs on disk now, in
`artifacts/authoring-adaptive-ui/captures/`:

| File | Profile |
|---|---|
| `D-1_compact-phone-portrait_rest.png` | phone portrait |
| `D-2_compact-phone-landscape_rest.png` | phone landscape |
| `D-3_tablet-landscape_rest.png` | tablet |
| `D-4_desktop-standard_rest.png` | desktop |
| `D-5_console-ten-foot_rest.png` | console (cropped on its right edge by the physical window — judge type and spacing, not framing) |

**One thing to look at specifically:** on phone portrait the three action buttons have
**ragged heights** (68 / 89 / 68px) because their labels wrap to different line counts and
the fixture does not ask for stretch. This is new, and it is the PT-5 fix working — the
buttons used to measure at the full 328px row width and claim 46px, which was too small
for their real wrapped labels. The sizes are now honest; whether they should be equalised
with `align = "stretch"` is a styling call, and it is yours.

Say "fine" or list what to change. Nothing automated can answer this.

---

## 2. `P1`–`P4` — physical hardware, whenever you have it

**Never** closable by emulator or headless evidence, so I will not attempt them. Ordered
checklist in `review-packet.md` §4:

- **P1** real phone: finger-target every control, pan the `ScrollView` for momentum, judge
  the Slider's drag feel.
- **P2** real gamepad: `PreferredInput == Gamepad`, Button A contention, focus navigation
  and `Adjust` at ten-foot distance.
- **P3** real phone: the OS keyboard against the adaptive layouts — and now also the real
  engine text rasterisation at a Large text preference. The sweep proved *reservation*
  correctness; only hardware proves the *glyphs*.
- **P4** low-end Android with MicroProfiler against the versioned budget.

---

## 3. Two smaller things the sweep turned up (no action needed yet)

- **Control rows overflow horizontally at high text offset.** At `preferredTextOffset >= 24`
  the label+track+value hstacks cannot hold their own readouts: `Settings/Volume` by 23px,
  `Settings/Brightness` by 46px, `Hud/Download` by 32px. Each is now named by the new
  diagnostic. Real, but it is the same class as the fixture defect and worth fixing in one pass.
- **`ViewThatFits` cannot distinguish "fits" from "fits horribly".** The action row keeps
  winning to `offset=32` because it genuinely fits in *width* — it just grows 4× taller
  (46 → 144px) rather than falling back to the column. That is SwiftUI's rule as specified,
  so I recorded it as an observation, not a defect. Worth a design conversation if you want
  a height budget to participate in the fit decision.

---

## 4. After Step 3 closes

`docs/plans/luauui-consolidated-roadmap.md` is the entry point. Next is **Step 4** —
turning the existing preview/conformance/perf systems into an honest cross-platform proof
system, and defining (not claiming) the spatial-UI seam. Opus 5 execution goal, prompt in
that file.

Do **not** start Step 4 until `P5` is answered: Step 4's whole premise is honest evidence
labelling, and starting it on an unreviewed Step 3 would undercut that.

---

## 5. Standing rules, now with fresh evidence behind them

- **A green suite is not completion.** All five defects sat under a green suite — 919 tests
  for PT-1/PT-2, 924 for PT-5/PT-6. The tests exercised only the paths the implementation
  happened to take.
- **Take the capture.** The fixture defect was pure geometry sitting in a report nobody
  rendered. Three surfaces had "geometry evidence but no picture", and the picture is what
  broke the row.
- **Fixing the fixture found more framework bugs than the sweep did.** PT-5 and PT-6 were
  only reachable once the content had a bounded container to be wrong inside. A test
  fixture that cannot fail cannot teach you anything.
- **When a check you wrote goes red because you edited the evidence, restore the evidence.**
  Two gate checks broke during the re-baseline because the rewrite dropped strings they
  pin. The fix was to put the substance back, never to loosen the check.
- **A capture is not a trace, and a trace is not a capture.** Rows need both.
- **Never diagnose the framework from a blind instrument.** Check
  `workspace.CurrentCamera.ViewportSize` first; `open -a "RobloxStudio"` is the 1×1 recovery
  that works (`activate` / `set frontmost` / a Play restart do not).
- **Prove a regression fails.** All seven tests added this session were verified to fail
  against the pre-fix source before being kept.

---

## 6. Captures are now real files (new, 2026-07-24)

`tools/studio/capture_viewport.sh <out.png>` writes the Studio viewport to disk.

This exists because **the MCP's `screen_capture` never wrote a file** — it streams the
image to the model and nothing lands in the repo, the Roblox caches, or any temp dir
(verified). Every `capture` id in the acceptance artifacts pointed at nothing, so no
capture this project ever took was openable by a later session. The matrix rows now carry
real paths plus a content hash, and `tools/check_matrix_rows.py` fails the gate if a
capture is missing or does not match its row — negative-proven both ways.

**Safety constraint, do not change:** the tool captures a SINGLE WINDOW by id
(`screencapture -l`), which reads Studio's own backing store. Anything stacked in front of
Studio cannot appear in the output. Do **not** switch it to region (`-R`) or full-screen
capture — those read screen pixels and will pull in whatever else is on the display.

The viewport rect (`3 154 1233 1067` inside a 1928x1297 window) depends on Studio's panel
docking. If the panels move, run the tool with no rect to get the whole window, look at it,
and pass a new rect.

---

## 7. Instrument notes (unchanged, do not re-litigate)

- `StudioDeviceSimulatorService` exposes only `GetDeviceListAsync`, `GetDeviceInfoAsync`
  and `ConfigurationChanged` from `execute_luau`. Every setter is plugin-security. Resolve
  presets through the API, drive their facts through `setEnv`.
- `VirtualInput` is created successfully but exposes **no send methods** at that level. Use
  the MCP's `user_mouse_input` / `user_keyboard_input` — both proven working.
- Loop: `lune run tools/lune/studio_sync`, then run `tools/studio/inject.luau` via the MCP
  in **Edit**, set `workspace.LuauUI_Scenario`, press Play. `report()` now returns
  `diagnostics` alongside geometry — read it.
