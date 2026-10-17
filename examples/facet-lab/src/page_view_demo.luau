--!strict
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	cell: typeof(require("@repo/tools/typecheck/aliases").CellFactory),
}
type PageViewSpec = typeof(require("@repo/tools/typecheck/aliases").PageViewSpec)
type Tab = typeof(require("@repo/tools/typecheck/aliases").Tab)
return function(c: Context): PageViewSpec
	local pages: { Tab } = {}
	for _, name in { "Coast", "Canyon", "City" } do
		table.insert(pages, {
			id = name,
			label = name,
			content = function(): Instance
				return c.UI.Text({ text = `{name} course` })
			end,
		})
	end
	local spec: PageViewSpec = { selection = c.cell("page", "Coast"), pages = pages, Size = UDim2.fromScale(1, 1) }
	return spec
end
