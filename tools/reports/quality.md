# Game UI quality verification

Inspect native captures and Verify audit reports for the game workspace under
test. Compare equivalent player states under the current evaluation protocol.
Keep diagnostic subsets separate from complete acceptance results.

## Capture and inspect

Capture the game without an agent:

```sh
lute run tools/facet perf capture --workspace <workspace> --out artifacts/quality/capture --devices desktop,phone-portrait --tap Shop
lute run tools/facet perf footprint artifacts/quality/footprint.json
```

Capture each panel and inspect its screenshot and audit. Open and close each panel on every device. Confirm that Close restores the base instance census. Use the same game workspace and package source for comparisons.

## Current mechanisms

- Button targets keep both dimensions at the theme minimum when needed.
- Sheet reserves native safe insets through GuiService.GetInsetArea.
- Overlay arrival uses a non-clipping Frame.Visible gate.
- StyleRule comma selectors share compatible property and motion state.
- Disabled filled controls limit text transparency to preserve paired contrast.
- The author kit contains its driving handler in `tools/play/engine`. RaceTrack
  loads only for an explicit driving request.

Verify reads styled properties and accounts for modal occlusion. An empty
full-viewport dismiss target is not safe-area content. Foreground content and
available actions still require safe-area and overlap checks. The audit does
not exempt findings by Facet tags or instance names.

## Timing limits

Mount includes startup and a wait for stable geometry. The probe waits for one second of stable geometry with a 20-second limit. Currency labels and progress fills can keep geometry changing. Studio background throttling affects frame pacing. These observations do not isolate interface CPU cost.

Use the configured overhead report for a paired verdict. Do not infer parity
with plain from a favorable point ratio. See
[the run's pass requirements](../../eval/README.md#pass-requirements).

## Validation commands

```sh
lute run tools/facet gate full
lute run tools/facet bench
lute run tools/facet package build
lute run tools/facet package status
```

Read the selected producers, case results, and deferrals. Focused cases do not
establish a complete gate pass. Native geometry, input, and physical device
behavior need their own live reports.
