--!strict
local policy = require("./collection_policy")
local Compose = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
return function<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.SelectionOptions<V, K>,
	source: Types.Value<{ V }>,
	keyOf: (V, number) -> K,
	controls: Compose.OrderedCollectionControls<K>,
	selection: Compose.Cell<CollectionTypes.Selection<K>>,
	defaultMode: "none" | "single" | "multi"
): (K, V) -> ()
	local Compose, read, E = ctx.Compose, ctx.read, ctx.types.Enum
	local anchor: K?
	local mode = spec.selectionMode or defaultMode
	local function publish(value: CollectionTypes.Selection<K>): ()
		if spec.onSelectionChange then
			spec.onSelectionChange(value)
		elseif type(selection.set) == "function" then
			selection:set(value)
		end
	end
	Compose.watch(function(use: Compose.Use)
		local existing = read(selection, use)
		if next(existing) == nil then
			return
		end
		local valid: { [K]: boolean } = {}
		for index, item in read(source, use) do
			valid[keyOf(item, index)] = true
		end
		local pruned: CollectionTypes.Selection<K> = {}
		local changed = false
		for key, value in existing do
			if value and valid[key] then
				pruned[key] = true
			else
				changed = true
			end
		end
		if changed then
			publish(pruned)
		end
	end)
	return function(key: K, item: V): ()
		if mode == "none" or not policy.allows(spec.selectable, item) or policy.disabled(spec.disabled, item) then
			return
		end
		local selected = if mode == "multi" then table.clone(read(selection)) else {}
		local input = ctx.config.userInputService
		local shifted = input and (input:IsKeyDown(E.KeyCode.LeftShift) or input:IsKeyDown(E.KeyCode.RightShift))
		local from, to = if anchor then assert(controls.indexOfKey)(anchor) else nil, assert(controls.indexOfKey)(key)
		if mode == "multi" and shifted and from and to then
			local rows = read(source)
			for index = math.min(from, to), math.max(from, to) do
				local candidate = rows[index]
				if policy.allows(spec.selectable, candidate) and not policy.disabled(spec.disabled, candidate) then
					selected[keyOf(candidate, index)] = true
				end
			end
		else
			selected[key] = if selected[key] then nil else true
			anchor = key
		end
		publish(selected)
	end
end
