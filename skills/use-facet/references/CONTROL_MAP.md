# Control map

Part of [game UI design](GAME_UI_DESIGN_GUIDE.md).

This map lists every Facet control by the level it serves.  Choose by the decision, compare the nearest alternative, then read the control's card (`<Control>.card`) and only the options you still need.  The options named here are the ones that most change the result; the card and its props node hold the rest.

## Flow and navigation

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| NavigationStack | A path into detail with Back, and destinations opened from play | Peers that players revisit: TabView | `path`, `destinations`, `backLabel`; `Custom-transitions` |
| TabView | Peer destinations that players revisit; the bumpers switch them | Depth: NavigationStack.  Editing a value: Picker | `selection`, `placement` (automatic follows room and input), `retention` |
| NavigationSplitView | A collection whose selection decides the detail beside it | Two unrelated panels: separate surfaces | `preferredCompactColumn`, `minSidebarWidth`, `minDetailWidth`, `compactWidth`, `axis` |
| NavBar | A page's title, Back and commands | A HUD: Composition | `title`, `onBack` (never on a root), `leading`, `trailing` |
| PageView | A short sequence to inspect in order | Result pages: Pagination | `selection`, `pages`, `indicators`; offer buttons as well as swipes |
| Pagination | Bounded pages of results that the game fetches | A continuous list: a virtual collection | `page`, `pageCount`, `form` |
| StepIndicator | The stages of one task | Destinations: TabView | `steps`, `current`, `onSelect` |

## Surfaces

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| Composition and Region | Every HUD group during play, ranked, with smaller forms, including the top bar strip | A page: Screen | Region `zone` (including `topbar`), `rank`, forms richest first, `mayDrop`, `reveal`, `leading`, `trailing` |
| Screen | The root of a page, inside safe margins | A HUD: Composition | `chrome` (`device`, `band`, `edge`), `padding`, `gap` |
| Sheet | A bounded task that holds focus | A destination players return to: a page.  A quick choice at its source: Popover | `placement` (`automatic`, `adaptive`, `center`, `side`, `bottom`), `detents` (`hug` for short content), `actions`, `guide`, `initialFocus`; `Sheet.dismissal` |
| Dialog | A modal decision that stays open while the server answers | A brief yes or no: Alert | `isPresented`, `onPresentedChange`, `actions` with `keepOpen` |
| Alert | A brief consequential confirmation | A task that must stay open for a result: Dialog | `title`, `actions` with a destructive role or a default action |
| Popover | A quick task anchored to its source | A bounded task: Sheet | `source` or `trigger`, `edge`, `compact` (`sheet` by default in narrow touch room) |
| Menu | Secondary commands behind one trigger | Frequent actions: direct Buttons | `items`, `trigger`, `presentation` (`automatic`, `menu`, `sheet`) |
| RadialMenu | Quick spatial choices, such as quick chat or emotes | Choices that need reading: Menu | `items`, `preset`, `anchor`, `completion`; `holdAction` with a press route as well |
| Callout | Teaching an action at its control | Persistent status: Notice | `anchor`, `title`, `content`, `closeButton` |
| DisclosureGroup | Optional facts that expand in the reading flow, under a label | A separate task: Sheet | `label`, `expanded`, `appearance` |
| CollapsibleView | A pill trigger whose panel opens over the page without moving it | Content that expands in the reading flow: DisclosureGroup | `label`, `expanded`, `content` |

