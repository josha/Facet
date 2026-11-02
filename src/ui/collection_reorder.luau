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
local Motion = require("./motion")
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
	UI: ControlTypes.Controls,
	spec: CollectionTypes.ReorderShape<V, K>,
	source: ComposeTypes.Source<{ V }>,
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
	type Order = {
		remaining: { K },
		keys: { K },
		slot: number,
		indexes: { [K]: number },
		offsets: { [K]: number }?,
	}
	local lastOrder: Order? = nil
	local function orderOf(move: { remaining: { K }, keys: { K }, slot: number, rows: { unknown } }): Order
		local cached = lastOrder
		if cached and cached.remaining == move.remaining and cached.keys == move.keys and cached.slot == move.slot then
			return cached
		end
		local ordered = table.clone(move.remaining)
		for index, carried in move.keys do
			table.insert(ordered, move.slot + index, carried)
		end
		local indexes: { [K]: number } = {}
		for index, candidate in ordered do
			indexes[candidate] = index
		end
		local offsets: { [K]: number }? = nil
		if not grid and reservedSlots == nil then
			local measured: { [K]: number } = {}
			local first = assert(controls.placementOf)(1)
			local offset = first.offset
			local gap = if #move.rows > 1 then assert(controls.placementOf)(2).offset - offset - first.size else 0
			for _, candidate in ordered do
				measured[candidate] = offset
				local index = assert(controls.indexOfKey)(candidate)
				if index then
					offset += assert(controls.placementOf)(index).size + gap
				end
			end
			offsets = measured
		end
		local made: Order =
			{ remaining = move.remaining, keys = move.keys, slot = move.slot, indexes = indexes, offsets = offsets }
		lastOrder = made
		return made
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
			local order = orderOf(move)
			local offset = if order.offsets then order.offsets[key] else nil
			if offset ~= nil then
				if offset == at.offset then
					return at
				end
				local next = table.clone(at)
				next.offset = offset
				return next
			end
			local index = order.indexes[key]
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
			local target, empty = shared.slotGap(session.payload, proposal, use)
			if index and target and empty then
				if index >= target and index < empty then
					return assert(controls.placementOf)(index + 1)
				elseif index < target and index > empty then
					return assert(controls.placementOf)(index - 1)
				end
				return at
			end
			local before = proposal.beforeKey
			local start = if before ~= nil then assert(controls.indexOfKey)(before :: K) else nil
			if index and start and index >= start then
				return assert(controls.placementOf)(index + (if keys then math.max(1, #keys) else 1))
			end
		end
		return at
	end
	type Positioned = {
		key: K,
		at: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		aim: ComposeTypes.Value<number>,
		cross: number,
		main: number,
	}
	type PositionTarget = { position: Vector2, relaid: boolean }
	local positioned: { [Positioned]: boolean } = {}
	local function peek<T>(value: ComposeTypes.ReadOnlyValue<T>): T
		return value:peek()
	end
	local wasShifting = false
	ctx.Compose.watch(function(use: ComposeTypes.Use)
		local seen: { [unknown]: boolean } = {}
		local function once<T>(value: ComposeTypes.ReadOnlyValue<T>): T
			if seen[value] then
				return value:peek()
			end
			seen[value] = true
			return use(value)
		end
		once(moving)
		once(shared.incoming)
		local session = once(shared.drag.state)
		local shifting = session ~= nil and session.target == bodyOf() and session.accepted == true
		local settled = not shifting and not wasShifting
		wasShifting = shifting
		if settled then
			return
		end
		for entry in positioned do
			local proposed = placement(entry.key, entry.at:peek(), once)
			if proposed.crossOffset ~= entry.cross or proposed.offset ~= entry.main then
				entry.aim:set(entry.aim:peek() + 1)
			end
		end
	end)
	return {
		placement = placement,
		position = function(
			key: K,
			at: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
			reducedMotion: Types.ValueBoolean?
		): ComposeTypes.ReadOnlyValue<Vector2>
			local entry: Positioned =
				{ key = key, at = at, aim = ctx.Compose.cell(0), cross = math.huge, main = math.huge }
			positioned[entry] = true
			ctx.Compose.cleanup(function()
				positioned[entry] = nil
			end)
			if shared.instantLayout then
				return ctx.Compose.formula(function(use: ComposeTypes.Use): Vector2
					use(entry.aim)
					local proposed = placement(key, use(at), peek)
					entry.cross, entry.main = proposed.crossOffset, proposed.offset
					return ctx.types.Vector2.new(proposed.crossOffset, proposed.offset)
				end)
			end
			local last: ComposeTypes.Placement? = nil
			local lastTarget: PositionTarget? = nil
			local lastShift = ctx.types.Vector2.zero
			local target = ctx.Compose.formula(function(use: ComposeTypes.Use): PositionTarget
				use(entry.aim)
				local base = use(at)
				local proposed = placement(key, base, peek)
				entry.cross, entry.main = proposed.crossOffset, proposed.offset
				local wanted = ctx.types.Vector2.new(proposed.crossOffset, proposed.offset)
				local shift = wanted - ctx.types.Vector2.new(base.crossOffset, base.offset)
				local previous = lastTarget
				local relaid = if previous then previous.relaid else true
				if last and previous and (base ~= last or wanted ~= previous.position) then
					relaid = base.index == last.index and (shift - lastShift).Magnitude <= 0.5
				end
				last, lastShift = base, shift
				if previous and wanted == previous.position and relaid == previous.relaid then
					return previous
				end
				local made: PositionTarget = { position = wanted, relaid = relaid }
				lastTarget = made
				return made
			end)
			local spring = ctx.motionSpring("snappy")
			local function reduced(use: ComposeTypes.Use): boolean
				return use(target).relaid or shared.motionReduced(use) or read(reducedMotion, use) == true
			end
			return Motion.forValue(ctx, ctx.types.Vector2.zero).spring(function(use: ComposeTypes.Use): Vector2
				return use(target).position
			end, {
				period = spring.period,
				damping = spring.damping,
				reducedMotion = reduced,
			})
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
