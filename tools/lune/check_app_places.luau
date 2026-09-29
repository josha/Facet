--!strict
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

for _, entry in
	{
		{ name = "Facet-VirtualMonitors", folder = "virtual_monitors", root = "VirtualMonitors" },
		{ name = "Facet-Farm", folder = "facet_farm", root = "FacetFarm" },
	}
do
	local path = `examples/places/{entry.name}.rbxl`
	local source = `examples/{entry.folder}`
	local place = roblox.deserializePlace(fs.readFile(path))
	local storage = place:GetService("ReplicatedStorage")
	local scripts = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local bootstrap = assert(scripts and scripts:FindFirstChild(entry.root), path)
	assert(bootstrap:IsA("LocalScript") and bootstrap.Source == fs.readFile(`{source}/main.client.luau`), path)
	local modules = assert(storage:FindFirstChild(entry.root), path)
	for _, module in modules:GetChildren() do
		assert(module:IsA("ModuleScript") and module.Source == fs.readFile(`{source}/{module.Name}.luau`), path)
	end
	assert(modules:FindFirstChild("model") and modules:FindFirstChild("screens"), path)
	local facet = assert(storage:FindFirstChild("Facet"), path)
	assert(facet.Source == fs.readFile("src/init.luau"), path)
	assert(facet.vendor.compose.core:FindFirstChild("focus-neighbor"), path)
	assert(facet.vendor.compose.core.structure:FindFirstChild("tile-collection"), path)
	assert(not facet.ui:FindFirstChild("focus_beam"), path)
	print(`PASS {path}: current source, client bootstrap and upstream Compose modules`)
end
