# Collections and actions

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md).
Choose the relationship between object, selection and command before choosing a
surface. Exact signatures are in the installed API docs.

## Separate focus, selection, activation, editing, and commitment

Focus receives input; selection identifies the candidate/set; activation opens or
acts; editing changes values or management mode; commitment applies an outcome.
Keep these meanings distinct across inputs. For example: selection previews,
Equip commits, Back preserves accepted equipment. Moving focus must not buy an
object or retarget a pending request.

## Choose how an action is exposed

| Need | Pattern and boundary |
| --- | --- |
| One obvious inexpensive result | Row `onActivate`; no silent spending or deletion |
| Frequent object command | Visible Button; avoid several repeated buttons per row |
| One short independent field | Table editor or CellEditor |
| Coupled fields/consequential change | Coherent draft editor and explicit Apply/Cancel |
| Inspect/compare before action | Selection, nearby identity/facts and named command |
| Act on a set | Multiple selection, explicit Select/Done, count and scope summary |
| Rare object commands | Menu or collection `rowActions`, with visible discovery |
| Dominant verb plus related variants | SplitButton; use peers when none dominates |
| Small stable learned command set | RadialMenu; use a list for reading/comparison |

Equivalent rows, menus and shortcuts invoke the same semantic commands and rules.

### Row action versus direct editing

Use an action for a verb on an object and an editor for its value. Repeated tuning
benefits from direct editors; a rare Rename can open a field from an action menu.
Do not independently commit fields whose combined terms need approval.

### Select then button

A separate command is useful when selection enables preview, comparison,
eligibility review or set construction. Put target identity and consequences
beside it. Disable invalid targets with a useful reason. Bind the command to the
selected key through sorting/refresh; invalidate it if that record disappears.

### Context menus

A menu belongs to its opening object. Define whether a command acts on that row
or the selected set; never silently widen Delete. Secondary click/long press
supplement a visible Actions route. Keep frequent essential commands direct,
relevant unavailable commands explainable and meaningless commands hidden.

## VirtualList

Use for descriptive records or repeated item actions, including short collections
that need selection/reorder. A VStack fits a few unrelated sections.

- Stable `key` values preserve identity. `selectionMode` is `none` for activation,
  `single` for a candidate and `multiple` for a set; focus remains distinct.
- Vertical reading suits descriptions; horizontal strips need visible access to
  more content and a bounded other axis.
- `measure`/`measured` supports varying content. Fixed `itemSize` must accommodate
  large text and actions. Keep drafts/expansion/selection outside recycled rows;
  `mode = "all"` is only for deliberately small bounded data.
- `focusPolicy = "key"` preserves objects; index policy fits positional identity.
  Choose useful `initialFocus`, avoid focus-stealing updates and use `wrapFocus`
  only when cycling is predictable.
- `follow = "end"` suits live feeds but must respect reading position. Use
  `scrollReset` for context changes, not refreshes. `onReachEnd` can request more;
  distinguish loading, end and retry.

## VirtualGrid

Use for visual recognition; choose list for descriptions or Table for shared
attributes. It shares list selection/editing/focus behavior. Set `columns` or
`minColumnWidth` from usable art, text and targets; reduce columns before
compressing content. Preserve separation with `gap`/`crossGap`.

`itemSize = "cards"` with `cards` options (`perView`, `minWidth`, `peek`) supports
intentional browsing. A peek suggests more, not a complete navigation route.
Use `snap = "item"` for deliberate item steps and `none` for scanning.
`contentOverflow = "visible"` permits effects, not escaped labels or overlapping
hit targets.

`slots` reserves positions by item key, leaving a nonselectable recess while an
item is absent; it does not create typed equipment sockets. Release reservations
when compaction is intended. `slotControls` exposes anchors for Travel; requiring
every anchor implies a deliberately small all-mounted collection. Keep a
non-drag route.

## SpatialGrid

Use when cell placement is part of inventory play. Keyed items use one-based
`{ column, row, width, height }` footprints. The control supplies rectangular
placement and existing pointer/touch/keyboard/gamepad drag/drop; update the model
from `drop.onDrop` with `info.placement`. The game owns stacking, rotation,
equipment rules and server validation.

Keep cells usable by scrolling or stacking containers, rather than shrinking the
whole board. Distinguish carried item, candidate footprint, occupied cells and
rejection. Test edges, former cells, conflicting updates, cancellation and refusal.

## Table

Use for comparing shared attributes, not merely many records.

- Give `columns` clear headings, units and formatting. Distinguish unknown, zero
  and unavailable; keep identity visible beside compared attributes.
- `sort`/`onSortChange` need truthful direction and stable operation during live
  updates. `widths`/`onWidthsChange` can support sustained comparison; resizing
  must not be required to repair the initial layout.
- Hide `header` only when meanings remain clear. `alternatingRows` aids scanning,
  not selection identity. Preserve decisive columns in compact form; use a compact
  comparison if they must remain simultaneous.
