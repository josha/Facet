--!strict
-- World geometry belongs to the showcase; all interface objects and input belong
-- to Facet. See docs/guide/03-getting-started.md for the ordinary component host.
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local starterGui = game:GetService("StarterGui")
starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
game:GetService("GuiService").TouchControlsEnabled = false
task.spawn(function()
	-- Core scripts can register SetCore after the place finishes loading.
	for _ = 1, 30 do
		local ready = pcall(function()
			starterGui:SetCore("TopbarEnabled", false)
		end)
		if ready then
			return
		end
		task.wait(0.1)
	end
	warn("Virtual Monitors: Roblox did not register the topbar setting")
end)
local storage = game:GetService("ReplicatedStorage")
local Facet = require(storage:WaitForChild("Facet"))
local ComposeRoblox = require(storage.Facet.client.scene)
local screens = require(storage.VirtualMonitors.screens)
local theme = require(storage.VirtualMonitors.theme)
local scenes = require(storage.VirtualMonitors.scenes)
scenes.prepareAvatar()
local conversation = require(storage.VirtualMonitors.chat_model).new(Facet.Compose)
local catalog = require(storage.VirtualMonitors.catalog).new(Facet.Compose)
local mode, selectedTab = Facet.Compose.cell("Spatial"), Facet.Compose.cell("Discover")
local modeChosen = false
-- Scene state is shared across the three independent UI hosts.
local Compose = Facet.Compose
local lifetime = Compose.createOwner()
local dark = Compose.cell(true)
local entrance = Compose.cell(0)
local reducedMotion = Compose.cell(false)
local focused = Compose.cell("Overview")
local cameraGoal = Compose.cell(CFrame.lookAt(Vector3.new(0, 7.6, -29), Vector3.new(0, 7, 0)))
local cameraMotion: any
local modeMotion: any
local world = ComposeRoblox.createRuntime()
local Host = world.constructors
local parts = {}
local stopWorld = world.mount(function()
	modeMotion = world.tween(function(use)
		return if use(mode) == "Screen" then 1 else 0
	end, { seconds = 0.48 })
	cameraMotion = world.spring(function(use)
		return use(cameraGoal)
	end, { period = 0.65, damping = 1 })
	local arrival = world.spring(function(use)
		return use(entrance)
	end, { period = 0.8, damping = 0.9 })
	-- Color3 uses Compose's Roblox codec, with the same interruption and
	-- ownership semantics as the camera. Reduced motion reads the goal directly.
	local function moodColor(night, day)
		local function goal(use)
			return if use(dark) then night else day
		end
		local animated = world.spring(goal, { period = 0.55, damping = 1 })
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
		-- Bias light: each monitor washes the wall behind it in its accent.
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
					Color = if name == "Discover" then Color3.fromRGB(120, 214, 182) else Color3.fromRGB(170, 150, 255),
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
			Reflectance = 0.16,
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

local hosts, themes = {}, {}
-- Shared scene state is owned by the showcase, outside any mounted component.
local angle = Compose.cell(-15)
local palette = Facet.Compose.cell("sage")
local hat = Facet.Compose.cell(true)
local selectedGame, savedGames = Facet.Compose.cell(nil), Facet.Compose.cell({})
-- `{ [gameId]: string }`. Shared across every host (per-monitor and Screen
-- canvas alike) so a note survives a shelf switch or a mode change same as
-- `savedGames` itself.
local savedNotes = Facet.Compose.cell({})
local modeProgress = Compose.formula(function(use)
	return if use(reducedMotion) then (if use(mode) == "Screen" then 1 else 0) else use(modeMotion)
end)
local appActions = {
	modeLabel = function(use)
		return if use(mode) == "Spatial" then "Screen mode" else "Spatial mode"
	end,
	toggleMode = function()
		modeChosen = true
		if mode:peek() == "Spatial" then
			local active = focused:peek()
			if active ~= "Overview" then
				selectedTab:set(active)
			end
			focused:set(selectedTab:peek())
			mode:set("Screen")
		else
			focused:set(selectedTab:peek())
			mode:set("Spatial")
		end
	end,
	hidden = function(use)
		return use(modeProgress) >= 1
	end,
	chatScroll = Facet.Compose.cell(0),
	discoveryScroll = Facet.Compose.cell(0),
	scrollActive = function(use)
		return use(mode) == "Spatial"
	end,
	chat = conversation,
	catalog = catalog,
	selectedGame = selectedGame,
	savedGames = savedGames,
	savedNotes = savedNotes,
	discoveryGenre = Facet.Compose.cell(nil),
	discoveryQuery = Facet.Compose.cell(""),
	discoverySort = Facet.Compose.cell("recommended"),
	discoveryShelf = Facet.Compose.cell("browse"),
	discoveryPath = Facet.Compose.cell({}),
	savedOrder = Facet.Compose.cell({}),
	gameRatings = Facet.Compose.cell({}),
	chatPromptUsed = Facet.Compose.cell(false),
	chatFollow = Facet.Compose.cell(true),
	avatarPalette = palette,
	avatarHat = hat,
	avatarSettingsExpanded = Compose.cell(true),
	needsFocus = function(name)
		return function(use)
			return use(focused) ~= name
		end
	end,
	focusLabel = function(name)
		return function(use)
			return if use(focused) == name then "All monitors" else "Focus"
		end
	end,
	focus = function(name)
		focused:set(if focused:peek() == name then "Overview" else name)
	end,
	appearanceLabel = function(use)
		return if use(dark) then "Light mode" else "Dark mode"
	end,
	toggleAppearance = function()
		local nextDark = not dark:peek()
		for _, controller in themes do
			controller.swap(if nextDark then "Dark" else "Light")
		end
		dark:set(nextDark)
	end,
	avatarAngle = angle,
	avatarAutoSpin = Facet.Compose.cell(0),
	-- ONE auto-spin driver for the whole showcase. `angle` is shared model state
	-- and both presentations mount an Avatar view, so without a single claim the
	-- preview integrates twice per frame while a mode transition has both alive.
	-- Shared by REFERENCE through every `table.clone` of this table.
	avatarSpinDriver = {},
	avatarSummaryShown = Facet.Compose.cell(false),
	avatarSummaryDetent = Facet.Compose.cell("medium"),
	avatarTipsExpanded = Facet.Compose.cell(false),
	-- Non-nil, but leaves `bind` unset so Discover's creator-avatar provider
	-- loads the real Roblox transport instead of the spec-world default.
	resourceProviderOptions = {},
}
local function sceneCallbacks(actions, app)
	local result = table.clone(actions)
	result.discoveryContent = function(stage)
		stage.setCamera({ position = { x = -11, y = 10, z = -17 }, lookAt = { x = 0, y = 1.2, z = 2 }, fov = 43 })
		stage.setLighting({ ambient = { r = 0.7, g = 0.7, b = 0.65 }, lightDirection = { x = -1, y = -1, z = -1 } })
		return scenes.discovery(world, stage.contentRoot())
	end
	result.gameContent = function(item)
		return function(stage)
			local gameItem = item:peek()
			stage.setCamera({ position = { x = -10, y = 8, z = -13 }, lookAt = { x = 0, y = 1, z = 0 }, fov = 43 })
			stage.setLighting({
				ambient = { r = 0.65, g = 0.68, b = 0.75 },
				lightColor = { r = 1, g = 0.92, b = 0.8 },
				lightDirection = { x = -1, y = -1, z = -0.5 },
			})
			return scenes.card(
				world,
				stage.contentRoot(),
				gameItem,
				app.environment:get("motionPolicy"),
				actions.scrollActive
			)
		end
	end
	result.avatarContent = function(stage)
		stage.setCamera({ position = { x = 0, y = 3.4, z = -11 }, lookAt = { x = 0, y = 2.5, z = 0 }, fov = 36 })
		stage.setLighting({
			ambient = { r = 0.36, g = 0.39, b = 0.47 },
			lightColor = { r = 1, g = 0.91, b = 0.78 },
			lightDirection = { x = -0.7, y = -0.8, z = 1 },
		})
		return scenes.avatar(
			world,
			stage.contentRoot(),
			angle,
			palette,
			hat,
			app.environment:get("motionPolicy"),
			actions.scrollActive
		)
	end
	return result
end
local function installTheme(app, package)
	return app.installTheme(package, {
		transitions = true,
		sheetModel = theme.sheet(Facet.themes, package, app.environment:get("effectiveDisplaySize"):peek()),
	})
end
for _, name in { "Discover", "Avatar", "Chat" } do
	local package = theme.create(Facet, name)
	local app = Facet.new({
		surface = {
			kind = "surface",
			target = parts[name],
			face = Enum.NormalId.Front,
			canvas = screens.CANVAS,
			maxDistance = 100,
		},
		style = Facet.themes.styleFor(package),
		nativeStyle = { transitions = true },
		themePackage = package,
	})
	hosts[name] = app
	local monitorCallbacks = sceneCallbacks(appActions, app)
	local views = screens.create(Facet, app, monitorCallbacks)
	-- A monitor is mounted while it can be seen. The screen presentation owns
	-- input alone, so a covered monitor holds no focus and hears no keys. The
	-- shared model keeps every selection, draft and scroll position.
	local close
	lifetime.watch(function(use)
		local covered = use(mode) == "Screen" and use(modeProgress) >= 1
		if covered and close then
			close()
			close = nil
		elseif not covered and close == nil then
			close = app.mount(function()
				return app.controls.Screen(name .. "Monitor")({ views[name]() })
			end)
		end
	end)
	themes[name] = installTheme(app, package)
end
local screenActions = table.clone(appActions)
screenActions.hidden, screenActions.needsFocus, screenActions.spatial = nil, nil, false
screenActions.scrollActive = function(use)
	return use(mode) == "Screen"
end
local desktopPackage = theme.create(Facet, "Discover")
local desktopApp = Facet.new({
	style = Facet.themes.styleFor(desktopPackage),
	themePackage = desktopPackage,
	nativeStyle = { transitions = true },
	displayOrder = 10,
})
hosts.Desktop = desktopApp
-- The viewport can arrive after host construction. Compact space and ten-foot
-- displays get a readable default until the user makes an explicit choice.
lifetime.watch(function(use)
	local environment = desktopApp.environment
	local needsScreen = use(environment:get("sizeClass")) == "compact"
		or use(environment:get("distanceProfile")) == "ten-foot"
	if needsScreen and not modeChosen then
		focused:set(selectedTab:peek())
		mode:set("Screen")
	end
end)
local desktopCallbacks = sceneCallbacks(screenActions, desktopApp)
local screenApps = screens.create(Facet, desktopApp, desktopCallbacks)
local Desktop =
	require(storage.VirtualMonitors.desktop).create(Compose, desktopApp, screenApps, mode, selectedTab, modeProgress)
desktopApp.mount(Desktop, { rootPolicy = "edgeToEdge" })
themes.Desktop = installTheme(desktopApp, desktopPackage)
local stopMotionPolicy = lifetime.watch(function(use)
	reducedMotion:set(use(hosts.Avatar.environment:get("motionPolicy")) == "reduced")
end)
entrance:set(1)

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 48
local function frameCamera()
	local viewport = camera.ViewportSize
	local aspect = math.max(0.1, viewport.X / math.max(1, viewport.Y))
	local tangent = math.tan(math.rad(camera.FieldOfView / 2))
	local distance = math.max(34 / (2 * tangent * aspect), 10 / (2 * tangent)) * 1.08 + 5
	camera.CameraType = Enum.CameraType.Scriptable
	local selected = parts[focused:peek()]
	-- Fit BOTH dimensions of the selected surface, including portrait windows.
	-- The canvas keeps its state and resolution while the viewing distance adapts.
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
frameCamera()
--[[ THE CAMERA DRIVER IS AUDIBLE WHEN IT FAILS.

	`presenter.onTick` quarantines a throwing hook with a bare `pcall` and
	reports nothing, which is right for not starving the hook's siblings and
	wrong for ever finding out. This hook OWNS the camera: if it throws, the
	camera simply stops moving and keeps whatever pose it last wrote — a frozen
	overview that looks exactly like "focusing a monitor did nothing", with no
	line anywhere saying a frame failed. One warn per distinct failure: enough
	to name it, never sixty a second. ]]
local cameraFault: string? = nil
local stopCamera = hosts.Discover.onFrame(function()
	local ok, err = pcall(frameCamera)
	if ok then
		cameraFault = nil
		return
	end
	local message = tostring(err)
	if message ~= cameraFault then
		cameraFault = message
		warn("VirtualMonitors: the camera driver failed and the view is frozen - " .. message)
	end
end)
local stopChat = hosts.Chat.onFrame(conversation.step)
local stopCatalog = hosts.Discover.onFrame(catalog.step)

script.Destroying:Connect(function()
	stopChat()
	stopCatalog()
	catalog.dispose()
	conversation.dispose()
	stopCamera()
	stopMotionPolicy()
	lifetime.dispose()
	for _, app in hosts do
		app.dispose()
	end
	stopWorld()
	world.dispose()
	scenes.disposeAvatar()
end)
