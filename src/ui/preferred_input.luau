--!strict
local MODIFIERS: { [string]: boolean } = {
	LeftShift = true,
	RightShift = true,
	LeftControl = true,
	RightControl = true,
	LeftAlt = true,
	RightAlt = true,
	LeftMeta = true,
	RightMeta = true,
	LeftSuper = true,
	RightSuper = true,
}

local preferredInput = {}

function preferredInput.withheld(input: UserInputService, value: unknown, keyboard: EnumItem): boolean
	if value ~= keyboard then
		return false
	end
	local ok, keys = pcall(input.GetKeysPressed, input)
	if not ok or type(keys) ~= "table" or #keys == 0 then
		return false
	end
	for _, key in keys do
		if not MODIFIERS[key.KeyCode.Name] then
			return false
		end
	end
	local clicked, buttons = pcall(input.GetMouseButtonsPressed, input)
	return not (clicked and type(buttons) == "table" and #buttons > 0)
end

function preferredInput.nudges(input: UserInputService, types: typeof(Enum), changed: () -> ()): () -> ()
	local began = input.InputBegan:Connect(changed)
	local moved = input.InputChanged:Connect(function(event: InputObject)
		local kind = event.UserInputType
		if kind == types.UserInputType.MouseMovement or kind == types.UserInputType.MouseWheel then
			changed()
		end
	end)
	return function()
		began:Disconnect()
		moved:Disconnect()
	end
end

return preferredInput
