# Motion.metrics.motion

The controls animate navigation and presentation by default. All motion uses
the Compose runtime. An exiting element cannot be interacted with, and the
selection never stays on it. NavigationStack restores selection when the
destination page stops moving, so the selection image does not cross the
screen or select a scrolling container during the transition. Every time,
easing, spring, scale and distance below is a token in the theme package's
`metrics.motion` (named in brackets). The values are Facet Neutral's.

| Control | Enter | Exit |
|---|---|---|
| NavigationStack push | The new page slides in from the trailing edge. The old page moves 30 percent (`distances.parallax`) to the leading edge and dims by 0.1 (`distances.dim`). Critically damped spring with a 0.3 second period (`springs.move`), visually complete in approximately 0.35 seconds. | Pop is the reverse. |

| Control | Enter | Exit |
|---|---|---|
| TabView page change | Crossfade, 0.2 seconds (`durations.tabFade`), Quad Out (`easing.fade`). | The same. |

| Control | Enter | Exit |
|---|---|---|
| Sheet | Slides up from the bottom, 0.3 seconds (`sheet.enter`), Cubic Out (`easing.present`). A side sheet slides in from its edge. The scrim fades in. A detent change, a released drag and a side sheet's released pull settle on one critically damped spring (`springs.sheet`, a 0.4 second period, visually complete in about 0.45 seconds) that starts from the finger's release velocity; a detent change retargeted mid-flight keeps its velocity. A release faster than 800 pixels per second (`fling.bounceSpeed`) settles on `springs.flick` (0.3 second period, damping 0.8), so it passes its detent by under 2 percent once and comes back. While you drag or pull a sheet that can be dismissed, the scrim lightens in proportion to how far the sheet has moved toward dismissal. | Slides down, or toward its edge, 0.2 seconds (`sheet.exit`). |

| Control | Enter | Exit |
|---|---|---|
| Alert, Dialog | The complete panel fades in without a scale change, 0.2 seconds (`dialog.enter`), Cubic Out. The scrim fades in. | The reverse, 0.15 seconds (`dialog.exit`). |

| Control | Enter | Exit |
|---|---|---|
| Popover | The complete panel fades in at its final position and size, 0.15 seconds (`popover.enter`), Cubic Out. | The reverse, 0.1 seconds (`popover.exit`). |

| Control | Enter | Exit |
|---|---|---|
| Callout | The panel grows from 0.9 to 1 about its tail point, and fades in, over the theme's `motion.fast` (0.12 seconds by default), Cubic Out (`easing.present`), from `materialize.anchored`. The panel, its text and its tail appear on the same first styled frame. | The reverse, over the same time. |
