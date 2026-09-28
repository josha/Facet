--!strict
local policy = require("./collection_policy")
local activation = require("./activation")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local reducedMotion = require("./motion").reduced
export type Editor<V, K> = {
	wrap: (GuiObject, ComposeTypes.Readable<V>, K, boolean?) -> Frame,
	overlay: (boolean?) -> Frame,
	leading: ComposeTypes.Readable<number>,
	trailing: ComposeTypes.Readable<number>,
	press: (K, InputObject) -> (),
	busy: () -> boolean,
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
	editing: Types.ValueBoolean?
): Editor<V, K>
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local moving: ComposeTypes.Cell<Move<V, K>?> = Compose.cell(nil :: Move<V, K>?)
	local TAP = 3
	local STACK = 6
	local HOLD = 0.35
	local SLOP = 10
	local reorderable = spec.reorderable == true
	local deletable = spec.deletable == true
	local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if ctx.config.userInputService
		then ctx.observe.PreferredInput(ctx.config.userInputService)
		else nil
	local controlsShown = Compose.formula(function(use: ComposeTypes.Use): boolean
		local kind = if preferred then use(preferred) else nil
		return kind == nil or read(editing, use) == true
	end)

	local marked = spec.selectionMode == "multiple"
		or (spec.selectionMode ~= nil and spec.selectionMode ~= "none" and not deletable)
	local minusShown = deletable and not marked
	local markShown = Compose.formula(function(use: ComposeTypes.Use): boolean
		return marked and read(editing, use) == true
	end)
	local leading = Compose.formula(function(use: ComposeTypes.Use): number
		return if (minusShown and use(controlsShown)) or use(markShown) then 44 else 0
	end)
	local trailing = Compose.formula(function(use: ComposeTypes.Use): number
		return if reorderable and use(controlsShown) then 44 else 0
	end)
	local motionReduced = reducedMotion(ctx)
	local horizontal = spec.direction == "horizontal"
	local function axis(position: Vector2): number
		return if horizontal then position.X else position.Y
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
	local pendingInput: InputObject?
	local origin: Vector2? = nil
	local travel = 0
	local keyboardTarget: TextButton?
	local rowKeys: { [Instance]: K } = setmetatable({}, { __mode = "k" }) :: any
	local gui = ctx.config.guiService
	local focus: ComposeTypes.Readable<GuiObject?> = if gui and gui.GetPropertyChangedSignal
		then ctx.observe.SelectedObject(gui)
		else Compose.cell(nil :: GuiObject?)
	local stopFrames: ComposeTypes.Dispose?
	local startFrames: (() -> ())?
	local frames = assert(ctx.runtime.host.frames)
	local touchKey: K? = nil
	local touchOrigin: Vector2? = nil
	local stopHold: ComposeTypes.Dispose? = nil
	local scrollLocked: ScrollingFrame? = nil
	local function disarm()
		touchKey, touchOrigin = nil, nil
		if stopHold then
			stopHold()
			stopHold = nil
		end
	end
	local function cancel()
		captured = nil
		disarm()
		if stopFrames then
			stopFrames()
			stopFrames = nil
		end
		if scrollLocked then
			scrollLocked.ScrollingEnabled = true
			scrollLocked = nil
		end
		moving:set(nil)
	end
	Compose.cleanup(disarm)
	local function movable(item: V): boolean
		return policy.allows(spec.movable, item) and not policy.disabled(spec.disabled, item)
	end
	local function begin(key: K, position: Vector2?, quiet: boolean?): ()
		if
			not reorderable
			or read(sort) ~= nil
			or not spec.onReorder
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
		local remaining: { K } = {}
		local before = 0
		local started = false
		for index, item in rows do
			local candidate = keyOf(item, index)
			if movable(item) and (candidate == key or (selected[key] and selected[candidate])) then
				started = true
				table.insert(keys, candidate)
				indices[candidate] = true
			else
				table.insert(remaining, candidate)
				if not started then
					before += 1
				end
			end
		end
		if #keys > 0 then
			local live = pendingInput ~= nil
				and pendingInput.UserInputState ~= E.UserInputState.End
				and pendingInput.UserInputState ~= E.UserInputState.Cancel
			captured = if position and live then pendingInput else nil
			activation.consume(captured)
			moving:set({
				key = key,
				keys = keys,
				included = indices,
				remaining = remaining,
				slot = before,
				rows = rows,
				pointer = position,
				keyboard = position == nil,
			})
			if position and captured and startFrames then
				startFrames()
			end
			if position == nil and not quiet and keyboardTarget and ctx.config.guiService then
				ctx.config.guiService.SelectedObject = keyboardTarget
			end
		end
	end
	local function commit()
		local move = moving:peek()
		cancel()
		if move == nil or move.rows ~= read(source) then
			return
		end
		local reordered = table.clone(move.remaining)
		for index, key in move.keys do
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
	local function movePointer(position: Vector2): ()
		local move = moving:peek()
		if move == nil then
			return
		end
		local body = bodyOf()
		local offset = alongBody(body, position) + axis(body.CanvasPosition)
		local low, high = 1, #move.rows + 1
		while low < high do
			local middle = math.floor((low + high) / 2)
			local at = assert(controls.placementOf)(middle)
			if offset >= at.offset + at.size / 2 then
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
	end
	local function step(delta: number): ()
		local current = moving:peek()
		if current then
			local nextMove = table.clone(current)
			nextMove.slot = math.clamp(current.slot + delta, 0, #current.remaining)
			moving:set(nextMove)
			local body = bodyOf()
			local at = current.remaining[math.clamp(nextMove.slot + 1, 1, #current.remaining)]
			local index = if at then assert(controls.indexOfKey)(at) else nil
			if index then
				canvasOffset(
					body,
					assert(controls.offsetOf)(index, "center", axis(body.AbsoluteWindowSize) / scaleOf(body))
				)
			end
		end
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local rows, order = read(source, use), read(sort, use)
		local move = moving:peek()
		if move and (move.rows ~= rows or order ~= nil) then
			cancel()
		end
	end)
	local rowNodes: { [K]: Frame } = {}
	local selectedObject: ComposeTypes.Readable<unknown>? = if ctx.config.guiService
		then ctx.observe.SelectedObject(ctx.config.guiService)
		else nil
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
		local handleProps: InputTypes.ButtonProps = {
			Name = "Move",
			Visible = function(use: ComposeTypes.Use)
				return use(controlsShown) and not use(confirming)
			end,
			AnchorPoint = V2.new(1, 0),
			Position = D2.fromScale(1, 0),
			Size = D2.new(0, 44, 1, 0),
			AutomaticSize = E.AutomaticSize.None,
			appearance = "utility",
			label = "",
			ctx.icon(function(use: ComposeTypes.Use)
				local move = use(moving)
				return if move and move.key == key then "checkmark" else "menu"
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
				DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
				DragAxis = if horizontal then V2.new(1, 0) else V2.new(0, 1),
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				Enabled = function(use: ComposeTypes.Use)
					local selected = if selectedObject then use(selectedObject) else nil
					local held = handleNode ~= nil and rawequal(selected, handleNode)
					return movable(use(current)) and read(sort, use) == nil and not held
				end,
				DragStart = function(position)
					local current = moving:peek()
					origin, travel = position, 0
					armed = current ~= nil and current.keyboard
					if not armed then
						begin(key, position)
					end
				end,
				DragContinue = function(position)
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
		local handle = if reorderable then UI.Button(handleProps) else nil
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
						if startFrames then
							startFrames()
						end
					end
				end
			end)
		end
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
			Position = D2.new(0, 22, 0.5, 0),
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
			Size = D2.new(0, 88, 1, 0),
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
					Position = D2.new(0, 22, 0.5, 0),
					Size = D2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Selectable = false,
					Visible = markShown,
					ctx.corner(9) :: Types.Child,
					ctx.styled(
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
					) :: Types.Child,
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
				Position = function(use: ComposeTypes.Use)
					return D2.fromOffset(math.floor(edges(use).X + 0.5), 0)
				end,
				Size = function(use: ComposeTypes.Use)
					local at = edges(use)
					return D2.new(1, -math.floor(at.X + at.Y + 0.5), 1, 0)
				end,
				BackgroundTransparency = 1,
				row,
			},
		}
		for _, control in { handle, minus, confirm, mark } :: { GuiObject? } do
			if control then
				table.insert(nativeProps, control)
			end
		end
		local frame = Host.Frame(nativeProps)
		rowNodes[key] = frame
		Compose.cleanup(function()
			if rowNodes[key] == frame then
				rowNodes[key] = nil
			end
		end)
		if row:IsA("GuiButton") then
			ctx.runtime.connect(row, "InputBegan", function(value: InputObject)
				pressRow(key, value)
			end)
		end
		rowKeys[frame] = key
		return frame
	end
	local pressed: K? = nil
	local pressOrigin: Vector2? = nil
	local function press(key: K, value: InputObject): ()
		local at: Vector3? = value.Position
		if not reorderable or at == nil or moving:peek() ~= nil then
			return
		end
		if value.UserInputType == E.UserInputType.MouseButton1 then
			pressed, pressOrigin, pendingInput = key, V2.new(at.X, at.Y), value
		elseif value.UserInputType == E.UserInputType.Touch and (editing == nil or editing == false) then
			disarm()
			touchKey, touchOrigin, pendingInput = key, V2.new(at.X, at.Y), value
			local elapsed = 0
			stopHold = frames.onFrame(function(step: number)
				elapsed += step
				if elapsed < HOLD then
					return
				end
				local armedKey, origin = touchKey, touchOrigin
				disarm()
				if armedKey ~= nil and origin ~= nil then
					begin(armedKey, origin)
					if moving:peek() then
						local body = bodyOf()
						if body.ScrollingEnabled then
							scrollLocked = body
							body.ScrollingEnabled = false
						end
					end
				end
			end)
		end
	end
	pressRow = press
	local function chosen(use: ComposeTypes.Use?, selectedOnly: boolean?): { K }
		local keys, selected = {}, read(selection, use)
		for index, item in read(source, use) do
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
			return deletable and (if use then use(moving) else moving:peek()) == nil and #chosen(use, selectedOnly) > 0
		end
	end
	local canDelete, canDeleteSelected = deletes(false), deletes(true)
	local function remove(selectedOnly: boolean?): ()
		local keys = {}
		for _, key in chosen(nil, selectedOnly) do
			for index, item in read(source) do
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
		local canvasAt, bodyAt = ctx.observe.CanvasPosition(body), ctx.observe.Position(body)
		local function dragImage(dropY: (ComposeTypes.Use) -> number): Frame
			local move = assert(moving:peek())
			local source = rowNodes[move.key]
			local index = assert(controls.indexOfKey)(move.key)
			local extent = if index then assert(controls.placementOf)(index).size else 0
			local layers = math.min(3, #move.keys)
			local stack = STACK * (layers - 1)
			local function sized(inset: number): UDim2
				return if horizontal then D2.new(0, extent, 1, -inset) else D2.new(1, -inset, 0, extent)
			end
			local imageProps: Types.FrameProps = {
				Name = "DragImage",
				ZIndex = 9,
				BackgroundTransparency = 1,
				Interactable = false,
				Size = if horizontal then D2.new(0, extent + stack, 1, 0) else D2.new(1, 0, 0, extent + stack),
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
					return if horizontal then D2.fromOffset(along, 0) else D2.fromOffset(0, along)
				end,
				ctx.styled(
					ctx.text({
						Name = "DragLabel",
						ZIndex = 4,
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
			for layer = layers, 1, -1 do
				local copy = if source then source:Clone() else nil
				if copy then
					for _, node in copy:GetDescendants() do
						if node:GetAttribute("FacetDragExclude") == true then
							node:Destroy()
						end
					end
					local nodes = copy:GetDescendants()
					table.insert(nodes, copy)
					for _, node in nodes do
						local rest = node:GetAttribute("FacetDragRestX")
						if type(rest) == "number" and node:IsA("GuiObject") then
							node.Position =
								D2.new(node.Position.X.Scale, rest, node.Position.Y.Scale, node.Position.Y.Offset)
						end
						if node:IsA("GuiObject") then
							node.Interactable, node.Active, node.Selectable = false, false, false
						elseif node:IsA("UIDragDetector") or node:IsA("InputContext") then
							(node :: any).Enabled = false
						end
					end
					copy.AnchorPoint = V2.zero
					copy.Position = D2.fromOffset(STACK * (layer - 1), STACK * (layer - 1))
					copy.Size = sized(stack)
					copy.ZIndex = layers - layer + 1
					copy.Parent = image
				end
			end
			return image
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
					pressed ~= nil
					and pressOrigin ~= nil
					and captured == nil
					and value.UserInputType == E.UserInputType.MouseMovement
				then
					local position = V2.new(value.Position.X, value.Position.Y)
					if math.abs(axis(position) - axis(pressOrigin)) >= 6 then
						local key = pressed
						pressed, pressOrigin = nil, nil
						begin(key, position)
						movePointer(position)
					end
					return
				end
				if
					captured
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
						or (move.keyboard and use(keyboard) == false and use(gamepad) == false)
					)
				then
					cancel()
				end
			end)
		end
		startFrames = function()
			if stopFrames or spec.autoscroll == false then
				return
			end

			stopFrames = assert(ctx.runtime.host.frames).onFrame(function(delta)
				local move = moving:peek()
				if move == nil or move.pointer == nil or not captured then
					return
				end
				local scale = scaleOf(body)
				local scroller: Instance? = body
				while scroller do
					if scroller:IsA("ScrollingFrame") and scroller.ScrollingEnabled then
						local size = axis(scroller.AbsoluteWindowSize) / scale
						local edge = math.min(40, size / 4)
						local at = (axis(move.pointer) - axis(scroller.AbsolutePosition)) / scale
						local inner = scroller == body
						local speed = if edge <= 0 or (not inner and (at < 0 or at > size))
							then 0
							elseif at < edge then -math.clamp((edge - at) / edge, 0, 1)
							elseif at > size - edge then math.clamp((at - size + edge) / edge, 0, 1)
							else 0
						local last = if inner then assert(controls.placementOf)(#move.rows) else nil
						local limit = if last
							then last.offset + last.size - size
							else axis(scroller.AbsoluteCanvasSize) / scale - size
						local now = axis(scroller.CanvasPosition)
						local target = math.clamp(now + speed * 600 * delta, 0, math.max(0, limit))
						if target ~= now then
							canvasOffset(scroller, target)
							movePointer(move.pointer)
							return
						end
					end
					scroller = scroller.Parent
				end
			end)
		end
		Compose.cleanup(function()
			if stopFrames then
				stopFrames()
			end
		end)
		local rootProps: Types.FrameProps = {
			Name = "ReorderFeedback",
			Position = function(use: ComposeTypes.Use)
				return if insideBody then D2.fromOffset(use(canvasAt).X, use(canvasAt).Y) else D2.fromOffset(0, 0)
			end,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
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
				local keyboardTargetProps: InputTypes.ButtonProps = {
					Name = "Drop",
					label = "Drop",
					Position = D2.new(1, -100, 0, 0),
					Size = D2.fromOffset(100, 40),
					ZIndex = 10,
					Visible = function(use: ComposeTypes.Use)
						local move = use(moving)
						return move ~= nil and move.keyboard
					end,
					onActivate = commit,
				}
				keyboardTarget = UI.Button(keyboardTargetProps)
				local nativeProps: Types.FrameProps = {
					Name = "DropFeedback",
					keyboardTarget :: ComposeTypes.Child,
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ctx.styled(
						Host.Frame "DropLine" {
							Size = if horizontal then D2.new(0, 2, 1, 0) else D2.new(1, 0, 0, 2),
							BorderSizePixel = 0,
							ZIndex = 8,
							Position = function(use: ComposeTypes.Use)
								return if horizontal then D2.fromOffset(dropY(use), 0) else D2.fromOffset(0, dropY(use))
							end,
						},
						"divider"
					),
					dragImage(dropY),
				}
				return Host.Frame(nativeProps)
			end),
		}
		local root = Host.Frame(rootProps)
		local function keyboardActive(use: ComposeTypes.Use): boolean
			local move = use(moving)
			return move ~= nil and move.keyboard
		end
		local earlier = if horizontal
			then { E.KeyCode.Left, E.KeyCode.DPadLeft }
			else { E.KeyCode.Up, E.KeyCode.DPadUp }
		local later = if horizontal
			then { E.KeyCode.Right, E.KeyCode.DPadRight }
			else { E.KeyCode.Down, E.KeyCode.DPadDown }
		ctx.action(root, "ReorderUp", earlier, keyboardActive, function()
			step(-1)
		end, { priority = 400, capture = true })
		ctx.action(root, "ReorderDown", later, keyboardActive, function()
			step(1)
		end, { priority = 400, capture = true })
		ctx.action(root, "ReorderCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			return use(moving) ~= nil
		end, cancel, { priority = 400 })
		ctx.action(
			root,
			"ReorderDrop",
			{ E.KeyCode.Return, E.KeyCode.ButtonA },
			keyboardActive,
			commit,
			{ priority = 400 }
		)
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
		wrap = wrap,
		overlay = overlay,
		leading = leading,
		trailing = trailing,
		press = press,
		busy = function(): boolean
			return moving:peek() ~= nil
		end,
		deleteSelected = function()
			remove(true)
		end,
		canDeleteSelected = canDeleteSelected,
	}
end
