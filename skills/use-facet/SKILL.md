---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

## Design

Read [Designing game interfaces with Facet](references/GAME_UI_DESIGN_GUIDE.md)
before planning, building, changing or reviewing UI. Its foundations are required
reading unless already in context. Use its task map to read the chapters relevant
to the work; do not load every chapter by default. For a new screen, also read
the design workflow. For a local decision, use the control index and compare
the nearest alternatives.

Choose from the player's task, information hierarchy and interaction, then map
the choice to Facet controls and options. Define compact forms and input behavior
where affected. Keep the work within the user's scope.

Establish one rendered task before spreading its helpers across the game.
Give the task's object a focal area, its decision a clear comparison, and its
main action stronger emphasis than navigation. Use recognizable glyphs with
labels for compact destinations; keep unfamiliar commands in words. A shared
button helper must preserve icon, appearance, selected and disabled states.
Use value controls for choices and navigation controls for pages. Review the
actual wide and compact composition before reusing it; a column of commands
does not establish the game's visual language.

## Find implementation details

Use the project's existing authoring path. In a filesystem project, saved
files are the source of truth. In Studio-only work, edit the persistent scripts
in the Edit data model with the available Studio tools; Play changes are
temporary. Locate the installed Facet module before choosing its require path.
If it is missing, use the project's supported package installation path.

After the design guide, read `docs/reference/nodes/Map.md` from the supplied
documentation. When the place includes `ServerStorage.FacetDocs`, its folders
follow these paths and its StringValues hold the document text. Read their
`Value` through the Studio tools. A reference such as `Tasks.hud` means
`docs/reference/nodes/Tasks.hud.md`. If the reference is not
accessible, request access rather than guessing signatures. Read the
recipe for the main structure, then another only when it supplies a missing
pattern. For a HUD with a shop, `Tasks.hud` and `Tasks.shop` cover the two
structures. Reuse those patterns across similar pages. A long feature list
does not require reading every recipe before building.
Open a control card or option node only for a missing detail.
Use `<Control>.card` for a control's entry point,
`<Control>.props` for typed options and defaults, and `Icons.names`
for icon names. Learn Facet and its
tools from the docs, not from their source. Read the source only to diagnose a
suspected Facet bug, when observed behavior contradicts a doc node. Name that
behavior and node first, then report the gap.
Never reread a node already in context. Read one bounded node at a time.
Read one matching starter in
`examples/blocks/` only if the recipe does not fit.

## Build

Use one Compose copy and one owned scene tree in each execution context.
Facet controls and native `Host` objects belong to that tree; branches and
portals keep their ownership when they render elsewhere. Do not maintain a
parallel imperative UI tree. The client and server have separate roots.
Roblox still owns physics, replication and engine-created objects.
For a new game, use `Facet.Compose` and `Facet.Roblox`. If the game already
uses Compose, bind Facet once with `Facet.bind(Compose, ComposeRoblox)` from
that same copy and use the returned Facet table throughout the context.

- Make one `Facet.app({ name, parent })` and one `app.mount(component)`.
  Use `app.UI` for controls. Name `app.runtime.constructors` `Host` for native
  objects. Each screen is a Compose branch or portal of this tree.
- Put Host-created objects in their parent's positional child list, such as
  `Host.InputContext { action }`. Do not pass an owned object as `Parent`.
  `Parent` can point to an existing engine object, such as the player's PlayerGui.
- Use named constructors: `UI.Button "Save" { label = "Save" }`. Use strict
  Luau without `any` casts. Control options use lower camel case; native
  properties keep their Roblox names.
- Take each option's values from `docs <Control>.props`, not from another
  option: `controlSize` is `xsmall`, `compact`, `regular` or `large`, and
  `default` is a `role`. Through an `any` cast a wrong value fails only when
  its branch mounts, which may be a narrow form that a wide screen never
  shows.
- Build each element from a Facet control when one shows that kind of
  information. A meter, gauge, charge or row of pips is a `ProgressView`
  (`segments` for pips, `trail` for a loss). Standings and results are a
  `Table`. A clock is a `Timer`. A short status mark is a `Badge` or a
  `StatusIndicator`. A brief acknowledgement is a `Toast`. Text is `Text` or
  `Label` with a `textRole`. A backing behind HUD readouts is a stack with
  `surface = "panel"`. A shop or store item is a `Card`; without art it is a
  text card with a title, a caption and a primary action. Do not draw these with native Frames, list
  layouts and fixed sizes: a copy does not get the theme, scaled metrics,
  reduced motion, accessible names or compact forms. Use `Host` objects only
  for content that no control shows, such as a minimap or custom art.
  When appearance is the decision, show the actual object with `UI.Stage`.
  Read `Stage.card` for its owned camera and content pattern.
  Bind the preview's visible properties to the draft;
  a text summary does not replace a preview of color, shape or decoration.
  Use `Callout` for guidance attached to a live action, `RadialMenu` for a
  wheel of quick choices, and `Slider` or `Toggle` for settings. Read their
  cards when those tasks are required; generic Sheets and buttons do not
  supply their anchoring, input, or value-editing behavior.
