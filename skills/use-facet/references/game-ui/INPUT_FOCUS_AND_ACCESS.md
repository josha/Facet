# Input, focus and access

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Own input by task

Distinguish gameplay, UI navigation, text editing, manipulation and modal
response. A UI activation must not also jump, steer or fire. Use native
InputAction/InputContext for game commands and Facet's input mechanisms for
controls. Do not bind Roblox's Escape or gamepad Start.

A Composition is already passive, with `gameplayGuard = false` and
`engageOnPress = false`. Do not add a second responder. Use `passive = false`
only for a dedicated interface. For other HUD roots, use UI.responder with an
authored entry command; engage and resign make that transition explicit.
`engageOnPress = false` permits activation without taking the keyboard.
A fullscreen page disables the game's gameplay context and custom touch actions,
and restores them on exit. Restore the previous GuiService.TouchControlsEnabled
value when changing native movement controls.

## Make focus a useful route

Show focus on the actual actionable boundary. Keep it distinct from persistent
selection and accepted equipment. Let the control own its focus treatment;
do not add a competing second selection system.

Set sensible entry and return focus. When an opener disappears, choose a useful
remaining target. Back returns along the actual task path. Scroll focused
content into view without continuously fighting the player's reading position.
Use scrollToVisible for an event such as revealing an invalid field.

Use commandScope or adjustable for specialized controls instead of rebuilding
general focus traversal. A world-space target still needs an accessible command
route; a moving or occluded anchor is not a reliable place for sustained reading.

## Adapt independently

Screen size, preferred input and viewing distance are different constraints.
Keep layouts stable when only a hint changes. Touch cannot depend on hover;
gamepad cannot depend on a pointer or drag. Larger text and localization must
reflow rather than hide required information.

With the on-screen keyboard open, keep the active field, validation and the
completion or cancellation route visible and reachable.

Read-only and unavailable are different: a read-only value can still need
selection, copying and full contrast. Test viewing distance independently of
input; a gamepad does not imply oversized tiles or reduced comparison detail.

Combine visual, sound and haptic feedback where useful, but never make one
sensory channel the only indication of an essential result. Respect reduced
motion without removing the result.

Test entering a passive HUD, opening and closing each task, scrolling, nested
Back, text entry, input-device changes, disabled and removed targets, and return
to gameplay. Native simulation is not proof of physical-device performance.
