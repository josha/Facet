### responder

<!-- aliases: responder | responder -->

`UI.responder(root, options?) -> Responder` declares how the surface `root`
(a GuiObject or a LayerCollector) shares the keyboard with the game. Call it
inside a component or a Compose owner; it stops when the owner ends. It works
on the engine selection: the surface is engaged while the selection is inside
it.

| Option | Effect |
|---|---|
| `passive` | `true` (the default): a HUD over live gameplay. At rest it binds nothing. Tab is not bound while nothing is selected, a D-pad press does not enter it, and Space reaches the game. It engages when the selection enters it, when the player taps it (the tapped control takes the selection) and on `engage()`. It resigns on a tap outside it, on ButtonB or Escape that no control takes, on `resign()`, and when the selection moves to another surface. `false`: the surface is always engaged, like any screen without a responder. |
| `gameplayGuard` | `true` (the default): while a passive surface is engaged, a sinking `FacetGameplayGuard` context at priority 3000 takes Space, so the avatar does not jump while the UI has the keyboard. `false`: no guard, and a Button inside `root` binds only Return, so Space reaches the game (a word game over the world). |
| `traversalWrap` | `true` (the default): Tab and Shift+Tab wrap at the ends of the surface. `false`: they stop at the last and the first control. |
| `resignOnActivate` | `false` (the default): the selection stays on a button after the player presses it. `true`: when ButtonA is released on a button inside a passive surface and the selection is still on that button (nothing opened a modal or moved it), the surface resigns and the selection returns to the game, so a HUD command such as Boost leaves the player driving. A `Composition` uses `true`. |
| `engageOnPress` | `true` (the default): a tap or click on a passive surface engages it. `false`: the press only activates the control under it, and the surface stays at rest, so the keyboard and the selection stay with the game. The selection entering the surface and `engage()` still engage it. A `Composition` uses `false`. |

The `Responder` has `state`, a readable of `"passive"` or `"engaged"`, and
`engage()` and `resign()`. `engage()` binds Tab and the guard; the first Tab
then enters the surface. `resign()` clears a selection inside `root`. On a
passive-only screen a gamepad player needs `engage()`, for example from a
menu button of the game. An unknown option or a value that is not a boolean
causes an error.

Every `UI.Composition` is a passive responder with `gameplayGuard = false`,
`engageOnPress = false` and `resignOnActivate = true`: a HUD over live gameplay. Its regions in the top-bar
strip share those options. The movement stick and the D-pad drive the game,
not the HUD. Give each HUD command a game action that a gamepad can press (a
face button or a shoulder button that opens the task), or set
`GuiService.SelectedObject` to a HUD control from a game action; the selection
engages the HUD; ButtonB, or pressing a HUD command that opens nothing, gives
it back to the game. Do not wrap a
Composition in another responder. Set the Composition's `passive = false` for
a dedicated screen that the D-pad should enter.

```luau
local hud = UI.Screen "Hud" { UI.Button "Map" { label = "Map" } }
local responder = UI.responder(hud)
-- the game opens its menu with a key of its own
responder.engage()
```