- When a control does not have an option that the game needs, such as a
  color for each segment, add the option to Facet or a rule to the theme and
  report it. Do not replace the control with native objects. Before you
  extend a hand-built element, find its control in the control index and
  replace the element.
- Give layout intent, such as hug, fill, `align = "stretch"` or a zone, and
  let Facet size the result. When a Facet layout looks wrong, fix the control
  in Facet and add a test. Examples are a readout that wraps below its bar, a
  number that overflows its plate, a row of panels with different heights and
  a stretched column with different widths. Do not measure and set sizes in
  the game to hide the fault.
- Use `Facet.Compose`: `cell` for local state, `formula` for derived values,
  `show` for branches, `keyed` for children and `cleanup` to release resources.
  Read cells with `use(cell)` in property functions and `cell:peek()` in
  callbacks. Write with `cell:set(value)` or `cell:update(fn)`.
  Use `function(use: Facet.Use)` when a property reads different cell types.
  Type shared state and reusable helper arguments before using them across
  screens. Use `Facet.ValueString`, `Facet.TextRole` and `Facet.Activate`
  for the corresponding helper arguments. Give collection specs their row
  and key types. Check these shared pieces before expanding the UI;
  one untyped helper can produce errors at every call. See `Types.reactive`.
- Use VirtualList, VirtualGrid or Table for interactive collections. Keep
  durable row state in the model. The server owns game state and validates
  requests. Bind accepted values to the current server model, not a copy taken
  when the panel opened. Keep editable drafts separate. Sending a request is
  pending; update accepted state and mark the draft saved only after acceptance.
  Guard dirty Sheet dismissal with `onPresentedChange`, using one decision for
  Close, Back, outside press, and drag; read `Sheet.dismissal`. Disabling a
  dismissal route does not implement a discard confirmation.
- The theme owns paint, type, spacing and motion. Turn the art direction of
  the brief into a theme with `Tasks.theme`: palette roles, readable type and
  surfaces that stay visible over the scene. Use quiet boundaries to group
  items and stronger emphasis for the current action or selection.
  Use `textRole`, `appearance`, `gap` and `padding` tokens. Give a padding
  table a type first: `local inset: Facet.Sides = { top = "xl" }`.
  Wrapped text fills its parent width and grows vertically. Give its parent
  a numeric width, or `width = "fill"` inside a bounded parent. Let short
  readouts hug their text; do not set `wrap = true` in a helper for every label.
  Do not set `TextScaled`.
- Keep core-safe HUD groups in one Composition. Facet warns when two
  Compositions on one screen place regions in the same zone. Use stable
  region widths and smaller forms before you let a region drop. Use
  `UI.environment` or adaptive controls for size changes. Do not branch on
  the device. For a length the game owns, use `UI.environment().scaled(64)`.
  A root Composition keeps its zones inside the TV safe area; do not offset a
  zone by hand.
  Add a type role, `scaled(64, "body")`, when the length sits beside text.
- Use `Tasks.hud` as a starting point. Choose zones from the game's sight lines
  and controls. Consider `topRight` below the engine top bar for secondary
  navigation; preserve its destinations in a compact Menu. Let Composition
  apply the safe area. Captioned circles suit recognizable icons; labeled buttons
  suit commands that need words. Keep navigation and readouts distinct in one
  Composition. Open `HUD-actions` for sizing and selection.
- Give each HUD group its own region. Put readouts that share a sight line,
  such as level progress and a timed goal, in one `top` or `bottom` zone.
  That zone shows them side by side while the row has room and wraps a region
  to a new row when it does not. Do not stack two groups in one region. The
  regions of one row take one height (Composition `rows`). The region content
  takes that height. Make the panel the region content, or hold it in an
  HStack with `align = "stretch"`. Give the panel `distribute = "center"`.
  A region that is empty, such as a match scoreboard between matches, takes
  no room.
- Give HUD panels depth and state through the theme. A theme
  `chrome.panel = { kind = "native", shadow = "raised" }` gives every
  `surface = "panel"` stack, Dialog and Alert the shadow. Use
  `status = "warning"` on a stack for a state, such as a full bag: the plate,
  its text, icons and bars take the status colours.
- Give each region forms from the richest to the narrowest. The narrowest
  form must fit a portrait phone, about 320 pixels wide. For example, a row of
  buttons, then the main button over the others, then one column. A narrower
  form makes its parts smaller or moves them. It keeps each panel and each
  button apart: do not put a button inside a readout's panel to save room.
  Let the Composition choose the form. Do not choose a layout in a region with
  `isCompact`, `isLandscape` or a fixed `AdaptiveStack` axis. A plain HStack
  never wraps. The Composition warns when a region does not fit at its last
  form. Fix each warning.
