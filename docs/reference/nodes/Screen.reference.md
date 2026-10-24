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
`distribute`, `width`, `height`, `chrome` and `surface`.

`chrome` is the platform-chrome policy. `"device"` (the default) clears the
top bar and the overscan; the app's `CoreUISafeInsets` clears the device safe
area. `"band"` lets the content ride
the free strip of the top bar beside the engine's buttons (a game's own top
row): no top bar padding, overscan kept. `"edge"` adds neither. A page
background does not need `"edge"`; use `surface`. For art that must itself
reach the glass, pair `"edge"` with `ScreenInsets = Enum.ScreenInsets.None` on
the ScreenGui and keep text and controls in safe children. Your own persistent
chrome is `padding`.

`surface` (`"surface"`, `"panel"` or `"pane"`) paints the theme plate of that
role behind the screen. At each edge where the screen meets the safe area of
its ScreenGui, the plate continues to the edge of the glass. It goes under the
top bar, the status bar, the cutouts and the home indicator. At an edge that
does not meet the safe area, such as a split view pane, the plate stops at the
screen bounds. The content keeps its padding, so text and controls stay safe.
Facet measures each band with `GuiService:GetInsetArea`. While the plate is in
a band, Facet sets the ScreenGui's `ClipToDeviceSafeArea` to false, as a modal
scrim does. Then it restores the value. Keep `CoreUISafeInsets` on the app.
