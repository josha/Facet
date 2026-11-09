# Build with Facet

Follow the supplied use-facet skill. Facet is installed at
`ReplicatedStorage.Packages.Facet`, including its Compose runtime.
The same skill and public reference pages are available in
`ServerStorage.FacetDocs`. Its folders follow repository paths. For example,
read `FacetDocs.skills["use-facet"]["SKILL.md"].Value` and
`FacetDocs.docs.reference.nodes["Map.md"].Value` through Studio MCP in Edit mode.
Your first call reads only `SKILL.md` and `references/runtime.md`. After that,
search instead of reading: in Edit,
`return loadstring(game.ServerStorage.FacetDocs["search.luau"].Value)()("hud standings")`
returns matching sections of guides, examples and reference pages. Read the
exact contract or one relevant complete example when needed to implement the
first screen correctly; search results are not always the complete contract.
Retrieve later controls when you need them. Batch related queries and avoid
dumping the whole control index or unrelated examples. Studio MCP is the only
tool; report unavailable art or review tools and use the skill's supported
native route when it fits the brief.
Use this installed library; do not add another UI library.
