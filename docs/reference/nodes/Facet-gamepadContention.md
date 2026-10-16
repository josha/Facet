### Facet.gamepadContention

<!-- aliases: Facet.gamepadContention | facetgamepadcontention -->

`Facet.gamepadContention` reports whether the engine's legacy player scripts
hold input that the controls need. Every probe is guarded: without an engine
it answers `false` and never throws. Nothing warns on its own; call them from
an input check or when an input looks dead.

| Call | Result |
|---|---|
| `legacyStackActive()` | `true` while ContextActionService binds `jumpAction`, which takes gamepad ButtonA before a selected control. |
| `cameraKeysContended(boundActionInfo?)` | `true` while any ContextActionService binding holds an arrow key (the camera's `RbxCameraKeypress` holds Left and Right). It reads a different binding than `legacyStackActive`. |
| `traversalKeyContended()` | `true` while the CoreGui players list is enabled, which takes Tab. |
| `iasPlayerScriptsActive(player?, waitSeconds?)` | `true` when the player has the engine's default `InputContexts` (`CharacterContext`, `CameraContext` or `VehicleContext`), which exist only when `Workspace.PlayerScriptsUseInputActionSystem` is on. |
| `disableLegacyControls(playerModuleParent?, player?)` | For a UI-only place only: it turns off avatar input. Returns `true, "inert: IAS owns PlayerScripts"` when the player scripts are on the Input Action System, `true, "disabled"` after `PlayerModule:GetControls():Disable()`, `true, "unbound"` when it removed `jumpAction`, else `false, "unavailable"`. |
| `freedJumpAction(before, after)` | The pure verdict of an unbind: `jumpAction` was bound before and is gone after. |
| `describeContention()` | The whole explanation as one string, for a log line. |

`cameraKeysContended` and `freedJumpAction` accept a map from action names to
records. Each record has an optional `inputTypes: { EnumItem }` field. Use the
records returned by `ContextActionService:GetAllBoundActionInfo()`.

The fix for a game with an avatar is `Workspace.PlayerScriptsUseInputActionSystem`.
No script can read or set it, but a Rojo project file can declare it. No
`InputContext` priority outranks a sinking ContextActionService binding.
