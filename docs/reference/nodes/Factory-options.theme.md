# Factory-options.theme

- `theme`: a theme package or a readable of one. The controls use it for
  metrics, artwork and icon resolution. At ten feet (`adaptive.isTenFoot`)
  they use `themes.forDistance(theme, "ten-foot")`, so every metric length,
  the 44 pixel hit floor (66) and the control heights are 1.5 times. A
  readable `environment` preview of the distance, the display size or the
  pointer makes the ladder follow a change at once. Without one, the controls
  take the distance when `Facet.controls` runs. `Screen` overscan follows the
  live fact.
- `motionLevel` and `icons`: these can also be reactive. `motionLevel` is
  `"normal"` (full motion), `"limited"` or `"none"` (see Motion). If you omit
  it, or when a readable gives nil, motion follows the device:
  `GuiService.ReducedMotionEnabled` gives `"limited"`, otherwise `"normal"`.
  The effective level is the stronger of
  yours and the device's (`"normal"` < `"limited"` < `"none"`): a game can add
  reduction but never remove a player's Reduce Motion. An unknown value given
  when the controls are made is an error; an unknown value that a readable delivers later
  (such as a stale saved setting) follows the device level with one warning.
- `pressHaptic`: a native `HapticEffect` or a feedback kind (`"selection"`,
  `"impact"`, `"success"`, `"warning"` or `"error"`). Only a control that
  changes a state or a value plays it. See [Haptics](Haptics.md).
- `controlSize`: the control-size step (`xsmall`, `compact`, `regular` or
  `large`) for theme icons.
- `onError`: receives a failure from the content of a presented Alert or
  Sheet, which then dismisses, and a failure from a Callout `onShow`. It also
  receives a failure that an `ErrorBoundary` without its own `onError`
  contains.
- `environment`: a preview of the device facts. Each field is a value or a
  readable. `nil` follows the engine. `preferredInput` (a `PreferredInput` or
  its name), `touchEnabled`, `mouseEnabled`, `gamepadEnabled` and
  `keyboardEnabled` replace the `UserInputService` facts that every control
  reads. `preferredTextSize` and `displaySize` (a `PreferredTextSize` or a
  `DisplaySize`, or its name) replace the `GuiService` facts. A `preferredTextSize` preview also
  changes the native typography rules from `createStyleSheet` on the same
  runtime. Create the controls before the StyleSheet. Each step uses the theme
  metric `controls.typography.preferredSizeStep` (2 pixels by default). A
  readable that returns `nil` follows the engine. `viewportSize`
  replaces the camera viewport of `UI.environment()` without a source. Use it
  for a preview in a catalog or a gallery. The engine input still arrives:
  a mouse click still works in a touch preview. `viewingDistance`
  (`"automatic"`, `"near"` or `"ten-foot"`) is the authored viewing context:
  `"ten-foot"` makes a lounge PC with a mouse a television, and `"near"` keeps
  a console near. It outranks every inference. `overscanInsets`
  (`{ top, left, bottom, right }` in pixels, or `"none"`) replaces the default
  ten-foot margins. An unknown field or value causes an error.
