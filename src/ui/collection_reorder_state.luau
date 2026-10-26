--!strict
local ControlTypes = require("./control_types")
local policy = require("./collection_policy")
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local gestureOf = require("./gesture_service")
local arbitration = require("./gesture_arbitration")
local sessionOf = require("./drag_session")
local DragTypes = require("./drag_types")
local Env = require("./environment_types")
local reducedMotion = require("./motion").reduced
export type Move<V, K> = {
	preview: GuiObject?,
	key: K,
	keys: { K },
	included: { [K]: boolean },
	remaining: { K },
	slot: number,
	rows: { V },
	pointer: Vector2?,
	keyboard: boolean,
	tap: boolean,
	navigationCross: number?,
}
export type Gesture<V, K> = {
	captured: InputObject?,
	recycled: boolean,
	selectedPickup: boolean,
	lastTap: { key: K, position: Vector2, at: number }?,
	pendingInput: InputObject?,
	pickupPosition: Vector2?,
	origin: Vector2?,
	travel: number,
	keyboardTarget: TextButton?,
	touchKey: K?,
	touchOrigin: Vector2?,
	touchTransfer: { key: K, pointer: InputObject, options: DragTypes.SourceSpec, keys: { K }, items: { V } }?,
	releaseScrollers: (() -> ())?,
	gestureOwner: GuiObject?,
}
export type Reorder<V, K> = {
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
	reservedSlots: Types.Input<{ K }>?,
	gesture: Gesture<V, K>,
	moving: ComposeTypes.Value<Move<V, K>?>,
	choosingDestination: ComposeTypes.Value<boolean>,
	incoming: ComposeTypes.Value<Env.DropInsertion?>,
	reorderable: boolean,
	drag: DragTypes.Service,
	arbiter: arbitration.Arbiter,
	collectionId: unknown,
	rowNodes: { [K]: Frame },
	deletable: boolean,
	preferred: ComposeTypes.ReadOnlyValue<Enum.PreferredInput>?,
	controlsShown: ComposeTypes.Value<boolean>,
	mode: string,
	marked: boolean,
	minusShown: boolean,
	markShown: ComposeTypes.Value<boolean>,
	leading: ComposeTypes.Value<number>,
	trailing: ComposeTypes.Value<number>,
	header: ComposeTypes.Value<number>,
	motionReduced: (ComposeTypes.Use?) -> boolean,
	horizontal: boolean,
	axis: (Vector2) -> number,
	crossAxis: (Vector2) -> number,
	scaleOf: (ScrollingFrame) -> number,
	alongBody: (ScrollingFrame, Vector2) -> number,
	canvasOffset: (ScrollingFrame, number) -> (),
	input: UserInputService?,
	rowKeys: { [Instance]: K },
	gui: GuiService?,
	focus: ComposeTypes.ReadOnlyValue<GuiObject?>,
	pluginGui: Instance?,
	disarm: () -> (),
	cancel: () -> (),
	movable: (V) -> boolean,
	sourceIndex: ComposeTypes.Value<{ [K]: V }>,
	begin: (K, Vector2?, boolean?, boolean?) -> (),
	commitLocal: ({ K }, number) -> (),
	commit: (...unknown) -> (),
	movePointer: (Vector2) -> (),
	setPointerSlot: ((Vector2) -> number?) -> (),
	step: (number, boolean?) -> (),
	chosen: (ComposeTypes.Use?, boolean?, boolean?) -> { K },
	canDelete: (ComposeTypes.Use?) -> boolean,
	canDeleteSelected: (ComposeTypes.Use?) -> boolean,
	remove: (boolean?) -> (),
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
): Reorder<V, K>
	local Compose = ctx.Compose
	local read = ctx.read
	local V2, E = ctx.types.Vector2, ctx.types.Enum
	local moving: ComposeTypes.Value<Move<V, K>?> = Compose.cell(nil :: Move<V, K>?)
	local choosingDestination = Compose.cell(false)
	local incoming: ComposeTypes.Value<Env.DropInsertion?> = Compose.cell(nil :: Env.DropInsertion?)
	local reorderable = spec.reorderable == true or spec.drag ~= nil
	local drag = sessionOf(ctx)
	local arbiter = gestureOf(ctx)
	local collectionId = spec.collectionId or source
	local rowNodes: { [K]: Frame } = {}
	local stopLocal: () -> () = function() end
	local pointerSlot: (Vector2) -> number? = function()
		return nil
	end
	local deletable = spec.deletable == true
	local preferred: ComposeTypes.ReadOnlyValue<Enum.PreferredInput>? = if ctx.config.userInputService
		then ctx.observe.PreferredInput(ctx.config.userInputService)
		else nil
	local controlsShown = Compose.formula(function(use: ComposeTypes.Use): boolean
		local kind = if preferred then use(preferred) else nil
		return kind == nil or read(editing, use) == true
	end)

	local mode = spec.selectionMode or (if spec.selection or spec.onSelectionChange then "single" else "none")
	local marked = spec.selectionIndicator ~= false and (mode == "multiple" or (mode ~= "none" and not deletable))
	local minusShown = deletable and not marked
	local markShown = Compose.formula(function(use: ComposeTypes.Use): boolean
		return marked
			and read(editing, use) == true
			and (preferred == nil or use(preferred) ~= E.PreferredInput.KeyboardAndMouse)
	end)
	local leading = Compose.formula(function(use: ComposeTypes.Use): number
		return if (minusShown and use(controlsShown)) or use(markShown) then 44 else 0
	end)
	local trailing = Compose.formula(function(use: ComposeTypes.Use): number
		return if reorderable and use(controlsShown) then 44 else 0
	end)
	local header = Compose.formula(function(use: ComposeTypes.Use): number
		local kind = if preferred then use(preferred) else nil
		local reserved = editing ~= nil
			and (marked or reorderable or deletable)
			and (kind == E.PreferredInput.Touch or kind == E.PreferredInput.Gamepad)
		return if grid then math.max(use(leading), use(trailing), if reserved then 44 else 0) else 0
	end)
	local motionReduced = reducedMotion(ctx)
	local horizontal = spec.direction == "horizontal"
	local function axis(position: Vector2): number
		return if horizontal then position.X else position.Y
	end

	local function crossAxis(position: Vector2): number
		return if horizontal then position.Y else position.X
	end

	local function scaleOf(body: ScrollingFrame): number
		local unit = body:FindFirstChild("LayoutUnit") :: GuiObject?
		local scale = if unit then unit.AbsoluteSize.X else 0
		return if scale > 0 then scale else 1
	end
	local function alongBody(body: ScrollingFrame, position: Vector2): number
		return (axis(position) - axis(body.AbsolutePosition)) / scaleOf(body)
	end
	local function canvasOffset(body: ScrollingFrame, value: number): ()
		body.CanvasPosition = if horizontal
			then V2.new(value, body.CanvasPosition.Y)
			else V2.new(body.CanvasPosition.X, value)
	end
	local input = ctx.config.userInputService
	local gesture: Gesture<V, K> = {
		captured = nil,
		recycled = false,
		selectedPickup = false,
		lastTap = nil,
		pendingInput = nil,
		pickupPosition = nil,
		origin = nil,
		travel = 0,
		keyboardTarget = nil,
		touchKey = nil,
		touchOrigin = nil,
		touchTransfer = nil,
		releaseScrollers = nil,
		gestureOwner = nil,
	}
	local rowKeys = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: K }
	local gui = ctx.config.guiService
	local focus: ComposeTypes.ReadOnlyValue<GuiObject?> = if gui and gui.GetPropertyChangedSignal
		then ctx.observe.SelectedObject(gui)
		else Compose.cell(nil :: GuiObject?)
	local function disarm()
		gesture.touchKey, gesture.touchOrigin = nil, nil
	end
	local function clearMove()
		if gesture.gestureOwner then
			arbiter.cancelOwner(gesture.gestureOwner)
			gesture.gestureOwner = nil
		end
		local move, selected = moving:peek(), gui and gui.SelectedObject
		local restore = move ~= nil and move.keyboard and selected == gesture.keyboardTarget
		gesture.captured = nil
		gesture.touchTransfer = nil
		gesture.selectedPickup = false
		disarm()
		if gesture.releaseScrollers then
			gesture.releaseScrollers()
			gesture.releaseScrollers = nil
		end
		if restore and move and gui then
			gui.SelectedObject = nil
			local index = assert(controls.indexOfKey)(move.key)
			if index then
				local body = bodyOf()
				canvasOffset(
					body,
					assert(controls.offsetOf)(index, "center", axis(body.AbsoluteWindowSize) / scaleOf(body))
				)
			end
		end
		moving:set(nil)
		if move and move.preview then
			move.preview:Destroy()
		end
		if restore and move and gui then
			local row = rowNodes[move.key]
			local handle = row and row:FindFirstChild("Move")
			if handle and handle:IsA("GuiObject") and handle.Visible then
				gui.SelectedObject = handle
			end
		end
	end
	stopLocal = clearMove
	local function cancel()
		local session = drag.state:peek()
		if session and session.executing then
			return
		end
		if session and session.source == bodyOf() then
			drag.finish(false, "Cancelled")
		end
		clearMove()
	end
	Compose.cleanup(cancel)
	local function movable(item: V): boolean
		return policy.allows(spec.movable, item) and not policy.disabled(spec.disabled, item)
	end
	local sourceIndex = Compose.formula(function(use: ComposeTypes.Use): { [K]: V }
		local result: { [K]: V } = {}
		for index, item in read(spec.selectionFrom or source, use) do
			result[keyOf(item, index)] = item
		end
		return result
	end)
	local function begin(key: K, position: Vector2?, quiet: boolean?, tap: boolean?): ()
		gesture.lastTap = nil
		local session = drag.state:peek()
		if session and session.source ~= bodyOf() then
			return
		end
		if
			not reorderable
			or read(sort) ~= nil
			or (not spec.onReorder and not spec.drag)
			or (position ~= nil and gesture.captured ~= nil and moving:peek() ~= nil)
		then
			return
		end
		if position and gesture.pendingInput then
			local node = rowNodes[key]
			local decision = arbiter.get(gesture.pendingInput)
			if decision and (decision.owner ~= node or (decision.kind ~= "pending" and decision.kind ~= "drag")) then
				return
			end
			if node then
				if not decision then
					arbiter.begin(
						gesture.pendingInput,
						node,
						gesture.pickupPosition or position,
						{ pickup = "immediate" }
					)
				end
				if not arbiter.claim(gesture.pendingInput, node, "drag") then
					return
				end
				gesture.gestureOwner = node
			end
		end
		local rows, selected = read(source), read(selection)
		for index, item in rows do
			if keyOf(item, index) == key and not movable(item) then
				return
			end
		end
		local keys: { K } = {}
		local indices: { [K]: boolean } = {}
		local items: { V } = {}
		for index, item in read(spec.selectionFrom or source) do
			local candidate = keyOf(item, index)
			if movable(item) and (candidate == key or (selected[key] and selected[candidate])) then
				table.insert(keys, candidate)
				table.insert(items, item)
				indices[candidate] = true
			end
		end
		local prepared = if position ~= nil or tap then gesture.touchTransfer else nil
		if prepared and prepared.key == key and prepared.pointer == gesture.pendingInput then
			keys, items = table.clone(prepared.keys), table.clone(prepared.items)
			table.clear(indices)
			for _, capturedKey in keys do
				indices[capturedKey] = true
			end
		end
		local remaining: { K } = {}
		local before, started = 0, false
		for index, item in rows do
			local candidate = keyOf(item, index)
			if indices[candidate] then
				started = true
			else
				table.insert(remaining, candidate)
				if not started then
					before += 1
				end
			end
		end
		if #keys > 0 then
			local options = (
				if prepared
						and prepared.key == key
						and prepared.pointer == gesture.pendingInput
					then prepared.options
					elseif spec.drag then spec.drag(items, keys)
					else {
						payload = { collection = collectionId, keys = keys, items = items },
						operations = { "move" :: "move" },
					}
			) :: DragTypes.SourceSpec
			if tap and not options.armOnTap then
				return
			end
			local live = gesture.pendingInput ~= nil
				and gesture.pendingInput.UserInputState ~= E.UserInputState.End
				and gesture.pendingInput.UserInputState ~= E.UserInputState.Cancel
			gesture.captured = if position and live then gesture.pendingInput else nil
			local row = rowNodes[key]
			if
				gesture.captured
				and gesture.captured.UserInputType == E.UserInputType.Touch
				and row
				and not gesture.releaseScrollers
			then
				gesture.releaseScrollers = scrollLock.holdAncestors(row)
			end
			gesture.recycled = false
			activation.consume(gesture.captured)
			local nextMove: Move<V, K> = {
				preview = if options.preview then options.preview:Clone() else nil,
				key = key,
				keys = keys,
				included = indices,
				remaining = remaining,
				slot = before,
				rows = rows,
				pointer = position,
				keyboard = position == nil,
				tap = tap == true,
			}
			local valid, ended = options.valid, options.onEnd
			options = table.clone(options)
			options.mark = false
			choosingDestination:set(false)
			if spec.drag and (spec.onReorder or spec.drop) then
				options.navigationHint = "Y: choose destination"
			end
			local original = rowNodes[key]
			local origin = if original then original.AbsolutePosition + original.AbsoluteSize / 2 else position
			options.returnPosition = function()
				local row = rowNodes[key]
				return if row and row.Parent then row.AbsolutePosition + row.AbsoluteSize / 2 else origin :: Vector2
			end
			options.valid = function()
				if valid and not valid() then
					return false
				end
				local live = sourceIndex:peek()
				for _, key in keys do
					local item = live[key]
					if item == nil or not movable(item) then
						return false
					end
				end
				return true
			end
			options.onEnd = function(accepted, reason)
				stopLocal()
				if ended then
					ended(accepted, reason)
				end
			end
			drag.begin(
				bodyOf(),
				options,
				if position then "pointer" else "armed",
				gesture.captured,
				false,
				if original
					then {
						position = if position
							then gesture.pickupPosition or position
							else original.AbsolutePosition + original.AbsoluteSize / 2,
						source = original :: GuiObject,
					}
					else nil
			)
			moving:set(nextMove)
			if position then
				drag.update(position)
			end
			if
				position == nil
				and not quiet
				and gesture.keyboardTarget
				and gesture.keyboardTarget.Visible
				and ctx.config.guiService
			then
				ctx.config.guiService.SelectedObject = gesture.keyboardTarget
			end
		end
	end
	local function commitLocal(keys: { K }, slot: number)
		if location then
			local accepted, siblingSlot, parentKey = location(keys, slot)
			if accepted then
				assert(spec.onReorder)(keys, siblingSlot, parentKey)
			end
			return
		end
		local rows = read(source)
		local included, remaining = {}, {}
		for _, key in keys do
			included[key] = true
		end
		for index, item in rows do
			local key = keyOf(item, index)
			if not included[key] then
				table.insert(remaining, key)
			end
		end
		local move = { rows = rows, remaining = remaining, keys = keys, slot = slot }
		local reordered = table.clone(move.remaining)
		local visible = {}
		for index, item in rows do
			local key = keyOf(item, index)
			if included[key] then
				table.insert(visible, key)
			end
		end
		for index, key in visible do
			table.insert(reordered, move.slot + index, key)
		end
		for index, item in move.rows do
			if not movable(item) and keyOf(item, index) ~= reordered[index] then
				return
			end
		end
		for index, item in move.rows do
			if keyOf(item, index) ~= reordered[index] then
				assert(spec.onReorder)(move.keys, move.slot)
				return
			end
		end
	end
	local function commit()
		local move = moving:peek()
		if move == nil then
			return
		end
		local session = drag.state:peek()
		if move.keyboard and (session == nil or session.target == nil) then
			drag.commit(bodyOf())
		else
			drag.commit(nil)
		end
	end
	local function movePointer(position: Vector2): ()
		local move = moving:peek()
		if move == nil then
			return
		end
		local nextMove = table.clone(move)
		nextMove.pointer = position
		moving:set(nextMove)
		drag.update(position)
		local session, live = drag.state:peek(), moving:peek()
		if session and session.target ~= bodyOf() and live then
			local slot = pointerSlot(position)
			if slot and live.slot ~= slot then
				local next = table.clone(live)
				next.slot = slot
				moving:set(next)
			end
		end
	end
	local function step(delta: number, along: boolean?): ()
		local current = moving:peek()
		local session = drag.state:peek()
		if current and not (session and session.pending) then
			local nextMove = table.clone(current)
			nextMove.slot = math.clamp(current.slot + delta, 0, #current.remaining)
			if grid and along then
				local function point(slot: number): (number, number)
					local candidate = current.remaining[slot + 1]
					local index = if candidate then assert(controls.indexOfKey)(candidate) else #current.rows
					local at = assert(controls.placementOf)(index or 1)
					return at.offset, at.crossOffset + (if candidate then 0 else at.crossSize)
				end
				local origin, across = point(current.slot)
				across = current.navigationCross or across
				local nearest, distance = math.huge, math.huge
				nextMove.slot, nextMove.navigationCross = current.slot, across
				for slot = 0, #current.remaining do
					local offset, cross = point(slot)
					local forward, side = (offset - origin) * delta, math.abs(cross - across)
					if forward > 0 and (forward < nearest or (forward == nearest and side < distance)) then
						nearest, distance, nextMove.slot = forward, side, slot
					end
				end
			else
				nextMove.navigationCross = nil
			end
			moving:set(nextMove)
			local body = bodyOf()
			local at = current.remaining[nextMove.slot + 1] or current.remaining[nextMove.slot]
			local index = if at then assert(controls.indexOfKey)(at) else nil
			if index then
				canvasOffset(
					body,
					assert(controls.offsetOf)(index, "center", axis(body.AbsoluteWindowSize) / scaleOf(body))
				)
			end
			if current.keyboard then
				drag.hover(body, nil)
			end
		end
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local rows, order = read(source, use), read(sort, use)
		local move = moving:peek()
		if move then
			local found = 0
			for index, item in read(spec.selectionFrom or source, use) do
				if move.included[keyOf(item, index)] and movable(item) then
					found += 1
				end
			end
			if order ~= nil or found ~= #move.keys then
				cancel()
			elseif rows ~= move.rows then
				local next = table.clone(move)
				next.rows, next.remaining = rows, {}
				for index, item in rows do
					local key = keyOf(item, index)
					if not move.included[key] then
						table.insert(next.remaining, key)
					end
				end
				next.slot = math.min(next.slot, #next.remaining)
				moving:set(next)
			end
		end
	end)
	local pluginGui = ctx.config.inputParent
	if pluginGui and not pluginGui:IsA("PluginGui") then
		pluginGui = nil
	end
	local function chosen(use: ComposeTypes.Use?, selectedOnly: boolean?, allSelected: boolean?): { K }
		local keys, selected = {}, read(selection, use)
		for index, item in read(if allSelected then spec.selectionFrom or source else source, use) do
			local key = keyOf(item, index)
			if selected[key] then
				table.insert(keys, key)
			end
		end
		if #keys == 0 and not selectedOnly and read(editing, use) == true then
			local body = bodyOf()
			local at: Instance? = if use then use(focus) else focus:peek()
			if at and not at:IsDescendantOf(body) then
				at = nil
			end
			while at and at ~= body and #keys == 0 do
				local key = rowKeys[at]
				if key == nil then
					for _, node in at:GetChildren() do
						key = rowKeys[node]
						if key ~= nil then
							break
						end
					end
				end
				if key ~= nil then
					table.insert(keys, key)
				end
				at = at.Parent
			end
		end
		return keys
	end
	local function deletes(selectedOnly: boolean?): (ComposeTypes.Use?) -> boolean
		return function(use: ComposeTypes.Use?): boolean
			if not selectedOnly then
				local at: Instance? = ctx.readSource(focus, use)
				while at do
					if at:GetAttribute("FacetSelectionOwner") == true then
						if at ~= bodyOf() then
							return false
						end
						break
					end
					at = at.Parent
				end
			end
			return deletable
				and (if use then use(moving) else moving:peek()) == nil
				and #chosen(use, selectedOnly, true) > 0
		end
	end
	local canDelete, canDeleteSelected = deletes(false), deletes(true)
	local function remove(selectedOnly: boolean?): ()
		local keys = {}
		for _, key in chosen(nil, selectedOnly, true) do
			for index, item in read(spec.selectionFrom or source) do
				if
					keyOf(item, index) == key
					and policy.allows(spec.rowDeletable, item)
					and not policy.disabled(spec.disabled, item)
				then
					table.insert(keys, key)
				end
			end
		end
		if #keys > 0 and spec.onDelete then
			spec.onDelete(keys)
		end
	end
	return {
		ctx = ctx,
		UI = UI,
		spec = spec,
		source = source,
		keyOf = keyOf,
		controls = controls,
		bodyOf = bodyOf,
		selection = selection,
		sort = sort,
		editing = editing,
		grid = grid,
		location = location,
		instantLayout = instantLayout,
		reservedSlots = reservedSlots,
		gesture = gesture,
		moving = moving,
		choosingDestination = choosingDestination,
		incoming = incoming,
		reorderable = reorderable,
		drag = drag,
		arbiter = arbiter,
		collectionId = collectionId,
		rowNodes = rowNodes,
		deletable = deletable,
		preferred = preferred,
		controlsShown = controlsShown,
		mode = mode,
		marked = marked,
		minusShown = minusShown,
		markShown = markShown,
		leading = leading,
		trailing = trailing,
		header = header,
		motionReduced = motionReduced,
		horizontal = horizontal,
		axis = axis,
		crossAxis = crossAxis,
		scaleOf = scaleOf,
		alongBody = alongBody,
		canvasOffset = canvasOffset,
		input = input,
		rowKeys = rowKeys,
		gui = gui,
		focus = focus,
		pluginGui = pluginGui,
		disarm = disarm,
		cancel = cancel,
		movable = movable,
		sourceIndex = sourceIndex,
		begin = begin,
		commitLocal = commitLocal,
		commit = commit,
		movePointer = movePointer,
		setPointerSlot = function(slotAt: (Vector2) -> number?)
			pointerSlot = slotAt
		end,
		step = step,
		chosen = chosen,
		canDelete = canDelete,
		canDeleteSelected = canDeleteSelected,
		remove = remove,
	}
end
