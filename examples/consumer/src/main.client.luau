--!strict
local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage:WaitForChild("Facet"))
local screen = require(storage:WaitForChild("FacetConsumerScreen"))
local runtime = Facet.Roblox.createRuntime()
local target = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local stop = runtime.mount(function()
	local Host = runtime.constructors
	local sheet = Facet.themes.createStyleSheet(runtime)
	return Host.ScreenGui({
		Name = "FacetConsumer",
		ResetOnSpawn = false,
		sheet,
		Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
		screen.build(Facet, runtime),
	})
end, target)
script.Destroying:Connect(function()
	stop()
	runtime.dispose()
end)
