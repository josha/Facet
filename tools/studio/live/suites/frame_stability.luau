--!strict
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type FrameNativeProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)
type StringPickerOption = typeof(require("@repo/tools/typecheck/aliases").StringPickerOption)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local storage = game:GetService("ReplicatedStorage")
local stability = (require :: (Instance) -> typeof(require("../frame_stability")))(storage.FacetLive.frame_stability)
local clipping = (require :: (Instance) -> typeof(require("../text_clipping")))(storage.FacetLive.text_clipping)
type Sample = { path: string, rect: { number }, text: { number }?, painted: boolean }
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Context = {
	dispatch: (string, unknown) -> unknown,
	active: ReadOnlyValue<string?>,
	errorMessage: ReadOnlyValue<string?>,
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
local QUIET_FRAMES = 12
local MINIMUM_FRAMES = 30
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

local function visiblePoint(node: GuiObject, root: Instance): Vector2?
	if node.AbsoluteSize.X <= 0 or node.AbsoluteSize.Y <= 0 then
		return nil
	end
	local at: Instance? = node
	local low, high = node.AbsolutePosition, node.AbsolutePosition + node.AbsoluteSize
	while at do
		if at:IsA("GuiObject") then
			if
				not at:GetStyled("Visible")
				or (at:IsA("CanvasGroup") and (at:GetStyled("GroupTransparency") :: number) >= 1)
			then
				return nil
			end
			if at:GetStyled("ClipsDescendants") then
				local position, ending = at.AbsolutePosition, at.AbsolutePosition + at.AbsoluteSize
				low = Vector2.new(math.max(low.X, position.X), math.max(low.Y, position.Y))
				high = Vector2.new(math.min(high.X, ending.X), math.min(high.Y, ending.Y))
				if low.X >= high.X or low.Y >= high.Y then
					return nil
				end
			end
		end
		if at == root then
			return (low + high) / 2
		end
		at = at.Parent
	end
	return nil
end

local function visible(node: GuiObject, root: Instance): boolean
	return visiblePoint(node, root) ~= nil
end

local function activate(node: GuiButton, point: Vector2)
	local keyboard = node.Selectable
	if keyboard then
		virtual:SendKey(true, Enum.KeyCode.Return, false)
	else
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, true)
	end
	for _ = 1, 2 do
		RunService.PreRender:Wait()
	end
	if keyboard then
		virtual:SendKey(false, Enum.KeyCode.Return, false)
	else
		virtual:SendMouseButton(point, Enum.UserInputType.MouseButton1, false)
	end
end