- `scrolls = false` mounts all rows for a short table inside one scrolling page;
  otherwise provide a bounded viewport.
- Use built-in editor columns or CellEditor for their edit lifecycle. Route
  `onCellChange` proposals through the model; they do not establish server acceptance.
- `children`/`expanded` supports hierarchical comparison; choose Outline when the
  tree is the main structure.

## Outline

Use for real parent-child records; DisclosureGroup fits optional document
sections. `children`, `expanded` and modest `indent` express the hierarchy.
Preserve keys and distinguish expansion from selection/commitment.

Built-in hierarchy reorder moves same-parent siblings. Moving to another parent
needs an explicit command/drop and model validation, including locked parents
and invalid descendants. Offer search or a focused destination when depth becomes
hard to navigate, rather than compressing labels.

## Collection editing and bulk actions

Use built-in selection/delete/reorder. `onReorder` and `onDelete` propose changes;
the game accepts or refuses. `movable`, `rowDeletable`, `selectable` and `disabled`
represent different permissions: an item can remain inspectable but undeletable.

`selectionMode = "multiple"` does not make every tap additive. Ordinary touch or
gamepad activation selects one row. `editing = true` toggles membership and
suppresses `onActivate`: provide Select/Edit and Done. Done preserves the set,
but the next plain activation can select one row. Persistent multi-choice needs
`editing = true`, without requiring delete or reorder.

A Table can provide an edit toolbar in the relevant configuration; a VirtualList
bound to an `editing` cell needs an authored Edit/Done route. With touch/gamepad,
that Table toolbar gates cell edits behind edit mode; otherwise enabled editor
cells accept edits. Collection mode and an open cell editor are separate states.

Show bulk count, scope, operation and consequences together. Define Select All as
visible, filtered or entire data. Explain hidden selections and mixed eligibility.
`selectionFrom` retains selection against authoritative records when `from` is
filtered; without it, selection is pruned to the visible source. Delete also uses
the wider source. `selectionIndicator = false` hides marks, not behavior; supply
an equivalent visible indicator.

