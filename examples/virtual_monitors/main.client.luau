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
		end, { seconds = 0.48 })
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
			table.insert(
				children,
				Host.Part({
					Name = name .. "Enclosure",
					Anchored = true,
					CanCollide = false,
					Size = Vector3.new(10.96, 10.8 * screens.CANVAS.h / screens.CANVAS.w + 0.16, 0.2),
					CFrame = function(use)
						local progress = if use(reducedMotion) then use(entrance) else use(arrival)
						return frame * CFrame.new(0, -2 * (1 - progress), 0.14 + 1.5 * (1 - progress))
					end,
					Color = Color3.fromRGB(35, 38, 47),
					Material = Enum.Material.Metal,
				})
			)

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
							return if use(dark) then 1.6 else 0.5
						end,
						Range = 22,
						Shadows = false,
					}),
				})
			)
		end
		table.insert(
			children,
			Host.Part({
				Name = "Floor",
				Anchored = true,
				Size = Vector3.new(200, 1, 200),
				CFrame = CFrame.new(0, -0.5, 0),
				Color = moodColor(Color3.fromRGB(24, 25, 38), Color3.fromRGB(173, 177, 187)),
				Material = Enum.Material.SmoothPlastic,
			})
		)
		table.insert(
			children,
			Host.Part({
				Name = "StudioBackdrop",
				Anchored = true,
				CanCollide = false,
				Size = Vector3.new(180, 100, 1),
				CFrame = CFrame.new(0, 30, 12),
				Color = moodColor(Color3.fromRGB(30, 31, 50), Color3.fromRGB(206, 211, 224)),
				Material = Enum.Material.SmoothPlastic,
			})
		)
		for _, side in { -1, 1 } do
			table.insert(
				children,
				Host.Part({
					Name = "AccentLight",
					Anchored = true,
					CanCollide = false,
					Size = Vector3.new(0.06, 24, 0.06),
					CFrame = CFrame.new(side * 20, 8, 9),
					Color = Color3.fromRGB(148, 128, 232),
					Material = Enum.Material.Neon,
					Host.PointLight({ Color = Color3.fromRGB(140, 119, 227), Brightness = 2, Range = 32 }),
				})
			)
		end
		return Host.Model(children)
	end, workspace)

	Compose.cleanup(stopWorld)
	scenes.prepareAvatar()
	Compose.cleanup(scenes.disposeAvatar)
	local modeProgress = Compose.formula(function(use)
		return if use(reducedMotion) then (if use(mode) == "Screen" then 1 else 0) else use(modeMotion)
	end)
	local function sceneActions(spatial, package)
		local actions = { model = model, spatial = spatial, theme = package, reducedMotion = reducedMotion }
		local function active(use)
			return if spatial then use(mode) == "Spatial" else use(mode) == "Screen"
		end
		actions.discoveryContent = function(sceneRuntime, target)
			return scenes.discovery(sceneRuntime, target)
		end
		actions.gameContent = function(current)
			return function(sceneRuntime, target)
				return scenes.card(sceneRuntime, target, current:peek(), motionPolicy, active)
			end
		end
		actions.avatarContent = function(sceneRuntime, target)
			return scenes.avatar(sceneRuntime, target, model.angle, model.palette, model.hat, motionPolicy, active)
		end
		return actions
	end
	for _, name in { "Discover", "Avatar", "Chat" } do
		runtime.mount(function()
			local package = theme.create(Facet, name)
			local sheet = Facet.themes.createStyleSheet(runtime, package, {
				reducedMotion = reducedMotion,
				theme = function(use)
					return if use(dark) then "Dark" else "Light"
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
				Brightness = 1.3,
				MaxDistance = 100,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Enabled = function(use)
					return use(modeProgress) < 1
				end,
				sheet,
				Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				Compose.show(function(use)
					return use(modeProgress) < 1
				end, views[name]),
			})
		end, players.LocalPlayer:WaitForChild("PlayerGui"))
	end
	runtime.mount(function()
		local package = theme.create(Facet, "Discover")
		local sheet = Facet.themes.createStyleSheet(runtime, package, {
			reducedMotion = reducedMotion,
			theme = function(use)
				return if use(dark) then "Dark" else "Light"
			end,
		})
		local views = screens.create(Facet, runtime, sceneActions(false, package))
		return Host.ScreenGui({
			Name = "VirtualMonitorsDesktop",
			DisplayOrder = 10,
			ResetOnSpawn = false,
			ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Enabled = function(use)
				return use(modeProgress) > 0
			end,
			sheet,
			Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
			Compose.show(
				function(use)
					return use(modeProgress) > 0
				end,
				desktop.create(
					Facet,
					runtime,
					views,
					model,
					modeProgress,
					{ theme = package, reducedMotion = reducedMotion }
				)
			),
		})
	end, players.LocalPlayer:WaitForChild("PlayerGui"))
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
end, runtime.reactor)
script.Destroying:Connect(function()
	lifetime.dispose()
	runtime:dispose()
end)
