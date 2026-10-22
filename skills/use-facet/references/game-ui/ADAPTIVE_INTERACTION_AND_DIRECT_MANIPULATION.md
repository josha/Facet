# Adaptive interaction and direct manipulation

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Design one understandable operation on a visible object, then let its interaction and feedback suit the player's input. Facet supplies adaptive behaviors for its controls and manipulation capabilities; the game supplies the meaning, eligibility, consequences, and any additional task-specific choices.

## Separate the operation from the input method

Direct contact and direct manipulation describe different things. Touch contacts the screen directly. A mouse uses an indirect pointer, while keyboard and gamepad commonly act through focus or directional input. Players can still manipulate a visible object with any of these methods: move a card, adjust a value, reorder a row, or place an item in a slot.

In this guide, **direct manipulation** means acting on a visible representation with an immediate, understandable relationship between the action and its effect. Mouse dragging is a direct-manipulation interaction even though the mouse is an indirect input device. Focus-based pickup and placement can preserve the same object-centered task without requiring a simulated finger or cursor.

The useful invariant is “I am moving this part into that slot.” Touch can express it through holding and dragging; a pointer through pickup and release; keyboard/gamepad through pickup, destination navigation, and placement. The operation, item identity, eligibility, and result should agree. The exact gesture and visual response need not be identical.

Not every command should become manipulation. A named Equip button may be clearer when there is one obvious slot or the destination is offscreen. Keep that route available where it reduces effort or improves access, and make it invoke the same underlying command.

## What stays common, and what adapts

| Keep consistent | Adapt to the interaction |
| --- | --- |
| Object identity and what the operation affects | Finger contact, pointer hover, or visible focus identifies the active target |
| Selection, draft, committed, and pending meanings | Touch affordances, pointer feedback, and focus treatment reveal those states appropriately |
| Valid values, eligible targets, and permission rules | Target sizes, gesture thresholds, focus traversal, and adjustment steps make them reachable |
| Move/copy/apply semantics and model commands | Dragging, armed pickup/place, explicit actions, or focused adjustment express the operation |
| Ability to inspect, cancel, recover, and understand the result | Input prompts, cancel bindings, dismissal routes, and return focus fit the method |
| Information needed for a decision | Menus, sheets, inline controls, and detail panes expose it within the available room |

Input adaptation is more than changing a button glyph or enlarging a hit target. It can change how a task is entered, how alternatives are traversed, how an object is held, and how commitment is indicated. Keep those changes coherent with the task.

## Start with the adaptive behavior Facet already owns

Use the semantic control or manipulation API first. Do not build separate touch, mouse, and gamepad implementations for behavior Facet already supplies. Configure exceptions only when the game has a concrete reason, then verify the affected paths.

| Task | Facet mechanism | How interaction can adapt |
| --- | --- | --- |
| Adjust a magnitude | `Slider`, `Stepper`, `NumberInput` | Pointer/touch can operate the visible value control; focused keyboard/gamepad operation provides adjustment. Choose bounds, steps, and precision once for the value. |
| Choose a value | `Picker` | Automatic style considers options, measured room, and input. A visible strip, inline choices, or an opened chooser can preserve the same value model. |
| Open object commands | `Menu`, collection `rowActions` | Secondary click, touch access, and focused actions reach the commands. Automatic Menu presentation can use a floating menu or a sheet with replacing submenu levels. |
| Change collection order | `reorderable` and `onReorder` | Pointer/touch manipulation and focused move controls reach the same placement proposal. Edit-mode affordances and input routes differ. |
| Transfer an object | Collection `drag`/`drop`/`rowDrop`, or `UI.draggable`/`UI.dropTarget` | A captured preview follows pointer/contact; armed input exposes pickup, destination navigation, placement, and cancellation. |
| Inspect a spatial board | `ZoomView` | Touch pinch/pan, pointer wheel/pan, and focused keyboard/gamepad zoom/pan act on the same stable content. |
| Resize or dismiss a temporary task | `Sheet` | Touch/pointer dragging follows the manipulation and settles on release; explicit controls and cancellation preserve access without a drag. Do not assume every gesture has an identical focused equivalent. |
| Make a directional quick choice | `RadialMenu` | Pointer/contact gestures and digital focus navigation expose the same items, with input-appropriate names and a list fallback when needed. |

