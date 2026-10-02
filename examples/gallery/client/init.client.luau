--!strict
local requireDynamic = require :: (any) -> any
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
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
local Compose: typeof(require("@repo/src/vendor/compose/core")) = Facet.Compose
local runtime: typeof(require("@repo/src/vendor/compose/roblox").createRuntime(nil :: any)) =
	Facet.Roblox.createRuntime()
local Host = (runtime.constructors :: unknown) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
local owner = Compose.createRootOwner(function()
	local viewport = Facet.Roblox.createViewport(workspace.CurrentCamera)
	local demos = gallery.list()
	local initial, booted = gallery.boot(
		workspace:GetAttribute("Facet_Demo"),
		workspace:GetAttribute("Facet_Scenario"),
		workspace:GetAttribute("Facet_Example")
	)
	if booted then
		table.insert(
			demos,
			{ id = booted.id, kind = booted.kind, module = booted.module, title = booted.title, blurb = nil }
		)
	end
	local selected = Compose.cell(initial)
	local neutral = assert(Facet.themes.define(Facet.themes.neutralPackage()))
	local theme = Compose.cell(neutral)
	local selectedTheme = Compose.cell(neutral.style.defaultTheme)
	local themeFolder = storage:FindFirstChild("FacetThemes")
	local packages = gallery.themePackages(
		Facet.themes,
		if themeFolder then themeFolder:GetChildren() else {},
		function(module)
			return requireDynamic(module)
		end
	)
	packages.Neutral = neutral
	local context: typeof(require("@repo/examples/types")(nil :: any)) = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = Host,
		UI = nil :: any,
		viewport = viewport,
		types = {
			UDim = UDim,
			UDim2 = UDim2,
			Vector2 = Vector2,
			Color3 = Color3,
			Vector3 = Vector3,
			CFrame = CFrame,
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
		inputTarget = players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui,
		guiService = game:GetService("GuiService"),
		runService = game:GetService("RunService"),
		theme = theme,
		themeMode = selectedTheme,
		packages = packages,
		load = function(kind, name, ...)
			local folder = if kind == "example"
				then storage.FacetExamples
				elseif kind == "reference" then storage.FacetReference
				else storage.FacetScenarios
			local target = folder:WaitForChild(name)
			for _, child in { ... } do
				target = target:WaitForChild(child)
			end
			return requireDynamic(target)
		end,
	}
	gallery.configure(context)
	context.UI = Facet.controls(runtime, {
		viewport = viewport,
		theme = theme,
		motionLevel = context.motionPreference,
		environment = context.environment,
		overlayParent = context.overlayParent,
	})
	local sheet = Facet.themes.createStyleSheet(runtime, theme, {
		theme = selectedTheme,
		motionLevel = context.motionPreference,
		hover = context.hoverPreview,
		tenFoot = context.UI.environment().isTenFoot,
	})
	context.sheet = sheet
	local stop, gui = runtime.mount(function()
		return Host.ScreenGui "FacetGallery" {
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			sheet :: unknown,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
			context.UI.focusRing(players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui),
			gallery.build(context),
		}
	end, players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui)
	Compose.cleanup(stop)
	local stopBackdrop, backdrop = runtime.mount(function()
		return Host.ScreenGui "FacetGalleryBackdrop" {
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.None,
			DisplayOrder = -1,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }) :: unknown,
			Host.Frame "Backdrop" {
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				Visible = function(use: Use)
					return not use(context.sceneVisible)
				end,
			},
		}
	end, players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui)
	assert((backdrop :: Instance):FindFirstChild("Backdrop")):AddTag("facet-surface")
	Compose.cleanup(stopBackdrop)
	local api = Host.BindableFunction "FacetShowcaseAPI" {
		Parent = workspace,
		OnInvoke = Compose.static(function(command, argument)
			return gallery.dispatch(context, command, argument)
		end),
	}
	workspace:SetAttribute("Facet_Version", Facet.VERSION)
	workspace:SetAttribute("Facet_ShowcaseReady", true)
end, runtime.reactor)
script.Destroying:Connect(function()
	owner.dispose()
	runtime:dispose()
end)
