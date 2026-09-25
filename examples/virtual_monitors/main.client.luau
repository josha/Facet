--!strict
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local storage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local guiService = game:GetService("GuiService")
local starterGui = game:GetService("StarterGui")
starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
guiService.TouchControlsEnabled = false
task.spawn(function()
	for _ = 1, 30 do
		if pcall(function()
			starterGui:SetCore("TopbarEnabled", false)
		end) then
			return
		end
		task.wait(0.1)
	end
end)
local Facet = require(storage:WaitForChild("Facet"))
Facet = Facet.bind(Facet.Compose, Facet.Roblox)
local Compose = Facet.Compose
local screens = require(storage.VirtualMonitors.screens)
local scenes = require(storage.VirtualMonitors.scenes)
local theme = require(storage.VirtualMonitors.theme)
local desktop = require(storage.VirtualMonitors.desktop)
local modelModule = require(storage.VirtualMonitors.model)
local runtime = Facet.Roblox.createRuntime()
local Host = runtime.constructors
local lifetime = Compose.createRootOwner(function()
	local model = modelModule.new(Compose)
	Compose.cleanup(model.dispose)
	local mode, dark = model.mode, model.dark
	local entrance = Compose.cell(0)
	local reducedMotion = Compose.cell(false)
	local motionPolicy = Compose.formula(function(use)
		return if use(reducedMotion) then "reduced" else "full"
	end)
	local pressHaptic = Host.HapticEffect "PressHaptic" { Type = Enum.HapticEffectType.UIClick }
	pressHaptic.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
	Compose.cleanup(function()
		pressHaptic:Destroy()
	end)
	local cameraGoal = Compose.cell(CFrame.lookAt(Vector3.new(0, 7.6, -29), Vector3.new(0, 7, 0)))
	local cameraMotion, modeMotion
	local camera = workspace.CurrentCamera
	local originalCameraType, originalCameraFrame, originalFieldOfView =
		camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 48
	Compose.cleanup(function()
		camera.CameraType = originalCameraType
		camera.CFrame = originalCameraFrame
		camera.FieldOfView = originalFieldOfView
	end)
	local function refreshMotion()
		local ok, value = pcall(function()
			return guiService.ReducedMotionEnabled
		end)
		reducedMotion:set(ok and value == true)
	end
	refreshMotion()
	local ok, motionSignal = pcall(function()
		return guiService:GetPropertyChangedSignal("ReducedMotionEnabled")
	end)
	if ok then
		local connection = motionSignal:Connect(refreshMotion)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	local parts = {}
	local stopWorld = runtime.mount(function()
		modeMotion = runtime.tween(function(use)
			return if use(mode) == "Screen" then 1 else 0
		end, { seconds = 0.6, ease = Compose.easing.inOutCubic })
		cameraMotion = runtime.spring(function(use)
			return use(cameraGoal)
		end, { period = 0.65, damping = 1 })
		local arrival = runtime.spring(function(use)
			return use(entrance)
		end, { period = 0.8, damping = 0.9 })

		local function moodColor(night, day)
			local function goal(use)
				return if use(dark) then night else day
			end
			local animated = runtime.spring(goal, { period = 0.55, damping = 1 })
			return function(use)
				return if use(reducedMotion) then goal(use) else use(animated)
			end
		end
		local children: any = { Name = "VirtualMonitors" }
		for index, name in { "Discover", "Avatar", "Chat" } do
			local x = (2 - index) * 10.9
			local frame = CFrame.new(x, 7, if index == 2 then 0.7 else -1.5)
				* CFrame.Angles(0, math.rad((2 - index) * 22), 0)
			local panel = Host.Part({
				Name = name,
				Anchored = true,
				CanCollide = false,
				Size = Vector3.new(10.8, 10.8 * screens.CANVAS.h / screens.CANVAS.w, 0.12),
				CFrame = function(use)
					local progress = if use(reducedMotion) then use(entrance) else use(arrival)
					return frame * CFrame.new(0, -2 * (1 - progress), 1.5 * (1 - progress))
				end,
				Color = Color3.fromRGB(43, 44, 51),
				Material = Enum.Material.SmoothPlastic,
			})
			parts[name] = panel
			table.insert(children, panel)
			local screenHeight = 10.8 * screens.CANVAS.h / screens.CANVAS.w
			local function arrived(offset)
				return function(use)
					local progress = if use(reducedMotion) then use(entrance) else use(arrival)
					return frame * CFrame.new(0, -2 * (1 - progress), 1.5 * (1 - progress)) * offset
				end
			end
			for _, piece in
				{
					{
						"Bezel",
						Vector3.new(11.04, screenHeight + 0.24, 0.1),
						CFrame.new(0, 0, 0.1),
						Color3.fromRGB(14, 14, 17),
						Enum.Material.Glass,
					},
					{
						"Housing",
						Vector3.new(11.04, screenHeight + 0.24, 0.22),
						CFrame.new(0, 0, 0.26),
						Color3.fromRGB(58, 60, 66),
						Enum.Material.Metal,
					},
					{
						"Back",
						Vector3.new(7.2, screenHeight * 0.62, 0.34),
						CFrame.new(0, -0.3, 0.52),
						Color3.fromRGB(52, 54, 60),
						Enum.Material.Metal,
					},
				}
			do
				table.insert(
					children,
					Host.Part({
						Name = name .. piece[1],
						Anchored = true,
						CanCollide = false,
						Size = piece[2],
						CFrame = arrived(piece[3]),
						Color = piece[4],
						Material = piece[5],
					})
				)
			end
			for _, piece in
				{
					{
						"Neck",
						Vector3.new(1.1, 6.6, 0.18),
						CFrame.new(0, -3.7, 0.86) * CFrame.Angles(math.rad(-4), 0, 0),
					},
					{ "Foot", Vector3.new(3.6, 0.14, 2.8), CFrame.new(0, -6.93, 1.3) },
				}
			do
				table.insert(
					children,
					Host.Part({
						Name = name .. "Stand" .. piece[1],
						Anchored = true,
						CanCollide = false,
						Size = piece[2],
						CFrame = frame * piece[3],
						Color = Color3.fromRGB(170, 172, 178),
						Material = Enum.Material.Metal,
					})
				)
			end
			table.insert(
				children,
				Host.Part({
					Name = name .. "Glow",
					Anchored = true,
					CanCollide = false,
					Transparency = 1,
					Size = Vector3.new(1, 1, 1),
					CFrame = frame * CFrame.new(0, 0, 2.4),
					Host.PointLight({
						Color = if name == "Discover"
							then Color3.fromRGB(120, 214, 182)
							else Color3.fromRGB(170, 150, 255),
						Brightness = function(use)
							return if use(dark) then 1.6 else 0.25
						end,
						Range = 22,
						Shadows = false,
					}),
				})
			)
		end
		table.insert(
			children,
			Host.Part "Floor" {
				Anchored = true,
				Size = Vector3.new(200, 1, 200),
				CFrame = CFrame.new(0, -0.5, 0),
				Color = moodColor(Color3.fromRGB(74, 52, 38), Color3.fromRGB(176, 136, 98)),
				Material = Enum.Material.Wood,
			}
		)
		table.insert(
			children,
			Host.Part "StudioBackdrop" {
				Anchored = true,
				CanCollide = false,
				Size = Vector3.new(180, 100, 1),
				CFrame = CFrame.new(0, 30, 12),
				Color = moodColor(Color3.fromRGB(46, 44, 56), Color3.fromRGB(222, 218, 210)),
				Material = Enum.Material.Plaster,
			}
		)
		return Host.Model(children)
	end, workspace)

	Compose.cleanup(stopWorld)
	scenes.prepareAvatar()
	Compose.cleanup(scenes.disposeAvatar)
	local modeProgress = Compose.formula(function(use)
		return if use(reducedMotion) then (if use(mode) == "Screen" then 1 else 0) else use(modeMotion)
	end)
	local function sceneActions(spatial, package)
		local actions = {
			model = model,
			spatial = spatial,
			theme = package,
			player = players.LocalPlayer,
			reducedMotion = reducedMotion,
			pressHaptic = pressHaptic,
		}
		local function active(use)
			return if spatial then use(mode) == "Spatial" else use(mode) == "Screen"
		end
		actions.discoveryContent = function(sceneRuntime, target)
			return scenes.discovery(sceneRuntime, target)
		end
		actions.gameContent = function(current)
			return function(sceneRuntime, target, live)
				return scenes.card(sceneRuntime, target, current:peek(), motionPolicy, function(use)
					return active(use) and use(live)
				end)
			end
		end
		actions.avatarContent = function(sceneRuntime, target)
			return scenes.avatar(
				sceneRuntime,
				target,
				model.angle,
				model.palette,
				model.hat,
				motionPolicy,
				active,
				model.hatTint
			)
		end
		return actions
	end
	for _, name in { "Discover", "Avatar", "Chat" } do
		runtime.mount(function()
			local package = theme.create(Facet, name)
			local sheet = Facet.themes.createStyleSheet(runtime, package, {
				reducedMotion = reducedMotion,
				theme = function(use)
					return theme.paletteName(use(model.palette), use(dark))
				end,
			})
			local views = screens.create(Facet, runtime, sceneActions(true, package))
			return Host.SurfaceGui({
				Name = name .. "Monitor",
				Adornee = Compose.static(parts[name]),
				Face = Enum.NormalId.Front,
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
				CanvasSize = Vector2.new(screens.CANVAS.w, screens.CANVAS.h),
				LightInfluence = 0,
				Brightness = function(use)
					return if use(dark) then 1.3 else 1.1
				end,
				MaxDistance = 100,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Enabled = function(use)
					return use(modeProgress) < 1
				end,
				sheet,
				Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				views[name](),
			})
		end, players.LocalPlayer:WaitForChild("PlayerGui"))
	end
	local desktopPackage = theme.create(Facet, "Discover")
	local palette = function(use)
		return theme.paletteName(use(model.palette), use(dark))
	end
	local showing = function(use)
		return use(modeProgress) > 0
	end
	runtime.mount(function()
		local sheet = Facet.themes.createStyleSheet(runtime, desktopPackage, {
			reducedMotion = reducedMotion,
			theme = palette,
		})
		local backdrop = Host.Frame "Backdrop" {
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = function(use)
				local t = math.clamp((use(modeProgress) - 0.55) / 0.45, 0, 1)
				return 1 - t * t * (3 - 2 * t)
			end,
		}
		backdrop:AddTag("facet-surface")
		return Host.ScreenGui "VirtualMonitorsBackdrop" {
			DisplayOrder = 9,
			ResetOnSpawn = false,
			ScreenInsets = Enum.ScreenInsets.None,
			Enabled = showing,
			sheet,
			Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
			backdrop,
		}
	end, players.LocalPlayer:WaitForChild("PlayerGui"))
	local app = Facet.app({
		runtime = runtime,
		name = "VirtualMonitorsDesktop",
		theme = desktopPackage,
		reducedMotion = reducedMotion,
		pressHaptic = pressHaptic,
		sheet = { theme = palette },
		screen = {
			DisplayOrder = 10,
			ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Enabled = showing,
		},
	})
	Compose.cleanup(app.dispose)
	app.mount(function()
		local views = screens.create(Facet, runtime, sceneActions(false, desktopPackage))
		return desktop.create(Facet, runtime, views, model, modeProgress, {
			theme = desktopPackage,
			reducedMotion = reducedMotion,
			pressHaptic = pressHaptic,
			player = players.LocalPlayer,
		})()
	end)
	local viewport = Facet.Roblox.createViewport(camera)
	Compose.watch(function(use)
		if (use(viewport).width < 700 or guiService:IsTenFootInterface()) and not model.modeChosen then
			model.focused:set(model.selectedTab:peek())
			mode:set("Screen")
		end
	end)
	local function frameCamera()
		local size = camera.ViewportSize
		local aspect = math.max(0.1, size.X / math.max(1, size.Y))
		local tangent = math.tan(math.rad(camera.FieldOfView / 2))
		local distance = math.max(34 / (2 * tangent * aspect), 10 / (2 * tangent)) * 1.08 + 5
		local selected = parts[model.focused:peek()]
		local focusDistance = if selected
			then math.max(selected.Size.X / (2 * tangent * aspect), selected.Size.Y / (2 * tangent)) * 1.12
			else 0
		local goal = if selected
			then CFrame.lookAt(selected.CFrame:PointToWorldSpace(Vector3.new(0, 0, -focusDistance)), selected.Position)
			else CFrame.lookAt(Vector3.new(0, 7.6, -distance), Vector3.new(0, 7, 0))
		cameraGoal:set(goal)
		local displayed = if reducedMotion:peek() then goal else cameraMotion:peek()
		if selected then
			local fillDistance = math.min(selected.Size.X / (2 * tangent * aspect), selected.Size.Y / (2 * tangent))
			local filled =
				CFrame.lookAt(selected.CFrame:PointToWorldSpace(Vector3.new(0, 0, -fillDistance)), selected.Position)
			displayed = displayed:Lerp(filled, modeProgress:peek())
		end
		camera.CFrame = displayed
	end
	local connection = runService.RenderStepped:Connect(function(dt)
		model.step(dt, reducedMotion:peek())
		frameCamera()
	end)
	Compose.cleanup(function()
		connection:Disconnect()
	end)
	entrance:set(1)
	frameCamera()
	Host.BindableFunction "VirtualMonitorsAPI" {
		Parent = workspace,
		OnInvoke = Compose.static(function(command, argument)
			if command == "mode" and (argument == "Screen" or argument == "Spatial") then
				model.modeChosen = true
				mode:set(argument)
			elseif command == "dark" then
				dark:set(argument == true)
			elseif command == "accent" and (argument == "sage" or argument == "clay" or argument == "iris") then
				model.palette:set(argument)
			elseif command == "focus" then
				model.focus(argument)
			elseif command == "tab" then
				model.selectedTab:set(argument)
			elseif command == "open" then
				for _, item in model.catalog.items:peek() do
					if item.id == argument then
						model.selectGame(item)
						model.launchGame(item.id, "Joining a public server")
					end
				end
			elseif command == "close" then
				model.selectedGame:set(nil)
			elseif command == "summary" then
				model.avatarSummary:set(argument == true)
			elseif command == "about" or command == "status" then
				local key = model.selectedTab:peek() .. ":" .. mode:peek()
				local presentation = model.presentations[key]
				if presentation then
					presentation[command]:set(argument == true)
				end
			elseif command == "appearance" then
				model.avatarSettingsExpanded:set(argument == true)
			elseif command == "tips" then
				model.avatarTipsExpanded:set(argument == true)
			elseif command == "motion" then
				model.avatarPath:set(if argument == true then { { id = "motion", value = true } } else {})
			elseif command == "chat" then
				model.prompt(argument)
				model.chat.send()
			end
			return {
				mode = mode:peek(),
				dark = dark:peek(),
				accent = model.palette:peek(),
				focused = model.focused:peek(),
			}
		end),
	}
end, runtime.reactor)
script.Destroying:Connect(function()
	lifetime.dispose()
	runtime:dispose()
end)
