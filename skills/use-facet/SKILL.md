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

## Find implementation details

After the design guide, use `lute run tools/facet docs` for `Map`. Open every task recipe that
matches a part of the screen. For a HUD with a shop, open `Tasks.hud` and
`Tasks.shop`. For a panel with child pages, also open `Tasks.sheet`.
Open a control card or option node only for a missing detail: `docs <path>`.
Use `docs <Control>.props` for typed options and defaults. Do not read package
source to find option types.
Use `docs --search TEXT` to find paths and one-line summaries.
Never reread a node already in context. Each call returns one bounded node.
Use `project [directory]` for file discovery. Read one matching starter in
`examples/blocks/` only if the recipe does not fit.

## Build

- Make one `Facet.app({ name, parent })` and one `app.mount(component)`.
  Use `app.UI` for controls. Name `app.runtime.constructors` `Host` for native
  objects. Each screen is a Compose branch or portal of this tree.
- Use named constructors: `UI.Button "Save" { label = "Save" }`. Use strict
  Luau without `any` casts. Control options use lower camel case; native
  properties keep their Roblox names.
- Build each element from a Facet control when one shows that kind of
  information. A meter, gauge, charge or row of pips is a `ProgressView`
  (`segments` for pips, `trail` for a loss). Standings and results are a
  `Table`. A clock is a `Timer`. A short status mark is a `Badge` or a
  `StatusIndicator`. A brief acknowledgement is a `Toast`. Text is `Text` or
  `Label` with a `textRole`. Do not draw these with native Frames, list
  layouts and fixed sizes: a copy does not get the theme, scaled metrics,
  reduced motion, accessible names or compact forms. Use `Host` objects only
  for content that no control shows, such as a minimap, a 3D view or art.
- When a control does not have an option that the game needs, such as a
  color for each segment, add the option to Facet or a rule to the theme and
  report it. Do not replace the control with native objects. Before you
  extend a hand-built element, find its control in the control index and
  replace the element.
- Use `Facet.Compose`: `cell` for local state, `formula` for derived values,
  `show` for branches, `keyed` for children and `cleanup` to release resources.
  Read cells with `use(cell)` in property functions and `cell:peek()` in
  callbacks. Write with `cell:set(value)` or `cell:update(fn)`.
  Use `function(use: Facet.Use)` when a property reads different cell types.
- Use VirtualList, VirtualGrid or Table for interactive collections. Keep
  durable row state in the model. The server owns game state and validates
  requests. Show the result that the server returns.
- The theme owns paint, type, spacing and motion. Use `textRole`,
  `appearance`, `gap` and `padding` tokens. Use `wrap = true` for long text in
  a stack with `width = "fill"`. Do not set `TextScaled`.
- Keep core-safe HUD groups in one Composition. Use stable region widths and
  smaller forms before you let a region drop. Use `UI.environment` or adaptive
  controls for size changes. Do not branch on the device. For a length the
  game owns, use `UI.environment().scaled(64)`. Add a type role,
  `scaled(64, "body")`, when the length sits beside text.
- Use `Tasks.hud` for HUD actions: a top-right horizontal row of circles in
  TopbarSafeInsets. Keep each readable label below the strip and inside its
  Button's descendants. Open `HUD-actions` for native sizing and selection.
- Give each region forms from the richest to the narrowest. The narrowest
  form must fit a portrait phone, about 320 pixels wide. For example, a row of
  buttons, then the main button over the others, then one column. Let the
  Composition choose the form. Do not choose a layout in a region with
  `isCompact`, `isLandscape` or a fixed `AdaptiveStack` axis. A plain HStack
  never wraps. The Composition warns when a region does not fit at its last
  form. Fix each warning.
- Put a command that the Roblox top bar can hold, such as a settings gear, in
  a `topbar` region. Use `leading = true` to put it beside the Roblox buttons.
  Open `Composition.regions` for options and `Composition.adaptation` for strip
  layout. Open `Composition.layout.step-down` for fallback and fit warnings.
  Use one `docs <path>` call for each node that you need.
- Let a text box hug its text, or use `textSize = { fit = ... }` in a box of
  fixed size. A label can be twice as long in another language.
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
- Use native InputAction and InputContext for game commands. Controls own
  their input and selection. Do not bind Escape or the gamepad Start button.
- Get every string that a player sees from a localization key, fixed words
  too. Keep the English source in one keyed table that builds the
  `LocalizationTable`. Read each string with `translator:FormatByKey(key, args)`
  in a readable and give the result to the control. Do not write a
  player-facing string literal in UI code, also not with `AutoLocalize` on: a
  literal has no key, no check finds it when the table does not have it, and
  it does not change when the table changes. Add a check that each key in the
  code is in the table. Set `AutoLocalize = false` on a label that shows a
  translated string or text that players write. Give the app the `translator`
  option for the strings that Facet makes.

## Check

Run `lute run tools/facet verify --tap TEXT...` after a coherent edit. It runs
strict types, usage lint, a Rojo build, audit and screenshots in one command.
Give one `--tap` for each control in the path to a screen. It uses one capture
session across all five devices and prints only problems and screenshot paths.
During repairs, add `--device ID` to check the affected device. Run one complete
final sweep without `--device`. Use the printed `verify --report` queries to
read findings. Add `--step ID` for one capture. Do not read the full report.
Inspect those screenshots and fix high and medium findings. Repeat checks only
after changes or an unresolved problem; separate audit and preview calls are
not needed for the same screens. Do not read dump files. If Studio is
unavailable, report that limit once and use `verify --static`.
Review the rendered result against the design guide: hierarchy, overlap,
legibility, compact forms, reachable actions and truthful feedback. Passing
technical checks alone does not establish design quality.
The tools remove a UTF-8 BOM from application Luau files before engine tools
read them. In Windows PowerShell 5.1 use `Set-Content -Encoding utf8`.

## Keep context small

Read only the affected function or line range after an edit. Keep UI components
in separate modules so a local change needs a local read. Do not print a whole
source file to prepare a Studio update. Use the project's sync path when one is
available. Otherwise transfer each module once, then patch only the changed
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
