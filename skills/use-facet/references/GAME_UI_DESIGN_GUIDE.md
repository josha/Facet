# Game UI design

Game UI is a conversation between the game and the player.  The player acts and the game answers with information.  Art makes both belong to one world.  Facet supplies the behavior of that conversation: controls, focus, layout, input, adaptation and motion.  The game supplies what it means and how it looks.

Read this guide once before you design.  It moves from principles to the whole game, then to one surface, one element and one moment.  The chapters at the end apply it to kinds of task.  API nodes give the exact contracts.

## Principles

1. **Serve play.**  Players came to play the game, not to operate its interface.  Keep the challenge the game intends and remove every difficulty the UI adds by accident.
2. **Speak a language players already know.**  Use the conventions of the genre and the platform: a vertical pause list, confirm on A and back on B, a loadout with the character among its slots.  Depart from a convention only when the player gains something they can feel.
3. **Direct attention.**  Each state has one focal point and one likely next action.  Contrast, size, color and motion are a budget.  When everything stands out, nothing does.
4. **Function first, then flourish.**  A surface must work in grayscale first: its layout, flow, type, icons and contrast.  Then add color, shape, pattern and material until it is unmistakably this game's.
5. **Design every state.**  Game UI changes constantly.  Design full and empty, the first visit and the hundredth, the longest translation, a slow network and a refused request.  One polished screenshot is not a design.
6. **Answer every input and tell the truth.**  Acknowledge each input at once.  Show progress honestly and show only results the game accepted.  Make cancellation, failure and recovery predictable.
7. **Fit every way of playing.**  Room, physical readability, input and access needs vary independently.  Design for the most constrained case first.  Roomier and more precise contexts add to that route; they never replace it.
8. **Keep the player oriented.**  Players know where they are, what changed and how to get back.  Return them to play with their state intact.

When principles compete, the player's immediate task wins.  An urgent hazard outranks a reward.  A readable label outranks a decorative font.  A reachable exit outranks a cleaner layout.

## Work from the outside in

Game UI has levels.  Each level sets the limits of the next one.