local function activityPaint(node: GuiObject): boolean
	local at: Instance? = node
	local fill = false
	while at do
		fill = fill or string.match(at.Name, "^Fill%d+$") ~= nil
		if at:HasTag("facet-progress-indeterminate") then
			return fill
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
			paints = paints and not activityPaint(node)
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
	local previousEnvironment: string? = nil
	local previousState: { [Instance]: string } = {}
	local previousModel: { [Instance]: string } = {}
	local stateEvents: { { frame: number, path: string, before: string, after: string } } = {}
	local active = true
	local buttons: { [GuiButton]: boolean } = {}
	local activations: { RBXScriptConnection } = {}
	local function sampleFrame()
		if not active then
			return
		end
		local stage = root()
		if stage then
			local inset, safeInset = GuiService:GetGuiInset()
			local camera = workspace.CurrentCamera
			local environment = {
				tostring(inset),
				tostring(safeInset),
				tostring(GuiService.TopbarInset),
				tostring(if camera then camera.ViewportSize else nil),
			}
			for _, layer in Players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren() do
				if layer:IsA("ScreenGui") and layer.Name == "CompositionTopbar" then
					table.insert(environment, tostring(layer.AbsoluteSize))
				end
			end
			local currentEnvironment = table.concat(environment, "|")
			if previousEnvironment ~= nil and previousEnvironment ~= currentEnvironment then
				table.insert(stateEvents, {
					frame = tracker.frame + 1,
					path = "native environment",
					before = previousEnvironment,
					after = currentEnvironment,
				})
			end
			previousEnvironment = currentEnvironment
			local currentState: { [Instance]: string } = {}
			local currentModel: { [Instance]: string } = {}
			local modelChanged = false
			for _, node in stage:GetDescendants() do
				if node:IsA("GuiButton") and not buttons[node] then
					buttons[node] = true
					table.insert(
						activations,
						node.Activated:Connect(function()
							stability.stateChange(tracker)
							table.insert(stateEvents, {
								frame = tracker.frame + 1,
								path = node:GetFullName(),
								before = "idle",
								after = "Activated",
							})
						end)
					)
				end
				local model = { `Visible={node:IsA("GuiObject") and node.Visible}` }
				for _, attribute in { "value", "selected", "busy", "label", "ToastVisible" } do
					local value = node:GetAttribute(attribute)
					if value ~= nil then
						table.insert(model, `{attribute}={value}`)
					end
				end
				if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
					table.insert(model, `Text={node.Text}`)
				end
				if node:IsA("ScrollingFrame") then
					table.insert(model, `CanvasPosition={node.CanvasPosition}`)
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
	local sampleError: string? = nil
	local connection = RunService.PreRender:Connect(function()
		task.defer(function()
			local ok, problem = xpcall(function()
				sampleFrame()
				return nil
			end, debug.traceback)
			if not ok then
				sampleError = tostring(problem)
				active = false
			end
		end)
	end)
	local ok, problem = pcall(function()
		change()
		repeat
			RunService.PreRender:Wait()
		until sampleError ~= nil
			or (tracker.quiet >= QUIET_FRAMES and tracker.frame >= MINIMUM_FRAMES)
			or tracker.frame >= 300
	end)
	connection:Disconnect()
	for _, activation in activations do
		activation:Disconnect()
	end
	active = false
	assert(ok, tostring(problem))
	assert(sampleError == nil, sampleError)
	local final = root()
	if final and not negative then
		local faults = clipping.inspect(final:FindFirstAncestorWhichIsA("LayerCollector") or final)
		t.check(name .. " settled text is not clipped", #faults == 0, faults)
	end
	t.check(name .. " records visible objects", tracker.seen > 0, tracker.seen)
	t.check(name .. ` reaches {QUIET_FRAMES} unchanged frames`, tracker.quiet >= QUIET_FRAMES, tracker.frame)
	t.check(
		name .. " stable from first visible frame",
		if negative then #tracker.faults > 0 else #tracker.faults == 0,
		{ count = #tracker.faults, first = tracker.faults[1] }
	)
	local failed = (if negative then #tracker.faults == 0 else #tracker.faults > 0) or tracker.quiet < QUIET_FRAMES
	if not failed then
		return tracker
	end
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

add({
	id = "native-pointer-only-clipped-target",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local activated = false
		local stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
			return Host.Frame "Clip" {
				Size = UDim2.fromOffset(60, 44),
				ClipsDescendants = true,
				Host.TextButton "PointerOnly" {
					Position = UDim2.fromOffset(40, 0),
					Size = UDim2.fromOffset(100, 44),
					Selectable = false,
					Text = "",
					Activated = function()
						activated = true
					end,
				},
			}
		end)
		local button = assert(stage:FindFirstChild("PointerOnly", true)) :: TextButton
		local point = assert(visiblePoint(button, stage)) + GuiService:GetGuiInset()
		observe(t, "clipped pointer activation", function()
			return stage
		end, function()
			virtual:SendMousePosition(point)
			activate(button, point)
		end)
		t.check("native pointer activation reaches the clipped nonselectable button", activated)
		t.cleanup()
	end,
})
for _, lateResize in { false, true } do
	add({
		id = if lateResize
			then "negative-indeterminate-progress-layout-resize"
			else "native-indeterminate-progress-layout",
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local progress: GuiObject? = nil
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
				progress = UI.ProgressView "Activity" { Size = UDim2.fromOffset(240, 6) }
				return Host.Frame {
					Size = UDim2.fromOffset(320, 60),
					progress :: GuiObject,
					Host.TextButton "Neighbour" {
						Position = UDim2.fromOffset(250, 0),
						Size = UDim2.fromOffset(60, 44),
						Text = "Next",
					},
				}
			end, { frames = 30 })
			local root = assert(progress)
			local fill = assert(root:FindFirstChild("Fill1", true)) :: Frame
			local before, moving = fill.AbsolutePosition, false
			local watch = RunService.PreRender:Connect(function()
				moving = moving or fill.AbsolutePosition ~= before
			end)
			local tracker = observe(t, "activity layout", function()
				return stage
			end, function()
				if lateResize then
					RunService.PreRender:Wait()
					RunService.Heartbeat:Wait()
					root.Size = UDim2.fromOffset(241, 6)
				end
			end, lateResize)
			watch:Disconnect()
			t.check("indeterminate paint keeps moving", moving)
			if lateResize then
				t.check(
					"activity does not hide its layout resize",
					tracker.faults[1] ~= nil and string.find(tracker.faults[1].path, "Activity", 1, true) ~= nil
				)
			end
			t.cleanup()
		end,
	})
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
	id = "negative-late-resize-after-native-activation",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local button: TextButton? = nil
		local activated = false
		local stage = t.mount(function(UI: FacetControls)
			button = UI.Button "Late" {
				label = "Continue",
				Size = UDim2.fromOffset(100, 44),
				AutomaticSize = Enum.AutomaticSize.None,
				onActivate = function()
					activated = true
					local node = assert(button)
					node.Size = UDim2.fromOffset(120, 44)
					task.defer(function()
						RunService.PreRender:Wait()
						RunService.Heartbeat:Wait()
						node.Size = UDim2.fromOffset(121, 44)
					end)
				end,
			}
			return assert(button)
		end, { frames = 20 })
		GuiService.SelectedObject = assert(button)
		local tracker = observe(t, "activation negative", function()
			return stage
		end, function()
			virtual:SendKey(true, Enum.KeyCode.Return, false)
			for _ = 1, 2 do
				RunService.PreRender:Wait()
			end
			virtual:SendKey(false, Enum.KeyCode.Return, false)
		end, true)
		t.check("native activation reaches the button", activated)
		t.check("activation negative retains only the late resize", #tracker.faults == 1, tracker.faults)
		t.check(
			"activation negative catches one pixel",
			tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1,
			tracker.faults
		)
		t.cleanup()
	end,
})
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
for _, lateResize in { false, true } do
	add({
		id = if lateResize then "negative-late-resize-after-text-change" else "native-text-change-starts-a-new-state",
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local stage: GuiObject? = nil
			local label: TextLabel? = nil
			local tracker = observe(t, "text state", function()
				return stage
			end, function()
				stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
					label = Host.TextLabel "Copy" {
						Size = UDim2.fromOffset(100, 24),
						Text = "A",
					}
					return label :: TextLabel
				end, { frames = 0 })
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				local node = assert(label)
				node.Text = "Different text"
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				if lateResize then
					node.Size = UDim2.fromOffset(101, 24)
				end
			end, lateResize)
			if lateResize then
				t.check("a text change does not hide the next frame resize", #tracker.faults == 1, tracker.faults)
				t.check(
					"the text state catches one pixel",
					tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1
				)
			end
			t.cleanup()
		end,
	})
