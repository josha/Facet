---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

Read [the game UI design guide](references/GAME_UI_DESIGN_GUIDE.md) once. For a new screen, read
its design workflow. Read task chapters for the decisions the work introduces; reuse that guidance
across similar tasks. Keep work within the user's scope.

Define the player's decision, visible result and return path before choosing controls. Establish
an attention order and a coherent theme. Give the task's object a focal area, its decision a clear
comparison, and its main action stronger emphasis than navigation. Use recognizable glyphs with
labels for compact destinations; keep unfamiliar commands in words. A shared control helper must
preserve icon, appearance, selected and disabled states. Render one complete task at wide and
compact sizes before spreading its pattern.

## Bootstrap once

Use the project's persistent authoring path. Files are authoritative in a filesystem project; in
Studio-only work, edit scripts in the Edit data model. Play changes are temporary. Locate the
installed Facet module before choosing its require path; use the project's supported installation
path if it is absent.

Use one Compose copy and one owned UI tree in each execution context. For a new game use
`Facet.Compose` and `Facet.Roblox`; for an existing Compose game bind once with
`Facet.bind(Compose, ComposeRoblox)` from that copy. Make one `Facet.app` and call `app.mount`
once. Reuse `app.UI`; name `app.runtime.constructors` `Host`. Screens and overlays are components,
branches or portals of that tree. Keep Roblox ownership of physics, replication and engine-created
objects. See `Mounting.Facet.app` for the bootstrap and lifetime.

Host-created children belong in their parent's positional child list. `Parent` can target an
existing engine object; do not use it to connect separately owned UI. Compose owns branching,
animation and cleanup. Use `cell`, `formula`, `show`, `keyed` and `cleanup`; create branch-owned
reactive values inside that branch. Read cells with `use` in property functions and `peek` in
callbacks. Write with `set` or `update`.

Use strict Luau and concrete shared types before copying helpers. Use named constructors, lower
camel case control options and native Roblox property names. Get exact signatures and option
values from the installed API docs. Do not cast through `any`.

Keep one keyed English source table that builds the game's `LocalizationTable`. Every
player-facing string comes from a key, including fixed labels. Format keys through the translator
in a readable; arguments to `FormatByKey` are strings. Check that code keys exist. Disable
`AutoLocalize` for already translated text and player text. Give the app its translator for
Facet-owned strings. All task components share this localization path. See
`Factory-options.keyboardNavigation` for translator behavior and keys.

## Compose the task

Choose controls by behavior using the design guide's control table and index. Use value controls
for choices and navigation controls for pages. Use Facet's supported controls for values,
progress, time, status, collections, previews, guidance and task surfaces. Do not redraw their
behavior with Frames or generic buttons. Host objects are for content no control shows, such as
game art, minimaps and Stage scene content. Extend a missing control option or theme rule and
report the gap instead of replacing the control.

Use VirtualList, VirtualGrid or Table for interactive collections, with durable row state and
stable keys in the model. Keep the server authoritative for game state and validation. Bind
accepted values to the live server model, keep drafts separate, and distinguish pending, accepted
and rejected requests. Sending is not saving. Guard dirty dismissal with one decision for every
route; use Sheet's dismissal contract.

The theme owns paint, type, spacing and motion. Use semantic text roles and appearance tokens.
Keep focus, selection, equipped, unavailable and pending states distinct beyond color. Show the
actual object with Stage when appearance is the decision; bind it to the draft. Do not replace the
preview with a summary.

Give layout intent with hug, fill, stretch and zones. Fix a shared sizing fault in Facet rather
than measuring and setting sizes in game code to hide it. Give each HUD group its own Region;
groups in one top or bottom zone share a row and wrap when needed. Keep panels and actions
distinct in smaller forms. Use panel surfaces, theme chrome and semantic status for depth and
state. See `Composition.layout` for row sizing and `Tasks.theme` for the visual system.

