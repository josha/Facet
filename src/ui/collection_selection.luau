--!strict
local policy = require("./collection_policy")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
return function<V, K>(
	ctx: Types.Context,
	spec: CollectionTypes.SelectionOptions<V, K>,
	source: Types.Input<{ V }>,
	keyOf: (V, number) -> K,
	controls: ComposeTypes.OrderedCollectionControls<K>,
	selection: ComposeTypes.Value<CollectionTypes.Selection<K>>,
	defaultMode: "none" | "single" | "multiple"
): ((K, V, InputObject?) -> (), (K?, K) -> ())
	local Compose, read, E = ctx.Compose, ctx.read, ctx.types.Enum
	local readRows = ctx.read<<{ V }>>
	local anchor: K?
	local mode = spec.selectionMode or defaultMode
	assert(
		mode == "none" or mode == "single" or mode == "multiple",
		`Facet collection selectionMode must be none, single or multiple (got {tostring(mode)})`
	)
	local function publish(value: CollectionTypes.Selection<K>): ()
		if spec.onSelectionChange then
			spec.onSelectionChange(value)
		elseif type(selection.set) == "function" then
			selection:set(value)
		end
	end
	local function validKeys(use: ComposeTypes.Use): { [K]: boolean }
		local valid: { [K]: boolean } = {}
		for index, item in readRows(spec.selectionFrom or source, use) do
			valid[keyOf(item, index)] = true
		end
		return valid
	end
	local membership = if mode ~= "none"
			or spec.selection ~= nil
			or spec.onSelectionChange ~= nil
		then Compose.formula(validKeys)
		else nil
	Compose.watch(function(use: ComposeTypes.Use)
		local existing = use(selection)
		if next(existing) == nil then
			return
		end
		local valid = if membership then use(membership) else validKeys(use)
		for key, value in existing do
			if not value or not valid[key] then
				local pruned: CollectionTypes.Selection<K> = {}
				for selectedKey, selected in existing do
					if selected and valid[selectedKey] then
						pruned[selectedKey] = true
					end
				end
				publish(pruned)
				return
			end
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
		local rows = readRows(source)
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
	local function choose(key: K, item: V, _input: InputObject?): ()
		if mode == "none" or not eligible(item) then
			return
		end
		if mode ~= "multiple" then
			local selected = if read(spec.editing) == true and selection:peek()[key] then {} else { [key] = true }
			publish(selected)
			return
		end
		if anchor ~= nil and held(shift) and range(anchor, key) then
			return
		end
		local selected: CollectionTypes.Selection<K> = {}
		if held(toggle) or read(spec.editing) == true then
			local current = selection:peek()
			for other, on in current do
				if on and not rawequal(other, key) then
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
		if mode ~= "multiple" or from == nil or rawequal(from, to) or not held(shift) then
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