end
for _, lateResize in { false, true } do
	add({
		id = if lateResize
			then "negative-late-resize-after-scroll-change"
			else "native-scroll-change-starts-a-new-state",
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local stage: GuiObject? = nil
			local scroller: ScrollingFrame? = nil
			local child: Frame? = nil
			local tracker = observe(t, "scroll state", function()
				return stage
			end, function()
				stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
					child = Host.Frame "Paint" {
						Size = UDim2.fromOffset(80, 20),
						Position = UDim2.fromOffset(30, 0),
					}
					scroller = Host.ScrollingFrame {
						Size = UDim2.fromOffset(100, 60),
						CanvasSize = UDim2.fromOffset(300, 60),
						ScrollingDirection = Enum.ScrollingDirection.X,
						ScrollBarThickness = 0,
						child :: Frame,
					}
					return scroller :: ScrollingFrame
				end, { frames = 0 })
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				assert(scroller).CanvasPosition = Vector2.new(20, 0)
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				if lateResize then
					assert(child).Size = UDim2.fromOffset(81, 20)
				end
			end, lateResize)
			if lateResize then
				t.check("a scroll change does not hide the next frame resize", #tracker.faults == 1, tracker.faults)
				t.check(
					"the scroll state catches one pixel",
					tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1
				)
			end
			t.cleanup()
		end,
	})
