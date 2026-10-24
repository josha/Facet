---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

## Start with one task

Read [game UI design](references/GAME_UI_DESIGN_GUIDE.md) once. It defines the
design principles and the capture correction loop. For the next task, read its
chapter and recipe from the table below, then the cards for the controls you use.
Do not load chapters for later work. Include Input when choosing input or access
behavior, and Adaptive manipulation for gestures or value adjustment.
Recipes show behavior and ownership; cards define exact options.

Build one small playable loop before expanding menus: enter, act through normal
input, observe the actual game effect and accepted result, then return.
Use representative content in the most constrained supported context.
Check Client and Server errors, repair persistent Edit scripts, restart Play
and repeat. Capture gameplay and UI together, correct the composition, then
reuse the working structure. If capture is unavailable, report visual review
as unverified and continue useful functional checks; bounds do not prove appearance.

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
| First gameplay HUD: objective, readouts and command | [Game flows](references/game-ui/GAME_FLOWS_AND_INFORMATION.md), then `Tasks.hud` |
| Destination from gameplay, input ownership and Back | [Layout](references/game-ui/LAYOUT_AND_NAVIGATION.md), then `Tasks.pages` |
| Gamepad entry into a passive HUD | `responder` |
| Mixed input, text size or viewing distance | [Input](references/game-ui/INPUT_FOCUS_AND_ACCESS.md), then `environment` |
| Gestures or value adjustment across inputs | [Adaptive manipulation](references/game-ui/ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md), then the control's input contract |
| Collection and selected detail | [Collections](references/game-ui/COLLECTIONS_AND_ACTIONS.md), then `Tasks.collection-detail` |
| Quick chat, emotes or another quick choice during play | `RadialMenu.card` |
| Boolean settings or named choices | [Choices](references/game-ui/CHOICES_AND_INPUT.md), then `Toggle.card`, `Picker.card` |
| Inspection art beside a decision and action | `Tasks.inspect`, then `Stage.card` |
| Object identity in a collection | `Card.card` |
| Container and text sizing | `Layout-options`, `Text.card`, `fill` |
| A bounded interruption or dirty dismissal | [Surfaces](references/game-ui/SURFACES_INFORMATION_AND_FEEDBACK.md), then `Tasks.sheet`, `Sheet.dismissal` |
| Visual system | `Tasks.theme` |
| Transitions and reward motion | [Motion](references/game-ui/MOTION_AND_FEEDBACK.md), then `Custom-transitions` |
| Server-accepted state | `Tasks.state` |
| Confirming a purchase the server must accept | `Tasks.confirm` |
| Reactive types or collection signatures | `Types.reactive` |
| Lower-corner controls and movement clearance | `Tasks.safe-layout` |
| Missing signature | The control's card or props node |

Batch independent known nodes for the current task. Follow a card's links rather
than guessing node names. Do not reread nodes already in context or load the
whole reference. Use implementation source only to diagnose a contradiction
with a named contract. Report missing installed docs instead of inventing options.

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
tokens. Host objects and Stage supply game artwork; sample sizes and cameras
apply to the sample's subject. Use stable model keys in VirtualList, VirtualGrid
and Table. Keep HUD Region nodes stable and branch inside their forms.

Container options do not apply to every control. `width`, `height`, `gap` and
`padding` belong to layout containers; Text and Button have no `width` option.
Use parent `align = "stretch"` for the cross axis or a `UI.fill()` child for
remaining space along the stack. Use native `Size` and `AutomaticSize` for an
explicit leaf size. Wrapped Text fills its bounded parent's width and grows
vertically; short readouts can hug without wrapping. Read `Text.card` before
making a text helper. Do not use TextScaled or game-specific measurement loops
to hide a sizing fault.

The game owns server validation and accepted state. Distinguish a draft, a
pending request, acceptance and rejection. Sending is not saving. Keep one keyed
LocalizationTable and translator path, including fixed labels; FormatByKey
arguments are strings. Disable AutoLocalize for translated and player text.
Give the app its translator for Facet-owned labels.

## Verify the task

Use Play, real input, Output, Script Analysis and captures. Test each distinct
pattern at wide, narrow and short sizes, including both phone orientations.
Check completion, cancellation, rejection, return, gamepad focus, touch clearance
and an open viewport change. Elapsed time or a changed label does not prove a
game effect. The design guide explains visual and player review.

In Studio, splice literal Source fragments instead of passing code through
pattern replacements. This preserves `%` in code and rejects missing or duplicate
matches. Apply changes to a local string; write Source after they all validate.

```luau
local function replaceOnce(source: string, old: string, replacement: string): string
    assert(old ~= "", "Empty source fragment")
    local first, last = string.find(source, old, 1, true)
    assert(first and last, "Source fragment not found")
    assert(not string.find(source, old, first + 1, true), "Source fragment is not unique")
    return string.sub(source, 1, first - 1) .. replacement .. string.sub(source, last + 1)
end
```

Save through the normal project workflow. Report the build, inputs and paths
tested, with their limits. A screenshot or targeted check is not complete evidence.

In the Facet repository, follow [AGENTS.md](../../AGENTS.md) before changes.
