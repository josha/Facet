--!strict
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

for _, name in { "Facet-VirtualMonitors", "Facet-Flap" } do
	local path = `../places/{name}.rbxl`
	local place = roblox.deserializePlace(fs.readFile(path))
	local isFlap = name == "Facet-Flap"
	assert((place:GetService("Workspace"):GetAttribute("FacetFlap") == true) == isFlap, path)
	local storage = place:GetService("ReplicatedStorage")
	local scripts = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local entry = assert(scripts and scripts:FindFirstChild("VirtualMonitors"), path)
	assert(entry:IsA("LocalScript") and entry.Source == fs.readFile("main.client.luau"), path)
	local modules = assert(storage:FindFirstChild("VirtualMonitors"), path)
	for _, module in modules:GetChildren() do
		assert(module:IsA("ModuleScript") and module.Source == fs.readFile(`{module.Name}.luau`), path)
	end
	assert(modules:FindFirstChild("flap") and modules:FindFirstChild("flap_model"), path)
	local facet = assert(storage:FindFirstChild("Facet"), path)
	assert(facet.Source == fs.readFile("../../src/init.luau"), path)
	assert(facet.vendor.compose.core:FindFirstChild("focus-neighbor"), path)
	assert(facet.vendor.compose.core.structure:FindFirstChild("tile-collection"), path)
	assert(not facet.ui:FindFirstChild("focus_beam"), path)
	print(`PASS {path}: current source, client bootstrap, Compose modules and launch mode`)
end
