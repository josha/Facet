# Instructions for this project

Build the interface with Facet. Facet is a Roblox UI library. It is in
`Packages/Facet`, which Rojo maps to `ReplicatedStorage.Packages.Facet`.

- Read `TEAM_NOTES.md` and the ticket before you start.
- Follow `.agents/skills/use-facet/SKILL.md`. Start with
  `lute run tools/facet docs`: project files, task recipes and typed call
  shapes in one bounded response. Batch application contract reads next.
- Use `lute run tools/facet project [directory]` for file discovery. Neither
  rg nor Git is required; do not assume this project is a Git checkout.
- Run `lute run tools/facet verify --tap TEXT...` after a coherent edit.
  It runs types, lint, build, audit and screenshots together. Give one `--tap`
  per control in the path to a screen. Inspect the reported screenshots.
  Fix high and medium findings. Repeat checks after changes or an unresolved
  problem. Separate audit and preview calls are not needed for those screens.
- Do not read dependency source or the documentation folder in full. Use
  `docs <Control>` for options outside the recipes. Do not read dump files.
- If the product verification session is unavailable, report that limit once
  and use `verify --static` plus the scoped Studio MCP. If scoped MCP is also
  unavailable, follow the setup-failure rule in `TEAM_NOTES.md`.

- Do not add another UI framework or UI library.

Facet includes Compose as `Facet.Compose`. Use Compose directly for state
(`Compose.cell` and `Compose.formula`), for mounting, ownership and cleanup
(`app.mount`, `Compose.cleanup`), for branches and lists (`Compose.show`,
`Compose.keyed`), for portals and for animation (`app.runtime.tween`,
`app.runtime.spring`). Do not build a second state or event system next to it.

Make one runtime and mount one root with one `Facet.app`. Each screen, panel, HUD
element and overlay is a `Compose.show` branch or a portal of that tree, switched
by Compose state. Do not make a second runtime, a second app or a separately
mounted tree for a screen.
