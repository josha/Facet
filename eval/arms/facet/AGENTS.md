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
  complete contract. Read a whole guide or example only when the skill names
  it for the step in hand.
- Do not dump the control index, unrelated examples or the Compose skill.
  `runtime.md` has the Compose calls that a screen needs.

Studio MCP is the only tool. There is no image model, no drawing tool and no
second agent. Where the skill offers a route for that case, such as blocking
in the first screen in place of a sketch and making art from native shapes,
take it and report what was unavailable.
Use this installed library; do not add another UI library.
