-- LuauUI Edit Preview — durable Studio plugin (director Part-2 ws2).
-- Wraps src/client/edit_preview: renders a blueprint through the REAL LuauUI
-- pipeline into CoreGui during Edit, with device-profile presets.
--
-- Install: copy this file into your local Studio plugins folder
--   macOS: ~/Documents/Roblox/Plugins/   (restart Studio to load)
-- Requirements in the open place:
--   * a `LuauUI` ModuleScript tree anywhere under ReplicatedStorage (Rojo sync
--     or injected — the plugin finds it recursively);
--   * optionally a `LuauUIPreviewEntry` ModuleScript under ReplicatedStorage
--     returning `function(LuauUI, core) -> Blueprint` (your screen to
--     preview); without one, a built-in sample screen renders.
-- Toolbar: "Preview" toggles; "Device" cycles phone → tablet → desktop.

local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toolbar = plugin:CreateToolbar("LuauUI")
local toggleButton =
	toolbar:CreateButton("Preview", "Toggle the LuauUI Edit-mode preview", "rbxasset://textures/ui/common/robux.png")
local deviceButton = toolbar:CreateButton(
	"Device",
	"Cycle device profile (desktop / phone portrait / phone landscape / tablet landscape / tablet portrait)",
	"rbxasset://textures/ui/common/settings.png"
)

local ORDER = { "desktop", "phone", "phoneLandscape", "tablet", "tabletPortrait" }
local profileIndex = 1
local handle = nil

local function findLuauUI()
	local found = ReplicatedStorage:FindFirstChild("LuauUI", true)
	if found == nil or not found:IsA("ModuleScript") then
		warn("[LuauUI Preview] no LuauUI ModuleScript found under ReplicatedStorage")
		return nil
	end
	return found
end

local function sampleBlueprint(LuauUI, core)
	local UI = LuauUI.UI
	local value = core:signal(true)
	return UI.Screen({
		id = "PluginSample",
		padding = 16,
		gap = 8,
		children = {
			UI.Text({ id = "Title", text = "LuauUI Edit Preview — sample screen", textSize = 22 }),
			UI.Text({
				id = "Hint",
				text = "Provide ReplicatedStorage.LuauUIPreviewEntry to preview your own screen.",
				textSize = 14,
				role = "secondary",
			}),
			UI.Toggle({ id = "Sample", label = "A sample toggle", value = value }),
			UI.Button({ id = "Sample2", label = "A sample button" }),
		},
	})
end

local function stop()
	if handle ~= nil then
		pcall(handle.dispose)
		handle = nil
	end
	toggleButton:SetActive(false)
end

local function start()
	local luauuiModule = findLuauUI()
	if luauuiModule == nil then
		return
	end
	local ok, err = pcall(function()
		local LuauUI = require(luauuiModule)
		local edit_preview = require(luauuiModule:FindFirstChild("client"):FindFirstChild("edit_preview"))
		local entryModule = ReplicatedStorage:FindFirstChild("LuauUIPreviewEntry")
		local blueprint
		if entryModule ~= nil and entryModule:IsA("ModuleScript") then
			blueprint = require(entryModule)
		else
			blueprint = sampleBlueprint
		end
		handle = edit_preview.start(LuauUI, {
			parent = CoreGui,
			blueprint = blueprint,
			profile = ORDER[profileIndex],
		})
	end)
	if not ok then
		warn("[LuauUI Preview] failed to start: " .. tostring(err))
		stop()
		return
	end
	toggleButton:SetActive(true)
end

toggleButton.Click:Connect(function()
	if handle ~= nil then
		stop()
	else
		start()
	end
end)

deviceButton.Click:Connect(function()
	profileIndex = (profileIndex % #ORDER) + 1
	if handle ~= nil then
		local ok, err = pcall(function()
			handle.setProfile(ORDER[profileIndex])
		end)
		if not ok then
			warn("[LuauUI Preview] profile switch failed: " .. tostring(err))
		end
	end
end)

plugin.Unloading:Connect(stop)
