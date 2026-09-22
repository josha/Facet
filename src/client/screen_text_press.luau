--!strict
--[[ A NATIVE TEXTBOX'S PRESS: `selectOnFocus`, applied once per focus session,
	and a NumberInput's scrub, a horizontal drag across the same box.

	Measured on a raw TextBox (docs/plans/facet-foundation-2026-09-18/reports/
	unfinished-fields-prototype.md): a mouse press places the caret, THEN fires
	Focused, THEN the box's own InputBegan; the engine's release writes land before
	UserInputService.InputEnded. So a selection written in Focused is overwritten
	by that press, and a pointer focus selects at its own pointer's release. Any
	other focus (CaptureFocus, activation) selects in Focused. Offsets are bytes.

	A scrub cannot use a UIDragDetector: on the box it eats the tap (no focus, no
	caret). So the box's own InputBegan starts a press and the global service
	follows it; nothing changes before the shared slop, so a tap stays native.
	Past it, a horizontal drag asks the control (`onScrub`), then releases focus
	(the box is inert after that, measured) and reports the TOTAL travel.

	Engine services arrive in `services` ({ uis, Enum }) so Lune can drive this
	with doubles; nothing here touches an engine global. ]]
local interaction_tokens = require("../input/interaction_tokens")
local screen_text_press = {}

function screen_text_press.wire(handle: any, services: any, handlers: any)
	local instance = handle.instance
	local uis, E = services.uis, services.Enum
	if handle.textPressReset ~= nil then
		handle.textPressReset()
	end
	local pending: string? = nil -- the policy waiting for its pointer's release
	local press: any = nil -- the held pointer this session follows
	local function select(policy: string)
		if handle.disabledState == true or not instance:IsFocused() then
			return
		end
		instance.CursorPosition = #instance.Text + 1
		instance.SelectionStart = if policy == "all" then 1 else -1
	end
	local function finish(phase: string)
		local ended = press
		if ended ~= nil then
			press = nil
			for _, conn in ended.conns do
				conn:Disconnect()
			end
			if ended.promoted then
				handlers.onScrub(phase)
			end
		end
	end
	-- the box's own events stop at its edge; its release is followed globally,
	-- filtered to the finger (or the mouse button) that pressed
	local function follow(touch: any?)
		press = { touch = touch, conns = {} }
		table.insert(
			press.conns,
			uis.InputEnded:Connect(function(input: any)
				local origin = if press.touch ~= nil
					then input == press.touch
					else input.UserInputType == E.UserInputType.MouseButton1
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
			press.conns,
			uis.InputChanged:Connect(function(input: any)
				local moved = if press.touch ~= nil
					then input == press.touch
					else input.UserInputType == E.UserInputType.MouseMovement
				if not press.scrub or not moved then
					return
				end
				local dx, dy = input.Position.X - press.start.X, input.Position.Y - press.start.Y
				if not press.promoted then
					if not interaction_tokens.promoted(dx, dy, press.pointerType) then
						return
					end
					-- a vertical drag stays the scroller's; a refused one stays native
					if math.abs(dx) <= math.abs(dy) or not handlers.onScrub("begin") then
						press.scrub = false
						return
					end
					press.promoted, pending = true, nil
					if instance:IsFocused() then
						instance:ReleaseFocus(false)
					end
				end
				handlers.onScrub("move", dx)
			end)
		)
		table.insert(
			press.conns,
			uis.InputBegan:Connect(function(input: any)
				if press.promoted and (input.KeyCode == E.KeyCode.Escape or input.KeyCode == E.KeyCode.ButtonB) then
					finish("cancel")
				end
			end)
		)
	end
	local conns = {
		instance.InputBegan:Connect(function(input: any)
			local touch = input.UserInputType == E.UserInputType.Touch
			if not touch and input.UserInputType ~= E.UserInputType.MouseButton1 then
				return
			end
			-- one press at a time; a mouse press joins the release Focused follows
			if press ~= nil and (press.start ~= nil or touch or press.touch ~= nil) then
				return
			end
			local scrub = handlers.onScrub ~= nil
				and handlers.onScrub("press", if touch then "touch" else "pointer") == true
			if press == nil then
				if not scrub and not touch then
					return
				end
				follow(if touch then input else nil)
			end
			press.start, press.scrub = input.Position, scrub
			press.pointerType = if touch then "touch" else "mouse"
		end),
		instance.Focused:Connect(function()
			local policy = handle.selectOnFocus
			pending = nil
			if policy ~= "all" and policy ~= "end" then
				return
			end
			if press ~= nil or uis:IsMouseButtonPressed(E.UserInputType.MouseButton1) then
				pending = policy
				if press == nil then
					follow(nil)
				end
			else
				select(policy)
			end
		end),
		instance.FocusLost:Connect(function()
			pending = nil
		end),
	}
	handle.textPressReset = function()
		pending = nil
		finish("cancel")
		for _, conn in conns do
			conn:Disconnect()
		end
	end
end

return screen_text_press
