# Input, focus and access

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Players reach the same task with different hands, devices and needs.  Entry, understanding, action, correction and return work with whichever input the player uses.  A shortcut can make a route faster, but it is never the only way to find a required command.  The interface feels native when it follows each platform's conventions and never makes the player fight it.

## Read the constraints

Choose from facts, not from a device name.  `UI.environment` reports each constraint separately:

| Constraint | Fields | What they tell you |
| --- | --- | --- |
| Room | `viewportSize`, `sizeClass`, `heightClass`, `orientation`, `safeInsets`, `overscanInsets` | The space a layout can use.  `UI.environment(source)` reads a native container instead of the camera viewport. |
| Physical readability | `displaySize`, `isTenFoot`, `viewingDistanceSource`, `metricScale`, `preferredTextSize` | How large the screen is in the world, how far away it is and the player's text preference |
| Available input | `interactionClasses` | Every input the device has: pointer, touch, gamepad and keyboard |
| Input in use | `effectiveInput` | The input the player is using now, from Roblox's `PreferredInput` |
| Reach | `thumbTarget` and the theme's `targetSizes` | The size of a primary thumb action and the smallest target |
| Motion | `motionLevel`, `reducedMotion` | The player's motion preference |

Read `environment.environment` and `environment.viewingDistanceSource` for the exact sources and overrides.  Capabilities say what is available; `PreferredInput` estimates what the player is using.  Neither one disables another valid input.  Read `effectiveInput` instead of switching on every raw input event.

Keep selection, drafts, scroll position and route identity when the input changes.  A new glyph alone does not need a new screen.  When a layout must change, keep the selected object and the next action recognizable.

## Play contexts in Facet

The same facts combine differently on each device.  These are the combinations to design and check:

- **Television.**  `isTenFoot` is true for a native console interface or a large display without touch or a mouse.  Facet then scales theme metrics by `TEN_FOOT_SCALE` (1.5) and adds `overscanInsets` in Screen and a root Composition.  That keeps text and controls about 5 percent inside each edge.  It also stops `sizeClass` at `"regular"` and `heightClass` at `"medium"`, so a television never gets the densest arrangement.  Text keeps the console reading floors of 24 and 28 pixels by itself, so do not hand-tune text sizes for the television.  These defaults are a starting point, not proof of readability: check from across the room.
- **Desktop with a gamepad.**  A gamepad alone is not ten-foot.  The layout keeps desktop density, while prompts and glyphs follow `effectiveInput`.  A near player with a gamepad still needs useful comparison detail.
- **Handheld PC.**  `displaySize` comes from the physical screen, so a 7 inch handheld reports a small display even when its viewport is wide.  Its gamepad is usually the input in use and its touch screen also works.  It is not ten-foot.  Facet's type roles scale for viewing distance and the player's text size, not for pixel density.  Measure the letters on the device against the guide's handheld reference.  When they fall short, raise the type for that context instead of shrinking other content: `Factory-options.theme` accepts a readable of a package, so the game can switch to a package with larger type sizes.  Report the case as a Facet gap too.  A resized desktop window cannot prove handheld readability.
- **Phone.**  `thumbTarget` is 70 pixels in the neutral package when the short edge is 500 pixels or less, and 120 otherwise.  With touch or a gamepad, small buttons keep at least `targetSizes.minimum` (44 pixels in the neutral package).  Core UI safe insets do not include movement or action buttons; `Tasks.safe-layout` covers that clearance.
- **Desktop with a mouse.**  When the theme declares `targetSizes.pointer`, floating menu rows use it while the input is pointer only.  Hover paint follows the pointer.  Hover can preview but never holds required information.

## Own input by task

Distinguish gameplay, UI navigation, text editing, manipulation and modal response.  A UI activation never also jumps, steers or fires.  Use native InputAction and InputContext for game commands and Facet's input mechanisms for controls.  Never bind Roblox's reserved Escape or gamepad Start.

A Composition is already passive, with `gameplayGuard = false`, `engageOnPress = false` and `resignOnActivate = true`.  Do not add a second responder.  Divide the gamepad between play and the HUD.  Gameplay keeps the buttons play needs.  Each frequent HUD task gets a free button with a visible hint.  Players reach the other HUD buttons through ButtonSelect or one game action that selects them (`HUD-actions`).  Use `passive = false` for a dedicated interface.  For other HUD roots, use `UI.responder`; `engage` and `resign` make the transition explicit.  `engageOnPress = false` lets a press activate a control without taking the keyboard.