Use reorder within a collection and `drag`, `drop`, `rowDrop` for meaningful
transfers. Do not combine manual reorder with a contradictory sort. Keep a
non-drag route and validate destination/result. See [direct manipulation](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md)
for input and landing behavior, and [search/filtering](GAME_FLOWS_AND_INFORMATION.md#browsing-search-filters-and-sorting)
for narrowing data.

## CellEditor

Use for one short in-place value: `editor` is `text`, `number`, `toggle` or `menu`.
Number bounds/step and menu `options` constrain values. Text/number begin as labels
rather than making every idle cell a text field. Give `editLabel` a field-specific
name; toggle/menu change directly when enabled.

`enabled` is permission, `busy` blocks pending proposals and `editing` controls the
open editor. `validate` returns an error message or nil. Return/blur commits;
cancellation restores a current value. Consequential coupled fields need a
separate explicit commitment.

Keep `draft` per record/field outside virtual row lifetime when unfinished input
must survive scrolling. Preserve rejected input and handle conflicts with newer
accepted values; clear deleted records' drafts. Use a larger editor for substantial
explanation, preview or coordinated changes.

## RowActions

Use collection `rowActions` or RowActions for a few object commands with swipe,
contextual, keyboard and gamepad access. Prefer integration over a competing row
interaction system.

- Order `leading`/`trailing` actions consistently by frequency and consequence.
  **Full swipe defaults on**: set `fullSwipe = false` on consequential edges if
  swipe should reveal rather than commit. Destructive role supplies no confirmation.
- `editing = true` removes swipe capture and exposes edit actions;
  `swipeEnabled = false` removes capture without showing them. Collection editing
  suppresses swipe capture. Otherwise the grip can route a tap to row selection
  instead of an embedded button.
- `actionPlacement = "trailing"` suits rows; `bottom` suits cards/grid integration.
  Reserve room and fit translated labels in `actionWidth`.
- A shared `coordinator` keeps one tray open; `open`/`onOpenChange` controls it.
  Tapping open-row content closes the tray instead of activating it, so urgent
  actions should have a direct route.

## Card

Use for one coherent object: identity, art, decisive facts and related actions.
Put repeated interactive cards in a collection; do not box every statistic.
`imageFraming = "fit"` preserves the object, while `crop` can normalize composition
when distinguishing features survive. Choose `imageAspectRatio`, `title` and
`caption` for recognition without repeating adjacent detail.

Give `onActivate` one clear meaning, `primaryAction` the main command and `menu`
secondary commands. `reveal = "always"` keeps essential actions discoverable;
automatic reveal still needs touch/focus access. `ringTarget = "card"` or `media`
must match the actionable boundary; `browseTarget` needs a deliberate focus relationship.

## Button

Use for a verb; Toggle changes a persistent binary state and Picker chooses a
value. Use `appearance = "emphasis"` for the main command, `standard` for ordinary
commands and quieter `soft`, `utility` or `link` where appropriate. `inverse`
provides contrast over suitable art/surfaces. `role = "destructive"` names harm;
`cancel` abandons work. `dialogAction` chooses safe default/cancel behavior.
`selected`, focus and busy are distinct.

Name the command with `label`; `subtitle` supplies necessary context.
`compactLabel` works only for plain text buttons, not icon/image/subtitle buttons.
`disclose` exposes truncation through help; essential meaning stays visible.
Icon-only controls need recognizable symbols and names. Circle fits a compact
glyph, not a long phrase. Use `target = "thumb"` for frequent thumb gameplay and
preserve separation as well as target size.

`busy` prevents repeated pending work; availability needs `enabled`/`disabled` and
an understandable restriction. A `shortcut` accelerates a visible command;
`help`/`hint` supplements it without hiding terms. Repeat timing fits adjustment,
not purchases/invitations. Genuine hold hooks need cancellation/interruption.
Use feedback to explain meaningful action rather than animate every navigation.

## Skill trees and growing maps

Use ZoomView with keyed Buttons for a graph; keep positions/prerequisites in the
model. SpatialGrid is for cell occupancy. Preserve tile identity and camera
position as nodes appear. Show benefit, cost and prerequisites before spending;
on touch a first tap can inspect and a second activation commit, while gamepad
focus inspects and A commits. Reveal ownership only after acceptance.

Keep a usable map and compact persistent detail on small screens; hover alone
is insufficient. Set native directional selection links from graph positions
and keep focus in view. Separate neighboring targets at minimum zoom. Distinguish
locked, available, selected and owned with labels/emblems as well as color, and
follow [visible-target feedback](INPUT_FOCUS_AND_ACCESS.md#match-feedback-to-the-visible-target).

## SplitButton

Use for one dominant verb plus related variants (`onActivate`, `items`); use Menu
or visible peers otherwise. Name `menuLabel`. Pointer/gamepad separate the parts;
touch taps the main action and long-presses alternatives. An important alternative
needs visible discovery, especially when it avoids a consequential default.
Reflect operation state consistently through `busy`/`enabled`.

## Menu

Use for a short command set; Picker selects a value and a destination handles
substantial comparison/editing. Provide either a label trigger or existing
`trigger`, not both. Preserve discovery across `activate`, `secondary`,
`longPress`, `keyboard` and `gamepad` routes unless a concrete conflict requires otherwise.

Start with `presentation = "automatic"`: it adapts floating/sheet presentation
and replaces submenu rows for touch/gamepad. Force a form only with a task/space
reason. Keep Close distinct from submenu Back (`closeButton`, `backLabel`). Use
stable IDs and shallow `children`; `enabled`, `hidden`, sections and metadata
should clarify commands. Bound width/`maxHeight` and scroll long sets; `query`
helps search but does not make a large taxonomy a good menu. `shortcutLabel`
displays a hint; it does not bind a shortcut.

## RadialMenu

Use for a small, stable, frequent set recognized by direction. Reading,
consequences and comparison favor a linear menu/detail. Keep direction assignments
stable, including unavailable slots and their explainable restrictions. Avoid deep
wheels of wheels.

### Ownership and placement

A global command may use a corner launcher; an object command stays attached to
its portrait/representation. `preset = "donut"` makes a full ring; corner presets
open inward. Choose `anchor`/`clearance` to avoid hands, movement and camera controls.
A stable portrait may serve better than a moving avatar.

`follow = "fixed"`, `idle` or `always` controls movement; avoid chasing an active
finger. Preserve target identity and close/invalidate on target loss.

### Configuration that changes the decision

| Options | Design consequence |
| --- | --- |
| `distribution`: `even` / `compass` | Balanced spacing versus learned directions; reserve Back/Close |
| `navigation`: `replace` / `expand`; `expansion`: `fan` / `ring` | One readable level versus retained hierarchy at greater area/reach cost |
| `completion`: `close` / `stay` / `back` / `root` | Finish, repeat adjustment or return to a related level |
| `center` | Default `back` gives root Close and nested Back; other content/modes must preserve exits and reserved space; corners retain corner exits |
| `gestureSelection`: `bounded` / `direction` | Item-region selection versus learned direction; test accidental selection and cancellation |
| `holdAction` / `launcher` | Hold can accelerate expert use; `launcher = false` requires another discoverable opening route |
| `appearance`: `wedges` / `buttons`; `buttonSurface` | Directional sectors versus discrete objects; all need clear targets |
| `ringWidth` / `contentFit` | Fit targets/content; default `radial`, alternatives `both`, `angular`, `none`; allow list fallback instead of squeezing |
| `scrim` / `centerPassThrough` | Open radials are modal even with `scrim = "none"`; test any exposed center interaction |

Ring items show an icon or a label; the list fallback can show both. Keep full
names accessible and preserve commands/target in fallback. Opening does not pause
play: test stick/finger conflicts, tap/hold/drag, digital navigation, Back, empty
release and target loss. Keep life-critical actions direct.
