--!strict
--[[ A NATIVE TEXTBOX'S PRESS: `selectOnFocus`, applied once per focus session.

	Measured on a raw TextBox (docs/plans/facet-foundation-2026-09-18/reports/
	unfinished-fields-prototype.md): a mouse press places the caret, THEN fires
	Focused, THEN the box's own InputBegan; the engine's release writes land before
	UserInputService.InputEnded. So a selection written in Focused is overwritten
	by that press, and a pointer focus selects at its own pointer's release. Any
	other focus (CaptureFocus, activation) selects in Focused. Offsets are bytes.

	Engine services arrive in `services` ({ uis, Enum }) so Lune can drive this
	with doubles; nothing here touches an engine global. ]]
local screen_text_press = {}

function screen_text_press.wire(handle: any, services: any)
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
	local function finish()
		if press ~= nil then
			for _, conn in press.conns do
				conn:Disconnect()
			end
			press = nil
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
				finish()
				if pending ~= nil then
					local policy = pending
					pending = nil
					select(policy)
				end
			end)
		)
	end
	local conns = {
		instance.InputBegan:Connect(function(input: any)
			if press == nil and input.UserInputType == E.UserInputType.Touch then
				follow(input)
			end
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
		finish()
		for _, conn in conns do
			conn:Disconnect()
		end
	end
end

return screen_text_press
