# Input, focus, and access

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). A good interface makes the next action predictable and available through the player's supported means of interaction. Input ownership, focus, and feedback are part of the design, even when they have no visible container of their own.

Use [Adaptive interaction and direct manipulation](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) to choose how a task responds to touch, pointer, keyboard, and gamepad. This chapter covers the focus, command, and input-ownership mechanisms that support those interactions.

## Assign input ownership by task

Decide whether the player is controlling the world, navigating UI, editing text, manipulating an object, or responding to a modal. Only the appropriate action should receive an input. A button press must not both equip an item and jump in the world; typing a name must not fire a weapon.

Use the control's own input behavior for standard fields, collections, menus, and surfaces. Use native input actions for game commands and `ShortcutHint` for truthful prompts. Avoid parallel global listeners that interpret the same press again. Respect reserved navigation and the current bindings rather than printing assumed key names.

A `Composition` is already a passive responder with `gameplayGuard = false` and `engageOnPress = false`: the stick, the D-pad, Space and clicks stay with gameplay. Do not wrap it in another responder; set its `passive = false` only when it is a dedicated interface rather than a HUD over play. Use `UI.responder(root, options)` for any other HUD that shares keyboard/gameplay input. Its default passive state leaves gameplay alone; engagement gives the UI an explicit navigation context. Provide an authored entry command for gamepad players rather than assuming a D-pad press enters a passive HUD. `engage()` and `resign()` express that transition.

Keep `gameplayGuard = true` when engaged UI should consume Space to prevent a simultaneous game action. Set it false only when continued gameplay input is intentional and understood. `traversalWrap` determines whether keyboard traversal wraps within the surface. `engageOnPress = false` lets a click or tap activate a control without giving the surface the keyboard. `passive = false` keeps the surface engaged; use it for a dedicated interface rather than a glance-only HUD. These settings do not define whether the game world pauses.

Modals isolate their covered interface, but custom gameplay actions and separate UI layers still need correct integration. Design returning from a modal, text field, or drag as carefully as entering it. Input should not remain trapped or execute a delayed underlying command when the surface closes.

## Make focus a visible route through the task

Focus answers “What will the next activation affect?” It is different from the selected record, equipped item, or checked value. Keep the focused target unmistakable against every state and background. Facet's app mount installs `UI.focusRing` behavior; style the shared focus chrome instead of drawing a competing ring for each ordinary control.

### Match feedback to the visible target

The visible artwork, hit area, and focus indicator serve different purposes.
Artwork identifies the object. The hit area makes activation reliable. The focus
indicator identifies the next activation target. They must describe the same
object, but need not have the same bounds. Keep hit areas large enough to use
without overlapping adjacent commands. Shape and place the indicator around the
visible target so it does not cross its content or appear to select a neighbor.
Reserve content space inside the artwork's contour, including padding along
sloped or curved edges. Fitting text in the rectangular bounds alone does not
prove it fits the visible surface. Keep state effects within that contour unless
an outward effect has a clear purpose and space reserved around it.

Use the shared focus treatment when it fits the control. For custom artwork,
native `SelectionImageObject` supplies a replacement. If the indicator must be
composed inside the control, drive its focus state from native selection events
and keep the native selection artwork visible. Preserve the distinction between
focus and persistent selection when focus moves elsewhere. Do not add a second
competing focus treatment.

Check the indicator through scaling, clipping, animation, theme changes, and
near and distant viewing. Test focus entering and leaving the control as well
as moving between its neighbors. A shape that looks correct in one still image
does not establish a usable focus route.

### Keep the route predictable

Use `UI.focusSection` when a coherent region needs deliberate entry and return behavior:

- `entry = "restore"` returns to the remembered useful item; `preferred` provides a first-entry fallback.
- `entry = "first"` suits a short sequence that should always begin at its start.
- `entry = "nearest"` preserves ordinary spatial entry where the engine's choice matches the layout.
- `focusOnAppear` claims a useful target when the task opens during selection navigation. Avoid repeatedly stealing focus during background updates.
- `returnFocus` restores the originating target when leaving, with a useful fallback if that target disappeared.

