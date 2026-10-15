--!strict
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type FrameNativeProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")
local stability = (require :: (Instance) -> typeof(require("../frame_stability")))(storage.FacetLive.frame_stability)
type Sample = { path: string, rect: { number }, text: { number }? }
type Context = { dispatch: (string, unknown) -> unknown }
type Config = {
	frames: number?,
	size: Vector2?,
	demo: string?,
	preferredTextSize: string?,
	environment: { preferredTextSize: string }?,
}
type T = {
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	cleanup: () -> (),
	mount: ((FacetControls, RobloxHost, ComposeModule) -> Instance, Config?) -> GuiObject,
	gallery: (Config) -> (GuiObject, Context),
}
type Page = { id: string, tab: string? }
type Entry = { id: string, kind: string, module: string }
type Fixture = { groups: { { id: string, tabs: { { id: string } } } }? }
type Virtual = {
	SendMousePosition: (Virtual, Vector2) -> (),
	SendMouseButton: (Virtual, Vector2, Enum.UserInputType, boolean) -> (),
	SendKey: (Virtual, boolean, Enum.KeyCode, boolean) -> (),
}
local virtual = ((game:GetService("UserInputService") :: unknown) :: { CreateVirtualInput: (unknown) -> Virtual }):CreateVirtualInput()

local function visible(node: GuiObject, root: Instance): boolean
	if node.AbsoluteSize.X <= 0 or node.AbsoluteSize.Y <= 0 then
		return false
	end
	local at: Instance? = node
	local low, high = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
	while at do
		if at:IsA("GuiObject") then
			if not at.Visible or (at:IsA("CanvasGroup") and at.GroupTransparency >= 1) then
				return false
			end
			if at.ClipsDescendants then
				local position, ending = at.AbsolutePosition, at.AbsolutePosition + at.AbsoluteSize
				low = Vector2.new(math.max(low.X, position.X), math.max(low.Y, position.Y))
				high = Vector2.new(math.min(high.X, ending.X), math.min(high.Y, ending.Y))
				if low.X >= high.X or low.Y >= high.Y then
					return false
				end
			end
		end
		if at == root then
			return true
		end
		at = at.Parent
	end
	return false
end

local function snapshot(root: GuiObject, identities: { [Instance]: number }, serial: { number }): { Sample }
	local samples: { Sample } = {}
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in nodes do
		if node:IsA("GuiObject") and visible(node, root) then
			local paints = node.BackgroundTransparency < 1
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				paints = paints or (node.TextTransparency < 1 and node.Text ~= "")
			elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
				paints = paints or (node.ImageTransparency < 1 and node.Image ~= "")
			elseif node:IsA("ScrollingFrame") then
				paints = paints or node.ScrollBarThickness > 0
			end
			if not paints then
				continue
			end
			if identities[node] == nil then
				serial[1] += 1
				identities[node] = serial[1]
			end
			local position, size = node.AbsolutePosition, node.AbsoluteSize
			local text = if node:IsA("TextLabel")
					or node:IsA("TextButton")
					or node:IsA("TextBox")
				then { node.TextBounds.X, node.TextBounds.Y }
				else nil
			table.insert(samples, {
				path = `{node:GetFullName()}#{identities[node]}`,
				rect = { position.X, position.Y, size.X, size.Y },
				text = text,
			})
		end
	end
	return samples
end

local function observe(t: T, name: string, root: () -> GuiObject?, change: () -> (), negative: boolean?)
	local tracker = stability.new()
	local frames: { { { number } } } = {}
	local paths: { string } = {}
	local indices: { [string]: number } = {}
	local identities: { [Instance]: number } = {}
	local serial = { 0 }
	local connection = RunService.PreRender:Connect(function()
		local stage = root()
		if stage then
			local sample = snapshot(stage, identities, serial)
			local changes: { { number } } = {}
			local present: { [string]: boolean } = {}
			for _, item in sample do
				present[item.path] = true
				local id = indices[item.path]
				if id == nil then
					table.insert(paths, item.path)
					id = #paths
					indices[item.path] = id
				end
				local previous = tracker.previous[item.path]
				local values = { id, item.rect[1], item.rect[2], item.rect[3], item.rect[4] }
				local changed = previous == nil
				for index, value in item.rect do
					changed = changed or previous == nil or previous.rect[index] ~= value
				end
				if item.text then
					table.insert(values, item.text[1])
					table.insert(values, item.text[2])
					local before = if previous then previous.text else nil
					changed = changed or before == nil or before[1] ~= item.text[1] or before[2] ~= item.text[2]
				end
				if changed then
					table.insert(changes, values)
				end
			end
			for path in tracker.previous do
				if not present[path] then
					table.insert(changes, { indices[path] })
				end
			end
			table.insert(frames, changes)
			stability.push(tracker, sample)
		end
	end)
	local ok, problem = pcall(function()
		change()
		repeat
			RunService.PreRender:Wait()
		until (tracker.quiet >= 30 and tracker.frame >= 60) or tracker.frame >= 600
	end)
	connection:Disconnect()
	assert(ok, tostring(problem))
	t.check(name .. " records visible objects", tracker.seen > 0, tracker.seen)
	t.check(name .. " reaches 30 unchanged frames", tracker.quiet >= 30, tracker.frame)
	t.check(
		name .. " stable from first visible frame",
		if negative then #tracker.faults > 0 else #tracker.faults == 0,
		tracker.faults
	)
	t.note(name .. " frames", { paths = paths, changes = frames })
	t.note(name .. " faults", tracker.faults)
