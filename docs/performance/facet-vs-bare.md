# Facet versus bare Roblox UI

Generated from `lute run tools/facet bench compare` measurements. Source revision: `c654bf0230c0ff5dcd37e9130adc1daf31f0036b` (working tree included).

These are headless cost-model numbers from Verify's reflection engine double. They do not measure Roblox engine rendering, native layout, text shaping, StyleSheet paint, input delivery or device performance. Visual and live Studio parity are unverified.

Ratios divide by bare. Lower is smaller. Each time sample runs the full iteration count in the table. Heap is retained Luau heap after all iterations, while the scene is still owned, and after teardown. Writes and Created cover only the timed workload's iterations, measured in a separate instrumented pass. Parent changes and attributes are excluded from Writes, as in Compose's comparison.

| Workload | Iterations | Framework | Median time (us) | / bare | Median heap (KiB) | / bare | Teardown (KiB) | Writes | Created | Connections | Deferred |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| main-menu-cold | 1 | bare | 413.625 | 1.00x | 214.000 | 1.00x | 101.000 | 69 | 11 | unavailable | unavailable |
| main-menu-cold | 1 | facet | 1774.458 | 4.29x | 375.000 | 1.75x | 128.000 | 82 | 15 | unavailable | unavailable |
| hud-600-frames | 600 | bare | 18237.875 | 1.00x | 150.000 | 1.00x | 68.000 | 2400 | 0 | unavailable | unavailable |
| hud-600-frames | 600 | facet | 248878.083 | 13.65x | 323.000 | 2.15x | 85.000 | 2400 | 0 | unavailable | unavailable |
| progress-20-120-frames | 120 | bare | 69395.625 | 1.00x | 735.000 | 1.00x | 86.000 | 2400 | 0 | unavailable | unavailable |
| progress-20-120-frames | 120 | facet | 120347.125 | 1.73x | 1379.000 | 1.88x | 64.000 | 2400 | 0 | unavailable | unavailable |
| badges-30-300-updates | 300 | bare | 64061.583 | 1.00x | 458.000 | 1.00x | 118.000 | 9000 | 0 | unavailable | unavailable |
| badges-30-300-updates | 300 | facet | 1034762.917 | 16.15x | 2279.000 | 4.98x | 182.000 | 9000 | 0 | unavailable | unavailable |
| world-markers-50 | 100 | bare | 29999.667 | 1.00x | 1224.000 | 1.00x | 117.000 | 5000 | 0 | unavailable | unavailable |
| world-markers-50 | 100 | facet | 411634.000 | 13.72x | 3433.000 | 2.80x | 210.000 | 5000 | 0 | unavailable | unavailable |
| inventory-100 | 200 | bare | 2291.750 | 1.00x | 3321.000 | 1.00x | 196.000 | 0 | 0 | unavailable | unavailable |
| inventory-100 | 200 | facet | 8773.500 | 3.83x | 13970.000 | 4.21x | 474.000 | 0 | 0 | unavailable | unavailable |
| inventory-500 | 200 | bare | 1291.583 | 1.00x | 15519.000 | 1.00x | 0.000 | 0 | 0 | unavailable | unavailable |
| inventory-500 | 200 | facet | 7010.042 | 5.43x | 68154.000 | 4.39x | 1710.000 | 0 | 0 | unavailable | unavailable |
| shop-filter-200 | 10 | bare | 4052.417 | 1.00x | 2325.000 | 1.00x | 145.000 | 2010 | 0 | unavailable | unavailable |
| shop-filter-200 | 10 | facet | 7074.833 | 1.75x | 5342.000 | 2.30x | 249.000 | 2032 | 14 | unavailable | unavailable |
| virtual-scroll-2000 | 100 | bare | 19388.375 | 1.00x | 375.000 | 1.00x | 68.000 | 4600 | 0 | unavailable | unavailable |
| virtual-scroll-2000 | 100 | facet | 112043.917 | 5.78x | 2265.000 | 6.04x | 0.000 | 7849 | 54 | unavailable | unavailable |
| chat-append-500 | 500 | bare | 17254.000 | 1.00x | 1116.000 | 1.00x | 159.000 | 4000 | 500 | unavailable | unavailable |
| chat-append-500 | 500 | facet | 453015.833 | 26.26x | 5568.000 | 4.99x | 209.000 | 47100 | 1500 | unavailable | unavailable |
| card-collection-60 | 1 | bare | 11223.167 | 1.00x | 3287.000 | 1.00x | 241.000 | 2350 | 543 | unavailable | unavailable |
| card-collection-60 | 1 | facet | 47519.208 | 4.23x | 9959.000 | 3.03x | 257.000 | 3670 | 723 | unavailable | unavailable |
| mixed-scroll-300 | 100 | bare | 380.917 | 1.00x | 5475.000 | 1.00x | 246.000 | 100 | 0 | unavailable | unavailable |
| mixed-scroll-300 | 100 | facet | 413.167 | 1.08x | 19878.000 | 3.63x | 31.000 | 100 | 0 | unavailable | unavailable |
| settings-17-values | 17 | bare | 183.583 | 1.00x | 700.000 | 1.00x | 143.000 | 25 | 0 | unavailable | unavailable |
| settings-17-values | 17 | facet | 1408.000 | 7.67x | 3064.000 | 4.38x | 223.000 | 56 | 0 | unavailable | unavailable |
| text-input-200 | 200 | bare | 798.958 | 1.00x | 54.000 | 1.00x | 47.000 | 220 | 0 | unavailable | unavailable |
| text-input-200 | 200 | facet | 1824.375 | 2.28x | 197.000 | 3.65x | 81.000 | 220 | 0 | unavailable | unavailable |
| button-feedback-50 | 3 | bare | 1104.875 | 1.00x | 736.000 | 1.00x | 96.000 | 150 | 0 | unavailable | unavailable |
| button-feedback-50 | 3 | facet | 194.125 | 0.18x | 1345.000 | 1.83x | 119.000 | 0 | 0 | unavailable | unavailable |
| stepper-segments-100 | 100 | bare | 1684.583 | 1.00x | 218.000 | 1.00x | 121.000 | 200 | 0 | unavailable | unavailable |
| stepper-segments-100 | 100 | facet | 31763.708 | 18.86x | 774.000 | 3.55x | 179.000 | 800 | 0 | unavailable | unavailable |
| dialog-50-cycles | 100 | bare | 11164.042 | 1.00x | 184.000 | 1.00x | 188.000 | 2150 | 400 | unavailable | unavailable |
| dialog-50-cycles | 100 | facet | 189205.833 | 16.95x | 1113.000 | 6.05x | 1075.000 | 9350 | 1800 | unavailable | unavailable |
| toast-stream-100 | 200 | bare | 18001.542 | 1.00x | 151.000 | 1.00x | 147.000 | 1600 | 300 | unavailable | unavailable |
| toast-stream-100 | 200 | facet | 264154.917 | 14.67x | 657.000 | 4.35x | 570.000 | 7800 | 1500 | unavailable | unavailable |
| tabs-5-100-switches | 100 | bare | 2015.750 | 1.00x | 219.000 | 1.00x | 94.000 | 622 | 4 | unavailable | unavailable |
| tabs-5-100-switches | 100 | facet | 31449.875 | 15.60x | 1432.000 | 6.54x | 141.000 | 970 | 116 | unavailable | unavailable |
| radial-50-cycles | 100 | bare | 13685.250 | 1.00x | 162.000 | 1.00x | 139.000 | 2100 | 300 | unavailable | unavailable |
| radial-50-cycles | 100 | facet | 681627.167 | 49.81x | 962.000 | 5.94x | 846.000 | 25750 | 3600 | unavailable | unavailable |
| navigation-5-20-cycles | 200 | bare | 19417.833 | 1.00x | 220.000 | 1.00x | 176.000 | 3300 | 500 | unavailable | unavailable |
| navigation-5-20-cycles | 200 | facet | 220497.125 | 11.36x | 1279.000 | 5.81x | 1016.000 | 11840 | 1600 | unavailable | unavailable |
| leaderboard-100 | 6 | bare | 2139.625 | 1.00x | 4157.000 | 1.00x | 224.000 | 900 | 0 | unavailable | unavailable |
| leaderboard-100 | 6 | facet | 36190.208 | 16.91x | 46672.000 | 11.23x | 339.000 | 2103 | 0 | unavailable | unavailable |
| theme-swap-200 | 10 | bare | 4735.458 | 1.00x | 2344.000 | 1.00x | 133.000 | 2000 | 0 | unavailable | unavailable |
| theme-swap-200 | 10 | facet | 35252.500 | 7.44x | 11755.000 | 5.01x | 446.000 | 0 | 0 | unavailable | unavailable |
| heavy-screen-20-cycles | 20 | bare | 352521.167 | 1.00x | 1969.000 | 1.00x | 1976.000 | 60260 | 8080 | unavailable | unavailable |
| heavy-screen-20-cycles | 20 | facet | 2020165.958 | 5.73x | 458.000 | 0.23x | 464.000 | 92260 | 16060 | unavailable | unavailable |
| tile-transfer-20 | 20 | bare | 151.167 | 1.00x | 410.000 | 1.00x | 98.000 | 0 | 0 | unavailable | unavailable |
| tile-transfer-20 | 20 | facet | 26431.125 | 174.85x | 2679.000 | 6.53x | 280.000 | 1114 | 160 | unavailable | unavailable |

