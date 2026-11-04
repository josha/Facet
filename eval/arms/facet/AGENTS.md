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
returns only the matching sections of every guide, route, example and reference
page. Before your first module, make at most two more documentation calls, each
a batch of searches. After that, search for a control just before the call that
first writes code using it. Do not read the
`Controls` index, whole examples, or batches of control pages: everything read
stays in context and is resent with every later call. Studio MCP is the only
tool.
Use this installed library; do not add another UI library.
