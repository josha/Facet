--!strict

type LiveModule = typeof(require("@repo/tools/studio/live"))
type FocusModule = typeof(require("@repo/tools/studio/live/focus"))
local HttpService = game:GetService("HttpService")
local liveModule = game:GetService("ReplicatedStorage"):WaitForChild("FacetLive")
assert(liveModule:IsA("ModuleScript"), "FacetLive is not a ModuleScript")
local loadLive: (ModuleScript) -> LiveModule = require
local L = loadLive(liveModule)
local focusModule = liveModule:WaitForChild("focus")
assert(focusModule:IsA("ModuleScript"), "FacetLive.focus is not a ModuleScript")
local loadFocus: (ModuleScript) -> FocusModule = require
local focus = loadFocus(focusModule)
local api = workspace:WaitForChild("FacetLabAPI")
local function remote(name: string): BindableFunction
	local node = api:WaitForChild(name)
	assert(node:IsA("BindableFunction"), `FacetLabAPI.{name} is not a BindableFunction`)
	return node
end
local root = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Facet_Lab")
local options = shared.LabFocusWalk or {}
local summary = {}
local report = L.case("facet-lab", "focus-walk", function()
	for _, id in HttpService:JSONDecode(remote("pages"):Invoke()) do
		if options.only and not string.find(id, options.only, 1, true) then
			continue
		end
		remote("open"):Invoke(id)
		task.wait(1)
		local lint = focus.lint(root)
		focus.rest(root)
		local stops = focus.stops(root)
		local paths = focus.paths(root, stops)
		local atlas = focus.atlas(root, "lab/" .. id, stops, paths)
		atlas.lint = lint
		local function merge(family, moves, offsets, scenes)
			atlas.moves[family] = atlas.moves[family] or {}
			atlas.offsets[family] = atlas.offsets[family] or {}
			atlas.scenes[family] = atlas.scenes[family] or {}
			for path, row in moves do
				atlas.moves[family][path] = row
				atlas.offsets[family][path] = offsets[path]
				atlas.scenes[family][path] = scenes[path]
			end
		end
		merge("dpad", focus.walk(root, stops, paths, { "DPadDown", "DPadLeft", "DPadRight" }, atlas))
		if options.stick ~= false then
			merge("stick", focus.walk(root, stops, paths, { "StickUp", "StickDown", "StickLeft", "StickRight" }, atlas))
		end
		if options.up then
			local moves, offsets, scenes = L.signal("focus-upstream", function()
				return focus.walkUp(root, stops, paths, options.up, atlas)
			end)
			for path, target in moves do
				atlas.moves.dpad[path].DPadUp = target
				atlas.offsets.dpad[path].DPadUp = offsets[path]
				if scenes[path] then
					atlas.scenes.dpad[path] = atlas.scenes.dpad[path] or {}
					atlas.scenes.dpad[path].DPadUp = scenes[path]
				end
			end
		end
		L.save("lab--" .. string.gsub(id, "[^%w%-]", "_"), HttpService:JSONEncode(atlas), "live")
		table.insert(summary, `{id} stops={#stops} lint={#lint}`)
	end
end)
shared.LabFocusWalkDone = table.concat(summary, "\n")
return report
