--!strict
local Players = game:GetService("Players")
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Facet = require(ReplicatedStorage:WaitForChild("Facet"))
local lab = require(ReplicatedStorage:WaitForChild("FacetScenarios"))
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)
local stop = runtime.mount(function()
	local sheet = Facet.themes.createStyleSheet(runtime)
	return Host.ScreenGui({
		Name = "FacetPerformanceLab",
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
			captureFacts = function()
				local viewport = workspace.CurrentCamera.ViewportSize
				return {
					evidenceClass = "studio",
					capturedAtIso = DateTime.now():ToIsoDate(),
					sourceStamp = workspace:GetAttribute("FacetSourceStamp") or "not recorded",
					placeName = "Facet-PerformanceLab",
					viewport = `{viewport.X}x{viewport.Y}`,
					orientation = if viewport.X >= viewport.Y then "landscape" else "portrait",
					graphicsQualityLevel = tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel),
					frameTarget = "not recorded",
					studioVersion = version(),
					deviceLabel = "Studio host",
					thermalNote = "not recorded",
				}
			end,
			emitCapture = function(row)
				print("FACET_PERF_CAPTURE " .. game:GetService("HttpService"):JSONEncode(row))
			end,
		}, lab),
	})
end, Players.LocalPlayer:WaitForChild("PlayerGui"))
script.Destroying:Connect(function()
	stop()
	runtime:dispose()
end)
