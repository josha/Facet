--!strict
local policy = require("./collection_policy")
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local sessionOf = require("./drag_session")
local pointerOf = require("./drag_pointer")
local reducedMotion = require("./motion").reduced
export type Editor<V, K> = {
	wrap: (GuiObject, ComposeTypes.Readable<V>, K, boolean?) -> Frame,
	overlay: (boolean?) -> Frame,
	leading: ComposeTypes.Readable<number>,
	trailing: ComposeTypes.Readable<number>,
	header: ComposeTypes.Readable<number>,
	press: (K, InputObject) -> (),
	mouseDown: (Vector2) -> (),
	finish: (InputObject) -> (),
	busy: () -> boolean,
	pickUp: (K, InputObject?) -> boolean,
	deleteSelected: () -> (),
	canDeleteSelected: (ComposeTypes.Use?) -> boolean,
}
type Move<V, K> = {
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
return function<V, K>(
	ctx: Types.Context,
	UI: { Button: Types.Constructor<InputTypes.ButtonProps, TextButton> },
	spec: CollectionTypes.ReorderOptions<V, K>,
	source: Types.Value<{ V }>,
	keyOf: (V, number) -> K,
	controls: ComposeTypes.OrderedCollectionControls<K>,
	bodyOf: () -> ScrollingFrame,
	selection: ComposeTypes.Cell<CollectionTypes.Selection<K>>,
	sort: ComposeTypes.Cell<CollectionTypes.Sort?>,
	editing: Types.ValueBoolean?,
	grid: boolean?,
	location: (({ K }, number) -> (boolean, number, K?))?
): Editor<V, K>
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local moving: ComposeTypes.Cell<Move<V, K>?> = Compose.cell(nil :: Move<V, K>?)
	local choosingDestination = Compose.cell(false)
	local TAP = 3
	local STACK = 6
	local FEEDBACK_Z = 1000
	local SLOP = 10
	local reorderable = spec.reorderable == true or spec.drag ~= nil
	local drag = sessionOf(ctx)
	local collectionId = spec.collectionId or source
	local rowNodes: { [K]: Frame } = {}
	local stopLocal: () -> () = function() end
	local deletable = spec.deletable == true
	local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if ctx.config.userInputService
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
	local captured: InputObject?
	local recycled = false
	local selectedPickup = false
	local lastTap: { key: K, position: Vector2, at: number }?
	local pendingInput: InputObject?
	local pickupPosition: Vector2?
	local origin: Vector2? = nil
	local travel = 0
	local keyboardTarget: TextButton?
	local rowKeys: { [Instance]: K } = setmetatable({}, { __mode = "k" }) :: any
	local gui = ctx.config.guiService
	local focus: ComposeTypes.Readable<GuiObject?> = if gui and gui.GetPropertyChangedSignal
		then ctx.observe.SelectedObject(gui)
		else Compose.cell(nil :: GuiObject?)
	local touchKey: K? = nil
	local touchOrigin: Vector2? = nil
	local releaseScrollers: (() -> ())? = nil
	local function disarm()
		touchKey, touchOrigin = nil, nil
	end
	local function clearMove()
		local move, selected = moving:peek(), gui and gui.SelectedObject
		local restore = move ~= nil and move.keyboard and selected == keyboardTarget
		captured = nil
		selectedPickup = false
		disarm()
		if releaseScrollers then
			releaseScrollers()
			releaseScrollers = nil
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
		lastTap = nil
		if
			not reorderable
			or read(sort) ~= nil
			or (not spec.onReorder and not spec.drag)
			or (position ~= nil and captured ~= nil and moving:peek() ~= nil)
		then
			return
		end
		local rows, selected = read(source), read(selection)
		for index, item in rows do
			if keyOf(item, index) == key and not movable(item) then
				return
			end
		end
		local keys: { K } = {}
		local indices: { [K]: boolean } = {}
		local items = {}
		for index, item in read(spec.selectionFrom or source) do
			local candidate = keyOf(item, index)
			if movable(item) and (candidate == key or (selected[key] and selected[candidate])) then
				table.insert(keys, candidate)
				table.insert(items, item)
				indices[candidate] = true
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
			local options: any = if spec.drag
				then spec.drag(items, keys)
				else {
					payload = { collection = collectionId, keys = keys, items = items },
					operations = { "move" },
				}
			if tap and not options.armOnTap then
				return
			end
			local live = pendingInput ~= nil
				and pendingInput.UserInputState ~= E.UserInputState.End
				and pendingInput.UserInputState ~= E.UserInputState.Cancel
			captured = if position and live then pendingInput else nil
			local row = rowNodes[key]
			if captured and captured.UserInputType == E.UserInputType.Touch and row and not releaseScrollers then
				releaseScrollers = scrollLock.holdOwnedAncestors(row)
			end
			recycled = false
			activation.consume(captured)
			local nextMove = {
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
				return if row and row.Parent then row.AbsolutePosition + row.AbsoluteSize / 2 else origin
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
				captured,
				false,
				if original
					then {
						position = if position
							then pickupPosition or position
							else original.AbsolutePosition + original.AbsoluteSize / 2,
						source = original,
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
				and keyboardTarget
				and keyboardTarget.Visible
				and ctx.config.guiService
			then
				ctx.config.guiService.SelectedObject = keyboardTarget
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
		local body = bodyOf()
		local offset = alongBody(body, position) + axis(body.CanvasPosition)
		local across = crossAxis(position - body.AbsolutePosition) / scaleOf(body) + crossAxis(body.CanvasPosition)
		local low, high = 1, #move.rows + 1
		while low < high do
			local middle = math.floor((low + high) / 2)
			local at = assert(controls.placementOf)(middle)
			local crossed = if grid
				then offset >= at.offset + at.size
					or (
						offset >= at.offset
						and offset < at.offset + at.size
						and across >= at.crossOffset + at.crossSize / 2
					)
				else offset >= at.offset + at.size / 2
			if crossed then
				low = middle + 1
			else
				high = middle
			end
		end
		local nextMove, slot = table.clone(move), 0
		for index = 1, low - 1 do
			if not move.included[keyOf(move.rows[index], index)] then
				slot += 1
			end
		end
		nextMove.slot = slot
		nextMove.pointer = position
		moving:set(nextMove)
		drag.update(position)
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
	local selectedObject: ComposeTypes.Readable<unknown>? = if ctx.config.guiService
		then ctx.observe.SelectedObject(ctx.config.guiService)
		else nil
	local pressed: K? = nil
	local pressOrigin: Vector2? = nil
	local pluginGui = ctx.config.inputParent
	if pluginGui and not pluginGui:IsA("PluginGui") then
		pluginGui = nil
	end
	local nativeOrigin: Vector2? = nil
	local pointerOffset = V2.new()
	local function mouseDown(position: Vector2)
		if pluginGui then
			nativeOrigin = position
			pickupPosition = position
			if pendingInput then
				pressOrigin = position
				pointerOffset = position - V2.new(pendingInput.Position.X, pendingInput.Position.Y)
			end
		end
	end
	local moveMouse: (Vector2) -> () = function() end
	local finishMouse: (InputObject) -> () = function() end
	local pressRow: (K, InputObject) -> () = function() end
	local function wrap(row: GuiObject, current: ComposeTypes.Readable<V>, key: K, painted: boolean?): Frame
		rowKeys[row] = key
		local handleNode: Instance? = nil
		local function toggle()
			if moving:peek() then
				commit()
			else
				begin(key)
			end
		end
		local function activate(activation: InputObject?)
			if
				activation
				and (
					activation.UserInputType == E.UserInputType.MouseButton1
					or activation.UserInputType == E.UserInputType.Touch
				)
			then
				return
			end
			toggle()
		end
		local armed = false
		local confirming = Compose.cell(false)
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(controlsShown) and confirming:peek() then
				confirming:set(false)
			end
		end)
		local handle = if reorderable
			then Compose.show(controlsShown, function()
				local handleProps: InputTypes.ButtonProps = {
					Name = "Move",
					Visible = function(use: ComposeTypes.Use)
						return use(controlsShown) and not use(confirming)
					end,
					AnchorPoint = V2.new(1, 0),
					Position = D2.fromScale(1, 0),
					Size = if grid then D2.fromOffset(44, 44) else D2.new(0, 44, 1, 0),
					AutomaticSize = E.AutomaticSize.None,
					appearance = "utility",
					label = "",
					ctx.icon(function(use: ComposeTypes.Use)
						local move = use(moving)
						return if move and move.key == key then "checkmark" elseif grid then "view.grid" else "menu"
					end, {
						Name = "ReorderIcon",
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
					}) :: ComposeTypes.Child,
					enabled = function(use: ComposeTypes.Use)
						return movable(use(current)) and read(sort, use) == nil
					end,
					onActivate = activate,
					ctx.Host.UIDragDetector({
						DragStyle = if grid
							then E.UIDragDetectorDragStyle.TranslatePlane
							else E.UIDragDetectorDragStyle.TranslateLine,
						DragAxis = if horizontal then V2.new(1, 0) else V2.new(0, 1),
						ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
						Enabled = function(use: ComposeTypes.Use)
							local selected = if selectedObject then use(selectedObject) else nil
							local held = preferred ~= nil
								and use(preferred) == E.PreferredInput.Gamepad
								and handleNode ~= nil
								and rawequal(selected, handleNode)
							return movable(use(current)) and read(sort, use) == nil and not held
						end,
						DragStart = function(position)
							position = pointerOf(ctx, position)
							local current = moving:peek()
							origin, travel = position, 0
							pickupPosition = position
							armed = current ~= nil and current.keyboard
							if not armed then
								begin(key, position)
								selectedPickup = moving:peek() ~= nil
									and gui ~= nil
									and handleNode ~= nil
									and rawequal(gui.SelectedObject, handleNode)
							end
						end,
						DragContinue = function(position)
							position = pointerOf(ctx, position)
							if origin then
								travel = math.max(travel, (position - origin).Magnitude)
							end
							if not armed or travel >= TAP then
								movePointer(position)
							end
						end,
						DragEnd = function()
							local tapped = origin ~= nil and travel < TAP
							origin = nil
							if armed then
								armed = false
								commit()
								return
							end
							if tapped then
								cancel()
								toggle()
							else
								commit()
							end
						end,
					}),
				}
				local handle = UI.Button(handleProps)
				handleNode = handle
				if handle then
					ctx.runtime.connect(handle, "InputBegan", function(value: InputObject)
						if
							value.UserInputType == E.UserInputType.MouseButton1
							or value.UserInputType == E.UserInputType.Touch
						then
							pendingInput = value
							local move = moving:peek()
							if move and move.pointer and captured == nil then
								captured = value
								activation.consume(value)
								if value.UserInputType == E.UserInputType.Touch and not releaseScrollers then
									releaseScrollers = scrollLock.holdOwnedAncestors(handle)
								end
							end
						end
					end)
				end
				return handle
			end)
			else nil
		local function deletableRow(use: ComposeTypes.Use): boolean
			local item = use(current)
			return policy.allows(spec.rowDeletable, item) and not policy.disabled(spec.disabled, item)
		end
		local minusProps: InputTypes.ButtonProps = {
			Name = "Minus",
			label = "−",
			name = "Delete",
			shape = "circle" :: "circle",
			role = "destructive" :: InputTypes.ButtonRole,
			AnchorPoint = V2.new(0.5, 0.5),
			Position = if grid then D2.fromOffset(22, 22) else D2.new(0, 22, 0.5, 0),
			Size = D2.fromOffset(28, 28),
			Visible = controlsShown,
			enabled = deletableRow,
			onActivate = function()
				confirming:set(not confirming:peek())
			end,
		}
		local confirmProps: InputTypes.ButtonProps = {
			Name = "Delete",
			label = "Delete",
			role = "destructive" :: InputTypes.ButtonRole,
			AnchorPoint = V2.new(1, 0),
			Position = D2.fromScale(1, 0),
			Size = if grid then D2.fromOffset(88, 44) else D2.new(0, 88, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			Visible = function(use: ComposeTypes.Use)
				return use(controlsShown) and use(confirming)
			end,
			enabled = deletableRow,
			onActivate = function()
				confirming:set(false)
				if spec.onDelete then
					spec.onDelete({ key })
				end
			end,
		}
		local minus = if minusShown then UI.Button(minusProps) else nil
		local confirm = if minusShown then UI.Button(confirmProps) else nil
		local mark = if marked
			then ctx.styled(
				Host.Frame "SelectMark" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = if grid then D2.fromOffset(22, 22) else D2.new(0, 22, 0.5, 0),
					Size = D2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Selectable = false,
					Visible = markShown,
					ctx.corner(if mode == "multiple" then 3 else 9) :: Types.Child,
					(if mode == "multiple"
						then ctx.icon("checkmark", {
							Name = "Check",
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							Size = D2.fromOffset(14, 14),
							Visible = function(use: ComposeTypes.Use)
								return use(selection)[key] == true
							end,
						})
						else ctx.styled(
							Host.Frame "Dot" {
								AnchorPoint = V2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
								Size = D2.fromOffset(8, 8),
								Visible = function(use: ComposeTypes.Use)
									return use(selection)[key] == true
								end,
								ctx.corner(4) :: Types.Child,
							},
							"fill"
						)) :: Types.Child,
				},
				"radio-mark"
			)
			else nil
		local function rightOf(use: ComposeTypes.Use): number
			return if use(confirming) then 88 else use(trailing)
		end
		local edgeSpring = ctx.motionSpring("snappy")
		local left = ctx.runtime.spring(function(use: ComposeTypes.Use)
			return use(leading)
		end, { period = edgeSpring.period, damping = edgeSpring.damping })
		local right = ctx.runtime.spring(rightOf, { period = edgeSpring.period, damping = edgeSpring.damping })
		local function edges(use: ComposeTypes.Use): Vector2
			if motionReduced(use) then
				return V2.new(use(leading), rightOf(use))
			end
			return V2.new(use(left), use(right))
		end
		local nativeProps: Types.FrameProps = {
			Name = "Reorderable",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = if painted then nil else 1,
			Attributes = {
				FacetDragging = function(use: ComposeTypes.Use)
					local move = use(moving)
					return move ~= nil and move.included[key] == true
				end,
			} :: EngineTypes.Attributes,
			Host.Frame "Cells" {
				Visible = function(use: ComposeTypes.Use)
					local move = use(moving)
					return move == nil or not move.included[key]
				end,
				Position = function(use: ComposeTypes.Use)
					return if grid
						then D2.fromOffset(0, use(header))
						else D2.fromOffset(math.floor(edges(use).X + 0.5), 0)
				end,
				Size = function(use: ComposeTypes.Use)
					local at = edges(use)
					return if grid
						then D2.new(1, 0, 1, -use(header))
						else D2.new(1, -math.floor(at.X + at.Y + 0.5), 1, 0)
				end,
				BackgroundTransparency = 1,
				row,
			},
		}
		for _, control in { handle, minus, confirm, mark } :: { ComposeTypes.Child } do
			if control then
				nativeProps[#nativeProps + 1] = control
			end
		end
		local frame = Host.Frame(nativeProps)
		rowNodes[key] = frame
		ctx.runtime.connect(frame, "TouchLongPress", function(positions: { Vector2 }, state: Enum.UserInputState)
			if state ~= E.UserInputState.Begin or touchKey ~= key or moving:peek() ~= nil then
				return
			end
			local position = if pendingInput
				then V2.new(pendingInput.Position.X, pendingInput.Position.Y)
				elseif positions[1] then pointerOf(ctx, positions[1])
				else touchOrigin
			disarm()
			if position then
				begin(key, position)
			end
		end)
		local rowOrigin: Vector2? = nil
		local rowDragged = false
		local function continueRowDrag(position: Vector2)
			if
				rowOrigin
				and not moving:peek()
				and (position - rowOrigin).Magnitude >= 6
				and (
					grid
					or math.abs(axis(position) - axis(rowOrigin))
						> math.abs(crossAxis(position) - crossAxis(rowOrigin))
				)
			then
				rowDragged = true
				if pendingInput == nil or pendingInput.UserInputType ~= E.UserInputType.Touch then
					begin(key, position)
				end
			end
			if moving:peek() then
				movePointer(position)
			end
		end
		local detector = Host.UIDragDetector({
			Name = "FacetCollectionDrag",
			DragStyle = E.UIDragDetectorDragStyle.TranslatePlane,
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use)
				return reorderable
					and movable(use(current))
					and read(sort, use) == nil
					and (
						preferred == nil
						or (use(preferred) ~= E.PreferredInput.Touch and use(preferred) ~= E.PreferredInput.Gamepad)
					)
			end,
			DragStart = function(position)
				position = pointerOf(ctx, position)
				rowOrigin, rowDragged = position, false
				pickupPosition = position
			end,
			DragContinue = function(position)
				continueRowDrag(pointerOf(ctx, position))
			end,
			DragEnd = function(position: Vector2?)
				if position and rowOrigin and not rowDragged then
					continueRowDrag(pointerOf(ctx, position))
				end
				local tapped = rowOrigin ~= nil
					and not rowDragged
					and not moving:peek()
					and pendingInput ~= nil
					and pendingInput.UserInputState ~= E.UserInputState.Cancel
				local tapPosition = rowOrigin
				rowOrigin = nil
				if not tapped then
					lastTap = nil
				end
				if captured == nil and moving:peek() then
					commit()
				elseif tapped and row:IsA("GuiButton") and not activation.consumed(pendingInput) then
					if activation.trigger(row, pendingInput, 0) then
						activation.consume(pendingInput)
					end
				elseif tapped and not activation.consumed(pendingInput) then
					local host = frame.Parent
					local hit = if host then host:FindFirstChild("RowHit") else nil
					if hit then
						local frames = ctx.runtime.host.frames
						local now = if frames then frames.now() else os.clock()
						local previous = lastTap
						local position = tapPosition :: Vector2
						local double = previous ~= nil
							and previous.key == key
							and now - previous.at <= 0.5
							and (position - previous.position).Magnitude <= 6
						lastTap = if double then nil else { key = key, position = position, at = now }
						local target = hit
						local layer = frame:FindFirstAncestorWhichIsA("BasePlayerGui")
						if layer and not double then
							for _, candidate in (layer :: PlayerGui):GetGuiObjectsAtPosition(position.X, position.Y) do
								if candidate.Name == "EditLabel" and candidate:IsDescendantOf(frame) then
									target = candidate
									break
								end
							end
						end
						activation.trigger(target, pendingInput, if double then 2 else 1)
						activation.consume(pendingInput)
					end
				end
			end,
		})
		detector.Parent = row
		Compose.cleanup(activation.provideDrag(frame, function(phase, position)
			if phase == "start" then
				rowOrigin = position
				pickupPosition = position
			elseif phase == "move" and position then
				if
					rowOrigin
					and not moving:peek()
					and (position - rowOrigin).Magnitude >= 6
					and pendingInput
					and pendingInput.UserInputType == E.UserInputType.MouseButton1
					and (
						grid
						or math.abs(axis(position) - axis(rowOrigin))
							> math.abs(crossAxis(position) - crossAxis(rowOrigin))
					)
				then
					begin(key, position)
				end
				if moving:peek() then
					movePointer(position)
					return true
				end
			elseif phase == "end" then
				rowOrigin = nil
				if moving:peek() then
					commit()
					return true
				end
			end
			return false
		end))
		Compose.cleanup(function()
			if rowNodes[key] == frame then
				rowNodes[key] = nil
				local move = moving:peek()
				if move and move.key == key then
					recycled = true
				end
			end
		end)
		ctx.runtime.connect(row, "InputBegan", function(value: InputObject)
			pressRow(key, value)
		end)
		if row:IsA("GuiButton") then
			if pluginGui then
				ctx.runtime.connect(row, "MouseButton1Down", function(x: number, y: number)
					mouseDown(V2.new(x, y))
				end)
				ctx.runtime.connect(row, "InputEnded", function(value: InputObject)
					finishMouse(value)
				end)
			end
		end
		rowKeys[frame] = key
		return frame
	end
	local function press(key: K, value: InputObject): ()
		local at: Vector3? = value.Position
		if not reorderable or at == nil or moving:peek() ~= nil then
			return
		end
		if value.UserInputType == E.UserInputType.MouseButton1 then
			if pluginGui then
				activation.release(value)
			end
			pressed, pressOrigin, pendingInput = key, V2.new(at.X, at.Y), value
			if pluginGui and nativeOrigin then
				pressOrigin = nativeOrigin
				pointerOffset = nativeOrigin - V2.new(at.X, at.Y)
			end
			pickupPosition = pressOrigin
		elseif value.UserInputType == E.UserInputType.Touch and (editing == nil or editing == false) then
			disarm()
			touchKey, touchOrigin, pendingInput = key, V2.new(at.X, at.Y), value
			pickupPosition = touchOrigin
		end
	end
	pressRow = press
	moveMouse = function(position: Vector2)
		if pressed ~= nil and pressOrigin ~= nil and captured == nil then
			if
				(if grid then (position - pressOrigin).Magnitude else math.abs(axis(position) - axis(pressOrigin))) >= 6
			then
				local key = pressed
				pressed, pressOrigin = nil, nil
				begin(key, position)
				activation.consume(pendingInput)
			end
		end
		local move = moving:peek()
		if move and move.pointer and not move.keyboard then
			movePointer(position)
		end
	end
	finishMouse = function(value: InputObject)
		if value.UserInputType ~= E.UserInputType.MouseButton1 then
			return
		end
		if pluginGui and value == pendingInput and value.UserInputState ~= E.UserInputState.Cancel then
			moveMouse(V2.new(value.Position.X, value.Position.Y) + pointerOffset)
		end
		pressed, pressOrigin, nativeOrigin = nil, nil, nil
		pointerOffset = V2.new()
		local move = moving:peek()
		if move and move.pointer and not move.keyboard then
			if value.UserInputState == E.UserInputState.Cancel then
				cancel()
			else
				commit()
			end
		end
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
				local at: Instance? = read(focus, use)
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
	local function overlay(insideBody: boolean?): Frame
		local body = bodyOf()
		local incoming = Compose.cell(nil :: any)
		local destination: any = if spec.drop then table.clone(spec.drop) else {}
		local accept, drop, update = destination.accepts, destination.onDrop, destination.onUpdate
		local noCarried: { K } = {}
		local cachedRows: { V }? = nil
		local cachedCarried: { K }? = nil
		local remaining: { K } = {}
		local rowIndices: { number } = {}
		local remainingIndex: { [K]: number } = {}
		local function insertion(payload: any, info: any)
			local rows: { V } = read(source)
			local same = type(payload) == "table" and payload.collection == collectionId and info.operation == "move"
			local carried = if same then payload.keys or noCarried else noCarried
			if rows ~= cachedRows or carried ~= cachedCarried then
				cachedRows, cachedCarried = rows, carried
				remaining, rowIndices, remainingIndex = {}, {}, {}
				local included: { [K]: boolean } = {}
				for _, key in carried do
					included[key] = true
				end
				for index, item in rows do
					local key = keyOf(item, index)
					if not included[key] then
						table.insert(remaining, key)
						table.insert(rowIndices, index)
						remainingIndex[key] = #remaining
					end
				end
			end
			local slot = 0
			local offset, across = math.huge, math.huge
			if info.position then
				offset = alongBody(body, info.position) + axis(body.CanvasPosition)
				across = crossAxis(info.position - body.AbsolutePosition) / scaleOf(body)
					+ crossAxis(body.CanvasPosition)
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
				local beforeIndex = if before ~= nil then remainingIndex[before] else nil
				local afterIndex = if after ~= nil then remainingIndex[after] else nil
				if (before ~= nil or after ~= nil) and beforeIndex == nil and afterIndex == nil then
					info.invalid = "The insertion neighbors were removed"
					return
				end
				slot = if beforeIndex then beforeIndex - 1 elseif afterIndex then afterIndex else 0
			end
			info.insertion =
				{ collection = collectionId, beforeKey = remaining[slot + 1], afterKey = remaining[slot], slot = slot }
		end
		local function localMove(payload: any, info: any): boolean
			if
				type(payload) ~= "table"
				or payload.collection ~= collectionId
				or not spec.onReorder
				or info.operation ~= "move"
			then
				return false
			end
			if type(payload.keys) ~= "table" or #payload.keys == 0 then
				return false
			end
			local live = sourceIndex:peek()
			for _, key in payload.keys do
				if live[key] == nil then
					return false
				end
			end
			return true
		end
		destination.propose = insertion
		destination.accepts = function(payload, info): (boolean, string?)
			if info.invalid then
				return false, info.invalid
			end
			if read(sort) ~= nil then
				return false, "Clear sorting before inserting items"
			end
			if localMove(payload, info) then
				if location then
					local accepted = location(payload.keys, info.insertion.slot)
					return accepted, if accepted then nil else "Move items within the same folder"
				end
				return true, nil
			end
			if accept then
				return accept(payload, info)
			end
			return drop ~= nil, "This collection does not accept these items"
		end
		destination.onDrop = function(payload, info)
			if localMove(payload, info) then
				commitLocal(payload.keys, info.insertion.slot)
				return true
			end
			return if drop then drop(payload, info) else false
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
			if move and not move.keyboard and accepted and move.slot ~= info.insertion.slot then
				local next = table.clone(move)
				next.slot = info.insertion.slot
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
		local canvasAt, bodyAt = ctx.observe.CanvasPosition(body), ctx.observe.Position(body)
		local function dragImage(dropY: (ComposeTypes.Use) -> number): (Frame, number, UDim2)
			local move = assert(moving:peek())
			local source = rowNodes[move.key]
			local index = assert(controls.indexOfKey)(move.key)
			local placement = if index then assert(controls.placementOf)(index) else nil
			local extent = if placement then placement.size else 0
			local nativeSize = if source then source.AbsoluteSize / scaleOf(body) else V2.zero
			local crossSize = if crossAxis(nativeSize) > 0
				then crossAxis(nativeSize)
				elseif placement then placement.crossSize
				else 0
			local previewKeys = { move.key }
			for _, key in move.keys do
				if key ~= move.key then
					table.insert(previewKeys, key)
				end
			end
			local layers = math.min(3, #move.keys)
			local stack = STACK * (layers - 1)
			local function sized(inset: number): UDim2
				return if grid
					then (if horizontal then D2.fromOffset(extent, crossSize) else D2.fromOffset(crossSize, extent))
					elseif horizontal then D2.new(0, extent, 1, -inset)
					else D2.new(1, -inset, 0, extent)
			end
			local imageProps: Types.FrameProps = {
				Name = "DragImage",
				ZIndex = FEEDBACK_Z + 1,
				BackgroundTransparency = 1,
				Interactable = false,
				Size = if grid
					then (if horizontal
						then D2.fromOffset(extent + stack, crossSize + stack)
						else D2.fromOffset(crossSize + stack, extent + stack))
					elseif horizontal then D2.new(0, extent + stack, 1, 0)
					else D2.new(1, 0, 0, extent + stack),
				Position = function(use: ComposeTypes.Use)
					local live = use(moving)
					local base = if horizontal then use(bodyAt).X.Offset else use(bodyAt).Y.Offset
					local window = axis(body.AbsoluteWindowSize) / scaleOf(body)
					local along = if live and live.pointer
						then math.clamp(
							alongBody(body, live.pointer) + base - extent / 2,
							base,
							math.max(base, base + window - extent - stack)
						)
						else dropY(use)
					local across = 0
					if grid then
						local pointer = if live and live.pointer
							then crossAxis(live.pointer - body.AbsolutePosition) / scaleOf(body) - crossSize / 2
							else (if placement then placement.crossOffset else 0)
						if live and live.keyboard then
							local candidate = live.remaining[live.slot + 1]
							local index = if candidate then assert(controls.indexOfKey)(candidate) else #live.rows
							local at = assert(controls.placementOf)(index or 1)
							pointer = at.crossOffset
								+ (if candidate then 0 else at.crossSize)
								- crossAxis(use(canvasAt))
						end
						across = math.clamp(
							pointer,
							0,
							math.max(0, crossAxis(body.AbsoluteWindowSize) / scaleOf(body) - crossSize - stack)
						)
					end
					return if horizontal then D2.fromOffset(along, across) else D2.fromOffset(across, along)
				end,
				ctx.styled(
					ctx.text({
						Name = "DragLabel",
						ZIndex = FEEDBACK_Z + 2,
						BackgroundTransparency = 0,
						AnchorPoint = V2.new(1, 0),
						Position = D2.fromScale(1, 0),
						Visible = #move.keys > 1,
						Text = function(use: ComposeTypes.Use)
							local live = use(moving)
							if live == nil then
								return ""
							end
							if #live.keys > 1 then
								return tostring(#live.keys) .. " selected"
							end
							local index = assert(controls.indexOfKey)(live.key)
							return if spec.dragLabel and index
								then spec.dragLabel(live.rows[index])
								else tostring(live.key)
						end,
					}),
					"badge"
				),
			}
			local image = Host.Frame(imageProps)
			local top = FEEDBACK_Z + 1
			for layer = layers, 1, -1 do
				local original = rowNodes[previewKeys[layer]] or source
				local parent = if original then original.Parent else nil
				local painted = if parent
						and parent:IsA("Frame")
						and parent:HasTag("facet-tablerow")
					then parent
					else original
				local copy = if painted then painted:Clone() else nil
				if copy then
					local cells = copy:FindFirstChild("Cells", true)
					if cells and cells:IsA("GuiObject") then
						cells.Visible = true
					end
					local row = if copy.Name == "Reorderable" then copy else copy:FindFirstChild("Reorderable", true)
					if row then
						for _, name in { "Move", "SelectMark", "Minus", "Confirm" } do
							local control = row:FindFirstChild(name)
							if control and control:IsA("GuiObject") then
								control.Visible = false
							end
						end
					end
					for _, node in copy:GetDescendants() do
						if node:GetAttribute("FacetDragExclude") == true then
							node:Destroy()
						end
					end
					local nodes = copy:GetDescendants()
					table.insert(nodes, copy)
					local base = top
					for _, node in nodes do
						local rest = node:GetAttribute("FacetDragRestX")
						if type(rest) == "number" and node:IsA("GuiObject") then
							node.Position =
								D2.new(node.Position.X.Scale, rest, node.Position.Y.Scale, node.Position.Y.Offset)
						end
						if node:IsA("GuiObject") then
							node.Interactable, node.Active, node.Selectable = false, false, false
							node.ZIndex += base
							top = math.max(top, node.ZIndex)
						elseif node:IsA("Path2D") then
							node.ZIndex += base
							top = math.max(top, node.ZIndex)
						elseif node:IsA("UIDragDetector") or node:IsA("InputContext") then
							(node :: any).Enabled = false
						end
					end
					copy.Name = "Reorderable"
					copy.AnchorPoint = V2.zero
					copy.Position = D2.fromOffset(STACK * (layer - 1), STACK * (layer - 1))
					copy.Size = sized(stack)
					copy.ZIndex = base + 1
					copy.Parent = image
				end
			end
			(image:FindFirstChild("DragLabel") :: GuiObject).ZIndex = top + 1
			return image, top + 2, sized(stack)
		end
		if pluginGui then
			ctx.runtime.connect(body, "MouseMoved", function(x: number, y: number)
				moveMouse(V2.new(x, y))
			end)
			ctx.runtime.connect(pluginGui, "WindowFocusReleased", function()
				pressed, pressOrigin = nil, nil
				cancel()
			end)
		end
		if input then
			ctx.runtime.connect(input, "InputBegan", activation.release)
			ctx.runtime.connect(input, "InputChanged", function(value: InputObject)
				if touchOrigin and value == pendingInput then
					local position = V2.new(value.Position.X, value.Position.Y)
					if (position - touchOrigin).Magnitude > SLOP then
						disarm()
					end
					return
				end
				if
					pluginGui ~= nil
					and pressed ~= nil
					and pressOrigin ~= nil
					and captured == nil
					and value.UserInputType == E.UserInputType.MouseMovement
				then
					local position = V2.new(value.Position.X, value.Position.Y)
					if
						(
							if grid
								then (position - pressOrigin).Magnitude
								else math.abs(axis(position) - axis(pressOrigin))
						) >= 6
					then
						local key = pressed
						pressed, pressOrigin = nil, nil
						begin(key, position)
						movePointer(position)
					end
					return
				end
				if
					captured
					and (pluginGui ~= nil or recycled or selectedPickup or captured.UserInputType == E.UserInputType.Touch)
					and (
						value == captured
						or (
							captured.UserInputType == E.UserInputType.MouseButton1
							and value.UserInputType == E.UserInputType.MouseMovement
						)
					)
				then
					if value.UserInputState == E.UserInputState.Cancel then
						cancel()
					else
						local position = V2.new(value.Position.X, value.Position.Y)
						if origin then
							travel = math.max(travel, (position - origin).Magnitude)
						end
						movePointer(position)
					end
				end
			end)
			ctx.runtime.connect(input, "InputEnded", function(value: InputObject)
				if value.UserInputType == E.UserInputType.MouseButton1 then
					pressed, pressOrigin = nil, nil
				end
				if touchOrigin and value == pendingInput then
					disarm()
				end
				if
					captured
					and (
						value == captured
						or (
							captured.UserInputType == E.UserInputType.MouseButton1
							and value.UserInputType == E.UserInputType.MouseButton1
						)
					)
				then
					if value.UserInputState == E.UserInputState.Cancel then
						cancel()
					else
						commit()
					end
				end
			end)
			ctx.runtime.connect(input, "WindowFocusReleased", cancel)
			local touch, mouse, keyboard, gamepad =
				ctx.observe.TouchEnabled(input),
				ctx.observe.MouseEnabled(input),
				ctx.observe.KeyboardEnabled(input),
				ctx.observe.GamepadEnabled(input)
			Compose.watch(function(use: ComposeTypes.Use)
				local move = use(moving)
				if
					move
					and (
						(captured and captured.UserInputType == E.UserInputType.Touch and use(touch) == false)
						or (captured and captured.UserInputType == E.UserInputType.MouseButton1 and use(mouse) == false)
						or (
							move.keyboard
							and use(keyboard) == false
							and use(gamepad) == false
							and (not move.tap or use(touch) == false)
						)
					)
				then
					cancel()
				end
			end)
		end

		local rootProps: Types.FrameProps = {
			Name = "ReorderFeedback",
			ZIndex = FEEDBACK_Z,
			Position = function(use: ComposeTypes.Use)
				return if insideBody then D2.fromOffset(use(canvasAt).X, use(canvasAt).Y) else D2.fromOffset(0, 0)
			end,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Attributes = { FacetDragFeedback = true } :: EngineTypes.Attributes,
			Compose.show(function(use)
				return use(incoming) ~= nil
			end, function()
				local function placement(use: ComposeTypes.Use)
					local proposal = use(incoming)
					local rows = read(source, use)
					if #rows == 0 then
						return { offset = 0, size = 44, crossOffset = 0, crossSize = 44 }, true
					end
					local key = proposal and proposal.beforeKey
					local index = if key ~= nil then assert(controls.indexOfKey)(key) else #rows
					return assert(controls.placementOf)(index or #rows), key ~= nil
				end
				return ctx.styled(
					Host.Frame {
						Name = "InsertionLine",
						BorderSizePixel = 0,
						ZIndex = FEEDBACK_Z,
						Size = function(use)
							local at = placement(use)
							return if grid
								then (if horizontal then D2.fromOffset(at.size, 2) else D2.fromOffset(2, at.size))
								elseif horizontal then D2.new(0, 2, 1, 0)
								else D2.new(1, 0, 0, 2)
						end,
						Position = function(use)
							local at, before = placement(use)
							local offset = if insideBody
								then V2.zero
								else V2.new(use(bodyAt).X.Offset, use(bodyAt).Y.Offset)
							local along = at.offset
								+ (if not grid and not before then at.size else 0)
								- axis(use(canvasAt))
							local across = if grid
								then at.crossOffset + (if before then 0 else at.crossSize) - crossAxis(use(canvasAt))
								else 0
							return D2.fromOffset(
								offset.X + (if horizontal then along else across),
								offset.Y + (if horizontal then across else along)
							)
						end,
					},
					"drop-line"
				)
			end),
			Compose.show(function(use: ComposeTypes.Use)
				return use(moving) ~= nil
			end, function()
				local function dropY(use: ComposeTypes.Use): number
					local move = use(moving)
					if move == nil then
						return 0
					end
					local candidate = move.remaining[move.slot + 1]
					local index = if candidate then assert(controls.indexOfKey)(candidate) else #move.rows
					local at = assert(controls.placementOf)(index or 1)
					return (if insideBody then 0 elseif horizontal then use(bodyAt).X.Offset else use(bodyAt).Y.Offset)
						+ at.offset
						+ (if candidate then 0 else at.size)
						- axis(use(canvasAt))
				end
				local image, targetZ, frontSize = dragImage(dropY)
				drag.preview(image, body, frontSize)
				image.Visible = false
				local keyboardTargetProps: InputTypes.ButtonProps = {
					Name = "Drop",
					label = "Drop",
					Position = D2.new(1, -100, 0, 0),
					Size = D2.fromOffset(100, 40),
					ZIndex = targetZ,
					Visible = function(use: ComposeTypes.Use)
						local move = use(moving)
						return move ~= nil
							and move.keyboard
							and not use(choosingDestination)
							and (spec.onReorder ~= nil or spec.drop ~= nil)
					end,
					onActivate = commit,
				}
				keyboardTarget = UI.Button(keyboardTargetProps)
				local nativeProps: Types.FrameProps = {
					Name = "DropFeedback",
					ZIndex = FEEDBACK_Z,
					keyboardTarget :: ComposeTypes.Child,
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ctx.styled(
						Host.Frame "DropLine" {
							Visible = function(use)
								local session = use(drag.state)
								local move = use(moving)
								return (spec.onReorder ~= nil or spec.drop ~= nil)
									and session ~= nil
									and (
										(move and move.keyboard and not use(choosingDestination))
										or (
											session.target == body
											and body:GetAttribute("FacetDropState") == "accepted"
										)
									)
							end,
							Size = function(use: ComposeTypes.Use): UDim2
								local move = use(moving)
								if grid and move then
									local candidate = move.remaining[move.slot + 1]
									local index = if candidate
										then assert(controls.indexOfKey)(candidate)
										else #move.rows
									local at = assert(controls.placementOf)(index or 1)
									return if horizontal then D2.fromOffset(at.size, 2) else D2.fromOffset(2, at.size)
								end
								return if horizontal then D2.new(0, 2, 1, 0) else D2.new(1, 0, 0, 2)
							end,
							BorderSizePixel = 0,
							ZIndex = FEEDBACK_Z,
							Position = function(use: ComposeTypes.Use)
								local move = use(moving)
								if grid and move then
									local candidate = move.remaining[move.slot + 1]
									local index = if candidate
										then assert(controls.indexOfKey)(candidate)
										else #move.rows
									local at = assert(controls.placementOf)(index or 1)
									local along = at.offset - axis(use(canvasAt))
									local across = at.crossOffset
										+ (if candidate then 0 else at.crossSize)
										- crossAxis(use(canvasAt))
									return if horizontal
										then D2.fromOffset(along, across)
										else D2.fromOffset(across, along)
								end
								return if horizontal then D2.fromOffset(dropY(use), 0) else D2.fromOffset(0, dropY(use))
							end,
						},
						"divider"
					),
					image,
				}
				return Host.Frame(nativeProps)
			end),
		}
		local root = Host.Frame(rootProps)
		local function keyboardActive(use: ComposeTypes.Use): boolean
			local move = use(moving)
			local node = use(focus)
			return (spec.onReorder ~= nil or spec.drop ~= nil)
				and move ~= nil
				and move.keyboard
				and not use(choosingDestination)
				and (node == nil or node == keyboardTarget or node:IsDescendantOf(body))
		end
		if spec.drag then
			local function focusedKey(use: ComposeTypes.Use?): K?
				local node = if use then use(focus) else focus:peek()
				if not node then
					return nil
				end
				for key, frame in rowNodes do
					if frame.Parent and node:IsDescendantOf(frame.Parent) then
						return key
					end
				end
				return nil
			end
			ctx.action(root, "CollectionPickUp", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
				return use(moving) == nil and use(drag.state) == nil and focusedKey(use) ~= nil
			end, function()
				local key = focusedKey(nil)
				if key ~= nil then
					begin(key)
				end
			end, { priority = 400 })
		end
		if spec.drag and (spec.onReorder or spec.drop) then
			ctx.action(root, "ChooseDropDestination", { E.KeyCode.ButtonY }, function(use)
				local move = use(moving)
				local session = use(drag.state)
				return move ~= nil and move.keyboard and session ~= nil and not session.pending
			end, function()
				choosingDestination:set(not choosingDestination:peek())
				if gui then
					local move = moving:peek()
					local row = move and rowNodes[move.key]
					local hit = row and row.Parent and row.Parent:FindFirstChild("RowHit")
					gui.SelectedObject = if choosingDestination:peek()
							and hit
							and hit:IsA("GuiObject")
						then hit
						else keyboardTarget
				end
				local session = drag.state:peek()
				if session then
					session.spec.navigationHint = if choosingDestination:peek()
						then "Y: reorder here"
						else "Y: choose destination"
					drag.hover(drag.targetOf(focus:peek()), nil)
				end
			end, { priority = 400 })
		end
		local earlier = if horizontal
			then { E.KeyCode.Left, E.KeyCode.DPadLeft }
			else { E.KeyCode.Up, E.KeyCode.DPadUp }
		local later = if horizontal
			then { E.KeyCode.Right, E.KeyCode.DPadRight }
			else { E.KeyCode.Down, E.KeyCode.DPadDown }
		ctx.action(root, "ReorderUp", earlier, keyboardActive, function()
			step(-1, true)
		end, { priority = 400, capture = true })
		ctx.action(root, "ReorderDown", later, keyboardActive, function()
			step(1, true)
		end, { priority = 400, capture = true })
		if grid then
			ctx.action(
				root,
				"ReorderCrossEarlier",
				if horizontal then { E.KeyCode.Up, E.KeyCode.DPadUp } else { E.KeyCode.Left, E.KeyCode.DPadLeft },
				keyboardActive,
				function()
					step(-1)
				end,
				{ priority = 400, capture = true }
			)
			ctx.action(
				root,
				"ReorderCrossLater",
				if horizontal then { E.KeyCode.Down, E.KeyCode.DPadDown } else { E.KeyCode.Right, E.KeyCode.DPadRight },
				keyboardActive,
				function()
					step(1)
				end,
				{ priority = 400, capture = true }
			)
		end
		ctx.action(root, "ReorderCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			return use(moving) ~= nil
		end, cancel, { priority = 400 })
		ctx.action(root, "ReorderDrop", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
			local move = use(moving)
			return move ~= nil
				and move.keyboard
				and not use(choosingDestination)
				and (spec.onReorder ~= nil or spec.drop ~= nil)
		end, commit, { priority = 400 })
		if reorderable then
			local function nudge(delta: number)
				local keys = chosen()
				if #keys > 0 then
					begin(keys[1], nil, true)
					step(delta)
					commit()
				end
			end
			local function ready(use: ComposeTypes.Use): boolean
				return use(moving) == nil and #chosen(use) > 0
			end
			ctx.action(root, "MoveRowsEarlier", { E.KeyCode.ButtonL1 }, ready, function()
				nudge(-1)
			end, { priority = 400 })
			ctx.action(root, "MoveRowsLater", { E.KeyCode.ButtonR1 }, ready, function()
				nudge(1)
			end, { priority = 400 })
		end
		if deletable then
			ctx.action(
				root,
				"DeleteRows",
				{ E.KeyCode.Delete, E.KeyCode.Backspace, E.KeyCode.ButtonX },
				canDelete,
				function()
					remove(false)
				end,
				{ priority = 400 }
			)
		end
		return root
	end
	return {
		pickUp = function(key: K, input: InputObject?): boolean
			if not spec.drag or input == nil or input.UserInputType == E.UserInputType.MouseButton1 then
				return false
			end
			if moving:peek() == nil then
				begin(key, nil, nil, input.UserInputType == E.UserInputType.Touch)
			end
			return moving:peek() ~= nil
		end,
		wrap = wrap,
		overlay = overlay,
		leading = leading,
		trailing = trailing,
		header = header,
		press = press,
		mouseDown = mouseDown,
		finish = finishMouse,
		busy = function(): boolean
			return moving:peek() ~= nil
		end,
		deleteSelected = function()
			remove(true)
		end,
		canDeleteSelected = canDeleteSelected,
	}
end
