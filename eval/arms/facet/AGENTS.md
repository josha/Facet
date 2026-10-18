# Instructions for this project

Build with Facet in `Packages/Facet`, mapped by Rojo to
`ReplicatedStorage.Packages.Facet`. Do not add another UI library.

Read `TEAM_NOTES.md`, the ticket and `.agents/skills/use-facet/SKILL.md`.
Start with `lute run tools/facet docs` for the map. Open one task recipe.
Open a card or option node only for a missing detail with `docs <path>`.
Use `docs --search TEXT` to find paths. Never reread a node already in context.
Treat `Packages/Facet` and `tools/` like the engine: use them, but learn them
from the docs. Read their source only to diagnose a suspected Facet bug, when
observed behavior contradicts a doc node. Before you read, state the behavior
and the node it contradicts in one sentence. Then work around the bug.
Use `project [directory]` for file discovery. Follow the skill for state,
ownership, layout and Studio checks.
Use one `Facet.app` and one mounted root, with Compose branches and portals.

Run `lute run tools/facet verify --tap TEXT...` after a coherent edit. Inspect
the reported screenshots and fix high and medium findings. If its Studio
session is unavailable, report the limit once and use `verify --static` plus
the scoped Studio MCP. If scoped MCP is also unavailable, follow the
setup-failure rule in `TEAM_NOTES.md`.
