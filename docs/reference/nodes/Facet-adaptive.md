### Facet.adaptive

<!-- aliases: Facet.adaptive | facetadaptive -->

`Facet.adaptive` holds pure decisions. They take numbers and never a device
name.

| Call | Result |
|---|---|
| `sizeClass(width)` | `"compact"` below 600, `"regular"` below 1000, else `"wide"`. A nil, NaN or negative width gives `"compact"`. |
| `heightClass(height)` | `"short"` below 600, `"medium"` below 1000, else `"tall"`. |
| `orientationFor(width, height)` | `"landscape"`, `"portrait"` or `"square"`. This is a shape fact. |
| `axisFor(width, { stackAbove? })` | `"x"` at or above `stackAbove` (default 600), else `"y"`. |
| `columnsFor(available, minColumnWidth, gap?)` | How many columns fit the requested minimum width and gap. Returns at least 1, even when one column cannot fit that minimum. |
| `sizeClassAtLeast(value, target)` | `true` when `value` ranks at or above `target` in `compact < regular < wide`. |
| `isTenFoot({ displaySize?, touch?, mouse?, tenFootInterface?, viewingDistance? })` | `viewingDistance` `"ten-foot"` or `"near"` decides. Otherwise `true` for `GuiService:IsTenFootInterface()` or a `Large` display, when there is no touch and no mouse. A large desk monitor with a mouse is near, and so is Studio, which reports `IsTenFootInterface()` true on a desktop. |
| `overscanInsets(width, height)` | The console overscan margins for a viewport: `{ top, left, bottom, right }` of 60/1080 of the height and 90/1920 of the width, rounded. |
| `TEN_FOOT_SCALE` | 1.5, the ten-foot metric factor. |
| `navPlacement({ sizeClass, heightClass, primary?, displaySize?, tenFoot? })` | The app navigation home, in this order: ten-foot `"topBar"`; compact width `"bottomBar"`; short height `"bottomBarCompact"`; a pointer `"sidebar"`; a gamepad on a `Small` display `"bottomBar"`; otherwise (a roomy touch screen, a gamepad on a larger display) `"topBar"`. |
| `BREAKPOINTS`, `HEIGHT_BREAKPOINTS` | The same table: `{ regular = 600, wide = 1000 }`. |
| `DEFAULT_STACK_ABOVE` | 600. |
