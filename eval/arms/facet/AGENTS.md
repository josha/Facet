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
page. Search each decision as you reach it, such as a screen pattern, a control,
an option or a theme token. Read a whole document only when you adapt it, one at
a time. Do not list the folder tree or read guides, routes, examples or several
reference pages up front: everything read stays in context and is resent with
every later call. Studio MCP is the only tool.
Use this installed library; do not add another UI library.
