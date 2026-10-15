# Instructions for this project

Build with Facet in `Packages/Facet`, mapped by Rojo to
`ReplicatedStorage.Packages.Facet`. Do not add another UI library.

Read `TEAM_NOTES.md`, the ticket and `.agents/skills/use-facet/SKILL.md`.
Start with `lute run tools/facet docs`, then batch application contract reads.
Use `docs <Control>` for a missing option and `project [directory]` for file
discovery. Follow the skill for state, ownership, layout and Studio checks.
Use one `Facet.app` and one mounted root, with Compose branches and portals.

Run `lute run tools/facet verify --tap TEXT...` after a coherent edit. Inspect
the reported screenshots and fix high and medium findings. If its Studio
session is unavailable, report the limit once and use `verify --static` plus
the scoped Studio MCP. If scoped MCP is also unavailable, follow the
setup-failure rule in `TEAM_NOTES.md`.