end
for _, lateResize in { false, true } do
	add({
		id = if lateResize
			then "negative-late-resize-after-visibility-change"
			else "native-visibility-change-starts-a-new-state",
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local stage: GuiObject? = nil
			local child: Frame? = nil
			local tracker = observe(t, "visibility state", function()
				return stage
			end, function()
				stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
					child = Host.Frame "Paint" {
						Size = UDim2.fromOffset(80, 20),
						Visible = false,
					}
					return Host.Frame { BackgroundTransparency = 1, child :: Frame }
				end, { frames = 0 })
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				assert(child).Visible = true
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				if lateResize then
					assert(child).Size = UDim2.fromOffset(81, 20)
				end
			end, lateResize)
			if lateResize then
				t.check("a visibility change does not hide the next frame resize", #tracker.faults == 1, tracker.faults)
				t.check(
					"the visibility state catches one pixel",
					tracker.faults[1] ~= nil and tracker.faults[1].delta[3] == 1
				)
			end
			t.cleanup()
		end,
	})
end
add({
	id = "native-notice-insertion-keeps-first-visible-neighbours",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local show: (() -> ())? = nil
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
			local shown = Compose.cell(false)
			show = function()
				shown:set(true)
			end
			return Host.Frame {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 16) } :: unknown,
				UI.Text { text = "Updates", textRole = "heading", LayoutOrder = 1 } :: unknown,
				Compose.show(shown, function()
					return UI.Notice "Update" {
						LayoutOrder = 2,
						appearance = "emphasis",
						title = "Update available",
						message = "A new track pack is ready to install.",
						link = { label = "Release notes", onActivate = function() end },
						actions = { { id = "Install", label = "Install", onActivate = function() end } },
						onDismiss = function() end,
					}
				end),
				UI.Button "Below" { label = "Continue", LayoutOrder = 3 },
			}
		end, { size = Vector2.new(768, 1024), environment = { preferredTextSize = "Largest" }, frames = 60 })
		observe(t, "notice insertion", function()
			return stage
		end, assert(show))
		local notice = assert(stage:FindFirstChild("Update", true)) :: Frame
		local action = assert(notice:FindFirstChild("Install", true)) :: GuiObject
		t.check("the prepared notice is visible", visible(notice, stage))
		t.check("the notice action is visible and selectable", visible(action, stage) and action.Selectable)
		t.check("the notice has its full content height", notice.AbsoluteSize.Y > 44, notice.AbsoluteSize)
		t.cleanup()
	end,
})

