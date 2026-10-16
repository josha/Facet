# Themes.stylesheet

- Make the sheet inside a Compose owner. Parent it as a numeric child. A
  StyleLink only references the sheet. It does not parent it.
- The options are:
  - `types`: injected datatypes.
  - `theme`: the selected palette, as a name or a readable.
  - `name`: the native name.
  - `transition`: a native TweenInfo, a readable, or `false`.
  - `motionLevel`: `"normal"`, `"limited"` or `"none"`, or a readable. If you
    omit it, the sheet uses the `motionLevel` given to `Facet.controls` on the
    same runtime. Paint transitions are instant only at `"none"`; the device's
    Reduce Motion (`"limited"`) keeps them.
  - `preferredTransparency`: a number or a readable. The value multiplies the
    scrim transparency. Other rules keep their authored transparency. A value
    that is not a number has no effect. If you omit it, the sheet follows
    GuiService.
  - `hover`: a boolean or a readable. When it is `false`, the sheet leaves out
    the `:Hover` rules, so a tapped control does not keep a hover tint. Press
    paint stays. If you omit it, or the readable gives `nil`, the sheet leaves
    out hover paint while UserInputService.PreferredInput is Touch.
  - `tenFoot`: a boolean or a readable. When it is `true`, the sheet compiles
    `forDistance(package, "ten-foot")`: the ten-foot type ramp, radii and
    strokes. If you omit it, the sheet follows `adaptive.isTenFoot` of
    GuiService and UserInputService. `app.mount` passes the environment's
    `isTenFoot`. Pass `false` for a SurfaceGui or BillboardGui, whose canvas
    has its own scale, and give its controls `environment.viewingDistance =
    "near"`.
  - `contentProvider`: the ContentProvider that warms the package's art. If
    you omit it, the sheet uses the engine's ContentProvider. The first time
    the sheet applies a package, it calls `PreloadAsync` once on the content of
    every entry in `package.assets` except those marked `preload = "lazy"`,
    off the calling thread, so a panel that
    first opens later already has its art.
- Colors and opacity use native StyleRule transitions. `:Press` rules use
  `metrics.motion.press` (0.08 seconds), `:Hover` rules use
  `metrics.motion.hover` (0.15 seconds), and other rules use
  `metrics.motion.normal` (0.2 seconds). Press and hover are never slower than
  `normal`. The easing is `metrics.motion.styles.paint` (Quad Out). The theme
  StyleSheet carries the three timings as TweenInfo attributes
  (`FacetMotionNormal`, `FacetMotionPress`, `FacetMotionHover`), and each rule's
  transitions reference one of them as a `$` token, so a timing change updates
  three attributes and rewrites no rule. The engine reads the token when a
  transition starts, so a new timing applies to the next change. The three
  attributes belong to Facet: a game rule may reference them but must not write
  them, and the sheet writes a cleared or overwritten one back at once (a rule
  whose token is missing falls back to another matching rule's timing). Roblox applies the transition of the
  rule being entered, so a press arrives in the press time; its release eases
  back in the normal time, or in the hover time while the pointer is still over
  the control (the release enters `:Hover`). Native transitions retarget
  interrupted changes.
