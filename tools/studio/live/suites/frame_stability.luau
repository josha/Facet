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
local clipping = (require :: (Instance) -> typeof(require("../text_clipping")))(storage.FacetLive.text_clipping)
type Sample = { path: string, rect: { number }, text: { number }?, painted: boolean }
type Readable<T> = { peek: (Readable<T>) -> T }
type Context = {
	dispatch: (string, unknown) -> unknown,
	active: Readable<string?>,
	errorMessage: Readable<string?>,
}
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
	attach: (string, unknown) -> (),
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

local function masked(node: Instance): boolean
	local gradient = node:FindFirstChildWhichIsA("UIGradient")
	if gradient and gradient:GetStyled("Enabled") then
		for _, point in (gradient:GetStyled("Transparency") :: NumberSequence).Keypoints do
			if point.Value < 1 then
				return false
			end
		end
		return true
	end
	return false
end

local function visible(node: GuiObject, root: Instance): boolean
	if node.AbsoluteSize.X <= 0 or node.AbsoluteSize.Y <= 0 then
		return false
	end
	local at: Instance? = node
	local low, high = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
	while at do
		if at:IsA("GuiObject") then
			if
				not at:GetStyled("Visible")
				or (at:IsA("CanvasGroup") and (at:GetStyled("GroupTransparency") :: number) >= 1)
			then
				return false
			end
			if at:GetStyled("ClipsDescendants") then
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
			local paints = (node:GetStyled("BackgroundTransparency") :: number) < 1
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				paints = paints or ((node:GetStyled("TextTransparency") :: number) < 1 and node.Text ~= "")
			elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
				paints = paints or ((node:GetStyled("ImageTransparency") :: number) < 1 and node.Image ~= "")
			elseif node:IsA("ScrollingFrame") then
				paints = paints or node.ScrollBarThickness > 0
			end
			paints = paints and not masked(node)
			for _, decoration in node:GetChildren() do
				if
					decoration:IsA("UIStroke")
					and decoration:GetStyled("Enabled")
					and (decoration:GetStyled("Transparency") :: number) < 1
					and not masked(decoration)
				then
					paints = true
				end
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
				painted = paints,
			})
		end
	end
	return samples
end

type Trace = {
	observations: number,
	previous: { [string]: Sample },
	paths: { string },
	indices: { [string]: number },
	identities: { [Instance]: number },
	serial: { number },
}
local traces = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [T]: Trace }