end

local function pages(): { Page }
	local screen = (require :: (Instance) -> { list: () -> { Entry } })(
		storage:WaitForChild("Gallery"):WaitForChild("screen")
	)
	local listed = screen.list()
	local added = workspace:GetAttribute("Facet_Demos")
	if type(added) == "string" then
		for _, entry in HttpService:JSONDecode(added) :: { Entry } do
			table.insert(listed, entry)
		end
	end
	local out: { Page } = {}
	for _, entry in listed do
		local module = if entry.kind == "fixture" then storage.FacetScenarios:FindFirstChild(entry.module) else nil
		local fixture = if module then (require :: (Instance) -> Fixture)(module) else nil
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

type Case = { id: string, contracts: { string }, keepGallery: boolean, run: (T) -> () }
local cases: { Case } = {}
local function add(case: Case)
	table.insert(cases, case)
end
local negative: Case = {
	id = "negative-one-frame-late-resize",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local stage: GuiObject? = nil
		local late: Frame? = nil
		observe(t, "negative", function()
			return stage
		end, function()
			stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
				late = Host.Frame "Late" { Size = UDim2.fromOffset(100, 20) }
				return late :: Frame
			end, { frames = 0 })
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			local frame = assert(late)
			frame.Size = UDim2.fromOffset(101, 20)
		end, true)
		t.cleanup()
	end,
}
add(negative)

