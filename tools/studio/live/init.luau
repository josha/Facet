--!strict
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")

local live = {}

local function round(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

local function encode(value: any): any
	local kind = typeof(value)
	if kind == "Vector2" then
		return { round(value.X), round(value.Y) }
	elseif kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "UDim" then
		return { value.Scale, value.Offset }
	elseif kind == "EnumItem" then
		return tostring(value)
	elseif kind == "number" then
		return round(value)
	elseif kind == "table" then
		local out = {}
		for key, item in value do
			out[key] = encode(item)
		end
		return out
	elseif kind == "Instance" then
		return value:GetFullName()
	end
	return value
end

local function themeModules(Facet: any): { { name: string, package: any } }
	local list = { { name = "Neutral", package = assert(Facet.themes.define(Facet.themes.neutralPackage())) } }
	local folder = storage:FindFirstChild("FacetThemes")
	local found = {}
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, definition = pcall(require, module)
				if
					ok
					and type(definition) == "table"
					and not definition.testOnly
					and type(definition.build) == "function"
				then
					local built, package = pcall(definition.build, Facet.themes)
					if built and package then
						table.insert(found, { name = module.Name, package = package })
					end
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.name < b.name
	end)
	for _, entry in found do
		table.insert(list, entry)
	end
	return list
end

local function environment(): { [string]: any }
	local camera = workspace.CurrentCamera
	local inset = GuiService:GetGuiInset()
	return {
		viewport = encode(camera.ViewportSize),
		guiInset = encode(inset),
		preferredTextSize = tostring(GuiService.PreferredTextSize),
		preferredTransparency = GuiService.PreferredTransparency,
		reducedMotion = GuiService.ReducedMotionEnabled,
		touch = game:GetService("UserInputService").TouchEnabled,
		studio = RunService:IsStudio(),
		version = version(),
		stamp = workspace:GetAttribute("Facet_SourceStamp"),
	}
end