## Method

The table combines 19 valid workload pairs from one full command run and six valid pairs from filtered command runs. Each pair passed CPU calibration. Both full command runs stopped when CPU calibration failed.

The command runs the registered Verify parity specs before any timing. Each pair checks initial and intermediate observations after every iteration, then releases its nodes and connections. Parity covers the observations declared by each workload. It does not establish pixel or input parity in Roblox.

Verify Benchmark collects nine time samples after two complete warm-up samples. Each sample gets a fresh scene. Runtime, control factory, data and initial mount setup are outside timing, except for the cold-mount and lifetime workloads. Lane order alternates by workload. The existing CPU yardstick runs before and after each pair. Only pairs that pass calibration appear in this table. Failed measurements remain in their JSON reports.

Three separate heap lifecycles use Verify's `gc-witness-low-water/2` estimate with eight collection witness cycles per endpoint. The common runtime, control factory and engine context exist before the heap baseline. The table uses the median retained mounted and teardown deltas. This is a low-water estimate, not an exact full collection or Roblox Instance memory reading. Cold-mount preparation leaves the scene empty until its one timed iteration. The heavy-screen workload ends with no screen mounted; its heap column is the retained endpoint after 20 complete lifetimes.

The pinned Verify API exposes `environment.observe`, `liveObjects` and `liveConnections`. It does not expose cumulative signal-subscription or deferred-task counts. These two metrics are unavailable, not zero. No replacement counter mechanism or vendor edit is included. Those columns require an upstream Verify API and a new pin.