local function observe(t: T, name: string, root: () -> GuiObject?, change: () -> (), negative: boolean?)
	local tracker = stability.new()
	local frames: { { { number } } } = {}
	local trace = traces[t]
	if trace == nil then
		trace = { observations = 0, previous = {}, paths = {}, indices = {}, identities = {}, serial = { 0 } }
		traces[t] = trace
	end
	local paths, indices, identities, serial = trace.paths, trace.indices, trace.identities, trace.serial
	trace.observations += 1
	local observation = trace.observations
	local previousState: { [Instance]: string } = {}
	local previousModel: { [Instance]: string } = {}
	local stateEvents: { { frame: number, path: string, before: string, after: string } } = {}
	local active = true
	local function sampleFrame()
		if not active then
			return
		end
		local stage = root()
		if stage then
			local currentState: { [Instance]: string } = {}
			local currentModel: { [Instance]: string } = {}
			local modelChanged = false
			for _, node in stage:GetDescendants() do
				local model = {}
				for _, attribute in { "value", "selected", "busy", "label", "ToastVisible" } do
					local value = node:GetAttribute(attribute)
					if value ~= nil then
						table.insert(model, `{attribute}={value}`)
					end
				end
				if #model > 0 then
					local state = table.concat(model, "|")
					currentModel[node] = state
					local before = previousModel[node]
					if before ~= nil and before ~= state then
						modelChanged = true
						table.insert(
							stateEvents,
							{ frame = tracker.frame + 1, path = node:GetFullName(), before = before, after = state }
						)
					end
				end
				local value, presented = node:GetAttribute("value"), node:GetAttribute("ToastVisible")
				local text = if (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
						and visible(node, stage)
						and (node:GetStyled("TextTransparency") :: number) < 1
						and not masked(node)
					then node.Text
					else nil
				if value ~= nil or presented ~= nil or text ~= nil then
					local state = `{value}|{presented}|{text}`
					currentState[node] = state
					local before = previousState[node]
					if before ~= nil and before ~= state then
						table.insert(
							stateEvents,
							{ frame = tracker.frame + 1, path = node:GetFullName(), before = before, after = state }
						)
					end
				end
			end
			previousState = currentState
			previousModel = currentModel
			if modelChanged then
				stability.stateChange(tracker)
			end
			local sample = snapshot(stage, identities, serial)
			local changes: { { number } } = {}
			local painted: { Sample } = {}
			local present: { [string]: boolean } = {}
			local encoded: { [string]: Sample } = {}
			for _, item in sample do
				if item.painted then
					table.insert(painted, item)
				end
				present[item.path] = true
				encoded[item.path] = item
				local id = indices[item.path]
				if id == nil then
					table.insert(paths, item.path)
					id = #paths
					indices[item.path] = id
				end
				local previous = trace.previous[item.path]
				local values = { id, item.rect[1], item.rect[2], item.rect[3], item.rect[4] }
				local changed = previous == nil or previous.painted ~= item.painted
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
					table.insert(values, if item.painted then 1 else 0)
					table.insert(changes, values)
				end
			end
			for path in trace.previous do
				if not present[path] then
					table.insert(changes, { indices[path] })
				end
			end
			trace.previous = encoded
			table.insert(frames, changes)
			stability.push(tracker, painted)
		end
	end
	local connection = RunService.PreRender:Connect(function()
		task.defer(sampleFrame)
	end)
	local ok, problem = pcall(function()
		change()
		repeat
			RunService.PreRender:Wait()
		until (tracker.quiet >= 30 and tracker.frame >= 60) or tracker.frame >= 600
	end)
	connection:Disconnect()
	active = false
	assert(ok, tostring(problem))
	local final = root()
	if final and not negative then
		local faults = clipping.inspect(final:FindFirstAncestorWhichIsA("LayerCollector") or final)
		t.check(name .. " settled text is not clipped", #faults == 0, faults)
	end
	t.check(name .. " records visible objects", tracker.seen > 0, tracker.seen)
	t.check(name .. " reaches 30 unchanged frames", tracker.quiet >= 30, tracker.frame)
	t.check(
		name .. " stable from first visible frame",
		if negative then #tracker.faults > 0 else #tracker.faults == 0,
		{ count = #tracker.faults, first = tracker.faults[1] }
	)
	t.note("geometry paths", paths)
	t.note(
		"frame trace encoding",
		"Deltas continue across observations. Rows contain path index, x, y, width, height, optional text width and height, and a paint flag. A one-value row removes a path. Empty frames repeat the previous frame. Transparent layout objects are recorded; geometry assertions use painted objects."
	)
	local frameParts: { string } = {}
	for first = 1, #frames, 30 do
		local part = `frames-{observation}-{first}.json`
		local changes = {}
		for index = first, math.min(#frames, first + 29) do
			table.insert(changes, frames[index])
		end
		t.attach(part, { firstFrame = first, changes = changes })
		table.insert(frameParts, part)
	end
	local faultParts: { string } = {}
	for first = 1, #tracker.faults, 1000 do
		local part = `faults-{observation}-{first}.json`
		local faults = {}
		for index = first, math.min(#tracker.faults, first + 999) do
			table.insert(faults, tracker.faults[index])
		end
		t.attach(part, faults)
		table.insert(faultParts, part)
	end
	t.note(name .. " frames", { count = #frames, attachments = frameParts })
	t.note(name .. " faults", { count = #tracker.faults, first = tracker.faults[1], attachments = faultParts })
	t.note(name .. " sample phase", "after render callbacks")
	t.note(name .. " state events", stateEvents)
	return tracker
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
add({
	id = "negative-late-resize-after-explicit-state-change",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local stage: GuiObject? = nil
		local late: Frame? = nil
		local tracker = observe(t, "state negative", function()
			return stage
		end, function()
			stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
				local frame = Host.Frame "Late" { Size = UDim2.fromOffset(100, 20) }
				frame:SetAttribute("value", 0)
				late = frame
				return late :: Frame
			end, { frames = 0 })
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			local frame = assert(late)
			frame:SetAttribute("value", 1)
			frame.Size = UDim2.fromOffset(120, 20)
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			frame.Size = UDim2.fromOffset(121, 20)
		end, true)
		t.check("state negative retains only the late resize", #tracker.faults == 1, tracker.faults)
		t.check(
			"state negative catches one pixel",
			tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1,
			tracker.faults
		)
		t.cleanup()
	end,
})
add({
	id = "negative-gradient-mask-does-not-hide-a-late-visible-resize",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local stage: GuiObject? = nil
		local fault: Frame? = nil
		local mask: UIGradient? = nil
		local tracker = observe(t, "gradient negative", function()
			return stage
		end, function()
			stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
				mask = Host.UIGradient { Transparency = NumberSequence.new(1) }
				fault = Host.Frame "Masked" { Size = UDim2.fromOffset(100, 20), mask :: UIGradient }
				return fault :: Frame
			end, { frames = 0 })
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			local frame, gradient = assert(fault), assert(mask)
			frame.Size = UDim2.fromOffset(101, 20)
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			gradient.Transparency = NumberSequence.new(0)
			RunService.PreRender:Wait()
			RunService.Heartbeat:Wait()
			frame.Size = UDim2.fromOffset(102, 20)
		end, true)
		t.check("only the visible resize fails", #tracker.faults == 1, tracker.faults)
		t.check(
			"the visible resize has one pixel delta",
			tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1,
			tracker.faults
		)
		t.cleanup()
	end,
})

local viewports = {
	{ name = "phone", width = 390, height = 844 },
	{ name = "tablet", width = 768, height = 1024 },
	{ name = "desktop", width = 1440, height = 900 },
}
add({
	id = "zstack-hugging-alignment",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local stage: GuiObject? = nil
		local pile: Frame? = nil
		observe(t, "hugging overlap", function()
			return stage
		end, function()
			stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
				local node = UI.ZStack "Overlap" {
					alignH = "end",
					alignV = "end",
					Host.Frame "Card" {
						Size = UDim2.fromOffset(60, 40),
					},
					Host.Frame "Dot" {
						Size = UDim2.fromOffset(16, 16),
					},
				}
				pile = node
				return node
			end, { frames = 0 })
		end)
		local node = assert(pile)
		t.check("overlap hugs its largest child", node.AbsoluteSize == Vector2.new(60, 40), node.AbsoluteSize)
		local dot = assert(node:FindFirstChild("Dot", true)) :: Frame
		t.check(
			"overlap aligns the smaller child",
			dot.AbsolutePosition - node.AbsolutePosition == Vector2.new(44, 24),
			dot.AbsolutePosition - node.AbsolutePosition
		)
		t.cleanup()
	end,
})
for _, viewport in viewports do
	for _, textSize in { "Medium", "Largest" } do
		add({
			id = `native-segment-caption/{viewport.name}/{textSize}`,
			contracts = {},
			keepGallery = false,
			run = function(t: T)
				local stage: GuiObject? = nil
				observe(t, "native segment caption", function()
					return stage
				end, function()
					stage = t.mount(function(UI: FacetControls, _Host: RobloxHost, Compose: ComposeModule)
						local picker = UI.Picker "CaptionEdges" {
							style = "segmented",
							selected = Compose.cell("a"),
							options = { { value = "a", label = "Device" }, { value = "b", label = "Theme" } },
						}
						for _, node in picker:GetDescendants() do
							if node:IsA("TextButton") and (node.Name == "a" or node.Name == "b") then
								local padding = assert(node:FindFirstChildWhichIsA("UIPadding"))
								padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 17), UDim.new(0, 19)
								padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 0), UDim.new(0, 0)
							end
						end
						return picker
					end, {
						frames = 0,
						size = Vector2.new(viewport.width, viewport.height),
						environment = { preferredTextSize = textSize },
					})
				end)
				for _, node in (stage :: GuiObject):GetDescendants() do
					if node:IsA("TextButton") and (node.Name == "a" or node.Name == "b") then
						t.check(
							`{node.Name} reserves caption and both padding edges`,
							node.AbsoluteSize.X + 0.5 >= node.TextBounds.X + 36,
							{
								size = node.AbsoluteSize,
								text = node.TextBounds,
							}
						)
						t.check(`{node.Name} keeps its whole caption`, node.TextFits, node.Text)
					end
				end
				t.cleanup()
			end,
		})
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
							UI.StatusIndicator "CustomCount" {
								count = 1,
								Size = UDim2.fromOffset(0, 36),
								Position = UDim2.fromOffset(16, 700),
							},
							UI.StatusIndicator "ScaledCount" {
								count = 1,
								Size = UDim2.new(0, 0, 0.05, 0),
								Position = UDim2.fromOffset(100, 700),
							},
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
					if node:IsA("GuiObject") and (node.Name == "CustomCount" or node.Name == "ScaledCount") then
						local floor = node:FindFirstChild("CountWidthFloor") :: Frame?
						if floor then
							t.note(
								"count width floor",
								{ size = floor.Size, styled = floor:GetStyled("Size"), actual = floor.AbsoluteSize }
							)
						end
						t.check(
							`{node.Name} single count is square`,
							math.abs(node.AbsoluteSize.X - node.AbsoluteSize.Y) <= 0.5,
							node.AbsoluteSize
						)
					end
				end
				table.sort(rows, function(a: GuiObject, b: GuiObject)
					return a.AbsolutePosition.Y < b.AbsolutePosition.Y
				end)
				t.check("three toast rows are mounted", #rows == 3, #rows)
				if #rows == 3 then
					local cap = math.min(560, viewport.width - 32)
					t.check("short hug uses its natural width", rows[1].AbsoluteSize.X < cap - 1, rows[1].AbsoluteSize)
					t.check(
						"long hug uses available width",
						math.abs(rows[2].AbsoluteSize.X - cap) <= 0.5,
						rows[2].AbsoluteSize
					)
				end
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
							local constraints: { { minimum: Vector2, maximum: Vector2, name: string } } = {}
							for _, child in text:GetChildren() do
								if child:IsA("UISizeConstraint") then
									table.insert(
										constraints,
										{ name = child.Name, minimum = child.MinSize, maximum = child.MaxSize }
									)
								end
							end
							t.note(`row {index} text layout`, {
								size = text.Size,
								styled = text:GetStyled("Size"),
								automatic = tostring(text:GetStyled("AutomaticSize")),
								constraints = constraints,
							})
							t.check(
								`row {index} fits message`,
								text.TextBounds.X <= text.AbsoluteSize.X + 0.5
									and math.abs(text.TextBounds.Y - text.AbsoluteSize.Y) <= 0.5,
								text.TextBounds
							)
						end
					end
				end
				local seconds = shared.FacetFrameStabilityCaptureSeconds
				if type(seconds) == "number" and seconds > 0 then
					local untilTime = os.clock() + seconds
					repeat
						RunService.PreRender:Wait()
					until os.clock() >= untilTime
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
					local loaded = assert(context)
					t.check(
						"requested page mounted",
						loaded.active:peek() == page.id and loaded.errorMessage:peek() == nil,
						{
							active = loaded.active:peek(),
							error = loaded.errorMessage:peek(),
						}
					)
					t.note("environment preferred text size", textSize)
					for _, node in (stage :: GuiObject):GetDescendants() do
						local parent = node.Parent
						if
							node:IsA("GuiObject")
							and node:GetAttribute("FacetPreparing") ~= nil
							and parent
							and parent:IsA("GuiObject")
							and visible(parent, stage :: GuiObject)
						then
							t.check(
								"layout preparation reveals " .. node:GetFullName(),
								node:GetAttribute("FacetPreparing") == false,
								node.AbsoluteSize
							)
						end
						if
							node:IsA("GuiObject")
							and node.Name == "Technique"
							and parent
							and parent:IsA("ScrollingFrame")
						then
							t.check(
								"ColorPicker technique fits the native scroll window",
								node.AbsoluteSize.X <= parent.AbsoluteWindowSize.X + 0.5,
								{
									size = node.AbsoluteSize,
									window = parent.AbsoluteWindowSize,
								}
							)
						end
						if node:IsA("GuiObject") and node.Name == "Values" and parent and parent.Name == "Readout" then
							local tallest = 0
							for _, child in node:GetChildren() do
								if child:IsA("GuiObject") then
									tallest = math.max(tallest, child.AbsoluteSize.Y)
								end
							end
							t.check(
								"ColorPicker readout reserves its tallest format",
								math.abs(node.AbsoluteSize.Y - tallest) <= 0.5,
								{
									size = node.AbsoluteSize,
									tallest = tallest,
								}
							)
						end
					end
					if page.id == "ex02" then
						local tracks = assert((stage :: GuiObject):FindFirstChild("Tracks", true))
						local header = assert(tracks:FindFirstChild("Header", true))
						local first = assert(tracks:FindFirstChild("neon", true))
						local row = assert(first:FindFirstChild("Row", true))
						for _, column in header:GetChildren() do
							if column:IsA("GuiObject") and column.Visible then
								local cell = assert(row:FindFirstChild(column.Name)) :: GuiObject
								t.check(
									"Playlist column aligns " .. column.Name,
									math.abs(cell.AbsolutePosition.X - column.AbsolutePosition.X) <= 0.5
										and math.abs(cell.AbsoluteSize.X - column.AbsoluteSize.X) <= 0.5,
									{
										header = { column.AbsolutePosition.X, column.AbsoluteSize.X },
										row = { cell.AbsolutePosition.X, cell.AbsoluteSize.X },
									}
								)
							end
						end
					end
					if shared.FacetFrameStabilityMountOnly == true then
						t.note("coverage", "mount only; interaction matrix not run")
						local seconds = shared.FacetFrameStabilityCaptureSeconds
						if type(seconds) == "number" and seconds > 0 then
							local untilTime = os.clock() + seconds
							repeat
								RunService.PreRender:Wait()
							until os.clock() >= untilTime
						end
						t.cleanup()
						return
					end
					local excluded: { [string]: boolean } = { Demos = true, Categories = true }
					if page.tab then
						excluded[string.split(page.tab, "/")[1]] = true
					end
					local function taskControl(node: Instance): boolean
						local at: Instance? = node
						while at do
							if at.Name == "Toolbar" then
								return false
							end
							if at.Name == "Tabs" then
								local view = at.Parent
								if view and view.Name == "TabBand" then
									view = view.Parent
								end
								if view and excluded[view.Name] then
									return false
								end
							end
							at = at.Parent
						end
						return true
					end
					local visited: { [string]: boolean } = {}
					local scrolled: { [string]: Vector2 } = {}
					local escapeTried = false
					while true do
						local target: GuiObject? = nil
						local overlayVisible = false
						for _, node in (stage :: GuiObject):GetDescendants() do
							local overlay = node:FindFirstAncestor("PreviewOverlays") ~= nil
							if overlay and node:IsA("GuiObject") and visible(node, stage :: GuiObject) then
								overlayVisible = true
							end
							if
								node:IsA("GuiObject")
								and not visited[node:GetFullName()]
								and visible(node, stage :: GuiObject)
								and taskControl(node)
								and (node.Selectable or node:IsA("GuiButton") or node:IsA("TextBox"))
							then
								if target == nil or overlay then
									target = node
								end
								if overlay then
									break
								end
							end
						end
						if target == nil then
							if overlayVisible and not escapeTried then
								escapeTried = true
								observe(t, "outside dismissal", root, function()
									local scene = assert(stage)
									local overlay = scene:FindFirstChild("PreviewOverlays", true)
									local surface = if overlay and overlay:IsA("GuiObject") then overlay else scene
									local point = surface.AbsolutePosition
										+ Vector2.new(2, 2)
										+ GuiService:GetGuiInset()
									virtual:SendMousePosition(point)
									virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
									virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
								end)
								continue
							end
							local advanced = false
							for _, candidate in (stage :: GuiObject):GetDescendants() do
								if
									candidate:IsA("ScrollingFrame")
									and candidate.ScrollingEnabled
									and visible(candidate, stage :: GuiObject)
									and taskControl(candidate)
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
						escapeTried = false
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
							if node:GetAttribute("value") ~= nil then
								for _, key in
									{ Enum.KeyCode.Right, Enum.KeyCode.Left, Enum.KeyCode.Up, Enum.KeyCode.Down }
								do
									observe(t, path .. " " .. key.Name, root, function()
										virtual:SendKey(true, key, false)
										virtual:SendKey(false, key, false)
									end)
								end
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