for _, textSize in { "Medium", "Largest" } do
	add({
		id = "native-calendar-first-visible-glyphs/" .. textSize,
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local show: (() -> ())? = nil
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
				local shown = Compose.cell(false)
				show = function()
					shown:set(true)
				end
				return Host.Frame {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(24, 24),
					Size = UDim2.fromOffset(360, 100),
					UI.DateTimePicker "Date" {
						label = "Race day",
						value = { year = 2026, month = 10, day = 17 },
						isPresented = shown,
						onPresentedChange = function(value: boolean)
							shown:set(value)
						end,
						onChange = function() end,
					},
				}
			end, { size = Vector2.new(768, 1024), environment = { preferredTextSize = textSize }, frames = 60 })
			observe(t, "calendar insertion", function()
				return stage
			end, assert(show))
			local surface = assert(stage:FindFirstChild("CalendarSurface", true)) :: GuiObject
			t.check("the prepared calendar is visible", visible(surface, stage))
			local days = 0
			for _, node in surface:GetDescendants() do
				if node:IsA("TextLabel") and node.Name == "Day" and visible(node, stage) then
					days += 1
				end
			end
			t.check("the calendar paints its day grid", days >= 28, days)
			t.cleanup()
		end,
	})
	add({
		id = "native-calendar-time-validation-placement/" .. textSize,
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
				return Host.Frame {
					Position = UDim2.fromOffset(24, 900),
					Size = UDim2.fromOffset(360, 100),
					UI.DateTimePicker "Date" {
						label = "Starts",
						value = { year = 2026, month = 10, day = 17, hour = 12, minute = 30 },
						onChange = function() end,
						time = true,
						isPresented = Compose.cell(true),
					},
				}
			end, { size = Vector2.new(768, 1024), environment = { preferredTextSize = textSize }, frames = 60 })
			local surface = assert(stage:FindFirstChild("CalendarSurface", true))
			local hour = assert(surface:FindFirstChild("Hour", true))
			local field = assert(hour:FindFirstChild("Field", true)) :: TextBox
			local live = (require :: (ModuleScript) -> { press: ({ string }, number?) -> string })(
				game:GetService("ReplicatedStorage").FacetLive :: ModuleScript
			)
			observe(t, "calendar time validation", function()
				return stage
			end, function()
				field:CaptureFocus()
				field.Text = "invalid"
				live.press({ "Return" })
			end)
			local validation = assert(hour:FindFirstChild("Validation", true)) :: TextLabel
			t.check("the calendar shows the invalid time message", validation.Text ~= "" and visible(validation, stage))
			t.cleanup()
		end,
	})
end

