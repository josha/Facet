--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type ThemeCell = typeof(require("@repo/tools/typecheck/aliases").ThemeCell)
type StringCell = typeof(require("@repo/tools/typecheck/aliases").StringCell)
type ViewportCell = typeof(require("@repo/src/vendor/compose/core").formula(function()
	return { width = 0, height = 0 }
end))
type MountEnvironment = {
	runtime: ComposeRuntime,
	viewport: ViewportCell,
	theme: ThemeCell,
	palette: StringCell,
	types: { [string]: unknown },
}
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Use = <T>(ReadOnlyValue<T>) -> T
type Rect = { x: number, y: number, w: number, h: number, r: number, b: number }
type ThemeEntry = { name: string, package: unknown }
local function virtualInput(): any
	return (game:GetService("UserInputService") :: any):CreateVirtualInput()
end

local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local storage = game:GetService("ReplicatedStorage")

local Verify = (require :: any)(storage:WaitForChild("FacetVerify"):WaitForChild("core"))
local VerifyRoblox: typeof(require("@repo/tools/vendor/verify/src/roblox")) = (require :: any)(
	storage:WaitForChild("FacetVerify"):WaitForChild("roblox")
)

local live = { caseSelection = true }

local function robloxTypes(): { [string]: unknown }
	return {
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Vector3 = Vector3,
		Color3 = Color3,
		CFrame = CFrame,
		RaycastParams = RaycastParams,
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
	}
end

local function findScript(kind: string, name: string, ...: string): ModuleScript
	local source: Instance = if kind == "example"
		then storage:WaitForChild("FacetExamples")
		elseif kind == "reference" then storage:WaitForChild("FacetReference")
		else storage:WaitForChild("FacetScenarios")
	local target: Instance = source:WaitForChild(name)
	for _, child in { ... } do
		target = target:WaitForChild(child)
	end
	assert(target:IsA("ModuleScript"), name .. " is not a ModuleScript")
	return target
end

local function traceback(message: string): string
	return debug.traceback(message, 2)
end

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
	local found: { ThemeEntry } = {}
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
	table.sort(found, function(a: ThemeEntry, b: ThemeEntry)
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
		preferredInput = tostring(game:GetService("UserInputService").PreferredInput),
		studio = RunService:IsStudio(),
		version = version(),
		stamp = workspace:GetAttribute("Facet_SourceStamp"),
	}
end

local function demos(screen: any): { any }
	local list = screen.list()
	local added = workspace:GetAttribute("Facet_Demos")
	if type(added) == "string" then
		for _, demo in HttpService:JSONDecode(added) do
			table.insert(list, demo)
		end
	end
	return list
end

local baselineDevice = "none"

local function visibleNamed(t: { visible: (Instance) -> boolean }, root: Instance, name: string): GuiObject?
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function rect(node: any): Rect
	local at, size = node.AbsolutePosition, node.AbsoluteSize
	return { x = at.X, y = at.Y, w = size.X, h = size.Y, r = at.X + size.X, b = at.Y + size.Y }
end

local function clipped(node: any): Rect?
	local box: Rect = rect(node)
	local x: number, y: number, r: number, b: number = box.x, box.y, box.r, box.b
	local at = node.Parent
	while at and not at:IsA("LayerCollector") do
		if at:IsA("GuiObject") and (at.ClipsDescendants or at:IsA("ScrollingFrame")) then
			local clip: Rect = rect(at)
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