“Automatic support” means the chosen Facet behavior provides its documented input routes and adaptive presentation. It does not mean every arrangement, source/target relationship, or custom control is automatically well designed. A drag destination still needs registration and validation. An editable collection may need an authored Edit/Done route. A custom adjuster may need `UI.adjustable`; a custom board may need `UI.commandScope`.

The designer still decides which operation is primary, whether selection previews or commits, which gestures compete, whether a drop means move or apply, and what happens while the world continues. Facet cannot infer those rules from the appearance of a card.

## Make the response feel natural to the input

### Touch: contact, occlusion, and gesture intent

Let continuous manipulation track the contact without decorative delay. Preserve the pickup relationship so the item does not jump unexpectedly under the finger. Put necessary labels and destination feedback where the finger does not hide them, and keep targets forgiving enough for the task.

Separate scrolling from pickup deliberately. A long press can reserve early movement for scrolling; an immediate drag can suit a manipulation-first board; orthogonal drag/scroll axes can resolve a genuine directional distinction. Do not enable all gestures on the same area and leave players to discover which one wins. Hover cannot carry required information on touch.

### Pointer: precision, hover, and captured movement

Use hover to preview what is actionable or where a drop will land before commitment. Keep the distinction between hovered, selected, and held states. Once pickup succeeds, the same object remains captured even while the pointer crosses other objects.

A held preview follows the pointer; after release it may settle, land, or return. Keep painted hover growth separate from the stable hit geometry. Precision can support denser targets, but small hit areas should not erase required access when touch or gamepad is also available.

Keep a spatial view stable during selection and actions. A click that selects,
opens or buys an object must not also zoom the camera. Reserve camera gestures
for the background and explicit navigation. Move the view only when requested
or when a focused object would otherwise be offscreen; do not recenter each
visible selection. Preserve scale when revealing an offscreen object.
Keep known canvas bounds stable as content appears; revealing an item should
not move the surrounding objects by changing centered margins.

### Keyboard and gamepad: focus, discrete steps, and explicit possession

Make the focus location and current mode unmistakable. Pickup should visibly establish which object is held; navigation should show the destination or insertion point; activation should place it; cancellation should return to a useful state. Use Facet's armed manipulation routes instead of requiring a pointer simulation for every task.

A reordered item can preview its next insertion position as focus or direction changes. An adjustable value can respond in meaningful increments while its visual representation updates. It need not reproduce the continuous trajectory of a finger to feel immediate and controllable. A gamepad may also supply analog input where the particular control supports it; do not assume all gamepad interaction is either discrete navigation or a free cursor.

Keep directional navigation and value adjustment distinguishable. Avoid consuming both axes for an adjuster if that strands focus, and avoid assigning a placement key that also activates the underlying item. Prompts should describe the current operation and actual bindings.

### Common feedback, different physical response

Across all methods, show acquisition, candidate target/value, accepted or rejected proposal, pending work, final result, and cancellation. The signal can differ: contact-attached preview, hover outline, focused destination, insertion gap, or an explicit status label. The state it communicates must stay the same.

During continuous manipulation, the manipulated representation follows input directly. During discrete manipulation, it responds promptly to the chosen step or destination. After release, a spring or eased movement can explain settling. During server confirmation, use a truthful pending state rather than continuing a celebratory animation. Choose those effects through [Motion and feedback](MOTION_AND_FEEDBACK.md), after the interaction is clear.

## Adapt input independently from room and gameplay pace