local viewports = {
	{ name = "phone", width = 390, height = 844 },
	{ name = "tablet", width = 768, height = 1024 },
	{ name = "desktop", width = 1440, height = 900 },
}
for _, viewport in viewports do
	for _, textSize in { "Medium", "Largest" } do
		add({
			id = `native-feedback/{viewport.name}/{textSize}`,
			contracts = {},
			keepGallery = false,
			run = function(t: T)
				local stage: GuiObject? = nil
				observe(t, "native feedback", function()
					return stage
				end, function()
					stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
						local properties: FrameNativeProps = {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							UI.Toast { message = "Saved", width = "hug", duration = 3600 },
							UI.Toast {
								message = "Your changes are saved. You can continue with the next task or review the collection before leaving.",
								width = "hug",
								duration = 3600,
							},
							UI.Toast { message = "Collection ready", duration = 3600 },
							UI.Card {
								title = "Native aspect",
								Size = UDim2.fromOffset(320, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Position = UDim2.fromOffset(16, 400),
								artwork = function(): GuiObject
									return Host.Frame { BackgroundTransparency = 1 }
								end,
							},
						}
						return Host.Frame(properties)
					end, {
						frames = 0,
						size = Vector2.new(viewport.width, viewport.height),
						environment = { preferredTextSize = textSize },
					})
				end)
				local rows: { GuiObject } = {}
				for _, node in (stage :: GuiObject):GetDescendants() do
					if node:IsA("GuiObject") and node.Name == "ToastRow" then
						table.insert(rows, node)
					end
					if node:IsA("GuiObject") and node.Name == "Artwork" then
						t.check(
							"artwork keeps native aspect",
							math.abs(node.AbsoluteSize.X / node.AbsoluteSize.Y - 16 / 9) < 0.01,
							node.AbsoluteSize
						)
					end
				end
				table.sort(rows, function(a: GuiObject, b: GuiObject)
					return a.AbsolutePosition.Y < b.AbsolutePosition.Y
				end)
				t.check("three toast rows are mounted", #rows == 3, #rows)
				for index, row in rows do
					t.check(
						`row {index} stays within presentation width`,
						row.AbsoluteSize.X <= viewport.width - 32 + 0.5,
						row.AbsoluteSize
					)
					if index > 1 then
						local previous = rows[index - 1]
						local gap = row.AbsolutePosition.Y - previous.AbsolutePosition.Y - previous.AbsoluteSize.Y
						t.check(`row {index} has native stack spacing`, math.abs(gap - 8) <= 0.5, gap)
					end
					for _, text in row:GetDescendants() do
						if text:IsA("TextLabel") and text.Name == "Message" then
							t.check(
								`row {index} fits message`,
								text.TextBounds.X <= text.AbsoluteSize.X + 0.5
									and text.TextBounds.Y <= text.AbsoluteSize.Y + 0.5,
								text.TextBounds
							)
						end
					end
				end
				t.cleanup()
			end,
		})
	end
end
for _, page in pages() do
	for _, viewport in viewports do
		for _, textSize in { "Medium", "Largest" } do
			local name = `{page.id}/{page.tab or "root"}/{viewport.name}/{textSize}`
			add({
				id = name,
				contracts = {},
				keepGallery = false,
				run = function(t: T)
					local stage: GuiObject? = nil
					local context: Context? = nil
					local function root(): GuiObject?
						return stage
					end
					observe(t, "mount", root, function()
						stage, context = t.gallery({
							size = Vector2.new(viewport.width, viewport.height),
							demo = page.id,
							frames = 0,
							preferredTextSize = textSize,
						})
						if page.tab then
							local active = assert(context)
							active.dispatch("tab", string.split(page.tab, "/")[1])
							active.dispatch("tab", page.tab)
						end
					end)
					t.note("native preferred text size", tostring(GuiService.PreferredTextSize))
					t.note("environment preferred text size", textSize)
					local visited: { [string]: boolean } = {}
					local scrolled: { [string]: Vector2 } = {}
					while true do
						local target: GuiObject? = nil
						for _, node in (stage :: GuiObject):GetDescendants() do
							if
								node:IsA("GuiObject")
								and not visited[node:GetFullName()]
								and visible(node, stage :: GuiObject)
								and node:FindFirstAncestor("Toolbar") == nil
								and (node.Selectable or node:IsA("GuiButton") or node:IsA("TextBox"))
							then
								target = node
								break
							end
						end
						if target == nil then
							local advanced = false
							for _, candidate in (stage :: GuiObject):GetDescendants() do
								if
									candidate:IsA("ScrollingFrame")
									and candidate.ScrollingEnabled
									and visible(candidate, stage :: GuiObject)
									and candidate:FindFirstAncestor("Toolbar") == nil
								then
									local path = candidate:GetFullName()
									local maximum = candidate.AbsoluteCanvasSize - candidate.AbsoluteWindowSize
									local before = scrolled[path] or Vector2.zero
									local step = candidate.AbsoluteWindowSize * 0.75
									local next = Vector2.new(
										math.min(math.max(0, maximum.X), before.X + math.max(1, step.X)),
										math.min(math.max(0, maximum.Y), before.Y + math.max(1, step.Y))
									)
									if next ~= before then
										scrolled[path] = next
										observe(t, path .. ` scroll {next}`, root, function()
											candidate.CanvasPosition = next
										end)
										advanced = true
										break
									end
								end
							end
							if advanced then
								continue
							end
							break
						end
						local node = target
						local path = node:GetFullName()
						visited[path] = true
						observe(t, path .. " select", root, function()
							GuiService.SelectedObject = node
						end)
						local point = node.AbsolutePosition + node.AbsoluteSize / 2 + GuiService:GetGuiInset()
						observe(t, path .. " hover", root, function()
							virtual:SendMousePosition(point)
						end)
						if node:IsA("TextBox") then
							observe(t, path .. " text", root, function()
								node.Text ..= " stability"
							end)
						else
							observe(t, path .. " activate", root, function()
								virtual:SendKey(true, Enum.KeyCode.Return, false)
								virtual:SendKey(false, Enum.KeyCode.Return, false)
							end)
							for _, key in { Enum.KeyCode.Right, Enum.KeyCode.Left, Enum.KeyCode.Escape } do
								observe(t, path .. " " .. key.Name, root, function()
									virtual:SendKey(true, key, false)
									virtual:SendKey(false, key, false)
								end)
							end
						end
					end
					t.cleanup()
				end,
			})
		end
	end
end

return cases