Bound task width before fill collections or wrapped text; let wrapped text grow vertically. Let
short readouts hug. Do not set `TextScaled`. Use one Composition for competing core-safe HUD
groups, with measurable forms from richest to narrowest. Keep Region nodes stable and put
`Compose.show` inside a form. Preserve every required destination and action in the smallest form,
including a portrait phone about 320 pixels wide. Let Composition choose forms from available
room; do not add device switches. Fix fit warnings. Use environment-scaled lengths and text roles
where relevant. See `Composition.regions`, `HUD-actions` and `ProgressView.reference` for form
sizing.

Use the free top-bar strip for compact navigation or readouts instead of pushing every group
below it. Give strip regions a form 44 pixels tall and let Composition handle the changing
`GuiService.TopbarInset` and fallback. See `Composition.adaptation` for strip layout.

Protect the camera's focus area, including from UI attached to the avatar, and keep what the
player watches outside the area covered by a held thumb. Check both phone orientations.
Protect device/TV safe areas and native movement controls. Give primary thumb
gameplay actions `target = "thumb"` and size their art from `UI.environment().thumbTarget`. Show
gameplay commands only in applicable states. Use native InputAction/InputContext for game
commands; controls own their input and selection. Do not bind Escape or gamepad Start. Make
keyboard/pointer, touch and gamepad paths complete, with readable focus and reliable Back/return.
Support localization, larger text and reduced motion. Choose Sheet placement and exits
deliberately; check every dismissal route and detent. Hover, press and focus must not resize
hugging surfaces or move targets.

## Find only the missing detail

Use the supplied docs, not implementation source, to learn Facet. In Studio read document
StringValue `Value`s under `ServerStorage.FacetDocs`; its folders follow the documentation paths.
`Tasks.hud` means `docs/reference/nodes/Tasks.hud.md`. With shell access use `lute run tools/facet
docs <node>` or `docs --search TEXT`. `<Control>.card`, `<Control>.props` and `Icons.names` are
generated; read them from the installed docs or CLI, not a source Markdown path. Cards give entry
points; props give typed options and defaults. If required docs are inaccessible, request access
rather than inventing signatures.

Read one main recipe and another only for a missing pattern. HUD plus shop normally needs
`Tasks.hud` and `Tasks.shop`; `Tasks.sheet` adds route/dismissal behavior when needed. Use their
component bodies inside the single bootstrap, not another app per recipe. Read `Map` when a task
has no known route. Open cards/options only for missing details and never reread a node already in
context. Batch independent, already identified nodes in one tool read, keeping each node bounded
and labeled. Read dependent links after choosing which detail is needed. Use one matching
`examples/blocks/` starter only if recipes do not fit.

Use `Tasks.theme` for art direction, `Tasks.state` for live accepted state, `Types.reactive` for
shared reactive types, `Sheet.dismissal` for dirty dismissal, and `Tasks.safe-layout` before
lower-corner readouts or controls. Exact HUD sizing, forms, text sizing and ownership edge cases
live in their linked reference nodes. Read only what the current decision needs.

For missing behavior check native Roblox APIs, Compose, Facet controls, then game code. Read the
[Compose skill](../compose/SKILL.md) for operations outside this path. Inspect Facet source only
to diagnose behavior contradicting a named doc node; report that behavior and gap. In the Facet
repository read [AGENTS.md](../../AGENTS.md) before changes.

## Verify the complete result

Check first mount and each distinct pattern before reuse. Complete, cancel, reject and reopen
affected tasks at wide and compact sizes with supported inputs. Test the promised game effect, not
only the changed label. Use Script Analysis, Output, Play, device emulation, input and captures.
Inspect actual gameplay and UI together for hierarchy, clipping, legibility, focus, truthful state
and compact access. Technical checks do not establish visual quality.

Fix persistent scripts, restart Play, and confirm changes survive stopping Play. Save through the
normal project workflow. Filesystem projects also follow [the filesystem
workflow](references/FILESYSTEM_WORKFLOW.md). Report what was tested and tools or paths that were
unavailable; do not claim a verifier ran when it did not.

Keep reads and updates bounded to affected code. Patch Studio Source with a checked match count;
do not print entire files. Batch related state queries, limit descendants to the affected panel,
capture each distinct layout/device after a coherent change, and capture again for unresolved
visual defects. Inspect images, never image bytes or complete payloads. Return concise evidence
and remaining limits.
