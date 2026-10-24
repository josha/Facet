---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

## Design principles

- **Start with the player's intent.** Compose the situation, choice, action and
  result as one connected task. Preserve the game's intended challenge; remove
  accidental difficulty in understanding or operating the UI.
- **Make the game recognizable.** Let its world and objects shape the art,
  framing, type and motion. A palette alone is not an identity.
- **Direct attention.** Give the subject and next useful action clear priority.
  Use quieter context, deliberate space and meaningful feedback around them.
- **Preserve the task across inputs and sizes.** Recompose around available
  room, reach and viewing distance. Input, screen space and text size are separate
  decisions. Keep identity, consequences and exits usable.
- **Earn the player's trust.** Distinguish intent from accepted results. Preserve
  useful state and make navigation, focus and gameplay input return predictably.

Read [game UI design](references/GAME_UI_DESIGN_GUIDE.md) once for how to apply
these principles. Before a new flow, identify the player's goal, play context,
information priority, action, accepted result and return path. Infer these from
the brief and existing game; ask only when a missing decision changes the work.
Read the matching task chapter before choosing its controls or layout.
Include Input for mixed input or accessibility, and Adaptive manipulation for
gestures or value adjustment. Read the chapter text, not only its name.
Recipes show behavior and ownership; API nodes define exact contracts.
Open only the next level needed for the current decision.

Choose the task surface before writing shared page helpers. Mount Composition
directly for gameplay HUDs. Use `Tasks.pages` for a destination that replaces
gameplay and `Tasks.collection-detail` when browsing and inspection belong
together. A Sheet is a bounded interruption. Its scrolling body does not supply
a page hierarchy or a collection/detail arrangement.

Build one small playable loop before expanding menus: enter, act through normal
input, observe the actual game effect and accepted result, then return.
Check Client and Server errors. Restart Play from persistent Edit scripts and
repeat before copying the pattern. Use representative content in the most
constrained supported context. Check whether a player can find, predict and
complete the task without coaching. Obtain a native Play capture of the combined
page and gameplay before repeating its structure. If capture is unavailable,
keep visual review unverified and continue useful functional checks and repairs;
instance bounds alone do not show visual hierarchy.

## Find the contract

In Studio, read StringValue `Value`s under `ServerStorage.FacetDocs`.
Folders follow repository paths: `Tasks.hud` is
`docs/reference/nodes/Tasks.hud.md`. With filesystem access, use
`lute run tools/facet docs <node>` or `docs --search TEXT`.
Read `<Control>.card` for the entry point, then follow its props or reference
link for exact options. `Icons.names` lists glyphs. These nodes are available
in the installed docs and CLI. Use `Map` only when the task has no known route.

| Need | Read |
| --- | --- |
| First mount or existing Compose integration | `Mounting.Facet.app` |
| Competing gameplay HUD groups | [Game flows](references/game-ui/GAME_FLOWS_AND_INFORMATION.md), then `Tasks.hud` |
| Destination from gameplay, input ownership and Back | [Layout](references/game-ui/LAYOUT_AND_NAVIGATION.md), then `Tasks.pages` |
| Gamepad entry into a passive HUD | `responder` |
| Mixed input, text size or viewing distance | [Input](references/game-ui/INPUT_FOCUS_AND_ACCESS.md), then `environment` |
| Gestures or value adjustment across inputs | [Adaptive manipulation](references/game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md), then the control's input contract |
| Collection and selected detail | [Collections](references/game-ui/COLLECTIONS_AND_ACTIONS.md), then `Tasks.collection-detail` |
| Boolean settings or named choices | [Choices](references/game-ui/CHOICES_AND_INPUT.md), then `Toggle.card`, `Picker.card` |
| Object identity, art and selection | `Card.card`, `Stage.card` |
| A bounded interruption or dirty dismissal | [Surfaces](references/game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md), then `Tasks.sheet`, `Sheet.dismissal` |
| Visual system | `Tasks.theme` |
| Server-accepted state | `Tasks.state` |
| Reactive types or collection signatures | `Types.reactive` |
| Lower-corner controls and movement clearance | `Tasks.safe-layout` |
| Missing signature | The control's card or props node |

