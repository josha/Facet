--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")
type PageReport = { current: string?, demo: { active: string? }? }
type PageIdentity = (PageReport) -> string
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local pageIdentity = (require :: (ModuleScript) -> PageIdentity)(storage.FacetLive.focus_page :: ModuleScript)

type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
	input: string?,
}
local cases: { Case } = {}

local function api(command: string, argument: unknown): PageReport
	return (workspace:WaitForChild("FacetShowcaseAPI") :: BindableFunction):Invoke(command, argument)
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
	id = "focus-rest-tracks-targets-while-activity-runs",
	contracts = {},
	input = "pointer",
	run = function(t)
		local focus = (require :: (ModuleScript) -> typeof(require("../focus")))(storage.FacetLive.focus)
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame {
				Size = UDim2.fromScale(1, 1),
				UI.ProgressView "Activity" { Size = UDim2.fromOffset(280, 6) } :: unknown,
				UI.Button "Target" {
					label = "Continue",
					Position = UDim2.fromOffset(0, 60),
					Size = UDim2.fromOffset(160, 44),
				},
			}
		end, { motionLevel = "normal" })
		local fill = assert(t.find(stage, "Fill1"))
		local previous, moving = fill.AbsolutePosition, false
		local run = game:GetService("RunService")
		local activity = run.PreRender:Connect(function()
			local now = fill.AbsolutePosition
			moving = moving or now ~= previous
			previous = now
		end)
		local settled, detail = pcall(focus.settle, stage)
		activity:Disconnect()
		local scale = Instance.new("UIScale")
		scale.Parent = assert(t.find(stage, "Target"))
		local alternate = false
		local motion = run.PreRender:Connect(function()
			alternate = not alternate
			scale.Scale = if alternate then 0.99 else 1
		end)
		local unstable = pcall(focus.settle, stage)
		motion:Disconnect()
		scale:Destroy()
		local restored, restoredDetail = pcall(focus.settle, stage)
		t.check("activity art is moving during the focus rest check", moving)
		t.check("stable focus geometry settles while activity art moves", settled, detail)
		t.check("a moving focus target still fails the rest check", not unstable)
		t.check("the restored target settles again", restored, restoredDetail)
		t.cleanup()
	end,
})

local selection = shared.FacetFocusWalk or {}
for index, page in pages() do
	local name = if page.tab then `{page.id}/{page.tab}` else page.id
	if
		(selection.only and not string.find(name, selection.only, 1, true))
		or (selection.pages and not table.find(selection.pages, name))
		or index < (selection.start or 1)
	then
		continue
	end
	table.insert(cases, {
		id = `focus-walk/{name}`,
		contracts = {},
		input = if shared.FacetFocusWalk and shared.FacetFocusWalk.keys == true then "pointer" else "gamepad",
		run = function(t: any)
			local live = (require :: any)(storage.FacetLive)
			local focus = shared.FacetFocusRecorder or (require :: any)(storage.FacetLive.focus)
			local layer = (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):WaitForChild("FacetGallery")
			local options = shared.FacetFocusWalk or {}
			local prefix = if options.device then `{options.device}--` else ""
			api("device", options.device or "automatic")
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
			local identity = pageIdentity(api("report", nil))
			local function onPage(): boolean
				return pageIdentity(api("report", nil)) == identity
			end
			local lint = focus.lint(layer)
			t.check(`{name} lint`, #lint == 0, lint)
			local stops = focus.stops(layer)
			local paths = focus.paths(layer, stops)
			local atlas = if options.resumePaths then shared.FacetFocusAtlas else focus.atlas(layer, name, stops, paths)
			if options.resumePaths then
				assert(atlas and atlas.page == name, "focus walk resume atlas does not match the page")
				focus.adopt(layer, atlas)
			end
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
				merge(
					"keys",
					focus.walk(
						layer,
						stops,
						paths,
						{ "Up", "Down", "Left", "Right" },
						atlas,
						restore,
						options.resumePaths,
						onPage
					)
				)
				file ..= "--keys"
			else
				merge(
					"dpad",
					focus.walk(
						layer,
						stops,
						paths,
						{ "DPadDown", "DPadLeft", "DPadRight" },
						atlas,
						restore,
						options.resumePaths,
						onPage
					)
				)
				if options.stick ~= false then
					merge(
						"stick",
						focus.walk(
							layer,
							stops,
							paths,
							{ "StickUp", "StickDown", "StickLeft", "StickRight" },
							atlas,
							restore,
							options.resumePaths,
							onPage
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
		end,
	})
end

return cases
