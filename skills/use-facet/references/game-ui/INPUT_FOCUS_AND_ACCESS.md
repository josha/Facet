# Input, focus and access

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Preserve the player's task across inputs. Entry, understanding, action,
correction and return must all work with the input the player uses. A shortcut
can make a route faster; it must not be the only way to discover a required
command. Make accessibility settings reachable before they are needed to
complete a difficult interaction.

## Separate the adaptation decisions

| Constraint | Evidence | Design response |
| --- | --- | --- |
| Available room | Container bounds, width and height classes, safe insets | Reflow groups, bound scrolling and retain the decision and its action |
| Physical readability | Display size, viewing distance, player text preference and device testing | Use readable type roles, contrast and an appropriate density |
| Available input | `interactionClasses` capabilities | Keep useful alternatives available |
| Current input | `effectiveInput` | Show relevant commands, glyphs and interaction feedback |
| Reach and precision | Held thumbs, pointer accuracy, focus traversal | Give targets space and offer discrete alternatives to gestures |

Use `UI.environment` for engine facts and device observation for physical
readability and reach. Read `environment.environment` and
`environment.viewingDistanceSource` for the exact sources and overrides.
A gamepad does not imply a television. A high-resolution handheld can have
many pixels but little physical reading space. A desktop player with a
gamepad still needs useful comparison detail. Choose from actual constraints,
not a device-name branch. Check a handheld such as a ROG Ally at its normal
holding distance; a resized desktop window cannot prove readability there.