add({
	id = "negative-native-sample-errors-fail-the-observation",
	contracts = {},
	keepGallery = false,
	run = function(t: T)
		local stage = t.mount(function(_UI: FacetControls, Host: RobloxHost)
			return Host.Frame { Size = UDim2.fromOffset(80, 20) }
		end, { frames = 0 })
		local samples = 0
		local ok, problem = pcall(function()
			observe(t, "sample failure", function()
				samples += 1
				if samples == 2 then
					error("native sample failure")
				end
				return stage
			end, function() end)
		end)
		t.check(
			"a native sample error fails the observation",
			not ok and string.find(tostring(problem), "native sample failure", 1, true) ~= nil
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
	add({
		id = `live-readouts-keep-neighbours/{viewport.name}`,
		contracts = {},
		keepGallery = false,
		run = function(t: T)
			local update: ((string, number, number) -> ())? = nil
			local rows: { { readout: GuiObject, neighbour: GuiObject } } = {}
			t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
				local words, progress = Compose.cell("88888"), Compose.cell(1)
				local now = 1
				update = function(text: string, value: number, at: number)
					words:set(text)
					progress:set(value)
					now = at
				end
				local children: { Instance } = {}
				for index, control in
					{
						UI.Text { text = words },
						UI.Timer {
							deadline = 6000,
							now = function(): number
								return now
							end,
						},
						UI.ProgressView { value = progress, showValue = true, endLabel = "ready" },
						UI.Badge { label = words },
					}
				do
					local neighbour = Host.Frame "Neighbour" { Size = UDim2.fromOffset(20, 20) }
					control.LayoutOrder, neighbour.LayoutOrder = 1, 2
					table.insert(rows, { readout = control, neighbour = neighbour :: GuiObject })
					table.insert(
						children,
						Host.Frame({
							Position = UDim2.fromOffset(0, (index - 1) * 60),
							AutomaticSize = Enum.AutomaticSize.XY,
							Size = UDim2.fromOffset(0, 0),
							Host.UIListLayout {
								FillDirection = Enum.FillDirection.Horizontal,
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							control,
							neighbour,
						} :: FrameNativeProps)
					)
				end
				return Host.Frame { Size = UDim2.fromScale(1, 1), table.unpack(children) }
			end, { size = Vector2.new(viewport.width, viewport.height), frames = 30 })
			local value = assert(rows[3].readout:FindFirstChild("Value", true)) :: TextLabel
			local ending = assert(rows[3].readout:FindFirstChild("EndLabel", true)) :: TextLabel
			table.insert(rows, { readout = value :: GuiObject, neighbour = ending :: GuiObject })
			local boxes: { { size: Vector2, position: Vector2 } } = {}
			for index, row in rows do
				boxes[index] = { size = row.readout.AbsoluteSize, position = row.neighbour.AbsolutePosition }
				if row.readout:IsA("TextLabel") then
					t.check(`readout {index} fits its initial text`, row.readout.TextFits, row.readout.TextBounds)
				end
			end
			local function texts(): { string }
				local out: { string } = {}
				for index, row in rows do
					out[index] = if row.readout:IsA("TextLabel") then row.readout.Text else ""
				end
				return out
			end
			for _, value in { "11111", "12345", "1", "111", "88888", "9" } do
				local before = texts()
				local faults: { [number]: { frame: number, size: Vector2, position: Vector2 } } = {}
				assert(update)(value, 0.09, 5999)
				RunService.PreRender:Wait()
				RunService.Heartbeat:Wait()
				local after = texts()
				local settled: { { size: Vector2, position: Vector2 } } = {}
				for index, row in rows do
					local sameLength = utf8.len(before[index]) == utf8.len(after[index])
					settled[index] = { size = row.readout.AbsoluteSize, position = row.neighbour.AbsolutePosition }
					if sameLength and settled[index].size ~= boxes[index].size then
						faults[index] = { frame = 1, size = settled[index].size, position = settled[index].position }
					end
				end
				for frame = 2, 30 do
					RunService.PreRender:Wait()
					RunService.Heartbeat:Wait()
					for index, row in rows do
						if
							faults[index] == nil
							and (
								row.readout.AbsoluteSize ~= settled[index].size
								or row.neighbour.AbsolutePosition ~= settled[index].position
							)
						then
							faults[index] = {
								frame = frame,
								size = row.readout.AbsoluteSize,
								position = row.neighbour.AbsolutePosition,
							}
						end
					end
				end
				for index in rows do
					t.check(
						`readout {index} keeps a same-length box and settles in one frame for {value}`,
						faults[index] == nil,
						faults[index]
					)
					boxes[index] = settled[index]
				end
			end
			t.check("text updates while its box stays reserved", (rows[1].readout :: TextLabel).Text == "9")
			t.check("timer updates while its box stays reserved", (rows[2].readout :: TextLabel).Text == "0:01")
			t.check("badge updates while its box stays reserved", (rows[4].readout :: TextLabel).Text == "9")
			t.check("progress updates while its box stays reserved", value.Text == "9%")
			t.cleanup()
		end,
	})
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
						local options: { StringPickerOption } = {
							{ value = "a", label = "Device" },
							{ value = "b", label = "Theme" },
						}
						local picker = UI.Picker "CaptionEdges" {
							style = "segmented",
							selected = Compose.cell("a"),
							options = options,
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
				t.cleanup()
			end,
		})
	end
end
local combos = {
	{ viewport = viewports[3], textSize = "Medium" },
	{ viewport = viewports[1], textSize = "Largest" },
}
for _, page in pages() do
	for _, combo in combos do
		local viewport, textSize = combo.viewport, combo.textSize
		add({
			id = `{page.id}/{page.tab or "root"}/{viewport.name}/{textSize}`,
			contracts = {},
			keepGallery = false,
			run = function(t: T)
				local stage: GuiObject? = nil
				local context: Context? = nil
				observe(t, "mount", function(): GuiObject?
					return stage
				end, function()
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
				local loaded = assert(context)
				t.check(
					"requested page mounted",
					loaded.active:peek() == page.id and loaded.errorMessage:peek() == nil,
					{
						active = loaded.active:peek(),
						error = loaded.errorMessage:peek(),
					}
				)
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
								visible = visible(node, stage :: GuiObject),
								path = node:GetFullName(),
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
				t.cleanup()
			end,
		})
	end
end

return cases
