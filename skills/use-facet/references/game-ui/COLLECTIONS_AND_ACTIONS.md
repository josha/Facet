# Collections and actions

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). First decide what a player is doing to an object. A row, card, menu, and toolbar can expose the same command, but they impose different attention, travel, discovery, and error costs.

## Separate focus, selection, activation, editing, and commitment

**Focus** is where the next input will go. **Selection** identifies the object or set being considered. **Activation** opens or acts on an object. **Editing** changes a value or enters a mode for managing records. **Commitment** applies an intended outcome, such as buying or equipping.

These states may coincide in a simple control, but must not be accidentally coupled. Moving gamepad focus through vehicles should not buy them. Selecting one to preview need not equip it. An equipped vehicle can remain marked while another is selected. An unconfirmed server request is pending, not equipped.

Write the interaction sentence before building: “Selecting previews; Equip commits; Back keeps the previously equipped vehicle.” Then choose controls that preserve that sentence for every input method.

## Choose how an action is exposed

| Pattern | Use when | Avoid when | Facet mapping |
| --- | --- | --- | --- |
| Activate the row | One obvious, inexpensive result follows from choosing this object | Activation would silently spend, delete, or conflate preview with commitment | Collection `onActivate`; explicit navigation or action |
| Visible row action | A frequent command belongs to one item and must be easy to find | Repeating several buttons in every row overwhelms browsing | A labeled `Button`, or `rowActions` with Facet's item-actions access |
| Direct field editing | One short value can be understood and corrected in context | Several fields have coupled constraints, substantial explanation, or consequential Apply/Cancel | Built-in `Table` editor columns or `CellEditor` |
| Collection edit mode | Players manage selection, deletion, or ordering across records | A single harmless field change would require unnecessary mode switching | Collection `editing`, `deletable`, `reorderable`, plus Edit/Done |
| Select, inspect, then act | Comparison or consequences justify a separate commitment | Every trivial repeated action gains a needless selection step | Collection selection + detail/summary + named `Button` |
| Select several, then act | One operation applies to a visible, intentional set | Eligible records differ in ways the summary conceals | `selectionMode = "multiple"`, explicit Select/Done, selection count, bulk command |
| Context menu | Infrequent commands belong to a specific object and need little permanent space | It is the only discoverable route to the primary task | `Menu` on an object, or collection `rowActions` |
| Primary action with alternatives | One operation clearly dominates related variants | Alternatives are equally important or unrelated | `SplitButton` |
| Directional quick menu | A small stable command set rewards learned positions | Choices require substantial reading, comparison, or frequent reordering | `RadialMenu` |

These patterns can coexist with clear ownership. A garage can use selection for preview, an Equip button for commitment, direct editing for a nickname, and a context menu for Duplicate. They should invoke the same semantic commands as equivalent shortcuts; they must not implement different rules by input method.

### Row action versus direct editing

Use a row action for a **verb on the object**: Duplicate build, Pin quest, Invite racer. Use direct editing for a **value of the object**: nickname, quantity, enabled state. If “Rename” is rare, opening a field from the item's action menu can be appropriate; if players repeatedly tune many numeric values, direct editors reduce travel and preserve comparison.

For a record with interdependent fields, open a coherent detail editor or sheet. Editing price, quantity, and trade terms independently while each immediately commits can create outcomes the player never approved together. Show a draft summary and one explicit commitment for a transaction.

### Select then button

Use a separate command when selection has a useful purpose before action: preview, compare, inspect eligibility, or build a set. Keep the target identity and consequential information beside the command. “Equip Falcon” is clearer than “Confirm” beneath a remote selection.

Disable the command when there is no valid target, and explain a relevant restriction near the decision. Keep the action associated with the selected key even if the list sorts or refreshes. If that record disappears, invalidate the command explicitly. A focus change must not silently retarget a pending action.

### Context menus

A context menu is an action surface for the object from which it opens. Name that object when ambiguity is possible. Secondary click and long press are shortcuts; provide a visible More/Actions route where players need to discover the commands. A required frequent command belongs directly in the row or detail area.

Opening a menu on one row while other rows are selected needs a defined scope. Either act on that row, or explicitly label that the command affects the selected set. Never let “Delete” unexpectedly change from one object to several. Keep unavailable-but-relevant commands visible with an explanation elsewhere nearby; hide commands that have no meaning for this object. Use separators for meaningful groups, not between every command.

