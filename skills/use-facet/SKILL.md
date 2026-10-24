---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

## Design first

Read [game UI design](references/GAME_UI_DESIGN_GUIDE.md) once before you design.  It holds the principles and the order of work.  Frame the task, map the flow and choose each surface's attention level.  Compose the surface, build the visual language and choose elements.  Design every state, make it feel alive and fit every way of playing.  Its chapters apply that order to specific tasks; recipes show behavior and ownership; API nodes define exact contracts.  Open only the next level the current decision needs.

For a new game, write its visual direction and define the complete theme before the first screen; the [visual language chapter](references/game-ui/VISUAL_LANGUAGE.md) shows how.  Build in full color from the start.  A theme change restyles every surface, so do not build a gray draft first.  Before a new flow, identify the player's goal, the play context, the information priority, the action, the accepted result and the return path.  Infer them from the brief and the existing game, and ask only when a missing decision changes the work.

Prove one complete playable loop before you expand menus.  Use representative content and the most constrained supported context early.  Test the first use of each layout or interaction in Play before you repeat it across the game.  Inspect the page, its body and the gameplay behind it together before you copy a pattern.  Watch whether a player can find, predict and complete the task without coaching.

## Find the contract

In Studio, read StringValue `Value`s under `ServerStorage.FacetDocs`.  Folders follow repository paths: `Tasks.hud` is `docs/reference/nodes/Tasks.hud.md`.  With filesystem access, use `lute run tools/facet docs <node>` or `docs --search TEXT`.  Read `<Control>.card` for the entry point, then follow its props or reference link for exact options.  `Icons.names` lists glyphs.  These nodes are available in the installed docs and the CLI.  Use `Map` only when the task has no known route.

| Need | Read |
| --- | --- |
| Which control fits a decision | [Control map](references/CONTROL_MAP.md), then the control's card |
| First mount or existing Compose integration | `Mounting.Facet.app` |
| Visual direction and theme | Visual language chapter, then `Tasks.theme` and `Theme-identity` |
| Competing gameplay HUD groups | `Tasks.hud`, then `Composition.regions` if needed |
| Destination from gameplay, input ownership and Back | `Tasks.pages` |
| Gamepad entry into a passive HUD | `responder` |
| Mixed input, text size or viewing distance | Input chapter, then `environment` |
| Collection and selected detail | `Tasks.collection-detail` |
| Boolean settings or named choices | `Toggle.card`, `Picker.card` |
| Object identity, art and selection | `Card.card`, `Stage.card` |
| A bounded interruption or dirty dismissal | `Tasks.sheet`, `Sheet.dismissal` |
| Server-accepted state | `Tasks.state` |
| Reactive types or collection signatures | `Types.reactive` |
| Lower-corner controls and movement clearance | `Tasks.safe-layout` |
| Missing signature | The control's card or props node |

Batch independent known nodes.  Do not reread nodes already in context or load the whole reference.  Use implementation source only to diagnose a contradiction with a named contract.  If installed docs are missing, report that gap instead of inventing options.

## Build one owned tree

Locate the installed Facet module.  In Studio-only work, edit persistent scripts in Edit mode; Play changes are temporary.  In a filesystem project, follow the [filesystem workflow](references/FILESYSTEM_WORKFLOW.md).

Use `Facet.Compose` and `Facet.Roblox` for a new game.  In an existing Compose game, call `Facet.bind(Compose, ComposeRoblox)` with that same copy.  Create one `Facet.app`, call `app.mount` once and reuse `app.UI`.  Screens, pages and overlays are components, branches or portals of that tree.

Name `app.runtime.constructors` `Host`.  Put Host-created children in the parent's positional child list.  A node-valued property such as `Parent` needs `Compose.static(node)` when that node is Compose-owned.  Compose owns state, branching, motion and cleanup.  Read cells with `use` in property functions and `peek` in callbacks; write with `set` or `update`.  Create branch-owned reactive values inside the branch.  Keep durable row state, selection and drafts in the model.

Separate rapidly changing gameplay readouts from inventory and settings state.  Update only changed values; a timer tick never rebuilds a page or refreshes every record.  Reuse small components and data-driven artwork across objects.

Use strict Luau, concrete shared types and named constructors.  Native properties keep their Roblox names; Facet options use lower camel case.  Do not cast through `any`.

## Apply the library

Use Facet controls for their supported behavior.  Host objects supply game art, minimaps and Stage scene content, not a replacement button or input system.  Use the engine first, then Compose, then Facet before you write a custom mechanism.  Read the [Compose skill](../compose/SKILL.md) only for an operation outside this path.

The theme owns paint, typography, spacing, shape and motion.  Use semantic roles and tokens, and derive the theme from the game's world; a recipe's sample palette is not a style.  Use Stage when the player needs to inspect a 3D object, and frame the actual subject.  Use stable model keys in VirtualList, VirtualGrid and Table, and choose collection density from what players must recognize or compare.

Use `UI.fill()` for the room left beside siblings; `width = "fill"` spans the parent's width.  Express layout intent with hug, stretch and zones.  Bound collections and wrapped text at the task boundary.  Wrapped text fills the width and grows vertically; short readouts can hug without wrapping.  Do not use TextScaled.  Keep HUD Region nodes stable and branch inside their forms.  Fix fit warnings and shared sizing faults instead of adding game-specific measurement loops.

Use the whole screen.  Safe insets bound text and controls, not art or backgrounds.  Put compact HUD items in the top bar's free strip with `zone = "topbar"` Regions.

Composition is a passive HUD: gameplay keeps the movement stick and the D-pad.  Give each frequent HUD task a free gamepad button and a visible input hint.  Reach the other HUD tasks through ButtonSelect or one game action that enters HUD selection (`HUD-actions`).

The game owns server validation and accepted state.  Distinguish a draft, a pending request, acceptance and rejection; sending is not saving.  Keep one keyed LocalizationTable and translator path, including fixed labels; FormatByKey arguments are strings.  Disable AutoLocalize for translated and player text, and give the app its translator for Facet-owned labels.

## Verify the task

Inspect each distinct pattern at wide, narrow and short sizes, including both phone orientations.  Use Play, real input, Output, Script Analysis and captures.  Check completion, cancellation, rejection, return, gamepad focus, touch clearance and a viewport change while the task is open.  Elapsed time or a changed label does not prove a game effect.

Review gameplay and UI together for hierarchy, clipping, truthful state and visual coherence.  Judge the hierarchy by lightness and size, ignoring hue: the focal area and the next action still lead.  Check whether the player can predict an action and identify its result, not only whether the control responds.  Fix persistent scripts, restart Play and confirm that the changes survive.  Save through the normal project workflow.  Keep reads and patches bounded, and check match counts when you replace Studio Source.  Report tested paths and limits; a screenshot or a targeted check is not complete evidence.

In the Facet repository, follow [AGENTS.md](../../AGENTS.md) before changes.
