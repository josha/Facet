--!strict
local active: any = nil
local api = {}

function api.press(node: any, value: any)
	node.InputBegan.fire(value)
	if node.IsA == nil or node:IsA("UserInputService") or value.Position == nil then
		return
	end
	local at = node
	local detector
	while at and not detector and not at:IsA("LayerCollector") do
		detector = at:FindFirstChildWhichIsA("UIDragDetector") or at:FindFirstChild("FacetCollectionDrag", true)
		at = at.Parent
	end
	if detector and detector.Enabled then
		active = { detector = detector, press = value }
		local V2 = require("@lune/roblox").Vector2
		detector.DragStart.fire(V2.new(value.Position.X, value.Position.Y))
	end
end

function api.move(input: any, value: any)
	input.InputChanged.fire(value)
	if
		active
		and active.detector.Parent
		and value.Position
		and (value == active.press or tostring(value.UserInputType) == "Enum.UserInputType.MouseMovement")
	then
		local V2 = require("@lune/roblox").Vector2
		active.detector.DragContinue.fire(V2.new(value.Position.X, value.Position.Y))
	end
end

function api.finish(input: any, value: any)
	local drag = active
	if drag and value ~= drag.press and tostring(value.UserInputType) == "Enum.UserInputType.Touch" then
		input.InputEnded.fire(value)
		return
	end
	active = nil
	if tostring(value.UserInputState) == "Enum.UserInputState.Cancel" then
		input.InputEnded.fire(value)
		return
	end
	if drag and drag.detector.Parent then
		local position = value.Position or drag.press.Position
		local V2 = require("@lune/roblox").Vector2
		drag.detector.DragEnd.fire(V2.new(position.X, position.Y))
	end
	input.InputEnded.fire(value)
end

function api.measure(node: any)
	local size = if node:IsA("ScrollingFrame") then node.AbsoluteWindowSize else node.AbsoluteSize
	local position = node.AbsolutePosition
	local parent = node.Parent
	while parent and not parent:IsA("LayerCollector") do
		if parent:IsA("GuiObject") then
			parent.AbsolutePosition = position
			parent.AbsoluteSize = size
			if parent:IsA("ScrollingFrame") then
				parent.AbsoluteWindowSize = size
			end
		end
		parent = parent.Parent
	end
end

return api
