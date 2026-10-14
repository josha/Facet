--!strict
local activation = require("./activation")
local ComposeTypes = require("../vendor/compose/core")
local DragTypes = require("./drag_types")
local State = require("./collection_reorder_state")
local SLOP = 10
export type Pointer<K> = {
	mouseDown: (Vector2) -> (),
	press: (K, InputObject) -> (),
	finish: (InputObject) -> (),
	listen: (ScrollingFrame) -> (),
}
return function<V, K>(shared: State.Reorder<V, K>): Pointer<K>
	local ctx, spec, gesture = shared.ctx, shared.spec, shared.gesture
	local Compose = ctx.Compose
	local read = ctx.read
	local V2, E = ctx.types.Vector2, ctx.types.Enum
	local moving, selection, source, keyOf = shared.moving, shared.selection, shared.source, shared.keyOf
	local reorderable, rowNodes, movable, arbiter = shared.reorderable, shared.rowNodes, shared.movable, shared.arbiter
	local grid, horizontal, pluginGui, editing = shared.grid, shared.horizontal, shared.pluginGui, shared.editing
	local disarm, begin, axis, movePointer = shared.disarm, shared.begin, shared.axis, shared.movePointer
	local cancel, commit, input = shared.cancel, shared.commit, shared.input
	local pressed: K? = nil
	local pressOrigin: Vector2? = nil
	local nativeOrigin: Vector2? = nil
	local pointerOffset = V2.new()
	local function mouseDown(position: Vector2)
		if pluginGui then
			nativeOrigin = position
			gesture.pickupPosition = position
			if gesture.pendingInput then
				pressOrigin = position
				pointerOffset = position - V2.new(gesture.pendingInput.Position.X, gesture.pendingInput.Position.Y)
			end
		end
	end
	local function press(key: K, value: InputObject): ()
		local at: Vector3? = value.Position
		if not reorderable or at == nil or moving:peek() ~= nil then
			return
		end
		if gesture.touchOrigin then
			return
		end
		local row = rowNodes[key]
		local options: DragTypes.SourceSpec? = nil
		if value.UserInputType == E.UserInputType.Touch and spec.drag then
			local items, keys = {}, {}
			local selected = read(selection)
			for index, item in read(spec.selectionFrom or source) do
				local candidate = keyOf(item, index)
				if movable(item) and (candidate == key or (selected[key] and selected[candidate])) then
					table.insert(items, item)
					table.insert(keys, candidate)
				end
			end
			if #keys == 0 then
				return
			end
			options = table.clone(spec.drag(items, keys)) :: DragTypes.SourceSpec
			gesture.touchTransfer =
				{ key = key, pointer = value, options = options :: DragTypes.SourceSpec, keys = keys, items = items }
		end
		if
			row
			and (value.UserInputType == E.UserInputType.MouseButton1 or value.UserInputType == E.UserInputType.Touch)
		then
			if
				not arbiter.begin(value, row, V2.new(at.X, at.Y), {
					pickup = if value.UserInputType == E.UserInputType.Touch
						then (options and options.touchPickup) or "longPress"
						else "immediate",
					axis = (options and options.touchDragAxis)
						or (if grid then "XY" elseif horizontal then "X" else "Y"),
					scroll = true,
				})
			then
				return
			end
			gesture.gestureOwner = row
		end
		if value.UserInputType == E.UserInputType.MouseButton1 then
			if pluginGui then
				activation.release(value)
			end
			pressed, pressOrigin, gesture.pendingInput = key, V2.new(at.X, at.Y), value
			if pluginGui and nativeOrigin then
				pressOrigin = nativeOrigin
				pointerOffset = nativeOrigin - V2.new(at.X, at.Y)
			end
			gesture.pickupPosition = pressOrigin
		elseif value.UserInputType == E.UserInputType.Touch and (editing == nil or editing == false) then
			disarm()
			gesture.touchKey, gesture.touchOrigin, gesture.pendingInput = key, V2.new(at.X, at.Y), value
			gesture.pickupPosition = gesture.touchOrigin
		end
	end
	local function moveMouse(position: Vector2)
		if pressed ~= nil and pressOrigin ~= nil and gesture.captured == nil then
			if
				(if grid then (position - pressOrigin).Magnitude else math.abs(axis(position) - axis(pressOrigin))) >= 6
			then
				local key = pressed
				pressed, pressOrigin = nil, nil
				begin(key, position)
				activation.consume(gesture.pendingInput)
			end
		end
		local move = moving:peek()
		if move and move.pointer and not move.keyboard then
			movePointer(position)
		end
	end
	local function finishMouse(value: InputObject)
		if value.UserInputType ~= E.UserInputType.MouseButton1 then
			return
		end
		if pluginGui and value == gesture.pendingInput and value.UserInputState ~= E.UserInputState.Cancel then
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
	local function listen(body: ScrollingFrame): ()
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
				if gesture.pendingInput and value.UserInputType == E.UserInputType.MouseMovement then
					arbiter.move(gesture.pendingInput, V2.new(value.Position.X, value.Position.Y))
				end
				if gesture.touchOrigin and value == gesture.pendingInput then
					local position = V2.new(value.Position.X, value.Position.Y)
					local kind = arbiter.move(value, position)
					if kind == "drag" and gesture.touchKey ~= nil then
						local key = gesture.touchKey
						disarm()
						begin(key, position)
						movePointer(position)
						return
					end
					if kind == "scroll" or kind == "pan" or (position - gesture.touchOrigin).Magnitude > SLOP then
						disarm()
					end
					return
				end
				if
					pluginGui ~= nil
					and pressed ~= nil
					and pressOrigin ~= nil
					and gesture.captured == nil
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
					gesture.captured
					and (
						value == gesture.captured
						or (
							gesture.captured.UserInputType == E.UserInputType.MouseButton1
							and value.UserInputType == E.UserInputType.MouseMovement
						)
					)
				then
					if value.UserInputState == E.UserInputState.Cancel then
						cancel()
					else
						local position = V2.new(value.Position.X, value.Position.Y)
						if gesture.origin then
							gesture.travel = math.max(gesture.travel, (position - gesture.origin).Magnitude)
						end
						movePointer(position)
					end
				end
			end)
			ctx.runtime.connect(input, "InputEnded", function(value: InputObject)
				if gesture.gestureOwner then
					arbiter.finish(value, gesture.gestureOwner, value.UserInputState == E.UserInputState.Cancel)
				end
				if value.UserInputType == E.UserInputType.MouseButton1 then
					pressed, pressOrigin = nil, nil
				end
				if gesture.touchOrigin and value == gesture.pendingInput then
					disarm()
				end
				if
					gesture.captured
					and (
						value == gesture.captured
						or (
							gesture.captured.UserInputType == E.UserInputType.MouseButton1
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
						(
							gesture.captured
							and gesture.captured.UserInputType == E.UserInputType.Touch
							and use(touch) == false
						)
						or (gesture.captured and gesture.captured.UserInputType == E.UserInputType.MouseButton1 and use(
							mouse
						) == false)
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
	end
	return { mouseDown = mouseDown, press = press, finish = finishMouse, listen = listen }
end
