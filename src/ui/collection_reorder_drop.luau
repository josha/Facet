--!strict
local DragTypes = require("./drag_types")
local Env = require("./environment_types")
local State = require("./collection_reorder_state")
return function<V, K>(shared: State.Reorder<V, K>, body: ScrollingFrame): ()
	local ctx, spec = shared.ctx, shared.spec
	local read = ctx.read
	local readSource = ctx.readSource
	local moving, incoming, drag = shared.moving, shared.incoming, shared.drag
	local source, controls, reservedSlots = shared.source, shared.controls, shared.reservedSlots
	local collectionId, sourceIndex, location = shared.collectionId, shared.sourceIndex, shared.location
	local horizontal, scaleOf, alongBody = shared.horizontal, shared.scaleOf, shared.alongBody
	local axis, crossAxis = shared.axis, shared.crossAxis
	local focus = shared.focus
	local destination = (if spec.drop then table.clone(spec.drop) else {}) :: DragTypes.TargetSpec
	local accept, drop, update = destination.accepts, destination.onDrop, destination.onUpdate
	if reservedSlots and destination.landing == nil then
		destination.landing = function(info: Env.DropInfo): Env.ScrollRect
			local session = drag.state:peek()
			local key = shared.recall(if session then session.payload else nil)
			local index = if key ~= nil then assert(controls.indexOfKey)(key) else nil
			if index == nil and info.insertion then
				local target, empty = shared.slotGap(if session then session.payload else nil, info.insertion)
				if target and empty then
					index = if empty < target then target - 1 else target
				else
					local before = info.insertion.beforeKey
					index = if before ~= nil then assert(controls.indexOfKey)(before :: K) else nil
				end
			end
			local at = assert(controls.placementOf)(index or (#read<<{ K }>>(reservedSlots) + 1))
			local scale = scaleOf(body)
			local items = body:FindFirstChild("Items") :: GuiObject?
			local origin = if items then items.AbsolutePosition else body.AbsolutePosition - body.CanvasPosition * scale
			return {
				x = origin.X + (if horizontal then at.offset else at.crossOffset) * scale,
				y = origin.Y + (if horizontal then at.crossOffset else at.offset) * scale,
				w = (if horizontal then at.size else at.crossSize) * scale,
				h = (if horizontal then at.crossSize else at.size) * scale,
			}
		end
	end
	local noCarried: { K } = {}
	local cachedRows: { V }? = nil
	local cachedCarried: { K }? = nil
	local remaining: { K } = {}
	local rowIndices: { number } = {}
	local remainingIndex: { [K]: number } = {}
	local function indexRows(rows: { V }, carried: { K })
		if rows ~= cachedRows or carried ~= cachedCarried then
			cachedRows, cachedCarried = rows, carried
			remaining, rowIndices, remainingIndex = {}, {}, {}
			local included: { [K]: boolean } = {}
			for _, key in carried do
				included[key] = true
			end
			for index, item in rows do
				local key = shared.keyOf(item, index)
				if not included[key] then
					table.insert(remaining, key)
					table.insert(rowIndices, assert(controls.indexOfKey)(key) or index)
					remainingIndex[key] = #remaining
				end
			end
		end
	end
	local function pointerSlot(position: Vector2?): number
		local slot = 0
		local offset, across = math.huge, math.huge
		if position then
			offset = alongBody(body, position) + axis(body.CanvasPosition)
			across = crossAxis(position - body.AbsolutePosition) / scaleOf(body) + crossAxis(body.CanvasPosition)
		end
		local low, high = 1, #remaining
		while low <= high do
			local middle = math.floor((low + high) / 2)
			local at = assert(controls.placementOf)(rowIndices[middle])
			local crossed = if shared.grid
				then offset >= at.offset + at.size
					or (
						offset >= at.offset
						and offset < at.offset + at.size
						and across >= at.crossOffset + at.crossSize / 2
					)
				else offset >= at.offset + at.size / 2
			if crossed then
				slot, low = middle, middle + 1
			else
				high = middle - 1
			end
		end
		return slot
	end
	local function insertion(payload: unknown, info: DragTypes.Proposal)
		local rows = readSource(source)
		local data = payload :: { collection: unknown, keys: { K }? }
		local same = type(payload) == "table" and data.collection == collectionId and info.operation == "move"
		local move, session = moving:peek(), drag.state:peek()
		local carried: { K } = if move
				and session
				and session.source == body
				and info.operation == "move"
			then move.keys
			elseif same then data.keys or noCarried
			else noCarried
		indexRows(rows, carried)
		local slot = pointerSlot(info.position)
		if move and move.keyboard and same then
			slot = move.slot
		end
		if info.insertion then
			local before, after = info.insertion.beforeKey, info.insertion.afterKey
			local beforeIndex = if before ~= nil then remainingIndex[before :: K] else nil
			local afterIndex = if after ~= nil then remainingIndex[after :: K] else nil
			if (before ~= nil or after ~= nil) and beforeIndex == nil and afterIndex == nil then
				info.invalid = "The insertion neighbors were removed"
				return
			end
			slot = if beforeIndex then beforeIndex - 1 elseif afterIndex then afterIndex else 0
		end
		info.insertion =
			{ collection = collectionId, beforeKey = remaining[slot + 1], afterKey = remaining[slot], slot = slot }
	end
	shared.setPointerSlot(function(position: Vector2): number?
		local move = moving:peek()
		if move == nil then
			return nil
		end
		indexRows(readSource(source), move.keys)
		return pointerSlot(position)
	end)
	local function localMove(payload: unknown, info: DragTypes.Proposal): boolean
		local data = payload :: { collection: unknown, keys: { K }? }
		if
			type(payload) ~= "table"
			or data.collection ~= collectionId
			or not spec.onReorder
			or info.operation ~= "move"
		then
			return false
		end
		if type(data.keys) ~= "table" or #data.keys == 0 then
			return false
		end
		local live = sourceIndex:peek()
		for _, key in data.keys do
			if live[key] == nil then
				return false
			end
		end
		return true
	end
	destination.propose = insertion
	destination.accepts = function(payload: unknown, info: DragTypes.Proposal): (boolean, string?)
		if info.invalid then
			return false, info.invalid
		end
		if readSource(shared.sort) ~= nil then
			return false, "Clear sorting before inserting items"
		end
		if localMove(payload, info) then
			if location then
				local accepted = location((payload :: { keys: { K } }).keys, (info.insertion :: Env.DropInsertion).slot)
				return accepted, if accepted then nil else "Move items within the same folder"
			end
			return true, nil
		end
		if accept then
			return accept(payload, info)
		end
		return drop ~= nil, "This collection does not accept these items"
	end
	destination.onDrop = function(payload: unknown, info: DragTypes.Proposal): (boolean | "pending")?
		if localMove(payload, info) then
			shared.commitLocal((payload :: { keys: { K } }).keys, (info.insertion :: Env.DropInsertion).slot)
			return true
		end
		return if drop
			then ((drop :: unknown) :: (unknown, Env.DropInfo) -> (boolean | "pending")?)(payload, info)
			else false
	end
	local leave = destination.onLeave
	destination.onLeave = function(payload)
		incoming:set(nil)
		if leave then
			leave(payload)
		end
	end
	destination.onUpdate = function(payload: unknown, info: DragTypes.Proposal, accepted: boolean, reason: string?): ()
		local session = drag.state:peek()
		incoming:set(if accepted and session and session.source ~= body then info.insertion else nil)
		local move = moving:peek()
		local insertion = info.insertion
		if move and not move.keyboard and insertion and move.slot ~= insertion.slot then
			local next = table.clone(move)
			next.slot = insertion.slot
			moving:set(next)
		end
		if update then
			update(payload, info, accepted, reason)
		end
	end
	destination.autoscroll = spec.autoscroll
	destination.scroll = function(position: Vector2, delta: number): boolean
		local scale = scaleOf(body)
		local size = axis(body.AbsoluteWindowSize) / scale
		local edge = math.min(40, size / 4)
		local at = alongBody(body, position)
		local speed = if edge <= 0
				or at < 0
				or at > size
			then 0
			elseif at < edge then -(edge - at) / edge
			elseif at > size - edge then (at - size + edge) / edge
			else 0
		local rows = readSource(source)
		local last = if #rows > 0 then assert(controls.placementOf)(#rows) else nil
		local limit = if last then math.max(0, last.offset + last.size - size) else 0
		local now = axis(body.CanvasPosition)
		local next = math.clamp(now + speed * 600 * delta, 0, limit)
		if next == now then
			return false
		end
		shared.canvasOffset(body, next)
		if moving:peek() then
			shared.movePointer(position)
		end
		return true
	end
	if spec.drop or spec.onReorder then
		destination.feedback = false
		drag.register(body, destination)
	end
	drag.own(body)
	ctx.Compose.watch(function(use)
		local node = use(focus)
		local session = drag.state:peek()
		if session and session.source == body and session.mode == "armed" then
			drag.hover(drag.targetOf(node), nil)
		end
	end)
end