Touch does not always mean a narrow layout, and gamepad does not always mean distant viewing. Use actual room, capabilities, preferred input, text size, and viewing distance through Facet's adaptive controls and `UI.environment`. Choose a compact destination flow when source and target cannot be usefully visible together, regardless of input.

Keep record identity, selection, drafts, and accepted state stable through layout or input changes. Let controls update their prompts and presentation; do not unnecessarily rebuild the whole task on incidental input switching. Preserve an active manipulation where supported, or cancel it clearly when its source/destination becomes invalid. Never silently commit to a different target because the layout changed.

During action gameplay, consider whether manipulation takes over a finger, stick, or key needed for movement or camera control. Use a quick direct command or a deliberate task surface when object manipulation would interfere. During planning or building, the visible spatial relationship can be the main value of the interaction.

## Decide whether drag-and-drop is the right interaction

Drag-and-drop is useful when the source-to-destination relationship is itself meaningful. Moving a part into a visible equipment slot or placing a tile on a board can be clearer than navigating a sequence of menus. It also requires pickup, transport, target acquisition, and error recovery. A distant or hidden destination can make a simple command more efficient.

| Player task | Starting choice | Reason |
| --- | --- | --- |
| Change order within one collection | Built-in `reorderable` and `onReorder` | The operation is placement among siblings, with collection navigation and insertion feedback already available |
| Move/copy records between visible collections | Collection `drag` and `drop` | Keeps selection, virtualization, insertion, and transfer identity coherent |
| Drop onto a record, such as a folder or paintable item | Collection `rowDrop` | The destination is the object, not a position between records |
| Transfer a standalone visual to a distinct GUI/world target | `UI.draggable` and `UI.dropTarget` | Gives the source and destination one shared input-independent drop lifecycle |
| Move a panel, resize a sheet, scrub a value, or pan a map | That control's existing manipulation behavior | A movement gesture is not necessarily an object-transfer operation |
| Perform a frequent command with one obvious destination | Direct Button or row action | Dragging adds travel without adding a useful choice |
| Choose among many distant/hidden destinations | Select then Move/Equip/Apply chooser | Destination discovery matters more than spatial continuity |
| Commit a costly purchase or destructive outcome | Explicit review and named commitment | A drop may prepare a draft; it should not conceal a consequential transaction |

For games, also ask what the hand or stick was doing before pickup. Dragging in a crafting workspace may be comfortable; dragging during unavoidable steering or combat may sacrifice the primary action. A spatial inventory can justify precision, but make targets tolerant and provide alternatives where exact movement is not the intended game challenge.

Define the operation before the gesture: **move** changes location/ownership, **copy** creates another object, and **apply** uses the source on a target. Show that meaning. Do not make a paint swatch disappear because a generic drag default said move, or duplicate an item because a transfer was ambiguously described as copy.

## Add drag-and-drop through the owning Facet behavior

### 1. Establish source, destination, and model command

Identify the stable source item or selected set, the eligible destinations, the operation, and the model command that accepts the result. A visual clone is feedback, not a second game item. Validate current eligibility at commitment even if a destination was legal when pickup began.

For collection items, return a draggable spec from `drag(items, keys)`. Use `drop` for insertion/collection transfer and `rowDrop(current, key)` for dropping onto an object. Do not decorate the same row with a second overlapping drag system. Use a separate `UI.dropTarget` inside a cell only for a genuinely distinct subtarget, such as its color well.

For a standalone source, call `UI.draggable(source, spec)` inside its component/owner. Register its GUI or world destination with `UI.dropTarget(target, spec)` in the appropriate owner. Their registrations end with their owners; do not create global listeners that survive their UI.

Carry stable IDs and enough context to interpret the request in `payload`. A source `valid()` predicate can invalidate a removed, spent, or no-longer-owned item during the session. `enabled = false` prevents pickup while allowing the underlying object to remain inspectable/activatable. `operations` limits the allowed operations; the destination's `operation` selects the applicable move/copy/apply meaning.

