--!strict
export type Phase = "press" | "begin" | "move" | "end" | "cancel"
export type Scrub = (Phase, (string | number)?) -> boolean
export type Options = {
	box: TextBox,
	input: UserInputService,
	Enum: typeof(Enum),
	policy: () -> string?,
	disabled: () -> boolean,
	onScrub: Scrub?,
}
type Press = {
	touch: InputObject?,
	connections: { RBXScriptConnection },
	start: Vector3?,
	scrub: boolean,
	promoted: boolean,
	gate: number,
}

local POINTER_SLOP, TOUCH_SLOP = 6, 14

return function(options: Options): () -> ()
	local box, input, E = options.box, options.input, options.Enum
	local pending: string? = nil
	local press: Press? = nil
	local function select(policy: string)
		if options.disabled() or not box:IsFocused() then
			return
		end
		box.CursorPosition = #box.Text + 1
		box.SelectionStart = if policy == "all" then 1 else -1
	end
	local function finish(phase: Phase)
		local ended = press
		if ended ~= nil then
			press = nil
			for _, connection in ended.connections do
				connection:Disconnect()
			end
			if ended.promoted and options.onScrub then
				options.onScrub(phase)
			end
		end
	end
	local function follow(touch: InputObject?): Press
		local current: Press = { touch = touch, connections = {}, scrub = false, promoted = false, gate = POINTER_SLOP }
		press = current
		table.insert(
			current.connections,
			input.InputEnded:Connect(function(event: InputObject)
				local origin = if current.touch ~= nil
					then event == current.touch
					else event.UserInputType == E.UserInputType.MouseButton1
				if not origin then
					return
				end
				finish("end")
				if pending ~= nil then
					local policy = pending
					pending = nil
					select(policy)
				end
			end)
		)
		table.insert(
			current.connections,
			input.InputChanged:Connect(function(event: InputObject)
				local moved = if current.touch ~= nil
					then event == current.touch
					else event.UserInputType == E.UserInputType.MouseMovement
				local start = current.start
				if not current.scrub or not moved or start == nil then
					return
				end
				local dx, dy = event.Position.X - start.X, event.Position.Y - start.Y
				if not current.promoted then
					if dx * dx + dy * dy < current.gate * current.gate then
						return
					end
					local scrub = options.onScrub
					if math.abs(dx) <= math.abs(dy) or scrub == nil or not scrub("begin") then
						current.scrub = false
						return
					end
					current.promoted, pending = true, nil
					if box:IsFocused() then
						box:ReleaseFocus(false)
					end
				end
				local scrub = options.onScrub
				if scrub then
					scrub("move", dx)
				end
			end)
		)
		table.insert(
			current.connections,
			input.InputBegan:Connect(function(event: InputObject)
				if current.promoted and (event.KeyCode == E.KeyCode.Escape or event.KeyCode == E.KeyCode.ButtonB) then
					finish("cancel")
				end
			end)
		)
		return current
	end
	local connections: { RBXScriptConnection } = {
		box.InputBegan:Connect(function(event: InputObject)
			local touch = event.UserInputType == E.UserInputType.Touch
			if not touch and event.UserInputType ~= E.UserInputType.MouseButton1 then
				return
			end
			local current = press
			if not touch and current ~= nil and current.start ~= nil and current.touch == nil then
				finish("cancel")
				current = nil
			end
			if current ~= nil and (current.start ~= nil or touch or current.touch ~= nil) then
				return
			end
			local scrub = options.onScrub ~= nil and options.onScrub("press", if touch then "touch" else "pointer")
			if current == nil then
				local policy = options.policy()
				local selects = policy == "all" or policy == "end"
				if not scrub and not (touch and selects) then
					return
				end
				current = follow(if touch then event else nil)
			end
			local active = assert(current)
			active.start, active.scrub = event.Position, scrub == true
			active.gate = if touch then TOUCH_SLOP else POINTER_SLOP
		end),
		box.Focused:Connect(function()
			local policy = options.policy()
			pending = nil
			if policy ~= "all" and policy ~= "end" then
				return
			end
			local held = (
				input :: unknown
			) :: { IsMouseButtonPressed: ((UserInputService, Enum.UserInputType) -> boolean)? }
			local mouseDown = held.IsMouseButtonPressed ~= nil
				and input:IsMouseButtonPressed(E.UserInputType.MouseButton1)
			if press ~= nil or mouseDown then
				pending = policy
				if press == nil then
					follow(nil)
				end
			else
				select(policy)
			end
		end),
		box.FocusLost:Connect(function()
			pending = nil
		end),
	}
	return function()
		pending = nil
		finish("cancel")
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end
