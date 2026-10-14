--!strict
local DragTypes = require("./drag_types")
local Env = require("./environment_types")
local State = require("./collection_reorder_state")
return function<V, K>(shared: State.Reorder<V, K>, body: ScrollingFrame): ()
	local ctx, spec = shared.ctx, shared.spec
	local Compose = ctx.Compose
	local read = ctx.read
	local moving, incoming, drag, sort = shared.moving, shared.incoming, shared.drag, shared.sort
	local source, keyOf, controls, reservedSlots = shared.source, shared.keyOf, shared.controls, shared.reservedSlots
	local collectionId, sourceIndex, location, commitLocal =
		shared.collectionId, shared.sourceIndex, shared.location, shared.commitLocal
	local grid, horizontal, scaleOf, alongBody = shared.grid, shared.horizontal, shared.scaleOf, shared.alongBody
	local axis, crossAxis, canvasOffset, movePointer =
		shared.axis, shared.crossAxis, shared.canvasOffset, shared.movePointer
	local focus = shared.focus
	local destination = (if spec.drop then table.clone(spec.drop) else {}) :: DragTypes.TargetSpec
	local accept, drop, update = destination.accepts, destination.onDrop, destination.onUpdate
	if reservedSlots and destination.landing == nil then
		destination.landing = function(info: Env.DropInfo): Env.ScrollRect
			local session = drag.state:peek()
			local payload = if session then session.payload else nil
			local data = if type(payload) == "table" then payload :: { keys: { K }? } else nil
			local key = if data and data.keys then data.keys[1] else nil
			local index = if key ~= nil and table.find(read(reservedSlots), key)
				then assert(controls.indexOfKey)(key :: K)
				else nil
			if index == nil and info.insertion then
				local before = info.insertion.beforeKey
				index = if before ~= nil then assert(controls.indexOfKey)(before :: K) else nil
			end
			local at = assert(controls.placementOf)(index or (#read(reservedSlots) + 1))
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
	local function insertion(payload: unknown, info: DragTypes.Proposal)
		local rows: { V } = read(source)
		local data = payload :: { collection: unknown, keys: { K }? }
		local same = type(payload) == "table" and data.collection == collectionId and info.operation == "move"
		local carried = if same then data.keys or noCarried else noCarried
		if rows ~= cachedRows or carried ~= cachedCarried then
			cachedRows, cachedCarried = rows, carried
			remaining, rowIndices, remainingIndex = {}, {}, {}
			local included: { [K]: boolean } = {}
			for _, key in carried :: { K } do
				included[key] = true
			end
			for index, item in rows do
				local key = keyOf(item, index)
				if not included[key] then
					table.insert(remaining, key)
					table.insert(rowIndices, assert(controls.indexOfKey)(key) or index)
					remainingIndex[key] = #remaining
				end
			end
		end
		local slot = 0
		local offset, across = math.huge, math.huge
		if info.position then
			offset = alongBody(body, info.position) + axis(body.CanvasPosition)
			across = crossAxis(info.position - body.AbsolutePosition) / scaleOf(body) + crossAxis(body.CanvasPosition)
		end
		local low, high = 1, #remaining
		while low <= high do
			local middle = math.floor((low + high) / 2)
			local at = assert(controls.placementOf)(rowIndices[middle])
			local crossed = if grid
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
		local move = moving:peek()
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
		if type(data.keys) ~= "table" or #(data.keys :: { K }) == 0 then
			return false
		end
		local live = sourceIndex:peek()
		for _, key in data.keys :: { K } do
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
		if read(sort) ~= nil then
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
			commitLocal((payload :: { keys: { K } }).keys, (info.insertion :: Env.DropInsertion).slot)
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
	destination.onUpdate = function(payload, info, accepted, reason)
		local session = drag.state:peek()
		incoming:set(if accepted and session and session.source ~= body then info.insertion else nil)
		local move = moving:peek()
		if move and not move.keyboard and accepted and move.slot ~= (info.insertion :: Env.DropInsertion).slot then
			local next = table.clone(move)
			next.slot = (info.insertion :: Env.DropInsertion).slot
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
		local rows = read(source)
		local last = if #rows > 0 then assert(controls.placementOf)(#rows) else nil
		local limit = if last then math.max(0, last.offset + last.size - size) else 0
		local now = axis(body.CanvasPosition)
		local next = math.clamp(now + speed * 600 * delta, 0, limit)
		if next == now then
			return false
		end
		canvasOffset(body, next)
		if moving:peek() then
			movePointer(position)
		end
		return true
	end
	if spec.drop or spec.onReorder then
		destination.feedback = false
		drag.register(body, destination)
	end
	drag.own(body)
	Compose.watch(function(use)
		local node = use(focus)
		local session = drag.state:peek()
		if session and session.source == body and session.mode == "armed" then
			drag.hover(drag.targetOf(node), nil)
		end
	end)
end
