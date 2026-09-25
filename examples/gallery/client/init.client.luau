--!strict
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
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local owner = Compose.createRootOwner(function()
	local viewport = Facet.Roblox.createViewport(workspace.CurrentCamera)
	local demos = gallery.list()
	local initial, booted = gallery.boot(
		workspace:GetAttribute("Facet_Demo"),
		workspace:GetAttribute("Facet_Scenario"),
		workspace:GetAttribute("Facet_Example")
	)
	if booted then
		table.insert(demos, booted)
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
			return require(module)
		end
	)
	packages.Neutral = neutral
	local context = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = Host,
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
		},
		worldTarget = workspace,
		selection = selected,
		demos = demos,
		inputTarget = players.LocalPlayer:WaitForChild("PlayerGui"),
		guiService = game:GetService("GuiService"),
		runService = game:GetService("RunService"),
		theme = theme,
		themeMode = selectedTheme,
		packages = packages,
		load = function(kind, name)
			local folder = if kind == "example"
				then storage.FacetExamples
				elseif kind == "reference" then storage.FacetReference
				else storage.FacetScenarios
			return require(folder:WaitForChild(name))
		end,
	}
	gallery.configure(context)
	local sheet = Facet.themes.createStyleSheet(runtime, theme, {
		theme = selectedTheme,
		reducedMotion = context.reducedMotion,
	})
	context.UI = Facet.controls(runtime, {
		viewport = viewport,
		theme = theme,
		reducedMotion = context.reducedMotion,
	})
	local stop, gui = runtime.mount(function()
		return Host.ScreenGui "FacetGallery" {
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			sheet,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
			gallery.build(context),
		}
	end, players.LocalPlayer:WaitForChild("PlayerGui"))
	Compose.cleanup(stop)
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
				Visible = function(use)
					return not use(context.sceneVisible)
				end,
			},
		}
	end, players.LocalPlayer:WaitForChild("PlayerGui"))
	backdrop:FindFirstChild("Backdrop"):AddTag("facet-surface")
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
