local HttpService = game:GetService("HttpService")
local L = require(game.ReplicatedStorage.FacetLive)
local focus = require(game.ReplicatedStorage.FacetLive.focus)
local api = workspace:WaitForChild("FacetLabAPI")
local root = game.Players.LocalPlayer.PlayerGui:WaitForChild("Facet_Lab")
local options = shared.LabFocusWalk or {}
local summary = {}
for _, id in HttpService:JSONDecode(api.pages:Invoke()) do
	if options.only and not string.find(id, options.only, 1, true) then
		continue
	end
	api.open:Invoke(id)
	task.wait(1)
	local lint = focus.lint(root)
	focus.rest(root)
	local stops = focus.stops(root)
	local paths = focus.paths(root, stops)
	local atlas = focus.atlas(root, "lab/" .. id, stops, paths)
	atlas.lint = lint
	local function merge(family, moves, offsets)
		atlas.moves[family] = atlas.moves[family] or {}
		atlas.offsets[family] = atlas.offsets[family] or {}
		for path, row in moves do
			atlas.moves[family][path] = row
			atlas.offsets[family][path] = offsets[path]
		end
	end
	merge("dpad", focus.walk(root, stops, paths, { "DPadDown", "DPadLeft", "DPadRight" }))
	if options.stick ~= false then
		merge("stick", focus.walk(root, stops, paths, { "StickUp", "StickDown", "StickLeft", "StickRight" }))
	end
	if options.up then
		L.save("focus-upstream", '"on"')
		local moves, offsets = focus.walkUp(root, stops, paths, options.up)
		L.save("focus-upstream", '"off"')
		for path, target in moves do
			atlas.moves.dpad[path].DPadUp = target
			atlas.offsets.dpad[path].DPadUp = offsets[path]
		end
	end
	L.save("lab--" .. string.gsub(id, "[^%w%-]", "_"), HttpService:JSONEncode(atlas), "live")
	table.insert(summary, `{id} stops={#stops} lint={#lint}`)
end
shared.LabFocusWalkDone = table.concat(summary, "\n")
return shared.LabFocusWalkDone