## Layout

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| VStack | Reading order | A compact row: HStack | `width`, `gap`, `padding`, `align` |
| HStack | One compact unit on a line; `wrap = true` lets peers use several rows | A row that must become a column: AdaptiveStack | `gap`, `wrap`; `UI.fill()` children |
| ZStack | Layering art, readouts and effects in one area | | `alignH`, `alignV` |
| Grid | A small static arrangement | An interactive collection: VirtualGrid | `columns`, `gap` |
| AdaptiveStack | One group that is a row while it fits and a column when it does not | Different content per size: ViewThatFits | `axis` (omit it to adapt), `gap` |
| ViewThatFits | Complete alternatives, richest first | The same content in another axis: AdaptiveStack | Candidates with intrinsic sizes, smallest last |
| ScrollView | Content longer than a bounded viewport | Many items: a virtual collection | `axis`, `gap`, `padding` |
| Spacer | A minimum gap that can grow | Remaining room: `UI.fill()`.  Even spacing: `gap` | `minLength` |
| Divider | A rule between adjacent rows, such as settings rows | Groups that space already separates | `axis` |

Stacks hug by default.  `width = "fill"` takes the parent's width, and `UI.fill()` takes the room left beside siblings.  `maxWidth` keeps a reading area comfortable, and `surface = "panel"` gives a group a plate that reads over the world.

## Collections

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| VirtualGrid | Objects that players recognize by sight; a small peer grid that hugs | Descriptions: VirtualList | `minColumnWidth`, `itemSize` or `measure`, `mode = "all"` with `hug`, `selection`, `onActivate` |
| VirtualList | Rows with descriptions | Shared attributes: Table | `from`, `key`, `render`, `itemSize` or `measure`, `selection` |
| Table | Comparing shared attributes | Descriptions: VirtualList | `columns`, `sort`, `onCellChange` |
| Outline | An actual hierarchy | Authored spatial relationships: ZoomView | `children`, `expanded` |
| SpatialGrid | Items with cell footprints on an inventory board | Uniform items: VirtualGrid | `columns`, `rows`, `placement` |
| ZoomView | A map, board or skill tree to pan and zoom | A plain hierarchy: Outline | `contentSize`, `zoom`, `focus` |
| Card | An object in a collection, with art and actions | Text-only rows: VirtualList rows | `title`, `image`, `primaryAction`, `menu`, `reveal`; `Card.browseTarget` |
| CellEditor | Editing one record field in place | Several fields with one result: a form with a draft | `editor`, `draft`, `validate` |
| RowActions | Commands on one row, including swipe actions | Many commands: Menu | `leading`, `trailing`, `editing`, `fullSwipe` |

## Commands and choices

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| Button | A command | A value: Toggle or Picker | `appearance` (`emphasis` for the primary action, `standard`, `soft`, `utility`, `link`, `inverse`), `role` (`destructive`), `busy`, `icon`, `caption`, `controlSize`, `haptic` |
| SplitButton | A meaningful default with alternatives | No default: Menu | `label`, `onActivate`, `items` |
| Toggle | Something on or off | Named alternatives: Picker | `presentation` (`switch`, `checkbox`, `button`), `row` |
| Picker | One value from a known set | Custom values: ComboBox | `style` (`segmented` for a few peer choices, `menu` for secondary filters, `radioGroup` for explanations, `cards` for visual alternatives), `query` |
| ComboBox | Search that permits custom values | A closed set: Picker | `value`, `text`, `acceptCustom` |
| Chip | A compact filter or a removable selection | A setting: Toggle | `selected`, `onRemove` |
| Slider | An amount on a bounded range | Exact increments: Stepper | `step`, `onCommit` |
| Stepper | Exact increments | A broad range: Slider | `step`, `min`, `max` |
| NumberInput | A precise number | Steps are enough: Stepper | `numericValue`, `parse`, `format`, `stepButtons` |
| TextInput | Text the player types | Known choices: Picker | `label`, `hint`, `errorText`, `validate`, `onCommit` |
| LevelPicker | A discrete level | A continuous value: Slider | `count` |
| Rating | Showing or choosing a rating | Up or down: Vote | `count` |
| Vote | An up or down vote, with the tally on the server | Choosing among options: Picker | `value`, `summary`, `readOnly` |
| ColorPicker | A color from a color space | A few named colors: Picker | `modes`, `draft`, `onCommit` |
| DateTimePicker | A date or an interval | | `min`, `max`, `selection`, `draft` |

