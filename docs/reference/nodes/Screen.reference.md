### Screen

<!-- aliases: Screen | screen -->

`UI.Screen(spec) -> Frame` is the root of a screen. It fills its parent
(`width` and `height` are `"fill"`) and stacks its children vertically. A
stack places each child, so a child `Position` or `AnchorPoint` has no effect.
For a HUD at a corner or an edge, return the HUD as the root of the mount, as
[Tasks.hud](Tasks.hud.md) does, or use a Composition region. The Screen has
`padding = "m"` by default. The ScreenGui `ScreenInsets` property keeps the
screen inside the device safe area. The content never sits under the engine top
bar: when the screen reaches into the `GuiService.TopbarInset` band, the covered
height is added to the top padding. This holds with `IgnoreGuiInset` on or off.
The band covers the full width, as `CoreUISafeInsets` does. The background of
the screen still fills its parent. A Screen in a SurfaceGui takes no top bar
padding. At ten feet the Screen also clears the environment's `overscanInsets`
(see [environment](environment.md)). It adds only the part of each margin that
its native bounds still overlap. Nested screens do not add the same margin
again. A configured `overlayParent` supplies the preview viewport bounds.
Options: `gap`, `padding`, `align`,
`distribute`, `width`, `height` and `chrome`.

`chrome` is the platform-chrome policy. `"device"` (the default) clears the
device safe area, the top bar and the overscan. `"band"` lets the content ride
the free strip of the top bar beside the engine's buttons (a game's own top
row): no top bar padding, overscan kept. `"edge"` adds neither; pair it with
`ScreenInsets = Enum.ScreenInsets.None` on the ScreenGui for art that reaches
the glass. Your own persistent chrome is `padding`.
