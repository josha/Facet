# Layout and navigation

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Choose a container for the relationship it expresses. Layout, navigation, and interruption are separate decisions: a stack can arrange a sheet's contents, but it does not make the sheet the right surface.

## Choose the structure first

| Relationship | Starting choice | Example |
| --- | --- | --- |
| Different sections read in order | `VStack` | Personal result, rewards, standings, Continue |
| One compact unit read across | `HStack` | Icon, item name, quantity |
| A small static two-dimensional arrangement | `Grid` | Four summary metrics |
| Repeated objects browsed or selected | `VirtualList` or `VirtualGrid` | Quests or paint previews |
| The same attributes compared across records | `Table` | Racers, lap times, penalties |
| An actual parent-child hierarchy | `Outline` | Folders of saved builds |
| Peer destinations | `TabView` | Garage, Events, Profile |
| An increasingly specific path | `NavigationStack` | Inventory → item → modification |
| A collection and its selected detail | `NavigationSplitView` | Vehicles beside the selected vehicle |
| Several HUD groups competing for room | `Composition` and `Region` | Driving controls, route, standings |

The difference between a stack and a table is **sequence versus comparison**. Three vehicles can justify a table; twenty independent settings need not. Shared column identity lets a player scan one attribute across records. A single object's label-value specification can use aligned rows without becoming an interactive table.

A results page can contain a `VStack` with a bounded `Table` inside it. The stack orders sections; the table compares records. When compacting that table, preserve the comparison that justified it. Retain essential columns or provide a deliberate current-versus-candidate comparison. Isolated cards do not preserve simultaneous comparison merely because they contain the same facts.

## Screen

Use `Screen` as a screen-level content root. It stacks content vertically and accounts for safe room. Do not add another screen root just to give a panel padding.

- Keep `chrome = "device"` for ordinary interactive screens: it clears device obstructions, the engine top band, and distant-view margins.
- Use `chrome = "band"` only for an intentionally designed row in the free top band. That row must avoid occupied controls; removing padding is not permission to overlap them.
- Use `chrome = "edge"` for intentional edge-reaching artwork. It removes those additional clearances; separately keep text and interactions safe. The native root's insets must also permit the intended artwork.
- Use `maxWidth` to keep a reading or decision column comfortable on a wide view. Use `padding` for the game's own persistent chrome and breathing room, not dozens of child offsets.

## Composition and Region

Use `Composition` when several HUD groups share space and must yield by importance. Give each coherent group a `Region`. Use an ordinary stack for the contents of one panel.

- `zone` identifies a region's home; `rank` determines precedence when space conflicts. Lower numbers matter more. This is spatial priority, not a global notification priority or draw order.
- Supply region forms from richest to smallest, with measurable content sizes. A form that fills all offered space cannot communicate its intrinsic requirement. Each form must still answer a useful player question.
- `mayDrop = true` permits the region to disappear from the main view. Never apply it to an immediate required action without an equally immediate usable alternative.
- `reveal` exposes reduced/hidden information through Facet's reveal affordances. Keep it unless nothing meaningful was omitted or another discoverable route exists. `expand` supplies the expanded content when the default richest form is unsuitable.
- Bind `form` when other UI must react to the chosen form; `0` means hidden. Do not treat every nonzero value as an authored form index: reveal affordances can add another form.
- `leading` concerns a topbar region. `Composition.topbar`, `padding`, and `gap` should express an intentional top band and spacing, not compensate for unrelated absolute positioning.

Do not put a second independent width-based content switch inside each measured form. Let the composition choose among forms with predictable sizes. Test simultaneous warnings, overlays, and maximum content; each region fitting alone proves little.

## VStack and HStack

Use `VStack` for a reading sequence or vertically grouped controls. Use `HStack` for a tightly related horizontal unit. Prefer a vertical structure when labels may be long or every item needs its own explanation.

- `gap` communicates relationships; tighter within a unit, larger between sections. `padding` gives the group an interior boundary.
- `align` works across the stack; `distribute` works along it. Use `spaceBetween` for genuinely opposing ends such as a label and value, not to scatter a form evenly through every screen height.
- `width`/`height = "hug"` express content size; `"fill"` accepts offered space. Give a long reading column a width constraint and let its height grow. Give a scrolling collection a bounded remaining height.
- `wrap` is off by default. Explicit wrapping can suit independent chips; use `AdaptiveStack` or authored alternatives when a complete row should become a column. Verify reading and focus order after wrapping.

Do not align separate records by inserting spaces into text or by giving every row unrelated offsets. Use shared layout or a table when alignment carries meaning.

