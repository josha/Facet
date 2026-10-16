# environment.viewingDistanceSource

<!-- aliases: scaled | environment.scaled | metricScale -->

environment.viewingDistanceSource option values and behavior.

| Field | Source and value |
|---|---|
| `viewingDistanceSource` | `"authored"` when the `viewingDistance` option is `"near"` or `"ten-foot"`, else `"inferred"`. |

| Field | Source and value |
|---|---|
| `metricScale` | `adaptive.TEN_FOOT_SCALE` (1.5) at ten feet, else 1. It is the factor of the ten-foot metric ladder (see [Themes](Themes.md)). |

| Field | Source and value |
|---|---|
| `scaled(value, relativeTo?)` | A new number readable for a length that a game authors itself, such as a portrait or a custom gauge. A number is multiplied by `metricScale`. A string is a theme metric path, such as `"space.m"` or `"iconSizes.large"`, read from the effective package (after `forDistance`). With `relativeTo`, a type role such as `"body"`, the length also grows with the player's text size by the same factor as text of that role: the engine factor that `TextService:GetTextSize` measures for `GuiService.PreferredTextSize`, times a `preferredTextSize` preview. Use it for a length that sits with text, such as a portrait beside a line or the width of a wrapped line. Use it in place of arithmetic with `metricScale`. Text sizes come from type roles: do not scale a `TextSize` with it. |

| Field | Source and value |
|---|---|
| `overscanInsets` | `{ top, left, bottom, right }` in pixels. At ten feet it is the console profile as a proportion of the viewport (`adaptive.overscanInsets`): 60/1080 of the height and 90/1920 of the width, so 1920 by 1080 reserves 60 and 90. Near, it is zero. The `overscanInsets` option wins; `"none"` is zero. `UI.Screen` adds it to its padding. |

| Field | Source and value |
|---|---|
| `navPlacement` | `adaptive.navPlacement` of the classes, the primary input, the display size and `isTenFoot`. |

| Field | Source and value |
|---|---|
| `safeInsets` | `{ top, left, bottom, right }` from `GuiService:GetGuiInset()`. It updates when the viewport or `GuiService.TopbarInset` changes. |
| `topbarInset` | A `Rect` from `GuiService.TopbarInset` in engine pixels. It updates when that property changes and keeps its screen coordinates with a custom environment source. It is an empty `Rect` when GuiService or the property is unavailable. The component owns the observation. It gives the free band, not the menu button bounds. See [HUD-actions](HUD-actions.md). |
| `topbarControlDiameter` | A derived diameter in physical pixels: round the top-bar band height times `0.75`, or times `0.5` when `GuiService:IsTenFootInterface()` reports native console UI. Thus bands of 58 and 87 pixels both give 44. It is 0 for an empty band. It follows the band and viewport. This uses native console UI, not the environment's inferred viewing distance. See [HUD-actions](HUD-actions.md). |

| Field | Source and value |
|---|---|
| `preferredTextSize` | The name of `GuiService.PreferredTextSize`, for example `"Medium"` or `"Largest"`. The engine applies the player setting. A preview adjusts the native typography rules with the theme's `controls.typography.preferredSizeStep`. |

| Field | Source and value |
|---|---|
| `motionLevel` | The stronger of the factory `motionLevel` option and the device level (`"limited"` when `GuiService.ReducedMotionEnabled` is true, otherwise `"normal"`). |

| Field | Source and value |
|---|---|
| `reducedMotion` | `true` when `motionLevel` is not `"normal"`. |