## Workload scope

Facet uses public controls and Compose ownership. Bare uses direct Instances, native layout objects, native editing, plain connections and Luau state. Common fixture setup uses the existing `bench/native_app.luau`. Bare does not mount through Compose. Facet keeps its extra measurement, accessibility, focus, modal, selection and cancellation policy. Bare includes only the controls and state needed for the measured route. Extra Facet policy is part of its reported cost.

The pairs match task content and selected state observations. Their complete instance trees and layout properties are not equal: Facet has additional wrappers and control chrome. Most scenes use the existing benchmark's unstyled controls. The theme case observes native StyleSheet tokens and compares them with bare text colours; this fixture does not resolve paint. Button feedback sets native GuiState; it does not measure hover or press rendering. Radial geometry and drag previews are additional Facet behavior. The transfer case exercises the gamepad pickup/drop route, not pointer hit testing. These limits prevent a claim of equal rendered screens.

The progress workload supplies the same linear values to 20 bars over 120 frames. Bare writes each frame directly. Dialog, toast and navigation steps advance the fixture clock; their native paint transitions are not rendering evidence. The filter retains rows and changes visibility. The chat log retains only the last 100 message nodes. The virtual-list case checks the row window, including overscan, during 100 offsets across 2,000 rows.

- `main-menu-cold`: Mount a background, title, six actions and footer; runtime and control-factory setup is excluded.
- `hud-600-frames`: Update health fill, ammo, currency and timer once per simulated frame.
- `progress-20-120-frames`: Drive 20 measured progress fills with per-frame values; both lanes use the same linear frame sequence.
- `badges-30-300-updates`: Update all 30 notification counts, 300 times; badges keep their native text nodes.
- `world-markers-50`: Update the labels of 50 native BillboardGui markers anchored to Parts.
- `inventory-100`: Select among 100 retained slots 200 times; each slot has an activation target and selected state.
- `inventory-500`: Select among 500 retained slots 200 times; each slot has an activation target and selected state.
- `shop-filter-200`: Edit a native TextBox with ten queries, including empty and no match; retain the 200 catalog rows and set their visibility.
- `virtual-scroll-2000`: Scroll a fixed 40-pixel row window from top to bottom; the bare lane keeps a small reusable row pool.
- `chat-append-500`: Append 500 keyed messages; remove the oldest when the log exceeds 100 rows.
- `card-collection-60`: Mount 60 cards with the same artwork, item title and price caption.
- `mixed-scroll-300`: Scroll 300 retained mixed rows: 100 text rows, 100 action buttons and 100 text cards.
- `settings-17-values`: Change each of ten toggle, four slider and three segmented-picker model values; native value readouts show the result.
- `text-input-200`: Type 200 characters through a native TextBox; validation rejects punctuation and accepts letters.
- `button-feedback-50`: Set native GuiState to Hover, Press and Idle on 50 buttons; native StyleSheet transitions are outside this double's paint model.
- `stepper-segments-100`: Change a bounded quantity and a segmented choice 100 times through the application model.
- `dialog-50-cycles`: Open a confirmation dialog, then activate Confirm and close it, 50 times.
- `toast-stream-100`: Show 100 one-shot result toasts and let each auto-dismiss after its four-second display duration.
- `tabs-5-100-switches`: Switch 100 times among five peer pages; retain each visited page and its content.
- `radial-50-cycles`: Open a four-command radial menu, select Wave and close, 50 times; bare positions four native buttons around the same centre.
- `navigation-5-20-cycles`: Push five child pages and pop them, 20 times; root has no Back action and covered pages remain retained.
- `leaderboard-100`: Sort 100 retained player rows by name, score and wins; replace every score after each sort.
- `theme-swap-200`: Swap two neutral packages on 200 buttons; Facet updates StyleSheet tokens while bare writes the matching text and plate colours.
- `heavy-screen-20-cycles`: Mount and dispose 200 action controls and 200 text rows, 20 complete lifetimes.
- `tile-transfer-20`: Pick up 20 tiles with gamepad activation and drop each into the second grid; Facet also installs pointer drag and cancellation policy.

## Run

```sh
lute run tools/facet bench compare --verify
lute run tools/facet bench compare
lute run tools/facet bench compare --filter inventory --out artifacts/inventory-comparison
```

The default output directory is `artifacts/facet-vs-bare`. It contains `report.json` and `comparison.md`. A successful unfiltered measurement also writes this page. A filtered run does not replace this page. The manual GitHub workflow uploads the raw report and Markdown.

Reference method: [Compose framework comparison](https://github.com/voidmeld/compose/blob/main/docs/framework-comparison.md) and [manual comparison](https://github.com/voidmeld/compose/blob/main/docs/benchmarks.md#manual-framework-comparison). Native APIs checked: `UIListLayout`, `UIGridLayout`, `ScrollingFrame`, `TextBox`, `UIDragDetector`, `BillboardGui` and `TweenService`. Compose APIs checked: `cell`, `keyed`, `portal`, `watch`, `createRootOwner` and runtime mounting. The suite uses these mechanisms; it adds workload cases and report formatting only.
