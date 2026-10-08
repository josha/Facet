--!strict
local Types = require("./types")
local gestureOf = require("./gesture_service")

type Gesture = {
	origin: ScrollingFrame,
	start: Vector3,
	previous: Vector3,
	held: { [ScrollingFrame]: () -> () },
	connections: { RBXScriptConnection },
}
local gestures: { [InputObject]: Gesture } = {}
type Listener = {
	frames: { [ScrollingFrame]: (InputObject) -> () },
	connection: RBXScriptConnection?,
}
local listeners: { [UserInputService]: Listener } = {}

local function listen(
	service: UserInputService,
	frame: ScrollingFrame,
	begin: (InputObject) -> (),
	touchType: Enum.UserInputType
): () -> ()
	local listener = listeners[service]
	if not listener then
		local created: Listener = { frames = {}, connection = nil }
		listeners[service] = created
		listener = created
		created.connection = service.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= touchType then
				return
			end
			local checked: { [Instance]: boolean } = {}
			for candidate in created.frames do
				local host = candidate:FindFirstAncestorWhichIsA("BasePlayerGui")
				if host and not checked[host] then
					checked[host] = true
					local hits = (host :: PlayerGui):GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
					for _, hit in hits do
						local node: Instance? = hit
						while node do
							if node:IsA("ScrollingFrame") then
								local start = created.frames[node]
								if start then
									start(input)
								end
								return
							end
							node = node.Parent
						end
						if hit.Active or hit:IsA("GuiButton") or hit:IsA("TextBox") then
							return
						end
					end
				end
			end
		end)
	end
	local current = assert(listener)
	current.frames[frame] = begin
	return function()
		current.frames[frame] = nil
		if next(current.frames) == nil then
			if current.connection then
				current.connection:Disconnect()
			end
			listeners[service] = nil
		end
	end
end

local function finish(input: InputObject)
	local gesture = gestures[input]
	if not gesture then
		return
	end
	gestures[input] = nil
	for _, connection in gesture.connections do
		connection:Disconnect()
	end
	for _, release in gesture.held do
		release()
	end
end

return function(
	ctx: Types.Context,
	frame: ScrollingFrame,
	isOwned: (ScrollingFrame) -> boolean,
	hold: (ScrollingFrame) -> () -> ()
)
	local service = ctx.config.userInputService
	if not service then
		return
	end
	local E = ctx.types.Enum
	local arbiter = gestureOf(ctx)
	local function begin(input: InputObject)
		if input.UserInputType ~= E.UserInputType.Touch or not frame.ScrollingEnabled then
			return
		end
		local current = gestures[input]
		if current then
			if frame:IsDescendantOf(current.origin) then
				current.origin = frame
			end
			return
		end
		local gesture: Gesture = {
			origin = frame,
			start = input.Position,
			previous = input.Position,
			held = {},
			connections = {},
		}
		gestures[input] = gesture
		table.insert(
			gesture.connections,
			service.InputChanged:Connect(function(changed: InputObject)
				if changed ~= input then
					return
				end
				if input.UserInputState == E.UserInputState.Cancel then
					finish(input)
					return
				end
				local kind = arbiter.move(input, ctx.types.Vector2.new(input.Position.X, input.Position.Y))
				if kind == "drag" or kind == "cancelled" then
					return
				end
				local travel, delta = input.Position - gesture.start, gesture.previous - input.Position
				gesture.previous = input.Position
				local horizontal = math.abs(travel.X) > math.abs(travel.Y)
				if math.max(math.abs(travel.X), math.abs(travel.Y)) < 6 then
					return
				end
				local direction = if horizontal then delta.X else delta.Y
				if direction == 0 then
					return
				end
				local pending: { ScrollingFrame } = {}
				local node: Instance? = gesture.origin
				while node do
					if node:IsA("ScrollingFrame") and not gesture.held[node] then
						if not node.ScrollingEnabled then
							return
						end
						local axis = node.ScrollingDirection
						local allowed = axis == E.ScrollingDirection.XY
							or axis == (if horizontal then E.ScrollingDirection.X else E.ScrollingDirection.Y)
						local position = if horizontal then node.CanvasPosition.X else node.CanvasPosition.Y
						local extent = node.AbsoluteCanvasSize - node.AbsoluteWindowSize
						local limit = math.max(0, if horizontal then extent.X else extent.Y)
						local movable = allowed
							and limit > 0
							and (if direction < 0 then position > 0.5 else position < limit - 0.5)
						if movable then
							for _, exhausted in pending do
								gesture.held[exhausted] = hold(exhausted)
							end
							return
						end
						if not isOwned(node) then
							return
						end
						table.insert(pending, node)
					end
					node = node.Parent
				end
			end)
		)
		table.insert(
			gesture.connections,
			service.InputEnded:Connect(function(ended: InputObject)
				if ended == input then
					finish(input)
				end
			end)
		)
		table.insert(
			gesture.connections,
			service.WindowFocusReleased:Connect(function()
				finish(input)
			end)
		)
	end
	local stop = listen(service, frame, begin, E.UserInputType.Touch)
	ctx.runtime.connect(frame, "InputBegan", begin)
	ctx.Compose.cleanup(function()
		stop()
		for input, gesture in gestures do
			if gesture.origin == frame or gesture.held[frame] then
				finish(input)
			end
		end
	end)
end
