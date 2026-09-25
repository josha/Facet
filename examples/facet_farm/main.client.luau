--!strict
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local storage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

local starterGui = game:GetService("StarterGui")
for _ = 1, 10 do
	if pcall(starterGui.SetCoreGuiEnabled, starterGui, Enum.CoreGuiType.All, false) then
		break
	end
	task.wait(0.2)
end
pcall(starterGui.SetCore, starterGui, "ResetButtonCallback", false)
local Facet = require(storage:WaitForChild("Facet"))
local Compose = Facet.Compose
local farmFolder = storage:WaitForChild("FacetFarm")
local modelModule = require(farmFolder:WaitForChild("model"))
local screens = require(farmFolder:WaitForChild("screens"))
local theme = require(farmFolder:WaitForChild("theme"))
local world = require(farmFolder:WaitForChild("world"))

local package = theme.create(Facet)
local backdrop = Facet.app({
	name = "FacetFarmBackdrop",
	theme = package,
	screen = { ScreenInsets = Enum.ScreenInsets.None, DisplayOrder = 0 },
})
local app = Facet.app({ name = "FacetFarm", theme = package, screen = { DisplayOrder = 1 } })
local UI = app.UI
local types = {
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	Color3 = Color3,
	Enum = Enum,
}
local farm = modelModule.new(Compose, os.clock)
local guiService = game:GetService("GuiService")
local camera = workspace.CurrentCamera

local layout = Compose.cell(0)
local watched: { RBXScriptConnection } = {}
local function remeasure()
	layout:update(function(value: number): number
		return value + 1
	end)
end
local function follow(node: GuiObject?)
	if node then
		table.insert(watched, node:GetPropertyChangedSignal("AbsoluteSize"):Connect(remeasure))
		table.insert(watched, node:GetPropertyChangedSignal("AbsolutePosition"):Connect(remeasure))
	end
end
table.insert(watched, camera:GetPropertyChangedSignal("ViewportSize"):Connect(remeasure))
local function openArea(): Rect
	local viewport = camera.ViewportSize
	local top = guiService:GetGuiInset().Y
	local left, right, bottom = 0, viewport.X, viewport.Y
	local gui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("FacetFarm")
	local controls = gui and gui:FindFirstChild("Controls", true) :: GuiObject?
	local hud = gui and gui:FindFirstChild("Hud", true) :: GuiObject?
	if hud and hud.Visible then
		top = math.max(top, hud.AbsolutePosition.Y + hud.AbsoluteSize.Y + guiService:GetGuiInset().Y)
	end
	if controls then
		local position = controls.AbsolutePosition + Vector2.new(0, guiService:GetGuiInset().Y)

		local besideWidth = position.X - left
		local aboveHeight = position.Y - top
		if besideWidth * (bottom - top) > aboveHeight * (right - left) then
			right = position.X
		else
			bottom = position.Y
		end
	end
	local margin = 20
	return Rect.new(
		left + margin,
		top + margin,
		math.max(left + margin + 1, right - margin),
		math.max(top + margin + 1, bottom - margin)
	)
end
app.mount(function()
	local reduced = Compose.cell(guiService.ReducedMotionEnabled)
	local changed = guiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		reduced:set(guiService.ReducedMotionEnabled)
	end)
	Compose.cleanup(function()
		changed:Disconnect()
	end)
	farm.blend = app.runtime.tween(function(use)
		return if use(farm.view) == "3d" then 1 else 0
	end, {
		seconds = function()
			return if reduced:peek() then 0.01 else 1.4
		end,
		ease = Compose.easing.inOutCubic,
	})
	Compose.watch(function(use)
		local blend = use(farm.blend)
		if blend <= 0 then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			return
		end
		use(layout)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		local sweep = math.clamp((blend - 0.35) / 0.65, 0, 1)
		local fitted = world.fitFrame(openArea(), function(frame: CFrame, point: Vector3): Vector2
			camera.CFrame = frame
			local screen = camera:WorldToViewportPoint(point)
			return Vector2.new(screen.X, screen.Y)
		end)
		camera.CFrame = world.topFrame():Lerp(fitted, sweep)
	end)
	local view = screens.farm(Facet, UI, app.runtime.constructors, types, farm)
	task.defer(function()
		local gui = game.Players.LocalPlayer.PlayerGui:WaitForChild("FacetFarm")
		follow(gui:FindFirstChild("Controls", true) :: GuiObject?)
		follow(gui:FindFirstChild("Hud", true) :: GuiObject?)
		remeasure()
	end)
	return view
end)
local SOUNDS = {
	plow = { "rbxassetid://9114083746", 0.5 },
	plant = { "rbxassetid://9118685574", 0.45 },
	harvest = { "rbxassetid://109359226723492", 0.5 },
	coins = { "rbxassetid://1169806635", 0.4 },
}
local effects = {}
backdrop.runtime.mount(function()
	local players = {}
	for name, sound in SOUNDS do
		local player = backdrop.runtime.constructors.Sound(name)({ SoundId = sound[1], Volume = sound[2] })
		effects[name] = player
		table.insert(players, player)
	end
	Compose.watch(function(use)
		local cue = use(farm.cue)
		if not cue then
			return
		end
		effects[cue.name]:Play()
		if cue.name == "harvest" then
			effects.coins:Play()
		end
	end)
	return backdrop.runtime.constructors.SoundGroup "FarmEffects"(players)
end, game:GetService("SoundService"))

local MUSIC = "rbxassetid://121626073601812"
backdrop.runtime.mount(function()
	return backdrop.runtime.constructors.Sound "FarmMusic" {
		SoundId = MUSIC,
		Looped = true,
		Volume = 0.35,
		Playing = function(use)
			return use(farm.music)
		end,
	}
end, game:GetService("SoundService"))
backdrop.mount(function()
	return screens.backdrop(backdrop.runtime.constructors, types, farm)
end)
local stopWorld = world.mount(app.runtime, Compose, farm, workspace)
local elapsed = 0
local beat = runService.Heartbeat:Connect(function(step)
	elapsed += step
	if elapsed >= 0.25 then
		elapsed = 0
		farm.tick()
	end
end)
script.Destroying:Connect(function()
	beat:Disconnect()
	for _, connection in watched do
		connection:Disconnect()
	end
	stopWorld()
	app.dispose()
	backdrop.dispose()
end)
