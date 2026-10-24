--!strict

local Json = require("./json")

local Setup = {}

function Setup.authorModels(suite: unknown): { string }
	local agents = assert(Json.arrayField(suite, "agents"), "suite must declare its author models")
	local names: { string } = {}
	for _, agent in agents do
		assert(Json.stringField(agent, "adapter") == "codex", "Studio-only preparation requires the Codex adapter")
		local name = assert(Json.stringField(agent, "model"), "each author must declare its model")
		assert(name ~= "", "author model must not be empty")
		if table.find(names, name) == nil then
			table.insert(names, name)
		end
	end
	assert(#names > 0, "suite must declare at least one author model")
	table.sort(names)
	return names
end

function Setup.restrictCatalog(catalog: unknown, requested: { string }): Json.Object
	local models = assert(Json.arrayField(catalog, "models"), "Codex model catalog has no models")
	assert(#requested > 0, "select at least one author model")
	local selected = Json.array()
	for _, name in requested do
		local found: Json.Object? = nil
		for _, value in models do
			local model = assert(Json.asObject(value), "invalid Codex model entry")
			if model.slug == name then
				assert(found == nil, "duplicate Codex model entry: " .. name)
				found = model
			end
		end
		local source: Json.Object = assert(found, "Codex model catalog does not contain " .. name)
		local restricted = Json.object()
		for _, key in Json.keys(source) do
			Json.set(restricted, key, source[key])
		end
		Json.set(restricted, "apply_patch_tool_type", Json.null)
		Json.set(restricted, "multi_agent_version", Json.null)
		Json.set(restricted, "experimental_supported_tools", Json.array())
		table.insert(selected, restricted)
	end
	local prepared = Json.object()
	Json.set(prepared, "models", selected)
	return prepared
end

return table.freeze(Setup)