## VirtualList

Use `VirtualList` for repeated items mainly read or acted on one at a time: quests, messages, racers, saved builds. It is also appropriate for short collections that need selection, row actions, or reordering. A plain `VStack` is enough for a few unrelated sections.

Use stable `key` values so sorting, filtering, and live updates preserve identity. Choose `selectionMode = "none"` if the task has activation but no lasting selection; `"single"` for one candidate; `"multiple"` for a set. Show an intelligible selected state independently of focus.

Choose `direction` for the reading task: a vertical list suits descriptive records; a horizontal strip suits a deliberate browsing sequence with visible access to more content. Keep the other axis bounded. Do not turn a list sideways merely to fit it around unrelated panels.

Use measured row sizing (`measure` or supplied `measured` sizes) for variable descriptions and large text. A fixed `itemSize` must fit the content and row actions. Choose windowed lifetime for large data; keep durable drafts, expansion, and selections outside recycled rows. `mode = "all"` is for deliberately small bounded content, not a cure for lost state.

`focusPolicy = "key"` preserves the object as records move; index-based focus is appropriate only when position itself is the intended identity. `initialFocus` should land on a useful item. Avoid repeated `autoFocus` that steals focus during updates. Use `wrapFocus` only when crossing the end to the beginning is predictable; a long list generally benefits from clear ends.

Use `follow = "end"` for a live feed whose newest content belongs at the end, and honor the player's reading position through the follow behavior/threshold. Offer a route back to new content. Use `scrollReset` for deliberate context changes such as a new search, not every refresh. `onReachEnd` can request more records; show loading, end-of-results, and retry states honestly.

## VirtualGrid

Use `VirtualGrid` when appearance or spatial browsing distinguishes items: vehicle bodies, emotes, cosmetics. Use a list when labels and descriptions dominate, or a table when common numeric attributes drive comparison.

It shares collection selection, editing, actions, and focus behavior with `VirtualList`. Set `columns` or `minColumnWidth` from the minimum useful preview, text, and target area. Reduce columns before squeezing every item. Use `gap`/`crossGap` to make units clear; selection paint must not bleed into a neighbor.

`itemSize = "cards"` and `cards` settings (`perView`, `minWidth`, `peek`) support intentional card browsing. A peek can suggest more content but does not replace navigation access. `snap = "item"` suits deliberate item-by-item browsing; `"none"` suits continuous scanning. `contentOverflow = "visible"` can accommodate intentional effects, but check neighboring hit areas and clipping; it is not permission for labels to escape their cells.

Use `slots` to reserve positions for specific item keys, such as pieces temporarily removed from a rack. An absent key leaves a nonselectable recess; that item returns to its reserved position. These are reservations by item identity, not automatically typed equipment sockets. Release a reservation deliberately when the collection should compact. `slotControls` exposes retained slot anchors for `Travel`; use a deliberately small all-mounted collection if every anchor must exist. Do not make precision dragging the only way to move an item.

## SpatialGrid

Use `SpatialGrid` when inventory placement is part of the task. Each keyed item has a one-based `{ column, row, width, height }` placement. The control checks rectangular footprints and uses the existing draggable/dropTarget interaction for pointer, touch, keyboard and gamepad. Update the model from `drop.onDrop` using `info.placement`; keep stacking, rotation, equip rules and server authority in the game. The lab's two-container inventory demonstrates this boundary.

Preserve usable cell sizes on small screens. Scroll the board or present containers vertically; do not shrink the complete inventory until cells become hard to select. Distinguish the carried item, candidate footprint, occupied cells and rejection reason. Test a large item at every edge, a move over its own former cells, a conflicting update during a carry, cancellation and a refused server response.

## Table

Use `Table` for records with shared attributes that players compare across rows. Column identity is the reason to use it; item count and spreadsheet-like styling are not.