For every new surface, check entry, traversal, access to scrollable content, Back/Cancel, and return. Focusing each decorative child creates needless work. A custom value control can be one stop while its meaningful parts remain understandable; separate actual commands still need reachable targets.

Use `UI.scrollToVisible` for an event that must reveal relevant content, such as taking the player to an invalid field. It moves ancestor scroll areas only as needed. Use `UI.scrollTo` for an explicit top/bottom/location command. Do not fight a player's reading position by calling either continuously. `animated = false` suits an immediate correction, and reduced motion also removes the interpolation.

## Follow console conventions

Console players expect the same few conventions in every game. They come from the Xbox Accessibility Guidelines (XAG 101, 107, 112 and 113), Microsoft's gamepad and TV design guidance, and Roblox's console guidelines; Sony's and Nintendo's requirements are not public, but their system conventions match these.

- **Buttons:** A selects and B goes back, on every screen. Since the PS5, Cross confirms in every region, Japan included, and Roblox maps Cross to `ButtonA`, so do not swap them. LB/RB move between tabs (TabView binds them) and LT/RT page through long content (bind them yourself on a long list; Facet's collections do not yet). X and Y are shortcuts for frequent but non-critical commands; every command they run also needs an on-screen route. Roblox keeps the Menu button for its own menu; the View button (`ButtonSelect`) moves the selection into the interface while `GuiService.AutoSelectGuiEnabled` is on.
- **During play:** the movement stick and the D-pad belong to gameplay. Open each frequent HUD task with its own button and show that button's glyph (`ShortcutHint` with the action shows the Xbox or PlayStation glyph the engine reports, `InputActionLabel` does the same for a bare action). Do not make the player navigate onto the HUD.
- **Where focus starts:** on the element the player is most likely to act on, never on a dismiss control that B already performs. A Sheet starts on its first content control, or on the one its `initialFocus` names (the recommended item, the cheapest affordable upgrade). A confirmation with consequences starts on the safe choice; a Dialog starts on its cancel action. Focus returns to where the player was when the surface closes.
- **Focus is always visible and on screen:** one indicator, readable on every background, that never rests on a hidden, disabled or off-screen control.
- **Digital and single presses:** every UI works with the D-pad and A/B alone, one press at a time. Do not require the stick, two buttons at once, rapid presses or long holds to use a menu; offer a toggle where a hold is unavoidable.
- **Short routes:** a player should cross a screen in about six presses. Put commands above or beside a long list rather than after it, and keep frequent actions within one or two presses of where focus starts.
- **Reading at a distance:** at 1080p, text needs a body height of at least 26 pixels (XAG 101) and players must be able to scale it to 200 percent. Facet's ten-foot ladder keeps text at 28 pixels or more (24 for captions) and follows the preferred text size. Keep text and controls inside the TV-safe area, about 5 percent from each edge; `Composition` and `UI.environment().overscanInsets` handle it.
- **Feedback:** confirm navigation and selection with sound or haptics sparingly (`UI.feedback`, Button `haptic`); constant vibration is unpleasant. Help that appears when the selection rests should be short, since it can cover nearby targets.

Check each surface with the Studio Controller Emulator and the Xbox and PlayStation device simulators: the first stick push after spawning, each HUD button, opening every surface (where focus lands), Back from every depth, and the return to play.

## Scope specialized commands instead of reinventing navigation

Use `UI.commandScope(root, spec)` for a custom board or work area whose commands act on the currently focused keyed target. Give `targets` stable keys/nodes and `commands` clear meanings, bindings, and eligibility. The handle's `current` identifies the target; `focus(key)` requests a valid target; `actions` can drive `ShortcutHint`.

The scope does not invent directional navigation. It participates in existing focus, yields to text entry and higher-priority control/modal behavior, and ends with its owner. Use it to express a focused board command such as Rotate or Recall, not to duplicate every Button's ordinary activation. Keep target identity and command results in the game model.

Use `UI.adjustable(node, options)` for a genuinely custom adjustable control when Slider, Stepper, or another built-in value control cannot represent the task. `onAdjust` receives a direction; `axis` chooses horizontal, vertical, or no directional keys. Leave the other axis for navigation. `canAdjust` expresses limits, `repeats` enables held adjustment, and enabled/busy states control availability. Make the node one selection stop without competing selectable descendants. Always show what changes and how much; binding an axis is not enough to make adjustment discoverable.

## Connect world information without losing reliability

Use `UI.worldAnchor` when information or contextual actions belong to a world target. It supplies a projected anchor for a marker or RadialMenu; it does not itself draw the marker, validate proximity, or authorize the action.

Choose `target` and stable identity. `padding` adds clearance around the projected object. Default `offscreen = "hide"` is appropriate when a context should disappear with its visible target. `"retain"` preserves projected direction for an offscreen marker. Pass the retained anchor to `UI.WorldMarker`: it follows the target on screen and clamps to the screen edge with an arrow toward the target when the target is off screen or behind the camera. `occlusion = true` hides an anchor blocked from the camera, useful where showing through walls would mislead or reveal unintended information.

Use a stable portrait/detail area when a moving anchor would make reading or selection difficult. If the anchor becomes invalid, an attached open radial closes. Give critical information a reliable HUD alternative when occlusion/offscreen loss must not erase it. Keep the binding in an owned lifecycle and dispose it when no longer needed.

## Adapt to capabilities and viewing conditions

Use `UI.environment(source)` for the available room of the actual surface and facts such as input capabilities, preferred text size, viewing distance, and motion level. An embedded panel's room can differ from the full display. Use the facts relevant to each decision instead of treating a device name as a complete design specification.

Prefer adaptive controls and Composition forms for layout changes. Use `scaled(value, relativeTo)` for authored lengths that should follow distance and optionally a text role; text itself should use semantic type roles. Keep thumb targets tied to `thumbTarget`, not an arbitrary fraction of the display width. Explicit viewing-distance context can override an incorrect inference; a gamepad alone does not require a distant-view layout.

Exercise previews with touch, pointer, keyboard/gamepad, large text, short height, narrow width, and near/distant viewing independently where the game supports them. Preview facts alter layout; they do not prove that the corresponding physical input path or real viewing conditions have been tested.

## Combine visual, sound, and tactile feedback

Use feedback to distinguish changed selection, execution, accepted success, warning, and refusal. Keep these meanings consistent across screens. Sound and tactile feedback can reduce the need to look away from play, but required information needs an available visual equivalent. Likewise, a visual flash alone may be missed; persistent meaningful state remains important.

Facet's `pressHaptic` supports changes in state/value. Button `haptic` opts a game-specific press into feedback; `UI.feedback(kind)` can signal a later result such as confirmed success. The named kinds are `selection`, `impact`, `success`, `warning`, and `error`. Do not play success for an unconfirmed request or duplicate a control's existing feedback with another unconditional call.

Game-owned audio should follow the same semantic event and volume/preferences policy. Do not attach an equally loud sound to every focus move or replay a celebration on harmless UI reconstruction. Respect disabled or unavailable feedback hardware and player preferences. Test actual audio/haptics on supported hardware; an editor preview or screenshot cannot verify them.

## Make accessibility part of each task

Required actions need discoverable routes without hover, precise dragging, rapid tapping, or sustained holds where those are not the intended challenge. Provide selectable destination/command alternatives to transfer gestures and a finish route for paced text. Keep deadlines readable and avoid adding unnecessary interaction time to timed tasks.

Use meaningful names and visible labels for unfamiliar icons. Verify the actual accessibility behavior of custom controls rather than assuming a label or a focus ring supplies complete support. Keep reading order coherent with visual grouping. Use more than color for state, preserve preferred text size, and let content grow or move to an appropriate surface.

Captions, text chat, enlarged text, motion reduction, input prompts, and HUD layout can compete for the same room. Test those combinations together. A caption option that covers the only action target is not a complete solution. The compact form must preserve the player's task and chosen access settings at the same time.
