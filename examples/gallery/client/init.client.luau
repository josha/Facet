--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Definition = typeof(require("@repo/examples/types").Definition)
type ThemeModule = typeof(require("@repo/examples/types").ThemeModule)
local loadDefinition: (ModuleScript) -> Definition = require
local loadTheme: (ModuleScript) -> ThemeModule = require
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
local Facet = require(storage:WaitForChild("Facet"))
local gallery = require(script:WaitForChild("screen"))
local Compose: ComposeModule = Facet.Compose
local runtime: ComposeRuntime = Facet.Roblox.createRuntime()
local Host: RobloxHost = Facet.host(runtime)
local owner = Compose.createRootOwner(function()
	local viewport = Facet.Roblox.createViewport(workspace.CurrentCamera)
	local function text(name: string): string?
		local value = workspace:GetAttribute(name)
		return if type(value) == "string" then value else nil
	end
	local attribute = workspace:GetAttribute("Facet_Example")
	local example = if type(attribute) == "number" then attribute else nil
	local demos = gallery.list(example)
	local initial, booted = gallery.boot(text("Facet_Demo"), text("Facet_Scenario"), example)
	if booted and example == nil then
		table.insert(
			demos,
			{ id = booted.id, kind = booted.kind, module = booted.module, title = booted.title, blurb = nil }
		)
	end
	local added = workspace:GetAttribute("Facet_Demos")
	if type(added) == "string" then
		for _, demo in game:GetService("HttpService"):JSONDecode(added) do
			table.insert(
				demos,
				{ id = demo.id, kind = demo.kind, module = demo.module, title = demo.title, blurb = nil }
			)
		end
	end
	local selected = Compose.cell(initial)
	local defined = Facet.themes.define(Facet.themes.neutralPackage())
	local neutral = assert(defined)
	local theme = Compose.cell(neutral)
	local selectedTheme = Compose.cell(neutral.style.defaultTheme)
	local themeFolder = storage:FindFirstChild("FacetThemes")
	local packages = gallery.themePackages(
		Facet.themes,
		if themeFolder then themeFolder:GetChildren() else {},
		function(module: ModuleScript): ThemeModule
			return loadTheme(module)
		end
	)
	packages.Neutral = neutral
	local function find(kind: string, name: string, ...: string): ModuleScript
		local folder: Instance = if kind == "example"
			then storage.FacetExamples
			elseif kind == "reference" then storage.FacetReference
			else storage.FacetScenarios
		local target = folder:WaitForChild(name)
		for _, child in { ... } do
			target = target:WaitForChild(child)
		end
		if not target:IsA("ModuleScript") then
			error(`{name} is not a ModuleScript`)
		end
		return target
	end
	local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")
	if not playerGui:IsA("PlayerGui") then
		error("the local player has no PlayerGui")
	end
	local UI: FacetControls
	local context: ExampleContext = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = Host,
		UI = UI,
		viewport = viewport,
		types = {
			UDim = UDim,
			UDim2 = UDim2,
			Vector2 = Vector2,
			Color3 = Color3,
			Vector3 = Vector3,
			CFrame = CFrame,
			RaycastParams = RaycastParams,
			Path2DControlPoint = Path2DControlPoint,
			FloatCurveKey = FloatCurveKey,
			Rect = Rect,
			NumberSequence = NumberSequence,
			NumberSequenceKeypoint = NumberSequenceKeypoint,
			ColorSequence = ColorSequence,
			ColorSequenceKeypoint = ColorSequenceKeypoint,
			Enum = Enum,
			Font = Font,
			NumberRange = NumberRange,
			TweenInfo = TweenInfo,
		},
		worldTarget = workspace,
		selection = selected,
		demos = demos,
		buildStamp = workspace:GetAttribute("Facet_Build"),
		inputTarget = playerGui,
		guiService = game:GetService("GuiService"),
		runService = game:GetService("RunService"),
		theme = theme,
		themeMode = selectedTheme,
		packages = packages,
		find = find,
		load = function(kind: string, name: string, ...: string): Definition
			return loadDefinition(find(kind, name, ...))
		end,
	}
	gallery.configure(context)
	local overlayParent: Instance? = context.overlayParent
	UI = Facet.controls(runtime, {
		viewport = viewport,
		theme = theme,
		motionLevel = context.motionPreference,
		environment = context.environment,
		overlayParent = overlayParent,
	})
	context.UI = UI
	local sheet = Facet.themes.createStyleSheet(runtime, theme, {
		theme = selectedTheme,
		motionLevel = context.motionPreference,
		hover = context.hoverPreview,
		tenFoot = UI.environment().isTenFoot,
	})
	context.sheet = sheet
	local stop, gui = runtime.mount(function()
		return Host.ScreenGui "FacetGallery" {
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			sheet,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
			UI.focusRing(playerGui),
			gallery.build(context),
		}
	end, playerGui)
	Compose.cleanup(stop)
	local sceneVisible = assert(context.sceneVisible)
	local stopBackdrop, backdrop = runtime.mount(function()
		return Host.ScreenGui "FacetGalleryBackdrop" {
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.None,
			DisplayOrder = -1,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
			Host.Frame "Backdrop" {
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				Visible = function(use: Use)
					return not use(sceneVisible)
				end,
			},
		}
	end, playerGui)
	if typeof(backdrop) == "Instance" then
		assert(backdrop:FindFirstChild("Backdrop")):AddTag("facet-surface")
	end
	Compose.cleanup(stopBackdrop)
	local api = Host.BindableFunction "FacetShowcaseAPI" { Parent = workspace }
	api.OnInvoke = function(command: string, argument: unknown)
		return gallery.dispatch(context, command, argument)
	end
	workspace:SetAttribute("Facet_Version", Facet.VERSION)
	workspace:SetAttribute("Facet_ShowcaseReady", true)
end, runtime.reactor)
script.Destroying:Connect(function()
	owner.dispose()
	runtime:dispose()
end)
