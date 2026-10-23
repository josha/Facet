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

## Follow console conventions

These follow the Xbox Accessibility Guidelines (XAG 101, 107, 112, 113),
Microsoft's gamepad and TV guidance and Roblox's console guidelines. Sony's and
Nintendo's requirements are not public; their system conventions agree.

A selects and B goes back on every screen. Since the PS5, Cross confirms in
every region, Japan included, and Roblox reports it as ButtonA: never swap
them. LB/RB change tabs (TabView binds them) and LT/RT page long content
(VirtualList, VirtualGrid, Table and Outline bind them while they hold
focus). X and Y
are shortcuts for frequent, non-critical commands that also have an on-screen
route. Roblox keeps Menu;
ButtonSelect (View) moves the selection into the interface while
GuiService.AutoSelectGuiEnabled is on. Show the button with ShortcutHint and
the action, which draws the Xbox or PlayStation glyph the engine reports.

A surface starts on the control the player most likely acts on, never on a
dismiss control that B performs: a Sheet's first content control or its
`initialFocus`, such as a recommended item. A confirmation with consequences
starts on the safe choice, as a Dialog's cancel action does. Focus returns to
the opener and always stays visible, never on a hidden or off-screen control.
Visible means visible over the game too: a ring the color of the grass behind
it is lost. Facet's default ring kind has a contrasting halo
(`chrome.focus.halo`); give bracket, glow and art looks the same contrast, and
check focus over the busiest and most similar scenery. A slow pulse suits
tiles and cards, not text buttons, and stops under reduced motion.

Show a button where its command is. A command with its own control carries
its glyph on that control (`ShortcutHint` with `cap = false`); on the HUD this
is the only kind of hint. A legend line, such as "A Buy  B Back  LB/RB Tabs",
is for commands that have no control of their own: those that act on the
focused item, the bumpers and triggers, and Back on a surface without a
visible Close. Build it with `UI.ButtonGuide`. Never list a command twice. A
legend is a readout, never a stop: it is not selectable, so the selection
route and a surface's first focus skip it. Follow the input class
(`effectiveInput`), not each input event: show it for a gamepad, leave it off
on touch, and on keyboard and mouse only when the game asks
(`inputs = { "Gamepad", "KeyboardAndMouse" }`), so moving the mouse never
makes it flash. Give players a setting that hides it: bind one settings
Toggle to the `buttonGuides` app option. Put it along the bottom edge of the
surface that owns input, inside the safe area; in a Sheet, use its `guide`
option. Keep it to about four entries in button order. Give bumpers and
triggers `keyCode` entries so each platform draws its own glyph. An `action`
entry shows while its native `Enabled` is on and the device binds it, so a
commandScope action updates the legend as focus moves. An alert
hides it and shows its own choices. When a controller connects or
disconnects, acknowledge it and switch the glyphs at once.

Every menu works with the D-pad and A/B alone, one press at a time: no stick,
chord, rapid press or long hold, or a toggle where a hold is unavoidable. Keep
routes short (about six presses to cross a screen) and put commands before or
beside long lists. At 1080p, text needs a body height of at least 26 pixels
and scales to 200 percent; Facet's ten-foot text is at least 28 (captions 24)
and follows the preferred text size. Keep text and controls about 5 percent
inside each edge; Composition and `overscanInsets` do this. Sound and haptics
confirm navigation sparingly: a soft tick for a focus move, and distinct
sounds for confirm, back, refusal and reward, so each one reads by ear. Help
that appears on a resting selection is one short sentence.

Test with the Studio Controller Emulator in the Xbox and PlayStation device
simulators: the first stick push after spawning, each HUD button, where focus
lands on every surface, Back from every depth and the return to play.

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