local function newCase(Facet: any, themes: { any }, record: { [string]: any })
	local t = {}
	local cleanups: { () -> () } = {}
	t.Facet = Facet
	t.themes = themes
	t.environment = environment()
	function t.check(name: string, ok: boolean, detail: any?)
		table.insert(record.checks, { name = name, ok = ok == true, detail = encode(detail) })
	end
	function t.near(name: string, actual: number, expected: number, tolerance: number?)
		local margin = tolerance or 1
		t.check(
			name,
			math.abs(actual - expected) <= margin,
			{ actual = actual, expected = expected, tolerance = margin }
		)
	end
	function t.note(name: string, value: any)
		record.notes[name] = encode(value)
	end
	function t.settle(frames: number?)
		for _ = 1, frames or 6 do
			RunService.RenderStepped:Wait()
		end
	end
	function t.stable(node: any, frames: number?, limit: number?): number
		local last, calm, waited = nil, 0, 0
		while waited < (limit or 120) do
			RunService.RenderStepped:Wait()
			waited += 1
			local now = if node and node.Parent then `{node.AbsolutePosition}{node.AbsoluteSize}` else ""
			calm = if now == last then calm + 1 else 0
			last = now
			if calm >= (frames or 4) then
				break
			end
		end
		return waited
	end
	function t.find(root: Instance, name: string): any
		if root.Name == name then
			return root
		end
		return root:FindFirstChild(name, true)
	end
	function t.all(root: Instance, name: string): { any }
		local out = {}
		for _, node in root:GetDescendants() do
			if node.Name == name then
				table.insert(out, node)
			end
		end
		return out
	end
	function t.rect(node: any): { x: number, y: number, w: number, h: number, r: number, b: number }
		local at, size = node.AbsolutePosition, node.AbsoluteSize
		return { x = at.X, y = at.Y, w = size.X, h = size.Y, r = at.X + size.X, b = at.Y + size.Y }
	end
	function t.inside(name: string, inner: any, outer: any, tolerance: number?)
		local a = if typeof(inner) == "Instance" then t.rect(inner) else inner
		local b = if typeof(outer) == "Instance" then t.rect(outer) else outer
		local margin = tolerance or 0.5
		t.check(
			name,
			a.x >= b.x - margin and a.y >= b.y - margin and a.r <= b.r + margin and a.b <= b.b + margin,
			{ inner = { a.x, a.y, a.w, a.h }, outer = { b.x, b.y, b.w, b.h } }
		)
	end
	function t.fits(label: any): boolean
		local bounds, size = label.TextBounds, label.AbsoluteSize
		return label.ContentText ~= "" and bounds.X <= size.X + 0.5 and bounds.Y <= size.Y + 0.5
	end
	function t.visible(node: Instance): boolean
		local current: Instance? = node
		while current and current:IsA("GuiObject") do
			if not current.Visible then
				return false
			end
			current = current.Parent
		end
		if current and current:IsA("LayerCollector") then
			return current.Enabled
		end
		return current ~= nil
	end
	function t.mount(build: (any, any, any, any) -> any, options: { [string]: any }?): any
		local config = options or {}
		local Compose = Facet.Compose
		local runtime = Facet.Roblox.createRuntime()
		local Host = runtime.constructors
		local package = config.theme or themes[1].package
		local root
		local emulate = config.size ~= nil and config.emulate ~= false
		local stop = runtime.mount(function()
			local overlay = if emulate
				then Host.Frame "Screen" { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1000 }
				else nil
			local theme = Compose.cell(package)
			local palette = Compose.cell(config.palette or package.style.defaultTheme)
			local viewport = if emulate
				then Compose.formula(function(use)
					local size = config.size
					local value = if Compose.isReadable(size) then use(size) else size
					return { width = value.X, height = value.Y }
				end)
				else Facet.Roblox.createViewport(workspace.CurrentCamera)
			local UI = Facet.controls(runtime, {
				viewport = viewport,
				theme = theme,
				reducedMotion = config.reducedMotion ~= false,
				overlayParent = overlay,
			})
			local sheet = Facet.themes.createStyleSheet(runtime, theme, { theme = palette, transition = false })
			local stage = Host.Frame "Stage" {
				Size = function(use)
					local size = config.size
					if size == nil then
						return UDim2.fromScale(1, 1)
					end
					local value = if Compose.isReadable(size) then use(size) else size
					return UDim2.fromOffset(value.X, value.Y)
				end,
				BackgroundTransparency = 1,
				build(UI, Host, Compose, {
					runtime = runtime,
					viewport = viewport,
					theme = theme,
					palette = palette,
					types = {
						UDim = UDim,
						UDim2 = UDim2,
						Vector2 = Vector2,
						Vector3 = Vector3,
						Color3 = Color3,
						CFrame = CFrame,
						Rect = Rect,
						Enum = Enum,
						Font = Font,
						NumberRange = NumberRange,
						BrickColor = BrickColor,
						TweenInfo = TweenInfo,
						Path2DControlPoint = Path2DControlPoint,
						NumberSequence = NumberSequence,
						NumberSequenceKeypoint = NumberSequenceKeypoint,
						ColorSequence = ColorSequence,
						ColorSequenceKeypoint = ColorSequenceKeypoint,
						FloatCurveKey = FloatCurveKey,
					},
				}),
			}
			if overlay then
				overlay.Parent = stage
			end
			root = stage
			return Host.ScreenGui "FacetLive" {
				ResetOnSpawn = false,
				DisplayOrder = 50,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				sheet,
				Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				Host.Frame "Backdrop" {
					Size = UDim2.fromScale(1, 1),
					BorderSizePixel = 0,
					ZIndex = 0,
				},
				stage,
			}
		end, Players.LocalPlayer:WaitForChild("PlayerGui"))
		table.insert(cleanups, function()
			stop()
			runtime:dispose()
		end)
		t.settle(config.frames or 8)
		return root
	end
	function t.context(UI: any, Host: any, Compose: any, env: any): { [string]: any }
		return {
			Facet = Facet,
			Compose = Compose,
			runtime = env.runtime,
			Host = Host,
			UI = UI,
			viewport = env.viewport,
			types = env.types,
			guiService = GuiService,
			runService = RunService,
			inputTarget = Players.LocalPlayer:WaitForChild("PlayerGui"),
			worldTarget = workspace,
			load = function(kind: string, name: string)
				local source = if kind == "example"
					then storage:WaitForChild("FacetExamples")
					elseif kind == "reference" then storage:WaitForChild("FacetReference")
					else storage:WaitForChild("FacetScenarios")
				return (require :: any)(source:WaitForChild(name))
			end,
		}
	end
	function t.clipped(node: any): { x: number, y: number, w: number, h: number, r: number, b: number }?
		local box = t.rect(node)
		local x, y, r, b = box.x, box.y, box.r, box.b
		local at = node.Parent
		while at and at:IsA("GuiObject") do
			if at.ClipsDescendants or at:IsA("ScrollingFrame") then
				local clip = t.rect(at)
				x, y = math.max(x, clip.x), math.max(y, clip.y)
				r, b = math.min(r, clip.r), math.min(b, clip.b)
			end
			at = at.Parent
		end
		if r - x < 0.5 or b - y < 0.5 then
			return nil
		end
		return { x = x, y = y, w = r - x, h = b - y, r = r, b = b }
	end
	function t.offenders(root: Instance, bounds: any, options: { [string]: any }?): { [string]: any }
		local config = options or {}
		local limit = if typeof(bounds) == "Instance" then t.rect(bounds) else bounds
		local margin = config.margin or 0.5
		local out = { lateral = {}, vertical = {}, clipped = {} }
		for _, node in root:GetDescendants() do
			if
				node:IsA("GuiObject")
				and t.visible(node)
				and node.AbsoluteSize.X > 0.5
				and node.AbsoluteSize.Y > 0.5
			then
				local seen = t.clipped(node)
				if seen then
					if seen.x < limit.x - margin or seen.r > limit.r + margin then
						table.insert(out.lateral, { node.Name, seen.x, seen.r })
					end
					if seen.y < limit.y - margin or seen.b > limit.b + margin then
						table.insert(out.vertical, { node.Name, seen.y, seen.b })
					end
					if
						(node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
						and node.ContentText ~= ""
						and not node.TextScaled
						and (node.TextBounds.X > node.AbsoluteSize.X + 0.5 or node.TextBounds.Y > node.AbsoluteSize.Y + 0.5 or (not node.TextFits and node:GetStyled(
							"TextWrapped"
						) == true))
						and node:GetStyled("TextTruncate") == Enum.TextTruncate.None
					then
						table.insert(out.clipped, { node.Name, node.ContentText, node.TextBounds, node.AbsoluteSize })
					end
				end
			end
		end
		return out
	end
	function t.gallery(options: { [string]: any }?): (any, any)
		local config = options or {}
		local context
		local stage = t.mount(function(UI, Host, Compose, env)
			local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
			local folder = storage:FindFirstChild("FacetThemes")
			local packages = screen.themePackages(
				Facet.themes,
				if folder then folder:GetChildren() else {},
				function(module)
					return (require :: any)(module)
				end
			)
			packages.Neutral = env.theme:peek()
			context = {
				Facet = Facet,
				Compose = Compose,
				runtime = env.runtime,
				Host = Host,
				viewport = env.viewport,
				types = env.types,
				worldTarget = workspace,
				selection = Compose.cell(config.demo or "all-controls"),
				demos = screen.list(),
				inputTarget = Players.LocalPlayer:WaitForChild("PlayerGui"),
				guiService = GuiService,
				runService = RunService,
				theme = env.theme,
				themeMode = env.palette,
				packages = packages,
				load = function(kind, name)
					local source = if kind == "example"
						then storage:WaitForChild("FacetExamples")
						elseif kind == "reference" then storage:WaitForChild("FacetReference")
						else storage:WaitForChild("FacetScenarios")
					return (require :: any)(source:WaitForChild(name))
				end,
			}
			screen.configure(context)
			context.UI = UI
			context.show = function(id: string): any
				return screen.dispatch(context, "show", id)
			end
			context.dispatch = function(command: string, argument: any): any
				return screen.dispatch(context, command, argument)
			end
			return screen.build(context)
		end, { size = config.size, theme = config.theme, frames = config.frames or 20 })
		return stage, context
	end
	function t.device(options: { [string]: any }): Vector2
		local simulator = game:GetService("StudioDeviceSimulatorService") :: any
		if options.device then
			simulator:SetDeviceAsync(options.device)
		end
		if options.orientation then
			simulator:SetOrientationAsync(options.orientation)
		end
		if options.width and options.height then
			simulator:SetResolutionAsync(options.width, options.height)
		end
		t.settle(options.frames or 30)
		local input = game:GetService("UserInputService")
		local last, steady = input.PreferredInput, 0
		for _ = 1, 180 do
			if options.input and input.PreferredInput ~= options.input then
				steady = 0
			elseif input.PreferredInput == last then
				steady += 1
			else
				steady = 0
			end
			last = input.PreferredInput
			if steady >= 15 then
				break
			end
			t.settle(1)
		end
		table.insert(cleanups, 1, function()
			pcall(function()
				simulator:SetDeviceAsync(options.restore or "xbox")
			end)
		end)
		return workspace.CurrentCamera.ViewportSize
	end
	function t.scenario(name: string): any
		return (require :: any)(storage:WaitForChild("FacetScenarios"):WaitForChild(name))
	end
	function t.hold(value: any)
		shared.FacetLiveHold = { cleanup = t.cleanup, value = value }
		record.held = true
	end
	function t.held(): any
		local hold = shared.FacetLiveHold
		return hold and hold.value
	end
	function t.cleanup()
		for index = #cleanups, 1, -1 do
			pcall(cleanups[index])
		end
		table.clear(cleanups)
	end
	return t
end

function live.cases(suite: string): { any }
	local module = script:WaitForChild("suites"):FindFirstChild(suite)
	assert(module and module:IsA("ModuleScript"), "unknown live suite " .. suite)
	return (require :: any)(module)
end

function live.run(suite: string, options: { [string]: any }?): string
	local config = options or {}
	local Facet = (require :: any)(storage:WaitForChild("Facet"))
	local themes = themeModules(Facet)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hidden = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and string.sub(gui.Name, 1, 12) == "FacetGallery" and gui.Enabled then
			if not config.keepGallery then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
	end
	local results = {}
	local passed, failed = 0, 0
	for _, case in live.cases(suite) do
		if not case.run or (config.only and not string.find(case.id, config.only, 1, true)) then
			continue
		end
		local record = { id = case.id, contracts = case.contracts or {}, checks = {}, notes = {} }
		local t = newCase(Facet, themes, record)
		local ok, problem = xpcall(case.run, debug.traceback, t)
		if not record.held then
			t.cleanup()
		end
		if not ok then
			record.error = tostring(problem)
		end
		local good = ok and #record.checks > 0
		for _, check in record.checks do
			good = good and check.ok
		end
		record.ok = good
		if good then
			passed += 1
		else
			failed += 1
		end
		table.insert(results, record)
	end
	for _, gui in hidden do
		gui.Enabled = true
	end
	return HttpService:JSONEncode({
		schema = "facet-live-assertions/1",
		suite = suite,
		environment = environment(),
		themes = (function()
			local names = {}
			for _, entry in themes do
				table.insert(names, entry.name)
			end
			return names
		end)(),
		passed = passed,
		failed = failed,
		cases = results,
	})
end

function live.begin(suite: string, id: string): string
	live.release()
	local Facet = (require :: any)(storage:WaitForChild("Facet"))
	local chosen
	for _, case in live.cases(suite) do
		if case.id == id then
			chosen = case
		end
	end
	assert(chosen and chosen.setup, "no interactive case " .. id)
	local record = { id = chosen.id, contracts = chosen.contracts or {}, checks = {}, notes = {}, steps = {} }
	local t = newCase(Facet, themeModules(Facet), record)
	if not chosen.keepGallery then
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hidden = {}
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and string.sub(gui.Name, 1, 12) == "FacetGallery" and gui.Enabled then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
		t.cleanup = (function(inner)
			return function()
				inner()
				for _, gui in hidden do
					gui.Enabled = true
				end
				table.clear(hidden)
			end
		end)(t.cleanup)
	end
	local value = chosen.setup(t)
	shared.FacetLiveHold = { cleanup = t.cleanup, value = value }
	shared.FacetLiveSession = { suite = suite, case = chosen, record = record, t = t, value = value }
	return HttpService:JSONEncode(record)
end

function live.step(name: string): string
	local session = assert(shared.FacetLiveSession, "call live.begin first")
	local before = #session.record.checks
	table.insert(session.record.steps, name)
	local ok, problem = xpcall(session.case.steps[name], debug.traceback, session.t, session.value)
	if not ok then
		session.t.check(name .. " ran", false, tostring(problem))
	end
	local lines = {}
	for index = before + 1, #session.record.checks do
		local check = session.record.checks[index]
		table.insert(lines, `{if check.ok then "ok  " else "FAIL"} {check.name} {HttpService:JSONEncode(check.detail)}`)
	end
	return table.concat(lines, "\n")
end

function live.finish(tag: string): string
	local session = assert(shared.FacetLiveSession, "call live.begin first")
	shared.FacetLiveSession = nil
	live.release()
	local record = session.record
	local good = #record.checks > 0
	for _, check in record.checks do
		good = good and check.ok
	end
	record.ok = good
	local json = HttpService:JSONEncode({
		schema = "facet-live-assertions/1",
		suite = session.suite,
		environment = environment(),
		passed = if good then 1 else 0,
		failed = if good then 0 else 1,
		cases = { record },
	})
	live.save(`{session.suite}-{record.id}-{tag}`, json)
	return live.summary(json)
end

local PAD_KEYS: { [string]: Enum.KeyCode } = {
	DPadDown = Enum.KeyCode.Three,
	DPadLeft = Enum.KeyCode.Two,
	DPadRight = Enum.KeyCode.Four,
	ButtonA = Enum.KeyCode.Nine,
	ButtonB = Enum.KeyCode.Zero,
	ButtonX = Enum.KeyCode.Eight,
	ButtonY = Enum.KeyCode.Seven,
	ButtonL1 = Enum.KeyCode.R,
	ButtonL2 = Enum.KeyCode.E,
	StickUp = Enum.KeyCode.W,
}

function live.press(names: { string }, frames: number?): string
	local UserInputService = game:GetService("UserInputService")
	local virtual = (UserInputService :: any):CreateVirtualInput()
	local seen: { string } = {}
	local connection = UserInputService.InputBegan:Connect(function(input)
		table.insert(seen, `{input.UserInputType.Name}:{input.KeyCode.Name}`)
	end)
	local moved = UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.5 then
			table.insert(seen, `{input.UserInputType.Name}:{input.KeyCode.Name}:{input.Position.X},{input.Position.Y}`)
		end
	end)
	local selections: { string } = {}
	for _, name in names do
		local key = PAD_KEYS[name] or (Enum.KeyCode :: any)[name]
		virtual:SendKey(true, key, false)
		for _ = 1, 3 do
			RunService.RenderStepped:Wait()
		end
		virtual:SendKey(false, key, false)
		for _ = 1, frames or 8 do
			RunService.RenderStepped:Wait()
		end
		local selected = GuiService.SelectedObject
		table.insert(selections, `{name}>{if selected then selected.Name else "nil"}`)
	end
	connection:Disconnect()
	moved:Disconnect()
	local session = shared.FacetLiveSession
	if session then
		local notes = session.record.notes
		notes.deliveredInput = notes.deliveredInput or {}
		for _, entry in seen do
			table.insert(notes.deliveredInput, entry)
		end
		notes.pressedSelections = notes.pressedSelections or {}
		for _, entry in selections do
			table.insert(notes.pressedSelections, entry)
		end
	end
	return HttpService:JSONEncode({ input = seen, selections = selections })
