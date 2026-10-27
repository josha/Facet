--!strict
local CatalogTypes = require("./catalog_types")
type CameraRig = typeof(require("@repo/tools/typecheck/aliases").CameraRig)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	Host: typeof(require("@repo/tools/typecheck/aliases").RobloxHost),
	Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule),
}
local function Demo(c: Context, fieldOfView: number, motion: string, blocked: boolean, inertia: boolean): Frame
	local UI, Host, Compose = c.UI, c.Host, c.Compose
	local layer = Compose.cell<<ScreenGui?>>(nil)
	local presented = Compose.cell(false)
	local rig = Compose.cell<<CameraRig?>>(nil)
	local status =
		Compose.cell("Move this page onto the display. Look around the room, inspect the table, then return.")
	local function Room(): Model
		return Host.Model "SpatialDemoRoom" {
			Host.Part "Floor" {
				Anchored = true,
				Size = Vector3.new(20, 0.2, 20),
				CFrame = CFrame.new(0, -0.1, 0),
				Color = Color3.fromRGB(90, 77, 66),
				Material = Enum.Material.WoodPlanks,
			},
			Host.Part "DisplayCase" {
				Anchored = true,
				Size = Vector3.new(4.2, 2.7, 0.1),
				CFrame = CFrame.new(0, 2, 0.1),
				Color = Color3.fromRGB(35, 38, 43),
			},
			Host.Part "Table" {
				Anchored = true,
				Size = Vector3.new(3, 0.2, 2),
				CFrame = CFrame.new(2, 1, -2),
				Color = Color3.fromRGB(132, 99, 68),
				Material = Enum.Material.Wood,
			},
		}
	end
	local function Presentation(): Folder
		local player = assert(layer:peek()):FindFirstAncestorWhichIsA("PlayerGui")
		assert(player and player:IsA("PlayerGui"), "The Lab presentation requires PlayerGui")
		local camera = UI.cameraRig {
			inputRoot = player,
			initial = { focus = Vector3.new(0, 2, 0), yaw = -2.8, pitch = 0.15, distance = 9.5 },
			focusBounds = { min = Vector3.new(-3, 0, -3), max = Vector3.new(3, 4, 3) },
			yawBounds = Vector2.new(-math.pi, math.pi),
			pitchBounds = Vector2.new(-0.8, 0.8),
			distanceBounds = Vector2.new(4, 15),
			presets = {
				room = { focus = Vector3.new(0, 2, 0), yaw = -2.8, pitch = 0.15, distance = 9.5 },
				table = { focus = Vector3.new(2, 1, -2), yaw = -2.5, pitch = 0.4, distance = 5 },
			},
			enabled = presented,
			blocked = blocked,
			inertia = inertia,
			smoothing = true,
			orbitSensitivity = 0.005,
			panSensitivity = 0.01,
			orbitSpeed = 1.5,
			zoomSpeed = 8,
		}
		rig:set(camera)
		Compose.cleanup(function()
			rig:set(nil)
		end)
		return UI.DiegeticScreen "LabPresentation" {
			layers = { assert(layer:peek()) },
			isPresented = presented,
			scene = Room,
			surface = CFrame.new(0, 2, 0),
			bounds = Vector2.new(4, 2.5),
			camera = camera.camera,
			interactive = true,
			fieldOfView = fieldOfView,
			motion = motion,
			onUnavailable = function(reason: string)
				status:set(reason)
			end,
		}
	end
	local frame = UI.VStack "SpatialDemo" {
		width = "fill",
		UI.Text "SpatialStatus" { text = status, wrap = true },
		UI.Button "EnterSpatialDemo" {
			label = "Move Lab to display",
			enabled = Compose.formula(function(use): boolean
				return use(layer) ~= nil
			end),
			onActivate = function()
				presented:set(true)
			end,
		},
		UI.Text {
			text = "Drag empty space to orbit. Use two fingers to pan and pinch to zoom. Mouse wheel, WASD, arrows, right stick and triggers also work.",
			wrap = true,
		},
		UI.AdaptiveStack "CameraActions" {
			UI.Button {
				label = "Room",
				onActivate = function()
					local camera = rig:peek()
					if camera then
						camera.preset:set("room")
					end
				end,
			},
			UI.Button {
				label = "Table",
				onActivate = function()
					local camera = rig:peek()
					if camera then
						camera.preset:set("table")
					end
				end,
			},
			UI.Button {
				label = "Reset camera",
				onActivate = function()
					local camera = rig:peek()
					if camera then
						camera.reset()
					end
				end,
			},
			UI.Button {
				label = "Return to screen",
				onActivate = function()
					presented:set(false)
				end,
			},
		},
		Compose.show(layer, Presentation),
	}
	local connection = frame.AncestryChanged:Connect(function()
		if not layer:peek() then
			local source = frame:FindFirstAncestorWhichIsA("ScreenGui")
			if source and source:IsA("ScreenGui") then
				layer:set(source)
			end
		end
	end)
	Compose.cleanup(function()
		connection:Disconnect()
	end)
	return frame
end

local page: CatalogTypes.PageDefinition = {
	family = "layout",
	purpose = "Inspect the room and table with a bounded camera, then return with the same live Lab page.",
	alternatives = "Use Stage for a separate 3D preview inside a page.",
	matrix = false,
	demonstrates = {
		"layers",
		"isPresented",
		"scene",
		"surface",
		"bounds",
		"camera",
		"onUnavailable",
		"inputRoot",
		"initial",
		"focusBounds",
		"yawBounds",
		"pitchBounds",
		"distanceBounds",
		"presets",
		"enabled",
		"blocked",
		"inertia",
		"smoothing",
		"orbitSensitivity",
		"panSensitivity",
		"orbitSpeed",
		"zoomSpeed",
	},
	axes = { { key = "fieldOfView", values = { 40, 60 } } },
	states = {
		{ name = "room reveal", props = { motion = "move" } },
		{ name = "quick return", props = { motion = "quick" } },
		{ name = "camera input blocked", props = { blocked = true } },
		{ name = "no inertia", props = { inertia = false } },
	},
	make = function(
		_UI: FacetControls,
		p: { fieldOfView: number?, motion: string?, blocked: boolean?, inertia: boolean? },
		c: Context
	): Instance
		return Demo(c, p.fieldOfView or 48, p.motion or "move", p.blocked == true, p.inertia ~= false)
	end,
}
return page
