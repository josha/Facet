--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

local function pages(): { { id: string, tab: string? } }
	local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
	local scenarios = storage:WaitForChild("FacetScenarios")
	local out: { { id: string, tab: string? } } = {}
	local listed = screen.list()
	local added = workspace:GetAttribute("Facet_Demos")
	if type(added) == "string" then
		for _, demo in HttpService:JSONDecode(added) do
			table.insert(listed, demo)
		end
	end
	for _, entry in listed do
		local module = if entry.kind == "fixture" then scenarios:FindFirstChild(entry.module) else nil
		local fixture = if module then (require :: any)(module) else nil
		if fixture and fixture.groups then
			for _, group in fixture.groups do
				for _, tab in group.tabs do
					table.insert(out, { id = entry.id, tab = `{group.id}/{tab.id}` })
				end
			end
		else
			table.insert(out, { id = entry.id })
		end
	end
	return out
end

table.insert(cases, {
	id = "focus-walk",
	contracts = {},
	run = function(t: any)
		local live = (require :: any)(storage.FacetLive)
		local focus = shared.FacetFocusRecorder or (require :: any)(storage.FacetLive.focus)
		local layer = (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):WaitForChild("FacetGallery")
		local options = shared.FacetFocusWalk or {}
		local prefix = if options.device then `{options.device}--` else ""
		api("device", options.device or "automatic")
		for index, page in pages() do
			local name = if page.tab then `{page.id}/{page.tab}` else page.id
			if
				(options.only and not string.find(name, options.only, 1, true))
				or (options.pages and not table.find(options.pages, name))
				or index < (options.start or 1)
			then
				continue
			end
			local function open()
				api("show", page.id)
				t.settle(30)
				if page.tab then
					local group = string.split(page.tab, "/")[1]
					api("tab", group)
					t.settle(10)
					api("tab", page.tab)
					t.settle(30)
				end
				focus.rest(layer)
				focus.settle(layer)
			end
			local function restore()
				game:GetService("GuiService").SelectedObject = nil
				api("show", if page.id == "hud" then "garage" else "hud")
				t.settle(10)
				open()
			end
			open()
			local lint = focus.lint(layer)
			t.check(`{name} lint`, #lint == 0, lint)
			local stops = focus.stops(layer)
			local paths = focus.paths(layer, stops)
			local atlas = focus.atlas(layer, name, stops, paths)
			local file = prefix .. string.gsub(name, "[^%w%-]", "_")
			local function merge(family: string, moves: any, offsets: any, scenes: any)
				atlas.moves[family] = atlas.moves[family] or {}
				atlas.offsets[family] = atlas.offsets[family] or {}
				atlas.scenes[family] = atlas.scenes[family] or {}
				for path, row in moves do
					atlas.moves[family][path] = row
					atlas.offsets[family][path] = offsets[path]
					atlas.scenes[family][path] = scenes[path]
				end
			end
			if options.keys then
				merge("keys", focus.walk(layer, stops, paths, { "Up", "Down", "Left", "Right" }, atlas, restore))
				file ..= "--keys"
			else
				merge("dpad", focus.walk(layer, stops, paths, { "DPadDown", "DPadLeft", "DPadRight" }, atlas, restore))
				if options.stick ~= false then
					merge(
						"stick",
						focus.walk(
							layer,
							stops,
							paths,
							{ "StickUp", "StickDown", "StickLeft", "StickRight" },
							atlas,
							restore
						)
					)
				end
				if options.up then
					local moves, offsets, scenes = live.signal("focus-upstream", function()
						return focus.walkUp(layer, stops, paths, options.up, atlas, restore)
					end)
					for path, target in moves do
						atlas.moves.dpad[path] = atlas.moves.dpad[path] or {}
						atlas.moves.dpad[path].DPadUp = target
						atlas.offsets.dpad[path].DPadUp = offsets[path]
						if scenes[path] then
							atlas.scenes.dpad[path] = atlas.scenes.dpad[path] or {}
							atlas.scenes.dpad[path].DPadUp = scenes[path]
						end
					end
				end
			end
			live.save(file, HttpService:JSONEncode(atlas), "atlas")
			t.note(`{name} stops`, #atlas.stops)
		end
	end,
})

return cases
