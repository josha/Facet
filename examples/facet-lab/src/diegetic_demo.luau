--!strict
local CatalogTypes = require("./catalog_types")
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	Host: typeof(require("@repo/tools/typecheck/aliases").RobloxHost),
	Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule),
}
local function Demo(c: Context, fieldOfView: number, motion: string): Frame
	local UI, Host, Compose = c.UI, c.Host, c.Compose
	local layer = Compose.cell<<ScreenGui?>>(nil)
	local presented = Compose.cell(false)
	local status = Compose.cell("Move this live Lab page onto the display. Tap it to return.")
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
		}
	end
	local function Presentation(): Folder
		return UI.DiegeticScreen "LabPresentation" {
			layers = { assert(layer:peek()) },
			isPresented = presented,
			scene = Room,
			surface = CFrame.new(0, 2, 0),
			bounds = Vector2.new(4, 2.5),
			camera = CFrame.lookAt(Vector3.new(-3, 3.5, -9), Vector3.new(0, 2, 0)),
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
	purpose = "Move the same live Lab page onto a world display and return without losing its state.",
	alternatives = "Use Stage for a separate 3D preview inside a page.",
	matrix = false,
	demonstrates = { "layers", "isPresented", "scene", "surface", "bounds", "camera", "onUnavailable" },
	axes = { { key = "fieldOfView", values = { 40, 60 } } },
	states = {
		{ name = "room reveal", props = { motion = "move" } },
		{ name = "quick return", props = { motion = "quick" } },
	},
	make = function(_UI: FacetControls, p: { fieldOfView: number?, motion: string? }, c: Context): Instance
		return Demo(c, p.fieldOfView or 48, p.motion or "move")
	end,
}
return page