Batch independent known nodes. Do not reread nodes already in context or load
the whole reference. Use implementation source only to diagnose a contradiction
with a named contract. If installed docs are missing, report that gap instead
of inventing options.

## Build one owned tree

Locate the installed Facet module. In Studio-only work, edit persistent scripts
in Edit mode; Play changes are temporary. In a filesystem project follow the
[filesystem workflow](references/FILESYSTEM_WORKFLOW.md).

Use `Facet.Compose` and `Facet.Roblox` for a new game. In an existing Compose
game, call `Facet.bind(Compose, ComposeRoblox)` with that same copy. Create one
`Facet.app`, call `app.mount` once, and reuse `app.UI`. Screens, pages and
overlays are components, branches or portals of that tree.

Name `app.runtime.constructors` `Host`. Put Host-created children in the
parent's positional child list. A node-valued property such as `Parent` needs
`Compose.static(node)` when that node is Compose-owned.
Compose owns state, branching, motion and cleanup. Read cells with `use` in
property functions and `peek` in callbacks; write with `set` or `update`.
Create branch-owned reactive values inside the branch. Keep durable row state,
selection and drafts in the model.
Separate rapidly changing gameplay readouts from inventory and settings state.
Update only changed values; a timer tick should not rebuild a page or refresh
every record. Reuse small components and data-driven artwork across objects.

Use strict Luau, concrete shared types and named constructors. Native properties
keep Roblox names; Facet options use lower camel case. Do not cast through `any`.
Check unfamiliar native constructors, datatype operations and members with a
small native probe before sharing that code. Use the intended data model and
inspect the result or error; a strict directive does not execute the path.

## Apply the library

Use Facet controls for their supported behavior. Host objects supply game art,
minimaps and Stage scene content, not a replacement button or input system.
Use the engine first, then Compose, then Facet before writing a custom mechanism.
Read the [Compose skill](../compose/SKILL.md) only for an operation outside this path.

The theme owns paint, typography, spacing and motion. Use semantic roles and
tokens. Use Stage when the player needs to inspect a 3D object; frame the actual
subject. Use stable model keys in VirtualList, VirtualGrid and Table.
Choose collection density from what players must recognize or compare.
The layout chapter covers bounded scrolling and grids that fit their content.
Treat sample sizes and cameras as dimensions for the sample's subject. Give
inspection artwork its own room and framing; do not reuse a thumbnail's fixed
height inside a larger detail area.

Use `UI.fill()` for remaining space beside siblings; `width = "fill"` spans
the parent's width. Give layout intent with hug, stretch and zones. Bound
collections and wrapped text at the task boundary. Wrapped text fills width and grows vertically;
short readouts can hug without wrapping. Do not use TextScaled. Keep HUD Region
nodes stable and branch inside their forms. Fix fit warnings and shared sizing
faults instead of adding game-specific measurement loops.

Composition is a passive HUD: gameplay keeps the movement stick and D-pad.
Give each HUD task a gamepad button action and a visible input hint.

The game owns server validation and accepted state. Distinguish a draft, a
pending request, acceptance and rejection. Sending is not saving. Keep one keyed
LocalizationTable and translator path, including fixed labels; FormatByKey
arguments are strings. Disable AutoLocalize for translated and player text.
Give the app its translator for Facet-owned labels.

## Verify the task

Inspect each distinct pattern at wide, narrow and short sizes, including both
phone orientations.
Use Play, real input, Output, Script Analysis and captures. Check completion,
cancellation, rejection, return, gamepad focus, touch clearance and an open
viewport change. Elapsed time or a changed label does not prove a game effect.

Review gameplay and UI together for hierarchy, clipping, truthful state and
visual coherence. Check whether the player can predict an action and identify
its result, not only whether the control responds. Fix persistent scripts,
restart Play and confirm the changes
survive. Save through the normal project workflow. Keep reads and patches bounded;
check match counts when replacing Studio Source. Report tested paths and limits,
without treating a screenshot or a targeted check as complete evidence.

In the Facet repository, follow [AGENTS.md](../../AGENTS.md) before changes.