Linked collection views should share `collectionId` and use a payload carrying collection, keys, and items. Moves preserve IDs; copies/new objects need new IDs allocated by the game. Update source and destination models coherently. Sorted views reject positional insertion until sorting is cleared: do not promise manual ordering while another rule owns the order.

### 2. Choose pickup without breaking other gestures

| Configuration/input | Design use and consequence |
| --- | --- |
| Default pointer pickup | Moving beyond the pickup threshold starts the drag; a shorter press retains ordinary activation. Keep the effective hit area stable even if hover art grows. |
| `touchPickup = "longPress"` | Early movement scrolls; a deliberate hold picks up. Good starting point for sources inside scrolling collections. |
| `touchPickup = "immediate"` | Movement after touch-down starts pickup promptly. Use when manipulation is the primary task and it will not steal an expected scroll. |
| `touchDragAxis = "X"` / `"Y"` | With immediate pickup, reserve one axis for drag and the other for scrolling. For example, horizontal pickup in a vertically scrolling list. `"XY"` does not provide that separation. |
| `armOnTap = true` | Tap source, then tap destination. Useful when sustained dragging is difficult; it changes what source activation means, so visibly show the picked-up state and cancellation. |
| `hitArea` | Bound pickup to a stable GUI rectangle, especially when painted tiles scale or overhang on hover. |
| Keyboard/gamepad pickup | Pick up, navigate to a destination, then place; provide a clear cancel route and truthful prompts. Test actual collection activation/edit-mode precedence. |

For standalone draggable buttons, armed pickup consumes their ordinary activation. Collections differ: an explicit `onActivate` takes priority over pickup on gamepad activation outside Edit mode; inside Edit mode, row activation changes selection and a move handle starts manipulation. Do not assume adding `drag` makes the same button both open detail and pick up at once. Give players an explicit mode, handle, or command when those intentions compete.

### 3. Make destination and acceptance visible

Use a destination `label` and truthful `accepts(payload, info)` validation. The acceptance function is checked during targeting and again at release; it should inspect eligibility, not mutate records or spend resources. Return a useful rejection reason. Use `onEnter`, `onLeave`, and `onUpdate` only for additional feedback that the default target highlight/status does not already provide.

Keep `statusLabels` on unless an equally clear authored treatment communicates operation, rejection, and pending state. Outline accepted targets, distinguish insertion between objects from dropping onto an object, and show what will move/copy/apply before commitment. A color change alone is insufficient.

`rowDrop` and collection insertion share space: pointer targeting in a row's middle can mean dropping onto the item, while edges route to insertion. Armed targeting uses the row as a destination. Make this relationship visually intelligible. If it remains ambiguous, separate the operations into a command or a distinct subtarget.

`passThrough(payload)` intentionally routes unmatched content to an enclosing target; a rejection otherwise blocks the drop. Do not let an invalid visible target silently pass a destructive operation to something behind it. World targets need a reachable GUI `focusTarget` for non-pointer placement. Visible UI and nearer world geometry can block world targets; do not imply that an obscured destination will receive the item.

### 4. Commit, reject, and handle pending work

`onDrop(payload, info)` runs the model command. For synchronous handling, return true or nothing after success, or false on rejection. `onReject` explains refusal without pretending the move succeeded. Hover previews and opened insertion gaps are provisional; model state changes at accepted placement.

For asynchronous confirmation, return `"pending"`. On the response, call `info.complete(true)` **before changing the presentation's model** and apply the accepted change only if it returns true. It revalidates and succeeds once. Use `info.complete(false, reason)` on refusal. A cancelled or late completion returns false. Keep authoritative requests and durable results in the game model; a cancelled UI session must not create a duplicate request or erase an already accepted server result when the model later reconciles.

Show pending state and prevent a second drop commitment for that session. On rejection, preserve a valid source and explain recovery. On success, make the final location and operation visible independently of motion. Cancellation, focus loss, source removal, destination removal, and UI disposal need safe outcomes. Bind the alternative Move/Equip/Apply command to the same eligibility and model rules.

