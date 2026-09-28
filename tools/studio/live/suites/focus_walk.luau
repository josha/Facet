--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

local function pages(): { { id: string, tab: string? } }
	local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
	local scenarios = storage:WaitForChild("FacetScenarios")
	local out = {}
	for _, entry in screen.list() do
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
		local focus = (require :: any)(storage.FacetLive.focus)
		local layer = Players.LocalPlayer.PlayerGui:WaitForChild("FacetGallery")
		local only = shared.FacetFocusWalkOnly
		for _, page in pages() do
			local name = if page.tab then `{page.id}/{page.tab}` else page.id
			if only and not string.find(name, only, 1, true) then
				continue
			end
			api("show", page.id)
			t.settle(30)
			if page.tab then
				local group = string.split(page.tab, "/")[1]
				api("tab", group)
				t.settle(10)
				api("tab", page.tab)
				t.settle(30)
			end
			local lint = focus.lint(layer)
			t.check(`{name} lint`, #lint == 0, lint)
			local atlas = focus.atlas(layer, name)
			local stops = focus.stops(layer)
			atlas.moves.dpad = focus.walk(layer, stops, { "DPadDown", "DPadLeft", "DPadRight" })
			atlas.moves.stick = focus.walk(layer, stops, { "StickUp", "StickDown", "StickLeft", "StickRight" })
			atlas.moves.keys = focus.walk(layer, stops, { "Up", "Down", "Left", "Right" })
			local file = string
				.gsub(name, "/", "__")(require :: any)(storage.FacetLive)
				.save(file, HttpService:JSONEncode(atlas), "atlas")
			t.note(`{name} stops`, #stops)
		end
	end,
})

return cases
