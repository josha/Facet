# Strong hub HUD

The reference uses plain Luau and native Roblox Instances. Its Kit owns the
shared visual styles and modal routes.

Play is the primary row action. Leave Queue or Leave Vehicle replaces Play
when that action applies. Shop, Garage and More use the secondary style.
Each action has a round icon button and a readable label below it.

All More items use the same secondary style and centered labels. The Ready
badge and Offer timer use separate bounds. They do not change label alignment.

The action row uses TopbarSafeInsets. It ends at the top bar's right safe
edge. Other HUD content uses CoreUISafeInsets. GuiService.TopbarInset gives
the free band, not the menu
button size. The diameter is round(0.75 times the band height), or round(0.5
times the height) when GuiService:IsTenFootInterface() reports native console
UI. Bands of 58 and 87 pixels both give 44 pixels. The action layer has no
UIScale, so the diameter stays in physical pixels without offset rounding.
Text uses the theme's console scale. An empty band uses a theme size.
The theme supplies edge spacing, label sizes, colors and icon strokes.

The circle bottoms end one theme border gap above the band bottom. This
matches the observed native menu center on desktop and console. The row
updates with the band and viewport. Labels stay visible below their circles
at the body text size. Solid shapes use the button's theme ink, without grey
texture pixels. The Intermission banner and wallet start below the labels.
The row stays clear of the native thumbstick and JumpButton regions.
UIListLayout keeps one horizontal selection row, with left and right links
between visible actions. Boundary links stay open for native navigation.

More keeps its full-screen scrim, scrollable groups, Close action and native
selection navigation. Its bounds are set while it is hidden.

## Studio coverage

Capture the hub and More menu on desktop, phone portrait, phone landscape,
tablet and console. Inspect the labels and touch clearance. On console,
Right must select Shop, Garage and More in that order from Play.

The checks use Studio Device Simulator presets and native VirtualInput.
Gamepad checks use engine selection with direction keys and Return. This
coverage does not prove behavior on physical phones or controllers.
