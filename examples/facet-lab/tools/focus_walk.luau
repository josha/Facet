--!strict

type LiveModule = typeof(require("@repo/tools/studio/live"))
type FocusModule = typeof(require("@repo/tools/studio/live/focus"))
local HttpService = game:GetService("HttpService")
local liveModule = game:GetService("ReplicatedStorage"):WaitForChild("FacetLive") :: ModuleScript
local loadLive = require :: (ModuleScript) -> LiveModule
local L = loadLive(liveModule)
local loadFocus = require :: (ModuleScript) -> FocusModule
local focus = loadFocus(liveModule:WaitForChild("focus") :: ModuleScript)
local api = workspace:WaitForChild("FacetLabAPI")
local root = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Facet_Lab")
local options = shared.LabFocusWalk or {}
local summary = {}
local report = L.case("facet-lab", "focus-walk", function()
	for _, id in HttpService:JSONDecode((api:WaitForChild("pages") :: BindableFunction):Invoke()) do
		if options.only and not string.find(id, options.only, 1, true) then
			continue
		end
		(api:WaitForChild("open") :: BindableFunction):Invoke(id)
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
			local moves, offsets = L.signal("focus-upstream", function()
				return focus.walkUp(root, stops, paths, options.up)
			end)
			for path, target in moves do
				atlas.moves.dpad[path].DPadUp = target
				atlas.offsets.dpad[path].DPadUp = offsets[path]
			end
		end
		L.save("lab--" .. string.gsub(id, "[^%w%-]", "_"), HttpService:JSONEncode(atlas), "live")
		table.insert(summary, `{id} stops={#stops} lint={#lint}`)
	end
end)
shared.LabFocusWalkDone = table.concat(summary, "\n")
return report
