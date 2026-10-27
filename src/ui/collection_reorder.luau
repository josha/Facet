--!strict
local ControlTypes = require("./control_types")
local createState = require("./collection_reorder_state")
local createPointer = require("./collection_reorder_pointer")
local createRow = require("./collection_reorder_row")
local registerDrop = require("./collection_reorder_drop")
local createFeedback = require("./collection_reorder_feedback")
local bindKeys = require("./collection_reorder_keys")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
export type Editor<V, K> = {
	placement: (K, ComposeTypes.Placement, ComposeTypes.Use) -> ComposeTypes.Placement,
	position: (
		K,
		ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		Types.ValueBoolean?
	) -> ComposeTypes.ReadOnlyValue<Vector2>,
	wrap: (GuiObject, ComposeTypes.ReadOnlyValue<V>, K, boolean?) -> Frame,
	overlay: (boolean?) -> Frame,
	leading: ComposeTypes.ReadOnlyValue<number>,
	trailing: ComposeTypes.ReadOnlyValue<number>,
	header: ComposeTypes.ReadOnlyValue<number>,
	press: (K, InputObject) -> (),
	mouseDown: (Vector2) -> (),
	finish: (InputObject) -> (),
	busy: () -> boolean,
	pickUp: (K, InputObject?) -> boolean,
	deleteSelected: (...unknown) -> (),
	canDeleteSelected: (ComposeTypes.Use?) -> boolean,
}
return function<V, K>(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	spec: CollectionTypes.ReorderShape<V, K>,
	source: Types.Input<{ V }>,
	keyOf: (V, number) -> K,
	controls: ComposeTypes.OrderedCollectionControls<K>,
	bodyOf: () -> ScrollingFrame,
	selection: ComposeTypes.Value<CollectionTypes.Selection<K>>,
	sort: ComposeTypes.Value<CollectionTypes.Sort?>,
	editing: Types.ValueBoolean?,
	grid: boolean?,
	location: (({ K }, number) -> (boolean, number, K?))?,
	instantLayout: boolean?,
	reservedSlots: Types.Input<{ K }>?
): Editor<V, K>
	local read = ctx.read
	local E = ctx.types.Enum
	local shared = createState(
		ctx,
		UI,
		spec,
		source,
		keyOf,
		controls,
		bodyOf,
		selection,
		sort,
		editing,
		grid,
		location,
		instantLayout,
		reservedSlots
	)
	local moving = shared.moving
	local pointer = createPointer(shared)
	local wrap = createRow(shared, pointer)
	local function overlay(insideBody: boolean?): Frame
		local body = bodyOf()
		registerDrop(shared, body)
		local canvasAt, bodyAt = ctx.observe.CanvasPosition(body), ctx.observe.Position(body)
		pointer.listen(body)
		local root = createFeedback(shared, body, insideBody, canvasAt, bodyAt)
		bindKeys(shared, root, body)
		return root
	end
	local function placement(key: K, at: ComposeTypes.Placement, use: ComposeTypes.Use): ComposeTypes.Placement
		local move, proposal = use(moving), use(shared.incoming)
		local session = use(shared.drag.state)
		if session == nil or session.target ~= bodyOf() or session.accepted ~= true then
			return at
		end
		if move and move.keyboard and spec.drag == nil and spec.drop == nil then
			return at
		end
		if move then
			local ordered = table.clone(move.remaining)
			for index, carried in move.keys do
				table.insert(ordered, move.slot + index, carried)
			end
			if not grid and reservedSlots == nil then
				local first = assert(controls.placementOf)(1)
				local offset = first.offset
				local gap = if #move.rows > 1 then assert(controls.placementOf)(2).offset - offset - first.size else 0
				for _, candidate in ordered do
					if candidate == key then
						local next = table.clone(at)
						next.offset = offset
						return next
					end
					local index = assert(controls.indexOfKey)(candidate)
					if index then
						offset += assert(controls.placementOf)(index).size + gap
					end
				end
			end
			local index = table.find(ordered, key)
			if index and reservedSlots then
				local live: { [K]: boolean } = {}
				for row, item in read(source, use) do
					live[keyOf(item, row)] = true
				end
				local occupied = 0
				for slot, candidate in read(reservedSlots, use) do
					if live[candidate] then
						occupied += 1
						if occupied == index then
							return assert(controls.placementOf)(slot)
						end
					end
				end
			end
			return if index then assert(controls.placementOf)(index) else at
		end
		if proposal then
			local data = if type(session.payload) == "table" then session.payload :: { keys: { K }? } else nil
			local keys = if data then data.keys else nil
			if shared.recall(session.payload, use) ~= nil then
				return at
			end
			local index = assert(controls.indexOfKey)(key)
			local before = proposal.beforeKey
			local start = if before ~= nil then assert(controls.indexOfKey)(before :: K) else nil
			if index and start and index >= start then
				return assert(controls.placementOf)(index + (if keys then math.max(1, #keys) else 1))
			end
		end
		return at
	end
	return {
		placement = placement,
		position = function(
			key: K,
			at: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
			reducedMotion: Types.ValueBoolean?
		): ComposeTypes.ReadOnlyValue<Vector2>
			local target = ctx.Compose.formula(function(use: ComposeTypes.Use): Vector2
				local proposed = placement(key, use(at), use)
				return ctx.types.Vector2.new(proposed.crossOffset, proposed.offset)
			end)
			local spring = ctx.motionSpring("snappy")
			local function reduced(use: ComposeTypes.Use): boolean
				return shared.instantLayout == true or shared.motionReduced(use) or read(reducedMotion, use) == true
			end
			local position = ctx.runtime.spring(function(use: ComposeTypes.Use): Vector2
				return use(target)
			end, {
				period = spring.period,
				damping = spring.damping,
				reducedMotion = reduced,
			})
			return ctx.Compose.formula(function(use: ComposeTypes.Use): Vector2
				return if reduced(use) then use(target) else use(position)
			end)
		end,
		pickUp = function(key: K, input: InputObject?): boolean
			if not spec.drag or input == nil or input.UserInputType == E.UserInputType.MouseButton1 then
				return false
			end
			if moving:peek() == nil then
				shared.begin(key, nil, nil, input.UserInputType == E.UserInputType.Touch)
			end
			return moving:peek() ~= nil
		end,
		wrap = wrap,
		overlay = overlay,
		leading = shared.leading,
		trailing = shared.trailing,
		header = shared.header,
		press = pointer.press,
		mouseDown = pointer.mouseDown,
		finish = pointer.finish,
		busy = function(): boolean
			return moving:peek() ~= nil
		end,
		deleteSelected = function()
			shared.remove(true)
		end,
		canDeleteSelected = shared.canDeleteSelected,
	}
end