| Level | Question | Section |
| --- | --- | --- |
| Flow | Which places exist, how do they connect and how does play resume? | [Map the flow](#map-the-flow) |
| Surface | Where does this task appear, and how much attention does it take? | [Choose the attention level](#choose-the-attention-level) |
| Group | What belongs together, and what comes first? | [Compose the surface](#compose-the-surface) |
| Element | Which control or readout expresses this decision? | [Choose elements by the decision](#choose-elements-by-the-decision) |
| State | How does each element look and behave in every condition? | [Design every state](#design-every-state) |
| Response | What confirms each input and each result? | [Make it feel alive](#make-it-feel-alive) |

Decide the levels in this order.  Review them in reverse: an element that works alone can still break its group, its surface or the flow.  The [visual language](#build-the-visual-language), the [ways of playing](#know-every-way-of-playing) and each [input's conventions](#follow-each-inputs-conventions) apply at every level.

### Frame the task first

Establish the intended experience from the brief and the game before you choose anything:

| Question | What to establish |
| --- | --- |
| Player | Prior knowledge, likely goal and access needs |
| Context | Pace, competing demands, available input, and whether the world continues |
| Decision | The facts and alternatives the player needs now |
| Action | Frequency, consequence, reversibility and effort |
| Outcome | The accepted result, the failure response and the next useful action |
| Return | Where play resumes and which state remains |

Keep this proportional to the work.  Infer it from the brief and the existing game, and ask only when a missing decision changes the design.  Do not invent game systems to fill a screen.

Study references with a similar task, pace and input.  Break each one into its building blocks: the large shapes, the route between screens, which icons have labels, how type creates hierarchy and how contrast marks the cursor.  Transfer the relationship that helps the decision, not the screenshot.

### Know every way of playing

Treat each constraint separately.  One label such as "console" or "mobile" never decides them all.

| Constraint | Design response |
| --- | --- |
| Room | Reflow and disclose; keep the decision and its action |
| Physical readability | Readable type roles, contrast and density for the real screen and distance |
| Available input | Keep every valid input usable |
| Input in use | Show matching prompts, glyphs and feedback |
| Reach and precision | Spaced targets and discrete alternatives to gestures |
| Access | Reflow, calm motion and redundant signals |

Design for the most constrained context first.  Every task has a single-press digital route: a game action for a HUD task and directional focus inside a surface.  Lay out each surface for the shortest supported room first.  Pointer and touch then add speed, and wider room adds richness.

These play contexts show how the constraints combine:

| Context | What it combines | What it needs |
| --- | --- | --- |
| Desktop with mouse and keyboard | Wide room, near view, precise pointer | Dense comparison; hover only adds; shortcuts shown with their keys |
| Desktop with a gamepad | Wide room, near view, directional focus | The desktop layout with a visible focus route and gamepad glyphs, not television-sized type |
| Phone, landscape | Short room; thumbs cover the lower corners | Short forms; primary actions within thumb reach; nothing important under thumbs |
| Phone, portrait | Narrow room | One column and a complete detail step |
| Tablet | Roomy touch, sometimes a keyboard | Two panes where they fit, with touch-sized targets |
| Console on a television | Far view, overscan, gamepad only | Ten-foot type and safe margins, fewer items per view, no pointer assumptions |
| Handheld PC, such as a ROG Ally or Steam Deck | Many pixels on a 7 or 8 inch screen at about 30 cm; gamepad first, with touch also live | The gamepad route of a desktop with the physical readability of a small screen; touch still works |

Readability is physical.  For Steam Deck Verified, Valve requires the smallest character to be at least 9 pixels tall at 1280×800, read from 30 cm, and recommends 12.  That is about 1.1 to 1.4 mm.  On a 7 inch 1080p screen the same heights are about 13 and 18 pixels.  A Roblox TextSize is larger than the letters it draws, so measure the letters in a capture instead of matching numbers.

## Map the flow

Draw the flow before you design a screen.  List the places the player goes: play, preparation, shared decisions, results, learning and settings.  Connect them with the inputs that move between them.

- A **linear** flow moves through fixed steps, such as choose, confirm, play and results.  Each step has one obvious next action and a way back.
- A **hub** offers several destinations from one place.  Peer destinations that players revisit become tabs.  Launch points become a list or tiles.  A destination can hold a hub of its own.
- In Roblox the world is often the hub.  A garage door, a vendor or a pad can open a destination.  A world station and a HUD button for the same task open the same destination.

Every place needs an entry the player can find and an exit that returns where they came from.  Count the presses from play to each frequent task, and keep the most frequent tasks one or two presses away.  A root has no Back.  Close returns to play.

A destination that replaces play owns input until it returns.  It replaces unrelated HUD groups and keeps only the context its decision needs, such as the balance beside a cost.  Opening it does not pause the world; the game decides that, and the surface says so when it matters.

Facet: `Tasks.pages` opens a destination from play and registers the game's own input suspension, so gameplay input comes back on return.  NavigationStack owns depth and Back, TabView owns peer destinations and NavigationSplitView owns a collection beside its detail.  The [layout and navigation chapter](game-ui/LAYOUT_AND_NAVIGATION.md) has the details.

## Choose the attention level

Each task takes some of the player's attention.  Order the options by cost and use the lowest level that keeps the decision clear.

| Level | The player | Facet starting point |
| --- | --- | --- |
| World | Reads the scene itself | World cues, `WorldMarker`, SurfaceGui or BillboardGui, `DiegeticScreen` |
| Glance | Monitors status while playing | Composition Regions with ProgressView, Timer, Badge and readouts |
| Prompt | Gets a command when it applies | An InputAction shown with `ShortcutHint` or `ButtonGuide`; Callout to teach it |
| In place | Makes a quick choice at its source | Popover, Menu, RadialMenu, DisclosureGroup |
| Interruption | Completes a bounded task that holds focus | Sheet, Dialog, Alert |
| Destination | Leaves play for a sustained task | `Tasks.pages` with NavigationStack, TabView or NavigationSplitView |

Frequency moves a task down the list: make it direct.  Consequence moves it up: make it deliberate.  A boost used in every race needs a visible button and a binding.  A graphics setting changed once can live two levels deep.  A purchase needs its full terms in view before commitment, not three confirmations.

Every press, focus move, menu and confirmation spends attention.  Add a step only when it improves understanding or prevents a meaningful mistake.  A confirmation cannot repair an unclear label or targets placed too close together.

### Protect play

The game owns the center of the screen, where the camera frames the action, and the areas that held thumbs cover.  Glance-level UI sits at the edges in a few coherent groups, and Composition handles the top bar inset and its fallback.  It shows only what changes the next action.  It ends commands and notices when their context ends.  A marker can enter the center when finding that target is the immediate task.

### Decide where information lives

Information can sit in the world or on the screen, and inside or outside the fiction:

- **Diegetic**: in the world and the fiction, such as a speedometer on the dashboard.
- **Spatial**: in the world but outside the fiction, such as a marker above a checkpoint.
- **Meta**: in the fiction but on the screen, such as rain on the lens when the player is hurt.
- **Non-diegetic**: on the screen and outside the fiction, such as a lap counter.

World forms are immersive, but distance, lighting, occlusion and camera motion affect them.  Use the most immersive form that the player can still read in time.  Give essential status a screen form when the world cue cannot be read.

## Compose the surface

### Start from the building blocks

Players already know the shapes of common screens.  A pause menu is a vertical list.  A loadout puts the character or vehicle among its slots, with its stats beside it.  A shop item shows the object, its price and Buy together.  A result leads with placement.  Start with the expected blocks and arrange them as large shapes.  Add detail after the shapes work.

### Give each state a focal area

Decide what the player notices first, second and third.  The subject (the object, the outcome or the hazard) gets the most space and contrast.  The next action sits beside it.  Context and optional detail are quieter.  A capture passes when a first glance shows the subject, its state and the next action.

### Group, align and balance

Put related facts close together, and separate groups with space before you add boxes.  Align comparable values so the eye compares them along one line.  Use one spacing scale everywhere: the theme's space tokens.  Balance the margins so opposing margins match.  To check balance, flip a capture: a balanced surface still looks stable mirrored or upside down.  Strong outlines mark the selection or the action, not every container.

### Rank the actions

One action per state is primary: the one most players take next.  It gets the emphasis appearance.  Secondary actions are quieter, and rare actions go in a menu.  A destructive action is never primary and never takes focus first.  Keep commands in the same order wherever they appear, so players can use what they learned.

### Match density to the task

Comparison needs several candidates and their deciding facts in view.  Action during play needs a brief glance.  Celebration can give art the room.  Keep the decision, its terms and its commitment visible together.  Never push the commitment below the visible area or inside a long scrolling list.

### Recompose for the room

Wide room can show browsing and detail together.  Compact room shows a complete detail step.  Short room drops decoration, introductions and secondary art before it drops legibility, consequences or exits.  Do not shrink the whole interface to fit a design made for more room.

Facet: VStack, HStack, Grid and ZStack express reading order and layering.  AdaptiveStack turns a row into a column.  ViewThatFits chooses among complete alternatives.  `UI.fill()` takes the remaining room, and `maxWidth` keeps a reading area comfortable.  Composition and Region rank competing HUD groups and swap in their smaller forms.  Read `Layout-options` for sizing.

## Build the visual language

Build the look in two passes.  The functional pass makes the surface usable.  The flourish pass makes it belong to this game.  Start the second pass only when the first one works.

The functional pass:

1. **Values.**  Compose with four to six neutral values, from the background to the strongest content.  Only the focal content and the focus indicator reach the extremes.  Desaturate a capture: if the hierarchy disappears, color is doing work that contrast should do.
2. **Type.**  Use one plain, readable family for body text.  A display face can carry personality in titles and large numbers.  Use a few sizes and keep the meaning of each across the whole game.
3. **Icons.**  Use one family with a consistent stroke and shape.  Icons that navigate or command must be familiar or labeled.  Decorative icons can be expressive.  Check each icon at the size it appears.

The flourish pass:

4. **Accent.**  Choose one accent color, at most two, for focus, the primary action and the current selection.  It becomes the game's signature.  Tint the neutral values toward the world's palette and keep their contrast.  Keep danger, success and warning distinct from the accent, and never let color alone carry a state.
5. **Shape, pattern and material.**  Take them from the game's setting, era and tone: chunky rounded plastic for a toy racer, cut corners and scan lines for a cockpit, parchment and ink for an expedition.  Apply them to frames, corners, headers, backgrounds and transitions.  Never put a pattern under text at a contrast that hurts reading.
6. **Motion character.**  Tune timing to the world: bouncy for a toy box, crisp for an instrument panel.

UI over gameplay sits on a scene that moves and changes brightness.  Protect it with a backing panel, a stroke, a shadow under light marks or a container.  Test it over the brightest and the darkest places in the game.

A palette alone is not an identity.  Two racing games should not look alike: they differ in shape, type, material and motion, not only in hue.  If a screen could belong to another game, the flourish pass is not done.

Facet: the theme owns paint, type, spacing, shape and motion.  Set its values, type and icons before the first screen, and add the flourish once that screen works.  `Facet.themes.define` takes palette roles, typography per role, metrics such as radii and strokes, chrome art for panels, controls, bars and focus, and extra StyleSheet rules.  Read the [visual language chapter](game-ui/VISUAL_LANGUAGE.md), then `Tasks.theme` and `Theme-identity`.

## Choose elements by the decision

Choose each control for what the decision means.  Then adapt its presentation to the room and the input.

- A Toggle sets something on or off.  A Picker chooses among named alternatives.  A Slider or Stepper sets an amount.  A Button runs a command.
- Cards with art present objects that players recognize by sight.  A list presents descriptions, and a Table compares shared attributes.
- Tabs move between destinations; they never edit a value.  A button that cycles through hidden values prevents comparison and correction.

Keep four intentions separate.  **Focus** is where the next input goes.  **Selection** is what the player is considering.  **Activation** opens or operates it.  **Commitment** buys, equips or deletes.  Moving through options never commits.

Prefer recognition to recall.  Show the choices, the current value and the effect before the player acts.  Show the actual object with its silhouette and distinguishing details, a color as a swatch and a pattern as a preview.  Use the game's vocabulary and explicit verbs, such as "Equip Comet" rather than "OK".  Show the change a choice makes: the current and new values side by side, with the difference marked by sign as well as color.  State the consequence before commitment, and put the reason beside an unavailable action.

The [collections](game-ui/COLLECTIONS_AND_ACTIONS.md) and [choices](game-ui/CHOICES_AND_INPUT.md) chapters map decisions to controls.

## Design every state

Give every element a complete set of states.  Make each state distinct beyond color, with shape, label, icon or position.

- **Interaction**: available, focused, pressed, selected, current or equipped, unavailable with a reason, and locked with a route forward.
- **Content extremes**: empty, one, many and full; the shortest and longest names; the longest translation, which can be a third longer than English; the largest number; missing art; the largest text setting.
- **Data**: loading, no items, no matches, offline, failed and stale.  Each one offers its next step: create, clear filters, wait, retry or explain.
- **Urgency**: normal, low and critical.  When alerts compete, the immediate hazard wins, and routine gains wait or combine.
- **Authority**: draft, pending, accepted and rejected.  Sending is not saving, and the server owns game rules and accepted progression.  An incoming accepted value never silently overwrites the player's active draft.  One dismissal policy covers every exit from unsaved work.
- **Waiting**: long loads, matchmaking and teleports.  Show what is happening, how long it takes when that is known, and what the player can do meanwhile.  Never show a frozen screen.

Return players to the state they left: the same query, selection, scroll position and draft.

Facet: Compose cells and formulas bind state without rebuilding pages.  `Tasks.state` and `Tasks.purchase` show accepted results, and `Sheet.dismissal` guards unsaved work.  Skeleton, Notice, Toast and ErrorBoundary cover waiting, persistent state, acknowledgement and recovery.

## Make it feel alive

Feel is the sum of small, immediate answers.

- **Respond at once.**  Every press shows its pressed state in the same frame, even when the result waits for the server.
- **Scale feedback to significance.**  A focus move is a quiet tick.  A confirmation is crisp.  A rare accepted reward earns anticipation, a reveal and a settle.  Routine gains combine, and danger interrupts.
- **Use more than one channel.**  Motion, sound and haptics reinforce each other.  No single channel carries an essential result alone.  Give UI sounds one family, with a distinct sound for focus, confirm, back, error and reward.
- **Explain where things went.**  Pages arrive from the direction of travel.  An item travels to where it is stored.  A value counts to the accepted number.
- **Never make players wait for motion.**  Input stays available, Skip reaches the end state, and reduced motion gives the same result.
- **Keep targets still.**  Hover and focus never move neighbors, and changing numbers reserve their width.

Facet: theme motion tokens drive control transitions through native StyleSheets.  Travel moves an object between slots, `UI.sequence` orders a reveal, Flash marks a target, and `UI.feedback` or a Button's `haptic` plays haptics.  The game plays its own sounds from the same events.  See the [motion chapter](game-ui/MOTION_AND_FEEDBACK.md), `Effect-sequences` and `Haptics`.

## Follow each input's conventions

Each input has conventions that make an interface feel native.  Follow them on every surface:

- **Gamepad.**  A confirms and B goes back on every surface.  Bumpers change peer tabs, triggers page long content, and X and Y are shortcuts for frequent actions that also have a visible route.  Focus is always visible and moves the way the layout looks.  It starts where the player most likely acts, or on the safe choice when a mistake would cost something.  Roblox reserves Escape and the gamepad Start (Menu) button; never bind them.
- **Divide the gamepad.**  Gameplay keeps the buttons that play needs.  The most frequent HUD tasks get the remaining buttons.  Players reach the other HUD tasks by entering HUD selection with ButtonSelect (View) or one game action.
- **Pointer.**  Hover can preview, but it never holds required information.  Show keyboard shortcuts with their keys, and make each shortcut run the same command as its visible control.
- **Touch.**  Size primary thumb actions from `UI.environment().thumbTarget`, and keep every target at least the theme's minimum size.  Put game-owned touch controls, such as a boost button, in Regions of the HUD's Composition so other groups stay clear of them.  Give every gesture a visible alternative, and keep the active field visible above the on-screen keyboard.
- **Mixed input.**  Prompts follow the input in use.  Every valid input keeps working, and a change of input keeps the task and its state.

Make settings for text size, motion and controls reachable before a task demands them.  Every route works with single digital presses: it needs no pointer, analog precision, chord, rapid repeat or long hold.

Facet: `UI.environment` reports room, input, display size, viewing distance, safe and overscan insets, text preference and reduced motion.  Composition keeps the movement stick and D-pad with gameplay.  ShortcutHint and ButtonGuide show the engine's glyphs for real bindings.  Read `environment` for the exact fields.  The [input, focus and access chapter](game-ui/INPUT_FOCUS_AND_ACCESS.md) covers input ownership, focus routes and access.

## Use Facet's mechanisms

Each section above names the Facet mechanism for its level.  Use the native engine first, then Compose, then Facet.  Do not rebuild focus traversal, text editing, layout, scrolling or animation scheduling.  A recipe shows a working structure and its ownership; adapt its content, density and look to the game, because its sample values are not a style.  Read a control's card first, then only the options you still need.

## Verify like a player

1. **Build one connected task first.**  Use real labels, art and data.  Go from the entry through the decision, commitment and feedback to the return, including cancellation and rejection.  Test its most constrained context before you repeat the pattern.
2. **Look at it.**  Inspect captures at the intended viewing size.  The first glance shows the subject, its state and the next action.  Desaturate the capture and check that the hierarchy survives.  Check alignment, clipping and text over the brightest and darkest scenes.
3. **Operate it.**  Use pointer, touch and gamepad at wide, narrow and short sizes.  Change the input and the viewport while the task is open.  Try the largest text setting and reduced motion.  Return to play and check input and focus.
4. **Watch a player.**  When you can, have an unfamiliar player find the task, predict the action, complete it and explain the result without coaching.  Fix the causes of hesitation, wrong turns and missed feedback.  An agent's walkthrough finds gaps; it does not show what players prefer.
5. **Report the evidence.**  Keep technical checks, visual review, input tests and player observations separate.  Name the build, device, inputs and paths you tested.  A capture proves appearance, not reachability, and a simulated size does not prove readability on a physical handheld.

Fix a shared layout or control cause before you copy the pattern elsewhere.

## Chapters

Read the chapter for the task at hand.  The first six run from whole moments of play down to single interactions.  The last three apply at every level.

| Topic | Chapter |
| --- | --- |
| Play, preparation, shared decisions, results and learning | [Moments of play](game-ui/GAME_FLOWS_AND_INFORMATION.md) |
| Page structure, fitting and navigation | [Layout and navigation](game-ui/LAYOUT_AND_NAVIGATION.md) |
| Interruptions, messages and recovery | [Surfaces and feedback](game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md) |
| Browsing, selection and commands | [Collections and actions](game-ui/COLLECTIONS_AND_ACTIONS.md) |
| Values, text and drafts | [Choices and input](game-ui/CHOICES_AND_INPUT.md) |
| Drag, drop and their alternatives | [Direct manipulation](game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) |
| Value, type, icons, color, shape and material | [Visual language](game-ui/VISUAL_LANGUAGE.md) |
| Feedback layers, transitions, reveals and sound | [Motion and feel](game-ui/MOTION_AND_FEEDBACK.md) |
| Input ownership, focus, conventions and access | [Input, focus and access](game-ui/INPUT_FOCUS_AND_ACCESS.md) |

## Sources

- Edd Coates, [The Principles of Game UI/UX](https://www.youtube.com/watch?v=5GiH6th_Za4), the [Game UI Database](https://www.gameuidatabase.com) and [The Game UI Bible](https://www.lostincult.co.uk/shop/p/gameui)
- Celia Hodent, [game UX practice](https://celiahodent.com/ux-practices-epic-games/) and [cognitive psychology for game UX](https://celiahodent.com/cognitive-psychology-applied-to-user-experience-in-video-games/)
- Fagerholt and Lorentzon, [Beyond the HUD](https://odr.chalmers.se/handle/20.500.12380/111921)
- Xbox Accessibility Guidelines on [navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) and [context and consequences](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/114); the [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com)
- Valve, handheld [compatibility](https://partner.steamgames.com/doc/steamhardware/compat) and [recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations)
- Roblox, [ViewportDisplaySize](https://devforum.roblox.com/t/full-release-build-cross-platform-ui-with-the-viewportdisplaysize-api/3880384)