A page that replaces gameplay disables the game's gameplay InputContext and custom touch actions.  When it hides native movement controls, save and restore the previous `GuiService.TouchControlsEnabled` value.  Register the restoration with `Compose.cleanup` in the owning page, as `Tasks.pages` does.  Close a child surface without restoring gameplay while its parent still owns input.  A visible overlay does not pause the world; the game owns that decision.

Native InputContext priority and `Sink` resolve competing action bindings, and disabling the gameplay context makes ownership explicit.  The responder's Space guard is not a general suspension of game commands.  `Facet.gamepadContention` reports legacy player scripts that hold input the controls need.

## Make focus a useful route

Focus identifies the target of the next command.  Keep it distinct from persistent selection, equipped state and pending work.  Show focus on the actual actionable boundary, and let the control own its treatment instead of adding a second selection system.  Check its contrast over bright, busy and similar-colored gameplay.  Facet's default ring has a contrasting `chrome.focus.halo`; a custom bracket, glow or art treatment needs an equally visible boundary.

Choose the entry focus from the likely next action and the cost of an accidental activation.  Never start on a dismiss control that B already performs.  When a Sheet takes selection, it uses `initialFocus`, then its first available content control, then a pinned action, then Close or the grabber.  A Dialog prefers Cancel, then a non-destructive action.  A read-only result can make Close its useful action.  Keep this choice separate from the visual emphasis of the primary action.  Read `Selection.SelectedObject` for the exact behavior.

Make directional movement match the visible arrangement, and keyboard order match the reading and action order.  Put frequent commands near their content; never require a walk through a long collection to reach them.  Keep logical item identity when rows recycle.  Restore focus to the opener on return, or to a useful remaining target when the opener is gone.  A HUD command that opens nothing hands the selection back to the game, so the player presses it and keeps playing; Composition does this (`resignOnActivate` in `responder`).  Back follows the actual task path.  Explain an unavailable action in reachable text, even when its disabled control is skipped.

Focused content stays visible, including inside nested scroll regions.  Use `scrollToVisible` for an event such as revealing an invalid field; do not keep recentering against the player's reading position.  Use `focusSection` to make a group an entry region with a remembered or preferred target.  Use `commandScope` for commands on native selected targets and `adjustable` for specialized value controls; `commandScope` does not provide directional navigation.  A world-space target also needs a reachable command route, because a moving or occluded anchor is not a reliable place for sustained reading.

For world-space or VR work, read `Native-targets-and-boundaries` before you choose an interaction.  Facet's world surfaces are flat UI.  It supplies no ray, hand or gaze input and no VR layout mode, so plan and verify that input and comfort explicitly.

## Follow the gamepad conventions

These follow the Xbox Accessibility Guidelines, Microsoft's gamepad and TV guidance and Roblox's console guidelines.  Sony's and Nintendo's requirements are not public, and their system conventions agree.  Name buttons by the engine's glyphs, not by one brand's labels.


- ButtonA activates and ButtonB goes back on every surface.  Facet binds them consistently.  On PlayStation, Cross confirms in every region, Japan included, and Roblox reports it as ButtonA: never swap them.
- TabView provides shoulder navigation between peer tabs.  VirtualList, VirtualGrid, Table and Outline page with the triggers while they hold focus.
- X and Y are shortcuts for frequent, non-critical commands that also have a visible route.  The selected control can own a more specific adjustment; check its contract before you assign the same button.
- Roblox reserves the Start (Menu) button.  ButtonSelect (View) enters native GUI selection while `GuiService.AutoSelectGuiEnabled` is on.
- Every menu works with the D-pad, confirm and back, one press at a time.  Keep routes short; about six presses should cross a screen.

## Make commands discoverable

Use `ShortcutHint` with an InputAction where you can.  It reads the native preferred binding, including its display image or name.  Use the engine's reported glyph instead of assuming a controller brand.  Keep the action's name clear, such as "Equip" rather than just "A".  A hint describes a binding; it never creates one.