Keep selection, drafts, scroll position and route identity when input changes.
A new glyph alone does not need a new screen. If a layout must change, keep
the selected object and next action recognizable. Read `effectiveInput`
instead of switching on every raw input event. Capabilities say what is
available; Roblox's `PreferredInput` estimates what the player is using.
Neither should disable another valid input.
[Roblox input reference](https://create.roblox.com/docs/reference/engine/classes/UserInputService#PreferredInput).

## Own input by task

Distinguish gameplay, UI navigation, text editing, manipulation and modal
response. A UI activation must not also jump, steer or fire. Use native
InputAction/InputContext for game commands and Facet's input mechanisms for
controls. Do not bind Roblox's Escape or gamepad Start.

A Composition is already passive, with `gameplayGuard = false` and
`engageOnPress = false`. Do not add a second responder. Give each HUD task an
authored gamepad command and a visible hint. Use `passive = false` for a
dedicated interface. For other HUD roots, use `UI.responder`; `engage` and
`resign` make the transition explicit. `engageOnPress = false` permits a press
to activate a control without taking the keyboard.

A page that replaces gameplay disables the game's gameplay InputContext and
custom touch actions. If it hides native movement controls, save and restore
the previous `GuiService.TouchControlsEnabled` value. Register restoration
with `Compose.cleanup` in the owning page, as in `Tasks.pages`. Close a child
surface without restoring gameplay while its parent still owns input. A
visible overlay does not pause the world; the game owns that decision.

Native InputContext priority and `Sink` resolve competing action bindings;
disabling the gameplay context makes its ownership explicit. The responder's
Space guard is not a general suspension of game commands.
[Roblox InputContext reference](https://create.roblox.com/docs/reference/engine/classes/InputContext).

## Make focus a useful route

Focus identifies the target of the next command. Keep it distinct from
persistent selection, equipped state and pending work. Show focus on the
actual actionable boundary. Let the control own its treatment; do not add a
second selection system. Check contrast over bright, busy and similar-colored
gameplay. Facet's default ring has a contrasting `chrome.focus.halo`; custom
bracket, glow and art treatments need equally visible boundaries.
[XAG 113: focus handling](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113).

Choose entry focus from the likely next action and the cost of an accidental
activation. When a Sheet takes selection, it uses `initialFocus`, then its
first available content control, then a pinned action, then Close or the
grabber. A Dialog prefers
Cancel, then a non-destructive action. A read-only result may need Close as
its useful action. Keep this judgment separate from the visual emphasis of
the primary action. Read `Selection.SelectedObject` for the exact behavior.

Make directional movement agree with the visible arrangement and keyboard
order agree with the reading and action order. Put frequent commands near
their related content; do not require a walk through a long collection to
reach them. Preserve logical item identity when rows recycle. Restore focus
to the opener on return, or to a useful remaining target when it disappears.
A HUD command that opens nothing hands the selection back to the game, so the
player presses it and keeps playing; Composition does this
(`resignOnActivate` in `responder`).
Back follows the actual task path. Show why an action is unavailable in
reachable text even when its disabled control is skipped.
[XAG 112: UI navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112).

Focused content must remain visible, including inside nested scroll regions.
Use `scrollToVisible` for an event such as revealing an invalid field; do not
continuously recenter and fight the player's reading position. Use
`commandScope` for commands on native selected targets and `adjustable` for
specialized value controls. `commandScope` does not provide directional
navigation. A world-space target also needs a reachable command route; a
moving or occluded anchor is not a reliable place for sustained reading.

For world-space or VR work, read `Native-targets-and-boundaries` before choosing
interaction. Facet's world surfaces are flat UI; it supplies no ray, hand,
gaze input or VR layout mode. Plan and verify the required native input and
comfort behavior explicitly rather than assuming a screen layout proves it.

## Make commands discoverable

Use Facet's Roblox bindings consistently: ButtonA activates and ButtonB goes
back. TabView provides shoulder navigation. VirtualList, VirtualGrid, Table
and Outline provide trigger paging while they hold focus. The selected
control can own a more specific adjustment command; check its contract before
assigning the same button. Roblox keeps Menu; ButtonSelect enters native GUI
selection when `GuiService.AutoSelectGuiEnabled` is enabled.

Use `ShortcutHint` with an InputAction where available. It reads the native
preferred binding, including its display image or name. The hint describes
a binding; it does not create it. Use the engine's reported glyph instead of
assuming a controller brand. Keep the action name clear, such as "Equip"
rather than just "A".

A control can carry its own glyph with `cap = false`. A Button takes the
action in `shortcutHint` and shows the glyph only while the device has a
binding for it. Use `UI.ButtonGuide`
for contextual commands that have no visible control, such as paging or an
action on the focused item. List each command once. Prioritize useful commands
rather than filling a fixed quota. The guide is a noninteractive readout;
native selection and the surface's entry focus skip it.

Use an `action` entry for a native InputAction. It shows while the action's
native `Enabled` is on and the device has a binding. Use actions from
`commandScope`, or update their native `Enabled`, to follow the current focus.
Use `keyCode` for platform glyphs, including bumper and trigger pairs. Its
entry stays visible; update the entries when the command becomes unavailable.
`keys` uses written names that stay the same on every platform. A hint does
not create a command or its binding. Read `ButtonGuide.reference` for exact options.

The guide follows `effectiveInput` and shows for Gamepad by default. Add
`KeyboardAndMouse` to `inputs` when useful; Touch is not supported. Bind the
`buttonGuides` app or controls option to a readable player setting so players
can hide persistent hints. Keep the guide inside the owning surface's safe
area. In a Sheet, use `guide`: it stays outside every scroller and takes room
from the body while visible. Check short layouts with it shown. A guide hides
when a modal that does not contain it opens. Read `Sheet.guide` for placement.

Test device changes during a task, including controller disconnection. Keep
the draft and a usable exit; update hints without committing or restarting
the task. Keep valid pointer and controller inputs usable together; an event
from one must not lock out the other.
[Valve input guidance](https://partner.steamgames.com/doc/steamhardware/recommendations).

## Remove unnecessary access barriers

Provide a menu route with single digital presses. Do not require a pointer,
analog precision, a chord, rapid repeats or a sustained hold to configure and
use the interface. If a gesture improves the task, provide an equivalent
command. Make the alternative preserve the same eligibility, result and
recovery. Shortcuts supplement that route.
[XAG 107: input](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107).

Touch needs adequate target size, spacing and clearance from held thumbs and
native movement controls. Test the active hit area, not only the drawn icon.
Required information cannot depend on hover. Keep the active text field,
validation and completion or cancellation route reachable with the on-screen
keyboard open. Use native text editing and IME; keyboard dismissal must not
silently commit a consequential action.

Use semantic text roles and let larger text and localization reflow. Facet's
text follows `GuiService.PreferredTextSize`; do not use TextScaled to squeeze
it into a fixed box. Check the largest preference with real content. Keep
icons that convey text readable too. Facet's ten-foot theme and `overscanInsets`
provide a starting point, not proof of readability on every screen.
[Roblox text-size reference](https://create.roblox.com/docs/reference/engine/classes/GuiService#PreferredTextSize).

XAG 101 recommends a rendered text body height of at least 26 pixels at 1080p
for console use, with an option to double it. Body height includes ascenders,
the main letter body and descenders. These are viewing-context
guidelines, not universal Roblox TextSize values or a guarantee that Facet's
preference steps provide 200 percent scaling. Verify rendered text at the
intended distance and the actual range the game offers.
[XAG 101: text display](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101).

Name icon-only actions. Distinguish states with labels, shapes or patterns as
well as color. A read-only value can still need selection, copying and full
contrast. Combine visual, sound and haptic feedback where useful, with no
essential result available in only one sensory channel. Keep navigation
feedback quiet enough for repeated use. Reduced motion preserves the same
meaning and result without requiring a pulse or animation to understand it.

Verify the complete route: first HUD entry, action, correction, nested Back
and return to gameplay. Include removed targets, input changes and settings
changes while the task is open. Use Studio's controller emulation for native
behavior and physical devices for reach, readability and hardware claims.
