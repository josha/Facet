--!strict

export type Context = {
	Facet: any,
	Compose: any,
	runtime: any,
	Host: any,
	UI: any,
	state: string,
}
export type Preview = { name: string, render: (Context) -> GuiObject }
export type Definition = { name: string, previews: { Preview } }

local catalog = {}

function catalog.validate(value: any): Definition
	assert(type(value) == "table", "A preview module must return a table")
	assert(type(value.name) == "string" and value.name ~= "", "A preview needs a name")
	assert(type(value.previews) == "table" and #value.previews > 0, "A preview needs at least one sample state")
	local names = {}
	local previews = {}
	for index, item in ipairs(value.previews) do
		assert(type(item) == "table", `Sample state {index} must be a table`)
		assert(type(item.name) == "string" and item.name ~= "", `Sample state {index} needs a name`)
		assert(not names[item.name], `Duplicate sample state: {item.name}`)
		assert(type(item.render) == "function", `Sample state {item.name} needs a render function`)
		names[item.name] = true
		table.insert(previews, { name = item.name, render = item.render })
	end
	for key in value.previews do
		assert(
			type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #previews,
			"Sample states must be a dense array"
		)
	end
	return { name = value.name, previews = previews }
end

function catalog.isPreview(node: Instance): boolean
	return node:IsA("ModuleScript")
		and (node:GetAttribute("FacetDesign") == true or string.sub(node.Name, -8) == ".preview")
end

function catalog.discover(roots: { Instance }): { ModuleScript }
	local found, seen = {}, {}
	for _, root in roots do
		local nodes = root:GetDescendants()
		table.insert(nodes, root)
		for _, node in nodes do
			if catalog.isPreview(node) and not seen[node] then
				seen[node] = true
				table.insert(found, node :: ModuleScript)
			end
		end
	end
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

function catalog.scope(module: ModuleScript): Instance
	local node: Instance = module
	while node.Parent and node.Parent ~= game do
		if node:GetAttribute("FacetDesignRoot") == true or node.Parent:IsA("ServiceProvider") then
			break
		end
		local parent = node.Parent
		if parent.Parent == game then
			break
		end
		node = parent
	end
	return node
end

return catalog
