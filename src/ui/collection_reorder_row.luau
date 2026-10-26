--!strict
local pointerDragOf = require("./pointer_drag")
local policy = require("./collection_policy")
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local EngineTypes = require("./engine_types")
local InputTypes = require("./input_types")
local InputProps = require("./input_props")
local pointerOf = require("./drag_pointer")
local State = require("./collection_reorder_state")
local Pointer = require("./collection_reorder_pointer")
local TAP = 3
return function<V, K>(
	shared: State.Reorder<V, K>,
	pointer: Pointer.Pointer<K>
): (GuiObject, ComposeTypes.ReadOnlyValue<V>, K, boolean?) -> Frame
	local ctx, UI, spec, gesture = shared.ctx, shared.UI, shared.spec, shared.gesture
	local Compose, Host = ctx.Compose, ctx.Host
	local read = ctx.read
	local pointerInput = pointerDragOf(ctx)
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local moving, selection, sort = shared.moving, shared.selection, shared.sort
	local grid, reorderable, preferred = shared.grid, shared.reorderable, shared.preferred
	local controlsShown, leading, trailing, header =
		shared.controlsShown, shared.leading, shared.trailing, shared.header
	local mode, minusShown = shared.mode, shared.minusShown
	local rowNodes, rowKeys = shared.rowNodes, shared.rowKeys
	local gui, movable = shared.gui, shared.movable
	local begin, commit, movePointer = shared.begin, shared.commit, shared.movePointer
	local axis, crossAxis = shared.axis, shared.crossAxis
	local selectedObject: ComposeTypes.ReadOnlyValue<unknown>? = if ctx.config.guiService
		then ctx.observe.SelectedObject(ctx.config.guiService)
		else nil
	local function wrap(row: GuiObject, current: ComposeTypes.ReadOnlyValue<V>, key: K, painted: boolean?): Frame
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
				local handleProps: InputProps.ButtonProps = {
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
						DragAxis = if shared.horizontal then V2.new(1, 0) else V2.new(0, 1),
						ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
						Enabled = function(use: ComposeTypes.Use)
							local selected = if selectedObject then use(selectedObject) else nil
							local held = preferred ~= nil
								and use(preferred) == E.PreferredInput.Gamepad
								and handleNode ~= nil
								and rawequal(selected, handleNode)
							return pointerInput(use) and movable(use(current)) and read(sort, use) == nil and not held
						end,
						DragStart = function(position)
							position = pointerOf(ctx, position)
							local current = moving:peek()
							gesture.origin, gesture.travel = position, 0
							gesture.pickupPosition = position
							armed = current ~= nil and current.keyboard
							if not armed then
								begin(key, position)
								gesture.selectedPickup = moving:peek() ~= nil
									and gui ~= nil
									and handleNode ~= nil
									and rawequal(gui.SelectedObject, handleNode)
							end
						end,
						DragContinue = function(position)
							position = pointerOf(ctx, position)
							if gesture.origin then
								gesture.travel = math.max(gesture.travel, (position - gesture.origin).Magnitude)
							end
							if not armed or gesture.travel >= TAP then
								movePointer(position)
							end
						end,
						DragEnd = function()
							local tapped = gesture.origin ~= nil and gesture.travel < TAP
							gesture.origin = nil
							if armed then
								armed = false
								commit()
								return
							end
							if tapped then
								shared.cancel()
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
							gesture.pendingInput = value
							local move = moving:peek()
							if move and move.pointer and gesture.captured == nil then
								gesture.captured = value
								activation.consume(value)
								if value.UserInputType == E.UserInputType.Touch and not gesture.releaseScrollers then
									gesture.releaseScrollers = scrollLock.holdAncestors(handle)
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
		local minusProps: InputProps.ButtonProps = {
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
		local confirmProps: InputProps.ButtonProps = {
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
		local mark = if shared.marked
			then ctx.styled(
				Host.Frame "SelectMark" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = if grid then D2.fromOffset(22, 22) else D2.new(0, 22, 0.5, 0),
					Size = D2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Selectable = false,
					Visible = shared.markShown,
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
			if shared.instantLayout or shared.motionReduced(use) then
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
			if state ~= E.UserInputState.Begin or gesture.touchKey ~= key or moving:peek() ~= nil then
				return
			end
			local position = if gesture.pendingInput
				then V2.new(gesture.pendingInput.Position.X, gesture.pendingInput.Position.Y)
				elseif positions[1] then pointerOf(ctx, positions[1])
				else gesture.touchOrigin
			shared.disarm()
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
					or spec.drag ~= nil
					or math.abs(axis(position) - axis(rowOrigin))
						>= math.abs(crossAxis(position) - crossAxis(rowOrigin))
				)
			then
				rowDragged = true
				if gesture.pendingInput == nil or gesture.pendingInput.UserInputType ~= E.UserInputType.Touch then
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
			Enabled = function(use: ComposeTypes.Use)
				return reorderable
					and pointerInput(use)
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
				gesture.pickupPosition = position
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
					and gesture.pendingInput ~= nil
					and gesture.pendingInput.UserInputState ~= E.UserInputState.Cancel
				local tapPosition = rowOrigin
				rowOrigin = nil
				if not tapped then
					gesture.lastTap = nil
				end
				if gesture.captured == nil and moving:peek() then
					commit()
				elseif tapped and row:IsA("GuiButton") and not activation.consumed(gesture.pendingInput) then
					if activation.trigger(row, gesture.pendingInput, 0) then
						activation.consume(gesture.pendingInput)
					end
				elseif tapped and not activation.consumed(gesture.pendingInput) then
					local host = frame.Parent
					local hit = if host then host:FindFirstChild("RowHit") else nil
					if hit then
						local frames = ctx.runtime.host.frames
						local now = if frames then frames.now() else os.clock()
						local previous = gesture.lastTap
						local position = tapPosition :: Vector2
						local double = previous ~= nil
							and previous.key == key
							and now - previous.at <= 0.5
							and (position - previous.position).Magnitude <= 6
						gesture.lastTap = if double then nil else { key = key, position = position, at = now }
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
						activation.trigger(target, gesture.pendingInput, if double then 2 else 1)
						activation.consume(gesture.pendingInput)
					end
				end
			end,
		})
		detector.Parent = row
		Compose.cleanup(activation.provideDrag(frame, function(phase, position)
			if phase == "start" then
				rowOrigin = position
				gesture.pickupPosition = position
			elseif phase == "move" and position then
				if
					rowOrigin
					and not moving:peek()
					and (position - rowOrigin).Magnitude >= 6
					and gesture.pendingInput
					and gesture.pendingInput.UserInputType == E.UserInputType.MouseButton1
					and (
						grid
						or spec.drag ~= nil
						or math.abs(axis(position) - axis(rowOrigin))
							>= math.abs(crossAxis(position) - crossAxis(rowOrigin))
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
					gesture.recycled = true
				end
			end
		end)
		ctx.runtime.connect(row, "InputBegan", function(value: InputObject)
			pointer.press(key, value)
		end)
		if row:IsA("GuiButton") then
			if shared.pluginGui then
				ctx.runtime.connect(row, "MouseButton1Down", function(x: number, y: number)
					pointer.mouseDown(V2.new(x, y))
				end)
				ctx.runtime.connect(row, "InputEnded", function(value: InputObject)
					pointer.finish(value)
				end)
			end
		end
		rowKeys[frame] = key
		return frame
	end
	return wrap
end
