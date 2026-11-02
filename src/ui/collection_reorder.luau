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
local Dynamic = require("../vendor/compose/core/dynamic")
export type Editor<V, K> = {
	placement: (K, ComposeTypes.Placement, ComposeTypes.Use) -> ComposeTypes.Placement,
	position: (
		K,
		ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		(Vector2) -> (),
		Types.ValueBoolean?
	) -> (ComposeTypes.Placement) -> (),
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
		first: number,
		last: number,
	}
	local lastOrder: Order? = nil
	local shifting = false
	local function orderOf(move: createState.Move<V, K>): Order
		local slot = move.slot:peek()
		local cached = lastOrder
		if cached and cached.remaining == move.remaining and cached.keys == move.keys and cached.slot == slot then
			return cached
		end
		local ordered = table.clone(move.remaining)
		for index, carried in move.keys do
			table.insert(ordered, slot + index, carried)
		end
		local firstChanged: number, lastChanged: number = slot + 1, slot + #move.keys
		if reservedSlots then
			for index, item in ctx.readSource(source) do
				if move.included[keyOf(item, index)] then
					firstChanged = math.min(firstChanged, index)
					lastChanged = math.max(lastChanged, index)
				end
			end
		else
			for _, key in move.keys do
				local index = assert(controls.indexOfKey)(key)
				if index then
					firstChanged = math.min(firstChanged, index)
					lastChanged = math.max(lastChanged, index)
				end
			end
		end
		if lastChanged > #ordered then
			lastChanged = #ordered
		end
		local indexes: { [K]: number } = {}
		for index = firstChanged, lastChanged do
			indexes[ordered[index]] = index
		end
		local offsets: { [K]: number }? = nil
		if not grid and reservedSlots == nil then
			local measured: { [K]: number } = {}
			local first = assert(controls.placementOf)(firstChanged)
			local offset = first.offset
			local gap = if #ctx.readSource(source) > 1
				then assert(controls.placementOf)(2).offset - assert(controls.placementOf)(1).size - assert(
					controls.placementOf
				)(1).offset
				else 0
			for position = firstChanged, lastChanged do
				local candidate = ordered[position]
				measured[candidate] = offset
				local index = assert(controls.indexOfKey)(candidate)
				if index then
					offset += assert(controls.placementOf)(index).size + gap
				end
			end
			offsets = measured
		end
		local made: Order = {
			remaining = move.remaining,
			keys = move.keys,
			slot = slot,
			indexes = indexes,
			offsets = offsets,
			first = firstChanged,
			last = lastChanged,
		}
		lastOrder = made
		return made
	end
	local incomingRows: { V }? = nil
	local incomingBefore: unknown = nil
	local incomingKey: K? = nil
	local function placement(key: K, at: ComposeTypes.Placement, use: ComposeTypes.Use): ComposeTypes.Placement
		local move, proposal = use(moving), use(shared.incoming)
		local session = use(shared.drag.state)
		if not shifting or session == nil then
			return at
		end
		if move and move.keyboard and spec.drag == nil and spec.drop == nil then
			return at
		end
		if move then
			use(move.slot)
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
			local keys = if type(session.payload) == "table" then Dynamic.raw(session.payload, "keys") else nil
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
			local rows = ctx.readSource(source, use)
			if rows ~= incomingRows or before ~= incomingBefore then
				incomingRows, incomingBefore, incomingKey = rows, before, nil
				if before ~= nil then
					for index, item in rows do
						local candidate = keyOf(item, index)
						if candidate == before then
							incomingKey = candidate
							break
						end
					end
				end
			end
			local start = if incomingKey ~= nil then assert(controls.indexOfKey)(incomingKey) else nil
			if index and start and index >= start then
				return assert(controls.placementOf)(index + (if type(keys) == "table" then math.max(1, #keys) else 1))
			end
		end
		return at
	end
	type Positioned = {
		key: K,
		at: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
		base: ComposeTypes.Placement,
		shift: Vector2,
		target: { number },
		current: Vector2,
		publish: (Vector2) -> (),
		reduced: Types.ValueBoolean?,
	}
	local positioned: { [K]: Positioned } = {}
	local Compose, V2 = ctx.Compose, ctx.types.Vector2
	local controllerOwner = assert(Compose.currentOwner())
	local reductionBound = false
	local spring = ctx.motionSpring("snappy")
	local function peek<T>(value: ComposeTypes.ReadOnlyValue<T>): T
		return value:peek()
	end
	type Moving = { spring: ComposeTypes.SpringState, reference: { number } }
	local active: { [Positioned]: Moving } = {}
	local stopFrame: (() -> ())? = nil
	local function halt()
		if stopFrame then
			stopFrame()
			stopFrame = nil
		end
	end
	Compose.cleanup(halt)
	local function settle(entry: Positioned)
		active[entry] = nil
		entry.current = V2.new(entry.target[1], entry.target[2])
		entry.publish(entry.current)
		if next(active) == nil then
			halt()
		end
	end
	local function tick(delta: number)
		for entry, motion in active do
			Compose.stepSpring(motion.spring, entry.target, delta, spring.period, spring.damping)
			if Compose.springAtRest(motion.spring, entry.target, motion.reference, 1e-4) then
				settle(entry)
			else
				entry.current = V2.new(motion.spring.position[1], motion.spring.position[2])
				entry.publish(entry.current)
			end
		end
	end
	local function update(entry: Positioned, base: ComposeTypes.Placement)
		local proposed = placement(entry.key, base, peek)
		local shift = V2.new(proposed.crossOffset - base.crossOffset, proposed.offset - base.offset)
		local relaid = base.index == entry.base.index and (shift - entry.shift).Magnitude <= 0.5
		local snap = relaid and base ~= entry.base
		entry.base, entry.shift = base, shift
		if
			proposed.crossOffset == entry.target[1]
			and proposed.offset == entry.target[2]
			and not (snap and active[entry])
		then
			entry.publish(entry.current)
			return
		end
		entry.target[1], entry.target[2] = proposed.crossOffset, proposed.offset
		if relaid or shared.motionReduced() or read(entry.reduced) == true then
			settle(entry)
			return
		end
		local reference = { entry.current.X, entry.current.Y }
		local motion = active[entry]
		if motion then
			motion.reference = reference
		else
			active[entry] = { spring = Compose.createSpringState(reference, 2), reference = reference }
		end
		if stopFrame == nil then
			stopFrame = assert(ctx.runtime.host.frames).onFrame(tick)
		end
	end
	local placedOrder: Order? = nil
	local hadIncoming = false
	shared.setPlacement(function(accepted: boolean?)
		local move, incoming = moving:peek(), shared.incoming:peek()
		local settled = not shifting and accepted ~= true
		if accepted ~= nil then
			shifting = accepted
		end
		if settled then
			return
		end
		if incoming == nil then
			incomingRows, incomingBefore, incomingKey = nil, nil, nil
		end
		local restoreIncoming = hadIncoming and incoming == nil
		hadIncoming = incoming ~= nil
		local function refresh(entry: Positioned)
			local base = entry.at:peek()
			update(entry, base)
		end
		if reservedSlots == nil and incoming == nil and not restoreIncoming then
			local nextOrder = if move and shifting then orderOf(move) else nil
			local previous = placedOrder
			placedOrder = nextOrder
			if previous == nextOrder then
				return
			end
			local first = math.min(
				if previous then previous.first else math.huge,
				if nextOrder then nextOrder.first else math.huge
			)
			local last = math.max(if previous then previous.last else 0, if nextOrder then nextOrder.last else 0)
			local rows = ctx.readSource(source, peek)
			for index = first, math.min(last, #rows) do
				local entry = positioned[keyOf(rows[index], index)]
				if entry then
					refresh(entry)
				end
			end
		else
			placedOrder = nil
			for _, entry in positioned do
				refresh(entry)
			end
		end
	end)
	return {
		placement = placement,
		position = function(
			key: K,
			at: ComposeTypes.ReadOnlyValue<ComposeTypes.Placement>,
			publish: (Vector2) -> (),
			reducedMotion: Types.ValueBoolean?
		): (ComposeTypes.Placement) -> ()
			if not reductionBound then
				reductionBound = true
				Compose.withOwner(controllerOwner, function()
					Compose.watch(function(use: ComposeTypes.Use)
						if shared.motionReduced(use) or read(reducedMotion, use) == true then
							for _, entry in positioned do
								if active[entry] then
									settle(entry)
								end
							end
						end
					end)
				end)
			end
			local base = at:peek()
			local proposed = placement(key, base, peek)
			local entry: Positioned = {
				key = key,
				at = at,
				base = base,
				shift = V2.new(proposed.crossOffset - base.crossOffset, proposed.offset - base.offset),
				target = { proposed.crossOffset, proposed.offset },
				current = V2.new(proposed.crossOffset, proposed.offset),
				publish = publish,
				reduced = reducedMotion,
			}
			positioned[key] = entry
			Compose.cleanup(function()
				if positioned[key] == entry then
					positioned[key] = nil
				end
				active[entry] = nil
				if next(active) == nil then
					halt()
				end
			end)
			return function(base: ComposeTypes.Placement)
				update(entry, base)
			end
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
