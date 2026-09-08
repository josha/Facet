--!strict
-- The gallery has one executable bootstrap: a Client-context Script in
-- ReplicatedStorage. Starter containers must not contain another copy.
-- https://create.roblox.com/docs/scripting/locations
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local failed = false
for _, path in process.args do
	local game = roblox.deserializePlace(fs.readFile(path))
	local gallery = game:GetService("ReplicatedStorage"):FindFirstChild("Gallery")
	local scripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local duplicate = scripts and scripts:FindFirstChild("Gallery")
	if
		gallery == nil
		or gallery.ClassName ~= "Script"
		or gallery.RunContext ~= roblox.Enum.RunContext.Client
		or duplicate ~= nil
	then
		print(`FAIL {path}: requires one ReplicatedStorage.Gallery Script with RunContext Client and no starter copy`)
		failed = true
	else
		print(`ok   {path}: one client-context Gallery Script in ReplicatedStorage`)
	end
end
process.exit(if failed then 1 else 0)
