--!strict
local Players = game:GetService("Players")
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Facet = require(ReplicatedStorage:WaitForChild("Facet"))
local lab = require(ReplicatedStorage:WaitForChild("FacetScenarios"))
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local neutral = assert(Facet.themes.define(Facet.themes.neutralPackage()))
local packages: { [string]: any } = { ["facet-neutral"] = neutral }
local folder = ReplicatedStorage:FindFirstChild("FacetThemes")
if folder then
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, definition = pcall(require, module)
			if
				ok
				and type(definition) == "table"
				and not definition.testOnly
				and type(definition.build) == "function"
			then
				local built, package = pcall(definition.build, Facet.themes)
				if built and package then
					packages[module.Name] = package
				end
			end
		end
	end
end
local theme = Facet.Compose.cell(neutral)
local themeName = Facet.Compose.cell("facet-neutral")
local UI = Facet.controls(runtime, { theme = theme })
local probe: any = nil
local function invoke(command: string, ...: any): any
	assert(probe, "the lab has not started")
	if command == "capture" then
		return HttpService:JSONEncode(probe.capture())
	elseif command == "state" then
		local state = probe.state()
		state.active = nil
		return state
	end
	local handler = probe[command]
	assert(type(handler) == "function", `unknown lab command {command}`)
	return handler(...)
end
local stop = runtime.mount(function()
	Host.BindableFunction "FacetPerfLabAPI" {
		Parent = workspace,
		OnInvoke = Facet.Compose.static(invoke),
	}
	local sheet = Facet.themes.createStyleSheet(runtime, theme)
	return Host.ScreenGui "FacetPerformanceLab" {
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		sheet,
		Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
		lab.screen.build({
			Facet = Facet,
			runtime = runtime,
			Host = Host,
			UI = UI,
			types = getfenv(0),
			heartbeat = game:GetService("RunService").Heartbeat,
			viewport = {
				w = workspace.CurrentCamera.ViewportSize.X,
				h = workspace.CurrentCamera.ViewportSize.Y,
			},
			themeName = themeName,
			setTheme = function(name: string)
				local package = assert(packages[name], `no theme package named {name}`)
				runtime.reactor:batch(function()
					theme:set(package)
					themeName:set(name)
				end)
			end,
			probe = function(api)
				probe = api
			end,
			captureFacts = function()
				local viewport = workspace.CurrentCamera.ViewportSize
				local class = workspace:GetAttribute("Facet_PerfEvidenceClass")
				return {
					evidenceClass = if class == "emulator" then "emulator" else "studio",
					capturedAtIso = DateTime.now():ToIsoDate(),
					sourceStamp = workspace:GetAttribute("Facet_SourceStamp") or "not recorded",
					placeName = "Facet-PerformanceLab",
					viewport = { x = viewport.X, y = viewport.Y },
					orientation = if viewport.X >= viewport.Y then "landscape" else "portrait",
					preferredTextSize = tostring(GuiService.PreferredTextSize),
					graphicsQualityLevel = tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel),
					frameTarget = "not recorded",
					studioVersion = version(),
					deviceLabel = "Studio host",
					thermalNote = "not recorded",
				}
			end,
			emitCapture = function(row)
				print("FACET_PERF_CAPTURE " .. HttpService:JSONEncode(row))
			end,
		}, lab),
	}
end, Players.LocalPlayer:WaitForChild("PlayerGui"))
workspace:SetAttribute("Facet_PerfLabReady", true)
script.Destroying:Connect(function()
	stop()
	runtime:dispose()
end)
