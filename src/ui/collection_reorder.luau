--!strict
local policy = require("./collection_policy")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
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
	sort: ComposeTypes.Cell<CollectionTypes.Sort?>
): ((GuiObject, ComposeTypes.Readable<V>, K) -> Frame, (boolean?) -> Frame)
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local moving: ComposeTypes.Cell<Move<V, K>?> = Compose.cell(nil :: Move<V, K>?)
	local TAP = 3
	local horizontal = spec.direction == "horizontal"
	local function axis(position: Vector2): number
		return if horizontal then position.X else position.Y
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
	local stopFrames: ComposeTypes.Dispose?
	local startFrames: (() -> ())?
	local function cancel()
		captured = nil
		if stopFrames then
			stopFrames()
			stopFrames = nil
		end
		moving:set(nil)
	end
	local function movable(item: V): boolean
		return policy.allows(spec.movable, item) and not policy.disabled(spec.disabled, item)
	end
	local function begin(key: K, position: Vector2?): ()
		if
			read(sort) ~= nil
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
			captured = if position then pendingInput else nil
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
			if position == nil and keyboardTarget and ctx.config.guiService then
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
		local offset = axis(position) - axis(body.AbsolutePosition) + axis(body.CanvasPosition)
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
				canvasOffset(body, assert(controls.offsetOf)(index, "center", axis(body.AbsoluteWindowSize)))
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
	local selectedObject: ComposeTypes.Readable<unknown>? = if ctx.config.guiService
		then ctx.observe.SelectedObject(ctx.config.guiService)
		else nil
	local function wrap(row: GuiObject, current: ComposeTypes.Readable<V>, key: K): Frame
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
		local handleProps: InputTypes.ButtonProps = {
			Name = "Move",
			Size = D2.new(0, 56, 1, 0),
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
					elseif captured == nil then
						commit()
					end
				end,
			}),
		}
		local handle = UI.Button(handleProps)
		handleNode = handle
		ctx.runtime.connect(handle, "InputBegan", function(value: InputObject)
			if value.UserInputType == E.UserInputType.MouseButton1 or value.UserInputType == E.UserInputType.Touch then
				pendingInput = value
			end
		end)
		local nativeProps: Types.FrameProps = {
			Name = "Reorderable",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Attributes = {
				FacetDragging = function(use: ComposeTypes.Use)
					local move = use(moving)
					return move ~= nil and move.included[key] == true
				end,
			} :: EngineTypes.Attributes,
			handle :: ComposeTypes.Child,
			Host.Frame "Cells" {
				Position = D2.fromOffset(56, 0),
				Size = D2.new(1, -56, 1, 0),
				BackgroundTransparency = 1,
				row,
			},
		}
		return Host.Frame(nativeProps)
	end
	local function overlay(insideBody: boolean?): Frame
		local body = bodyOf()
		if input then
			ctx.runtime.connect(input, "InputChanged", function(value: InputObject)
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
			if stopFrames then
				return
			end
			stopFrames = assert(ctx.runtime.host.frames).onFrame(function(delta)
				local move = moving:peek()
				if move == nil or move.pointer == nil or not captured then
					return
				end
				local size = axis(body.AbsoluteWindowSize)
				local edge = math.min(40, size / 4)
				if edge <= 0 then
					return
				end
				local localY = axis(move.pointer) - axis(body.AbsolutePosition)
				local speed = if localY < edge
					then -math.clamp((edge - localY) / edge, 0, 1)
					elseif localY > size - edge then math.clamp((localY - size + edge) / edge, 0, 1)
					else 0
				if speed == 0 then
					return
				end
				local last = assert(controls.placementOf)(#move.rows)
				local y = math.clamp(
					axis(body.CanvasPosition) + speed * 600 * delta,
					0,
					math.max(0, last.offset + last.size - size)
				)
				canvasOffset(body, y)
				movePointer(move.pointer)
			end)
		end
		Compose.cleanup(function()
			if stopFrames then
				stopFrames()
			end
		end)
		local offset, origin, screen =
			ctx.observe.CanvasPosition(body), ctx.observe.Position(body), ctx.observe.AbsolutePosition(body)
		local rootProps: Types.FrameProps = {
			Name = "ReorderFeedback",
			Position = function(use: ComposeTypes.Use)
				return if insideBody then D2.fromOffset(use(offset).X, use(offset).Y) else D2.fromOffset(0, 0)
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
					return (if insideBody then 0 elseif horizontal then use(origin).X.Offset else use(origin).Y.Offset)
						+ at.offset
						+ (if candidate then 0 else at.size)
						- axis(use(offset))
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
					ctx.styled(
						ctx.text({
							Name = "DragLabel",
							ZIndex = 9,
							BackgroundTransparency = 0,
							Text = function(use: ComposeTypes.Use)
								local move = use(moving)
								if move == nil then
									return ""
								end
								if #move.keys > 1 then
									return tostring(#move.keys) .. " selected"
								end
								local index = assert(controls.indexOfKey)(move.key)
								return if spec.dragLabel and index
									then spec.dragLabel(move.rows[index])
									else tostring(move.key)
							end,
							Position = function(use: ComposeTypes.Use)
								local move = use(moving)
								if move and move.pointer then
									return D2.fromOffset(12, move.pointer.Y - use(screen).Y + use(origin).Y.Offset + 8)
								end
								return D2.fromOffset(12, dropY(use) + 8)
							end,
						}),
						"panel"
					),
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
		return root
	end
	return wrap, overlay
end