## Information and status

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| Text | Text with a semantic role | An icon with a title: Label | `textRole`, `role = "secondary"`, `wrap`, `truncate`, `lines` |
| Label | An icon with its title | No icon helps: Text | `presentation` (`titleAndIcon`, `titleOnly`, `iconOnly`) |
| Badge | A short status or count on an object | A bare mark: StatusIndicator | `status`, `icon`, `appearance` |
| StatusIndicator | A compact, named status mark | Words help: Badge | `form` (dot, ring, square, dash), `count`, `name` |
| ProgressView | A measured quantity or an unknown wait | A deadline: Timer | `presentation` (bar, circular, gauge, spinner) |
| Timer | Time left to a deadline | An amount: ProgressView | `deadline` and `now` from the same clock |
| Notice | Persistent state | A brief acknowledgement: Toast | `severity`, `placement` (`inline`, `affixed`), `actions` |
| Toast | A brief acknowledgement | It must persist: Notice | `message`, `action`; `app.presentToast` for a one-shot result |
| Skeleton | Known structure while content loads | A wait without structure: ProgressView | `form`, `lines` |
| ErrorBoundary | Recovery when a region fails to build | A refused request: model state | `view`, `fallback`, `onError` |
| ShortcutHint | The glyph of a real binding on its control | Commands without a control: ButtonGuide | `action`, `keys`, `cap` |
| ButtonGuide | A legend of commands without a visible control | A control that can carry its glyph: ShortcutHint | `entries`, `inputs` |
| Typewriter | Dialogue text that reveals | Static copy: Text | `controls`, `onRevealed` |

## Objects, people and the world

| Control | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| Image | A static image | Loaded content: AsyncImage | `image`, `scaleMode`, `tint` |
| AsyncImage | An image that loads, with a placeholder | A known asset: Image | `placeholder`, `onStatus` |
| Stage | A 3D object to inspect | A static view carries the decision: Image | `camera`, `content`, `lazy` |
| Avatar | One player's face | Several players: AvatarGroup | `userId` or `image`, `presence` |
| AvatarGroup | A summary of a group | Comparing individuals: a list | `max`, `layout`, `onOverflow` |
| Path | Vector strokes such as rings, links and routes | Filled art: Image | `points`, `thickness`, `role`, `closed` |
| WorldMarker | Pointing to a target in the world, also from the screen edge | Status: a HUD readout | `anchor` from `UI.worldAnchor`, `edge`, `arrow` |
| DiegeticScreen | Moving the app onto a framed surface in the world | Separate world UI: SurfaceGui | `layers`, `surface`, `camera` |

## Motion and feedback

| Mechanism | Use it for | Choose instead when | Options that shape the result |
| --- | --- | --- | --- |
| Travel | An object moving between places | Emphasis in place: Flash | `destination`, `motion`, `onLanded` |
| `UI.sequence` | An ordered reveal that Skip and reduced motion can finish | One transition: theme motion | `steps`, `finish()`; see `Effect-sequences` |
| Flash | A transient effect on a target | Movement: Travel | `target`, `progress`, `mode` |
| `UI.feedback` and `haptic` | Haptics for a result or a press | | Kinds `selection`, `impact`, `success`, `warning`, `error`; see `Haptics` |

## Behaviors

These attach behavior to native objects and draw nothing of their own:

- `UI.environment`: the facts that adaptation reads.
- `UI.responder`: input for a passive HUD.
- `UI.focusSection`: entry and return focus for a group.
- `UI.commandScope`: commands on the selected target.
- `UI.adjustable`: custom value controls.
- `UI.draggable` and `UI.dropTarget`: direct manipulation.
- `UI.worldAnchor`: targets in the world.  `Facet.format.compact` shortens HUD numbers, and `Facet.richText.escape` makes player text safe in rich text.