- Define `columns` with meaningful headings, consistent units, and appropriate formatting. Distinguish unknown from zero and unavailable from an empty string. Keep the object identity visible while comparing another attribute.
- Use `sort` and `onSortChange` for questions that sorting answers. Show direction. A live leaderboard should not keep moving the target under a player's pointer or focus during an action; preserve identity and consider a deliberate update rhythm.
- Use column widths and bounds to preserve essential columns. `widths`/`onWidthsChange` let players refine sustained comparison. Disable resizing for columns whose fixed meaning/geometry requires it. Test the default: resizing is not a repair for an unreadable initial state.
- `header = false` is suitable only when column meanings are already unmistakable. `alternatingRows` can aid scanning a dense comparison; do not depend on stripes to identify selection.
- `scrolls = false` mounts all rows and lets the table size to content. Use it for a short table inside one scrolling page. Otherwise give the table its own bounded viewport.
- Use built-in editor columns for standard field types. Use `CellEditor` in a custom cell when custom presentation needs the same edit lifecycle. Route accepted changes through the model; `onCellChange` is not permission to treat an optimistic proposal as confirmed.
- `children` and `expanded` can represent hierarchical records where comparison still matters. Prefer `Outline` when the tree itself is the principal structure.

On compact screens, retain the columns needed for the current decision. Move supplementary detail behind a named action. If the decision needs several attributes simultaneously, create a compact comparison rather than replacing the table with isolated cards or tiny text.

## Outline

Use `Outline` when records have real parent-child relationships and players need to open branches, select nodes, or manage that hierarchy. Use `DisclosureGroup` for optional sections in a document, and ordinary grouping for categories that need no tree navigation.

`children` defines descendants; `expanded` records open branches; `indent` communicates depth. Keep indentation modest enough that deeper labels remain readable. Preserve stable keys across expansion and updates. Selection and expansion are different operations: opening a branch should not accidentally commit the selected node. Use clear activation behavior and record-specific `rowActions`.

It shares collection editing and reorder/delete proposals. Built-in hierarchy reordering moves same-parent siblings; moving into a different folder requires an explicit drop/command and model validation. Reparenting must respect the hierarchy's rules, including locked parents and invalid descendants. If the tree becomes a maze of deep branches, offer search or a task-focused destination rather than indefinitely shrinking labels.

## Collection editing and bulk actions

Use the built-in collection model for common selection, deletion, and ordering before adding a parallel row interaction system. `reorderable` with `onReorder` and `deletable` with `onDelete` propose changes; the game applies or refuses them. `movable`, `rowDeletable`, `selectable`, and `disabled` express different permissions. A locked item may remain inspectable while refusing deletion.

`selectionMode = "multiple"` permits a set; it does **not** make every tap additive. Ordinary touch/gamepad activation selects one row. With `editing = true`, activation toggles membership without running `onActivate`. Provide Select/Edit and Done. Done preserves the set, but the next plain activation can select just one row. For a persistent multi-choice collection, keep `editing = true`; this does not require delete or reorder commands.

A Table can provide its own edit toolbar in the relevant configuration; a VirtualList using an `editing` cell needs the authored Edit/Done route. Do not assume every collection manufactures the same toolbar. With touch/gamepad, a Table with that toolbar gates cell edits behind editing; editor cells otherwise accept edits when enabled. Collection edit mode and an individual cell being open for text input are separate states.

For bulk operations, show the selection count, operation, and consequence together. Define whether Select All means visible results, all filtered results, or the entire collection. Say which. Preserve or clear selection deliberately when filtering and show hidden selections if they remain part of the command. Mixed eligibility needs a truthful summary, such as “Sell 7 eligible items; 2 equipped items excluded,” before commitment.

Use `selectionFrom` with the authoritative records when shared selection must survive a filtered `from`; otherwise selection is pruned against the visible source. Delete operations also use that wider source, so hidden selections must be included in the review summary. `selectionIndicator = false` only hides edit-selection marks; use it when supplying an equally clear custom indicator, not to remove selection behavior.

Use built-in reordering for ordering within a collection. Use `drag`, `drop`, and `rowDrop` only when transferring objects or dropping onto a meaningful target warrants them. Show source, destination, acceptance, and result. Keep a non-drag move/equip route. Avoid enabling reorder while a sort order contradicts manual placement; explain or disable the conflicting mode.