## Grid

Use `Grid` for a small static arrangement requiring rows and columns. Use `VirtualGrid` when the objects need collection selection, recycling, row commands, or reordering.

Choose `columns` from the minimum useful cell width, not a preferred screenshot. Set `aspectRatio` when the visual object genuinely has a fixed shape; set `cellHeight` only when content extremes fit it. `rowGap` can separate rows more than columns. `flow` changes how items fill the grid: preserve the intended reading sequence and input traversal.

## ZStack

Use `ZStack` for intentional layers of one object: artwork and its badge, a meter and its label, or a preview with controls. Use `alignH`/`alignV` to attach those layers consistently and `padding` to protect them from the edges.

It is not an overlap repair. Independent text sections need allocated space. A decorative layer must not intercept the action beneath it; a badge must not cover the identifying part of an image. Check every layer against bright and dark artwork.

## Spacer and Divider

`Spacer` distributes spare room; `minLength` preserves a minimum separation. Use it between genuinely separate groups, such as navigation and a trailing action. Avoid filling a screen with fixed spacers to imitate one target size.

`Divider` marks a meaningful boundary within an otherwise continuous surface. Use `axis` to match that boundary, `appearance = "strong"` only for stronger separation, and `thickness` sparingly. Prefer spacing when the groups are already obvious. Dividers between every small element make scanning harder.

## ScrollView

Use `ScrollView` for a bounded document, form, or mixed-content page. Choose `axis = "y"` for ordinary reading; `"x"` for a deliberate horizontal strip; `"xy"` for content whose two-dimensional position matters. A map usually needs `ZoomView` as well as pan behavior rather than a tiny fully visible image.

Keep necessary task context and commitment actions reachable. Let the body scroll without making the title and Close action vanish unnecessarily. Avoid a collection's own scrolling inside another scroll view on the same axis. A short table can use `scrolls = false` inside one page scroll; a large table should own its bounded viewport.

Scrolling makes the scrolling axis unbounded to content. This changes fit decisions: a fit container cannot discover a small width requirement from an unbounded horizontal canvas. Test with the software keyboard, large text, and the last item focused.

## AdaptiveStack

Use `AdaptiveStack` when the same content can change from a row to a column while keeping its meaning. Without an explicit `axis`, it uses a row while that row fits and a column when it does not. Children remain mounted, preserving local state and focus.

Set a bound `axis = "x"` or `"y"` only when the task has a better explicit rule. Its current public configuration has no `breakpoint` option. `align` remains cross-axis and `distribute` main-axis after the turn. Use `ViewThatFits` when compacting needs different content, and region forms when several HUD groups compete.

## ViewThatFits

Use `ViewThatFits` for one local group with several authored valid arrangements: full action labels, shorter labels, then a clearly named menu. Order children from preferred to compact. It chooses the first that fits; **the last still displays if none fits**.

Constrain the relevant `width` and `height`, and make the final alternative usable at the smallest supported room. A fill-sized candidate can appear to fit regardless of its actual content; a hug axis or scrolling axis may be unbounded. This control selects layouts, not semantic priorities. It cannot invent which information may be removed.

## TabView

Use `TabView` for a small set of stable peer destinations the player revisits. Use a `Picker` for a setting within a destination and `StepIndicator` for task progress.

- Start with automatic `placement`. Override to `topBar`, `sidebar`, `bottomBar`, or `bottomBarCompact` only for a specific composition or input need. `placement = "none"` hides navigation but preserves selection and shoulder behavior; provide another obvious route to every required destination.
- `style = "sidebarAdaptable"`, `sidebarPreference`, and `railWidth` tune destination navigation where a rail is useful. `sidebarExpanded` supports an explicitly opened sidebar in a distant viewing arrangement. Do not equate that arrangement with every gamepad session.
- `style = "collapsible"` replaces the visible strip with a menu in the top band. Use it when secondary destination navigation can trade simultaneous visibility for working room; avoid it for peer destinations that must remain discoverable at a glance.
- `retention = "all"` keeps visited content; `"top"` disposes departing pages. Choose based on cost and expected return behavior, while keeping durable selection and drafts in the model.
- Keep useful `restoreFocus` and `restoreScroll` behavior. `shoulderNavigation = "strip"` switches while focus is in the tab strip and wraps its ends; `"content"` also works from page content and stops at the ends. Choose the scope deliberately so it does not compete with content or gameplay bindings.
- `labelPlacement = "belowIcon"` can clarify compact destination bars. Use `iconOnly` only for reliably recognizable destinations with names available. `indicator`, `indicatorPlacement`, and `track` change selection paint and geometry; never remove the only visible selected-state cue.
- Use `sections` and `customization` for substantial destination sets that benefit from organization. Custom ordering must not make essential destinations inaccessible. A tab's status indicator communicates new state; it must not be mistaken for the selected-tab marker.

