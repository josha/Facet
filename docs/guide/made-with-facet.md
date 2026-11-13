# Made with Facet

Two public Roblox games build their interfaces with Facet:

- [Word Amigos](#word-amigos), a two-player word game.
- [Realms of Artinel](#realms-of-artinel), an online role-playing game.

Both games build their screens as Facet designs. A design is a function of the
controls with a typed contract: its inputs, its outputs and the stock control
at its root. The same design renders from sample data in tests and in Studio,
and from live game state in play. Both games keep their look in a Facet theme
and its StyleSheet, not in the controls. Each claim on this page comes from the
source of the game.

## Word Amigos

[Word Amigos](https://www.roblox.com/share?code=994a73c59fd9544e88798cbea6e34c21&type=ExperienceDetails) is an original
two-player word game for Roblox. Players take turns. Each player puts letter
tiles on a shared board to make words and get points. The game supports phone,
tablet, desktop and console. Players use touch, mouse, keyboard and gamepad.

### How the screens are built

Most screens of the game are generated designs.

1. Each screen starts as a design document. The game has 44 of them.
2. A design kit from `Facet.design()` describes the controls that a document
   can use. It adds game design kinds for the letter tile, a word of tiles,
   the navigation glyphs, the reward preview and the Sparks balance. The kit
   reads the spacing, colors and fonts from one design token table.
3. A tool emits each document as a view module: a function of
   `(UI, props)` with a `_design` table. The table holds the contract
   inputs (values, readables and cells, with their types), the outputs with
   their argument types, and editor names for the inner nodes. Nobody edits a
   generated view by hand; a check fails when a view and its document differ.
4. Screen modules call the views with the shared controls and pass model
   readables as inputs.
5. A Studio fixture mounts the Profile, Leaderboard and Achievements views
   with fixed data for visual review.

A few screens are still written by hand from the same controls: the match
header, Friends, How to play and the 3D room views.

### App shell and theming

| Mechanism | Use in Word Amigos |
| --- | --- |
| `Facet.bind` and a direct Compose mount | The client root mounts the tree with the bound runtime. `UI.provide` gives the controls to the screens. |
| Three ScreenGuis | A backdrop layer with the palette gradient, the main `WordAmigos` layer with `CoreUISafeInsets`, the focus ring and the StyleSheet, and an `Overlays` layer. Sheets, menus and dialogs go to the overlay layer through the `overlayParent` option. |
| [Theme definition](../reference/nodes/Themes.definition.md) | `Facet.themes.define` extends `Facet.themes.neutralPackage` and checks the definition report. Light, dark and seasonal palettes change with the player preferences. A regular variant with larger type and spacing applies when the screen is not compact or short. |
| [StyleSheet](../reference/nodes/Themes.stylesheet.md) | `Facet.themes.createStyleSheet` with `tenFoot` makes the StyleSheet for each layer. |
| [Skin](../reference/nodes/Themes.skin.md) | `Facet.themes.skin` with the `fab` skin draws the new-game button. |
| [environment](../reference/nodes/environment.environment.md) | The controls take `preferredTextSize` and the measured `viewportSize`. |

### Navigation

| Control | Use in Word Amigos |
| --- | --- |
| [TabView](../reference/nodes/TabView.card.md) | `style = "sidebarAdaptable"` holds Games, Leaderboard, Profile and Achievements. It shows a rail on wide screens and a bottom bar on phones, with icon-only tabs in the compact size class. The tabs hide while a match is open on a short or compact screen. A second TabView with `placement = "none"` switches between the Games and Settings pages. The navigation menu selects the page. |
| [NavigationSplitView](../reference/nodes/NavigationSplitView.card.md) | The games list is the sidebar. The open match is the detail. On a compact screen one column shows, and Back returns to Games. |
| [NavigationStack](../reference/nodes/NavigationStack.card.md) | The detail column of the split view. It has hidden chrome and a scale transition. Its root page asks the player to choose a game. |
| [NavBar](../reference/nodes/NavBar.card.md) | The match title bar, with Back to Games and trailing match commands. |
| [Composition](../reference/nodes/Composition.card.md) and [Region](../reference/nodes/Region.card.md) | The top bar. The wordmark is the leading region. The Sparks balance, the 2D and 3D mode switch and the menu button are the trailing region. |
| [Screen](../reference/nodes/Screen.card.md) | The safe-area page for Games, Settings, Leaderboard, Profile and Achievements. |
| [ErrorBoundary](../reference/nodes/ErrorBoundary.card.md) | Each page has a boundary. A failed page shows a failure view with Retry. |
| [Sheet](../reference/nodes/Sheet.card.md) | `placement = "side"` on the right edge holds the navigation menu. |

### Home and games list

| Control | Use in Word Amigos |
| --- | --- |
| [ScrollView](../reference/nodes/ScrollView.card.md) | The games home and its list of matches. |
| [PageView](../reference/nodes/PageView.card.md) | The home spotlight: word of the day, Lucky Tile, weekly quest, tip of the day and achievements. It advances automatically, except when the player reduces motion. A second PageView shows the three How to play pages. |
| [RadialMenu](../reference/nodes/RadialMenu.card.md) | The new-game button opens four choices: Computer, Pass and play, Friend and Online. The menu anchors to the bottom-right button. |
| [Path](../reference/nodes/Path.card.md) | `Facet.pathShapes.needle` draws the strokes of the new-game button glyph. Other paths draw the navigation glyphs. |
| [StatusIndicator](../reference/nodes/StatusIndicator.card.md) | Shows if it is your turn or the opponent's turn in each match row. |
| [Badge](../reference/nodes/Badge.card.md) | The turn label in each match row and the count of matches in each section. |
| [Label](../reference/nodes/Label.card.md) and [Travel](../reference/nodes/Travel.card.md) | The Sparks balance on the home page. Earned Sparks fly to it. |
| [Avatar](../reference/nodes/Avatar.card.md) | The opponent in each match row. |
| [ProgressView](../reference/nodes/ProgressView.card.md) | A spinner while ranked matchmaking searches. |
| [Button](../reference/nodes/Button.card.md) and [Label](../reference/nodes/Label.card.md) | Match rows, Play, How to play, friends and ranked search actions. |

### Match board and rack

| Control | Use in Word Amigos |
| --- | --- |
| [ZoomView](../reference/nodes/ZoomView.card.md) | The board. Players pinch, scroll and pan it. Double tap zooms to a comfortable cell size. The game calls `fit`, `zoomAt` and `zoomTo` on the zoom controls to frame the board and the tiles that a player places. |
| [Grid](../reference/nodes/Grid.card.md) and [HStack](../reference/nodes/HStack.card.md) | The rows of board squares. Each square is a Button. |
| [VirtualList](../reference/nodes/VirtualList.card.md) | The rack is a horizontal list with fixed slots and `reorderable = true`. Players reorder tiles and drag them to the board. |
| [draggable and dropTarget](../reference/nodes/draggable-and-dropTarget.md) | A placed tile can be dragged back. Each board square is a drop target that accepts or refuses a tile. The rack is a drop target for returned tiles. |
| [Travel](../reference/nodes/Travel.card.md) | Tiles fly on an arc between the rack and the board, refill from the bag and return on recall. Word points fly to the score. Sparks fly to the balance. |
| [commandScope](../reference/nodes/Focus-and-command-scopes.md) | With a keyboard, a letter key puts a matching rack tile on the focused square. Backspace returns the tile. |
| [Menu](../reference/nodes/Menu.card.md) | A long press, secondary click, keyboard or gamepad on a played square opens a menu to define its words. The More menu holds the match powers. Both menus open as a sheet in the compact size class. |
| [Path](../reference/nodes/Path.card.md) | An outline and a shadow around the tiles of each played word. |
| [VirtualGrid](../reference/nodes/VirtualGrid.card.md) | The letters left in the tile bag, the tiles to swap and the letter choice for a blank tile. |
| [Avatar](../reference/nodes/Avatar.card.md) and [Badge](../reference/nodes/Badge.card.md) | The two players, the turn mark and the Sparks count in the match header. |

### Chat

| Control | Use in Word Amigos |
| --- | --- |
| [VirtualList](../reference/nodes/VirtualList.card.md) | The messages use `follow = "end"`, `arrival = "rise"` and measured rows. A horizontal list holds the stock replies. |
| [Notice](../reference/nodes/Notice.card.md) | An empty conversation and a chat that is not available. |
| [Avatar](../reference/nodes/Avatar.card.md) | The opponent at the top of the chat. |
| [Sheet](../reference/nodes/Sheet.card.md) | The chat opens in a full-height sheet with no header. |

### Leaderboard

| Control | Use in Word Amigos |
| --- | --- |
| [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) | The rank columns and the filters are side by side on wide screens and stacked on narrow screens. |
| [Picker](../reference/nodes/Picker.card.md) | A segmented picker selects the scope. A menu picker selects the week. Another menu picker selects the word language. |
| [VirtualList](../reference/nodes/VirtualList.card.md) | The rank rows. |
| [Avatar](../reference/nodes/Avatar.card.md) and [Badge](../reference/nodes/Badge.card.md) | Each ranked player, and a "You" badge on the row of the player. |
| [Pagination](../reference/nodes/Pagination.card.md) | `form = "label"` moves between pages of ranks. |
| [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) | The record of the player's own rank. |

### Profile and achievements

| Control | Use in Word Amigos |
| --- | --- |
| [ProgressView](../reference/nodes/ProgressView.card.md) | Rings for the win rate and for wins, draws and losses. Bars for the weekly quest and for each achievement. |
| [Toggle](../reference/nodes/Toggle.card.md) | Seasonal themes on the Achievements page. |
| [Toast](../reference/nodes/Toast.card.md) | "Choice saved" after a player selects a reward style. |
| [Divider](../reference/nodes/Divider.card.md) | Separates sections of the record and the achievements. |
| [Flash](../reference/nodes/Flash.card.md) | A sweep across each earned reward tile. |

### Friends and settings

| Control | Use in Word Amigos |
| --- | --- |
| [TextInput](../reference/nodes/TextInput.card.md) | `presentation = "search"` finds a Roblox username. A trailing Find button submits it. |
| [Picker](../reference/nodes/Picker.card.md) | A menu picker with a query chooses a friend. A cards picker chooses the game format. In Settings, menu pickers set appearance and text size; the Device appearance option is disabled with a description. The New game sheet picks the word language, the opponent, the difficulty and the table mode. Profile and Leaderboard also pick the word language. |
| [Toggle](../reference/nodes/Toggle.card.md) | Friend invitations, 3D mode as a button, seasonal themes, sound effects, music, mute, haptics and reduced motion. |
| [DisclosureGroup](../reference/nodes/DisclosureGroup.card.md) | The Appearance and Credits sections of Settings. |
| [Notice](../reference/nodes/Notice.card.md) | No invitations yet, sent invitations and the match history status. |
| [VirtualList](../reference/nodes/VirtualList.card.md) | Friend invitations and the turns in the match history. |
| [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) | The Decline and Block player actions on an invitation, the Settings actions and the Profile columns. |

### Sheets, dialogs and menus

| Control | Use in Word Amigos |
| --- | --- |
| [Sheet](../reference/nodes/Sheet.card.md) | Word definition, new game, friends, matchmaking, rematch, report player, opponent profile, match history and tile bag. On compact screens the game result, the blank letter choice and the swap also use a sheet. The game result uses the `hug` and `large` detents. |
| [Dialog](../reference/nodes/Dialog.card.md) | On regular screens the game result, the blank letter choice and the swap use a dialog. In Pass and play, a dialog asks the next player to take the device. |
| [Alert](../reference/nodes/Alert.card.md) | Confirms Pass, Resign and Block player. Offers Retry when the server did not confirm a turn. |
| [Popover](../reference/nodes/Popover.card.md) | The game panel in the 3D room. |
| [Menu](../reference/nodes/Menu.card.md) | The More menu in the 3D room heads-up display (HUD). |

### Room and 3D surfaces

| Control | Use in Word Amigos |
| --- | --- |
| [DiegeticScreen](../reference/nodes/DiegeticScreen.reference.md) | In 3D mode the app layers move onto a tablet surface on a table in the room. The player can still use them. |
| [cameraRig](../reference/nodes/cameraRig.reference.md) | The room camera, with home, play and tall play presets and bounds for focus, distance and pitch. |
| [draggable and dropTarget](../reference/nodes/draggable-and-dropTarget.world.md) | `world` drag on a plane lifts the 3D tiles from the rack to the board. The board cells and the rack are drop targets. |
| [Grid](../reference/nodes/Grid.card.md) and [Menu](../reference/nodes/Menu.card.md) | The input cells over the 3D board, and the define-word menu on each cell. |
| [TabView](../reference/nodes/TabView.card.md) | `placement = "none"` selects the room panel: Pause, Settings, How to play and the other destinations. |
| [VirtualList](../reference/nodes/VirtualList.card.md) and [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) | The match cards and the rails of the room HUD. |

The room HUD gets its own `Facet.controls` table and StyleSheet for its layer.

### Input and focus

| Mechanism | Use in Word Amigos |
| --- | --- |
| [focusSection](../reference/nodes/focusSection.md) | The home tabs, the match, Settings and the room HUD. The match puts first focus on the rack and sets `returnFocus`. |
| [focusRing](../reference/nodes/focusRing.md) | One focus ring for the player GUI. |
| [commandScope](../reference/nodes/Focus-and-command-scopes.md) | Letter and Backspace keys on the board. |
| [environment](../reference/nodes/environment.md) | `isCompact`, `isShort`, `isWide` and `sizeClass` select the layout. `scaled`, `metricScale` and `thumbTarget` size the controls. `viewportSize` selects the camera framing in the room. |
| [layoutSize](../reference/nodes/layoutSize.md) | Measures the match header, the dock and the leaderboard week column. |
| [Adaptive facts](../reference/nodes/Facet-adaptive.md) | `Facet.adaptive.sizeClass` selects the board zoom for wide screens. |

### Motion

| Mechanism | Use in Word Amigos |
| --- | --- |
| [sequence, countUp and shake](../reference/nodes/Effect-sequences.md) | `sequence` runs the room daylight, the end-of-game glow, the word meld sweep and the rack refill. `countUp` counts scores, Sparks and profile rates. `shake` shakes refused tiles. |
| [Flash](../reference/nodes/Flash.card.md) | Score arrival, the Play ready pulse, turn arrival, quest ticks, and the squares of a word that scores. |
| [Haptics](../reference/nodes/Haptics.md) | `UI.feedback "success"` when word points land, if the player turned haptics on. |
| [motionLevel](../reference/nodes/Motion.motionLevel.md) | `"limited"` when the player reduces motion. |
| [fill](../reference/nodes/fill.md) and [Spacer](../reference/nodes/Spacer.card.md) | Push rows apart in stacks. |

`Facet.Roblox.cleanup` cancels deferred tasks when their owner ends. The
`translator` option localizes the control text.


## Realms of Artinel

[Realms of Artinel](https://www.roblox.com/share?code=59f659534e7a01429cad08b7f2c75bb8&type=ExperienceDetails) is an online role-playing game for Roblox. Its whole
client interface uses Facet: the heads-up display (HUD), the game windows,
character creation, dialogue and the markers over the world. The game supports
phone, tablet, desktop and console, and switches the HUD for touch and for
ten-foot viewing.

### How the screens are built

The interface is a library of 159 Facet designs. Each design declares a
`_design` table with a typed contract (inputs of kind value, readable or cell,
and outputs) and an editor root that names the stock control it stands on. For
example, the shared meter design stands on ProgressView and the window design
stands on Sheet. A design catalog and a design library register the designs
and the game design kinds, built with the `Facet.design()` kit. Each design has
sample data and a build check, so a screen renders from samples in tests and
from live game state in play. HUD bindings connect the game state to the HUD
designs. An in-game design editor and a live design tool, which runs its own
`Facet.app`, render the designs during development.

The game names its windows, tabs and meters as designs over the stock
controls, and keeps the game look in the theme:

- The window design calls a game control, `UI.WindowSheet`, that wraps
  `UI.Sheet` with named detent plans for windows, trainers, the compendium and
  crafting.
- A game control wraps `UI.TabView` and adds the TabOverflow design, which
  draws a fade over the overflowing tabs. The character sheet and the
  compendium use `UI.TabView` directly.
- The shared meter design returns `UI.ProgressView`. The HUD meter design
  returns `UI.VitalsBar`, a game control that wraps a ProgressView track.

### App shell and theming

| Mechanism | Use in Realms of Artinel |
| --- | --- |
| [Facet.app](../reference/nodes/Mounting.Facet.app.md) | One app mounts the client interface in one ScreenGui with `CoreUISafeInsets`. It sets `suspendGameplay`, a reactive theme, `motionLevel` and the `preferredTextSize` environment fact. Most screens call `Facet.controls(runtime)` with no options and inherit the app controls through `UI.provide`; some read the app controls directly. |
| [Theme definition](../reference/nodes/Themes.definition.md) | `Facet.themes.define` extends `Facet.themes.neutralPackage` with the game colors, typography, metrics, motion, focus chrome and StyleSheet rules. Each realm has its own theme on that base. The player's allegiance selects the realm theme. |
| [Theme resolution](../reference/nodes/Themes.resolution.md) | `Facet.themes.forResolution` adapts the selected realm theme to the viewport size. |
| [StyleSheet](../reference/nodes/Themes.stylesheet.md) | The front-door scene, the war zone and each character window surface (wares, talents, the spellbook bar, quest entries and trainers) get their own themed controls and StyleSheet. The window surfaces adapt their theme with `forResolution`. The theme also adds game style rules, such as the tab fade, that `Facet.tag` applies. |

### Player-facing surfaces

| Surface | Facet controls |
| --- | --- |
| Battle HUD | Unit frames, the action bar, the cast bar, the minimap and the quest tracker are HUD designs. [ProgressView](../reference/nodes/ProgressView.card.md) draws the health and resource meters, the cast bar, the experience bar and the party rows. [Composition](../reference/nodes/Composition.card.md) and [Region](../reference/nodes/Region.card.md) lay out the HUD lanes. [Button](../reference/nodes/Button.card.md) draws the action bar slots and the touch combat actions. |
| Game windows | The compendium, the character sheet, shops and trainers open in the window design over [Sheet](../reference/nodes/Sheet.card.md), with [TabView](../reference/nodes/TabView.card.md) pages. [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) and [ScrollView](../reference/nodes/ScrollView.card.md) lay out the character sheet, the spellbook and the market, trade, bank, mail and guild lists. |
| Bag and items | [VirtualGrid](../reference/nodes/VirtualGrid.card.md) holds the bag slots. [AsyncImage](../reference/nodes/AsyncImage.card.md) draws the item icons. The Button `help` option shows the inspection text of equipped items. [Stage](../reference/nodes/Stage.card.md) shows 3D previews of the character, weapons and banners. |
| Abilities | Players drag abilities from the spellbook to the action bar with [draggable and dropTarget](../reference/nodes/draggable-and-dropTarget.md), and swap or clear slots. |
| Character creation | [NavigationStack](../reference/nodes/NavigationStack.card.md) and [TabView](../reference/nodes/TabView.card.md) hold the steps. Each step fades in with [sequence](../reference/nodes/Effect-sequences.md) and puts first focus on its controls with [focusSection](../reference/nodes/focusSection.md). |
| Quests and dialogue | [Badge](../reference/nodes/Badge.card.md) shows objective counts and the tracked mark in the quest journal. Dialogue and the book reader open in a [Sheet](../reference/nodes/Sheet.card.md). Side-docked dialogue shows a Stage portrait of the speaker. |
| Chat | [TextInput](../reference/nodes/TextInput.card.md) is the composer. [scrollTo](../reference/nodes/scrollTo-and-scrollToVisible.md) keeps the log at its last message. A Button `shortcut` with the Slash key opens the chat. |
| World markers | [worldAnchor](../reference/nodes/worldAnchor.md) places screen markers that follow parts in the world, hide offscreen and respect occlusion. [WorldMarker](../reference/nodes/WorldMarker.card.md) marks a used gathering node. Nameplates and combat labels in BillboardGuis get the app controls through `UI.provide`. |
| Settings and modal moments | [Toggle](../reference/nodes/Toggle.card.md) sets the accessibility options, such as reduced motion and high contrast. [Dialog](../reference/nodes/Dialog.card.md) shows the death screen and the return to character selection. |

### Input, devices and motion

| Mechanism | Use in Realms of Artinel |
| --- | --- |
| `Facet.inputPriority.belowControls` | The InputContexts of the game sit below the Facet controls, so a control gets its input first. |
| [environment](../reference/nodes/environment.environment.md) | `gameplaySuspended` pauses the game while the interface is modal. `interactionClasses.touch` selects the touch HUD, the slot size and the map size. `isTenFoot` enlarges the HUD text on a television. `effectiveInput` selects the input hints. |
| [motionLevel](../reference/nodes/Motion.motionLevel.md) | The press scale and the ready pulse play only at the normal motion level. Reduced motion in the game settings sets the level. |

The item tooltip layer uses a Facet Popover, the movement thumbstick uses the
Facet controls, and the interface layer order and the teleport loading cover
are Facet designs. The reward float above a defeated enemy makes its own
ScreenGui.
