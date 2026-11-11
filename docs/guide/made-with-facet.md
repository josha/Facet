# Made with Facet

Two games build their interfaces with Facet:

- [Word Amigos](#word-amigos), a released two-player word game.
- [Realms of Artinel](#realms-of-artinel), an online role-playing game in
  development.

The games use Facet in different ways. Word Amigos uses the stock controls
almost everywhere. Realms of Artinel keeps the Facet mechanisms and the
StyleSheet, and adds its own control kits for a game look. Each claim on this
page comes from the source of the game.

## Word Amigos

[Word Amigos](https://www.roblox.com/games/88565189553139) is an original
two-player word game for Roblox. Players take turns. Each player puts letter
tiles on a shared board to make words and get points.

The game builds its whole interface with Facet controls over Compose. One
client root mounts the interface. The app draws in one ScreenGui. Each control
comes from `Facet.controls(runtime)`. Sheets, menus and dialogs go to a
separate overlay layer through the `overlayParent` option.

The game supports phone, tablet, desktop and console. Players use touch,
mouse, keyboard and gamepad.

The tables below list each Facet control and mechanism that the game uses, and
the task that each one does.

### App shell and navigation

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
| [Badge](../reference/nodes/Badge.card.md) | The turn label in each match row, the count of matches in each section and the Sparks balance. |
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
| [Skeleton](../reference/nodes/Skeleton.card.md) | Placeholder rows while ranks load. |

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
| [Picker](../reference/nodes/Picker.card.md) | A menu picker with a query chooses a friend. A cards picker chooses the game format. Menu pickers set appearance, text size and word language. The Device appearance option is disabled with a description. |
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
| [Alert](../reference/nodes/Alert.card.md) | Confirms Pass and Resign. Offers Retry when the server did not confirm a turn. |
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

### Motion and theming

| Mechanism | Use in Word Amigos |
| --- | --- |
| [sequence, countUp and shake](../reference/nodes/Effect-sequences.md) | `sequence` runs the room daylight, the end-of-game glow, the word meld sweep and the rack refill. `countUp` counts scores, Sparks and profile rates. `shake` shakes refused tiles. |
| [Flash](../reference/nodes/Flash.card.md) | Score arrival, the Play ready pulse, turn arrival, quest ticks, and the squares of a word that scores. |
| [Haptics](../reference/nodes/Haptics.md) | `UI.feedback "success"` when word points land, if the player turned haptics on. |
| [motionLevel](../reference/nodes/Motion.motionLevel.md) | `"limited"` when the player reduces motion. |
| [Theme definition](../reference/nodes/Themes.definition.md) | `Facet.themes.neutralPackage` and `Facet.themes.define` make the game theme. Light, dark and seasonal palettes change with the player preferences. |
| [StyleSheet](../reference/nodes/Themes.stylesheet.md) | `Facet.themes.createStyleSheet` with `tenFoot` makes the StyleSheet for each layer. |
| [Skin](../reference/nodes/Themes.skin.md) | `Facet.themes.skin` with the `fab` skin draws the new-game button. |
| [fill](../reference/nodes/fill.md) and [Spacer](../reference/nodes/Spacer.card.md) | Push rows apart in stacks. |

`Facet.bind` binds Compose to the Roblox host. `Facet.Roblox.cleanup` cancels
deferred tasks when their owner ends. The `translator` option localizes the
control text.

## Realms of Artinel

Realms of Artinel is an online role-playing game for Roblox. It is in
development and is not released. Its whole client interface uses Facet: the
heads-up display (HUD), the game windows, character creation, dialogue and the
markers over the world.

### App shell

| Mechanism | Use in Realms of Artinel |
| --- | --- |
| [Facet.app](../reference/nodes/Mounting.Facet.app.md) | One app mounts the client interface in one ScreenGui. It sets `suspendGameplay`, a reactive theme, `motionLevel` and the `preferredTextSize` environment fact. Every screen uses `app.UI`. |
| [Theme definition](../reference/nodes/Themes.definition.md) | `Facet.themes.define` extends `Facet.themes.neutralPackage` with the game colors, typography, metrics, motion, focus chrome and StyleSheet rules. Three realm themes extend that base. |
| [Theme resolution](../reference/nodes/Themes.resolution.md) | `Facet.themes.forResolution` adapts the selected realm theme to the viewport size. |
| [Design library](../reference/nodes/Design-library.md) | Each screen is a Facet design with a design contract. The game control kits are registered as design kinds. |
| [Controls](../reference/nodes/Controls.md) | Game control kits extend the `app.UI` table with window, tab, meter and HUD controls in the game style. The front-door scene gets its own controls table and StyleSheet. |

The game orders its own interface layers above the Facet controls, and moves
the focus between them with Compose focus scopes.

### HUD

| Control | Use in Realms of Artinel |
| --- | --- |
| [Composition](../reference/nodes/Composition.card.md) and [Region](../reference/nodes/Region.card.md) | The lanes of the battle HUD, the caption HUD and the arrival HUD. |
| [ProgressView](../reference/nodes/ProgressView.card.md) | The cast bar, the health and resource meters, the experience bar and the party rows. |
| [Sheet](../reference/nodes/Sheet.card.md) | The class controls on the HUD. |
| [Button](../reference/nodes/Button.card.md) | The touch combat actions and the action bar slots. |

### Windows and character

| Control | Use in Realms of Artinel |
| --- | --- |
| [Sheet](../reference/nodes/Sheet.card.md) | The game window kit is a Sheet. Shops, trainers, the talent panel, dialogue and the book reader open in it. |
| [TabView](../reference/nodes/TabView.card.md) | The pages of the compendium and the tabs of the game windows. |
| [VirtualGrid](../reference/nodes/VirtualGrid.card.md) | The bag slots. |
| [AdaptiveStack](../reference/nodes/AdaptiveStack.card.md) and [ScrollView](../reference/nodes/ScrollView.card.md) | The columns and pages of the character sheet, the spellbook and the book reader. The lists of the market, trade, bank, mail and guild windows. |
| [Stage](../reference/nodes/Stage.card.md) | The 3D previews of the character, the weapons and the banners, and the speaker portrait in dialogue. |
| [AsyncImage](../reference/nodes/AsyncImage.card.md) | Item icons. |
| [draggable and dropTarget](../reference/nodes/draggable-and-dropTarget.md) | Players drag abilities from the spellbook to the action bar, and swap or clear slots. |
| [Picker](../reference/nodes/Picker.card.md) | A segmented picker chooses a profession. |
| [Badge](../reference/nodes/Badge.card.md) | Objective counts and the tracked mark in the quest journal. |
| [Dialog](../reference/nodes/Dialog.card.md) | The death screen, the return to character selection and other full-screen moments. |
| [Notice](../reference/nodes/Notice.card.md) | Gear notices on arrival. |
| [Toggle](../reference/nodes/Toggle.card.md) | The accessibility settings, such as reduced motion and high contrast. |

### Character creation

| Control | Use in Realms of Artinel |
| --- | --- |
| [NavigationStack](../reference/nodes/NavigationStack.card.md) and [TabView](../reference/nodes/TabView.card.md) | The steps of character creation. |
| [Effect sequences](../reference/nodes/Effect-sequences.md) | Each step fades in with `sequence`. |
| [focusSection](../reference/nodes/focusSection.md) | Each step puts first focus on its controls when it appears. |

### Chat

| Control | Use in Realms of Artinel |
| --- | --- |
| [TextInput](../reference/nodes/TextInput.card.md) | The chat composer. |
| [scrollTo](../reference/nodes/scrollTo-and-scrollToVisible.md) | Keeps the chat log at its last message. |
| [Button](../reference/nodes/Button.card.md) | A `shortcut` with the Slash key opens the chat. |

### World markers

| Mechanism | Use in Realms of Artinel |
| --- | --- |
| [worldAnchor](../reference/nodes/worldAnchor.md) | Screen markers that follow parts in the world, hide offscreen and respect occlusion. |
| [WorldMarker](../reference/nodes/WorldMarker.card.md) | A marker on a used gathering node. |
| `UI.provide` | Nameplates, progress bars and combat labels in BillboardGuis use the app controls. |

### Input, devices and motion

| Mechanism | Use in Realms of Artinel |
| --- | --- |
| `Facet.inputPriority.belowControls` | The InputContexts of the game sit below the Facet controls, so a control gets its input first. |
| [environment](../reference/nodes/environment.environment.md) | `gameplaySuspended` pauses the game while the interface is modal. `interactionClasses.touch` selects the touch HUD, the slot size and the map size. `isTenFoot` enlarges the HUD text on a television. `effectiveInput` selects the input hints. |
| [motionLevel](../reference/nodes/Motion.motionLevel.md) | The press scale and the ready pulse play only at the normal motion level. Reduced motion in the game settings sets the level. |

The game builds some parts itself: the interface layer stack, the item
tooltips, the teleport loading cover, the movement thumbstick from Facet
stacks, the damage numbers and the input binding table.
