# Strong hub HUD

The reference uses plain Luau and native Roblox Instances. Its Kit owns the
shared visual styles and modal routes.

Play is the primary dock action. Leave Queue or Leave Vehicle replaces Play
when that action applies. Shop, Garage and More use the secondary style.

All More items use the same secondary style and centered labels. The Ready
badge and Offer timer use separate bounds. They do not change label alignment.

The HUD uses CoreUISafeInsets. The phone dock stays at the right edge and
clears the measured native thumbstick and JumpButton regions. Landscape uses
a short stats row on a backing panel at the top-left safe inset. Portrait uses
a vertical stats panel. Native UIListLayout, UIGridLayout, UIPadding and
AutomaticSize arrange the content. The dock measures touch controls before
it becomes visible.

More keeps its full-screen scrim, scrollable groups, Close action and native
selection navigation. Its bounds are set while it is hidden.

## Studio coverage

Each device passes all universal cases for the slice and the full hub.

| Device | Slice | Full hub |
| --- | ---: | ---: |
| Desktop | 6/6 | 17/17 |
| Phone portrait | 6/6 | 17/17 |
| Phone landscape | 6/6 | 17/17 |
| Tablet | 6/6 | 17/17 |
| Gamepad | 6/6 | 17/17 |

The checks use Studio Device Simulator presets and native VirtualInput.
Gamepad checks use engine selection with direction keys and Return. This
coverage does not prove behavior on physical phones or controllers.