local function newCase(Facet: any, themes: { any }, record: { [string]: any }, context: any?)
	local t = { visibleNamed = visibleNamed, rect = rect, clipped = clipped }
	local cleanups: { () -> () } = {}
	t.Facet = Facet
	t.themes = themes
	t.environment = environment()
	function t.check(name: string, ok: boolean, detail: any?)
		table.insert(record.checks, { name = name, ok = ok == true, detail = encode(detail) })
		if context then
			pcall(function()
				context:step(name, function()
					context:expect(ok == true):toBeTrueWith(HttpService:JSONEncode(encode(detail)))
				end)
			end)
		end
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
	function t.attach(name: string, value: unknown)
		if context then
			context:attach(name, "application/json", HttpService:JSONEncode(value))
		else
			t.note(name, value)
		end
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
	function t.ruleValue(rule: StyleRule, property: string): unknown
		local value = rule:GetProperty(property)
		local sheet = rule:FindFirstAncestorWhichIsA("StyleSheet")
		if sheet and type(value) == "string" and string.sub(value, 1, 1) == "$" then
			local resolved = sheet:GetAttribute(string.sub(value, 2))
			if resolved ~= nil then
				return resolved
			end
		end
		return value
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
		while current and not current:IsA("LayerCollector") do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			current = current.Parent
		end
		return current ~= nil and (current :: LayerCollector).Enabled
	end
	local function mount(
		build: (unknown, RobloxHost, ComposeModule, MountEnvironment) -> Frame,
		options: { [string]: any }?
	): any
		local config: { [string]: any } = options or {}
		local Compose: ComposeModule = Facet.Compose
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime()
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local package = config.theme or themes[1].package
		local root
		local emulate = config.size ~= nil and config.emulate ~= false
		local stop = runtime.mount(function()
			local overlay = if emulate
				then Host.Frame "Screen" { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1000 }
				else nil
			local theme = Compose.cell(package)
			local palette = Compose.cell(config.palette or package.style.defaultTheme)
			local viewport: ViewportCell = if emulate
				then Compose.formula(function(use: Use)
					local size = config.size
					local value = if Compose.isValue(size) then use(size) else size
					return { width = value.X, height = value.Y }
				end)
				else Facet.Roblox.createViewport(workspace.CurrentCamera)
			local UI = Facet.controls(runtime, {
				viewport = viewport,
				theme = theme,
				motionLevel = config.motionLevel or "none",
				environment = config.environment,
				overlayParent = overlay,
			})
			local sheet = Facet.themes.createStyleSheet(runtime, theme, { theme = palette, transition = false })
			local environment: MountEnvironment = {
				runtime = runtime,
				viewport = viewport,
				theme = theme,
				palette = palette,
				types = robloxTypes(),
			}
			local content = build(UI, Host, Compose, environment)
			local stage = Host.Frame "Stage" {
				Size = function(use: Use)
					local size = config.size
					if size == nil then
						return UDim2.fromScale(1, 1)
					end
					local value = if Compose.isValue(size) then use(size) else size
					return UDim2.fromOffset(value.X, value.Y)
				end,
				BackgroundTransparency = 1,
				content,
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
				Host.StyleLink { StyleSheet = Compose.static(sheet) },
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
	t.mount = mount
	function t.context(UI: any, Host: any, Compose: any, env: any): { [string]: any }
		local function find(kind: string, name: string): Instance
			local source: Instance = if kind == "example"
				then storage:WaitForChild("FacetExamples")
				elseif kind == "reference" then storage:WaitForChild("FacetReference")
				else storage:WaitForChild("FacetScenarios")
			return source:WaitForChild(name)
		end
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
			find = find,
			load = function(kind: string, name: string)
				return (require :: any)(find(kind, name))
			end,
		}
	end
	local function textClipped(node: any): boolean
		local bounds, size = node.TextBounds, node.AbsoluteSize
		if bounds.X > size.X + 0.5 or bounds.Y > size.Y + 0.5 then
			return true
		end
		if node.TextFits or node:GetStyled("TextWrapped") ~= true then
			return false
		end
		local params = Instance.new("GetTextBoundsParams")
		params.Text = node.Text
		params.Font = node:GetStyled("FontFace")
		params.Size = node:GetStyled("TextSize")
		params.Width = size.X
		params.RichText = node.RichText
		local measured = game:GetService("TextService"):GetTextBoundsAsync(params)
		params:Destroy()
		return measured.X > size.X + 0.5 or measured.Y * node.LineHeight > size.Y + 0.5
	end
	function t.offenders(root: Instance, bounds: any, options: { [string]: any }?): { [string]: any }
		local config: { [string]: any } = options or {}
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
						table.insert(out.lateral, { node.Name :: unknown, seen.x, seen.r })
					end
					if seen.y < limit.y - margin or seen.b > limit.b + margin then
						table.insert(out.vertical, { node.Name :: unknown, seen.y, seen.b })
					end
					if
						(node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox"))
						and node.ContentText ~= ""
						and not node.TextScaled
						and node:GetStyled("TextTransparency") < 1
						and textClipped(node)
						and node:GetStyled("TextTruncate") == Enum.TextTruncate.None
					then
						table.insert(
							out.clipped,
							{ node.Name :: unknown, node.ContentText, node.TextBounds, node.AbsoluteSize }
						)
					end
				end
			end
		end
		return out
	end
	function t.gallery(options: { [string]: any }?): (any, any)
		local config: { [string]: any } = options or {}
		local context: { [string]: any }
		local function build(_UI: unknown, Host: RobloxHost, Compose: ComposeModule, env: MountEnvironment): Frame
			local screen = (require :: any)(storage:WaitForChild("Gallery"):WaitForChild("screen"))
			local folder = storage:FindFirstChild("FacetThemes")
			local packages = screen.themePackages(
				Facet.themes,
				if folder then folder:GetChildren() else {},
				function(module: ModuleScript)
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
				demos = demos(screen),
				inputTarget = Players.LocalPlayer:WaitForChild("PlayerGui"),
				guiService = GuiService,
				runService = RunService,
				theme = env.theme,
				themeMode = env.palette,
				packages = packages,
				find = findScript,
				load = function(kind: string, name: string, ...: string)
					return (require :: any)(findScript(kind, name, ...))
				end,
			}
			screen.configure(context)
			local viewportSize = context.environment.viewportSize
			context.environment.viewportSize = function(use)
				local chosen = viewportSize(use)
				if chosen ~= nil then
					return chosen
				end
				local size = use(env.viewport)
				return Vector2.new(size.width, size.height)
			end
			context.motionPreference:set("none")
			if config.preferredTextSize then
				context.textPreview:set(config.preferredTextSize)
			end
			context.UI = Facet.controls(env.runtime, {
				viewport = env.viewport,
				theme = env.theme,
				motionLevel = "none",
				environment = context.environment,
				overlayParent = context.overlayParent,
			})
			context.environmentFacts = context.UI.environment()
			local sheet = Facet.themes.createStyleSheet(env.runtime, env.theme, {
				theme = env.palette,
				transition = false,
				tenFoot = context.environmentFacts.isTenFoot,
			})
			context.show = function(id: string): any
				return screen.dispatch(context, "show", id)
			end
			context.dispatch = function(command: string, argument: any): any
				return screen.dispatch(context, command, argument)
			end
			return Host.Frame "Gallery" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				sheet,
				Host.StyleLink { StyleSheet = Compose.static(sheet) },
				screen.build(context),
			}
		end
		local stage = mount(build, { size = config.size, theme = config.theme, frames = config.frames or 20 })
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
			if baselineDevice == "keep" then
				pcall(function()
					simulator:SetDeviceAsync(options.restore or "xbox")
				end)
			end
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
		local failures = {}
		for index = #cleanups, 1, -1 do
			local cleanup = assert(table.remove(cleanups))
			local ok, problem = pcall(function()
				cleanup()
				return nil
			end)
			if not ok then
				table.insert(failures, tostring(problem))
			end
		end
		assert(#failures == 0, table.concat(failures, "\n"))
	end
	return t
end

live.context = newCase
live.themes = themeModules

function live.cases(suite: string): { any }
	local module = script:WaitForChild("suites"):FindFirstChild(suite)
	assert(module and module:IsA("ModuleScript"), "unknown live suite " .. suite)
	return (require :: any)(module)
end

local function reportEnvironment(suite: string): { [string]: string }
	local values = environment()
	local fields = { suite = suite }
	for key, value in values do
		fields[key] = if type(value) == "table" then HttpService:JSONEncode(value) else tostring(value)
	end
	return fields
end

local function baseline()
	local input = game:GetService("UserInputService")
	assert(
		not input.VREnabled,
		"Studio started play in VR, which disables GUI selection; set the Device Simulator to a non-VR device before the run"
	)
	if baselineDevice == "keep" then
		return
	end
	local simulated = false
	pcall(function()
		local simulator = game:GetService("StudioDeviceSimulatorService") :: any
		if baselineDevice == "none" then
			simulator:StopSimulationAsync()
		else
			simulator:SetDeviceAsync(baselineDevice)
			simulated = true
		end
	end)
	local viewport, topbar, inset, steady =
		workspace.CurrentCamera.ViewportSize, GuiService.TopbarInset, GuiService:GetGuiInset(), 0
	for frame = 1, 240 do
		RunService.RenderStepped:Wait()
		local now = workspace.CurrentCamera.ViewportSize
		local band, origin = GuiService.TopbarInset, GuiService:GetGuiInset()
		local registered, enabled = pcall(function(): boolean
			return game:GetService("StarterGui"):GetCore("TopbarEnabled")
		end)
		local coreReady = simulated or registered and (enabled == false or band.Min.X > 0 and band.Width > 0)
		steady = if coreReady and now == viewport and band == topbar and origin == inset then steady + 1 else 0
		viewport, topbar, inset = now, band, origin
		if not simulated and input.PreferredInput ~= Enum.PreferredInput.KeyboardAndMouse and frame % 10 == 1 then
			steady = 0
			pcall(function()
				local virtual = virtualInput()
				virtual:SendMousePosition(Vector2.new(4 + frame % 7, 4))
			end)
		end
		if steady >= 30 then
			break
		end
	end
	assert(steady >= 30, "native viewport and CoreGui insets did not settle before the live case")
end

local ATTACHMENTS = (require :: (ModuleScript) -> typeof(require("@repo/tools/studio/live/attachment_limits")))(
	script:WaitForChild("attachment_limits") :: ModuleScript
)
local active: any = nil

local function attachNotes(context: any, record: { [string]: any })
	if next(record.notes) ~= nil then
		context:attach("notes.json", "application/json", HttpService:JSONEncode(record.notes))
	end
end

local GAMEPAD_SUITES: { [string]: boolean } =
	{ focus_opened = true, focus_probe = true, focus_walk = true, gamepad_walk = true }

local GAMEPAD_CASES: { [string]: boolean } = {
	["needs_live_c/card-rail-distant-and-shelves"] = true,
	["needs_live_c/gallery-previews-keep-page-and-pad-routes"] = true,
	["needs_live_c/playlist-pad-reorder-and-tray-walk"] = true,
	["needs_live_c/radial-retiring-branch-refuses-selection"] = true,
	["ports_pickers/picker-menu-scroll-live"] = true,
}

local function inputCapability(): string
	local input = game:GetService("UserInputService")
	return if baselineDevice ~= "none" and input.GamepadEnabled then "input-gamepad" else "input-pointer"
end

local function inputRequirement(suite: string, case: { [string]: any }): string
	local input = case.input
		or (
			if GAMEPAD_SUITES[suite]
					or GAMEPAD_CASES[`{suite}/{case.id}`]
					or string.sub(case.id, 1, 4) == "pad-"
				then "gamepad"
				else "pointer"
		)
	return "input-" .. input
end

function live.report(suite: string, options: { [string]: any }?): any
	local config: { [string]: any } = options or {}
	local runId = if type(config.runId) == "string" then config.runId else nil
	local progressToken = if type(config.progressToken) == "string" then config.progressToken else nil
	local Facet = (require :: any)(storage:WaitForChild("Facet"))
	local themes = themeModules(Facet)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hidden: { ScreenGui } = {}
	local harness =
		Verify.createHarness({ now = os.clock, source = suite, prefixIds = false, attachments = ATTACHMENTS })
	baselineDevice = config.device or "none"
	baseline()
	harness:afterEach(function()
		for _, gui in hidden do
			gui.Enabled = true
		end
		table.clear(hidden)
	end)
	local keepGallery = if config.keepGallery ~= nil then config.keepGallery else suite ~= "layout_geometry"
	local capabilities = { "roblox-client", inputCapability() }
	local records = {}
	local selected = {}
	for _, case in live.cases(suite) do
		local run = case.run
		if not run then
			continue
		end
		if not config.only or string.find(case.id, config.only, 1, true) then
			table.insert(selected, case.id)
		end
		local requirements = { "roblox-client", inputRequirement(suite, case) }
		for _, requirement in case.requires or {} do
			table.insert(requirements, requirement)
		end
		harness:case(case.id, {
			id = case.id,
			requires = requirements,
			run = function(context: any)
				local caseKeepGallery = if case.keepGallery == nil then keepGallery else case.keepGallery
				for _, gui in playerGui:GetChildren() do
					if
						gui:IsA("ScreenGui")
						and gui.Enabled
						and (
							(
								string.sub(gui.Name, 1, 12) == "FacetGallery"
								and not (if case.probe then false else caseKeepGallery)
							) or (string.sub(gui.Name, 1, 9) == "Facet_Lab" and suite ~= "lab")
						)
					then
						gui.Enabled = false
						table.insert(hidden, gui)
					end
				end
				local record: { [string]: any } =
					{ id = case.id, contracts = case.contracts or {}, checks = {}, notes = {} }
				table.insert(records, record)
				local t = newCase(Facet, themes, record, context)
				active = context
				context:defer(function()
					active = nil
					if not record.held then
						t.cleanup()
					end
				end)
				baseline()
				local ran, problem = xpcall(function(): boolean
					context:step(case.id, function()
						run(t)
					end)
					return true
				end, traceback)
				attachNotes(context, record)
				if not ran then
					error(problem, 0)
				end
				if case.probe then
					context:expect(next(record.notes) ~= nil):toBe(true)
				else
					context:expect(#record.checks):toBeGreaterThan(0)
				end
			end,
		})
	end
	assert(#selected > 0, "no live cases matched the selection")
	local report = harness:run({
		executor = "roblox-studio",
		environment = reportEnvironment(suite),
		capabilities = capabilities,
		selection = { ids = config.ids or selected },
		progress = if runId and progressToken
			then VerifyRoblox.progressChannel.publisher(runId, progressToken, function(message, context)
				LogService:GetLogger(VerifyRoblox.progressChannel.LOGGER)
					:Info(message, context :: { [string]: unknown })
			end)
			else nil,
	})
	return report
end

function live.begin(suite: string, id: string, config: { device: string? }?): string
	live.release()
	baselineDevice = if config then config.device or "none" else baselineDevice
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
	do
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hidden = {}
		for _, gui in playerGui:GetChildren() do
			if
				gui:IsA("ScreenGui")
				and gui.Enabled
				and (
					(string.sub(gui.Name, 1, 12) == "FacetGallery" and not chosen.keepGallery)
					or string.sub(gui.Name, 1, 9) == "Facet_Lab"
				)
			then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
		t.cleanup = (function(inner: () -> ())
			return function()
				local ok, problem = pcall(inner)
				for _, gui in hidden do
					gui.Enabled = true
				end
				table.clear(hidden)
				if not ok then
					error(problem, 0)
				end
			end
		end)(t.cleanup)
	end
	local ready = false
	local value
	local harness = Verify.createHarness({ source = suite, now = os.clock, prefixIds = false })
	harness:case(id, {
		id = id,
		run = function(context)
			context:defer(function()
				if not ready then
					t.cleanup()
				end
			end)
			value = chosen.setup(t)
			shared.FacetLiveHold = { cleanup = t.cleanup, value = value }
			shared.FacetLiveSession = { suite = suite, case = chosen, record = record, t = t, value = value }
			ready = true
		end,
	})
	local report = harness:run({
		executor = "roblox-studio",
		environment = reportEnvironment(suite),
		capabilities = { "roblox-client" },
	})
	assert(report.passed == 1, Verify.format(report))
	return Verify.format(report)
end

function live.step(name: string): string
	local session = assert(shared.FacetLiveSession, "call live.begin first")
	local before = #session.record.checks
	table.insert(session.record.steps, name)
	local ok, problem = xpcall(session.case.steps[name], traceback, session.t, session.value)
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

function live.finish(): string
	local session = assert(shared.FacetLiveSession, "call live.begin first")
	shared.FacetLiveSession = nil
	local record = session.record
	local harness = Verify.createHarness({
		now = os.clock,
		source = session.suite,
		prefixIds = false,
		attachments = ATTACHMENTS,
	})
	harness:case(record.id, {
		id = record.id,
		run = function(context)
			context:defer(live.release)
			attachNotes(context, record)
			context:expect(#record.checks):toBeGreaterThan(0)
			for _, check in record.checks do
				pcall(function()
					context:step(check.name, function()
						context:expect(check.ok):toBeTrueWith(HttpService:JSONEncode(check.detail))
					end)
				end)
			end
		end,
	})
	local report = harness:run({
		executor = "roblox-studio",
		environment = reportEnvironment(session.suite),
		capabilities = { "roblox-client" },
	})
	return HttpService:JSONEncode(Verify.decode(report))
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
	ButtonR1 = Enum.KeyCode.O,
	ButtonL2 = Enum.KeyCode.E,
	ButtonR2 = Enum.KeyCode.P,
	Stick2Up = Enum.KeyCode.I,
	Stick2Left = Enum.KeyCode.J,
	Stick2Down = Enum.KeyCode.K,
	Stick2Right = Enum.KeyCode.L,
	StickUp = Enum.KeyCode.W,
	StickLeft = Enum.KeyCode.A,
	StickDown = Enum.KeyCode.S,
	StickRight = Enum.KeyCode.D,
}

function live.click(node: GuiObject, frames: number?)
	local virtual = virtualInput()
	local inset = game:GetService("GuiService"):GetGuiInset()
	local at = node.AbsolutePosition + node.AbsoluteSize / 2 + inset
	virtual:SendMousePosition(at)
	for _ = 1, 2 do
		RunService.RenderStepped:Wait()
	end
	virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
	for _ = 1, 2 do
		RunService.RenderStepped:Wait()
	end
	virtual:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
	for _ = 1, frames or 4 do
		RunService.RenderStepped:Wait()
	end
end

function live.press(names: { string }, frames: number?): string
	local UserInputService = game:GetService("UserInputService")
	local virtual = virtualInput()
	local seen: { string } = {}
	local connection = UserInputService.InputBegan:Connect(function(input)
		table.insert(seen, `{input.UserInputType.Name}:{input.KeyCode.Name}`)
	end)
	local moved = UserInputService.InputChanged:Connect(function(input)
		if
			(input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2)
			and input.Position.Magnitude > 0.5
		then
			table.insert(seen, `{input.UserInputType.Name}:{input.KeyCode.Name}:{input.Position.X},{input.Position.Y}`)
		end
	end)
	local selections: { string } = {}
	local undelivered: { string } = {}
	for _, name in names do
		local first = #seen + 1
		local key = PAD_KEYS[name] or (Enum.KeyCode :: any)[name]
		virtual:SendKey(true, key, false)
		for _ = 1, frames or 3 do
			RunService.RenderStepped:Wait()
		end
		virtual:SendKey(false, key, false)
		for _ = 1, frames or 8 do
			RunService.RenderStepped:Wait()
		end
		if PAD_KEYS[name] then
			local delivered = false
			for index = first, #seen do
				delivered = delivered or string.sub(seen[index], 1, 9) == "Gamepad1:"
			end
			if not delivered then
				table.insert(undelivered, name)
			end
		end
		local selected = GuiService.SelectedObject
		table.insert(selections, `{name}>{if selected then selected.Name else "nil"}`)
	end
	connection:Disconnect()
	moved:Disconnect()
	assert(
		#undelivered == 0,
		"native controller input was not delivered; enable Studio Virtual controller: "
			.. table.concat(undelivered, ", ")
	)
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
	assert(active, "live.save needs a running case")
	active:attach(`{dir or "live"}/{name}.json`, "application/json", json)
	return #json
end

function live.case(source: string, id: string, body: () -> ()): string
	local harness =
		Verify.createHarness({ now = os.clock, source = source, prefixIds = false, attachments = ATTACHMENTS })
	harness:case(id, {
		id = id,
		run = function(context)
			active = context
			context:defer(function()
				active = nil
			end)
			body()
		end,
	})
	local report = harness:run({
		executor = "roblox-studio",
		environment = reportEnvironment(source),
		capabilities = { "roblox-client" },
	})
	return HttpService:JSONEncode(Verify.decode(report))
end

local function collect(...: unknown): { [number]: unknown, n: number }
	return table.pack(...)
end

function live.signal(name: string, body: () -> ...unknown): ...unknown
	local context = assert(active, "live.signal needs a running case")
	local results: { [number]: unknown, n: number }
	context:step(name, function()
		results = collect(body())
	end)
	return table.unpack(results, 1, results.n)
end

return live