A control can carry its own glyph: put a `ShortcutHint` with `cap = false` on it.  Use `UI.ButtonGuide` for contextual commands without a visible control, such as paging or an action on the focused item.  List each command once, in button order.  Show the useful commands, at most about four, and never pad the list to fill it.  The guide is a noninteractive readout; native selection and the surface's entry focus skip it.

- An `action` entry names a native InputAction.  It shows while the action's native `Enabled` is on and the device has a binding.  Use actions from `commandScope`, or update their `Enabled`, to follow the current focus.
- A `keyCode` entry shows a platform glyph, including bumper and trigger pairs.  It stays visible, so update the entries when the command becomes unavailable.
- A `keys` entry uses written names that stay the same on every platform.

The guide follows `effectiveInput` and shows for Gamepad by default.  Add `KeyboardAndMouse` to `inputs` only when the game wants keyboard hints too; Touch is not supported.  Bind the `buttonGuides` app or controls option to a readable player setting, so players can hide persistent hints.  Keep the guide inside the owning surface's safe area.  In a Sheet, use `guide`: it stays outside every scroller and takes room from the body while visible, so check short layouts with it shown.  A guide hides while a modal that does not contain it is open.  Read `ButtonGuide.reference` and `Sheet.guide` for exact options.

Test input changes during a task, including a controller disconnecting.  Keep the draft and a usable exit, and update hints without committing or restarting the task.  Pointer and controller stay usable together; an event from one never locks out the other.

## Remove access barriers

Every route works with single digital presses.  None requires a pointer, analog precision, a chord, rapid repeats or a sustained hold.  When a gesture improves the task, provide an equivalent command with the same eligibility, result and recovery.  A radial or menu that opens on a hold also opens with a single press.  Where a hold is unavoidable, offer a toggle.  Shortcuts add to that route.  Make accessibility settings reachable before a task demands them.

Touch targets need adequate size, spacing and clearance from held thumbs and native movement controls.  Test the active hit area, not only the drawn icon.  Keep the active text field, its validation and its completion or cancellation route reachable while the on-screen keyboard is open.  Use native text editing and IME.  Dismissing the keyboard never silently commits a consequential action.

Use semantic text roles and let larger text and localization reflow.  Facet's text follows `GuiService.PreferredTextSize`; never use TextScaled to squeeze it into a fixed box.  Check the largest preference with real content, and keep icons that convey text readable too.  The theme's `controls.typography.minimumSize` sets the smallest role size, and it cannot be below 14 pixels.

For console viewing, the Xbox Accessibility Guidelines recommend a rendered text body height of 26 pixels or more at 1080p.  They also recommend an option to double it.  Body height includes ascenders, the main letter body and descenders.  These are guidelines for a viewing context, not universal Roblox TextSize values, and Facet's preference steps do not guarantee 200 percent scaling.  Verify rendered text at the intended distance and across the range the game offers.

Name icon-only actions.  Distinguish states with labels, shapes or patterns as well as color.  A read-only value can still need selection, copying and full contrast.  Combine visual, sound and haptic feedback where it helps, with no essential result in only one sensory channel.  Keep navigation feedback quiet enough for repeated use.  Help that appears on a resting selection is one short sentence.  Reduced motion keeps the same meaning and result without a pulse or animation.

## Check

Verify the complete route: the first entry into the HUD, the action, a correction, nested Back and the return to gameplay.  Include removed targets, input changes and settings changes while the task is open.  Use the Studio Controller Emulator in the Xbox and PlayStation device simulators for native behavior.  Check the first stick push after spawning with nothing selected, each HUD command, where focus lands on every surface and Back from every depth.  Use physical devices for reach, readability and hardware claims.

Sources: [XAG 101 text display](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101), [XAG 107 input](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107), [XAG 112 UI navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112), [XAG 113 focus handling](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/113), [Roblox PreferredInput](https://create.roblox.com/docs/reference/engine/classes/UserInputService#PreferredInput), [Roblox InputContext](https://create.roblox.com/docs/reference/engine/classes/InputContext), [Roblox PreferredTextSize](https://create.roblox.com/docs/reference/engine/classes/GuiService#PreferredTextSize) and [Valve's input guidance](https://partner.steamgames.com/doc/steamhardware/recommendations).
