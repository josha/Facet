--!strict
local CatalogTypes = require("./catalog_types")
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Context = CatalogTypes.Context
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)

type Point = { x: number?, y: number?, clearance: number?, visible: boolean, onscreen: boolean?, occluded: boolean? }
type Spot = { x: number, y: number, onscreen: boolean, label: string }
local SPOTS: { Spot } = {
	{ x = 0.5, y = 0.45, onscreen = true, label = "In view" },
	{ x = 1.8, y = 0.4, onscreen = false, label = "Off to the right" },
	{ x = -0.6, y = -0.8, onscreen = false, label = "Behind, up and left" },
	{ x = 0.25, y = 1.9, onscreen = false, label = "Below" },
}

local function Demo(c: Context, edge: "clamp" | "hide", arrow: boolean): Instance
	local UI, Host, Compose = c.UI, c.Host, c.Compose
	local spot = Compose.cell(1)
	local anchor = Compose.cell({ visible = false } :: Point)
	local field: Frame? = nil
	local function project()
		local holder = field
		if holder == nil then
			return
		end
		local s = SPOTS[spot:peek()]
		local at, size = holder.AbsolutePosition, holder.AbsoluteSize
		local layer = holder:FindFirstAncestorWhichIsA("ScreenGui")
		local inset = if layer and not layer.IgnoreGuiInset
			then game:GetService("GuiService"):GetGuiInset()
			else Vector2.zero
		anchor:set({
			visible = true,
			x = at.X + s.x * size.X + inset.X,
			y = at.Y + s.y * size.Y + inset.Y,
			onscreen = s.onscreen,
		})
	end
	local frame = Host.Frame "Field" {
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundTransparency = 1,

		UI.WorldMarker "Marker" {
			anchor = anchor,
			edge = edge,
			arrow = arrow,
			margin = "s",
			UI.Badge { label = "Golden grass", status = "warning" },
		},
	}
	field = frame
	local sizeChanged = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(project)
	local positionChanged = frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(project)
	Compose.cleanup(function()
		field = nil
		sizeChanged:Disconnect()
		positionChanged:Disconnect()
	end)
	task.defer(project)
	return UI.VStack "MarkerDemo" {
		gap = "s",
		align = "stretch",
		frame,
		UI.Text {
			text = function(use: Use)
				return SPOTS[use(spot)].label
			end,
		},
		UI.Button {
			label = "Move the target",
			onActivate = function()
				spot:set(spot:peek() % #SPOTS + 1)
				project()
			end,
		},
	}
end

local page: CatalogTypes.PageDefinition = {
	family = "media",
	purpose = "Point to a world target, and keep pointing from the screen edge when it is off screen.",
	alternatives = "Use worldAnchor alone to place a RadialMenu.",
	snippet = 'UI.WorldMarker { anchor = UI.worldAnchor({ target = patch, offscreen = "retain" }).anchor }',
	demonstrates = { "anchor", "edge", "margin", "arrow" },
	axes = { { key = "edge", values = { "clamp", "hide" } }, { key = "arrow", values = { true, false } } },
	states = {},
	make = function(_UI: FacetControls, p: { edge: ("clamp" | "hide")?, arrow: boolean? }, c: Context): Instance
		return Demo(c, p.edge or "clamp", p.arrow ~= false)
	end,
}
return page
