# Changelog

## Unreleased

- Breaking: `UI.focusQuery` and the types `FocusQuery`, `FocusMove` and
  `FocusDirection` are removed. The engine makes each gamepad and arrow move.
  A value control keeps the selection on its axis only while its value can
  change in that direction. At its limit, the engine moves the selection. A
  tree row with nothing to collapse or expand lets the engine move the
  selection.

- A Table header works with a gamepad. The column divider is not a selection
  stop when the gamepad is the preferred input, thus the D-pad and the stick
  move from one heading to the next. While a heading is selected, L1 makes its
  column narrower and R1 makes it wider. Before, no move reached the heading
  of a middle column, and a move across a divider changed the column width.

- A Button with an icon and an authored width counts each icon and its gap in
  the minimum width. Before, the icon left the content box at a tight width.

- PageView dots have a 44 pixel target again. The painted dot is unchanged.

- A range Slider draws its fill on whole pixels under the handle centres.
  Before, the fill ended 1 pixel short of the upper handle.

- A mouse drag on a selected Move handle moves the row. Before, the drag armed
  a keyboard move. A mouse click on a Button row of a reorderable collection
  activates the Button.

- A Menu on a theme with no art carve keeps its rows in its panel. Before, the
  panel took 16 pixels of padding that its height did not include, and a sheet
  Menu with one row cut that row.

- A Popover and a Dialog take their rest state from the live size of the
  panel. Before, they could show one frame before their geometry was final.

- `UI.Composition` puts `topbar` regions side by side in the top bar strip.
  Before, the strip stacked them vertically, so two regions overflowed it or
  stepped down. The regions now step down when their total width does not fit.
  Outside the strip, they still lead the `top` zone as a column.

- Use Verify for reflected test classes, instance cloning, tags, ancestor lookup,
  focus and style maps. The fixture keeps explicit geometry and input providers.
  Benchmark percentile summaries use the shared Verify implementation.

- Card hover keeps measured collection rows steady. Native AnchorPoint centering
  avoids integer position steps. Cards with no primary action or menu do not
  paint an empty action plate over the next row.

- Use Verify for the headless engine hierarchy, signals, attributes and destruction.
  Keep borrowed modal content alive through Compose and preserve native StyleSheet
  panel padding. The shared Compose module
  also exposes `createSlot` and `geometry`.

- Use the same test library as Compose, the pinned `voidmeld/verify`, for cases,
  assertions, execution,
  worker reports, Studio reports, and checked evidence transport. Preserve the
  registered case IDs, numeric tolerances, tier rules, and package release gate.
  Verify is a test dependency. The consumer control API is unchanged.

- Nested Facet scrolling controls hand off a touch swipe at either scroll boundary to an ancestor that can move. Swipes over file tiles work too. Native scrolling keeps inertia and wheel behavior; modal and drag locks remain in force.

- NavigationSplitView uses the pane minimums and divider size for its default collapse threshold. Landscape views keep both panes when they fit. Explicit compact limits still apply. The Lab starts with a visible resize handle and names its compact destinations.

- Sheet keeps its normal content spacing inside the theme's panel art insets. Titles, scrolling content and actions clear thick frames such as Fantasy Parchment, including after theme and placement changes.

- ScrollView lets direct fill-height vertical stacks grow beyond the window when their content needs more space. Native automatic sizing and flex growth preserve pane minimums and produce scrollable overflow. Compact Files moves search and editing options into a scrolling sheet and groups file commands in Actions, leaving room for the active split pane.

- Editable grid tiles reserve a bottom area for item actions and include it in measured item heights. The circular utility action button leaves the tile content at full width instead of squeezing it into a row-style trailing gutter. Lists and tables retain trailing actions.

- NavigationSplitView can disable resizing with `resizable = false` and keep its grip visible with `alwaysShowResizeHandle = true`. Disabled resizing keeps a separator without a drag target or focus stop. Files exposes Linked and Inbox in a visible Views menu at compact sizes instead of hiding these choices with search options.

- NavigationSplitView supports top/bottom panes with `axis = "y"` and height limits. It uses native vertical dragging and Up/Down focus traversal; the default stays side by side. Both layouts retain their panes when compact navigation replaces the divider. The Lab includes both axes.
- Grid resizing creates inline editors on first use and shares ancestor input observers. Geometry reads finish before updates publish on the next Heartbeat. This avoids repeated row construction work and the same-frame deferred callback limit that could freeze layout; geometry feedback is not drained recursively within one frame.

- Batch native geometry measurements after construction and layout events. Split resizing no longer publishes control and skin measurements during the engine's layout pass. Pending measurements leave with their Compose owners.

- Add NavigationSplitView with resizable related panes, compact and TV navigation, touch dragging and gamepad focus through the divider. The File library uses nested splits for Files, Inbox and Linked view. Outline Left navigation yields at a collapsed root so focus can leave the pane.

- Inline cell editing preserves field geometry and avoids a duplicate caption. Context menus open at the secondary-click position. Table and outline resize targets straddle their dividers and use the current input minimum. Native touch resize and reorder gestures hold ancestor scrolling, and focused move handles remain draggable with touch. Gamepad drop and cancel bring the original item into view before restoring focus. Lab editing examples separate container and cell permissions; reorder presets update their models.

- Field editing is independent of collection edit mode. Table columns accept `editable(item)`; custom cells use `CellEditor.enabled`. Text and number cells appear as labels until editing starts. Shared item actions, F2 and selected-name mouse clicks open the field, with configurable `editLabel` text. Touch and gamepad show an item-actions button; gamepad X opens the same menu. Built-in table editors use the same native inset and alignment as custom cells. Action menus appear once per row and reserve column space. Active fields stay visible and return focus to their row. Pointer drag detectors yield to gamepad navigation.
- Collection insertion shows its insertion marker without a redundant outline around the entire scroller. The Outline Lab expanded preset has independent state, and row-drop examples visibly copy a lap count.

- Drag sources can set `statusLabels = false` to hide operation, rejection and pending labels. Armed input instructions, drop validation, highlights and animations remain available.

- Lists, grids, outlines and tables share `rowDrop(current, key)` for item destinations. Row edges retain insertion, while the row center accepts an item drop. Folder transfers between linked views reach the model; gamepad users can open outline branches while choosing a destination. Native drag detectors use the final release position for quick drags.
- Collections construct move controls only when needed and avoid redundant focus subscriptions and table truncation updates. Drag feedback stays above stacked previews. Ordinary mouse and touch moves omit the redundant Move badge; copy, apply, rejection, pending completion and armed input instructions remain visible.

- Outline reveals branch rows progressively so expansion keeps the mounted row count bounded. Collections cache measurements between changes, and linear keyboard/gamepad focus no longer rebuilds pixel positions during layout. Leaf rows reserve indentation without constructing hidden disclosure buttons. Drag insertion searches measured positions and caches item order instead of scanning every item on each pointer update; model changes invalidate the cache and drops still validate current items.

- Vertical collection rows use flat theme highlights and compact inline editors. Disclosure buttons retain their authored square size. Custom table cells align vertically; pointer fields stay compact while touch and gamepad targets grow. The Outline Lab uses a focused hierarchy playground and a two-column editing example. Files uses compact horizontal list/table cells and a flexible filename column.

- Outline extends collection selection, editing and drag behavior with keyed children, shared expansion and animated disclosure. Tables support the same hierarchy with sibling sorting. Native content measurements keep bitmap themes and enlarged text within rows; reduced motion makes expansion immediate. The Lab has an Outline page, and the Files showcase supports folders, folder drops, creation and navigation on desktop, touch and gamepad.
- Nested NavigationStacks derive gamepad Back priority from native ancestry, including stacks built with separate controls instances. Detector-captured row taps preserve double-click opening while a drag or cancelled gesture resets the click sequence. Collapsing an outline returns focused descendants to their nearest visible ancestor.

- Plain touch, gamepad and keyboard activation replaces collection selection. Edit mode explicitly enables additive selection across tables, lists and grids; desktop modifier selection is unchanged.

- Drag previews preserve the proportional pickup point and source scale. World-drop hit testing uses native styled transparency so transparent layout frames do not block destinations.

- Frame-backed collection cells forward native drag-detector taps to selection, including after a drop. Accepted previews shrink at the destination with theme-timed native motion. Grid edit controls reserve their space on touch/gamepad, and the File library keeps name fields mounted when editing is disabled.
- Transparent native control plates hide their shadows, so Glossy Mobile segments remain readable at rest. The File library view picker follows theme corners and names its transfer panel Show Inbox.

- Drop highlights and insertion markers appear only for accepted destinations. A source-only palette is not a drop target. Rejected and cancelled drag previews return to the source with native TweenService motion and honor reduced motion.
- Themed panels now receive native UIPadding with a theme spacing floor, including bitmap themes. Explicit padding remains available.

- Drag and drop shares one validated session across UI, collections, and registered Workspace targets. Native detectors drive pointer pickup; stable insertion neighbors, copy/move/apply operations, pending completion, selection-safe activation, and native hit testing support transfers. The File library adds an Inbox. Facet Lab has a Drag and drop demo for world appearance and working Editing sections on Table, VirtualList, and VirtualGrid.

- Grid drag previews retain tile dimensions and stack the selected cards. Grid insertion tracks both axes. Grid edit controls occupy a top strip so narrow cells retain their content width. The Showcase File library supports selected-item reordering and a Grid size slider with compact, multi-column tiles.
- Virtual lists and grids apply selected theme paint to the cell owner, including its text. The Showcase File library uses a compact icon view picker, direct desktop editing, Edit/Done for touch and gamepad, one Enable editing toggle, and two initial file labels. A segmented Picker with an explicit `controlSize` now keeps its native minimum height on that size instead of adding its internal inset.

- Containers share authoritative selection through `selectionFrom`, item actions and edit marks. `CellEditor` supplies model-owned drafts, validation, rejection and cancellation for custom cells and built-in table editors. Tables forward focus and retention options and support column alignment; grids support `minColumnWidth`. The Showcase File library shows one file model as icons, rich rows and linked tables, with creation, editing, deletion and Undo.

- Check every repository Luau file in strict mode with pinned Roblox and Lune types. The complete check rejects every type diagnostic and invalid API probe.
- Export `RowActionsOptions` and `SheetDetent` for consumer annotations. Match public types to supported nullable bindings, theme overrides and image resource factories.

- Outpost’s world terminal fits the live Showcase space on phones and after rotation; short views scroll the controls.
- Held touch names and help clear the actual fingertip. Radial names wrap in themed tooltip plates, and opening a radial menu stays neutral until a deliberate drag.

- Lab automatic input follows the selected device. Lab and showcase overlays use the preview frame's live bounds. Color and date pickers stay within those bounds after rotation, including when the field moves offscreen.
- NavigationStack restores focus after page motion settles. Initial focus prefers a control inside a scroll container over the container itself.
- Nested Screens add only the console overscan margin that their bounds still overlap.
- The combined showcase menu has one gamepad shortcut and hint, LB. It keeps the last selected section when it opens again.

- Check in the Virtual Monitors and Facet Farm place builds under `examples/places`. The standard example build refreshes both. Facet Flap remains part of Virtual Monitors. Retire the Glade, Cartwheel, Sipworks and Foyer standalone place builds; keep their source and regression fixtures.

- Directional focus uses upstream `Compose.focusNeighbor`; the duplicate Facet algorithm is removed.
- Filled top tabs use the theme's `metrics.radii.tab`. Neutral uses pills; the example themes set corners to match their artwork.
- Upgrade the pinned Compose module to `dbf518ac3d28846c81ab0cf8f74cbc76ad22b30a`, adding `Compose.TileCollection` and `Compose.focusNeighbor`. Virtual Monitors adds Facet Flap as its fourth app, with a scrolling tile course, flight controls, scoring, retry and pause on leaving the active monitor.

