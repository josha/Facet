# Build with Facet

Follow the supplied use-facet skill. Facet is installed at
`ReplicatedStorage.Packages.Facet`, including its Compose runtime.
The same skill and public reference pages are available in
`ServerStorage.FacetDocs`. Its folders follow repository paths. For example,
read `FacetDocs.skills["use-facet"]["SKILL.md"].Value` and
`FacetDocs.docs.reference.nodes["Map.md"].Value` through Studio MCP in Edit mode.
Start with `SKILL.md`; it names the one batch of documents to read first.
Read `SKILL.md`, runtime essentials and your task's route together in one call.
After that, look up a control or option with
`return require(game.ServerStorage.FacetDocs.search)("Sheet detents")`, which
returns only the matching sections, instead of reading whole reference pages.
Whole pages, examples and every route up front stay in context and are resent
with every later call. Studio MCP is the only tool.
Use this installed library; do not add another UI library.
