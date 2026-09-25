--!strict
local policy = require("./collection_policy")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
return function<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.SelectionOptions<V, K>,
	source: Types.Value<{ V }>,
	keyOf: (V, number) -> K,
	controls: ComposeTypes.OrderedCollectionControls<K>,
	selection: ComposeTypes.Cell<CollectionTypes.Selection<K>>,
	defaultMode: "none" | "single" | "multi"
): ((K, V, InputObject?) -> (), (K?, K) -> ())
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
	Compose.watch(function(use: ComposeTypes.Use)
		local existing = use(selection)
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
	local base: CollectionTypes.Selection<K> = {}
	local shift = { E.KeyCode.LeftShift, E.KeyCode.RightShift }
	local toggle = {
		E.KeyCode.LeftControl,
		E.KeyCode.RightControl,
		E.KeyCode.LeftMeta,
		E.KeyCode.RightMeta,
		E.KeyCode.LeftSuper,
		E.KeyCode.RightSuper,
	}
	local function held(keys: { Enum.KeyCode }): boolean
		local input = ctx.config.userInputService
		if input == nil then
			return false
		end
		for _, keyCode in keys do
			if input:IsKeyDown(keyCode) then
				return true
			end
		end
		return false
	end
	local function eligible(item: V): boolean
		return policy.allows(spec.selectable, item) and not policy.disabled(spec.disabled, item)
	end
	local function range(from: K, to: K): boolean
		local first, last = assert(controls.indexOfKey)(from), assert(controls.indexOfKey)(to)
		if first == nil or last == nil then
			return false
		end
		local selected: CollectionTypes.Selection<K> = {}
		local current = selection:peek()
		for key in base do
			if current[key] then
				selected[key] = true
			end
		end
		local rows = read(source)
		for index = math.min(first, last), math.max(first, last) do
			local candidate = rows[index]
			if candidate ~= nil and eligible(candidate) then
				selected[keyOf(candidate, index)] = true
			end
		end
		publish(selected)
		return true
	end
	local function anchorAt(key: K, selected: CollectionTypes.Selection<K>): ()
		anchor = key
		base = table.clone(selected)
	end
	local function choose(key: K, item: V, input: InputObject?): ()
		if mode == "none" or not eligible(item) then
			return
		end
		if mode ~= "multi" then
			local selected = { [key] = true }
			anchorAt(key, selected)
			publish(selected)
			return
		end
		if anchor ~= nil and held(shift) and range(anchor, key) then
			return
		end
		local selected: CollectionTypes.Selection<K> = {}
		if held(toggle) or input == nil or input.UserInputType ~= E.UserInputType.MouseButton1 then
			local current = selection:peek()
			for other, on in current do
				if on and other ~= key then
					selected[other] = true
				end
			end
			if not current[key] then
				selected[key] = true
			end
		else
			selected[key] = true
		end
		anchorAt(key, selected)
		publish(selected)
	end
	local function extend(from: K?, to: K): ()
		if mode ~= "multi" or from == nil or from == to or not held(shift) then
			return
		end
		if anchor == nil or assert(controls.indexOfKey)(anchor :: K) == nil then
			local selected = table.clone(selection:peek())
			selected[from] = true
			anchorAt(from, selected)
		end
		range(anchor :: K, to)
	end
	return choose, extend
end