end

function live.release()
	local hold = shared.FacetLiveHold
	shared.FacetLiveHold = nil
	if hold then
		hold.cleanup()
	end
end

function live.save(name: string, json: string, dir: string?): number
	local event = storage:WaitForChild("FacetLiveRelay", 10) :: RemoteEvent?
	assert(event, "start the relay in the Server datamodel first")
	local size = 30000
	local count = math.max(1, math.ceil(#json / size))
	for index = 1, count do
		event:FireServer(name, index, count, string.sub(json, (index - 1) * size + 1, index * size), dir)
	end
	return #json
end

function live.record(tag: string, suites: { string }?): string
	local lines = {}
	for _, suite in suites or { "layout_geometry", "gallery", "needs_live" } do
		local json = live.run(suite, { keepGallery = suite ~= "layout_geometry" })
		live.save(`{suite}-{tag}`, json)
		table.insert(lines, live.summary(json))
	end
	return table.concat(lines, "\n")
end

function live.summary(json: string, limit: number?): string
	local result = HttpService:JSONDecode(json)
	local lines = {
		`{result.suite}: {result.passed} passed, {result.failed} failed at {table.concat(
			result.environment.viewport,
			"x"
		)} {result.environment.preferredTextSize}`,
	}
	for _, case in result.cases do
		local bad = 0
		for _, check in case.checks do
			if not check.ok then
				bad += 1
				if bad <= (limit or 4) then
					table.insert(lines, `  FAIL {case.id} :: {check.name} {HttpService:JSONEncode(check.detail)}`)
				end
			end
		end
		table.insert(
			lines,
			`{if case.ok then "ok  " else "FAIL"} {case.id} ({#case.checks} checks, {bad} failed){if case.error
				then " error " .. string.sub(case.error, 1, 300)
				else ""}`
		)
	end
	return table.concat(lines, "\n")
end

return live