- Appearing Alert, Dialog, Menu, Popover, Callout and Help surfaces keep their text at its settled size while the surrounding panel grows. Native anchoring keeps that content in place through the final frame; scaling the text with the panel caused glyph, wrapping and scrollbar pops. Theme shadows now fade with the surface, including interrupted closing and reopening.
- Toasts measure the overlay parent that receives them, so text wraps within an embedded phone preview or other bounded overlay instead of using the entire screen width.
- Table headings cover the persistent scrollbar gutter. Heading measurement, column resizing and horizontal scrolling use logical layout units so enlarged text redraws at the resized width under display scaling.
- The Facet Lab and its optional Foundation Light and Dark theme models live in `examples/facet-lab`. The control list uses larger text. Foundation remains an explicit installation choice outside the default Facet package.
- Standard live verification now includes overlay continuity and table resizing. Continuity checks detect text-size pops, transient scrollbars, final-frame movement, toast overflow and shadows that outlast their closing surface.
- A framed TextInput or Search (one with a label, hint, `controlSize`, `appearance` or `corners`) draws the focus look around the whole field, search icon included; it ringed only the inner text box. `FacetFocusPart` accepts `..` to name an ancestor.
- A NavigationStack's bar title is inset by the control's horizontal padding on both sides. A root page's leading title sat flush against the stack's left edge.
- A segmented Picker with `corners = "pill"` (or `"square"`) gives its selection highlight the same corners. The highlight carried its own `UICorner`, which beat the theme's corner rule, so it stayed at 8 pixels inside a pill strip.
- DisclosureGroup content is inset on both sides by the control's horizontal padding (12 pixels in Neutral), in line with the header label. An `outline` group keeps no side inset, and `indent` still sets the left inset.
- A RadialMenu folds back into its centre when it closes, the reverse of its opening; it only faded where it was.
- A RadialMenu level that replaces its parent (`navigation = "replace"`) keeps the parent ring's band, so its items sit as far from the centre as the ones they replaced. A corner menu's two-item submenu sat about a third closer to the corner, because a level with fewer items needs a thinner band.
- A Toast's fade runs on the theme's new `motion.easing.trail` (`linear` in Neutral) while its slide keeps Cubic Out. The fade followed the slide's curve, so it was 80 percent done before the row was in view and read as a plain slide.
- A segmented strip's segments start at their labels' widths and share only the space left over, so a long label gets the room it needs before a short neighbour gets spare room. The 44 pixel touch floor on a strip segment is now 44 including its padding: the engine adds a padded `AutomaticSize` object's padding on top of its `UISizeConstraint.MinSize`, so every short text segment was 68 pixels wide and squeezed its neighbours (an icon-only segment keeps a 44 pixel floor, since its padding is the theme inset). `api.md` states the sharing rule.
- A segmented Picker's segment never breaks a word across lines. Under a `UIScale` the engine sized a hugging (`AutomaticSize` X) wrapped label to its one-line width at one precision and wrapped it at another, so the Showcase TV preview showed "Erro" / "r". A segment label now stays on one line while it fits; when it overflows it wraps at word boundaries; and when a word cannot fit its own line (a crowded strip) the label stays on one line and ends in an ellipsis (`TextTruncate.AtEnd`) instead of breaking the word, on both axes. Radio and card captions stay on one line while they fit and otherwise keep the engine's own wrapping, so a script written without spaces (Japanese, Chinese, Thai) still wraps between characters. The decision follows the room, the text, the styled size and font, the segment count and the segment's own width, and settles without re-deciding on its own writes. The full label stays the button's accessible name.
- A Button with any authored `Size` whose height is 0 and no `AutomaticSize` is floored at the control height (44, or 66 at ten feet), as it already was with `AutomaticSize = Y`; it hugged its text instead, well below the tap target. This covers a width-only Size (`UDim2.new(1, 0, 0, 0)`), a zero `Size` that relies on hugging (it now hugs its width and floors its height), and a label-less Picker whose `Size` has zero height (its trigger inherits the Size).
- Tab, Shift+Tab and Escape work from a real keyboard. The engine's own bindings take both keys ahead of every input action and ContextActionService binding (measured on main too), so Facet's traversal and its Escape actions never ran; Facet now also reads them from `UserInputService.InputBegan` and runs the one enabled Facet action with the highest priority, once per press. Escape still opens the Roblox menu as well (engine-reserved); Facet's top modal closes on the same press, and an Escape while the Roblox menu is open closes nothing. One press runs one action across every `Facet.controls` set on the same `UserInputService`. Tab leaves only a Facet text field and does nothing with Ctrl, Alt or Meta held. With no navigation gamepad listed, the stick follows the last gamepad used.
- A ColorPicker's saturation and brightness plane listens for `SelectionGained`, so the engine's D-pad ranks it with buttons instead of after all of them.
- Tab and Shift+Tab skip scroll containers, except one that is itself a selection stop: an overflowing Dialog body, a Collection or a Pagination root. A plain scroll container around the selected control swallowed the Tab and the walk stopped.
- `UI.focusQuery` finds a `SelectionGroup` or a scroll container above the control when a Folder sits between them (the engine does).
- A value control at a limit passes the selection on only for a D-pad, arrow or stick press toward that limit; L1, R1, Comma and Period at the limit keep the selection. The pass follows the game's own `NextSelection*` link from the control when it has one (as `UI.focusQuery` reports), and the stick, like the D-pad, changes nothing while the control is under a non-interactable or hidden ancestor, and only a navigation gamepad's stick adjusts (`UserInputService:GetNavigationGamepads`, which lists every gamepad unless the game calls `SetNavigationGamepad`); held-key checks read the same gamepads.
- A D-pad move reaches a multi-line TextInput with `visibleLines` that is still below the screen. The engine skips a control inside a scroll container whose window is off the screen, so the last field on a scrolling page could not be selected; its `Viewport` is now selectable and passes the selection to the field.
- `UI.focusQuery` ranks moves out of the beam the way the engine does. With no candidate overlapping on the cross axis, the engine takes a candidate whose centre lies within 45 degrees of the move by its centre offset, even when a nearer one sits at a steeper angle; the query ranked them by gap plus twice the centre offset. A candidate that starts past the selected control's centre now counts as ahead (a control inside a row is ahead of the row), and a control in a nested scroll container whose window is off the screen is not a target from outside it.
- One D-pad press takes one step in a RadialMenu. With engine navigation off while a ring is open, the press reached the ring's direction action twice (the input action and the selection fallback), so a corner ring skipped its middle item. A press whose release never arrives (the action switched off mid-hold) no longer blocks the selection fallback: the guard clears when the key is released, when the action is switched off or on, and when the selection moves with no bound key down.
- RadialMenu D-pad: a direction pointing back across the centre selects the centre control, and the next press the item on the other side; from the centre each direction selects the item nearest that direction; other directions move to the neighbouring item along the ring. A corner ring's middle item could not be reached with the D-pad.
- One B or Escape press closes one modal. Closing a menu opened from inside a modal (the date picker's month or year list) enabled the modal's Back action while the same press was still being delivered, so it closed the date picker too. An input action now ignores a press whose key was already down when the action became enabled, until that key is released.
- Dismissing a Callout from inside its plate (Got it, an action, the close control, B or Escape) hands the selection to the callout's anchor at once. The plate's buttons stop being selectable as it leaves, and the engine had already moved the selection to another control on the page before the plate was gone.
- An Instance given to a Sheet (`content`, `header` or `hero.content`), a DisclosureGroup, CollapsibleView or Callout (`content`), or a NavigationStack destination (`content`) shows again after the surface closes, pops or is rebuilt. The dismissal destroyed that Instance with the surface, so the next presentation failed (`FacetError` on the Sheet) and closed at once; every presenter now takes an Instance out before the surface is destroyed. Popover, Dialog and Toast take only content factories.
- A D-pad move with nothing in its direction no longer jumps to the first control of the page. The engine selected the scroll container around the selected control, and Facet passed the selection to the container's first control; it now keeps the selected control.
- `UI.focusQuery` follows the engine on scroll containers: a control clipped out of its scroll container's window is not a target from outside that container (from inside it, it still is), and a selectable scroll container ranks by its own rectangle like any control, reporting the control the container passes the selection to.
- A D-pad move reaches a Slider, Stepper, Rating, LevelPicker or `UI.adjustable` again. The engine's D-pad search ranks every candidate that has a `SelectionGained`, `SelectionLost`, `Activated` or `MouseButton1Click` listener ahead of those without one, so from a Slider it jumped past the value controls to the nearest button in that direction (Up from the bottom Slider on a form landed on a toolbar button). Each value control's stop now listens for `SelectionGained`.
- A Slider's drag detectors, a row's swipe detector (RowActions) and a Sheet's panel drag detector switch off while the gamepad is the preferred input and back on at the next touch or mouse input. An enabled `UIDragDetector` made its track, or a row's swipe grip, a D-pad and stick target although neither is selectable. A row swipe in progress when its detector switches off ends there and the row returns to its resting state without opening a tray (a Slider drag already cancelled).
- A disabled Stepper or `UI.adjustable` node is no longer a selection stop; it becomes one again when enabled (a Slider already worked this way). A busy `UI.adjustable` stays a stop and ignores presses until it is idle. Value control roots carry a `disabled` attribute. The Slider's and the Stepper's accessible label is on the control itself, the object that takes the selection (a Slider without a label announces its value); `Track` and `ThumbStop` no longer carry it.
- A scroll container with no controls passes a directional move to the control whose leading edge is nearest among those in line with the move (the centre offset only breaks a tie); it used to weigh the gap and twice the centre offset together.
- `UI.focusQuery(from?)` reports, for Up, Down, Left and Right, what a D-pad or arrow move from a control selects and the rule that decides it (`capture`, `link`, `beam`, `stop` or `none`), without moving the selection. New types `FocusQuery`, `FocusMove` and `FocusDirection`.
- **Breaking: `UI.adjustable` makes its node the one selection stop** (it sets `Selectable = true` on the node) and adjusts only while the node itself is selected, not a descendant. Give the node no selectable descendants.
- **Breaking: a range Slider is one stop, and A (gamepad) or Return (keyboard) switches the handle that Left and Right move.** The selection always lands on the lower handle; the focus look is drawn on the handle being moved, and the Slider's `adjusting` attribute and accessible label name it. The gamepad "press A to engage a handle" mode is gone and Tab no longer visits each handle. Touch and mouse still drag either handle. A game that selected `HandleLower` or `HandleUpper` selects the Slider instead.
- **Breaking: a Stepper is one gamepad and keyboard stop.** Its − and + buttons are no longer selectable (they still respond to touch and the mouse); the Stepper itself takes the selection, Left and Right change the value, and Up and Down leave it. A game that selected `Decrease` or `Increase` by name selects the Stepper instead.
- The left thumbstick changes a selected Slider, Stepper, Rating, LevelPicker or `UI.adjustable` like the D-pad: a push past half-way along the control's axis (and clearly more along it than across) steps once, holding repeats, the push counts as held until it falls back below about a third, so a wobble near half-way does not step again, and a push on the other axis still moves the selection. The stick is read from `UserInputService`, because the engine keeps the D-pad and the stick from input actions while anything is selected. A stick already pushed when the selection lands waits for a release first.
- **Breaking: a value control keeps its adjust axis while a press is held.** While a Slider, Stepper, Rating, LevelPicker or `UI.adjustable` has the selection, Left and Right (Up and Down for a vertical control) change the value; a held or repeating press stops at the minimum or maximum instead of moving the selection away, and a new press toward a limit the value is already at moves the selection to the next control that way (it used to leave as soon as the value reached the limit). The control claims the axis only while the control itself is selected, never while a part inside it is. `UI.adjustable`'s `canAdjust` returning `false` now makes the press do nothing instead of giving the arrow back to navigation.
- **Breaking: a Slider is one gamepad and keyboard stop: the whole Slider** (its label, track and value). Its track and thumb are no longer selectable; the focus look stays on the thumb (or the track when the thumb is hidden) through `FacetFocusPart`. The engine now measures the Slider by its whole frame, so a move from a wide Slider reaches a narrow control beside its label (the gamepad skip past a vertical Slider). A game that selected `Track` or `ThumbStop` selects the Slider instead.
- `UI.focusRing` draws the look on a named part of the selected object: a string attribute `FacetFocusPart` (a `/` path of child names) puts the look on that descendant, sized to it and shaped by its `UICorner`, and the look follows the part as it moves.
- At motion level `limited` a Notice lands its height at once and fades its content in over `reducedFade`, and a close fades it out before `onDismiss` runs (it cut in and out). A presentation reversed mid-entrance or mid-exit continues its fade from its current opacity instead of stepping for a frame.
- **Breaking: a Dialog is measured at rest like an Alert**, and the rest wait now runs at every motion level (it was skipped under reduced motion). A Dialog waits invisible at scale 1 until its size holds for one frame (normally two frames, at most `motion.restLimit`), then scales in from that size and holds it as a fixed box until it lands, so it no longer grows 4 pixels (or 21 at motion level `none`) after it shows. At `limited` and `none` every rest-gated presentation now appears up to two frames later, whole.
- **Breaking: a switch Toggle's knob glides** with its track colour on `motion.springs.control` instead of teleporting between its ends; a change mid-flight turns it smoothly, and it lands at once below motion level `normal`.
- **Breaking: a PageView fling decelerates without overshoot** (`metrics.motion.styles.fling` is `Quint`, was `Back`); the page still turns on the native `UIPageLayout`.
- **Breaking: RadialMenu Back folds the submenu into its item and re-opens the parent ring around it**, the reverse of the unfold: the leaving slots sweep along the ring into the item they came from as they fade, and the parent slots start at that item and sweep to their places (they re-expanded from the centre). A ring that closes and opens again still blooms from the centre.
- **Breaking: a Sheet's scrim lightens as you drag it toward dismissal, and a fast flick settles with a small overshoot.** While you drag a sheet (or pull a side sheet) that can be dismissed, the scrim's opacity follows the painted height over its detent height (or the pull over the panel width); a dismissal-disabled sheet keeps its scrim. A release faster than `metrics.motion.fling.bounceSpeed` (800 pixels per second) settles on `motion.springs.flick` (0.3 second period, damping 0.8) and passes its detent by under 2 percent before it comes back; slower releases and programmatic changes stay critically damped. `settle.launch` takes an optional spring.
- **Breaking: at motion level `limited` (the engine's Reduce Motion) a presentation cross-fades over 0.15 seconds** (`metrics.motion.reducedFade`, `easing.fade`) instead of cutting in and out; it still never scales or slides. This covers Alert, Dialog, Popover, Menu (pointer and sheet form), Callout, the Button `help` plate and Sheet (its panel fades with the scrim), and Toast (fades in place, even with `fade = false`), TabView (its default cross-fade runs over `reducedFade`; a custom `transition` keeps its timing), NavigationStack push (the new page fades in with no slide; a pop is immediate) and DisclosureGroup/CollapsibleView (the height lands at once, the content fades). Level `none` keeps the instant cut. Paint transitions keep their timing under `limited` (colour fades are not travel) and are instant only under `none`, so the theme StyleSheet no longer watches `GuiService.ReducedMotionEnabled`. `reducedFade` must be above 0.
- **Breaking: the `reducedMotion` option is replaced by `motionLevel`** on `Facet.controls`, `Facet.app` and `themes.createStyleSheet`: `"normal"` (full motion), `"limited"` or `"none"`. If you omit it, Facet follows the device: `GuiService.ReducedMotionEnabled` gives `"limited"`, otherwise `"normal"`, and the effective level is the stronger of the game's and the device's (`normal` < `limited` < `none`), so a game can add reduction but never remove a player's Reduce Motion. Passing `reducedMotion` is an error, and so is an unknown level when the controls are made; an unknown value a readable delivers later (for example a stale saved setting) follows the device level with one warning. A theme StyleSheet built without its own `motionLevel` uses the levels given to `Facet.controls` on the same runtime (the strongest wins). `UI.environment()` adds `motionLevel`; its `reducedMotion` is `motionLevel ~= "normal"`. Migrate `reducedMotion = true` to `motionLevel = "none"` for the old instant behaviour, and drop `reducedMotion = false`. The per-control `reducedMotion` options on List, Table, VirtualList, VirtualGrid and RowActions stay booleans. The Showcase Settings Motion control offers Device, Game: Normal, Game: Limited and Game: None.
- **Breaking: a presentation fades ahead of its travel.** An Alert, Dialog, Popover, Menu, Callout, Button `help` plate and a Sheet's scrim are opaque once 60 percent of the entrance time has run and clear once half of the exit time has run, while the scale, slide or rise still runs its whole time (new tokens `metrics.motion.presentFadeIn` 0.6 and `presentFadeOut` 0.5). `surfaces.appearance` returns `{ opacity, travel }` (internal).
- The theme StyleSheet carries its paint timings as TweenInfo attributes (`FacetMotionNormal`, `FacetMotionPress`, `FacetMotionHover`) and every rule's transitions reference them as `$` tokens, the engine's own way to share a transition. A timing change (a theme with a different `motion.normal`, reduced motion, `transition = false`) now updates the three attributes and rewrites no rule. A game rule can reference the same tokens but must not write them; the sheet writes a cleared or overwritten token back. `GetPropertyTransitions()` on a Facet rule returns the token string. `fling.projection` may be 0.
- `themes.define` validates `metrics.motion`: durations and role timings from 0 to 10 seconds, `restLimit` up to 1 second, shares from 0 to 1, spring periods and damping above 0, materialize scales and fling values above 0, easing names that `Compose.easing` has and style names that `Enum.EasingStyle` has. A package that breaks one is refused with a report entry instead of stalling or crashing a control.
- **Breaking: a pointer Menu's submenu grows from the row you chose**, and Back grows the parent from the side the child was on, instead of re-materialising the panel from its corner. A keyboard or gamepad Right into a submenu takes the same path as a click.
- **Breaking: a Menu shown as a sheet slides up from the bottom edge with the Sheet's timing** (0.3 seconds in, 0.2 seconds out) instead of growing from its bottom centre, and its level changes cross-fade the rows as they slide. The cross-fade runs on a window-sized `MenuLevel` frame around `MenuScroll`, so a long level never renders through a CanvasGroup as tall as its rows.
- **Breaking: a press highlights in 0.08 seconds and a hover in 0.15 seconds** (`metrics.motion.press`/`hover`, never slower than `normal`); a release and other paint changes keep `motion.normal`.
- A RowActions swipe settles from the finger's release velocity: the tray keeps moving in the swipe's direction on the first frame after release instead of stopping and restarting, and a row grabbed mid-settle continues from where it is drawn (`motion.springs.snappy`). A snapping VirtualList or VirtualGrid glides to its boundary on a critically damped spring (`motion.springs.control`, 0.25 second period) that starts gently from rest instead of a fixed 0.18 second Cubic Out; the `durations.snap` token is gone.
- **Breaking: a Sheet detent change eases on a spring instead of a linear 0.2 second tween.** A programmatic or keyboard/gamepad detent change, a released drag and a side sheet's released pull all settle on one critically damped spring (`motion.springs.sheet`, a 0.4 second period, about 0.45 seconds to settle) seeded with the release velocity, so a flick carries into its settle and a reversal mid-flight turns smoothly. A side sheet grabbed while it springs back continues from where it is drawn. The `durations.sheetDetent` and `durations.sheetPull` tokens are gone.
- A Menu, each Menu level (a submenu or Back), a Callout and a Button `help` plate measure themselves at rest before they scale in, as a Popover and an Alert already did: each waits (normally two frames, at most `motion.restLimit`) at scale 1 and invisible, and its placement and tail read that rested size while the scale runs. A Callout and a help plate also hold that rested size as a fixed box (`AutomaticSize` off) while they scale, so the engine cannot re-measure their text under the scale and grow them on the last frame. The Popover gate now waits for the whole panel, not only its body.
- Theme packages hold every motion value: `metrics.motion` now carries role timings (`popover`, `dialog`, `reveal`, `sheet`, `toast`, `radial`), `durations`, `springs`, `materialize` scales, `distances`, `easing` and `styles`, with Facet Neutral's values unchanged. A package overrides any one of them, and the rest come from Neutral. The metrics type `motion` is now `ThemeTypes.MotionMetrics`, and controls read it through `ctx.motionTiming`, `ctx.motionSpring`, `ctx.motionEase` and `ctx.motionStyle`.
- The neutral theme adds three motion tokens that controls read instead of hard-coded values: `motion.revealFadeShare` (0.5, the share of a DisclosureGroup or CollapsibleView reveal the content fades over), `motion.unfoldStart` (0.25, the arc a RadialMenu submenu wedge unfolds from) and `motion.restLimit` (0.25 seconds, the longest an Alert or Popover waits for its content to rest). A package that omits them inherits the neutral values.
- A theme StyleSheet preloads the package's art (`ContentProvider:PreloadAsync` on every `package.assets` entry not marked `preload = "lazy"`) the first time it applies the package, so a skinned panel that first opens later, such as a Pixel Quest CollapsibleView, no longer opens with no art and no backdrop while its image downloads. `createStyleSheet` takes an optional `contentProvider`. A CollapsibleView's expanding plate also no longer jumps in height and position mid-open: its themed inset is measured from live sizes.
- A fixed-width Button no longer sticks in its tight padding (`facet-button-tight`) after a label that fits. The padding gave way on a fit report the engine had not yet refreshed (taken before the theme's font and size arrived) and only a width change released it. It now decides from the live `TextFits` and `AbsoluteSize`, re-tests when the text, the styled `TextSize` or the styled `FontFace` changes, and watches only while the button does not grow on X.
- A Table's "…" Details button is a `utility` button, like the reorder handle beside it: it has no plate at rest, so a selected row's fill shows behind it and the row's bottom separator runs under it in pointer and edit modes.
- A shared fade (Toast, Alert, Popover pages, RadialMenu, DisclosureGroup and CollapsibleView content) now fades the theme outline with the fill and the content. The theme's `::UIStroke` is a phantom that no per-node value reaches, so every stroke rule `S::UIStroke` gains a twin `S > .facet-fade-stroke` that styles a real `UIStroke` (`FadeStroke`, tagged `facet-fade-stroke`) each `ctx.fade` node carries, disabled at rest. While a fade runs the node is tagged `facet-fading`: its phantom stroke is disabled, the real stroke is enabled in the same style pass, and its `UIGradient` follows the fade. A game's own stroke rules get the same twin.
- **Breaking: an anchored menu insets its rows by `space.xs` and rounds every row's highlight to `radii.panel - space.xs`**, so a selected or hovered row stays inside the card's stroke and corners. The `facet-menu-end` tag and its `::UICorner` rule are gone; a game rule on `facet-menu-end` no longer matches.
- **Breaking: a Table holds a custom `render` cell's content in an `Inset` frame** (tag `facet-tablecellinset`) that the theme places at the value inset, so custom cells, headings and text values start at the same x. The content's parent is the `Inset` frame, not the cell. A heading takes the value inset even when its button latched `facet-button-tight`, the header band is as wide as the rows (not the scroll bar gutter), and the Edit toolbar keeps `space.s` above the header.
- A Popover and an Alert measure their content at rest before the scale-in and hold that height until it ends, so the panel no longer grows 1 or 2 pixels as the entrance finishes; the body height is the measured canvas in layout units, so a fitting body never shows a scroll bar. A Popover whose content fills its width (`Size.X.Scale > 0`, no automatic width) gets the standard popup width (`controls.popup.panelWidth`, within `maxWidth` and the screen) instead of collapsing to its minimum sizes.
- An icon-only segment and a RadialMenu item that shows only its icon take the glyph padding (`facet-button-glyph`), so a skinned theme's insets no longer push the icon off-centre. The RadialMenu's full-screen panel is a `facet-panel` only in its list fallback, so a skinned panel inset no longer shifts the ring off its launcher. A CollapsibleView's expanded content fits inside the plate's themed inset (a `ContentBox` frame measures it) and the plate grows by it.
- Showcase: the demo panel rebuilds its demo list each time Demos shows (returning from Settings reused destroyed buttons and collapsed the card), and the stray "Section" caption is gone. The race-day picker's hint names its season, which bounds its years.
- A modifier key pressed alone (Shift, Control, Alt, Meta or Command/Super) no longer switches Facet to its keyboard-and-mouse layouts. The engine sets `UserInputService.PreferredInput` to `KeyboardAndMouse` on the bare key down, so on a touch device a system shortcut such as Command+Shift+5 flipped every control to its pointer form (a Table lost its Edit toolbar until the next tap). Facet's shared `PreferredInput` observation and the theme StyleSheet's hover paint now hold that change until another key or mouse button is pressed or the mouse moves or scrolls.
- A RadialMenu submenu unfolds from the chosen item again, as before 0.12: each new slot starts at that item's angle and band and sweeps along the ring to its place, and a wedge grows from a quarter of its arc. 0.12 only pulled a slot 30 percent toward the item, so on a full ring most slots rose out of the centre.
- **Breaking: edit mode selects rows on every input.** While `editing` is true, a tap, click, Return or A on a row of a selectable List or Table toggles its selection and no longer runs `onActivate` (a single-selection collection selects that row, and a second press clears it). A `selectionMode = "multiple"` collection shows the selection ring on each row in edit mode instead of the per-row minus (a deletable single-selection collection keeps the minus). A deletable Table's own toolbar shows `Delete` (`DeleteSelected`) beside `Edit` while it edits on touch, keyboard and mouse; on a gamepad X removes the selected rows as before. `editing` moves from `ReorderOptions` to `SelectionOptions` in the collection types.
- **Breaking: a RadialMenu long press names the item without picking it.** A finger held still on an item for 0.4 seconds shows its name; that release does nothing and a second tap picks it. A press that slides more than 14 pixels stays a pick-on-release gesture.
- DisclosureGroup and CollapsibleView fade their content over the first half of the open (0.125 seconds) and out over the first half of the close (0.1 seconds), through the shared `ctx.fade` path; the height or the panel still moves for the whole 0.25 or 0.2 seconds.
- **Breaking: a display-only Toast fades in and out as it slides by default** (it only slid unless `fade = true`). The fade is the shared `ctx.fade` path, so settled text is not rasterised; `fade = false` keeps the slide alone.
- **Breaking: a tap or click on a Sheet's grabber closes the sheet** (it grew the sheet to the next detent). Return and the gamepad A button still grow it and close from the tallest detent; with `interactiveDismissDisabled` a tap grows it as before.
- A disposed controls context can be collected. Its layout kit, help presenter and reduced-motion source lived in module-scope weak tables keyed by the context, and each value held the context, which Luau's weak keys never release, so every context and its tree stayed in memory.
- **Breaking: a Region with two or more forms opens its richest form in a Popover by default.** A tap on a reduced form (a target up to the touch floor around it) moves the region's form 1 node into a Popover and back on close, so state and selection carry over. `expand` is now an optional override for the Popover content, and `reveal = false` keeps the old silent reduction.
- **Breaking: a `mayDrop` Region steps to a badge form before it drops.** The badge is one form past the authored ones, so a `form` cell reads `#forms + 1` while it shows (read it as "reveal"); `reveal = false` keeps the old drop. A zone gathers its dropped regions behind one "…" beside it, and its Popover stays open while another region in the zone steps between visible forms.
- **Breaking: under touch or gamepad input a Table's flexible column yields its `minWidth` down to the theme's touch floor** (`targetSizes.minimum`, 44): the columns fit a phone lane beside the edit controls first, and past that floor the pinned-row cells scroll sideways, so no column is lost.
- **Breaking: a touch hold no longer picks a row up where the collection has an Edit mode** (a Table's own Edit/Done toggle or a bound `editing`); the hold is left to scrolling and touch reorders through the Edit handles. A collection with no `editing`, or `editing = false`, keeps hold-to-reorder.
- **Breaking: a plain Button with an authored width drops to tight side padding when its label does not fit** (`facet-button-tight`), so a narrow key keeps its glyph; a Button that hugs its label never does.
- **Breaking: RadialMenu names an icon item only while a pointer hovers it, a finger holds it or the stick aims at it**, just outside the item and inside the screen, never after a pick or a level change. A nested `expand` level that does not fit around its parent replaces the parent ring before the list fallback. An anchored ring fits the page space that holds its anchor (the nearest ancestor with room for the ring at the touch floor), not the whole overlay layer, shrinking its band to the touch floor, and a word wider than its fitted slot shows the item's icon instead.
- **Breaking: a ScrollView turns a child's Scale height into a `UISizeConstraint` floor of the padded window** (the child's `Size` becomes its offset height, and a child's own `UISizeConstraint` takes the floor in its `MinSize`). The child still fills the page and grows the canvas past it; when the window shrinks the child shrinks back and the scroll position is kept. A child whose `Size` its author changes is left alone.
- RowActions holds only the ScrollingFrames Facet made while a horizontal pan is locked, through the shared ref-counted scroll lock, so it no longer fights an open sheet's lock or a bound `ScrollingEnabled`, and a game's own scrollers are untouched. A Table touch cell tests every word's rendered width before it wraps. A TabView reveals the selected tab again when its width or the strip's overflow settles.
- A TabView top strip that overflows scrolls freely: it reveals the selected tab once per selection or strip width, so a scroll that moves the selected tab out of view is no longer pulled back.
- **Breaking: Facet's own theme `::UIStroke` rules stroke inside the box** (`BorderStrokePosition.Inner`) unless a rule says otherwise, so a border at a clipping edge is not cut. A game's `package.rules` keep the engine's stroke position, and the AvatarGroup separator stays outside the avatar.
- **Breaking: vertical scrollers keep a persistent bar gutter** (`VerticalScrollBarInset = Always` on the theme's `ScrollingFrame` rule and `UI.ScrollView`), so a vertical scroller's content is 4 pixels narrower even when it does not scroll. Horizontal rails, menus, tab rails, the calendar and alert bodies keep the on-demand reserve.
- **Breaking: `UI.environment(frame)` reports the frame's size in layout units** (its `AbsoluteSize` divided by the scale of its `UIScale` ancestors), so a scaled preview keeps its size class. A camera source still reports `ViewportSize` in pixels.
- Visual review fixes. The TabView rail and top-strip plate wear the theme's hairline and corner (it carried real modifiers, an opaque engine stroke, the white or black ring), its strip clips only while it scrolls (skinned tab shadows were cut), and a skinned rail adds the control art's content insets to its width. SplitButton's pointer chevron is its padding and glyph wide (a touch-floor constraint doubled its padding). A Callout, Popover or Tooltip tail keeps a tail width of straight edge from a corner arc. `PageView` with `AutomaticSize = Y` hugs its tallest page, and its summary, dots and buttons are centred; its dots never wear control art. A revealed `Card` grows its one plate around Play and More. On a skinned theme a filled tab shows the selected art, a Stepper's value sits on its plate, a status badge's art takes the status colour, and `Table` rows wear the control art like List rows.
- The Showcase Toasts page shows its messages with `UI.Toast` (it drew and scheduled its own toast). A "Fit content" toast is the `width = "hug"` toast: it widens to its title and detail up to 560 pixels before it wraps. A shown toast now outlives the page, like any `UI.Toast`.
- The Showcase pages scroll through `UI.ScrollView` with `padding = 16`, so every page keeps its 16 pixels inside the scroller (a ring, border or shadow at a page edge is not cut) and none hand-writes the scroller, its list or its padding. The Status page keeps its padding outside the scroller as the banner reservation.
- Showcase: a previewed device fits under the Roblox top bar. The fit read the top-bar inset once at start, when the engine still reports 0, so a phone preview ran 58 pixels past the bottom of the window and hid its bottom bar; it now follows `TopbarInset`.
- **Breaking: RadialMenu `scrim` defaults to `"none"`** (it was `"dark"`), as in 0.11: an open ring does not dim the page; pass `scrim = "dark"` for the old look (`"light"` stays available). RadialMenu matches 0.11 again in its controls too: and the ring's Back and Close are always icons, never the words.
- The dated planning records (`docs/plans`, `docs/superpowers`) and the distribution-readiness ledgers are no longer in the repository; the guide and the API reference are the documentation. A package build takes its `Repository` attribute from the checkout's `origin` remote.
- **Breaking: a ScrollView with `axis = "x"` hugs its content height by default** (it filled its parent's height). A chip row no longer clips when its chips grow at ten feet. A ScrollView whose props hold a child with a Scale height (`height = "fill"`) still fills, so that child keeps a height; a child added later through a keyed list or a fragment is not seen, so give such a ScrollView `height = "fill"` yourself.
- `FacetEntry` and `FacetResponderCancel` sit at priority 30, above `Facet.inputPriority.belowControls`, so a game back action on B at `belowControls` no longer takes B from an engaged responder. A selected activatable Card keeps the live shared focus look (it pulses, hides after mouse input and follows a theme change); the body's `FacetFocusHeight` attribute stretches the look to the card or the artwork. The focus pulse is a `TweenService` tween on a `NumberValue`. A RadialMenu leaves `GuiNavigationEnabled` alone at the last close once the game turned it on while a ring was open. A touch Rating narrows its star spacing to fit a fixed-width holder such as a Table column. A Callout relinks the anchor when its panel content is rebuilt in place. Toast schedule callbacks run after the schedule settles, so a callback that pushes or dismisses cannot overfill the slots. A tail on a short side narrows the tail and keeps the panel's corner radius.
- A Rating spaces its stars when touch is the effective input (`PreferredInput` first, the same rule as `environment().effectiveInput`), not whenever `TouchEnabled` is true, so a touch laptop at a mouse packs them. A Callout clears an anchor's `NextSelection*` only while it still holds the link the Callout set, so an app's own link survives. The focus look follows the selected control's size and corner while it stays selected. The segmented selection fill is clamped to the layout's `AbsoluteContentSize`, not the strip's own size, which the fill fed (a vertical strip ran away to 1,500 pixels on mount with re-entrancy warnings).
- Review fixes: overlapping RadialMenus share one hold on `GuiService.GuiNavigationEnabled` and restore the game's value when the last closes; the keep-visible room moves out of `UI.focusRing` into the selection layer (every app that observes the selection, keyboard or pad only) and is clamped so a tall selection stays in view; `UI.focusRing` stacks per PlayerGui and gives the previous selection object back, and `app({ focusRing = false })` opts out; the focus look reads `LastInputTypeChanged`; a selected Card draws the theme's focus look; one held-repeat policy, and a Stepper takes `repeatDelay`/`repeatInterval` for its arrows and buttons; a toast's Down link ends when the selection moves on and `queueCap` is at least 1; a child added during a fade joins the group; `Facet.inputPriority` publishes `{ belowControls, aboveFacet }`; a short-side tail no longer spikes the outline; the segmented selection fill sits in the strip's padded content box.
- A toast with an action docks 16 pixels above the app's reserved bottom chrome (a TabView bottom bar, an affixed Notice), its action is a full Button sized to its label (it was a padding-less link the engine cut off), and a row torn down with its owner still hands the selection back. A corner RadialMenu hands the selection back to its launcher when it closes.
- A labelled horizontal segmented Picker stays inside its row: the row limit rides on the strip's one `TargetFloor` constraint (the engine honours one `UISizeConstraint` per object, so the second one was ignored and a long-label strip overflowed), and a fill strip shares the width instead of wrapping onto a line its fixed height cannot hold, as `fill` did before 0.12. Long radio-group and card labels wrap inside their rows.
- A Rating spaces its stars for touch only (see above for the effective-input rule); a gamepad adjusts the whole run with Left and Right, so the stars pack as for a pointer (a Table's fixed Rating column overflowed at ten feet).
- A shoulder move in a Table or List edit mode keeps the pad selection on the moved row. A pad-selected Sheet grabber answers A (the grip's `UIDragDetector` stands down while a gamepad has the grabber selected). An open RadialMenu turns `GuiService.GuiNavigationEnabled` off, so the left stick reaches `RadialAim` (engine navigation takes `Thumbstick1` while anything is selected), and restores it on close.
- **Breaking: `UI.Snackbar` is gone; `UI.Toast` is the one transient message.** A Toast without `action` is the display-only toast (three stacked per edge, never selectable). A Toast with `action` is the old snackbar: one at a time at the bottom, one Down from the control that had the selection, Cancel on ButtonB or Escape, an optional `closeButton` (on by default), readable time that pauses on hover, selection or a modal, and the 2.5 second read floor. `isPresented` with `onPresentedChange` is optional in both modes; a bound toast proposes false and leaves when the fact is false. Both modes run on the one `toast_schedule` (the snackbar's own queue and floor are deleted). Migrate `UI.Snackbar { ... }` to `UI.Toast { ... }`; a snackbar without an action becomes a display-only toast (drop `closeButton`); the dismiss reason `superseded` is now `preempt`; `SnackbarSpec` is now `ToastSpec`; the anchor attributes are `ToastVisible` and `ToastQueued`; the cancel input action is `ToastCancel`. The capacity error at the tenth snackbar is gone: past eight waiting, the least urgent waiting toast retires with `capacity` (and a bound one proposes false). A display-only toast takes `icon` too.
- A segmented Picker's selection fill stays inside the strip. Before, a fill on a segment the strip could not fit reached past the strip and, because the strip sizes to its content, widened it, which re-laid the segments in a loop until the engine stopped it ("Maximum event re-entrancy depth exceeded" on a long option in the lab).
- A Popover, Callout or help plate draws its border as one continuous `Path2D` outline around the panel and the tail, so the edge stroke stops exactly at the tail and joins its sides in every theme. Before, the panel stroke ran under a covering seam and showed stubs beside the tail base.
- A Dialog with `actions` has no close button by default, as an Alert never had one before 0.12: ButtonB and Escape run the `cancel` action. `closeButton = true` still adds it, and a Dialog without actions keeps it.
- A segmented Picker places its sliding selection fill on the segment where the layout put it (its `AbsolutePosition` in layout units). Before, the fill summed the widths as one line, so a strip that wrapped (a long option) painted the fill past its end, and that stray fill fed the strip's automatic width back into the layout.
- Focus looks are theme data again, drawn by the engine: `UI.focusRing` builds one `SelectionImageObject` from the package's `chrome.focus` recipe (`kind` `ring`, `glow`, `nineSlice` or `brackets`; `color`, `thickness`, `size`, `outset`, `sliceScale`, `corner`, `pulse`). The look takes the selected control's shape (its own `UICorner`, a pill for a Chip, a circle for a circle Button, else `radii.control`). At ten feet it is larger (a ring twice as thick, brackets and art 1.5 times, a glow 1.6 times the blur) and stands 3 pixels off the control. Facet Neutral keeps the thin ring, Pixel Quest draws square brackets (a gradient-masked stroke), Fantasy Ornate its gold frame with a slow pulse (reduced motion stops it), Fantasy Parchment a gold ring. The look is one `ImageLabel` with UI components, because the engine does not draw a selection object's child GuiObjects. Before, 0.12 drew one accent ring for every theme.
- A Slider's thumb is its selection stop: a 44 by 44 `ThumbStop` around the painted `Thumb`, so the focus look lands on the thumb and follows it. `thumb = "auto"`, `thumb = "none"` and a `thumbContent` knob keep the track as the stop.
- Named haptic feedback is back: `haptic` on a Button takes `"selection"`, `"impact"`, `"success"`, `"warning"` or `"error"` as well as `true` (the shorthand for `pressHaptic`), `pressHaptic` takes a kind, and `UI.feedback(kind)` plays one at once. Each kind is one pooled engine `HapticEffect` (presets for selection, impact and success; custom pulses for warning and error).
- A held Stepper button and a held NumberInput step button repeat after 0.4 seconds, then every 0.1 seconds, as before 0.12. A repeating Button follows the frame clock only while it is held.
- `UI.adjustable(node, { onAdjust, axis?, repeats?, canAdjust? })` gives a game control the value controls' keyboard and gamepad adjustment (the old contribution `adjustAxis` and `adjustRepeat` opt-in).
- Avatar and AvatarGroup per-input rules from before 0.12: an Avatar without `onActivate` takes no input, an interactive Avatar lights a `HoverRing` only under the pointer, and the AvatarGroup overflow chip sits clear of the stacked faces (`OverflowGap`) with the touch and gamepad target floor. The group binds no gamepad button, so ButtonB reaches the screen.
- The documentation says what did not change: a mouse-only compact control keeps its size without the 44 pixel floor, and `keyboardNavigation` stays on by default.

- A `sidebarAdaptable` TabView's rail and top strip sit on a raised plate again (`facet-tab-plate`: the strong surface with a hairline), and the current tab of the top strip is filled with the accent like the rail's, as before 0.12. Before, the rail had no plate and the top strip's current tab was the dim selected-control paint.
- RadialMenu: the centre control paints on the ten-foot ladder (48 pixels at a distance, 32 near). The list fallback's preview names where it is when nothing is highlighted, as in 0.11: the breadcrumb of the open branches, or the menu's `label` ("Quick actions") at the top.
- Showcase settings: at ten feet Preview as, Orientation and Input use the automatic ladder (inline rows or a segmented strip) and stay menus at arm's length; the settings card has a hairline border, as before 0.12.

- A TabView sidebar is sized to its widest tab by default (the label, the tab padding and the icon), with centred labels, and a top bar centres its tabs, as before 0.12. Before, the rail was 20 percent of the TabView (200 to 280 pixels) with leading labels, and an inner top bar hugged the leading edge. An authored `railWidth` keeps leading labels.
- Showcase shell, as before 0.12: the LB and RB hints sit beside the demo button while a gamepad is the input (LB opens Demos, RB opens Settings, the backquote key toggles the panel); "Use top tabs" / "Use sidebar" sits beside the demo button while the categories can take either home (not at ten feet, not in a bottom bar), and the categories carry no accessories; the panel is a card under the bar, not a Popover (a tap outside, ButtonB or Escape closes it, the selection returns to the demo button); Settings is Preview as (Automatic, Desktop, Phone, Tablet, TV / 10-foot), Orientation (Phone and Tablet only), Input, "Reset everything to Automatic" with its note, Motion with its note, the build stamp and the Theme chips with their palettes. The compact top-bar strip is gone: the bar stays under the Roblox top bar in landscape.

- `UI.responder(root, options?)` restores the pre-0.12 first responder on the engine selection. A passive surface (the default) binds nothing at rest: Tab is not bound while nothing is selected, a D-pad press does not enter it and Space reaches the game. It engages when the selection enters it, on a tap on it (the tapped control takes the selection) and on `engage()`, and resigns on a tap outside, on an untaken ButtonB or Escape, on `resign()` or when the selection leaves for another surface. While engaged, `gameplayGuard` (default on) sinks Space at priority 3000; `gameplayGuard = false` also drops Space from the Buttons inside it. `traversalWrap = false` stops Tab and Shift+Tab at the ends of the surface. `passive = false` keeps a surface always engaged. The Virtual Monitors desktop declares itself engaged-open.
- `keyboardNavigation = false` now also drops Space from a selected Button (Return still activates), as before 0.12; `true`, the default, binds Tab and Space. The default is one constant in `selection.luau`.
- `UI.Grid` clamps a move into a short last line: the cells of the line before it that have no cell below get `NextSelectionDown` (`NextSelectionRight` for `flow = "column"`) to the last cell, the pre-0.12 ragged-row rule. A neighbour that you set wins.

- NavigationStack Back returns the selection to the control that pushed, found by its path in the page when the page rebuilt that control. Before, it fell to the page's first control (a Browse → Back in a test bed landed on its "Show examples" button).
- A TabView inside the page of a bar-less TabView (`placement = "none"`) is not nested: it takes the full home policy (a phone gets the bottom bar). The Showcase categories follow the policy on Automatic again, so a phone shows them in a bottom bar as before 0.12.
- A TabView whose home changes (a sidebar preference, an expanded sidebar) moves the selection from its accessories to the current tab, instead of letting it fall to a control in the page (found live: "Use sidebar" left the selection on the page's first button).
- Showcase shell is back to the pre-0.12 design: no "Facet gallery" title; one button named for the current demo (it reads "Close" while open) opens an anchored panel with a Section switch, Demos (one button per demo, the current one emphasised) and Settings (theme, appearance, motion, viewing distance, categories, device preview with orientation, input and text previews). It replaces the demo menu Picker, the Settings gear and the Gallery settings sheet. The categories keep the sidebar at a pointer, top tabs with "Use sidebar" elsewhere, and at ten feet "Use sidebar" expands the sidebar (ButtonB collapses it).
- Gamepad and ten-foot fixes from the live console check: a left-stick push enters the selection when nothing is selected (a non-sinking `FacetEntry` context, like the D-pad), `adaptive.isTenFoot` needs no mouse and no touch even when `IsTenFootInterface()` is true (Studio reports true on a desktop), a nested sidebarAdaptable TabView honours `sidebarExpanded` and moves the selection from its accessories to the current tab, and the TabView strip and NavigationStack bar are `targetSizes.minimum` high (66 at ten feet) instead of a fixed 44. Showcase: the TV preview insets the gallery by the overscan margins, and the toolbar height is read in layout units under the preview scale.
- Showcase: the Viewing-distance preview drives the framework (`environment.viewingDistance`), so Distant TV shows the real ten-foot sizes and overscan instead of an app-side 150% zoom, and the TV device preview is ten-foot. Demos lay out against the viewport divided by `metricScale`.
- `UI.Screen` takes `chrome = "device" | "band" | "edge"`, the platform-chrome policies from before 0.12: device clears the top bar and the overscan (the default), band lets the content ride the free top-bar strip, edge adds neither.
- `Facet.gamepadContention` is back: `legacyStackActive`, `cameraKeysContended`, `traversalKeyContended`, `iasPlayerScriptsActive`, `disableLegacyControls` (UI-only places), `freedJumpAction` and `describeContention` report and resolve the legacy player scripts holding ButtonA, the arrow keys and Tab. The Virtual Monitors place logs the explanation when the legacy stack is active.
- `UI.TabView` `style = "sidebarAdaptable"` takes `sidebarExpanded`, a writable cell: at ten feet `true` shows the sidebar instead of the top bar, and ButtonB while the selection is in that sidebar collapses it (the old `expandSidebar()` / `collapseSidebar()`).
- The declarative focus model is back on the engine selection. Tab traversal orders by the native `SelectionOrder` tier, then layout order (the old `traversalPriority`). The `FacetTraversal` context binds Tab only while `KeyboardEnabled` is true, and the factory option `keyboardNavigation = false` binds nothing (a HUD over gameplay). `UI.focusSection(group, options?)` takes `entry` (`"restore"`, `"first"` or `"nearest"`), `preferred`, `focusOnAppear` (true or a descendant name) and `returnFocus`; an unknown option is an error. Grid lanes and per-direction exits are the native `SelectionGroup`, `SelectionBehavior*` and `NextSelection*` properties, now documented under Selection.
- Ten-foot viewing is restored from before 0.12. At ten feet (`adaptive.isTenFoot`) the controls and the StyleSheet use `themes.forDistance(package, "ten-foot")`: every metric length, control height, icon size, radius, stroke and type role is 1.5 times, so a 44 pixel target is 66 and body text is 24 while every text-to-control proportion stays the same. `createStyleSheet` takes `tenFoot` (it follows the device when omitted; `app.mount` passes the environment's fact). `UI.Screen` adds the console overscan margins at ten feet (60/1080 of the height and 90/1920 of the width, as native UIPadding scale). The `environment` option takes `viewingDistance` (`"automatic"`, `"near"` or `"ten-foot"`, which outranks every inference) and `overscanInsets` (pixels or `"none"`). `UI.environment()` adds `viewingDistanceSource`, `metricScale` and `overscanInsets`; `Facet.adaptive` adds `overscanInsets(width, height)` and `TEN_FOOT_SCALE`. The Virtual Monitors world screens stay near. Before, 0.12 painted a television at arm's-length sizes with UI flush to the glass.
- `UI.draggable(source, spec)` and `UI.dropTarget(target, spec)` are back as the public drag and drop API, on 0.12 instances: a pointer picks the source up after 6 pixels of travel (a shorter press stays a click), a finger on the engine's long press (a finger that moves first scrolls, and the scroller under a held finger stays put), and an inert `DragGhost` copy follows it; the press that became a drag never activates a Facet Button; Return or A arms the selected source and drops on the target that holds the selection, and Escape or B puts it back; `armOnTap` makes a touch tap the pickup. `accepts` returns the game's `(legal, reason)`, and a refusal calls `onReject`. A held source has the `facet-drag-held` tag, and every theme hides its text and icons so its plate stays as the empty slot. The virtual monitors Discover cards use it to drop a game on the Saved shelf, replacing 170 lines of their own detector and long-press code. The pure session primitives (`newDragSession`, `newAutoscroll`, `touchGestures`) are not restored.
- Tab walks a collection's rows in row order after they scroll: each row's `LayoutOrder` is its index and Tab sorts the `Items` rows by it. Before, Tab followed the recycled row containers' creation order, so in a scrolled Table it skipped from row 4's editor to row 8's.
- Reorder autoscroll walks the scroller chain again: when the list is at its end, the nearest enclosing ScrollingFrame whose edge band holds the pointer scrolls, so a list or a non-scrolling Table inside a page hands the drag to the page. Before, only the list itself scrolled.
- A pointer reorder under a scaled ancestor (a UIScale, the TV device preview) reads the pointer in the body's layout units for the drop slot, the drag image and the edge autoscroll. Before, it mixed screen pixels with layout units, so at a scale of 2 the drop slot and the image landed about twice as far down as the pointer.
- While `editing`, a selectable Table or VirtualList that is not `deletable` marks each row's selection at the leading edge again: a ring (`facet-radio-mark`, the Picker radio mark) with a filled dot on selected rows, which takes no focus. A Table with a supplied `editing` shows it even when it is neither reorderable nor deletable. Before, edit mode showed no selection mark (lost in 0.12).
- `UI.Table` rows follow a ladder by viewing distance again: a touch row wraps its cells and starts at two lines of body text (56 in Neutral), and a ten-foot row (`ctx.tenFoot()`) holds one line at the large control height (56). A near row is unchanged (40 or the regular control height; 44 with a gamepad). Every row still rises to fit its measured text. Before, touch and ten-foot rows were the one-line 44 of a gamepad at a desk.
- Journey example (NavigationStack gallery scenario): the details page's "Days 3 away" and "Travel light" rows are `HStack`s whose words hug and whose `Spacer` takes the rest, as in 0.11. Before, each word was a full-width Text in a horizontal list, so "3" and "away" painted past the Summary column over "Your notes".
- A Toast stack docks clear of the app's reserved chrome on its edge, in its own ScreenGui or an enabled sibling one (`reservations.reserved`), and a TabView bottom bar now reserves its band (`FacetInsetBottom`). Before, a bottom toast painted over a bottom bar that lived in another ScreenGui, and no bottom bar reserved anything.
- A Popover, Callout or help panel beside its source (a side edge) that is shorter than 39 pixels keeps its tail, centred on its side. Before, the tail was dropped whenever the panel was too short for the tail plus its 8 pixel end insets.
- `UI.Text { reveal = "auto" }` (restored from 0.11): a truncated one-line label rests in its ellipsis, then scrolls its whole value left to the tail and back, one strip at a time, never under reduced motion or while its disclosure panel shows.
- `UI.Toggle { disclose = true }` shows the whole value of a truncated label in the `Disclosure` panel (restored from 0.11), on a settings row too. A Button with a leading icon or a subtitle gates `disclose` on its painted `Title` label; before, it read the empty button text, which always fits, so the panel never showed.
- `UI.Toast` and `app.presentToast` take `fade = true` (restored from 0.11): the row fades in and out as it slides. By default a toast now only slides, as in 0.11, so its text stays in native glyph rendering; before, every toast faded through a CanvasGroup.
- RadialMenu centre and corner controls match 0.11 again: the centre control paints 32 pixels with no plate inside a transparent `CenterHit` touch target (`targetSizes.minimum`); Home is the up chevron; a `centerLabel` is the accessible name only, never visible text; a corner control grows out of the launcher on open (and back into it on close) while its glyph crossfades between the launcher icon and Close/Back; the list fallback names the highlighted item at the bottom left. When a submenu replaces a level while the player selects by gamepad, the selection lands on the new level's first item (before, the engine reselected the launcher or the centre).
- RadialMenu Back/Close placement follows the 0.11 rules again: an even full ring with an `empty`, `content`, `root` or `close` centre turns so its Back/Close wedge sits at the lower left; a full compass with an empty centre puts Back/Close in the centre; a corner preset's corner control is always Close at the root and Back in a submenu, whatever `center` is; the list fallback has one round Back/Close at the top right instead of a full-width row or a list row.
- `UI.Toast` and `app.presentToast` (restored from 0.11): input-transparent, non-focus-stealing messages, three visible and eight waiting per edge, priority order, a 2.5 second read floor that priority never cuts, same-key supersede, and survivors that slide into a vacated slot.
- `app.presentAnchored(component, options) -> close, screen` shows a panel against a node or a rect (restored from 0.11), and `UI.Popover` takes `modal = false` (chrome: no catcher, no Cancel, no selection claim; input passes through) and `cancelPolicy = "none"` (Cancel and an outside tap propose nothing).
- Every input can open every Button `help`: a touch long-press shows the panel at once (its release does not activate the button; the next touch closes it), beside the pointer dwell and the keyboard or gamepad selection. Before, help never showed on touch.
- `UI.Text { disclose = true }` and a text `UI.Button { disclose = true }` show the whole value of a truncated label in a `Disclosure` panel on a pointer dwell, a keyboard or gamepad selection, or a touch long-press (restored from 0.11). A truncated Button label outranks its `help`.
- `UI.focusSection(group, { focusOnAppear, returnFocus })`: an appearing branch takes the selection (its first stop, or a named descendant) while the player navigates by selection, and gives it back to what held it before when the branch leaves (restored from 0.11).
- `UI.Menu` takes `controls` and sets `controls.diagnostics()`: advice for a submenu two levels deep, a level of more than five items and a destructive item that is not last (restored from 0.11 `api.diagnostics()`).
- A theme whose `radii.pill` is 0 draws no round corners: every corner Facet used to force round (a circle Button, the Toggle switch track and knob and the checkbox box, slider thumbs and contained rails, Avatar and circle Image shapes, page dots, the sheet grabber, step dots, status and presence dots) is square, and the segmented track, tooltip and shortcut hint follow `radii.control`. A corner the author asks for (`corners = "pill"`) still wins. Pixel Quest's radii are now all 0, so its flat plates, fields, chips, pills, popups, dots and focus ring are square.
- A ProgressView bar's `barCap` and `barCenter` art fits its track: it scales down to the track's cross thickness and to a quarter of its length (never above its declared `size`; the length is read in layout units, so a scaled ancestor does not change it), the caps anchor inward at the track's ends and paint over the fill, and the fill runs between the caps. Below half its declared size the art is dropped. Before, each cap was centred on a track end at its declared size, so Pixel Quest's 40 pixel hearts hung 20 pixels past a HUD bar over the task names, the reward pills and the health plate's frame, and the fill ran under them.
- In a Table edit mode the row band is the edit wrap (it paints `tableRow`), the inner row is transparent, and the minus and the revealed Delete paint the `danger` role. Before, the inner row showed the engine's default grey and both controls painted `accent` (blue). Pixel Quest has a darker `tableRowAlternate` so alternate rows keep cream text at 4.5:1.
- A skin decoration that resizes inside another decoration's resize defers its write (`task.defer`), so decoration size handlers never nest. Before, a layout that flipped during a device preview change (a test bed's strip, phone to automatic) nested the handlers until Roblox raised "Maximum event re-entrancy depth exceeded" (390 messages per switch).
- Word game example: only the cursor cell (the next letter slot) has a subtle accent outline, and a typed letter has the neutral filled-cell border. Before, every cell of the current row was outlined.
- Editable collections: Table, VirtualList and VirtualGrid take `reorderable` + `onReorder` and a new `deletable` + `onDelete(keys)` (with `rowDeletable(item)`). A pointer drags a row, or the selected rows, to reorder with no handle, and Delete or Backspace removes the selected rows. On touch and gamepad a Table shows an Edit/Done toolbar (unless you supply `editing`), and edit mode shows a round red minus at the leading edge (it reveals a trailing Delete that confirms) and the move handle at the trailing edge, inside the row band, with the row content sliding to make room; the X button deletes and L1/R1 move the selected rows. Row actions no longer enter edit mode. **Breaking:** `UI.Table` `editable` is removed (the toolbar follows `reorderable`/`deletable`), and `selectionMode = "multi"` is now `"multiple"`.
- `UI.Table` rows and header are rounded bands (`radii.control`) separated by a 1 pixel inner `surface` stroke, with no row divider; the header band spans the whole row, headings have no plate on it and hairline dividers separate them. Before, the header band ran over the handle column, each heading painted its own rounded plate (corner artifacts) and a divider line under every row outlined a selected row.
- A skinned `facet-control` plate (any Frame with the tag that `themes.skin` paints, such as the HUD score chips, timer pod and health readout) pads its content by the control art carve (`contentInsets`), like a Button, panel or badge. Before, only its own padding applied, so in Fantasy Parchment the "12", "9", "2:14" and "84" readouts touched or crossed their frames.
- A TabView current tab in a sidebar or bottom bar (the filled tab) is a selected Button, so a skinned theme paints it with its selected art at its siblings' size and `onSelected` ink, and it reports `selected`. Before, it was a flat `accent` rounded rect (Fantasy Ornate Crypt teal, Fantasy Parchment brown, Pixel Quest green), wider than its framed siblings.
- Every theme package compiles the same core StyleSheet rules; a rule that only some packages need (selected art, a pressed emphasis swap, the segment fallback, `artTint`) is emitted with no properties where it does not apply. A theme swap re-sets rules and never creates or destroys them: the headless `theme-swap-assets` scene went from 0.93 to about 0.44 ms (p95), under its 0.559 ms budget.
- `UI.focusSection(group)`: when the selection enters `group` from outside (Left from a detail pane into a sidebar), it returns to the item last selected there, while that item is still selectable.
- A Button with an authored width and a label keeps at least one `control` em of label room inside its padding and the theme carve (a `UISizeConstraint` `MinSize`), so it grows a little rather than truncating the label to nothing. Before, a 52 pixel Button in Fantasy Parchment had 4 pixels for its label and showed an empty plate (Showcase "Edit item" ladder).
- A busy Button reserves the room for its dots on a real `UIPadding` (a direct `PaddingRight` write), so a hugging parent grows with it. Before, only the StyleSheet `::UIPadding` changed, the engine did not re-fit the hugging parent, and the dots painted past a hugging cell (a busy `link` Button in a Stack).
- `UI.RadialMenu` takes `scrim = "dark" | "light" | "none"`: the default dark dim, the theme scrim that a Dialog uses, or no dim (a tap outside still closes). The Showcase RadialMenu demo cycles it under More options ("Page dim").
- The `UI.Table` row More button is the `more` (…) icon named "More actions" (its `label` attribute), and still opens the Popover of truncated values. Before, it was named "More".
- A palette extra `artTint` multiplies the `control`, `field` and `panel` chrome art. Fantasy Parchment Candlelight darkens its parchment to 0.3 and Pixel Quest its wood to 0.78 (the flat `control` plate matches), so text on the art reads at 4.5:1: before, Candlelight field text was 1.1:1 on light parchment and Pixel Quest cream on wood 3.3:1. A skinned inactive tab uses `contentSecondary` only where it reads at 4.5:1 on `control`, otherwise `content`. Fantasy Parchment Daylight and Glossy Touch have a darker `contentSecondary` so a placeholder or quiet tab reads at 4.5:1 on their art.
- A segmented Picker bounds its segments by its row's width in layout units under a scaled ancestor (the TV device preview). Before, it used the scaled pixel width, so a long segment could be wider than its line and the wrapping row flipped between two layouts on every change, raising "Maximum event re-entrancy depth exceeded" from skinned segments.
- A `measure` collection (List, Grid, VirtualList, Table) reads a row's size in layout units under a scaled ancestor (a UIScale, the TV device preview). Before, it stored the scaled pixels as the row height, so a row that fills its slot grew by the scale on every pass, to billions of pixels, and raised "Maximum event re-entrancy depth exceeded".
- An `emphasis` plate (a primary Button, a `contrast` menu Picker trigger, a chosen Picker card) in a skinned package whose accent is too light to tint under its label shows the theme's selected art with an `onSelected` label. Before, Pixel Quest, Fantasy Ornate and Fantasy Parchment Candlelight hid the art and painted a flat accent rounded rect; Parchment Daylight now matches Candlelight.
- A DateTimePicker day number on the range band has the `facet-calendar-banded` tag and paints in `onSelected`, the ink of `controlSelected`. Before, it stayed `content`, so a theme whose selected fill is dark (Glossy Touch, Fantasy Parchment) drew dark numbers on a dark band.
- Every selected plate in a skinned theme uses the theme's selected art: a segment, a Picker row, radio row or card, a Chip, a Toggle button and a menu row, at the size of its unselected siblings. The chosen Picker card is now `selected` too; before, it was a flat accent rect wider than its siblings in Pixel Quest. Fantasy Ornate, Fantasy Parchment, Glossy Touch and Compact Pointer now have a selected piece made from their own art (Parchment's selected label is vellum on inked parchment; Compact Pointer's `controlSelected` is the tinted pressed button).
- A floating Menu or Picker menu on skinned panel art is its rows plus the art carve on each side, up to `maxHeight` or the screen. Before, the panel was only as tall and wide as its rows, so the carve padding squeezed them: in Pixel Quest a three-row Picker scrolled with its first and last rows cut.
- On skinned art, a Button, Chip, Menu or Picker trigger, segment, list row and framed TextInput add the art's carve (`contentInsets`) to their own padding on each side. Before, the padding was the larger of the two, so at a small step the label sat on the frame (Pixel Quest compact Picker "(default)" started on the left bevel), and a framed TextInput kept 10 and 4 pixels even when the carve was larger.
- The RadialMenu centre is a small round plate-less close with the highlighted item's name under it inside the hole, and the ring's scrim is black, at least 80 percent, and reaches the screen edges. Before, the close was a skinned plate filling the hole, the name showed below the ring, and a 70 percent theme-coloured scrim left page text legible.
- An image Button with an authored fixed height keeps its `imageAspectRatio` and centers the image in the space the text leaves. Before, the image filled that space and was cropped, so the Showcase driver cards cut off the head. A row Slider's root Frame is transparent; before, it painted the engine's default grey, so the Showcase "Music volume" row looked disabled. The Showcase driver cards show the chosen driver as selected.
- A Button with an authored width stays inside it. An authored `TextTruncate` keeps a text label on one line and truncates it (before, it wrapped and grew, so the Showcase "Edit item" button showed "Ed ite" over its plate), and an icon Button keeps its width and truncates its label (before, it grew and pushed the row past its edge).
- A fade (TabView, NavigationStack, Dialog, Alert, Popover, Callout, help, Menu, Snackbar, DisclosureGroup, CollapsibleView, RadialMenu slots, Card plate) puts the content in a CanvasGroup named `Fade` only while it runs, and removes it when the fade ends. Before, every faded surface stayed a CanvasGroup, so settled tab pages (three nested groups in the Showcase) and panels were rasterised and blurry.
- A RadialMenu sizes its default ring from theme metrics and its labels' length, with no text measurement, and keeps each wedge one touch target wide. Before, the ring read measured text bounds, and opening it could raise "watch cascade did not settle".
- `themes.skin` draws no art images into a TextBox target (the recipe shadow still applies), so an unframed TextInput in a skinned theme keeps the flat `facet-field` plate. Before, the `field` art was a child of the TextBox and Roblox drew it over the typed text and placeholder (Fantasy Parchment Playlist "Filter tracks").
- An off switch's knob uses `content` when `onSelection` has less than 3:1 contrast on the `control` track (Fantasy Parchment, Neutral Light, Classic Desktop, Glossy Mobile, Sci-Fi HUD). Before, a cream or white knob on a pale track made the off switch invisible.
- A destructive or `emphasis` Button on skinned `control` art paints its role again: the art is tinted with `danger` or `accent` when the label is lighter than that fill, and otherwise the flat fill replaces the art. Skin images have the `facet-skin-art` tag. Before, in Fantasy Parchment "Delete profile" showed plain parchment art under cream text.
- A Button whose `BackgroundTransparency` is 1 (a transparent hit target laid over other content) takes no `control` chrome art. Before, in Fantasy Parchment the Match 3 tiles' hit buttons painted the plate art over each tile's glyph.
- A row action with an `icon` sizes its tray from the painted label caption plus the icon. Before, it measured the empty text of the icon Button, so the tray stayed 88 pixels and the Playlist "Remove" label was cut off.
- `UI.Table` rows paint `control` by default (alternate rows `controlHover`) with a strong hairline `Divider` under each row, and each heading is a standard Button, so Fantasy Parchment frames it with its `control` art (`parchment_button`) as before 0.12. Before, rows painted `surface` on a `surface` page, so rows, separators and the Parchment header frames were gone.
- A tap on a swipeable row of a selectable collection selects the row (a mouse click replaces the selection), and a selected Table row carries `facet-selected` for a `controlSelected` band. Before, the grip sent the tap to the first Button in the row, so a Playlist click started a keyboard move (✓ handle, drag label, a Drop button over the header) and nothing showed as selected.
- `UI.Table` keeps every column in a narrow table: only a column with a numeric `priority` collapses, and the rest keep `minWidth` and truncate. The header band (`HeaderBand`, tag `facet-tablehead`) spans the whole table, and the row More button is icon-only. Before, the Playlist lost its Rating column in portrait, each row got a clipped "M…" button, and the band stopped short of the gutters.
- A RadialMenu measures each item's label once, in a hidden label outside the wedge it sizes, and only records a real measurement. Before, the measure sat inside the wedge button and every live copy of a wedge wrote its own reading, which could raise "watch cascade did not settle" when the menu opened.
- An open RadialMenu dims the page to at least 70 percent (the theme's `scrimOpacity` when higher). Before, it used the Dialog scrim (30 to 62 percent), and page text read clearly between the wedges.
- The RadialMenu centre control is a round icon button that fills the hole and covers the launcher under it. Before, a 72 by 40 "Close" plate overlapped the launcher's own label and poked past the hole.
- A RadialMenu ring without `ringWidth` is as thick as its measured labels and icons plus theme spacing, at least one touch target. Before, it filled the room up to a 240 pixel radius, far thicker than its labels.
- A RadialMenu wedge item is its icon and label only, inside its wedge. Before, each item was a full Button plate on top of the wedge; in a skinned theme (Pixel Quest) the plates overflowed the wedges.
- Showcase: Gallery settings has a Device preview (Phone, Tablet, TV) and an Orientation choice again. It frames the gallery at 389x762, 768x1024 or 1920x1080 (scaled down to fit) and feeds `viewportSize`, `displaySize` and the input to the `environment` option: Phone and Tablet are Small and Touch, TV is Large and Gamepad. An Input preview choice still wins.
- A Sheet grabber sits in its own gutter just inside the panel art's inner edge. Before, the panel padding also moved the grabber, so a Fantasy side sheet drew its bar about 140 pixels in from the frame, inside the content.
- A labelled TabView tab with an icon badge widens the gap between its icon and its label to hold the badge. Before, the badge covered the start of the label by about 4 pixels.
- The StepIndicator underline is placed as a fraction of the row width. Before, it was placed in pixels from absolute sizes, so under an ancestor `UIScale` (a TV) it was scaled twice and ran past its step.
- A StepIndicator with `sizing = "hug"` changes to the summary and the Steps menu when its laid-out row is wider than its root. Before, it estimated the row from the label text, so on a phone the row ran off the screen.
- Every StepIndicator step has the Button inset of its `controlSize`, whether or not it is a Button. Before, a step that was not a Button had no inset, so its cue sat on the cell edge.
- A StepIndicator with `sizing = "fill"` gives every step an equal width. Before, each step got its own width plus an equal share of the spare room, so the cells differed.
- An inactive segmented Picker segment uses `contentSecondary` ink only when it reaches 4.5:1 on the `control` track (or beats `content`); otherwise it uses `content`. Before, Pixel Quest showed tan on wood (1.9:1, now cream at 3.3:1), and Classic Desktop Night and Fantasy Parchment Daylight were below 4.5:1.
- `UI.ColorPicker` sizes its anchored panel around the theme's panel `contentInsets` (the padding the shared panel skin applies). Before, it assumed 12 pixel padding, so in Pixel Quest the panel was 24 pixels short and its content ran onto the frame art.
- `UI.ColorPicker` Sliders: the Hue, Saturation and Brightness labels share the widest label's width (from `TextBounds`), so the tracks line up. Before, each track started after its own label.
- `UI.ColorPicker`: in a scrolling panel body, an inactive technique reserves at most the height of the body. Before, the Swatches tab kept the Bricks tab's 800 pixel height and scrolled into empty space.
- `UI.ColorPicker` sizes its technique to the `Body` scroll window (`VerticalScrollBarInset = ScrollBar`, width from `AbsoluteWindowSize`). Before, the technique was 380 pixels wide in a 376 pixel window, so the last grid column and the slider values ("229" showed "22") were cut off under the scrollbar.
- The DateTimePicker `CalendarSurface` adds the theme's panel carve to the calendar's size, and a surface that does not fit below the field opens above it. Before, in Pixel Quest the 24 pixel carve pushed the calendar inside a surface of the calendar's own size, so the Saturday column and the last week were cut and the frame art covered the header arrows.
- The DateTimePicker field's `Entry`, `Show` and `Open` take the plate's height, and `Show` reads in the `body` text role like `Entry`. Before, they were fixed at 44 pixels, so at a small `controlSize` (and more on a TV) the selected `Show` painted past the field and pushed `Open` out of it, and a custom `format` field showed its words larger than a typed field.
- A DateTimePicker range band runs unbroken across the days of the range in every theme. Before, the theme's button padding (12 pixels a side) also inset each calendar day's layers, so the band broke into slabs with a 24 pixel gap between days.
- `UI.focusRing(playerGui)` installs the theme focus ring on any screen (the gallery now uses it); `app.mount` calls it. Before, only `Facet.app` screens had the ring, so the Showcase still showed the engine glow after a mouse click.
- TabView `placement = "none"` hides the bar and gives the page the whole view, for a full-screen page such as a HUD on a short landscape phone.
- Restored screen-anchored composition as `UI.Composition` and `UI.Region`. Regions anchor to the nine screen edges and corners in three reserved lanes, and to the free top bar strip through a native `TopbarSafeInsets` ScreenGui. When a lane does not fit, the least important region steps down to its next measured form, then hides if it may. A form change pops in unless motion is reduced. api.md "Migrating from 0.11" maps the 0.11 declarations.
- A Card with `reveal = "automatic"` shows its actions on a panel plate directly below the body again: the primary action fills the row and More is a trailing `more` icon button (the Menu root, now named `More`, is that button). Before, the row floated with no plate, a gap above it, a hugging primary and a worded More trigger.
- A theme plaque layer with `text = true` is title art. A Sheet or Dialog title shows in it, the plaque 9-slice grows around the title, and the header title hides. Without a title the plaque is not drawn. Before, Fantasy Ornate drew an empty plaque on every panel. The Fantasy Ornate plaque is now 9-sliced, with text insets inside its gold rim.
- A skinned Sheet, Dialog, Popover, Menu or picker panel pads its content by the theme `panel` chrome `contentInsets`. Before, the panel's own padding beat the theme rule, so in Fantasy Ornate the Sheet title sat on the inner border and the Close button was clipped at the right edge.
- A Sheet dragged below its lowest detent moves down as one piece, and a drag dismissal slides out from where it was released. Before, the panel got shorter from the top, so the pinned actions stayed put while the body collapsed, and a dismissal jumped back to full height first.
- A Sheet grabber sits on the edge that the sheet came from: a bar at the top of a bottom sheet, a vertical bar on the left edge of a sheet from the right, and on the right edge of one from the left. The content reserves that side. Dragging a side grabber toward its edge moves the whole sheet and closes it past a third of the width.
- A Sheet with a grabber shows no Done button: the grabber closes and resizes the sheet, and it is always selectable. With the grabber hidden, the header shows an icon-only Close button (accessible name `Close`, 44 pixels). `closeButton = true` or a label still shows a close button.
- A presented modal (Dialog, Menu, RadialMenu, Sheet and the others) selects its first control once the surface is shown, and a RadialMenu selects its first wedge, not its panel. Before, the selection was set in the hidden arrival frame, the engine warned "Setting GuiService.SelectedObject to invalid GuiObject" and the selection stayed outside the surface.
- A RadialMenu without an `anchor` opens centred on its launcher, and a full ring moves inward to stay inside the presentation area. Before, it always opened in the middle of the screen, and an anchor near an edge shrank the ring or switched it to a list.
- A RadialMenu wedge takes the selected paint whenever its label does: when it is focused, checked or selected, not only under the pointer. Before, the focused wedge kept the resting panel paint under the selected label color, so its label was unreadable in Glossy Touch and Pixel Quest.
- An open RadialMenu dims the page behind it with the theme scrim, and a still tap outside the ring closes it. Before, the page showed at full strength between the wedges and a tap outside did nothing.
- Restored `UI.AdaptiveStack` and `UI.ViewThatFits` with native measurement. AdaptiveStack turns its axis from a bound `axis`, or without `axis` becomes a column when its row does not fit. ViewThatFits shows the first candidate whose `AbsoluteSize` fits the container and hides the others.
- A text field placeholder takes the theme's `contentSecondary` colour. Before, it kept the engine's grey, which almost vanished on a light skinned field (Fantasy Parchment).
- The TextInput clear button shows the `close` icon with the accessible name "Clear" on a plate-less `utility` Button. Before, it showed the word "Clear" truncated to "C…" in its 44 px box.
- The floating Menu fades through a `MenuGroup` CanvasGroup the size of the panel, around the new `MenuScroll` ScrollingFrame; `MenuPanel` is now a Frame (the plate, with its shadow outside the group). Before, the group wrapped every row inside the scroller, so a long list (the DateTimePicker year menu) grew a group taller than the engine renders sharply and the row text blurred.
- The DateTimePicker calendar icon `Open` sits inside the field at its trailing edge again: a 44 pixel square that shares the field's corners, and the field clips the `Show` and `Open` highlights. Before, `Open` was a separate round button inset from the end of the field.
- The DateTimePicker year menu lists at most 50 years on each side of the shown year, inside `min` and `max`. Before, a far bound listed every year to it (2,126 rows for `min` year 1).
- The DateTimePicker year menu lists at most 10 years on each side of the shown year, inside `min` and `max`. Before, a far bound listed every year to it (2,126 rows for `min` year 1), and the menu's fade group grew taller than the engine renders sharply, so the year text blurred.
- The `row` form of Button, Toggle and Slider is one list row (`facet-list-row`): the leading icon, a `Captions` column that fills the width, then the trailing parts. Its minimum height is the `controlSize` height, and its padding follows the rung on all four sides. Before, a Toggle or Slider row had no top and bottom padding, a Slider row had no minimum height, and `controlSize` did not change the padding of any row. A row description is secondary text in every form. A Slider row now names its title `Title`.
- `UI.ColorPicker` readout: the preview is two cells wide, the RGB/HSV/Hex picker fills the rest of its row, and the fields share their row in equal columns (`HorizontalFlex`), with Hex across the whole row. The swatch and brick grids are centred in the panel. Before, the fields were sized by a fixed third minus 6 pixels and the grids sat at the leading edge.
- `UI.ColorPicker` shows the Bricks technique by default when the controls' `types` has `BrickColor` (the default on Roblox). Before, the default was Swatches, Spectrum and Sliders, so the engine BrickColor palette was hidden unless `modes` listed `"brick"`. A well now names a colour that is a BrickColor by its brick name.
- `UI.ColorPicker` swatch, brick and save cells are 44 by 44 squares with the theme's `radii.control` corner. Before, the button padding narrowed each swatch to a 20 pixel wide pill.
- CollapsibleView expands in place again, as before 0.12. It is not a modal: there is no scrim, no presented layer and no outside catcher. The plate grows over the trigger, and the content fades in, in 0.25 seconds (reduced motion: at once). The collapsed summary is one line that truncates at the end, with a `chevron.down` affordance. The trigger, a tap on the plate, the Close button and Cancel (Escape, ButtonB) collapse it. The Table row More action is now a Popover.
- Pixel Quest paints a selected segment, Chip, list or menu row and Toggle button as its wood plate turned over (pressed in) and tinted green, with a cream label. A chrome art state can now be `{ asset, rotation, tint }`, and a skin falls back to its `selected` art for a selected control in a state without its own art. Before, a selected Pixel segment was a flat green rounded rect.
- A Button `help` plate and a Callout appear as one unit over the theme's `motion.fast` (0.12 seconds by default; reduced motion shows them at once). The help body is capped at 264 pixels by a native `UISizeConstraint` instead of a hidden measuring label, which sat at the end of the plate; a callout tail now waits for the same first styled frame as its panel.
- A segmented Picker keeps each segment inside the width of the strip, or of the row of a labelled strip, and a long label wraps inside that width. A segmented Picker with `query` causes an error. Before, an 80-character label grew its segment past the cell, and a search field and its strip painted under the next cell.
- Table `editable = true` shows an Edit/Done button above the header that toggles `editing` (the same cell as row edit mode). With touch or gamepad input, editor cells accept edits only in edit mode; with mouse and keyboard they stay editable in place. The button keeps the width of the wider of Edit and Done, so it does not jump when it toggles.
- Table paints its header band and rows through the theme tags `facet-tablehead` and `facet-tablerow` (palette roles `tableHeader`, `tableRow`; `control` and `surface` by default). `alternatingRows = true` tags every second row `facet-tablerow-alternate` (`tableRowAlternate`, `surfaceStrong` by default). Before, the header and rows were transparent.
- An image Button hugs its image and text in height (240 pixels wide by default), with the image flush to the top edge, clipped to the top corners, and the text inset from the sides and bottom. With an authored fixed height the image fills what the text leaves. Before, the image took 55% of a fixed 260-pixel plate, sat inset and narrower than the plate on a wide card, and left an empty band under the text.
- `UI.Screen` keeps its content below the engine top bar. It adds the part of the `GuiService.TopbarInset` band that covers it to its top padding, with `IgnoreGuiInset` on or off. Its background still fills the screen. Before, a Screen in a ScreenGui that ignores the inset put its first row under the Roblox menu and chat buttons.
- A pointer or gamepad `UI.SplitButton` is one plate: the primary action and an icon-only chevron segment joined by a hairline, with shared outer corners and one piece of `control` art in a skinned theme. Before, it drew two separate buttons with a gap. The chevron segment keeps a 44 pixel floor and shows `menuLabel` as its help text.
- A skinned plate that lays out its children (a framed TextInput, a panel) keeps its chrome art in a `Chrome` folder, outside the list layout. Before, the list placed the art as a child, so a Pixel Quest search field painted its plate left of the field.
- The theme `toggleTrack` and `toggleKnob` art paints a switch only. Before, a checkbox took the switch art and lost its outline, so a Pixel Quest checkbox drew as a small bar.
- `app.mount` into a PlayerGui replaces the engine selection glow with one theme focus ring (`PlayerGui.SelectionImageObject`): a thin inner `accent` stroke with the control corner, thicker on a `Large` display, shown only after keyboard or gamepad input. Before, a pointer-opened menu row showed the thick engine glow on top of its own highlight.
- A `utility` or `link` Button takes no `control` chrome art. Before, a skinned theme (Pixel Quest, Fantasy) painted a full plate on every utility row, link and outline DisclosureGroup header.
- A skin that paints its own caption (a plaque) hides only its own button caption. Before, the rule matched every button caption inside the skinned surface, so a Fantasy Ornate Sheet showed its action, Done and Toggle labels as empty plates.
- A text Button whose width follows its label no longer truncates it. With `TextTruncate` on such a width, the engine measured the truncated label and alternated between two widths every frame; in a skinned theme a long segmented Picker label raised hundreds of "Maximum event re-entrancy" errors. A bounded width still truncates.
- A skinned control's painted caption rounds its width and height up to whole pixels. Before, a fractional text width (Pixel Quest) was cut down by the whole-pixel offset, so a label that fits showed as "Lab…" or "Automat…".
- A stack keeps the rows of a `Compose.keyed` or `Compose.show` child in the directive's order, and a `LayoutOrder` set in a row orders it within that child. Before, every row got the child's own position, so keyed rows painted in an arbitrary order and a row's `LayoutOrder` was overwritten. A list with such a child spaces its positions by 65536.
- An `outline` DisclosureGroup header starts its chevron and label at the leading edge, like the rows under it. Before, they were centered.
- A text Button or Toggle with an authored width wraps its label and grows in height, and a label that cannot fit its box truncates at the end. Before, a long label painted past the control or was cut in the middle of a letter.
- A VirtualList, VirtualGrid or Table `status` cell that starts as `nil` is filled with the empty status record. Before, the collection raised "attempt to index nil with 'total'".
- Divider paints its hairline in every theme. Before, the Divider wrote `BackgroundTransparency = 1` itself, which beats the `facet-divider` rule, so no line showed.
- A Dialog, Sheet or Callout hero or media with `aspectRatio` keeps its height with a native `UIAspectRatioConstraint`. Before, it measured its own size and set its height, and a Dialog with a hero raised thousands of "Maximum event re-entrancy depth exceeded" errors when it opened.
- A tap outside a Popover closes it. Before, the outside test used the full-screen popup layer, so no tap was outside and the popover stayed open.
- The `environment` factory option previews device facts: `preferredInput`, `touchEnabled`, `mouseEnabled`, `gamepadEnabled`, `keyboardEnabled`, `preferredTextSize`, `displaySize` and `viewportSize`. Each is a value or a readable, and `nil` follows the engine. Every control and `UI.environment()` read the preview. The gallery settings use it for the input and text-size previews.
- Table editable cells. A column `editor` of `text`, `number`, `toggle` or `menu` shows the matching field control in each cell. Each accepted edit calls `onCellChange(rowKey, columnId, value)`, and the caller updates its rows. An edit that changes nothing proposes nothing.
- `app.refusal(control, spec)` returns the words that the constructor of `UI[control]` refuses `spec` with, or nil. It builds under a temporary Compose owner and mounts nothing. Facet now also uses `Compose.withRootOwner`.
- The Snackbar reference lists each dismiss route and warns about a row with no Close, no `duration` and no action.
- NavBar `surface` paints a background plate: `surface`, `panel` or `pane`.
- An icon name that ends in `.fill` names the filled variant, for example `"star.fill"`. The art of the package for that name wins. Otherwise the regular icon draws.
- ShortcutHint takes `label`, the words for the action beside the keys, and `labelPosition`, `end` (the default) or `start`.
- Skeleton `corners` takes `"control"` and `"panel"`, the radii of the theme package, beside a number of pixels, `"square"`, `"rounded"` and `"pill"`.
- Slider `contained = true` makes the rail and the fill as thick as the knob, with round ends. The knob rides inside the rail, and the fill ends at its center.
- The selection ring of a Card body surrounds the whole card, including the action row. `ringTarget = "media"` rings only the artwork. The ring is the native `SelectionImageObject` of the body, painted by the `facet-card-ring` theme rule.
- Breaking: a Dialog action press closes the dialog by default. After its `onActivate`, it proposes `onPresentedChange(false)` with the reason `action`, as the close button does. `keepOpen = true` on an action runs it without the proposal. Sheet, Notice and Callout actions refuse `keepOpen`. Before, actions never closed the dialog.
- Avatar takes `icon`, an icon name drawn in place of the initials, such as `"person"` for a guest. An AvatarGroup member takes `icon` too. `presence = "inExperience"` draws an opaque `accent` ring with a `surface` gap inside the edge of the face, and no corner mark. `background` paints the plate in a palette role and the initials and icon in its partner color.
- StatusIndicator, Badge and a TabView tab indicator take `status = "voice"` and `"contrast"`. Voice uses the optional palette `extra.voice` color, which is halfway between `warning` and `danger` when a palette does not declare it. Contrast is a `contentStrong` mark with `surface` text.
- A Toggle switch follows `controlSize`. The track is the rung `iconSize` plus 4 pixels high and keeps the 38 by 24 proportion. The knob is 6 pixels smaller than the track. Before, every rung drew the 38 by 24 switch.

## 0.12.0 — Compose and native engine cutover

- Menu parity with main. `trigger` attaches the menu to any node and returns that same node with no wrapper; its other native properties and a constructor name apply to that node. `label` and `trigger` together cause an error. `onOpen` and `onClose` run once for each open and close on every route, also for a change of `isPresented` and for unmount. `width` takes pixels, a `UDim`, a `UDim2` or a dimension table (`fixed`, `fill`, `hug`, `percent`, `minMax`, `content`) with pixels or theme metric names. The floating panel is one raised card: the panel owns the `radii.panel` corner, the hairline stroke and a raised shadow, the rows are flat and touch, a hairline separates each pair of adjacent rows, and a selected or checked row fills with `accent` under an `onAccent` label and icon. Each level scales from 0.96 and fades in from the corner where it hangs, and dips out faster. A sheet submenu slides in from the trailing side and Back slides from the leading side. Reduced motion removes the scale and the slide. The panel follows a moving trigger and stays inside the `GuiService:GetGuiInset()` insets when its screen ignores the inset. Placement reads the origin of the overlay on each solve, so a menu in an `IgnoreGuiInset` screen no longer sits one inset too high. A floating submenu has no Back row, and its parent level keeps the open row filled, the checks and the hairlines. RowActions, the HUD scenario, the selection scenario, the date picker and Virtual Monitors attach their menus to their own trigger nodes.
- Restored `UI.Text` for plain text. It is a native TextLabel with the `text`, `textRole`, `role`, `truncate` and `textSize` of main, plus `textAlign`, `wrap`, `rich`, `direction` and `tint`. `textSize` takes pixels, a type role name, `"fit"` or a fit band. `color` and `font` cause an error, because the theme owns them. Every plain-text use of `UI.Label` in the source, examples, tests and guides now uses `UI.Text`.
- `UI.Label` has the meaning of main again: an icon and a title. `title` is required and is the accessible name, `presentation` is `titleAndIcon`, `titleOnly` or `iconOnly`, and `iconOnly` without an icon shows the title. `iconSize`, `textSize`, `gap` and `iconPosition` set the parts. `text` and `label` on a Label cause an error that names `UI.Text`.
- Restored `UI.Image`, a native ImageLabel with `image`, `tint`, `scaleMode`, `tileSize`, `sliceCenter`, `sliceScale`, `resample` and `shape = "circle"`. A tile or slice mode and its geometry are checked in both directions.
- Restored `UI.Divider`. It gets its direction from the stack that holds it, uses the theme's `strokes.hairline` weight, and paints through the `facet-divider` and `facet-divider-strong` tags at the theme's hairline opacities.
- Restored `UI.Spacer`, a `UIFlexItem` fill with an optional `minLength` in pixels or a spacing step. `UI.fill()` stays.
- Migration: `UI.PopupButton` is not restored. It was deprecated on main. Use `UI.Picker { style = "menu", options, selected }`. `UI.TextField` is not restored. It was the renderer leaf under TextInput. Use `UI.TextInput`. `UI.Gauge` was never a control on main. It was the name of a theme example. Use `UI.ProgressView { presentation = "circular" }` or a custom control from `examples/themes/custom_control.luau`.
- Facet now exports `Compose`, `Roblox`, `controls(runtime, options)`, and `themes`. Applications create the Compose Roblox runtime and native `Host` tree directly. This is a breaking cutover with no compatibility APIs.
- Deleted Facet's application shell, scene tree, blueprint schema, layout solver, renderer, presenter, environment, focus graph, input transport, replication and animation facades. Compose owns composition, lifetime, keyed retention, portals, pools and ordered collections. Roblox owns native layout, text, scrolling, selection, drag and styling.
- Controls retain their task behavior through native Instances and Compose owners. Native properties, events and attributes pass through; control refs receive the actual Instance.
- Gallery, virtual monitors, reference apps, consumer and performance lab use the same native authoring model. Themes compile to native StyleSheets linked by the caller.
- Verification records which old mechanism tests were retired and which control behaviors have replacement evidence. The generated Compose vendor remains unchanged.
- Removed first-party explanatory code comments. Compiler directives and legal notices remain.
- Restored the verification producers that still apply to the native architecture: documentation style, maintainer map, brand and call-shape drift, experiment markers, screen key bindings, theme drift, public-surface snapshot, performance scene, capture, place and gate evidence, the release falsification and the release-gate evidence file. CI runs on Ubuntu and on the ARM reference runner.
- Lab audit parity: a Slider `controlSize` sets the thumb size, and the track is at least 44 pixels long. A ProgressView bar `controlSize` sets the track thickness. A read-only Vote mark has the interactive option size. The optional metric `controls.shortcutHint.capStroke` draws the ShortcutHint cap outline. A standard Notice pads its content by the theme's `panel` contentInsets.
- Badge `corners` reads the package radii. The Table resize grip and the Slider track have accessible names. The ornate-gauge and custom-control theme fixtures use the current constructors.
- A `RadialMenu` with `follow = "fixed"` keeps its ring and its center hole until it opens again. The list presentation shows one navigation control: `close` and `back` at the root read "Close", and `back` in a submenu reads "Back".
- Button refuses an `imageFraming` other than `fit` or `crop`. ComboBox refuses a value that is not a string and missing `options`.
- `Facet` exports the `RadialItem` and `RadialMenuSpec` types.
- An unknown control option error names the control and suggests the nearest option, for example `Facet UI.Button: unknown option 'lable'. Did you mean 'label'?`. A spec that is not a table names the control. The duplicate Menu item id error shows the id. The Picker `options` error tells what `options` must be.
- VirtualList, VirtualGrid and Table accept a field name as `key`, for example `key = "id"`. The key is `tostring(item[field])`.
- The type check includes the standalone consumer in `examples/consumer`. The consumer calls `runtime:dispose()` with a colon.
- The getting-started guide shows how to test a screen headlessly with the fake native engine. Guides and tutorial examples use `text` for `UI.Text`.
- `Facet.bind(Compose, Roblox)` returns a Facet table whose controls and themes use the Compose instance that you give. A game that already uses Compose keeps one reactive graph. The controls in `src/ui` use the pinned copy only for types. `Facet.COMPOSE_COMMIT` names the tested Compose commit. `bind` names a missing Compose function. A control names itself when a runtime or a readable from a different Compose instance reaches it. Before this change, such a control failed with a Compose owner error, or did not update.
- The public-surface snapshot lists the `RadialItem` and `RadialMenuSpec` types.
- Navigation and presentation animate by default. A NavigationStack push slides the new page in from the trailing edge and moves the covered page 30 percent with a dim. A pop plays the reverse. TabView crossfades pages in 0.2 seconds. Sheet slides up. Alert scales from 0.94 and fades in. Callout, Button `help` and Menu scale and fade from their anchor. Each exit plays the reverse, faster. Reduced motion removes the motion. `transition = false` removes it for NavigationStack, TabView and Alert. An exiting presentation releases its modal scope and the selection when its exit starts.
- A modal takes the selection again when the engine refuses its first control before the panel is laid out. When the engine moves a leaving modal's selection to a nearby control, the modal still returns it to the control that held it before. A gamepad player now enters a Sheet on present and returns to the opener on ButtonB.
- A real gamepad ButtonA on a selected range Slider handle engages it. The engine gives that press to the handle's drag detector as a drag start, so the handle now engages there. Before this change, the handle never engaged.
- A Card keeps its actions revealed while a mouse button or a finger is held down on Play or More after the pointer leaves the card, until the press ends. Before this change, the engine reset the button state when the pointer left and the reveal ended.
- When a Pagination page that holds the selection leaves the window, the selection lands on the current page in a live engine too. Before this change, the engine moved the selection to another control first, or refused the current page before its layout, and the selection stayed where the engine put it.
- A circular or spinner ProgressView refuses `diameter` with `controlSize`, and ProgressView refuses an `endLabel` that is not a string.
- A segmented Picker option with an `icon` shows its `badge` on the corner of the icon, as a TabView icon tab does. A text option keeps the count in its words.
- StepIndicator measures a whole step before it draws the row: the widest of the label, the state word and the description, plus the Button padding of a selectable step. A row that would overflow its width shows the summary.
- A checkbox Toggle with `controlSize` sizes its box to the rung icon size plus the `xs` space, and its tick with the box, so the box grows with the rung and never outgrows an xsmall row. Without `controlSize` the box stays 24 pixels.
- A held ButtonX removes one editing Chip, as a held Delete or Backspace does. Before this change, the held button removed every chip in turn.
- At a Large, Larger or Largest preferred text size, a segmented Picker strip in a skinned theme grows when its caption does not fit inside the theme control insets, so the segment labels are not clipped. At the default text size it keeps the rung height.
- A selected reorder handle keeps out of the engine's selection drag, so gamepad ButtonA and keyboard Return grab the row, the D-pad moves it and ButtonA drops it.
- `pressHaptic` plays only for a control that changes a state or a value: Toggle, a selectable Chip, an unselected Picker option, a Stepper step, a Slider detent, Rating, LevelPicker, and a destructive or default Alert action. A plain Button, a tab, a menu row, a keyboard key and a link do not play it. Button `haptic = true` opts in.
- Added the layout constructors `UI.Screen`, `UI.VStack`, `UI.HStack`, `UI.ZStack`, `UI.ScrollView` and `UI.Grid`, and the `UI.fill(weight?)` flex item. Each one makes a native Frame or ScrollingFrame with a native list or grid layout. They set `LayoutOrder` from the order of the children. `gap` and `padding` take the `xs`, `s`, `m`, `l` and `xl` spacing steps from `metrics.space` of the theme package, and follow a theme change. `width` and `height` take `fill`, `hug` or pixels. The internal control stacks use the same code. `themes.define` refuses a negative spacing step. `Facet` exports the `StackProps`, `ScreenProps`, `ZStackProps`, `ScrollViewProps`, `GridProps`, `Space`, `Padding` and `Extent` types.
- The generated native property types share one alias for each reactive property type, such as `ValueUDim2`. The public type graph stays inside the analyzer limit.
- Facet pins official Compose commit `a921f43`. This Compose scopes `Compose.cleanup` to each watch run, answers `indexOfKey` before a collection is laid out, and routes a bound formula failure to its error boundary. Compose cells are readables for typing. A native property accepts a value, a readable, a formula or a `function(use)`; Facet names this type `Value`. Compose now recovers every consumer of a formula that raised an error. An overlay exit returns its timeline's completion to Compose presence directly, because this Compose releases an exit that is already complete. An annotated cell checks under the old type solver, so Facet makes no cell type casts. A Formula is a readable, so the public type graph checks inside the default analyzer limit with the new controls. A Button reads its enabled state once for each activation, because this Compose refuses a read of a disposed formula, and a menu row that opens a submenu is removed during its own activation. The generated engine types name one alias for each native value type, so strict type checking stays within the analyzer limits. VirtualGrid focus follows the row placements, because this Compose publishes a collection status only when its summary changes. Badge validates its label, Avatar its name and presence, and StatusIndicator its form in the bindings themselves, so a rejected value does not stop later valid values.
- Restored `UI.ErrorBoundary`. It contains a failure in its `view`, at mount or in a later update, shows `fallback(failure, retry)`, reports the failure once to `onError` or to the factory `onError`, and builds the view again on `retry()`. It uses `Compose.boundary`.
- Facet Neutral declares a `Light` palette beside `Dark`. Both pass the contrast gate. A package that does not declare `style.themes` gets only the first palette of its base.
- Restored the multi-selection keys of Table, VirtualList and VirtualGrid. A plain mouse click selects only that row. Ctrl-click or Cmd-click toggles a row. Shift-click selects a range from the anchor. Shift with an arrow key, Home or End extends the range from the keyboard. A touch tap and a gamepad press still toggle.
- A lazy `Stage` builds its scene when it shows in the scroll window, also while the window scrolls. Before, a feed card that scrolled into view stayed blank until the scroll stopped. Scene animation still pauses while the window scrolls.
- A full-screen Alert source transition keeps the alert content opaque at its final size and clips it with the growing panel. The source snapshot keeps the source size and fades out in the first 35 percent of the motion. Before, the stretched snapshot and the content crossfaded over each other.
- The page under a NavigationStack push or pop keeps its full width. Before, its content was laid out up to 3.3 times wider during the motion, so its buttons stretched and shrank.
- A theme StyleSheet leaves out its `:Hover` rules while touch is the preferred input, so a tapped control does not keep a hover tint. The `hover` option overrides this.
- DisclosureGroup keeps the 8 pixel gap above its body inside the clipped reveal. Before, a collapse ended with an 8 pixel step when the body was removed.
- A mouse click or a touch outside an open RowActions row closes its tray. The row does not consume the press.
- Restored the adaptive environment. `UI.environment(source?)` returns readables for the viewport size, the size and height classes, orientation, interaction classes, display size, safe insets, preferred text size and reduced motion. They come from `AbsoluteSize` or `Camera.ViewportSize`, `UserInputService.PreferredInput` and its capabilities, `GuiService:GetGuiInset()`, `GuiService.PreferredTextSize` and `GuiService.ReducedMotionEnabled`. `Facet.adaptive` holds the pure decisions: `sizeClass`, `heightClass`, `orientationFor`, `axisFor`, `columnsFor` and `sizeClassAtLeast`.
- Restored the world anchor as `UI.worldAnchor(options)`. It projects a part, a model or a player's character to a `RadialMenu` anchor or a marker, with padding, offscreen directions, occlusion and near-plane rejection.
- Restored programmatic scrolling. `UI.scrollTo(frame, position)` and `UI.scrollToVisible(node, rect?)` move native `ScrollingFrame` ancestors the minimum distance. They tween `CanvasPosition` and move at once under reduced motion.
- Restored Text `truncate = "middle"`, which keeps the start and the end of a long value, and `textSize = "fit"`, which paints the largest size that fits the box between a cap and a floor.
- A closed Menu, Sheet, Callout or Button `help` presentation releases its exit timer and its reduced-motion observer when the exit ends. Before this change, each close kept one timer until the control was removed, and an immediate exit kept one finished watch. A NavigationStack page spring reads reduced motion, so a push or a pop with reduced motion does not start a frame connection.
- Added `Facet.app(options?)`. It returns `{ runtime, UI, mount, dispose }`. `app.mount(Component, parent?)` mounts a ScreenGui with a StyleSheet and a StyleLink to it, and returns the stop function and the ScreenGui. The `theme` option goes to the controls and to the StyleSheet, so a game sets the theme one time. `screen` sets native ScreenGui properties and `sheet` sets StyleSheet options, such as the palette. The Virtual Monitors desktop mounts through it. `app.dispose()` stops each mount and disposes the runtime that the app made. The app uses only `Facet.Roblox.createRuntime`, `Facet.controls`, `Facet.themes.createStyleSheet` and `runtime.mount`, and it works with `Facet.bind`. `Facet` exports the `App`, `AppOptions` and `Component` types. The getting-started guide, the README, the component guide and the consumer example use it.
- `UI.Text` refuses `label` and the native `Text` with a named error. The guides, the gallery scenarios and the reference apps use `text`.
- The fake native engine in `tests/lib/native_engine.luau` refuses a property that the Roblox class does not have, as Roblox does. A misspelled native property, such as `Sise`, now stops a headless test with `Sise is not a valid member of TextButton`.
- `UI.Grid` rounds the share of the gaps in each cell up to a whole pixel. Before this change, 7 columns with a 4 pixel gap made a row 3 pixels wider than the grid, and Roblox moved the last cell to the next row.
- The gallery examples `02_playlist_table`, `03_settings_sync`, `05_word_game`, `06_tile_game` and `07_match3` use the layout constructors and spacing steps. Only native nodes that draw game content stay. `02_playlist_table` uses `key = "id"`. `07_match3` reads reduced motion from the gallery readable that the controls also receive.
- The adaptive recipes, the client-server guide and the recipes use the layout constructors in place of a native Frame and UIListLayout.
- The API reference documents one call style: a dot for the plain functions (`app.mount`, `runtime.mount`), a colon for the Compose runtime methods (`runtime:dispose()`, `runtime:batch(body)`). The tests use the colon form.
- `UI.Pagination` selects a page of numbered results. The caller owns `page`, and a press proposes one page through `onChange`. The window shows the boundary pages, the current page and its neighbours. It drops the farthest pages when the measured width is too small, and then shows "Page n of m". The selection moves to the current page when a selected page leaves the window or a selected arrow becomes disabled.
- `UI.StepIndicator` shows the state of each workflow step. `current` alone sets the underline and the summary. Only navigable, enabled steps with `onSelect` are Buttons. When the measured width is too small, the row changes to "Step n of m" and a Steps menu.
- `UI.Vote` shows up, down or none over the caller's value in the segmented strip paint. A press proposes the next value, and a press on the chosen side proposes `none`. A read-only vote shows the choice with no Button.
- `UI.Card` shows an item with artwork and a title, and reveals a primary action and a More menu on engagement. The action plate is always laid out, so the card and its siblings never move. An engaged card lifts to 1.04 with a raised shadow. In a VirtualGrid, `browseTarget` and `controls.enterActions()` make the cell the browse stop and let a gamepad enter the actions.
- Menu takes `edge`, `align`, `width` and `maxHeight`. A floating panel is always bounded by the screen. A level opens with the selection on its selected row, which scrolls to the center. Rows take `badge`, `avatar`, `sectionTitle` and a display-only `shortcutLabel`, and Picker passes an option `badge` to its menu rows.
- TabView takes a per-tab `indicator` and `enabled`. Tab words in a bottom bar shrink toward the caption size to fit before they truncate. A TabView that a page builds later in a branch is nested.
- The gallery adds Motion and layout > Layout > Containers, which shows each container job with native objects and the layout constructors. The Practical recipes guide lists them. The heavy recipe divider is three theme hairlines.
- `UI.badged(host, value, direction?)` puts a count or a dot on the top corner of a host without changing its layout box, hit area or selection. A TabView icon tab shows its badge on the icon corner.
- `UI.VirtualGrid` keeps half of each gap at its outer edges, so a lifted card in a corner cell is not cut by the scroll clip. The lanes are narrower by one cross gap and the canvas is longer by one gap.
- `UI.Dialog` is a modal whose `isPresented` the caller owns. The close button, Cancel and the backdrop propose through `onPresentedChange`, and `onDismiss` reports `close`, `outside`, `cancel` or `action` once. It pins a hero, a title, an action label and actions around one scrolling body, and every region moves into one scroller when the room is too small.
- `UI.Popover` presents content against a trigger, a source node or a rectangle. The placement flips to the opposite edge, then hangs beside the source before any clamp, and takes `crossOffset`. A compact touch screen gets the Sheet route. Removing the source node reports `anchorLost`.
- `UI.Snackbar` shows one short message at a time at the bottom of the layer. Close, Cancel, a timeout and a supersession propose through `onPresentedChange`. Readable time pauses under hover, selection and modals. Nine rows can be shown, waiting or leaving.
- `UI.Notice` keeps a page status in view with a severity, a link, up to two actions and a close button. An affixed notice sets `FacetInsetTop` on its layer, and a visible snackbar sets `FacetInsetBottom`.
- `UI.NavBar` is the slot bar: Back, leading, a filling center and one trailing node that moves to a second row when the center has too little room.
- `UI.Sheet` takes `placement`, `edge`, `width`, `header`, `hero`, `actions`, `actionLayout`, `contentInset`, `scrollPolicy`, the `hug` detent and a `closeButton` that can carry a localized label. A release projects by its velocity, and a drag resists past the limits. The grabber reads `Size: Medium`.
- `UI.Callout` takes `title`, `media`, `steps`, up to two `actions` and a top `closeButton`. A failing `onShow` goes to `onError`.
- Button `help` also takes `{ title, body, shortcut, edge, align }`.
- `Facet.civilDate` is the civil date calendar from `main`: arithmetic, the numeric words of a locale and fixed-offset instants. `Facet.recipes.arithmetic.parse` is the bounded arithmetic parser from `main` for a number field. The types `CivilDate`, `CivilRange`, `CivilLocale` and `CivilDateModule` are exported. The type check runs at the default analyzer limits: the full `Facet` type stays within them.
- `UI.TextInput` has the field chrome from `main`: `label` (activation focuses the field, and the label is not a focus stop), `requiredMark` notation, one `hint` or `errorText` line with the error mark, `leading` and `trailing` Instances in the plate, `controlSize`, `appearance` and `corners`. It also takes `readOnly`, `selectOnFocus` (`none`, `all` or `end`, once for each focus session) and `visibleLines` for a multiline field. A field without these options keeps its TextBox root. **Breaking:** the constructor type returns `TextBox | Frame`.
- `UI.NumberInput` is `UI.TextInput` with the number presentation, as on `main`. It adds `step`, `precision`, `stepButtons`, `prefix`, `suffix` and `scrub` (a horizontal drag moves one step for each 8 pixels). **Breaking, number presentation:** `onCommit` reports the committed number; a number outside `min` or `max` commits the bound with the reason `clamped`; the default parser is a strict decimal grammar; an incomplete draft restores the last number without a message unless the field is `requiredMark = "required"`.
- `UI.Slider` has the shapes from `main`: `axis = "y"` (bottom to top, Up and Down), `range` with `minGap` (two handles that never cross, one commit for each gesture that names the handle, pad adjust mode, a late illegal pair kept out), `thumb` (`always`, `auto` or `none`), `thumbContent`, `trackContent`, a paint-only `rotation` with press conversion, and `controlSize` track thickness. The arrow that moves the selection onto a slider is not also a value step. The Slider is now in `src/ui/slider.luau`.
- `UI.Picker` is a field, as on `main`: `requiredMark`, one `hint` or `errorText` line in every style, `controlSize`, `appearance` (menu `standard`/`contrast`/`utility`, segmented `filled`/`stroke`/`utility`, mapped by `automatic`), `corners`, `maxHeight` and radio `indicatorPosition`. A labelled menu picker stands its title above the trigger. The new `cards` style shows options as cards and clears on a second press when `required = false`. Options take `meta`, `sectionTitle`, `avatar` and a live `indicator`; menu rows show `badge`, `meta` and `avatar`, and a menu opens on its chosen row. Main's avatar `key` and `provider` fields are not ported: the native Avatar takes `name`, `image` and `userId`.
- A switch or checkbox `UI.Toggle` takes no `control` art from a theme package, as on `main`. A Toggle settings row has the `facet-toggle-settings` tag and the horizontal padding of a Button row.
- **Breaking:** `UI.Chip` removal is edit mode, as on `main`. A chip with `selected` and `onRemove` requires the caller's `editing` value; a remove-only chip is always in edit mode. The separate Remove button and the Frame root are gone: the chip is one TextButton with a `Remove` text mark, and activation or Delete, Backspace or ButtonX removes it in edit mode. A removal key that is still down when selection moves to the next chip does not remove it too.
- **`UI.DateTimePicker`.** A civil date or date range field that opens an anchored calendar panel (below the field, start-aligned, flipping above, capped to the screen; a sheet with Done on a compact touch screen, a centred sheet at ten feet), or the calendar inline: one month for a single date, two consecutive months for a wide range, header month and year menus bounded by `min`/`max`, days outside the bounds or refused by `isDateDisabled` selectable, struck and inert, typed entry in the field when keyboard and mouse is preferred, hour and minute fields on the `minuteStep` grid with AM/PM and a touch time list, range end drags, presets clipped to the bounds and an Apply/Cancel/Reset all draft. Proposals go through the caller's callbacks. The day grid uses native GuiService selection with InputActions for the arrows and L1/R1/Comma/Period paging. `ref` receives the root Frame; the root carries `month`, `dual`, `route`, `presented`, `text`, `typedError` and `diagnostics` attributes. A `UI.Menu` level whose selected group holds one of its enabled rows now opens with selection on that row.
- **`UI.ColorPicker`.** A colour well over your Color3, ported from `main` onto native Instances. It opens an anchored panel (below, else above, else beside, else shrunk and scrolled; a sheet on a narrow touch screen; a centred sheet at ten feet) or shows the panel inline. The panel has Swatches, Spectrum (a two-layer UIGradient plane with a UIDragDetector, and a rainbow hue strip), Sliders and Bricks techniques, an RGB/HSV/Hex readout, optional opacity (`alpha`), saved colours (`onSaveSwatch`, `onRemoveSwatch`), `draft` with Apply and Cancel, right-stick steering, and a colour bubble above the finger on touch. `ref` receives the root Frame, and its attributes replace main's `dump()`.
- `UI.Card` takes `artwork`, a factory for live artwork such as a Stage preview, in place of `image` or over it. The body `onActivate(input)` receives the native input of the activation.
- A Button whose activation removes the Button no longer reads released state after `onActivate` returns. Before this change, a Menu row that closed its menu raised a disposed-formula error.
- Virtual Monitors uses every public Facet field, control and theme function: the layout constructors, `Card`, `NavBar`, `Notice`, `Snackbar`, `Dialog`, `Popover`, `Vote`, `StepIndicator`, `Pagination`, `badged`, `DateTimePicker`, `NumberInput`, field chrome, `ErrorBoundary`, `civilDate`, `recipes.arithmetic`, `bind` and the theme package functions. `tests/native_virtual_monitors_coverage.spec.luau` fails with the names of any unused ones. `VirtualMonitorsAPI` also takes `tab`, `open`, `close` and `chat`.
- A Sheet stays off screen until its room, width, text and height are stable for two frames, then slides. The text has its final size and wrap before the sheet shows, and the height does not animate during the entrance. The `hug` detent measures the body content instead of the scroll canvas, which was never smaller than the window and made a hug sheet grow on each frame. A full-screen Alert keeps its content at the destination size while it grows from its source, so its text does not wrap again.
- A Card does not lift when `PreferredInput` is `Touch`. A tap on its body, primary action or More shows only the press paint of that control. The artwork height uses the width without the lift, so a lifted card no longer changes its own size. `controls.lifting` and the `FacetLifting` attribute report the lift.
- Stage passes a `live` readable to `content(runtime, world, live)`. It is false while the nearest ScrollingFrame scrolls, for 0.15 seconds after, and while less than half of the stage shows. `lazy = true` builds the content only when the stage is first live, one stage per frame. The Virtual Monitors game grid builds its card scenes lazily and pauses their animation while the grid scrolls.
- Virtual Monitors turns off default voice chat with `VoiceChatService.EnableDefaultVoice = false` in its project file.
- Every presented surface has motion by default. Dialog and CollapsibleView scale from 0.94 and fade in with the scrim in 0.2 seconds, and leave in 0.15 seconds, as Alert does. The Dialog panel is a CanvasGroup; the CollapsibleView surface is a CanvasGroup named `ExpandedPresentation`. The Snackbar row is a CanvasGroup that fades as it slides, and a leaving row cannot be interacted with. DisclosureGroup opens and closes the height of its content in a clipped `Reveal` frame, fades the content and turns the chevron, in 0.25 seconds in and 0.2 seconds out. Collapsing content cannot be interacted with, and the selection moves to the header when the collapse starts. A new Notice opens its height from 0. Its close button closes the height and then calls `onDismiss`; a notice that stays mounted opens again. Reduced motion makes each change immediate.
- `UI.Popover` takes `title`. The compact sheet shows it in the header beside Done and uses the `hug` detent in place of `medium`, so the sheet fits the content. Before this change, the sheet showed an empty band above short content and no title.
- A modal root and its scrim are Active. While a modal is open, each ScrollingFrame in the same LayerCollector outside the top modal has `ScrollingEnabled = false`. Facet writes the recorded value back when no modal holds the frame, also for stacked modals, frames that were already `false`, frames added during the modal and frames that leave the layer. Before this change, a drag or a wheel in a Dialog also scrolled a grid below it. The fake native engine fires `DescendantAdded` and `DescendantRemoving`.
- A `radioGroup` Picker puts the radio mark in its own slot in the content row of each option. Before this change, the theme padding moved the label under the mark.
- A horizontal segmented Picker track is one control height tall. The segments fill the track inside a 3 pixel inset. The `.facet-segment::UICorner` rule sets the segment radius to the track radius minus the inset. Before this change, the selected segment was taller than the track.
- NavBar keeps the title and the trailing node on one row when the full title fits. Before this change, a bar narrower than about 360 pixels plus the trailing node always used two rows.
- The theme has a `:Press` rule for each control family that has a `:Hover` rule: segments, choices, tabs, calendar days and the quiet and menu destructive rows. A current segment or choice keeps its selected paint while pressed. Before this change, a pressed control showed its base paint between the highlight and the selected paint.
- During a NavigationStack push or pop, both pages are opaque with the background color of the nearest opaque container. The covered page is dimmed by a separate shade. Before this change, the transparent pages showed through each other.
- The Virtual Monitors header shows the overflow menu as an icon button with the accessible name "Menu".
- The Virtual Monitors Avatar palette (Sage, Clay, Iris) is now the accent of all three apps in light and dark. Each accent is a palette of the app theme package, swapped through the native StyleSheet. The hat colour comes only from the ColorPicker. `workspace.VirtualMonitorsAPI` adds `accent`, `summary`, `about`, `status`, `appearance` and `tips` for Studio evidence.
- Theme packages can declare optional roles and metrics. A palette that does not declare them paints as before. `extra.selection` and `extra.onSelection` paint the switch, the checked box and tick, the slider fill and the underline indicator, and then also a chosen Chip (tagged `facet-selection-mark`) and a selected link Button. `extra.scrim` colors the modal backdrop. `extra.inverseSurface` and `extra.onInverse` paint the new Button `appearance = "inverse"`. `extra.dimDisabledPlates = true` fades a disabled plate with its text. `extra.strongHairlineOpacity` tunes the new `facet-divider-strong` tag, and `facet-pane` paints a flush pane. `metrics.controlSizes.xsmall` is an optional fourth size step; without it `controlSize = "xsmall"` is one step below `compact` (28, 4 and 12 with Neutral). `metrics.targetSizes.pointer` (24 up to the minimum) makes floating Menu and Picker menu rows dense while the input is pointer-only, and they grow back live when touch or a gamepad appears. `metrics.strokes.utility` draws an outline on a utility Button. `themes.define` refuses a partial `xsmall` step and a `pointer` value outside its range.
- New control options: Button `underline` (`always` or `hover`) and `textSize` (a type role or pixels, which also reaches the label beside an icon); Toggle `appearance = "plain"` and `textSize`; DisclosureGroup `appearance = "outline"`, `textSize` and `indent`; TabView `controlSize`; Sheet `placement = "adaptive"`, which docks at the side edge on a wide screen with a mouse and no touch; Picker `valueAlignment = "start"`, which keeps a labelled menu on one row and hugs the pair with `sizing = "hug"`. The gallery shows the `xsmall` step, the inverse and underlined links, a plain checkbox, a strong divider and an outline group.
- A Picker option `badge` shows as a `Badge` named `Count` in stacked rows and in the searchable list of a `navigationLink` Picker, as in menu rows. Before this change, those rows added the count to the label, for example "Beta (9)". A segmented option keeps the count in its words.
- A Sheet released after a drag settles from the height where it was released, at the release speed, and does not overshoot the chosen detent. Before this change, the panel jumped back to the lagging motion value on release and then tweened from rest.
- A Popover whose `source` node never mounts warns once with the node name.
- When a Dialog, Sheet or Popover room is too small and unpins its regions into one scroller, the scroller is never a selection stop, and Up or Down reaches the next control even when it is scrolled out of view: the engine only moves the selection to a control it can see, so Facet scrolls the room and selects the next control above or below. Before this change, a gamepad player could not reach the actions of a short sheet.
- A press outside an anchored Popover closes it, including a press on its trigger. Before this change, the full-screen popup wrapper counted as the panel, so every outside press was ignored.
- The Recipes divider examples sit under an icon row in one card of at most 360 pixels. A leading or trailing inset is the distance from the row to its text, so an inset line starts at the text.

## Pre-0.12.0 development history

The entries below retain their original labels and describe the former API.
The 0.12.0 entry above and the current API reference supersede that authoring model.

### Unreleased — interaction and theme hardening

- Tab bookmarks follow real navigation, including shoulder entry, while explicit focus requests keep their destination.
- All plain Chips reserve disjoint effective targets. Toggle accepts bound width for wrapping content-sized settings; display-only switch labels clamp at zero space.
- Built-in sheets tint resolved framework icons, over-media lettering follows contentStrong, and success/warning pair validation covers authored variants.

## Unreleased — semantic status colors

- Added success/onSuccess and warning/onWarning palette pairs and public effective-pair helpers. Both compile gates enforce 4.5:1; omitted pairs retain earlier fallback paint. Explicitly authored roles that were previously inert now paint and must pass validation.
- Badge semantic art retains one caption-sized host, with room for multi-character fallback glyphs. Managed pictures on the four explicit readable partner roles follow that lettering, including selected menu/picker content; unrelated package icon tint remains unchanged.


All notable changes to Facet are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Facet's version
numbers follow the policy in
[the versioning policy](CONTRIBUTING.md#versioning): while the
library is pre-1.0, a minor bump may change public behavior, and every retiring
surface is documented in its breaking release. The 0.12.0 cutover removes old
surfaces immediately.

The version string lives in exactly one place, `src/init.luau`, and is readable at
runtime as `Facet.VERSION`.

## [Unreleased]

- A chat thread can be scrolled while a reply is arriving. `UI.VirtualList`'s
  `follow = "end"` re-pinned the end on every frame of content growth, and one
  frame of a pan never moves the whole `followThreshold`, so a player panning
  away from a growing thread was snapped back faster than they could travel and
  the list read as completely stuck (measured on a phone: canvas 1216 in a 389
  window, a 230 px pan moved the offset 827 -> 827, while the same gestures
  worked once the thread was a few hundred px up). Following now YIELDS on a
  reported offset that moves away from the end — including from inside
  `followThreshold`, which is what the old test could not see — and while it is
  yielded, growth moves the view by nothing. It resumes when the player comes
  back to the end, or when the consumer re-asserts `follow`. The list's own
  follow-write is matched against its echo, so it is never mistaken for the
  player.

- A desktop the engine buckets as a `"Large"` physical display no longer gets the
  ten-foot treatment (1.5x type, metrics, target floors and overscan margins).
  `GuiService.ViewportDisplaySize` answers `"Large"` for a 4K desk monitor, and a
  big pixel count is not a long viewing distance; a mouse now corroborates
  against it exactly as a touchscreen already did. A console has neither and is
  unchanged, and `viewingDistance = "ten-foot"` still outranks the derivation.
- A placement property a parent never reads (`alignH` under a stack, the
  `offsetX`/`offsetY` pair `UI.offset` writes under anything but a `UI.Anchor`)
  now `warn`s in Studio, once per site, as well as being reported on
  `controller.diagnostics()`. Off in a running game.
- A finger can scroll a list of draggable things again. A `UIDragDetector` owns
  a touch from the press and keeps it whether or not the press ever becomes a
  drag, so on a phone a feed of draggable cards could not be scrolled at all
  (measured: a 230 px flick moved the scroller 0 px; the same flick with the
  detectors off moved it 249 px). A touch press now claims nothing until it has
  been held still for `interactionTokens.touchDragArm.holdMs`; travelling
  `slopPx` first releases the gesture to the scroller — or to a swipeable row —
  for good. A mouse and a pen are unchanged, and so is any engine with no
  touchscreen. `UI.draggable`'s `declineTouch` also reaches the engine's
  acquisition now: it used to disable Facet's own drag and leave the detector
  claiming the finger anyway, which was the worst of the two.

- ...and the hold now actually *picks the thing up*. The arm above switched the
  engine's detector on and stopped there, so a player who held a card still felt
  nothing, saw nothing, and then watched the page pan out from under the card
  when they moved. Three things changed. An armed press is now a **promotion
  already spent**: the drag session begins at the arm instead of asking for
  another 14 px of travel, so the ghost, the lift and the `dragHeld` state all
  land at the moment the hold does. The nearest scrolling ancestor is **stopped
  for the rest of an armed gesture** and handed back when the drag ends (never at
  the lift — the engine can still be dragging). And `holdMs` is **280 ms**, not
  320, which sits closer to what a phone teaches. A mouse, a pen and any engine
  without a touchscreen are still untouched.

- A surface presented before its content exists now navigates that content when
  it arrives. Whether a screen's ring is GROUPED (so Down moves by direction and
  Left/Right are a real horizontal axis) used to be settled once, at present
  time, from the tree as it stood then — so a screen whose body is behind a
  `Compose.show` or a tab, and is therefore presented empty, walked every control
  that arrived later in flat document order and had no horizontal axis at all.
  The focus graph was already grouped; only the key wiring was not.

- A `UI.PageView` carousel is ONE keyboard and gamepad stop: Left/Right page,
  Activate reaches the page's own primary action, and one vertical press leaves
  it. The page indicators stay tappable and stay the stops for a carousel whose
  pages hold no focusable of their own.
- A `UI.ComboBox`'s suggestions opener is exactly as tall as the field beside it.

- Consolidate Showcase recipes into existing family tabs with shared reset actions.
  Long removable tags scroll horizontally; progress tracks retain visible segments
  beside trailing copy at large text sizes. New-control scaffolds use existing demos.

- Setting rows retain their real switch/checkbox with optional side, hint and size.
  DisclosureGroup gains description, icon, side, appearance and size; removable
  Chips retain independent target floors and collection focus. Add the archived
  settings gear without changing earlier icon art. Small status cutouts cap their
  separator proportionally so thick theme strokes do not consume the mark.

- ProgressView gains a trailing endLabel and checked live spinner/circular size
  rungs. Omitting the rung preserves each package's authored indicator sizes.

- Add passive `UI.StatusIndicator` shapes/counts and `UI.Badge` captions with live
  status paint. Avatar presence uses the shared status shapes and cutout. Existing
  All controls Indicators gains Status and Badges child tabs. Round marks fit both
  reserved axes, counted height resolves once, and Badge caption presence stays live.

- Add `UI.AvatarGroup` keyed player rosters with shared caller-owned picture
  requests, stacked or spread faces, and one optional overflow target. Indicators
  gains an Identity child tab alongside its existing Progress demonstrations.

- Add `UI.Avatar` player pictures and UTF-8 initials with caller-owned loading,
  presence marks, localized semantic labels, and optional activation targets.

- Add `UI.Skeleton` loading silhouettes with checked bound sizing and a shared
  decorative shimmer whose lifetime follows mounted Compose branches. Reduced
  motion retains a static theme-tinted plate.

- Bound control sizes and each control's appearance family reject invalid updates
  before publishing derived geometry or paint, and recover on a legal value.
  Scroll extents require positive finite pixels or known metrics resolving to
  that range. Middle truncation returns an ellipsis for nonpositive width.
  Rich text caps authored font sizes at 100 in both published markup and layout,
  leaving caller strings intact. It measures glyphs and runs in one parse; font memos have bounded
  admission and reset with measured text. Rich inter-word spaces use their active
  font and size, including learned widths, so a large span reserves its full phrase.
  Button and Chip animation policies
  now reach the primitive plate and retain its property validation.

- Custom-child Buttons retain their theme padding when a control size is named;
  explicit padding still wins. A Button with no drawable content now refuses,
  even when a semantic name is supplied; an initially empty bound label remains
  valid. Decorative text reveals no longer block horizontal drag acquisition;
  real overlays, native child gestures and an authored scroll freeze retain
  their existing input ownership.

- Add passive `UI.ShortcutHint` keycaps, borrowing live action names and native
  key labels/images. Shared input lookup follows device class and the hint's own
  surface, including passive contexts; revision changes update bindings in place.
  Provider teardown is safe out of order. Keys use theme tint and icon sizes,
  with no decoration slot or interactive floor. Existing Actions and Adaptive
  pages now include keys/labels/link navigation and a measured container grid;
  the grid uses actual inner geometry and updates already-visible debug bands.

- `UI.Label.title` accepts Compose readables and tracked functions; visual text,
  accessible text and dumps update together without rebuilding. Semantic icon
  names use package art with the shared glyph fallback; asset URLs remain Images.
  `UI.Text.over = "media"` exposes the existing strong-contrast style treatment
  for passive text over artwork, as a construction-only word.

- Expose the native leaf capabilities the leaf specs did not reach. `UI.Text`
  takes `rich` (construction-only boolean, default false — parses the engine's
  closed tag set `b i u s font stroke br uc sc mark` plus the five `&…;` escapes)
  and `direction` (`"auto" | "ltr" | "rtl"`, mapped to `TextDirection`; absent
  leaves the class default, which is not the same as authoring `"auto"`).
  **Measurement reserves the box for the DISPLAYED text**, so a tag never widens a
  label: EVERY well-formed tag and `<!-- -->` comment is removed (measured live —
  the engine consumes markup it does not implement rather than drawing it),
  `<uc>`/`<uppercase>` content is measured upper-cased, and markup that does not
  parse is measured RAW because that is what the engine draws. A span that changes
  FACE — `<b>`, `<font weight|face|size>` — travels with the string to the per-word
  measurement key and is measured at that face (in every `weight` spelling the
  engine accepts: the nine `FontWeight` names case-insensitively and the nine
  numbers they carry, so `heavy`, `Heavy` and `900` name one face and `800` is
  `ExtraBold` rather than being rounded up to it), which is what keeps
  a marked-up label from clipping; small caps, non-ASCII upper-casing and nested
  face changes remain approximate and are named in `docs/reference/api.md`. The disclosure plate and the `reveal`
  strip render a rich label's value as rich. New public
  `Facet.richText.escape(s)` escapes `< > & " '`; escape untrusted or
  composed-in text before pasting it into markup (it is not a text filter).

- Add `UI.Text{ truncate = "end" | "middle" }`, default `"end"` (the engine's own
  end ellipsis, unchanged). `"middle"` keeps the head AND the tail, sized by
  the library's own measurer to the DRAWABLE width (the box minus the label's own
  padding, published on the solve's text facts as `padX`), re-derived only when the
  string, the face, the size, that width or the measurer's own epoch moves — the
  last is the engine's boot window, so a cut derived before the text metrics settle
  is derived again when they do. The engine has no such mode, so this is a fit
  policy rather than an adapter write. The whole value stays reachable through
  `disclose`. `truncate = "middle"` needs `lineLimit = 1` and cannot be combined
  with `rich = true`; both are spec errors.

- Add `UI.Image{ resample = "default" | "pixelated" }` (`ResampleMode` — pixel art
  stays crisp), and two new `scaleMode` words, `"tile"` and `"slice"`, each with
  a required companion geometry key: `tileSize = { width, height }` in whole
  pixels `> 0`, and `sliceCenter = { x0, y0, x1, y1 }` — the stretchable centre
  RECTANGLE in SOURCE pixels, the engine's own `SliceCenter` under the name and
  shape a theme package's art already uses, never insets — plus `sliceScale`
  (`> 0`, default 1). A geometry key without its mode, or a mode without its
  geometry, is a spec error; the geometry keys are construction-only, so the two
  new modes are authored statically and a BOUND `scaleMode` resolving to either is
  refused at the binding write (new `PropSpec.staticOnly`, checked in
  `primitive_properties` through the Compose property write). Theme-owned nine-slice chrome is unaffected.
  `UI.AsyncImage` forwards all five keys.

- Add `UI.ScrollView{ axis = "xy" }` (`ScrollingDirection.XY` — neither axis
  clamps its canvas), `scrollEnabled` (`Bound<boolean>`, default true; false
  freezes PLAYER scrolling through `ScrollingEnabled` while the offset, the layout
  and framework keep-visible are untouched), `extent = { width?, height? }` (an
  explicit canvas in pixels or a theme metric name, for a host whose canvas is a
  coordinate space rather than a content sum — **only on an axis this host
  scrolls**, because the adapter clamps a cross-axis canvas back to the window and
  accepting one would diverge live from headless). `indicators` stays ONE word for
  both axes: a `ScrollingFrame` carries one `ScrollBarThickness`, so a per-axis
  form would be a declaration that does nothing, and a table is refused. An `xy`
  host is a `"y"` host to the chrome lane, the leading-edge bleed and the
  drag-to-edge autoscroll band; its children arrange at their natural size on both
  axes; keep-visible moves both axes; and it reaches the same nested-scroller chain
  rule: pinned at the end of the band a drag is asking for, it is transparent and
  the page behind it wins. `ScrollingEnabled` has ONE writer — the paging
  mouse-drag restores the authored value at release rather than an unconditional
  `true` — and Facet's own drag-to-edge autoscroll respects a freeze.

- Add eleven common glyphs to the framework's own standard icon set: `status.info`,
  `status.success`, `status.warning`, `status.error`, `calendar`, `clock`,
  `vote.up`, `vote.down`, `person`, `chevron.first` and `chevron.last`, each with
  an ASCII fallback floor (`i`, `ok`, `!`, `x!`, `[#]`, `(:)`, `+1`, `-1`, `@`,
  `|<`, `>|`). Same generator, style, manifest and resolver as the existing
  eighteen; no control wires them in yet.

- Add optional local `controlSize` (`compact`, `regular`, `large`), `appearance`,
  and `corners` to `app.controls.Button` and `Chip`, plus Button `over = "media"`.
  Compose readables and `function(use)` bindings update size and appearance in
  place. Named sizes use theme metric paths and reserve the effective hit floor
  in layout, so compact neighbors retain separate targets. Appearance composes
  with semantic role at rest, hover and press in the default and package sheets;
  `standard` is the untagged default. Button gains construction-time semantic
  `icon`/`trailingIcon` and the required `name` for icon-only content; Chip gains
  static `leading`/`trailing` content. Omitted keys preserve existing behavior.

- Application presentation forwards the existing renderer comparison options
  `measureReuse`, `commitScope`, `structuralReuse` and `translateHosts`.
  `Facet.schema` exposes read-only constructor facts for contract tooling, and
  the supported PopupButton alias is again listed in the deprecation ledger.
- Application disposal immediately retires animated exits, toasts and auxiliary
  surfaces before releasing their state. All cleanup steps run even if one fails.
- Headless test worlds release their complete applications after each case.
  CI runs the full verifier with one worker, reports producer progress, and saves
  verification diagnostics on failure.

### One authoring model (breaking)

Facet has one way to build an interface. `local app = Facet.new(opts)` builds the
application and `local UI = app.controls` is its constructor table. A component
is a plain Luau function that returns a node. State is `Compose.cell`,
`Compose.formula`, `Compose.watch` and `Compose.cleanup`, and lifetime is a
Compose owner. Present with `app.mount`, `app.presentModal`,
`app.presentAnchored` and `app.presentToast`.

This lands before 0.11.0's first publish, so the surfaces below are removed
directly rather than deprecated for a minor version
([the versioning policy](CONTRIBUTING.md#versioning)). Each row
names what moved and why a caller breaks.

| Removed | Use instead | Why a caller breaks |
|---|---|---|
| `Facet.UI.<Class>({ id, children, … })` | `app.controls.<Class>("Id")({ …, child, child })` | The blueprint constructors are gone. Children are positional and the identity is the constructor name. |
| `Facet.Controls.<Name>(core, spec)` and `.blueprint` | `app.controls.<Name>(spec)`, which returns the node | A control is built under an application, not a core. Its record arrives through `ref`. |
| `Facet.View`, `Facet.component` | A plain function that returns a node | There is no component wrapper and no separate state API. |
| `Facet.mount(core, blueprint)` | `app.mount(component)` | Mounting belongs to the application, which owns the surface and its teardown. |
| `Facet.newCore`, `Facet.newPresenter`, `Facet.newEnvironment` as entry points | `Facet.new(opts)`; reach `app.environment` and `app.presenter` from it | The application builds and releases these together. |
| `core:signal`, `core:memo`, `scope:own` | `Compose.cell`, `Compose.formula`, `Compose.cleanup` / a Compose owner | State and ownership are Compose's. `:get()` reads become `:peek()` or a tracked `use(...)`. |
| `Facet.preload` | Nothing; controls load with the application | The deferred control loader is gone. |
| A composite's `dispose` and `blueprint` on its record | The owner the control was built under | `ref` publishes `{ api, dump }` only. |

New public API:

- `UI.Toggle.onChange(wanted)` requests a model change before any write. The
  model accepts by writing its value; a declined request preserves the value
  and appearance, including a checkbox's mixed state. This form accepts
  readonly Compose bindings. Cell-only toggles continue updating directly.
- `UI.activationGate(node, { closed, onOpen })`. While `closed` reads true, the
  first Activate at or under the node wakes the subtree instead of reaching what
  is under the press. `onOpen(path, meta)` receives the path that press would
  have reached. One dispatch covers pointer, touch, keyboard and gamepad.
- `Facet.motion.newTextReveal({ value, cursor?, placeholder?, policy? })`. It
  publishes `text` and `revealed`, never splits a codepoint, paints
  `placeholder` only while nothing is revealed, and lands the whole value when
  `policy` reads `"reduced"`.
- `transition.source` on `UI.When` and `UI.ForEach`. With `enter = "transform"`,
  `{ path = "…" }` or `{ rect = … }` expands the region from a shared element.
  The source rect is re-read on every painted frame, so a moving source is
  tracked. Either field may itself be a readable.
- `app.newResourceProvider(options?)` returns `provider, release`. `options.bind`
  replaces the Roblox transport.
- `app.presentToast(component, options)` runs the component inside the toast's
  own row.
- `ref` on a composite control's spec. It must be a function, and it is called
  once while the control is built, with a frozen `{ api, dump }` record.
- `UI.PageView` `summary` and `controls`. Both are booleans; `false` removes that
  row.
- `UI.VirtualList` `follow` accepts a readable.
- `UI.Slider` `step` accepts a readable.
- `UI.ComboBox` puts the field and its opener on a single row.
- `UI.DisclosureGroup` does not draw an expanded header as selected.
- `UI.ForEach` and `UI.When` are public and take schema-shaped specs:
  `items`/`row`/`key`, `condition`/`thenView`/`elseView`, and `transition`.

Focus and enablement:

- `enabled = false` means the node and its whole subtree.
- A presentation refuses when `initialFocus` names a disabled control, on every
  screen. The error lists the focusables that are available. Name a control that
  is live, or use `"first"` or `"none"`.
- The arrows cannot cross a `Grid` row whose every cell is disabled. A grid names
  each row group's `up`/`down` exit by index, so an emptied row is still the
  named neighbour and everything below it is unreachable by the arrows and the
  pad. The same content as stacked `HStack` rows is crossed cleanly, and
  `UI.When` removes the row outright. Tab is unaffected.

- Replace Signals and Facet’s duplicate scheduler and
  ownership storage with pinned Compose cells, formulas, watches, batching and
  owners. Remove the unused `Facet.Signals` export and raw-getter bridge.
  Delivery now follows dependency FIFO, and runaway watches use the native
  million-run cap with explicit re-registration after abandonment. Failed
  evaluations retain partial dependency changes. Keep Facet’s renderer settling,
  structural transitions and error boundaries. See `src/core/README.md`.
  Rebuild all bundled tutorial, showcase, reference and performance places with
  this runtime; examples use plain components, Compose cells and `function(use)` bindings.

- Unlink retired child scopes in constant time, preserving reverse cleanup order
  and cleanup-error quarantine. Large keyed collections no longer scan and shift
  the parent's ownership list for every removed row; storage tracks live resources.

- Toast rows animate into vacated positions at either screen edge. Add per-toast
  `width` using ordinary dimensions, including content-fit `hug`; default slides
  avoid CanvasGroup text rasterization, while explicit fades remain available.
  Component toast bodies inherit environment and animation services.
- `UI.ProgressView` inherits the mounted owner and presenter clock, including
  activity cycles and trails. Maintained examples adopt ordered numeric children;
  tutorials, showcase chrome and reference views use Compose state, property
  bindings and automatic ownership. New-feature scaffolding and contributor
  guidance teach the same syntax.
- Track getter-based drag enablement without invoking payload callbacks.
  NavigationStack pages and Alert content accept component descriptions.
  AsyncImage request leases follow the mounted owner, including stale-response
  rejection after unmount.
- Prevent getter indexes from retaining cyclic values after unmount; keep shared
  bindings alive through their component owner instead of a global strong value.
- Earlier unreleased Signals queue optimizations are superseded by the pinned
  Compose runtime described above.

- Native StyleRule paint transitions now default on with explicit opt-out and live reduced-motion support; `client.host` installs Roblox's easing evaluator just like `motion_driver`.

- Historical unreleased work introduced Signals 0.9.0, `Facet.component` and
  `Facet.View`. The current authoring-model change above replaces those APIs
  with Compose and plain component functions, including the showcase and
  Settings Sync examples.
- Add declarative screen, billboard and surface placement to the client host.
- Complete previously untyped public control specs, describe activation metadata,
  and check real component authoring with the pinned Luau analyzer.


- Add segmented ProgressView bars, delayed damage trails, and sized circular HUD
  gauges with readouts that adapt to preferred text size. Share transient HUD
  reservations through the presenter and add pure HUD inset/marker layout helpers.
  World anchors can retain offscreen direction and test center occlusion.
- Expose Toasts in the Showcase's Indicators pages and World markers in its Layout
  pages. Screen-anchored HUD actions demonstrate damage, healing, and notifications
  that displace nearby HUD content without taking focus.


- Expand adaptive region disclosures over their compact source. Region and
  CollapsibleView share an optional automatic dismissal affordance; the HUD
  task disclosure uses outside taps for pointer/touch and reveals Collapse for
  keyboard/gamepad navigation. The always-visible corner close remains available.

- Repair Showcase interaction routes: focused context-menu chords and a true
  right-click example, Match 3 neighbor dragging through public drag/drop,
  a standalone HUD, Corner commands with Slim band defaults, and clearer
  pending-save/rollback instructions in Settings sync.
- Keep adaptive Picker row separators on the live axis so TV selections cannot
  overlap the next setting. Theme adaptable TabView bands with control corners;
  preserve per-corner focus shapes and square skin highlights.
- Use one compositing buffer for expanded CollapsibleView content. Keyboard
  arrows now share held-navigation repeat with D-pad and thumbstick input.

- Hide the initial focus ring in mouse/touch sessions while retaining entry
  focus. Controller sessions show it immediately; navigation restores it after
  a pointer interaction.

- Keep aspect-sized children at their measured size in stretching stacks, fixing
  the oversized circular action that overlapped the Showcase sidebar. Move the
  demo layout action into the existing Showcase toolbar as a labeled Button.

- Add Picker `valueAlignment` (`start` or `end`) for labeled menu rows. Showcase
  display settings use start alignment to keep values close to their labels;
  trailing alignment remains the default for other forms.
- Remove TabView's built-in sidebar toggle. Add the bindable `sidebarPreference`
  API for nearby layouts; the Showcase supplies its demo toggle in its toolbar.

- Add Showcase display previews for Automatic, Desktop, Phone, Tablet and TV,
  with orientation and independent input selection. The reusable
  `client.environment_preview` binding retains live platform facts for restoration
  and updates mounted screens through the existing layout and focus system.

- Use adaptable outer navigation in All controls, Collections, and Motion and
  layout, with ordinary nested page tabs. Clarify that navigation role, rather
  than the screen being a game or demo, determines the TabView style.
- Reflow scrollable content when switching input changes scrollbar reservation,
  including pages whose content and viewport have not changed.
- Bound Alert's animated CanvasGroup to the card and its margin instead of the
  full viewport, reducing desktop text rasterization blur while preserving motion.
- Consolidate the Showcase picker from 46 entries to nine. All controls uses nested
  tabs for inputs, actions, indicators and navigation; Collections and Motion and
  layout combine focused comparisons. Playlist, settings and three games remain
  standalone. Individual regression scenarios remain available by workspace attribute.

- Compact menu submenus slide forward and back through the shared navigation motion. Switches paint their initial value immediately, slide without overshoot on changes, and keep label size steady when pressed.

- PageView now advances at most one page per mouse/touch swipe, settles on release, and preserves direct dot jumps and child input priority.
- Fix pixelated text in expanded disclosure groups, including the UI laboratory menu. The shared `reveal` transition animates a native clipping frame instead of rasterizing the entire list in a CanvasGroup; caret timing, focus restoration and reversal remain intact.

- Horizontal scroll hosts support desktop mouse dragging after child controls get first refusal. Ordinary clicks remain clicks, text editing and claimed drags keep ownership, and snapping waits until mouse release. PageView hides its horizontal scrollbar when page dots are shown.
- CollapsibleView transforms its plate from the compact button's current screen rectangle, with separate content fading and no text scaling or overshoot. Race settings now has one collapse action. CanvasGroup surface paint follows the stylesheet instead of forcing a transparent backdrop.

- Reuse reactive propagation work lists between completed rounds, reducing allocation
  during repeated signal updates while preserving observer order, transaction reads,
  feedback handling and isolation between cores.

- Gallery fallback cleanup releases parent controls before child scopes, preventing duplicate-disposal errors when switching demos.

- Added `Controls.CollapsibleView`: arbitrary content expands from a static or bound summary button, with modal focus, safe-area placement, scrolling and grow/shrink motion. `TabView.style = "collapsible"` supplies the selected-destination version. NavigationStack retains its Back hierarchy.

- Add `Controls.Sheet`: owner-held detents, bottom entry and dismissal, a header
  grip, focus-based sizing, and centered distant-screen presentation. Content pans
  remain scrolling; the header owns resizing. Add `Controls.PageView`: finite
  pages, dots, native snapping, and focus that follows the visible page. These
  controls reuse the shared presentation, input, scrolling and motion systems.
- A fixed-height container now bounds descendant measurement inside an outer
  vertical scroller, so nested page viewports receive their actual height.

- **A modal centres on the whole screen; content still yields the host's own
  chrome (2026-09-13).** `coreSafeInsets` carried two meanings — the device safe
  area AND any band the HOST app reserved for chrome of its own, because inflating
  it was the only vocabulary a host had. The showcase folded its demo/settings chip
  strip in there, so every alert it raised centred in the space UNDER the strip,
  visibly high-shouldered against a backdrop covering the whole window. The fact is
  split: `coreSafeInsets` means the device safe area again, and **`appChromeInsets`**
  is the host's own four-edge reservation (zero by default, the sibling of
  `appChromeRects` — that one says where the chrome IS, this one says how much
  content must clear). The content root policies add the two; `presentModal` and
  `presentCritical` reserve the device's edges alone (`renderer.attach`'s new
  `reserveAppChrome`, default true), and `bandSafeContent` still consumes the app's
  chrome per column through `platformChrome.rects`. Anything a surface RAISES —
  an anchored popover (a picker panel, a Menu, an expanded region), a disclosure
  or help plate, the room a field measures for the soft keyboard — belongs to the
  surface that raised it and takes ITS answer, so a popover over a content page
  keeps the band and one inside a modal does not. **Nothing moves for a
  consumer that never sets the new fact** — Rascal Rally's `coreSafeInsets` was
  always device-only, and its role-pick modal's centre is pinned unchanged.

- **A modal's action label is never cut before the form changes (2026-09-13).**
  `Controls.Alert`'s row/stack decision was categorical only — a width class, a
  viewing distance, a text preference — and every rung was a proxy for the question
  that decides whether a label gets cut. The labels now get a vote: the control
  measures each at the size and face a Button will draw it, adds the button's
  chrome and the row's gap, and stacks when the sum does not fit the card
  (`alert.rowFits` is the pure rung, exported beside `resolveStacked`). Measured, a
  1280 desktop row asked for 802 px of a 528 px card and ran outside it. The card
  also stops paying twice for its own frame: its `padding` yields to the panel
  slot's carved inset (down to one `xs`, never to nothing) and it declares
  nothing about its chrome lane at all: the bleed a scroller keeps for content
  that paints past its box is NETTED against the slot's carved frame at the layout
  reader (`chrome_slots.bleedLane`, read per solve, so a theme swapped under a live
  modal moves the lane with it), because that carved
  frame is the lane a scroller reserves for content chrome — 288 px of content on a
  390 px phone under Fantasy Parchment becomes 322, which is what lets "Continue"
  draw whole at the Largest preference. The primary action also stretches in the
  stacked form again: a `shortcut`-bearing action inherited `Controls.Button`'s own
  `align = "center"`, and the stack's `align = "stretch"` passed it by. `disclose`
  stays underneath all of it as the last resort it was meant to be.

- **A content-sized `ScrollView` reserves BOTH chrome-bleed edges, so the Alert
  card grows instead of scrolling (2026-09-13).** The scroll canvas is
  `contentSize + padding + lane`, where the lane is the trailing allowance that
  makes the last child's shadow reachable — the package's `chromeBleed` netted
  against the slot's own carved frame, per the entry above — while a hugging
  scroller's measure counted only the leading edge of that two-edge reservation.
  A box measured one edge short of the canvas it then publishes can never fit
  inside itself, so the Alert card overflowed by exactly the lane and showed a
  scrollbar forever: measured before the netting landed in this same release, 17 px
  under Fantasy Parchment, Fantasy Ornate and Glossy Touch and 24 px under Sci-Fi
  HUD, on a 390×844 phone with 400 px of room behind the card. A card wearing a
  carved panel frame now nets that lane away entirely (Fantasy Parchment carves 18
  under a 17 px reach), so what the reservation is still worth is the uncarved
  packages. A definite-extent scroller is untouched.

- **The Alert's severity mark is punctuation, and its title is centred
  (2026-09-13).** The critical caution mark (and an authored `icon`) was
  `targetSizes.minimum` — 44 px, the *hit floor* — beside a 20 px heading, so it
  was more than twice the height of the line it qualifies. Its default is now
  `iconSizes.medium` capped at the heading it leads — the type-height rung the rest
  of the library already spends, with the cap because a package may pitch its
  picture ladder above its type (Fantasy Ornate's `medium` is 32 against a 22 px
  heading) — and `controls.alert.iconStroke` follows the mark (a tenth of the box, floored at
  the package's hairline) instead of a spacing step. With no mark the title's text
  is centred in the card, as the message under it always was; with a mark the pair
  is centred **as a unit** and the title reads from the mark, instead of a `fill`
  title centring its line in whatever width the icon left over. A package that
  authors `controls.alert.iconSize` still wins.

- **The ten-foot overscan is a fraction of the display, not 1080p pixels
  (2026-09-13).** `effectiveOverscanInsets` derived the console profile's
  60/60/90/90 as literals, so it reserved the same absolute band from any
  viewport — 5.6%/4.7% of a television and 31%/22% of an 801×392 Studio window,
  where an alert's card resolved to 577×73 around 269 px of content. It is now
  that same profile expressed as the proportion it is (`60/1080` of the height,
  `90/1920` of the width, whole pixels). At 1920×1080 the answer is byte-identical
  to what shipped; an authored `overscanInsets` and the `"none"` opt-out are
  unchanged.

- **A materialize may declare the scale it starts from, and `Controls.Alert`
  settles DOWN into place (2026-09-13).** `transition.scale` joins `distance` as
  the scaling form's own opt-in override. It exists because of a measured engine
  fact: Roblox rasterizes text at `floor(TextSize × effectiveScale)`, so any
  `UIScale` below 1 paints every string under it one whole pixel smaller for the
  entire flight — 0.9999999 renders exactly as 0.96 does — and snaps ~5% larger
  the moment the scale reaches 1, which is when the spring settles and the
  channel finally drops the `UIScale`. On the Alert that read as the card's title
  re-flowing a quarter of a second after the card had stopped moving. The modal's
  default is now `{ enter = "materialize", plate = "fades", scale = 1.015 }`: the
  band `[1, 1 + 1/66)` floors to the same pixel for every text size the framework
  can paint, so the type lands at its final rect on the first painted frame. It is
  the **enter's** band only — an exit is the opposite instant, so it still dips out
  to the ratified `0.96` — and every other caller keeps that `0.96` both ways.

- **Transitions round (2026-09-12, informed by a transitions.dev survey).**
  Structural exits default to the new `dismiss` motion class (`exitClass` opts a
  caller into its own); `Controls.Alert` and `Controls.Menu` materialize on open
  (`AlertSpec.transition`, including `transition = false`); `transition.plate`
  acknowledges a modal/popover's fading backdrop; a keyed `ForEach`'s rows can
  arrive on a `stagger` beat; `Controls.TextInput` gains `invalid`, a caller-
  driven shake; `Controls.Button` gains opt-in `pop`; `RadialMenu` wedges bloom,
  the candidate lifts, and a commit pops; `Controls.DisclosureGroup`'s caret
  turns and its content slides in behind an optional `presenter` glide (its old
  `chevron.down` art slot is no longer requested); the `Toggle` knob settles
  with a Back overshoot; the ten-foot focus lift tweens between controls instead
  of snapping; and a `Picker`/`TabView` selection fill can wear its own strip's
  `stripCorner`. `presenter.surfaceIdNotes()` diagnoses two live surfaces under
  one id. New perf scene `control-motion` and gate `tests/motion_paint_only.spec.luau`
  price and prove every motion above stays on the paint-only presentation
  channel. Each is its own row below; this one just points at them.
- `Controls.DisclosureGroup`'s caret is one `chevron.trailing` glyph now, not a
  mounted/unmounted `chevron.down`/`chevron.trailing` pair: its paint-only
  `rotation` springs 0 → 90 as `expanded` flips, turning to point down instead of
  swapping identity. A package's `chevron.down` art, if it declared any, is no
  longer requested by this control. Content still mounts through `UI.When`, now
  with `{ enter = "slide-up", distance = 12 }`; its exit rides the structural
  default (`dismiss`) rather than declaring its own, so reopening mid-exit
  reverses through the same travel instead of jumping across it. `DisclosureGroupSpec`
  gains an optional `presenter`: when given, the toggle runs inside
  `presenter.withAnimation("container", …)` so a sibling whose position the flip
  moves — a section below sliding to make or close room — glides there instead of
  jumping; absent (the common case), the flip is instant and only the caret/content
  animate their own paint, off the ambient motion clock every mounted control
  already receives.
- Structural exits are faster than the entrances they mirror. A new built-in
  spring class `dismiss` (ζ1.0, 0.2 s) is what every exit runs on unless a
  `transition` names its own `exitClass`, so a `When`, a `ForEach` row, a toast
  and a dismissed surface all dip out at about 1.7x the pace they came in —
  transitions.dev's 250/150 ms pairing, and the one deliberately visible change
  of the round. The exit's settle tolerance is coarser than the enter's
  (`EXIT_EPS`, 2% of the transition's own progress, which is 2% alpha or 0.48 px
  of the themed 24 px slide): an exit that is visually absent should stop
  existing, and at the enter's tolerance a `dismiss` exit disposed on the flat
  500 ms cap — the same frame `container` did — rather than on its own spring.
  The bound is now "at most 2% of the travel remains, or the 500 ms cap,
  whichever comes first"; frames to dispose at 60 fps went `dismiss` 30 → 22 and
  `object` 31 → 28, while `container` and `decay` genuinely outrun the cap and
  still end on it. An ENTER keeps the default tolerance, because its settle is
  what fires the `arrive` feedback event.
- `Controls.Alert` and `Controls.Menu` materialize. A modal card and a floating
  menu popover scale 0.96 → 1 with a fade on the `container` class and dip out on
  `dismiss`; `AlertSpec` gains `transition?` so a caller can override it or pass
  `{ enter = "instant" }` to opt out, and `transition = false` is accepted as the
  framework's own "no transition" spelling (it folds to the default, which is
  what the present site already did with it). An invalid transition is refused
  where it can be seen: a static one at BUILD, named `Controls.Alert: transition:
  …` rather than the coordinator's own message, and a Readable one on its first
  read, where the refusal is recorded on `dump().lastError` and resets the
  binding instead of raising inside the observer that opened it.
- `transition.plate = "fades"` acknowledges the modal/popover shape. The
  backdrop-before-content gate reports a fade group that composes its own opaque
  plate, because `GroupTransparency` dims the backdrop and the content together
  — and an Alert's card or a Menu's popover is structurally identical to that
  defect while being exactly what a modal should look like, its backdrop being
  the scrim behind the whole surface rather than the card's own face. No tree
  read can separate the two, so the surface declares it. Honoured only for a
  fade group whose SOLE child is the plate: a plate with a sibling still reports,
  and an acknowledged shape is still recorded (under its own kind) so a reader
  can see which surfaces made the claim. `Controls.Alert`, `Controls.Menu` and
  the menu-style `Picker` declare it; nothing else needs to.
- The modal card wears the `panel` decoration slot. `Alert`'s card is a
  `UI.ScrollView` so a long message stays reachable, and `chrome_slots.classify`
  answers by CLASS before it reads `surface` — so under every skinned package the
  card classified as a scroll TRACK and got no carved frame, hairline, shadow or
  contentInsets. An unhinted `ScrollView` is still a scrollbar, which is right
  for every other one. An alert ACTION now declares `disclose` with it: a carved
  frame spends contentInsets, and a one-word label that no longer fits has
  nothing to wrap at, so it keeps a route to its whole string.
- `presenter.surfaceIdNotes()` reports two surfaces presented under one id. Every
  node path is rooted at the blueprint id, so the second surface silently takes
  over the first's paths in the adapter and the first can no longer be torn down
  by path. A diagnostic, not a refusal, once per id per session.
- `When`/`ForEach` transitions gain `stagger` (a nonnegative number of
  **seconds**, enter only): the beat between one entering row and the next, so
  a list that lands as one slab reads as a redraw instead. It is inert outside
  a keyed `ForEach` — a lone `When` branch is always the first (and only) row of
  its own batch and waits for nothing. The accumulated wait caps at eight beats,
  not the number of timers running: every row past the eighth still books its
  own hold, the rows past the cap simply all book the same duration, so a
  600-row list's last row enters with its ninth rather than half a minute
  later. Exits never stagger, a re-entry mid-exit reverses immediately, and
  reduced motion lands every row on the first frame. A ms/seconds mixup such as
  `stagger = 500` is not clamped or warned about — it holds a row absent for
  minutes.
- `Controls.TextInput` gains `invalid`: an optional caller-owned readable
  boolean whose false→true edge shakes the field once — four legs on the
  paint-only `offset` (±8px at 0/80/140/200/240ms) that never move the solved
  rect, hit target or focus order. A numeric-presentation rejection shares the
  same shake but fires on every rejected commit rather than an edge, because a
  repeat of the same rejection is exactly when the nudge is worth the most.
  Reduced motion drops the shake on both paths; the validation message is the
  only account of *why* and is unaffected.
- `Controls.Button` gains opt-in `pop`: an activate seeds velocity into a
  `reward` spring on the button's paint-only `scale`, kicking past 1 and
  springing back rather than easing to a target — the same acknowledgement
  `RadialMenu`'s commit uses, on a plain button. Fires on the initial press
  only; a pointer-held repeating button's later repeat pulses do not re-kick
  it, though keyboard/gamepad activation still pops once, on the press that
  starts the hold. Reduced motion holds the scale at exactly 1.
- `RadialMenu`: an opening ring blooms as a sequence rather than a slab (each
  wedge waits 20ms longer than the one before it, capped at 100ms total
  regardless of how many wedges the ring holds); the candidate wedge — under
  the pointer, the stick, or a direct hover — lifts 4% out of the ring; and
  committing it seeds an overshoot into that same lift so the acknowledgement
  continues the motion instead of starting a new one. Both are paint-only.
  Reduced motion opens the ring whole, keeps the candidate lifted, and drops
  the commit overshoot.
- The `Toggle` knob's settle tween switches from `Quad`/`Out` to `Back`/`Out`
  (transitions.dev's `(.34,1.35,.64,1)` shape): it overshoots by about 10% and
  returns, the way a physical switch thumb settles. The track's colour tween is
  unaffected — a colour never overshoots. Both tweens are now held and
  cancelled the same way (`handle.toggleKnobTween` beside `toggleTrackTween`),
  so a flip-flip inside 0.2s can no longer leave a stale tween racing a fresh
  one into a recycled control.
- The ten-foot focus lift (the 1.05 paint-only scale a pad/keyboard focus
  change applies) now tweens between controls instead of snapping: moving
  focus across a row used to snap each control to 1.05 and the previous one
  back to 1 on the same frame. One tween per focus change, cancelled by the
  next; the floating focus ring travels along the same tween rather than
  arriving at its destination size ahead of the lift. Reduced motion keeps the
  instant write.
- New perf scene `control-motion` (`UI-PERF-001`) prices a 30-row staggered
  `ForEach` enter, a `DisclosureGroup`, `TextInput.invalid` and `Button.pop`
  overlapping in one frame, off a scripted clock so the sample measures work
  rather than wall-clock luck. New gate `tests/motion_paint_only.spec.luau`
  proves every motion this round added — the shake, the pop, the caret turn,
  the radial lift/commit and the stagger — writes only to the paint channel,
  never the solver, and that idle after a motion settles costs nothing: zero
  clock steps, writes, transactions and rect writes for sixty more frames.

- Fixed: a count badge's number sat off-centre in its seal. Two rules make the
  plate bigger than the glyph — the intrinsic `controls.badge.minimum` on both
  axes and the row recipe's `xs` a side — and while the plate and the number were
  ONE `UI.Text`, where the number sat came from the adapter's per-class text
  defaults (`TextXAlignment.Left`, 2.5px off centre on a 20px circle in Facet
  Neutral) rather than from the control. The seal is a plate with a `Count` glyph
  inside it now, centred on both axes by the control, which also makes the claim
  measurable: a mounted badge exposes `<row>/Badge/Count` beside `<row>/Badge`.
  New gate: `tests/badge_centering.spec.luau`.
- A selection highlight wears the silhouette of the strip that holds it.
  `radii.selection:<container>` is the new token form — an authored
  `radii.selection` wins over every container, a `pill` container gives a pill by
  the pill rule, and anything else is the container's radius less one `space.xs`,
  the inset the fill floats by. A segmented picker's fill therefore sits
  concentric inside its own `radii.control` track, and a `TabView`'s adaptable
  app bar in its BAND form — a `radii.pill` capsule that previously held a
  `radii.selection` rounded rect (999 against 4 under Compact Pointer) — now
  holds a capsule. Its SIDEBAR RAIL names no container and its rows keep plain
  `radii.selection`, because a selected row sits in the middle of a column rather
  than concentric with the rail's outer corner. `newPicker` gains an optional
  `stripCorner` for a caller that suppressed the picker's own track; it refuses a
  name outside the container vocabulary and refuses to sit on a tracked strip.
  The vocabulary is the LIVE style's: a package that authors a radius of its own
  (`radii.chip`) may be named, because `radii.selection:chip` resolves under it,
  and a package may only ADD to the base names, never narrow them. An authored
  `radii.selection` no longer makes every spelling resolvable — the container has
  to exist before any clause answers for it. If the live style stops publishing
  the container — a theme swapped away from the package that declares it, or a
  READABLE `stripCorner` set to a name that never resolves — the fill falls back
  to plain `radii.selection` rather than losing its corner, says so once per
  token per control WHILE it is falling back — a swap back clears it, and a
  second departure warns again; a reactive `stripCorner` alternating between two
  unresolvable names warns on every change (the cost of a present-tense count) —
  and reports it on `dump().indicator.cornerFallbacks`, which counts what is
  falling back RIGHT NOW: it returns to zero when the package comes back, and
  stays at one for a name that never resolves. A static `stripCorner` is
  resolved once at build (through the same fallback, once) and never re-derives,
  so a later swap-away leaves it on the token it took and neither the counter
  nor the fallback moves again.
  The bar's own corner is unchanged, and so is what plain `radii.selection`
  means, so a menu card's chosen-row shade reads it exactly as before. New gate:
  `tests/selection_shape_container.spec.luau`.
- Fixed: a `TabView`'s strip touched its page at every placement but the sidebar.
  The root stack spent the theme's `m` step beside a rail and nothing at all
  above or below a band, so a strip — a plate with its own fill and corner — ran
  straight into the content under it in every theme. A placement with room for a
  gap owns a theme-sized one now (`m` beside a rail, `s` above or below a band),
  spent as a metric name so a package's spacing and a ten-foot display's scale
  both reach it; `bottomBarCompact` — the placement the policy picks when the
  screen is too short for an ordinary band — spends none, because the chrome
  gives way before the content does. New gate: `tests/tab_strip_gap.spec.luau`.
- Fixed: a `UI.Divider` painted the theme's hairline COLOUR at full opacity while
  every stroke in the sheet painted the same token at `hairlineOpacity` — so a
  segmented picker's seam, a menu's row rule and any list separator were a solid
  bar of a colour meant to be washed (Facet Neutral's hairline is pure white).
  Both paint paths spend the theme's own `hairlineOpacity` now, so every package
  inherits a subtle seam and one authored number still moves strokes and dividers
  together. The background-transparency preference does not patch it — a divider
  is a border. New gate: `tests/divider_hairline.spec.luau`.
- Fixed: the swipe-actions gallery example's List surface had lost the plate
  behind its rows in every theme. `6a65baef` made a declared surface outrank the
  class map, and these rows had been drawing their plate out of exactly that
  accident while declaring `base` — the app background, which is also what the
  screen behind them declares. The plate is a node of its own now (`ListPlate`, a
  stack that fills the band and holds the scroller), so one `panel` recipe frames
  the pane a player looks at and carries the shadow, and every row's own fill
  reads against it; the row's sender line fills and truncates, so the panel's
  carved border comes out of the name rather than out of the box. The card gives
  way only when the band MEASURES too small for the package's own carved frame
  plus one tappable row — a package that carves nothing (Facet Neutral among
  them) therefore never loses its plate at any size, and a theme swapped in place
  re-measures rather than answering with the previous package's band. It cannot live on the
  ScrollView itself — `chrome_slots.classify` answers for a ScrollView's own chrome (its
  SCROLLBAR) before it reads the declared surface — so the gate pins the SLOT
  beside the surface name. New gate: `tests/row_plate_paint.spec.luau`.
- Segmented picker, shape round (2026-09-12, user visual review). The strip is
  ONE strip: only its outer ends round, with the theme's `radii.control` rather
  than a hard-coded pill; the inner segments are square and touch, with a
  hairline seam between each pair (hidden beside the selection, because the
  sliding fill paints behind the strip); the fill wears the silhouette of the
  segment it is on; and the track plate takes the same outer radius. The same
  rule turned 90 degrees is the vertical rail's. `selection_indicator` gains
  `segmentCorners`, and its default corner is now `radii.control` — Pixel Quest
  draws a 4px selection and Fantasy Ornate a 6px one where both drew a capsule.
  `corner = "pill"` remains the caller's opt-in. A `TabView` strip
  (`track = false`) keeps its own spacing and gains only the theme radius.
- A ten-foot row list gives every row one silhouette, chosen or not, and lifts
  the FOCUSED row by a paint-only 1.05 on the presenter's spring (reduced motion
  places it on the frame it arrives). The solver, the hit target and the focus
  order do not move, and the rows' own gap is wider than the lift.
- `newLevelPicker`'s `bar` segment plates a track and rounds only the run's two
  ends, the same language the segmented picker speaks. `newRating` (glyph) is
  unchanged.
- Fixed: a segmented strip's segments were the same height only while their
  labels agreed about truncating — at the Largest preference under Fantasy
  Ornate one reserved its disclosure plate and the other did not, solving 108px
  beside 66px. The option stack stretches its children on the cross axis now.
- `Controls.Menu`'s anchored panel is now one card: flat `plain` rows with no
  radius of their own, one hairline between adjacent rows, and a selection fill
  that is the row's own surface, clipped to the card's radius at its two ends.
- A selected menu row's label is now painted for the fill it sits on
  (`accent`/`onAccent`). It previously kept `$Content`, which read at 2.37:1 on
  Glossy Touch and 2.46:1 on Pixel Quest. New gate:
  `tests/selection_contrast.spec.luau`.
- `Controls.SplitButton`'s touch form shows a trailing `chevron.down` hint, so
  the long-press menu is discoverable. Still one hit target, one focus stop,
  one activation.
- A control's content line is centred: an icon beside a word in a `UI.Button` no
  longer rides the top of the line under a package whose icon rung is taller
  than its control type (Pixel Quest 6px, Fantasy Ornate 4.5, Glossy Touch and
  Classic Desktop 2.5).
- A closed picker trigger paints its package's `control` plate instead of the
  row-selection wash. It declares `selected` so its open state can light up, and
  the slot classifier read that declaration as a state.
- A picker popover grows to fit its widest row's full label, measured through
  `text_metrics` and counting the card's frame, the scroller's shadow reserve
  and the row's real padding. Pixel Quest asked for 182px where 280 was needed,
  leaving 78px for a 176px word.
- `UI.ScrollView` accepts `chromeReserve` (`"auto"` default, `"none"`): the
  lane a scroller keeps for content chrome that reaches past its box —
  `max(0, chromeBleed − the slot's own carve)` since 2026-09-13
  (`chrome_slots.bleedLane`), because a carved frame already holds content that
  far from the clip edge. The
  picker popover's list declares `"none"` — its rows are plain and its check
  draws inside its box — so the list runs to the card's content box and the
  chosen row's fill spans the card less one `xs` a side with the theme's
  control radius (Glossy Touch had it floating 31px inside the card), and
  two rows that fit no longer show a scrollbar (the region's content grew by
  two lanes while the host grew by one). Pinned in `picker_sweep`.
- `radii.selection` (theme metrics): the highlight shape — the segmented
  picker's sliding fill, now an inset rounded rect on all four corners floating
  inside a track that keeps `radii.control` on its ends, and a menu card's
  chosen-row shade plus the focus ring on that row, clipped to the row's place
  (first row rounds its top, last its bottom, middle rows square, an only row
  all four). It follows `radii.control` unless a package authors it; Pixel
  Quest and Fantasy Ornate set `0` in their own metrics. Documented in
  `docs/guide/09-custom-themes.md`, `05-styling.md` and `api.md` themes.
- `controls.popup.shadeInset` (theme metrics, optional, default 0) picks the
  menu card's row-shade form: flush (edge to edge, clipped to the row's place)
  or, for a positive inset, floating (that far inside the card's edges, all four
  corners on `radii.selection`, the row under it inset the same so the focus
  ring matches). Glossy Touch authors `selection = 10` and `shadeInset = 4`.
- The picker card keeps no padding of its own (Glossy Touch stacked it on the
  frame's insets); rows run to the card's content box.
- `menu_recipe.row` accepts a Readable `indicatorEdge`; the picker popover
  passes one, so the check follows the live interaction class instead of the
  class at build time.
- The chosen row in a picker popover paints its label with the theme's
  `onSelected` partner (Glossy Touch 2.37:1 → 7.03:1, Pixel Quest 2.46:1 →
  6.04:1). `onSelected` is a new tint role: the decision `$OnSelected` already
  carried, reachable by a child `UI.Text` that no `TextButton`-scoped sheet rule
  can descend into.
- Gallery: the selection and action demos caption every control ("Picker ·
  segmented", "Split button", …) so a capture names what it shows.

- Picker menu, third visual round (2026-09-12, user review of the side-by-side
  against the reference platform). The popover is ONE card: the panel owns the
  corner and the stroke, the rows are plain with a hairline between them, the
  chosen row carries a subtle `controlSelected` fill, and the check sits at the
  row's trailing edge on a touch surface (leading on a pointer or pad). The
  touch form row is one row — title and value + chevron on one line, value and
  chevron flush trailing, no box, the whole row the tap target; a pointer or a
  pad keeps the boxed pop-up button beside the title, centred on its line. The
  chevron is centred on the value's line everywhere, and the picker sweep pins
  both centres to a pixel. `menu_recipe.row` gains `indicatorEdge`.

- `UI.Button` accepts `disclose` (construction-only), the same full-value
  path a one-line `Text` or a Toggle label carries: a squeezed label reaches its
  whole string through the large-text plate. Every segment of a sliding picker
  strip declares it, which closes the LT-G4 gap the large-text sweeps recorded
  (an option label with no route to the whole string); a TabView's tab strip
  declines it (`track = false`) because the bar's own compact ladder owns
  overflow there.

- **Icons: no shipped theme paints a character where a picture belongs.** The
  radio and checkbox indicators, the pop-up button's chevron pair and the tick
  now resolve to real art in every shipped package. Facet's own icon set gained
  the three selection marks; Pixel Quest gained the eight names it was missing,
  which is what licenses it to keep declining the framework set; Glossy Touch and
  Compact Pointer no longer decline it. `tests/icon_coverage.spec.luau` fails a
  package that leaves any control-requested name on the ASCII floor, which stays
  an engine recovery path. `tools/upload_icons.py --theme` uploads a theme
  package's own art headlessly.
- Picker visual round (2026-09-11). The segmented style is one plated track
  (the `control` surface every package skins) holding equal pill segments with
  the bar sliding beneath them; a segment carries a label only — a described
  option is refused on a declared segmented picker and steers the automatic
  ladder to a row form; the ladder also estimates the band from facts (glyph
  count x the text size the preference and the ten-foot scale make, plus the
  theme's padding) against the control's own measured offer and falls to
  inline/menu when a pill would not fit. The menu popover hugs its widest row
  between the trigger's width and the safe width, hangs from the visible
  trailing edge (a plain touch trigger's chevron) with an `xs` gap, keeps the
  screen's content inset, grows out of the corner it hangs at, and the trigger
  stays selected while it is open. `presentAnchored` gains `anchor.margin`; a
  transition gains `pivot`; Menu popovers take the same gap and margin. The
  overflow sweep now runs the largest text preference at the widest viewport
  under every shipped package as well as at the narrowest.

- Performance: a scale-only presentation transform write (every frame of a
  `materialize` transition, every animated scale) re-applies the written node
  only; the subtree is walked only when the offset half moved. Headless, the
  picker menu open/close scene halves (3.1 -> 1.4 ms) and the radial menu
  open/close drops 14%. `tests/presentation_transform_subtree.spec.luau` pins
  the rule in both adapters.
- Performance lab: a nineteenth workload, `transient-surfaces` (alert present,
  picker menu open, radial menu open), with fixtures shared by the headless
  scenes `alert-present-dismiss`, `picker-menu-open-close`,
  `picker-segmented-textsize` and `radial-menu-open-close`. Seven trend budgets
  tightened after earlier improvements; none loosened.
- Picker gains `style` — `automatic` (default), `menu`, `segmented`, `inline`,
  `radioGroup`, `navigationLink` — the reference platform's picker styles over
  one selection model. The automatic style resolves from published facts: a
  nearby touch or pointer surface gets the menu family (one integrated trigger
  carrying the value and an up/down chevron, the options anchored to it with a
  materialize transition, the current value focused and check-marked, no Cancel
  row; a titled picker is a form row that stacks at accessibility text sizes;
  a gamepad or a long list on a compact or touch surface presents a sheet); a
  ten-foot display gets a focus-navigable strip; a nearby gamepad keeps a short
  strip and folds a long list, or any list on a compact screen, into the menu.
  A searchable list (`query`) is the navigation link. `presentation` is the
  deprecated spelling of `style` (`radio` reads as `radioGroup`), declared in
  `DEPRECATIONS`; `Picker.resolveStyle(facts)` is the pure ladder.
- `Controls.PopupButton` / `newPopupButton` are deprecated (removal no earlier
  than 0.12.0): the popup engine moved to `src/controls/picker_menu.luau` and
  both names build on it. Migrate a value to a `Picker` menu style, a searchable
  list to `navigationLink` with `query`, and a `selectedValues` set to a `Menu`
  with `checked` items.
- SplitButton is one button with a long-press menu under touch and a joined
  edge-to-edge split under a pointer or gamepad; the forms follow the live
  interaction class. `dump().form` reports which is on screen.
- New framework icon `chevron.up.chevron.down` (the pop-up button's stacked
  pair), generated and uploaded with the standard set; the menu row recipe
  gains the check-only `mark` indicator.
- Showcase: Choices and filters is built on the Picker's styles (radio group,
  segmented, the automatic form-row menu, a searchable navigation link) and a
  checked `Menu` for filters; the section switch and the Actions and menus idiom
  switch declare `segmented`. The Cartwheel reference app's sort, axis and
  ingredient popups are Pickers.
- Alert actions follow the platform alert rules instead of author order: the
  cancel action leads a row and closes a stack; a stack (full-width buttons) is
  used with more than two actions, on compact widths, on ten-foot displays and at
  accessibility text sizes. The action region is one keyed `AdaptiveStack`, so a
  live width/distance/text flip moves the mounted buttons rather than remounting
  them. Alert accepts `env` like the other adaptive controls. Action paths are now
  `…/Card/Actions/Order/[<id>]/<id>`.
- Directional search inside inferred layout groups shares the section scorer
  (one beam/distance rule, not two copies).

- A node that declares a surface is no longer given a theme package's control
  decoration by its class. A `Button` or `Toggle` declaring `surface = "base"`
  or `"scrim"` fell through to the class map and was skinned as a control —
  plate, corner and, under a package with depth, the control slot's shadow,
  which reaches outside the node and painted onto whatever sat next to it. Every
  other declared surface already decided the slot; the class map now answers
  only for a node that declared none. A node carrying a `selected` prop still
  reaches the selection slot whatever surface it declared.
- A virtualized list or grid's full-bleed row hit target no longer takes a
  control surface when it paints no selection. It carried no label, no icon and
  no image, yet wore the installed theme package's control plate, corner,
  gradient and shadow — and since rows sit back to back, that shadow painted as
  far into the neighbouring rows as the package's `chromeBleed` reaches. A list
  that paints selection keeps the surface its selected row is drawn with, so
  selection treatment is unchanged.
- Add Controls.Alert for content-sized confirmations, adaptive action rows,
  presentation/data/error bindings, safe cancel focus, icons, severity and an
  optional suppression choice. Showcase confirmations and Delete Save use it.
- Adaptable tabs retain a complete TV tab strip across destination changes and
  use a shared sidebar/body gap. Distant viewing changes navigation placement
  even with mouse input; Actions and menus reflows its content sections.
- Measure capped hugging containers at their declared width limit so wrapped
  text contributes its full height before actions are placed. Hugging scroll
  containers also reserve the leading space their themed shadows require.
- Match integer fill allocation during measurement and arrangement, preventing
  aspect images from exceeding their measured columns by a pixel.
- Let pointer zones inside native scrolling containers pass touch scrolling
  through while retaining horizontal swipe gestures and their normal input capture.
- Release completed press-only scale modifiers so native themed shadows return
  after taps, including the first row after changing List and VList modes.
- Release unread-marker bindings when Row Actions List and VList rows unmount.
- Keep the virtualized table toolbar scrollable on narrow phones with large
  text; remove its resolved themed-overflow waiver.
- Remove the forced line break in the Journey details “Travel light” heading.

- Framed image geometry commits no longer reread or rewrite unchanged native
  paint. Origin-only moves preserve the crop, while source, theme and modifier
  changes retain their existing synchronization. Performance Lab now includes
  the same 24-image adaptive navigation inventory used by the headless bench.

- Keep adaptable navigation controls and their ScrollView mounted across nearby
  top/sidebar changes. ScrollView axis now accepts a readable value and updates
  directional navigation and active named travel without restoring cancelled focus.
  Scan presentation-path separators directly instead of visiting each character.

- Navigation performance: rendering and input share a live path lookup that skips
  unrelated subtrees. Buttons without a possible busy state omit progress regions
  and their reactive state; declared busy buttons retain their spinner behavior.
  The one-time input binding registry no longer strongly retains retired control
  bundles, while reusable blueprints keep their once-only binding behavior.

- Adaptive follow-up: explicit scroll-to-focus arrival and removed-target visibility exits;
  opt-in content shoulder paging, bounded value hold-repeat, and layered Table edit Back.
  Navigation flow now demonstrates adaptive search with query/focus restoration.
  Theme navigation chrome keeps ornate capsules light. Completed partial feedback
  no longer causes a redundant next-refresh layout pass. Agent guidance applies
  the Facet-first implementation order to layouts and controls.

- Narrow nonstructural geometry feedback to its changed subtree, preserving full-layout fallbacks. Cache selection-indicator geometry by structural/layout changes, pair reordered identities with their measured rectangles, and remove image-button focus polling from idle refreshes. Sidebar commands retain focus when the effective navigation placement does not change.

- Fit radial label height as well as width inside thin rings; measure compact icons against their actual padding so ten-foot action and navigation artwork remains usable.

- `UI.Image.imageFraming` adds source focal-point crop, fit, stretch, unscaled
  pixels and an explicit scale multiplier through the existing image/background
  path. Reactive framing is paint-only. Game-authoring guidance now calls for
  game-specific themes, real icon artwork and deliberate background framing.

- Add opt-in `TabView.style = "sidebarAdaptable"`: tablet toggle, pointer sidebar, distant-screen collapsed destination pill, and stable page identity when navigation moves.
- Picker/TabView badges reuse measured, wrapping row content so image-backed counts do not cover labels; `onAccent` tint keeps custom selected labels paired with the theme palette.
- Extend existing `Controls.Button` with image, aspect ratio, and subtitle content; reserve padded focus enlargement space, animate lift with the shared interruptible motion clock, and coordinate image highlight with persistent captions. Reduced motion retains the ring without lift.
- Use single-panel automatic gamepad menu hierarchies. Update the Showcase, agent/control-selection guidance, ornate-theme checks, and the 24-card adaptive-navigation performance workload.

- Navigate inferred nested layouts using resting geometry, including bound stack-axis changes; preserve declared grid, virtual collection, and radial topology.
- Add `viewingDistance` (automatic/near/ten-foot) and `distanceProfileSource`, with a Showcase setting. Explicit distance applies across typography, metrics, density, focus, and safe areas independently of controller connection.
- Restore valid tab focus paths on navigation entry without retaining tab content; `TabView.restoreFocus = false` allows a fresh task entry. Long automatic gamepad menus and popups use the existing sheet presentation.
- Keep Pixel Quest selection ornaments inside their content reservation; wrap the existing Showcase action row when theme or text needs more room.
- Bound held-navigation catch-up to three steps per frame. Expand controller and Pixel Quest theme verification to nearby handheld screens.

- Round native presentation offsets and size deltas before writing pixel geometry, removing the final pixel snap when Showcase animations settle.

- Blend focal launchers back in on the radial exit clock, including interrupted closing; hand off lists without overlapping rows. Measure navigation arcs against the themed icon square so large Close artwork stays inside its plate. Fit custom compact images against their actual rendered rectangle, including responsive image fallback. Keep explicit image content visible when a composite suppresses its theme plate, without borrowing the plate’s shadow.
- Give Pixel Quest, Compact Pointer, and Glossy Touch the actual tinted search image while preserving their other glyph choices. Expand world-anchor design guidance for proximity actions and choosing between object, corner, and single-action UI.

- Change unpublished `client.world_anchor.padding` from pixel spacing (default 12) to a relative radius fraction from 0 to 1 (default 0.15). Remove its pixel `minimumRadius` option; use RadialMenu’s theme-based `clearance` for a minimum opening. Existing pixel padding callers must migrate to a fraction.

- Preserve runtime native theme sheets across character respawns in a shared, non-rendering ScreenGui with `ResetOnSpawn = false`. This fixes lost styling after revisiting the Quick actions Item scene.

- Add public `client.world_anchor` for Part, Model, and avatar bounds projected into radial anchor/clearance data on the host frame. Radial menus follow measured radius, freeze it during selection, and support `launcher = false` and `api.isVisible` for proximity prompts without overlapping launchers. Add the real-world Item example to Quick actions.

- Preserve themed circular launcher borders outside their animation content bounds. Measure radial preview space and compact bands around fixed clearance so the Fantasy Ornate character ring fits small portrait offers.
- Keep the corner navigation disc visible through dismissal, crossfading Back/Close into the launcher icon and smoothly returning to its size; support reopening during retirement.
- Compact radial geometry before choosing a list on small landscape surfaces, preserving minimum touch targets, directions, and explicit focal clearance.
- Keep radial opening/closing centered on its launcher or focal anchor through the presentation offset channel, including all four corners and interrupted animations.

- Add `UI.Button.focusVisual` for composed controls that paint their own focus treatment; radial selection highlights the outer circle/wedge while image-only buttons retain the content outline.
- Center radial compact representations and use semantic navigation icons. Animate opening/closing rings in one coordinate space; fade list fallback fully before restoring its launcher.

- Allocate radial list rows at their themed button height so adjacent rows cannot cover the keyboard focus outline; use standard list navigation to scroll the focused row into view.
- Inset focus rings beneath any clipping ancestor, including scroll containers beyond an intermediate layout or motion host.
- Keep the native scaling pivot at an explicit settled scale of one, removing a final-frame pixel snap while preserving scale cleanup when the transform clears.
- Refine radial menus with single list navigation, closed arc borders, image-only button surfaces, concurrent parent-origin submenu motion, and a four-corner Showcase selector. Add control-choice guidance for UI-building agents.
- Correct radial-menu touch/list activation, shared surface/content retirement and replacement transitions, centered skins/icons, ring/corner navigation, uniform slim bands, and contrasting outlines. Add direction-based gesture selection for cramped layouts.

- Add `Controls.RadialMenu`: native wedges and corner buttons, configurable content-fitted arcs (both axes by default), compact icon/text labels, mixed ring/page hierarchy, captured gestures and semantic keyboard/gamepad input. Add the curated Quick actions Showcase demo.
- Add the Path tint alpha channel via a reused UIGradient; document that CanvasGroup does not fade Path2D.
- Fix scaffold runner-signature drift and remove the type checker's stale hardcoded control count.

## [0.11.0] — not yet published

- `Controls.NavigationStack` adds a caller-owned observable route path, root and
  destination builders, push/pop/back/root operations, page scope cleanup and
  legal focus restoration through the existing presenter contribution seam.
- Navigation pages share a clipped viewport. Pure horizontal slides travel the
  stack's width, reverse on Back and preserve motion when interrupted; outgoing
  pages no longer create a second vertical layout slot. Structural transition
  declarations can be readable and are sampled on enter/exit.
- Interrupted transitions release paint channels no longer used by the next
  form, so changing a fade to a slide cannot leave content partly transparent.
- The confirmation example uses an content-sized horizontal actions with compact-label fitting, centered
  labels and a primary Cancel action with explicit initial focus.
- Search clear icons and checkbox marks are centered through the existing layout
  rules, including theme changes and larger text.
- Search fields use a tintable magnifying-glass asset in the existing `facet:search`
  icon slot. Preferred compact icons reserve their theme size, including Back.
  Selected labels keep aligned with their selection pill during ten-foot focus.
- Horizontal `firstTextBaseline` / `lastTextBaseline` alignment composes with
  nested and wrapped layouts. Theme typography supplies semantic guides; no
  engine glyph-baseline measurement is claimed.
- `UI.Spacer.minLength` adds a reactive, theme-compatible main-axis floor.
- `motion` clocks can bind numeric animation values to observable state with
  `clock:animate`, including existing theme tint blends and reduced motion.
- The default theme is **Facet Neutral**, package ID `facet-neutral`. Replace
  saved or configured `studio-neutral` identifiers with `facet-neutral`.
  The theme's colors and geometry are unchanged; its identity and content stamp
  change. `themes.neutral()` and `themes.neutralPackage()` keep their names.
- The Showcase journey demonstrates navigation, text guides and flexible gaps;
  the controls guide describes current controls and their configuration.


### Added

- **`Button.role = "onIndicator"`, the label-only role.** The other three button
  roles name a fill *and* the colour that reads on it; this one names the colour
  alone, because the plate is painted by something behind the button — an accent
  surface such as Facet's own sliding selection indicator. Its rule is
  `TextColor3 = $OnAccent`, the theme contract's one gated partner for `$Accent`,
  and it brings no background, so the chip it sits on is still the only plate on
  screen. See [api.md — semantic roles](docs/reference/api.md#button).
- **`enabled` and `tint` on the layout containers, where they apply to the whole
  subtree.** `enabled = false` on a `Screen`, stack, `ScrollView`, `Grid`,
  `Anchor`, `AdaptiveStack` or `Composition` disables everything under it: every
  descendant leaves focus order — both derivations, the linear one Tab walks and
  the directional one the arrows and the pad walk — refuses Activate on every
  input class, and takes no pointer, touch, drag or secondary action. `tint` on
  the same containers is the continuous colour their subtree paints with. Both are
  reactive, and a change re-solves in place rather than rebuilding.
  The pre-0.12.0 API reference documented these inherited properties.
- **A themed disabled state, `facet-state-disabled`**, and what it paints is
  exactly one rule. The engine's `:NonInteractable` state exists only on the
  classes it considers interactable, so Facet Neutral and every theme package
  emit `Disabled subtree text`: a `TextLabel` carrying the tag is dimmed to that
  theme's own `disabledContentOpacity`. **Text only** — image paint is legal in a
  theme rule only inside a nineSlice chrome recipe — and the tag reaches the four
  classes that consume it (`Button`, `Toggle`, `TextField`, `Text`) rather than
  every node, because writing to a container the renderer had elided materializes
  it permanently. A `tint` that declares its own `transparency` claims that
  property and outranks the dim. A presented surface (modal, toast, menu, popover,
  anchored sheet) is its own root and inherits neither channel. All four limits
  were stated in the pre-0.12.0 API reference.
- **A Roblox Package distribution channel.** Facet is now published as one Roblox
  Package asset, which is the recommended install for creators who work in Studio
  without a file sync. The asset id does not exist yet; it is recorded in
  `package/facet-package.json` when the asset is created, and the maintainer
  interface is `tools/package.sh` with [`package/README.md`](package/README.md) as
  its reference.
  Installing, updating, and version checking are described in
  [guide 8](docs/guide/08-without-rojo.md).
- **A standalone consumer project**, `examples/consumer/`, that builds the
  five-minute screen from the public API alone and is proved headlessly by
  `tests/consumer_standalone.spec.luau`.
- **Public project files**: `LICENSE`, `THIRD_PARTY_NOTICES.md`, this changelog,
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
  [`AGENTS.md`](AGENTS.md), a `skills/use-facet/` skill, and continuous
  integration plus issue and pull-request templates under `.github/`.

### Fixed

- **An authored hide that moves during a solve now lands on the next drain.** A
  `hidden` flip made from inside the presenter's geometry feed was swallowed
  for the life of the surface, so a segmented `Picker`'s selection indicator
  never painted until a real slide ticked. The renderer now forces the solve
  that owes the walk when the re-read value actually moved.
- **A `UI.Path`'s stroke is born at, and follows, its node's paint order, and its
  geometry is uploaded once.** The screen target never gave a `Path2D` its
  `ZIndex` and re-sent unchanged control points on every rect write.

### Changed

- **A segmented `Picker`'s selected option is readable on its own chip.** The
  sliding pill paints `$Accent` behind the option; the option's label kept
  `$Content`, the colour chosen to read on `$Surface`, and on a package with a
  saturated accent the pair measured 1.55:1 against a 4.5 floor. The option the
  pill covers now carries `role = "onIndicator"`, so the label takes `$OnAccent`
  and travels with the selection. Nothing else about the control moves: the
  option still declares `surface = "plain"`, still carries no `selected` tag, and
  the chip is still the selection paint. The `underline` indicator is unaffected —
  it paints a tint rule on the segment's far edge, not a plate under the label.
- **`present()` refuses when `initialFocus` names a disabled control**, on every
  screen rather than only some. The flat focus derivation always refused —
  "initialFocus 'X' names no focusable on this surface", listing the ones that
  are — but a screen with horizontal structure took the grouped derivation, which
  did not exclude a disabled control at all and so presented happily with the
  ring sitting on it. The two agree now, and the error is the same one. **If you
  focus a primary action that starts disabled until a form is valid, name a
  control that is live, or use `"first"` / `"none"`.**
- **The arrows cannot cross a `Grid` row whose every cell is disabled.** A grid
  names each row group's `up`/`down` exit by index, so an emptied row is still the
  named neighbour and the move lands nowhere — everything below it is unreachable
  by the arrows and the pad. This is exactly what a fully `hidden` grid row has
  always done; what changed is that `enabled` is now inheritable, so the shape
  reaches an ordinary settings screen. **The same content as stacked `HStack` rows
  is crossed cleanly**, and `UI.When` removes the row outright. Tab is unaffected.
- **`enabled = false` now means the node AND its subtree.** On `Button`, `Toggle`
  and `TextField` the property is unchanged for a leaf; what is new is that the
  state is inherited, and that it cannot be undone from below — an ancestor never
  re-enables a node that declares `enabled = false`, and a descendant never
  re-enables itself inside a disabled container. A focusable `Grip` inside a
  disabled subtree now leaves focus order too, which it did not before: `Grip`
  carries no `enabled` of its own, so nothing had ever asked the question for it.
  A `Button` is a container, so **a disabled button's custom content is now
  disabled with it** — its own children wear the theme's disabled state instead
  of keeping full contrast beside a plate the engine had already dimmed.
- **Facet is licensed under the MIT License.** Material this repository did not
  create is listed with its own notice in
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Verification runs in four named tiers** — affected, fast, full, and release —
  through one command, `tools/verify.sh`. An ordinary change runs affected or
  fast; a change about to merge runs full; a release runs the release tier.
  `./run-tests.sh` and `./run-tests.sh --fast` still work and still mean the same
  thing.
- **The public documentation was refreshed end to end**: the README, the guide
  index and capability catalog, installation and upgrade instructions, the
  extension playbooks, and every link that pointed at internal material.

### Removed

- **The vendored copy of another reactive library, and its adapter.** Both were
  bake-off arms kept from the comparison that chose Facet's own core; neither
  ever shipped in Facet's runtime, model, or Package. Facet used its own core
  at that point; the current unreleased runtime uses Compose as described above.

## [0.10.0] — not yet published

The version this tree reports as `Facet.VERSION`. It has not been published, so
the deprecation window begins at its first release. Until then the register below
is the record of every behavior change riding this version. Recording the change
is what makes a breaking change legal before a version's first publish
([the versioning policy](CONTRIBUTING.md#versioning)).

### Added

- `Facet.Controls`, a frozen namespace of typed control constructors called as
  `Facet.Controls.<Name>(core, spec)`. Every older `Facet.new<Name>(Facet, core,
  spec)` builder still works and is listed in `Facet.DEPRECATIONS`.
- The world-fixed surface render target, `client.surface_target`: the same flat
  two-dimensional Facet screen on a `SurfaceGui` a player walks up to. It is a
  flat world target, not a spatial one — geometry in front of it blocks input,
  and it pins `AlwaysOnTop = false` so that stays true.

### Changed

- **Adaptation answers for itself.** Controls that need device facts and cannot
  find an environment now refuse to construct instead of quietly assuming a
  large screen with a pointer. A `UI.Grid` given neither `columns` nor
  `minColumnWidth` lanes itself from the box it was given, and
  `UI.AdaptiveStack` requires its `axis`.
- **The ten-foot display class scales type, theme metrics, and paint**, so a
  screen written the ordinary way is legible on a television.
- **Roblox `StyleSheet` paint is the default render path** rather than an opt-in.
- The library is named Facet, and its call shapes moved with the name.

### Behavior changes riding this unreleased version

Each row names the surface, what it did before, what it does now, and why the
move breaks a caller. A change to what the library promises is landed by adding
its row here in the same commit.

1. `UI.AdaptiveStack.axis` was optional and defaulted to `"y"`; it is now
   **required**. A bare `UI.AdaptiveStack{…}` was a permanent vertical stack and
   now raises at construction.
2. `UI.Grid` given neither `columns` nor `minColumnWidth` laid out one lane at
   every width; it now lanes itself from the box it was given
   (`minColumnWidth = "intrinsic"`). A bare grid silently re-lays out: the same
   six cards go from one column to two, four, six, nine, five, or seven across
   the audited viewport combinations.
3. `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, and
   `newVirtualList` with `itemExtent = "cards"` each **refuse to construct** when
   no environment can be found. Each previously substituted the large-screen,
   near-distance, no-cutout answer in silence. The refusal replaced wrong
   behavior rather than working behavior: zero of the seventeen shipped `Picker`
   sites had reached the adaptive default.
4. `adaptive.navPlacement` on a tablet answered `bottomBar` and now answers
   `topBar`. A documented policy answers differently for a real device class;
   six shipped assertions were re-pinned because they had asserted the defect.
5. `adaptive.columnsFor` at the ten-foot distance was uncapped and is now capped
   against the wide breakpoint, so a television gets fewer columns than a desktop
   where it used to get more.
6. Unauthored text on a `Large` display scaled only at its authored size; the
   whole type ladder now scales by 1.5. Every screen written the natural way is
   1.5 times larger on a television.
7. Every theme metric on a `Large` display was unscaled and is now scaled by the
   type floor's own factor, so control heights, spacing, icon sizes and the 44px
   hit floor all move on a television.
8. `UI.Composition`'s content lane at the ten-foot distance took an uncapped
   share and is now capped at the lane measure times the metric scale (900px). A
   shipped composition re-measures on a television and nowhere else.
9. `newTable` narrower than its columns clipped; it now **collapses** a column by
   priority and discloses it. Shipped tables re-lay out at the compact size
   class, and a `fill` column's `minWidth` is honored — one playlist column went
   from 30px to 66px.
10. `newTable` selection and edit-mode keys had no modifier semantics: an arrow
    key replaced the selection. Control or Command now moves without selecting,
    Shift extends, and on a table with no `onPrimaryAction` a device Activate
    toggles.
11. A horizontal `UI.ScrollView`'s focus ring ran vertically and now runs
    **horizontally**: Left and Right step the rail, Up and Down leave it. That is
    the opposite of what shipped.
12. `newTabView` and `newPicker` band placement parked in the band's corner and
    are now centred in it. Shipped geometry moves on three placements.
13. The library's own name and call shapes changed: the require path is `Facet`,
    and `Facet.newTable(Facet, core, spec)` became
    `Facet.Controls.Table(core, spec)`. Nineteen call shapes moved; every old
    builder still works and is in the deprecation ledger.
14. The gallery example's `showcase_chrome.TOGGLE_GAMEPAD` was `"ButtonY"` and is
    **removed**. The showcase chrome bound the gamepad toggle to `ButtonY`, which
    is `newMenu`'s own gamepad trigger, so one press opened both. `ButtonY`
    belongs to the menu verb; the pad reaches the chrome through the two shoulder
    buttons instead. This is an example's export rather than a library surface,
    and it is recorded because a consumer copying the showcase's key map is
    exactly who this register is for.
15. `native_style.DEFAULT_ENABLED`, the library's default paint path, was opt-in
    (`false`) and is now default-on (`true`): a `screen_target.new({})` carrying
    no `nativeStyle` option paints through a Roblox `StyleSheet`. Every screen
    target that never named a paint path changes painter. Sheet rules and the
    `::UICorner` and `::UIStroke` modifiers replace the adapter's per-property
    writes, so no `UICorner` or `UIStroke` instance exists under a Facet root any
    more and a consumer reading those instances back finds nothing; the Style
    Editor becomes the paint authority for anyone who opens the place. The two
    paths were measured byte-equal on every mapped property, so the pixels are
    the same and the mechanism is what moved — which is exactly the kind of
    change a consumer's own code touches and a screenshot does not. The escape
    hatch is unchanged and still wins over everything: an explicit
    `nativeStyle = false` keeps the explicit-write path, which stays a
    first-class tested path rather than a corpse.
16. `UI.Region{ expand }` on a form that carries no control of its own
    synthesized a chevron beside the form; it now synthesizes a **cover** over
    the whole form. A passive compact form draws no mark at all and the whole of
    it becomes the tap or Activate target at the standard hit floor, where it
    used to draw a caret in a column the form's own measure reserved. Shipped
    geometry moves: the form gets the mark's column back — one demo's clock zone
    went from 100px to 80px at 360x691 — so a value that was being cut may now
    fit and a screen tuned against the reserved width re-lays out. The cover
    declares `zIndex = -1`, so it and the hit expander banded below it paint
    under every form within its own region. `UI.Foreign` and the lazy regions
    still force the chevron.
17. Corner radii and hairline strokes now scale with the metric ladder at the
    ten-foot display class, derived from the same metric scale so a later scale
    change moves them in lockstep. A radius rounds to a whole pixel because a
    `UDim` offset is an integer; a stroke keeps its fraction because thickness is
    a float. At a scale of 1.5: 12 becomes 18, 8 becomes 12, and 1 becomes 1.5.
    The capsule sentinel scales from 999 to 1499 and paints identically for every
    box up to 1998px on its shorter side. A theme package's ten-foot metrics may
    name a paint path and win on both sides. Near-distance density is
    byte-identical.
18. `UI.Region{ expand }`'s plate-or-sheet selection, and the resolved
    `plate.max`, were measured against the gutter allowance and are now measured
    against **the allowance minus the plate's own chrome** (at a 390px viewport,
    358 becomes 342). A form whose natural width lands in the last few pixels of
    the allowance now falls back to the full-width sheet instead of mounting an
    anchored panel that was wider than the allowance it had just been chosen
    against — reproduced at 390px, where a 320px form gave a 358px cap and a
    380px panel. No shipped screen moves today, which is exactly why the row is
    owed: the next reader tuning a form against the allowance has no other way to
    learn the band exists.
19. The hit expander a `role = "cover"` affordance receives inflated the solved
    rect by 44px unconditionally; it now **grows one side at a time, and each
    side stops at the first rect outside it that can sink a press**. Boxed in on
    every side it retracts, and the affordance is reached through the region's own
    box. A cover is its region's whole box, so the old floor took presses from
    neighbours: measured at 390x150, 960 square pixels of one neighbouring button
    and 828 of another — 26% of each — were delivered to the plate instead of the
    button the player aimed at. Only rects the author declared stop a floor: a
    framework affordance may not take the accessibility floor off another one. Of
    381 swept routes, 38 end below the effective floor and every one is cut by an
    author node; the smallest route is 35px and 31 covers retract.
20. `newPicker`'s activation order is now **one transaction** around both the
    control's own write to `selected` and the `onChange` it then calls. It used
    to be two turns: the write flushed on its own before the callback ran. A caller
    may redirect or veto a pick from inside `onChange` by writing the signal
    back, and until now the value it was about to undo was published first: every
    observer of `selected` saw it, and a `UI.When` over the selection mounted a
    whole subtree and evicted it in the same frame. An observer that counted
    selection changes now sees fewer of them, and an `onChange` inherits a
    transaction body's obligation not to yield. A read is unaffected: a
    transaction defers the flush, never a read.
21. `newTabView` with a declared `sizing = "hug"` at `bottomBar` now gets the same
    **centred scroller** every other hugging home gets. It used to park the strip
    at the band's leading edge in a stack that could not scroll.
    The thumb-zone band is deliberately not a scroller because a
    `fill` strip divides the offer and has nothing to overflow with — a statement
    about the default that the code was applying to the home, so a caller who
    declared `hug` there got natural-width segments at the leading edge and a
    strip wider than the phone simply ran off it. The `fill` default is
    untouched.
22. `Facet.text.fit` and `Facet.text.size` decided a size "fits" when the wrapped
    form stayed inside `lines` (and `height` when given); the widest line must now
    also stay inside `width`. A single word has no legal break, so the wrapper
    reported one natural line at every size however far past the box the glyphs
    ran, and the function handed back the cap for a string that does not fit at
    all. For a multi-word phrase nothing moves, except the one case where it
    should not have: a phrase whose longest word is wider than the box, which the
    engine breaks mid-word and paints outside the column.
23. A `hug` dimension on a `UI.ViewThatFits` **candidate** was measured at the
    minimum of content and offer, like every other `hug`, so the width test was
    true at every width. It is now resolved as content, uncapped, for the
    duration of the fit probe; the author's own `min` and `max` still bind, and
    the winning candidate is capped by its offer exactly as before. A `hug`
    candidate could never report "does not fit", so the ladder pinned its first
    rung forever and the labels it exists to protect truncated anyway. Refusing
    `hug` at construction was rejected: a control that picks `hug` for itself
    would have been refused for a spelling its author never wrote.
24. A `topbar` region under `rootPolicy = "bandSafeContent"` was a row spanning
    the composition's full width, as tall as its own content. It is now laid into
    the platform's own free strip — that strip's x and width, reaching its bottom
    edge — and the lane band below it is floored at the platform's whole top
    reservation. The tenth zone is the one that is not an anchor, and its purpose
    is to sit level with the platform's own controls; until now its geometry was
    the consumer's, held open with spacers and a memo. A caller that declares a
    `topbar` region now gets a row whose x, width and height are all platform
    facts, so a hand-computed spacer beside it is a double reservation. Two
    further consequences: a span row's slack now goes to its `fill` regions, which
    is what lets a region centre in the strip rather than sit at the top of it;
    and the lane band's floor is the platform's whole reservation rather than the
    band's bottom edge, except for a composition that both rides the strip and
    declares `exclusions`, which has already said where its own chrome is per
    column and gets the platform's own row instead of the bounding box. A
    composition that declares no `topbar` region resolves exactly as
    `deviceSafeContent` would have resolved it.
25. The gallery's grid scenarios forced their cell and line gaps to `"xs"` (4px)
    at Facet Neutral, because no space step named 6. They are restored to
    `"tight"` (6px), the value both fixtures originally wanted, now that
    `space.tight` exists as a derived step naming the value halfway between `xs`
    and `s`. Both grids' rendered gutters grow from 4px to 6px in the shipped
    gallery: a deliberate value change, not a value-identical rewrite.
26. Two gallery viewports carried literal pixel heights (150 and 120, each a
    hand-guessed "roughly N rows with the next one peeking through"). They are
    now content-terms formulas — four rows of the compact control height (144px),
    and six lines (116px). Both render 6px and 4px shorter at Facet Neutral, in
    the safe direction for a viewport: the old 150 never held four full rows
    either, since the rows are 46px each. What actually changes is that both now
    grow at the ten-foot ladder and at a raised text preference, where the frozen
    literals never did: 144 becomes 216, and 116 becomes 173.
27. Under `rootPolicy = "bandSafeContent"` with both a declared `topbar` region
    and declared `exclusions`, the lane band used to start at the topbar row's own
    measured height with no platform-reservation floor under it whenever the
    platform band was absent. It now falls back to the same reservation the
    no-exclusions path already used. The platform band really is absent on a live
    device, both at boot before the first platform push and on a measured
    rotation-recovery frame, so this was a real lane-and-topbar overlap risk
    rather than a headless-only one.
28. The expand plate's close disc used a spacing step (`space.xs`) for its corner
    inset, which had no relationship to the focus ring it exists to clear. It now
    uses the larger of that step and the ring's own inset. Every package whose
    spacing already cleared the ring gets the identical inset back; the two
    packages that were short move from 3px to 4px at the ten-foot ladder, closing
    a measured 1px overrun by construction rather than by a named ratchet.
29. `surface = "badge"` had no intrinsic size at all — a bare glyph hugging its
    own pixels, or an empty zero-sized box. It now carries a theme-owned minimum
    (20px at Facet Neutral, scaling at the ten-foot ladder like every other
    control metric) on both axes when the author declared neither `width` nor
    `height`.
30. Two gallery motion fixtures sized their lane and puck with a raw 40, unscaled
    at every display class. Both now use the theme-owned decorative-chrome floor:
    identical 40 at Facet Neutral and Medium, and 60 at the ten-foot class — the
    first scaling either box has ever had. Both render 20px larger there, in the
    safe direction.
31. `UI.Composition{ exclusions }` shared a lane's slack out as the lane's budget
    without the chrome row, rather than as the lane's own already-inset height.
    An `end`-placed group landed exactly the give-way inset past the bottom of its
    own lane, a `center`-placed one half of it, a numeric placement a matching
    fraction of it, and a `fill` group took the same phantom pixels as height.
    Measured one-for-one from a 1px inset to a 300px one, and seen live at 141px
    on a console and 54px on a phone. It is a defect fix that restores the
    partition guarantee, and shipped geometry moves for every consumer that
    declares `exclusions`.
32. The themed-chrome family changed in four places. An inset was spent whenever
    any pixels remained; it is now spent only when the node's own line box still
    fits — a text-bearing leaf needs more than its text size, everything else is
    unchanged — on both the measure and the paint seam. A sibling plate's border
    is no longer spent twice. The pill selection indicator's inset is reduced by
    the plate slot's carved border. Shipped geometry moves under every package
    that carves a border: an ornate disc loses the frame it was reserving twice
    (60px becomes 52px under one package, 44px becomes 38px under another), and
    every pill indicator covers its whole segment rather than an inset chip.
    Facet Neutral and every flat package are byte-identical, because their carve
    insets are all zero.
33. `newMenu`'s automatic presentation at a **compact** size class with a
    pointer-primary interaction class resolved to its own answer, gated on live
    touch plus an item count; it is now forced to the sheet presentation whenever
    the size class is compact, unconditionally. A documented policy answered
    differently for a real, reachable environment — a compact width with no touch
    signal, which is a phone with a mouse, or Studio's own compact preset, which
    cannot inject touch at all. Every submenu now replaces the panel in place with
    a Back row instead of floating a second panel over a parent that does not have
    room for it. The regular and wide classes are unaffected, and an
    author-forced presentation is unaffected at any width.
34. `distanceProfile`, `typographyScale`, `typographyPaintScale`, `themeMetrics`,
    `sizeClass` and `effectiveOverscanInsets` resolved from the raw `displaySize`
    and now resolve from the derived `effectiveDisplaySize`, which downgrades
    `"Large"` to `"Medium"` when the session is touch-capable. On a
    `"Large"`-reporting, touch-capable session the ten-foot type and metric scale,
    the density cap and the console overscan margins now read off, 1, uncapped
    and zero, where they used to read on, 1.5, capped and 60 to 90px.
35. Under `scrollIndicatorPolicy = "auto"`, the solver's scroll-bar reserve was
    policy-blind: `"always"` and `"auto"` reserved the same thickness. It is
    policy-driven again. `"always"` is unchanged; `"auto"` now publishes zero, so
    content measures to the full cross-axis width instead of the width minus the
    bar. Content that used to stop 8px short of the scroller's own edge now runs
    to the full edge. A bare zero reserve alone would reproduce an older defect,
    because Roblox narrows a `ScrollingFrame`'s window by the bar's thickness
    whenever the scroll axis overflows regardless of paint policy — measured
    again this round, and a fully transparent bar image does not stop it — so the
    zero reserve is paired with widening the scroll host's own frame by the same
    thickness on the cross axis while it overflows. The overlap is the bar sitting
    in that borrowed space.
36. The float focus ring a focusable control draws inside a clipping or scrolling
    host read its corner radius from the target's construction-time style, which
    no theme swap ever reassigns; it now prefers the live theme snapshot's radii
    and falls back to the construction-time style only while no package is
    installed. The corner was also built only on first creation and is now
    re-synced on every focus-visual call, so a live swap's repaint reaches it. A
    focused control's ring corner moves under any installed package whose control
    or panel radius differs from the target's boot radius, on the first focus
    after a swap. With no package installed at all it is byte-identical.
37. Every badge overlay in the repository — the segmented picker's count seal and
    the gallery's hand-rolled tile badge, two independent implementations — was
    anchored flush at the raw corner under every package. Each now insets top and
    right by the theme's carved border for its slot, through one shared
    primitive rather than the same four-line loop written by hand three times.
    Shipped geometry moves under any package that carves a control or accent
    border; flat and Facet Neutral packages are byte-identical, because the
    computed inset is zero on both axes.
38. Every `UI.Path` wrote its normalized control points as pixel offsets and now
    writes them as scale. A `UDim` offset is a 32-bit integer — measured live on a
    round trip, `UDim2.new(0, 25.05, 0, 6.95)` reads back as 25 and 6, while the
    same pair survives to six decimals as scale — so every control point was
    truncated to a whole pixel. A 32px progress ring lost 0.8px at its 3 and 6
    o'clock extremes and 0.2px at 12 and 9, painting as an off-centre egg, and a
    closed ring's last point floored to 15 where its identical first point floored
    to 16, so the track closed one pixel left of where it opened. Separately, the
    showcase's glass plates now declare their own surface role and take the
    caller's gutter through one shared inset memo, instead of painting a raised
    box behind a sibling that wrote its own gutter.
39. The layout reserve every native scroll host spends under
    `scrollIndicatorPolicy = "always"` was exactly the bar instance's thickness
    (8px) and is now that thickness plus a one-pixel gutter (9px). The bar
    instance itself is untouched at 8px, and so is the engine's own window
    narrowing, which is what makes the extra pixel visible rather than painted
    over. Every overflowing `"always"` scroll host lays its content out 1px
    narrower on the cross axis, and the gutter a sibling pays — a table header
    aligning with its body — grows from 8 to 9 on the right for a vertical
    scroller and on the bottom for a horizontal one. `"auto"` is untouched: it
    reserves zero and deliberately overlaps. The earlier round had already
    measured that this boundary was not an overlap; the ruling is that
    exact-and-flush is the defect, because content on the bar's outermost pixel
    reads as a collision.

## Earlier versions

Versions 0.4.0 through 0.9.0 predate this file. Their public surfaces are
documented in [`docs/reference/api.md`](docs/reference/api.md), and the retiring
ones are listed with the version that may remove them in `Facet.DEPRECATIONS`.

### Unreleased — game navigation continuity

- Add declarative per-property animation and automatic layout groups on the shared
  motion clock; provide owned `ui.animate` and explicit `ui.withAnimation` helpers.
- Normalize custom-component children, accept direct `When` children and collection
  key fields, and share repeated getter bindings within their mounted owner.
- Add Motion → Automatic to the showcase and paired animation benchmark workloads.


- Keep client input contexts in stable client-created storage; entering Table rows from a focus section works in normal and edit modes. Showcase unread markers use bounded vector paint so ornate panel decorations cannot spill across their rows.

- Add semantic row presentations to Button, Toggle and Slider, declarative focus
  sections, and named ScrollView targets with shared snap/motion and visibility/progress.
- Restore TabView scroll positions by stable descendant/item key, including virtual
  lists, grids and tables; preserve lazy page disposal.
- Add optional tab sections and caller-owned order/visibility customization, with
  animated selection indicators that follow changing keyed options.
- Extend Showcase game-art/row/navigation examples, theme containment checks and the
  adaptive navigation performance scene. Document when agents should choose each.
