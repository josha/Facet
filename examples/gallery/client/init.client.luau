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
	local initial = workspace:GetAttribute("Facet_Demo") or "all-controls"
	local scenario = workspace:GetAttribute("Facet_Scenario")
	local exampleIndex = workspace:GetAttribute("Facet_Example")
	local exampleNames = {
		"01_temperature_converter",
		"02_playlist_table",
		"03_settings_sync",
		"04_confirm_dialog",
		"05_word_game",
		"06_tile_game",
		"07_match3",
	}
	local initialModule = if type(scenario) == "string" and scenario ~= "" then scenario else exampleNames[exampleIndex]
	if initialModule then
		initial = initialModule
		table.insert(demos, {
			id = initial,
			title = initialModule,
			kind = if scenario then "fixture" else "example",
			module = initialModule,
		})
	end
	local selected = Compose.cell(initial)
	local theme = Compose.cell(Facet.themes.neutralPackage())
	local selectedTheme = Compose.cell(Facet.themes.neutralPackage().style.defaultTheme)
	local packages = { Neutral = Facet.themes.neutralPackage() }
	local themeFolder = storage:FindFirstChild("FacetThemes")
	if themeFolder then
		for _, module in themeFolder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, definition = pcall(require, module)
				if ok and not definition.testOnly then
					local built, package = pcall(definition.build, Facet.themes)
					if built and package then
						packages[module.Name] = package
					end
				end
			end
		end
	end
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
		return Host.ScreenGui({
			Name = "FacetGallery",
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			sheet,
			Host.StyleLink({ StyleSheet = Facet.Compose.static(sheet) }),
			gallery.build(context),
		})
	end, players.LocalPlayer:WaitForChild("PlayerGui"))
	Compose.cleanup(stop)
	local api = Host.BindableFunction({
		Name = "FacetShowcaseAPI",
		Parent = workspace,
		OnInvoke = Compose.static(function(command, argument)
			return gallery.dispatch(context, command, argument)
		end),
	})
	workspace:SetAttribute("Facet_Version", Facet.VERSION)
	workspace:SetAttribute("Facet_ShowcaseReady", true)
end, runtime.reactor)
script.Destroying:Connect(function()
	owner.dispose()
	runtime.dispose()
end)
