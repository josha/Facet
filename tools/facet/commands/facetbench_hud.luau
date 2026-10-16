--!strict

local Files = require("../lib/files")
local Lute = require("../../vendor/verify/src/lute")
local Devices = require("../../play/host/devices")

return function(place: string, output: string)
	local opened, problem = Lute.studio.launch({
		place = Files.absolute(place),
		directory = Files.absolute(output .. "/studio"),
		runSeconds = 600,
	})
	assert(opened, problem)
	local owner = opened :: Lute.StudioLaunched
	local ok, detail = pcall(function()
		for _, device in Devices.list do
			local orientation = if device.orientation == "portrait" then "Portrait" else "LandscapeLeft"
			local rotate = if device.orientation
				then "s:SetOrientationAsync(Enum.ScreenOrientation." .. orientation .. ") "
				else ""
			local setup = owner.session.execute(
				"Edit",
				string.format(
					"local s = game:GetService('StudioDeviceSimulatorService') s:SetDeviceAsync(%q) %sreturn s:GetDeviceAsync()",
					device.preset,
					rotate
				)
			)
			assert(setup.ok, setup.detail)
			assert(owner.session.play(true).ok)
			local measured = owner.session.execute(
				"Client",
				[[
task.wait(3)
local gui = game:GetService("GuiService")
local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
local function bounds(node)
    return { x = node.AbsolutePosition.X, y = node.AbsolutePosition.Y,
        width = node.AbsoluteSize.X, height = node.AbsoluteSize.Y }
end
local result = { band = tostring(gui.TopbarInset), native = {}, actions = {}, selection = {} }
for _, node in game:GetService("CoreGui"):GetDescendants() do
    if node:IsA("GuiButton") and string.find(node:GetFullName(), "MenuIconHolder", 1, true) then
        table.insert(result.native, { path = node:GetFullName(), bounds = bounds(node) })
    end
end
for _, node in playerGui:GetDescendants() do
    if node:IsA("TextButton") and node:FindFirstChild("ActionLabel") and node.Visible then
        local caption = node.ActionLabel
        local shown = node.Parent.Visible
        table.insert(result.actions, { label = caption.Text, bounds = bounds(node), shown = shown,
            labelBounds = bounds(caption), labelSize = caption.TextSize, labelVisible = caption.Visible,
            labelTransparency = caption.TextTransparency, left = node.NextSelectionLeft ~= nil,
            right = node.NextSelectionRight ~= nil })
    end
end
local root = playerGui:FindFirstChild("HubActions")
if root then
    local actions = {}
    for _, node in root:GetDescendants() do
        if node:IsA("TextButton") and node.Parent.Visible then table.insert(actions, node) end
    end
    table.sort(actions, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
    if #actions > 0 then
        gui.SelectedObject = actions[1]
        for index = 1, #actions do
            local selected = gui.SelectedObject
            table.insert(result.selection, selected and selected.ActionLabel.Text or "none")
            local input = game:GetService("UserInputService"):CreateVirtualInput()
            input:SendKey(true, Enum.KeyCode.Right, false)
            task.wait(0.05)
            input:SendKey(false, Enum.KeyCode.Right, false)
            task.wait(0.15)
        end
    end
end
return game:GetService("HttpService"):JSONEncode(result)
]]
			)
			assert(measured.ok, measured.detail)
			Files.write(output .. "/" .. device.id .. ".json", measured.text or "")
			assert(owner.session.play(false).ok)
		end
	end)
	local closed = owner.close()
	assert(#closed.survivors == 0, "HUD inspection Studio survived cleanup")
	assert(ok, tostring(detail))
end
