--[[ check_place_bootstrap: the gallery bootstrap in a built place must be a LocalScript.

	`examples/gallery/client/init.client.luau` mounts the whole showcase. Built as a
	RunContext=Client `Script` (emitLegacyScripts=false) it runs TWICE — once from
	StarterPlayerScripts and once from the PlayerScripts copy — so every place
	booted two hosts, two chromes and two copies of the first demo, and picking a
	new demo replaced only one of them (measured live 2026-09-07: two
	`Facet_ShowcaseBackdrop` ScreenGuis in PlayerGui). The checked-in project
	files say `emitLegacyScripts: true`; `tools/build_places.sh` writes its OWN
	project heredocs, which is where the flag was still `false`. This refuses to
	let a build ship that shape again, whichever file it comes from.

	Usage: lune run tools/lune/check_place_bootstrap.luau <place.rbxl>...
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local failed = false
for _, path in process.args do
	local game = roblox.deserializePlace(fs.readFile(path))
	local scripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local gallery = scripts and scripts:FindFirstChild("Gallery")
	if gallery == nil then
		print(`FAIL {path}: no StarterPlayerScripts.Gallery`)
		failed = true
	elseif gallery.ClassName ~= "LocalScript" then
		print(`FAIL {path}: Gallery is a {gallery.ClassName}, must be a LocalScript (boots twice otherwise)`)
		failed = true
	else
		print(`ok   {path}: Gallery is a LocalScript`)
	end
end
process.exit(if failed then 1 else 0)
