# Motion.help

| Control | Enter | Exit |
|---|---|---|
| Button `help` | The panel grows from 0.9 to 1 about its tail point, and fades in once, over the theme's `motion.normal` (0.2 seconds by default), Cubic Out (`easing.present`), from `materialize.anchored`. The panel, its text and its tail appear on the same first styled frame. | The reverse, over `motion.fast`. |

| Control | Enter | Exit |
|---|---|---|
| Menu, Picker menu | The complete panel fades in at its final position and size, 0.15 seconds (`popover.enter`), Cubic Out. As a sheet (touch, gamepad, narrow window), the panel slides up from the bottom edge and fades in with the Sheet timing (`sheet.enter` 0.3 seconds, `sheet.exit` 0.2 seconds) and never scales. A sheet level change slides the rows 32 pixels (`distances.menuSlide`) in from the trailing side (Back: from the leading side) and cross-fades them over `popover.enter`. | The reverse, 0.1 seconds (`popover.exit`); a sheet slides back down over `sheet.exit`. |

| Control | Enter | Exit |
|---|---|---|
| Popover compact sheet | The Sheet motion. | The Sheet motion. |

| Control | Enter | Exit |
|---|---|---|
| Toast | Slides in from its edge, 0.2 seconds (`toast.enter`), Cubic Out, and fades in over the same time on the linear `easing.trail`, so the fade is still running once the row is in view. `fade = false` only slides. | Slides out toward its edge and fades out, 0.2 seconds (`toast.exit`), the fade on `easing.trail`. |

| Control | Enter | Exit |
|---|---|---|
| Toast with an action | Slides up from below the layer, 0.2 seconds (`toast.enter`), Cubic Out, and fades in over the same time on `easing.trail`. | Slides down and fades out, 0.2 seconds (`toast.exit`), the fade on `easing.trail`. |

| Control | Enter | Exit |
|---|---|---|
| DisclosureGroup | The content height opens from 0, 0.25 seconds (`reveal.enter`), Cubic Out, and the content fades in over the theme's `motion.revealFadeShare` of that time (half by default). The chevron turns 90 degrees with it. | The height closes in 0.2 seconds (`reveal.exit`), and the content fades out over the same share of that time. |

| Control | Enter | Exit |
|---|---|---|
| CollapsibleView | The panel grows out of the trigger's rectangle to its open rectangle, 0.25 seconds (`reveal.enter`), Cubic Out (`easing.present`), and the content fades in over the theme's `motion.revealFadeShare` of that time (half by default). The chevron turns 180 degrees with it. | The panel shrinks back in 0.2 seconds (`reveal.exit`), and the content fades out over the same share of that time. |
