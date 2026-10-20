# ProgressView

ProgressView.reference option values and behavior.

The unwrapped value and end label keep their largest measured boxes while mounted.

| Control | Main contract |
|---|---|
| `ProgressView` | `value`, `min` (0), `max` (1). `presentation`: bar, circular, gauge or spinner. label and endLabel, showValue and format, diameter, thickness, segments, and an optional trail `{ delay, duration }`. The endLabel shows after the value. With a label, a bar shows the value and the endLabel on the label row. Segments require the bar presentation. Diameter requires circular, gauge or spinner.  A gauge is a dial: an arc open at the bottom, `sweep` degrees round (60 to 330, default 240), filled to the value, with a needle from the centre to the value and a hub over its root.  `needle = false` leaves only the arc.  A gauge needs a `value`; `sweep` and `needle` refuse every other presentation.  The needle and the hub take the theme's `progress-gauge-needle` and `progress-gauge-hub` roles (content colour). A trail holds on damage, settles over its duration, and snaps on healing or reduced motion. A circular value is centered when the native text bounds fit. Otherwise it shows below the ring. A circular ring with no thickness uses 8 percent of its diameter, and not less than the theme metric. On a bar, `controlSize` sets the track thickness: `xsmall` and `compact` use `space.xs`, and `regular` and `large` use `controls.progress.trackHeight`. A bar refuses `controlSize` together with `thickness`, and a ring or a spinner refuses it together with `diameter`. `endLabel` must be a string. |
