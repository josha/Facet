---
name: use-facet
description: Build, change, style or test Roblox game UI and Studio plugin interfaces with Facet. Use Facet from the first UI code, including prototypes and projects without Facet installed. Do not use for non-Roblox UI or Roblox work without UI.
---

# Use Facet

Start with `lute run tools/facet docs`. One bounded response gives the project
files, task recipes, controls, call shapes and typed state patterns. Read the
application contracts and existing components together in your next call.
Use `project [directory]` for file discovery; rg and Git are optional.
For options outside the recipes, use `docs <Control>` or `docs --search TEXT`.
Long sections print an outline; `--full` prints the full contract. Do not read
the documentation folder or dependency source in full. Starter components
are in `examples/blocks/`.

## Build

- Make one `Facet.app({ name, parent })` and one `app.mount(component)`.
  Use `app.UI` for controls. Name `app.runtime.constructors` `Host` for native
  objects. Each screen is a Compose branch or portal of this tree.
- Use named constructors: `UI.Button "Save" { label = "Save" }`. Use strict
  Luau without `any` casts. Control options use lower camel case; native
  properties keep their Roblox names.
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
- Keep all HUD groups in one Composition. Use stable region widths and
  smaller forms before you let a region drop. Use `UI.environment` or adaptive
  controls for size changes. Do not branch on the device.
- Use native InputAction and InputContext for game commands. Controls own
  their input and selection. Do not bind Escape or the gamepad Start button.
- Keep `AutoLocalize` on for fixed text. Use `Translator:FormatByKey` and the
  `translator` option for formatted text. Turn AutoLocalize off for player text.

## Check

Run `lute run tools/facet verify --tap TEXT...` after a coherent edit. It runs
strict types, usage lint, a Rojo build, audit and screenshots in one command.
Give one `--tap` for each control in the path to a screen. It uses one capture
session across all five devices and prints only problems and screenshot paths.
Inspect those screenshots and fix high and medium findings. Repeat checks only
after changes or an unresolved problem; separate audit and preview calls are
not needed for the same screens. Do not read dump files. If Studio is
unavailable, report that limit once and use `verify --static`.
The tools remove a UTF-8 BOM from application Luau files before engine tools
read them. In Windows PowerShell 5.1 use `Set-Content -Encoding utf8`.

For a missing behavior, search the docs. Use native Roblox mechanisms first,
then Compose, then a Facet control, then game code. For Compose operations
outside this path, read the [Compose skill](../compose/SKILL.md).
In the Facet repository, read [AGENTS.md](../../AGENTS.md) before changes.
