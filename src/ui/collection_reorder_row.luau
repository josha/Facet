--!strict
local pointerDragOf = require("./pointer_drag")
local policy = require("./collection_policy")
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local pointerOf = require("./drag_pointer")
local State = require("./collection_reorder_state")
local Pointer = require("./collection_reorder_pointer")
local liftOf = require("./drag_lift")
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
	local fixedCells = shared.editing == nil and not minusShown
	local cellPosition = if grid then D2.fromOffset(0, header:peek()) else D2.fromOffset(leading:peek(), 0)
	local cellSize = if grid
		then D2.new(1, 0, 1, -header:peek())
		else D2.new(1, -leading:peek() - trailing:peek(), 1, 0)
	local rowNodes, rowKeys = shared.rowNodes, shared.rowKeys
	local gui, movable = shared.gui, shared.movable
	local begin, commit, movePointer = shared.begin, shared.commit, shared.movePointer
	local axis, crossAxis = shared.axis, shared.crossAxis
	local selectedObject: ComposeTypes.ReadOnlyValue<unknown>? = if ctx.config.guiService
		then ctx.selection.observe()
		else nil
	local edgeSpring = ctx.motionSpring("snappy")
	local left: ComposeTypes.ReadOnlyValue<number> = ctx.runtime.spring(function(use: ComposeTypes.Use): number
		return use(leading)
	end, { period = edgeSpring.period, damping = edgeSpring.damping })
	local trailingEdge: ComposeTypes.ReadOnlyValue<number> = ctx.runtime.spring(function(use: ComposeTypes.Use): number
		return use(trailing)
	end, { period = edgeSpring.period, damping = edgeSpring.damping })
	type Access = {
		current: ComposeTypes.ReadOnlyValue<V>,
		detector: UIDragDetector?,
		handleDetector: UIDragDetector?,
		handle: TextButton?,
		enabled: boolean?,
		rowEnabled: boolean?,
		handleEnabled: boolean?,
	}
	local entries: { [K]: Access } = {}
	local allowed, rowsAllowed, unsorted = false, false, false
	local focused: unknown = nil
	local function refresh(entry: Access, item: V?)
		local enabled = unsorted and (if item ~= nil then movable(item) else movable(entry.current:peek()))
		local handle = entry.handle
		if handle and enabled ~= entry.enabled then
			entry.enabled = enabled
			handle.Interactable, handle.Selectable = enabled, enabled
			if enabled then
				handle:RemoveTag("facet-disabled")
			else
				handle:AddTag("facet-disabled")
			end
		end
		local rowEnabled = reorderable and enabled and rowsAllowed
		if entry.detector and entry.rowEnabled ~= rowEnabled then
			entry.rowEnabled = rowEnabled
			entry.detector.Enabled = rowEnabled
		end
		local handleEnabled = enabled and allowed and not (handle and rawequal(handle, focused))
		if entry.handleDetector and entry.handleEnabled ~= handleEnabled then
			entry.handleEnabled = handleEnabled
			entry.handleDetector.Enabled = handleEnabled
		end
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local kind = if preferred then use(preferred) else nil
		allowed, unsorted = pointerInput(use), use(sort) == nil
		rowsAllowed = allowed and kind ~= E.PreferredInput.Touch and kind ~= E.PreferredInput.Gamepad
		focused = if kind == E.PreferredInput.Gamepad and selectedObject then use(selectedObject) else nil
		local items: { [K]: V } = {}
		if spec.movable ~= nil or spec.disabled ~= nil then
			for index, item in ctx.readSource(shared.source, use) do
				items[shared.keyOf(item, index)] = item
			end
		end
		for key, entry in entries do
			refresh(entry, items[key])
		end
	end)
	local function wrap(row: GuiObject, current: ComposeTypes.ReadOnlyValue<V>, key: K, painted: boolean?): Frame
		rowKeys[row] = key
		local entry: Access = { current = current }
		entries[key] = entry
		Compose.cleanup(function()
			if entries[key] == entry then
				entries[key] = nil
			end
		end)
		local move = moving:peek()
		local carried = move ~= nil and move.included[key] == true
		local handleNode: Instance? = nil
		local function toggle()
			if moving:peek() then
				commit()
			else
				begin(key)
			end
		end
		local armed = false
		local confirming = if minusShown then Compose.cell(false) else nil
		if confirming then
			Compose.watch(function(use: ComposeTypes.Use)
				if not use(controlsShown) then
					confirming:set(false)
				end
			end)
		end
		local function makeHandle(): TextButton
			local lead = shared.leads(key)
			local handleDetector = Host.UIDragDetector {
				Archivable = false,
				DragStyle = if grid
					then E.UIDragDetectorDragStyle.TranslatePlane
					else E.UIDragDetectorDragStyle.TranslateLine,
				DragAxis = if shared.horizontal then V2.new(1, 0) else V2.new(0, 1),
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				Enabled = false,
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
							and rawequal(ctx.selection.get(), handleNode)
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
			}
			local handle: TextButton
			local function activate(input: InputObject?, clicks: number?)
				if
					activation.consumed(input)
					or activation.intercepted(handle, input)
					or not movable(current:peek())
					or read(sort) ~= nil
					or not ctx.available(handle)
				then
					return
				end
				if
					input == nil
					or (
						input.UserInputType ~= E.UserInputType.MouseButton1
						and input.UserInputType ~= E.UserInputType.Touch
					)
				then
					toggle()
				end
				activation.notify(handle, input, clicks)
			end
			local handleProps: Types.TextButtonProps = {
				Name = "Move",
				Archivable = false,
				Visible = if shared.editing == nil and confirming == nil
					then true
					else function(use: ComposeTypes.Use)
						return use(controlsShown) and (confirming == nil or not use(confirming))
					end,
				AnchorPoint = V2.new(1, 0),
				Position = D2.fromScale(1, 0),
				Size = if grid then D2.fromOffset(44, 44) else D2.new(0, 44, 1, 0),
				AutomaticSize = E.AutomaticSize.None,
				Text = "",
				AutoButtonColor = false,
				Selectable = unsorted and movable(current:peek()),
				Interactable = unsorted and movable(current:peek()),
				Attributes = {
					appearance = "utility",
					controlSize = "regular",
					role = "default",
					label = "",
					selected = false,
					busy = false,
				},
				ctx.icon(function(use: ComposeTypes.Use)
					return if use(lead) then "checkmark" elseif grid then "view.grid" else "menu"
				end, {
					Name = "ReorderIcon",
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
				}),
				Activated = activate,
				handleDetector,
			}
			handle = ctx.styled(Host.TextButton(handleProps), "button")
			handle:AddTag("facet-appearance-utility")
			local effect = ctx.haptic(nil)
			if effect then
				handle.PressHapticEffect = effect
			end
			activation.mark(handle)
			Compose.cleanup(activation.provide(handle, activate))
			handleNode = handle
			rowKeys[handle] = key
			entry.handle, entry.handleDetector = handle, handleDetector
			entry.enabled, entry.handleEnabled = nil, nil
			refresh(entry)
			Compose.cleanup(function()
				if entry.handle == handle then
					entry.handle, entry.handleDetector, handleNode = nil, nil, nil
				end
			end)
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
		end
		local handle = if not reorderable
			then nil
			elseif shared.editing ~= nil then Compose.show(controlsShown, makeHandle)
			elseif controlsShown:peek() then makeHandle()
			else nil
		local function deletableRow(use: ComposeTypes.Use): boolean
			local item = use(current)
			return policy.allows(spec.rowDeletable, item) and not policy.disabled(spec.disabled, item)
		end
		local minus = if minusShown
			then UI.Button {
				Name = "Minus",
				Archivable = false,
				label = "−",
				name = "Delete",
				shape = "circle",
				role = "destructive",
				AnchorPoint = V2.new(0.5, 0.5),
				Position = if grid then D2.fromOffset(22, 22) else D2.new(0, 22, 0.5, 0),
				Size = D2.fromOffset(28, 28),
				Visible = controlsShown,
				enabled = deletableRow,
				onActivate = function()
					assert(confirming):set(not assert(confirming):peek())
				end,
			}
			else nil
		local confirm = if minusShown
			then UI.Button {
				Name = "Delete",
				Archivable = false,
				label = "Delete",
				role = "destructive",
				AnchorPoint = V2.new(1, 0),
				Position = D2.fromScale(1, 0),
				Size = if grid then D2.fromOffset(88, 44) else D2.new(0, 88, 1, 0),
				AutomaticSize = E.AutomaticSize.None,
				Visible = function(use: ComposeTypes.Use)
					return use(controlsShown) and confirming ~= nil and use(confirming)
				end,
				enabled = deletableRow,
				onActivate = function()
					assert(confirming):set(false)
					if spec.onDelete then
						spec.onDelete({ key })
					end
				end,
			}
			else nil
		local mark = if shared.marked
			then ctx.styled(
				Host.Frame "SelectMark" {
					Archivable = false,
					AnchorPoint = V2.new(0.5, 0.5),
					Position = if grid then D2.fromOffset(22, 22) else D2.new(0, 22, 0.5, 0),
					Size = D2.fromOffset(18, 18),
					BackgroundTransparency = 1,
					Selectable = false,
					Visible = shared.markShown,
					ctx.corner(if mode == "multiple" then 3 else 9),
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
								ctx.corner(4),
							},
							"fill"
						)),
				},
				"radio-mark"
			)
			else nil
		local function rightOf(use: ComposeTypes.Use): number
			return if confirming and use(confirming) then 88 else use(trailing)
		end
		local right: ComposeTypes.ReadOnlyValue<number> = if minusShown
			then ctx.runtime.spring(rightOf, { period = edgeSpring.period, damping = edgeSpring.damping })
			else trailingEdge
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
				FacetDragging = carried,
			},
			Host.Frame "Cells" {
				Visible = not carried,
				Position = if fixedCells
					then cellPosition
					else function(use: ComposeTypes.Use)
						return if grid
							then D2.fromOffset(0, use(header))
							else D2.fromOffset(math.floor(edges(use).X + 0.5), 0)
					end,
				Size = if fixedCells
					then cellSize
					else function(use: ComposeTypes.Use)
						local at = edges(use)
						return if grid
							then D2.new(1, 0, 1, -use(header))
							else D2.new(1, -math.floor(at.X + at.Y + 0.5), 1, 0)
					end,
				BackgroundTransparency = 1,
				row,
			},
		}
		local rowControls: { ComposeTypes.Child? } = { handle, minus, confirm, mark }
		for _, control in rowControls do
			if control then
				nativeProps[#nativeProps + 1] = control
			end
		end
		local frame = Host.Frame(nativeProps)
		rowNodes[key] = frame
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
		local detector = Host.UIDragDetector {
			Name = "FacetCollectionDrag",
			Archivable = false,
			DragStyle = E.UIDragDetectorDragStyle.TranslatePlane,
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = false,
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
						local position = assert(tapPosition)
						local double = previous ~= nil
							and previous.key == key
							and now - previous.at <= 0.5
							and (position - previous.position).Magnitude <= 6
						gesture.lastTap = if double then nil else { key = key, position = position, at = now }
						local target = hit
						local layer = frame:FindFirstAncestorWhichIsA("BasePlayerGui")
						if layer and layer:IsA("BasePlayerGui") and not double then
							for _, candidate in layer:GetGuiObjectsAtPosition(position.X, position.Y) do
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
		}
		entry.detector = detector
		refresh(entry)
		detector.Parent = row
		Compose.cleanup(activation.provideDrag(frame, function(phase, position)
			if phase == "start" then
				rowOrigin = position
				gesture.pickupPosition = position
			elseif phase == "move" and position then
				if gesture.pendingInput and gesture.pendingInput.UserInputType == E.UserInputType.MouseButton1 then
					continueRowDrag(position)
				elseif moving:peek() then
					movePointer(position)
				end
				if moving:peek() then
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
		if spec.drag then
			local lift = liftOf(ctx, row, shared.liftScale)
			shared.lifts[key] = lift
			Compose.cleanup(function()
				if shared.lifts[key] == lift then
					shared.lifts[key] = nil
				end
			end)
		end
		Compose.cleanup(function()
			if rowNodes[key] == frame then
				if gesture.touchKey == key then
					shared.disarm()
				end
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
