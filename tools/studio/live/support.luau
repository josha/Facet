--!strict

local GuiService = game:GetService("GuiService")

local UserInputService = game:GetService("UserInputService")

type Rect = { x: number, y: number, r: number, b: number }

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function overlap(a: Rect, b: Rect): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function gamepadWatch(): () -> { string }
	local seen: { string } = {}
	local connection = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			table.insert(seen, input.KeyCode.Name)
		end
	end)
	return function()
		connection:Disconnect()
		return seen
	end
end

local function centre(node: GuiObject): Vector2
	return node.AbsolutePosition + node.AbsoluteSize / 2
end

local function textBox(root: Instance?): TextBox?
	if root == nil then
		return nil
	end
	if root:IsA("TextBox") then
		return root
	end
	return root:FindFirstChildWhichIsA("TextBox", true)
end

return {
	selectedName = selectedName,
	overlap = overlap,
	gamepadWatch = gamepadWatch,
	centre = centre,
	textBox = textBox,
}