Use [Adaptive interaction and direct manipulation](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) to design one object-centered operation across input methods, then its drag/drop sections for pickup gestures, collection integration, target validation, armed input, pending responses, and landing feedback. Use [Browsing, search, filters, and sorting](GAME_FLOWS_AND_INFORMATION.md#browsing-search-filters-and-sorting) to design how players narrow the collection.

## CellEditor

Use `CellEditor` for a small value edited in place in a table, list, or grid. `editor` is `text`, `number`, `toggle`, or `menu`. Use number bounds/step for valid increments, and `options` for a constrained categorical value.

Text and number editors begin as labels; they do not force every idle cell to be a text field/focus stop. Pointer, keyboard, touch, and gamepad have supported entry routes. Give `editLabel` a field-specific name when a row has several editable values: “Edit nickname,” not three identical “Edit value” commands. Toggle and menu editors change values directly when enabled.

`enabled` expresses permission; `busy` blocks proposals while validation is pending. An individual `editing` cell controls whether that editor is open, not permission. `validate` returns an error message or nil. Keep error text available for correction. Return/blur commits; cancellation restores an appropriate current value. Do not use blur-to-commit editing for a purchase or other consequential multi-field transaction.

Use a `draft` per record and field outside virtual row lifetime when unfinished text must survive scrolling. Drafts preserve dirty text and errors; external changes can produce a conflict. Do not silently overwrite either the player's draft or the latest accepted value. Clear drafts for deleted records and preserve rejected input for correction. Use a larger editor when the field needs substantial explanation, preview, or coordinated changes.

## RowActions

Use `RowActions`, or a collection's `rowActions` factory, for a few object-level commands that should remain available without permanent full-width buttons. The supplied actions serve swipe, contextual, keyboard, and gamepad routes. Prefer the collection integration to wrapping it in a competing second action mechanism.

- Choose `leading`/`trailing` actions consistently across equivalent rows. Order them by frequency and consequence. Label the actual verb and object where necessary.
- **Full swipe is enabled by default.** Set `fullSwipe = false`, or disable it on the consequential edge, when a gesture must reveal choices rather than commit. A confirmation or undo policy still belongs to the game; do not assume the destructive role creates one.
- `editing = true` removes swipe capture so embedded fields and buttons receive native input and exposes edit actions. `swipeEnabled = false` disables capture without showing those actions. Collection integration suppresses swipe capture while editing. Choose deliberately when rows contain controls: the ordinary swipe grip can route a tap to row selection instead of the embedded button.
- `actionPlacement = "trailing"` suits rows; `"bottom"` suits cards and is used by grid integration. Reserve the necessary space. `actionWidth` must accommodate translated labels, not just icons.
- A shared `coordinator` keeps only one tray open. `open` and `onOpenChange` are useful for controlled presentation; avoid leaving several rows in competing open states.

An open row's content tap closes its tray rather than activating the content. Check that two-step behavior against the frequency of the task. Use a direct visible action for an urgent command that cannot afford discovery or an extra tap.

## Card

Use `Card` when an item is a coherent browsing unit: identity, preview, a few decisive facts, and related actions. Put repeated interactive cards in a collection. A visible panel around every statistic adds boundaries without adding meaning.

Choose `image`/`artwork` and `imageAspectRatio` for the subject. `imageFraming = "fit"` preserves the entire object; `"crop"` gives consistent composition when cropping does not hide distinguishing features. Use `title` and `caption` to establish identity and support; do not duplicate every value already shown in an adjacent detail pane.

`onActivate` needs one clear card-level meaning. `primaryAction` exposes a distinct main command; `menu` holds secondary object commands. Avoid a card click that buys while its visible button merely previews. `reveal = "always"` suits actions that must remain discoverable; automatic reveal must still work for touch and focus. `ringTarget = "card"` or `"media"` chooses the focus boundary—make the highlighted object match the actionable target. Use `browseTarget` only with a deliberate browsing/focus relationship.

## Button

Use `Button` for an immediate verb: Start, Equip, Retry, Open details. Use `Toggle` for a persistent binary state and `Picker` for choosing a value.

Choose `appearance` from the game's action hierarchy:

| Appearance | Design purpose |
| --- | --- |
| `emphasis` | The principal action in this decision area; competing emphasis buttons weaken the hierarchy |
| `standard` | A normal clearly actionable command |
| `soft` | A quieter supporting action that still benefits from a visible surface |
| `utility` | Compact supporting chrome or an iconic command; preserve discoverability without a plate |
| `link` | A text-led action with link-like treatment, often opening further information |
| `inverse` | A contrasting plate over a surface/art treatment that needs the inverse color relationship |

Use `role = "destructive"` for a harmful consequence and `"cancel"` for abandoning the current operation. A destructive color is not sufficient disclosure. `dialogAction` identifies default/cancel behavior within a dialog; choose a safe and expected default. `selected` describes a persistent selected state, not focus or busy state.

Use `label` for a meaningful verb and `subtitle` for brief necessary context. `compactLabel` applies to plain text buttons, not icon/image/subtitle buttons; use it only when its shorter wording stays clear. `disclose` can expose a truncated full label through help routes, but required command meaning should remain visible. Icon-only buttons need names and recognizable meaning. `shape = "circle"` suits a compact iconic action; a longer phrase needs a rectangular target. `controlSize` and `target = "thumb"` can support frequent touch gameplay actions; preserve space between targets as well as their size.

Use `busy` to communicate a pending request and prevent unintended repetition. Use `enabled`/`disabled` for availability, with a discoverable explanation when the player reasonably expects the action. A `shortcut` accelerates a visible command. `help` supplements the label; `hint` can explain what is needed. Neither should conceal a cost or irreversible consequence.

`repeatDelay`/`repeatInterval` fit intentionally repeatable adjustment, not purchases or invitations. Pointer down/up/cancel hooks suit a genuine hold interaction; design interruption and cancellation, not only successful release. `haptic`, `pop`, and other feedback should reinforce a meaningful action rather than animate every navigation step.

## Skill trees and growing maps

Use `ZoomView` with keyed `Button` children for an authored skill tree. Keep node
positions and prerequisites in the game model. Use `SpatialGrid` when items
occupy cells, not to place a graph. Revealing nodes must preserve existing tile
identity and the player's camera position.

Selecting a tile shows its benefit, cost and prerequisite before spending points.
The selected tile can become an explicit unlock action; a remote purchase button
is not required. On touch, first tap inspects and a second activation commits.
Gamepad focus inspects and A commits. Reveal new nodes only after acceptance.
Keep the map large on small screens and use a compact persistent detail strip;
a hover tooltip alone does not work across inputs. Set native directional
selection links from the graph's positions and keep the focused tile in view.

Artwork can extend beyond the native rectangular button. Keep adjacent targets
separate and test them at minimum zoom. Use theme colors and motion tokens for
state feedback. Preserve labels or emblems as well as color for locked,
available, selected and owned states. Apply the shared guidance on
[matching feedback to the visible target](INPUT_FOCUS_AND_ACCESS.md#match-feedback-to-the-visible-target).
Check reduced motion and all input modes.

## SplitButton

Use `SplitButton` when one clear primary verb has related alternatives, such as Play with alternate match entry commands. `onActivate` performs the primary action; `items` contains the alternatives. If choices are peers, use `Menu` or visible buttons instead.

Give `menuLabel` a meaningful name. Pointer/gamepad presentation separates the primary and menu parts; touch uses tap for the primary action and long press for alternatives. Consequently, a critical alternative may need a separate visible route. Do not put the only way to avoid a consequential default behind an undisclosed long press. `busy` and `enabled` should reflect the operation's availability consistently.

## Menu

Use `Menu` for a short set of named commands. Use `Picker` when the main meaning is “choose this value,” even if the eventual presentation looks like a menu. Use a destination when choices require substantial comparison or editing.

- Supply a visible label trigger or attach to an existing `trigger`; do not supply both. `triggers` can include `activate`, `secondary`, `longPress`, `keyboard`, and `gamepad`. Limit routes only for a concrete conflict, preserving discoverable access.
- Start with `presentation = "automatic"`. It adapts between a floating menu and a sheet, including replacing submenu rows rather than cascading for touch/gamepad. Force `"menu"` or `"sheet"` only when the intended interaction and room justify it.
- Keep a clear Close route. `closeButton` changes explicit dismissal; `backLabel` names return within sheet submenus. Back through menu levels and closing the underlying task are different operations.
- Use stable item IDs, useful labels, `enabled`/`hidden` deliberately, and shallow `children`. `sectionTitle`, `meta`, `badge`, and avatar information should help choose, not turn each command into a miniature dashboard.
- `query` can help locate a longer set, but a large taxonomy may deserve a destination. `maxHeight` and width should preserve legibility and scrolling rather than compressing commands.
- A displayed `shortcutLabel` does not bind the shortcut. Connect actual command bindings once, then display the truthful hint.

## RadialMenu

Use `RadialMenu` when a small, frequently used, stable command set benefits from directional recognition. Players should recognize positions faster than they can scan a list. A starting set of roughly four to eight choices is a useful design trial, not a limit or an assurance of usability. Long labels, high stakes, and extensive comparison favor a linear menu or detail view.

Keep direction assignments stable. Do not sort by recent usage or remove a temporarily unavailable choice if doing so shifts learned commands. Show the disabled slot and its reason through a suitable accessible route. Keep categories shallow; a wheel of wheels can lose its speed advantage.

### Ownership and placement

Anchoring expresses ownership; a corner preset expresses geometry. Global quick emotes may use a stable corner launcher. Inspect, Invite, and Follow for one racer should remain associated with that racer's portrait or target representation. An avatar near a screen edge still owns its contextual commands.

`preset = "donut"` gives a full ring; the four corner presets open inward from that corner. Use a corner only when its arc avoids movement/camera controls and the player's hand. Use `anchor` for the relevant GUI object or screen point. A stable portrait is often a better selection anchor than a moving world avatar.

Choose `follow` deliberately: `fixed` keeps placement fixed, `idle` avoids chasing active interaction, and `always` follows changes. A moving target must not make options chase the finger. Preserve the target identity while open; if it disappears, invalidate or close the task rather than silently selecting another target. `clearance` should protect room around the anchor and adjacent controls.

### Configuration that changes the decision

| Option | Design choice |
| --- | --- |
| `distribution = "even"` / `"compass"` | Even spacing suits a balanced ring; compass placement suits learned directional associations. Check reserved Back/Close space. |
| `navigation = "replace"` / `"expand"` | Replace keeps one level readable in limited room; expand retains spatial hierarchy at a greater area and attention cost. |
| `expansion = "fan"` / `"ring"` | Choose how expanded levels relate geometrically, then test reach, occlusion, and target size. Do not add depth just because space exists. |
| `completion = "close"` / `"stay"` / `"back"` / `"root"` | Close after a completed quick command; stay for intentional repeated adjustments; back/root when another related selection should follow. |
| `center` | Default `back` provides Close at root and Back below. `content`, `empty`, `root`, or `close` changes where those controls fit. Corner presets keep Back/Close at the corner. Account for the control's reserved space. |
| `gestureSelection = "bounded"` / `"direction"` | Bounded selection requires the item region; directional selection supports a learned directional gesture. Test accidental selection and cancellation rather than assuming either is universally faster. |
| `holdAction` / `launcher` | A bound hold can accelerate practiced use; retain a discoverable route without sustained hold. `launcher = false` requires another opening route. |
| `appearance = "wedges"` / `"buttons"` | Wedges emphasize directional sectors; buttons emphasize discrete objects. `buttonSurface` changes their visual boundary, not their need for clear targets. |
| `ringWidth` / `contentFit` | Preserve targets and readable content. `contentFit` defaults to `radial`; `both`, `angular`, or `none` changes the fitted geometry. Do not squeeze the ring to avoid its list fallback. |
| `scrim` / `centerPassThrough` | An open radial is modal and blocks the page. `scrim = "none"` does not mean nonmodal. A dark scrim strongly obscures the game; use it only when that interruption is intended. Center pass-through needs deliberate testing of the exposed interaction. |

Ring items show an icon or a label, not both; the list fallback can show both. Use recognizable icons with full names available and test long labels. Facet falls back to a list when the ring cannot present its content; preserve the commands and target identity in that form.

Opening a wheel does not pause gameplay. Check whether selection consumes a stick or finger still needed to move, steer, or aim. Keep an immediate life-critical action direct. Test tap-to-open, hold/drag selection, digital focus navigation, Back, release without selection, and target loss. A beautiful wheel that causes accidental actions or hides hazards fails its task.