### 5. Choose landing feedback

During pointer/contact dragging, the preview should track the player's input directly. Do not ease it behind the pointer or finger. During armed manipulation, show the held object and current destination or insertion point as navigation changes. After placement or release, motion can explain arrival or return.

Facet's default drag feedback already uses the shared Travel engine. `returnTravel = true` preserves the source recess during a cancelled return. Use reserved collection `slots` when an absent item's return position must remain stable. Do not make several unrelated copies of the same carried object to add more effects.

Set destination `travel = true` when visibly traveling to the destination before applying the drop clarifies placement. This **delays `onDrop` until arrival** and revalidates there; a removed destination or cancellation can prevent the handler. Without it, the ordinary immediate-drop contract remains. Choose deliberately: a fast direct operation may not benefit from the added wait. Reduced motion commits without travel delay.

`landing(info)` supplies the destination rectangle in screen pixels when the GUI target's measured rectangle is not the correct landing location, such as a particular insertion slot. A world target needs an explicit landing rectangle for screen travel. Keep that landing related to the visible destination; a flourish ending at a different point weakens the operation's meaning.

A swipe-controlled page is navigation, not an item drop. Use TabView with
`transition.progress` and a native `UIDragDetector` on a stable parent.
The [motion chapter](MOTION_AND_FEEDBACK.md) explains direct progress,
release settlement and cancellation. Keep explicit navigation buttons for
keyboard and gamepad. Do not create a second page control or animation loop.

## Worked design: inventory part to equipment slot

The player needs to inspect a part, see where it fits, preview a replacement, and equip deliberately. In a spacious inventory, a grid and visible equipment targets make drag-and-drop useful. In a compact layout with the destination on another page, selecting the part and pressing Equip opens a clearer destination chooser.

1. Use `VirtualGrid.drag` for the part and `rowDrop` or a standalone `dropTarget` for the visible slot, depending on who owns that target.
2. Define whether equipping moves ownership or applies the part while retaining its inventory record. Reflect that meaning in the operation label and model command.
3. Validate slot compatibility, ownership, and locks with `accepts` and authoritative game rules. Explain rejected targets before release.
4. Preserve scrolling with long-press pickup, or deliberately choose orthogonal immediate pickup. Retain inspect and non-drag Equip routes without conflicting activation.
5. If replacement needs review, a drop creates a proposed loadout/draft; it does not silently discard the old part. Show the replacement and a named commitment.
6. If the equip request is pending, show that state until the response and honor the completion lifecycle. Keep the equipped marker distinct from the selected candidate.
7. Use built-in landing feedback or target travel when continuity helps. The accepted slot and item state remain clear if motion is disabled or the view closes.

## Verify one task across input methods

Evaluate the same meaningful task through touch, pointer, keyboard, and gamepad where supported. Confirm common identity, eligibility, commitment, and result while allowing the interaction to differ naturally. Do not demand identical gestures or identical screenshots as evidence of consistency.

Check acquisition, active feedback, change/placement, cancellation, and return. On touch, test finger occlusion and scroll conflicts. With pointer input, test hover versus selection and stable captured geometry. With keyboard/gamepad, test visible focus, pickup mode, destination traversal, adjustment limits, and a reliable way out. Test any supported input switch or layout change during the task.

For drag-and-drop, also exercise valid, invalid, empty, and occupied targets; multi-selection; item disappearance; destination removal; scroll/recycling; filtered/sorted views; overlapping targets; pending success/rejection; and late responses. Confirm that a drag never also activates the source and that alternative commands reach the same accepted result.

Reduced motion should preserve clear input response, accepted state, and recovery. Use the [motion checks](MOTION_AND_FEEDBACK.md#verify-the-motion) for the effects themselves. Success means players can predict and control the operation using their input method, not that every method imitates touch.
