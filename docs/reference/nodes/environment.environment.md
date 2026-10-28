# environment.environment

`UI.environment(source?) -> Environment` returns readables of the engine facts
that a screen adapts to. Call it inside a component or a Compose owner. The
readables stop when the owner ends. Without a `source`, every call returns the
app's one camera environment while any owner holds it, so a property function
that calls `UI.environment()` again when it reruns gets live facts. Call it
once at the top of the component and read its fields with `use`. `source` is a `GuiBase2d`, whose
`AbsoluteSize` in layout units (divided by the scale of its `UIScale`
ancestors) is the viewport, or a `Camera`, whose `ViewportSize` is the
viewport. Without a source it reads the `ViewportSize` of the workspace camera.
A viewport smaller than 2 by 2 pixels is an engine placeholder. The
environment keeps the last real size.

| Field | Source and value |
|---|---|
| `viewportSize`, `viewportWidth`, `viewportHeight` | The viewport: layout units for a `GuiBase2d` source, pixels for a camera. |
| `topbarInset` | The available top-bar rectangle from `GuiService.TopbarInset`, in screen pixels. |
| `gameplaySuspended` | True while a modal surface, or with `suspendGameplay` a NavigationStack page, replaces gameplay. Derive gameplay InputContext `Enabled` from it. |
| `topbarControlDiameter` | The rounded top-bar height times 0.75, or 0.5 when `GuiService:IsTenFootInterface()` is true. Use it for an action beside the Roblox controls. |

| Field | Source and value |
|---|---|
| `thumbTarget` | The size in pixels of a primary on-screen action for the thumb. It is `targetSizes.thumb` (70 in the neutral package) when the screen's short edge is 500 pixels or less. Otherwise it is `targetSizes.thumbLarge` (120). These match the Roblox touch jump button sizes. A rotation does not change it. |

| Field | Source and value |
|---|---|
| `sizeClass`, `heightClass`, `orientation`, `axis` | `adaptive` applied to the viewport. On a ten-foot display (`isTenFoot`) `sizeClass` stops at `"regular"` and `heightClass` at `"medium"`, so a television never takes the densest arrangement. |

| Field | Source and value |
|---|---|
| `isCompact`, `isRegular`, `isWide`, `isRegularOrWider`, `isShort`, `isTall`, `isLandscape` | Booleans. `isRegular` is the middle class only. Use `isRegularOrWider` for "not compact". |

| Field | Source and value |
|---|---|
| `atLeast(target)` | A new boolean readable for `sizeClassAtLeast(sizeClass, target)`. |

| Field | Source and value |
|---|---|
| `interactionClasses` | `{ primary, pointer, touch, gamepad, keyboard }` from `UserInputService.PreferredInput` and the `MouseEnabled`, `TouchEnabled`, `GamepadEnabled` and `KeyboardEnabled` capabilities. `primary` is `"pointer"`, `"touch"` or `"gamepad"`. Before a player uses touch or a gamepad, a device with touch and no mouse is `"touch"`. The primary class is always in the set. A press of modifier keys alone (Shift, Control, Alt, Meta or Super, with no other key or mouse button down) does not move Facet to keyboard and mouse, though the engine's `PreferredInput` changes; the next other key, mouse button, mouse movement or wheel does. Every control, and the theme StyleSheet's hover paint, reads `PreferredInput` through this rule. |

| Field | Source and value |
|---|---|
| `effectiveInput` | `primary` as `"KeyboardAndMouse"`, `"Touch"` or `"Gamepad"`. |

| Field | Source and value |
|---|---|
| `displaySize` | The name of `GuiService.ViewportDisplaySize`: `"Small"`, `"Medium"` or `"Large"`. |

| Field | Source and value |
|---|---|
| `isTenFoot` | `adaptive.isTenFoot` of the `viewingDistance` option, the display size, the touch and mouse capabilities and `GuiService:IsTenFootInterface()`. A gamepad alone is not ten-foot. |
