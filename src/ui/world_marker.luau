--!strict
local Types = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")
local HudProps = require("./hud_props")
local Env = require("./environment_types")
local layoutKit = require("./layout_kit")

type Props = HudProps.WorldMarkerProps

local EDGES: { [string]: boolean } = { clamp = true, hide = true }

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, Compose, read, types, runtime = ctx.Host, ctx.Compose, ctx.read, ctx.types, ctx.runtime
	local D2, V2 = types.UDim2, types.Vector2
	local kit = layoutKit.of(ctx)
	UI.WorldMarker = ctx.construct("WorldMarker", function(spec: Props): Frame
		assert(spec.anchor ~= nil, "Facet WorldMarker requires an anchor from UI.worldAnchor")
		local placed = Compose.cell(V2.zero)
		local content = Compose.cell(V2.zero)
		local function pad(use: ComposeTypes.Use?): number
			return if read(spec.arrow, use) == false then 0 else ctx.controlSize(nil, "iconSize", use) + 8
		end
		local shown = Compose.cell(false)
		local clamped = Compose.cell(false)
		local heading = Compose.cell(0)
		local root = Host.Frame(ctx.props(spec, { "anchor", "edge", "margin", "arrow" }, {
			BackgroundTransparency = 1,
			AnchorPoint = V2.new(0.5, 0.5),
			Size = function(use: ComposeTypes.Use): UDim2
				local inner, ring = use(content), pad(use)
				return D2.fromOffset(inner.X + 2 * ring, inner.Y + 2 * ring)
			end,
			Position = function(use: ComposeTypes.Use): UDim2
				local at = use(placed)
				return D2.fromOffset(at.X, at.Y)
			end,
			Visible = function(use: ComposeTypes.Use): boolean
				return use(shown)
			end,
		}))
		local ring = Host.UIPadding {
			PaddingTop = function(use: ComposeTypes.Use): UDim
				return types.UDim.new(0, pad(use))
			end,
			PaddingBottom = function(use: ComposeTypes.Use): UDim
				return types.UDim.new(0, pad(use))
			end,
			PaddingLeft = function(use: ComposeTypes.Use): UDim
				return types.UDim.new(0, pad(use))
			end,
			PaddingRight = function(use: ComposeTypes.Use): UDim
				return types.UDim.new(0, pad(use))
			end,
		}
		ring.Parent = root
		local pointer = Host.Folder "Pointer" {}
		pointer.Parent = root
		local arrow = ctx.styled(
			Host.Frame "Arrow" {
				AnchorPoint = V2.new(0.5, 0.5),
				Size = function(use: ComposeTypes.Use): UDim2
					local side = pad(use)
					return D2.fromOffset(side, side)
				end,
				Visible = function(use: ComposeTypes.Use): boolean
					return use(clamped) and read(spec.arrow, use) ~= false
				end,
				Rotation = function(use: ComposeTypes.Use): number
					return math.deg(use(heading))
				end,
				Host.UICorner({ CornerRadius = types.UDim.new(0.5, 0) }),
				ctx.icon("chevron.trailing", {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.fromScale(0.7, 0.7),
				}),
			},
			"badge"
		)
		arrow.Parent = pointer
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("Clamped", use(clamped))
		end)
		local watched: { [Instance]: RBXScriptConnection } = {}
		local unit = ctx.layoutUnit(root, "MarkerUnit")
		local function measure()
			local widest, tallest = 0, 0
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					widest = math.max(widest, child.AbsoluteSize.X)
					tallest = math.max(tallest, child.AbsoluteSize.Y)
				end
			end
			local factor = unit:peek()
			local scale = if factor > 0 then factor else 1
			local value = V2.new(widest / scale, tallest / scale)
			if content:peek() ~= value then
				content:set(value)
			end
		end
		local function track(child: Instance)
			if child:IsA("GuiObject") and watched[child] == nil then
				watched[child] = child:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
			end
			measure()
		end
		for _, child in root:GetChildren() do
			track(child)
		end
		runtime.connect(root, "ChildAdded", track)
		runtime.connect(root, "ChildRemoved", function(child: Instance)
			local connection = watched[child]
			if connection then
				connection:Disconnect()
				watched[child] = nil
			end
			measure()
		end)
		Compose.cleanup(function()
			for _, connection in watched do
				connection:Disconnect()
			end
			table.clear(watched)
		end)
		local size = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			local point = read(spec.anchor, use) :: Env.WorldAnchorPoint
			local edge = read(spec.edge, use) or "clamp"
			assert(EDGES[edge] == true, "Facet WorldMarker edge must be clamp or hide")
			local extent = use(size)
			local requested = read(spec.margin, use)
			local function side(key: "top" | "right" | "bottom" | "left"): number
				if type(requested) == "table" then
					local value = (requested :: Types.Sides)[key]
					return kit.spacing(if value == nil then "m" else value, use)
				end
				return kit.spacing(if requested == nil then "m" else requested :: Types.Space, use)
			end
			local parent = root.Parent
			if not point.visible or point.x == nil or point.y == nil or not (parent and parent:IsA("GuiObject")) then
				shown:set(false)
				return
			end
			local holder = parent :: GuiObject
			local x, y = point.x :: number, point.y :: number
			local layer = root:FindFirstAncestorWhichIsA("ScreenGui")
			local gui = ctx.config.guiService
			if layer and not layer.IgnoreGuiInset and gui then
				local ok, inset = pcall(gui.GetGuiInset, gui)
				if ok and typeof(inset) == "Vector2" then
					x, y = x - inset.X, y - inset.Y
				end
			end
			local origin, room = holder.AbsolutePosition, holder.AbsoluteSize
			x, y = x - origin.X, y - origin.Y
			local half = extent / 2
			local left, top = side("left") + half.X, side("top") + half.Y
			local right, bottom = room.X - side("right") - half.X, room.Y - side("bottom") - half.Y
			local inside = point.onscreen ~= false and x >= left and x <= right and y >= top and y <= bottom
			if inside then
				placed:set(V2.new(x, y))
				clamped:set(false)
				shown:set(true)
				return
			end
			if edge == "hide" then
				shown:set(false)
				return
			end
			local cx, cy = (left + right) / 2, (top + bottom) / 2
			local dx, dy = x - cx, y - cy
			if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then
				dy = 1
			end
			local spanX, spanY = math.max(0, (right - left) / 2), math.max(0, (bottom - top) / 2)
			local scale = math.min(
				if math.abs(dx) > 0.001 then spanX / math.abs(dx) else math.huge,
				if math.abs(dy) > 0.001 then spanY / math.abs(dy) else math.huge
			)
			local angle = math.atan2(dy, dx)
			placed:set(V2.new(cx + dx * scale, cy + dy * scale))
			heading:set(angle)
			local inset = pad() / 2
			local cos, sin = math.cos(angle), math.sin(angle)
			local reach = math.min(
				if math.abs(cos) > 0.001 then math.max(0, half.X - inset) / math.abs(cos) else math.huge,
				if math.abs(sin) > 0.001 then math.max(0, half.Y - inset) / math.abs(sin) else math.huge
			)
			arrow.Position = D2.new(0.5, cos * reach, 0.5, sin * reach)
			clamped:set(true)
			shown:set(true)
		end)
		return root
	end)
end