- The row of the Roblox top bar is screen space for the HUD too. Do not push
  every zone below it. Put compact pieces in `topbar` regions, level with the
  Roblox buttons: a menu or settings button, a coin readout, a short status.
  Use `leading = true` beside the Roblox buttons and `trailing = true` at the
  far edge. The strip is as wide as `GuiService.TopbarInset` leaves free, and
  that space shrinks when Roblox shows more buttons, such as voice chat or a
  larger chat button. Give each strip region a form 44 pixels tall. Let the
  Composition move a region below the bar when the strip cannot hold it.
  Open `Composition.regions` for options and `Composition.adaptation` for strip
  layout. Open `Composition.layout.step-down` for fallback and fit warnings.
  Read one referenced node for each missing detail.
- Let a text box hug its text, or use `textSize = { fit = ... }` in a box of
  fixed size. A label can be twice as long in another language.
- A bar `ProgressView` without a label shows its value and `endLabel` on the
  bar's row. Do not add a separate Text for a percentage.
- A bar `ProgressView` fills the width of its container. In a box that hugs
  its content, give the bar a width, such as
  `Size = UDim2.fromOffset(width, 0)` with a `scaled` width. A fill child
  does not size a hug box, so the box can take the width of the slot where
  the Composition measures it, and stay that wide.
- A `show` branch disposes the formulas that its content makes, `scaled`
  results too, when it hides. Make them inside the branch. Do not keep them
  in a table outside the branch for the next time it shows.
- The Composition measures each form with its scale. To pop part of a region,
  put the `UIScale` on an inner frame inside a holder of fixed size. Then a
  pop does not move the region to another place or form.
- Give the primary actions that a player presses with a thumb, such as Jump
  or Drift, `target = "thumb"`. Size their art from
  `UI.environment().thumbTarget`, not from the screen width.
  Open `Button.appearance` for `target`, `environment.environment` for
  `thumbTarget` or `Themes.metrics` for theme options.
  Show gameplay commands only in the states where they apply. Core safe
  insets do not reserve Roblox's movement or Jump controls. Keep secondary
  navigation above that area and reserve the lower corners for active input.
  Read `Tasks.safe-layout` before placing readouts or custom controls there.
- Use native InputAction and InputContext for game commands. Controls own
  their input and selection. Do not bind Escape or the gamepad Start button.
- Get every string that a player sees from a localization key, fixed words
  too. Keep the English source in one keyed table that builds the
  `LocalizationTable`. Read each string with `translator:FormatByKey(key, args)`
  in a readable and give the result to the control. Pass every argument to
  `FormatByKey` as a string, for example `tostring(count)`; a number argument
  raises an error. Do not write a
  player-facing string literal in UI code, also not with `AutoLocalize` on: a
  literal has no key, no check finds it when the table does not have it, and
  it does not change when the table changes. Add a check that each key in the
  code is in the table. Set `AutoLocalize = false` on a label that shows a
  translated string or text that players write. Give the app the `translator`
  option for the strings that Facet makes.

## Check

Use Script Analysis, Output, Play, device emulation, and
the input and capture tools available to the assistant. Check the first mount,
then open and operate each distinct shared pattern before copying it across
tasks. A successful HUD mount does not test a preview or an unopened panel.
For each command, check the promised game effect as well as its label: changing
a setting or selection must change the corresponding sound, view, or game object.
Complete, cancel, and reopen the affected tasks at wide and compact sizes
with the supported inputs. Fix errors in the persistent Edit scripts and start
a fresh Play session to verify them. Confirm that the changes remain after
Play stops. Report checks the available tools cannot perform; do not claim the
filesystem verifier ran. Save the place through the project's normal workflow.

For projects with saved source files and shell tools, use the
[filesystem workflow](references/FILESYSTEM_WORKFLOW.md).

Review the rendered result against the design guide: hierarchy, overlap,
legibility, compact forms, reachable actions and truthful feedback. Passing
technical checks alone does not establish design quality.
For temporary surfaces, list the built-in dismissal routes before adding Close,
Cancel or Done. Remove duplicate visible exits that add no task value, while
preserving a discoverable route for each input. Check the grabber's actual
behavior at every detent; a drag indicator alone does not prove dismissal works.
Choose Sheet placement separately from task size. A centered task panel uses
Close without a grabber; a docked sheet uses a grabber without a duplicate
Close. Leave `closeButton` absent for adaptive placement. Check that hover,
press and focus do not resize a hugging surface or move nearby targets.

## Keep context small

Read only the affected function or line range after an edit. Keep UI components
in separate modules so a local change needs a local read. Do not print a whole
source file to prepare a Studio update. In Studio, patch only the changed
section through `execute_luau`. Check the match count before changing Source.
Return a short status, not the updated source.

For Studio checks, batch related `execute_luau` queries and return only the
needed text, state, selected control, viewport or bounds. Limit descendant
queries to the affected panel. Use input events to test interactions. Capture
each distinct layout and device after a coherent change, and capture again
when a visual problem remains. Use state queries between those visual checks;
do not capture after every input. Inspect images through the image tool, never
print image bytes, base64, complete capture payloads or full interface dumps.

For a missing behavior, search the docs. Use native Roblox mechanisms first,
then Compose, then a Facet control, then game code. For Compose operations
outside this path, read the [Compose skill](../compose/SKILL.md).
In the Facet repository, read [AGENTS.md](../../AGENTS.md) before changes.