## NavigationStack

Use `NavigationStack` for a meaningful path from overview to detail and deeper tasks. Its `path`, `root`, and `destinations` represent that history. Back should return to the state that led here, including the useful collection position.

Keep `chrome = "automatic"` unless supplying a complete alternative navigation treatment. `"hidden"` requires an obvious Back path and an understandable title/context. Use `backLabel` to name the return when needed. Keep transitions modest, and disable them when motion would distract or delay repeated work. Do not push a new page for every small setting adjustment.

## NavigationSplitView

Use `NavigationSplitView` when a selection in one pane determines related detail in the other. Two unrelated panels do not create a master-detail relationship.

- Use `axis = "x"` for adjacent panes, `"y"` only when a top/bottom relationship serves the content.
- Set minimum sidebar and detail widths/heights from actual readable content. `compactWidth` or `compactHeight` establishes when the pair should become one pane. Do not preserve two unreadable panes just because the display has many pixels.
- `preferredCompactColumn` should move to detail on a deliberate selection and back to the list on Back. Preserve the selected record through the transition.
- `resizable` and sidebar size cells support sustained comparison work; bounds prevent one pane becoming unusable. Show a permanent resize handle only when that affordance matters.
- `detailVisible` removes the detail region when it has no useful role. An empty selection can instead show a purposeful detail placeholder if that teaches the relationship.

## NavBar

Use `NavBar` to organize a screen's title, Back, and a small number of contextual commands. It arranges chrome; it does not own navigation history. Connect `onBack` to the actual navigation/task model.

Use `leading`, `center`, and `trailing` deliberately: a long title must not collide with actions. `titleSize` expresses hierarchy; `surface` (`surface`, `panel`, `pane`) should match the region the bar belongs to. A custom `center` should still communicate location. Do not put every screen command in the trailing slot; move secondary commands to a menu.

## PageView

Use `PageView` for a sequence best consumed one page at a time: a short story recap or inspectable set of featured items. Use a list or table for comparison and tabs for named destinations.

Keep `selection` stable. `controls` provide explicit navigation; do not rely solely on swiping. `indicators` communicate position in a short sequence; `summary` can communicate current page context. Avoid a long string of tiny dots. Do not automatically advance a page the player is reading or interacting with.

## Pagination

Use `Pagination` when the data or task has meaningful bounded pages, such as archived match results. Do not split a small set merely to reduce height; scrolling may be simpler.

`form = "numbers"` supports jumping to known pages; `"arrows"` suits sequential movement; `"label"` emphasizes position. Supply honest `pageCount`, `hasNext`, and `hasPrevious`; an unknown total should not appear exact. `boundaryCount`, `siblingCount`, and `showFirstLast` trade navigation shortcuts against width. Keep filters and sorting stable across page changes and reset to a valid page when results shrink.

## StepIndicator

Use `StepIndicator` for progress through a task with named stages: create event, configure rules, review. It is neither a percentage meter nor a substitute for destination tabs.

`current` identifies the stage. `onSelect` makes stages navigable; supply it only where revisiting is valid and define what happens to unfinished edits. Keep unavailable stages visibly unavailable rather than pretending they can open. `sizing = "hug"` suits compact summaries; `"fill"` suits a dedicated workflow. `listLabel` should make an alternate list of stages understandable. Do not use a stepper for a task that can sensibly be one short form.

## ZoomView and Path

Use `ZoomView` when spatial relationships must survive inspection at different scales: a course map, skill tree, or build board. Keep one stable content tree and a truthful `contentSize`. Set `minZoom` so the overall structure can be understood and `maxZoom` so inspection stays useful. `doubleTapZoom` should offer a useful second scale; `focus` should reveal the current target without repeatedly pulling the view away from the player. Expose zoom/reset routes through its controls for players who cannot use a pinch gesture. Never hide required global navigation inside the zoomed canvas.

`Path` draws a line through points. It is useful for routes, connections, or trajectories; it is **not** a breadcrumb/navigation control. Use `closed` only for a closed shape. `thickness`, `role`, and `tint` should keep a meaningful route legible without overpowering its nodes. A line alone cannot explain direction, ownership, completion, or a selectable destination: add the necessary labels and state cues.
