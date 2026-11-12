# Build with Facet

The use-facet skill follows these instructions in full. Follow it. Do not read
its `SKILL.md` again from Studio: a second copy stays in context for the rest
of the work.

Facet is installed at `ReplicatedStorage.Packages.Facet`, including its Compose
runtime. The skill's reference pages, its examples and the public control
contracts are in `ServerStorage.FacetDocs`. Its folders follow repository
paths, so `references/runtime.md` in the skill is
`FacetDocs.skills["use-facet"].references["runtime.md"].Value`. Read them
through Studio MCP in Edit mode.

- Your first call reads only `references/runtime.md`.
- After that, search before you read: in Edit,
  `return loadstring(game.ServerStorage.FacetDocs["search.luau"].Value)()({ "hud standings", "Sheet detents" })`
  returns the matching sections of guides, examples and reference pages.
  Batch related queries in one call.
- Read a complete contract with `search.read(path)` before the first use of a
  control or of an option on that control; a search result is not always the
  complete contract. Read the contracts of the screen in hand; those of a
  later screen wait until you build it. Read a whole guide or example only
  when the skill names it for the step in hand.
- Do not dump the control index, unrelated examples or the Compose skill.
  `runtime.md` has the Compose calls that a screen needs.

Studio MCP is the only way to change the place and to look at it, and there
is no second agent. Look at your tool list for an image generator. When it
has one, use it for the concept of the first screen and for nothing else.
When it has none, a skill that names one cannot run: block the first screen
in, as step 1 of the skill describes, and make art from native shapes. Either
way the concept is the first picture of the work.
Use this installed library; do not add another UI library.
