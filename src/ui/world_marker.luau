--!strict
local Types = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")
local HudProps = require("./hud_props")
local Env = require("./environment_types")
local layoutKit = require("./layout_kit")

type Props = HudProps.WorldMarkerProps

local EDGES: { [string]: boolean } = { clamp = true, hide = true }
local STILL_PIXELS = 1
local STILL_RADIANS = 0.025

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
		local watched: { [Instance]: { RBXScriptConnection } } = {}
		local unit = ctx.layoutUnit(root, "MarkerUnit")
		local function measure()
			local widest, tallest = 0, 0
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					if child.Size.X.Scale == 0 then
						widest = math.max(widest, child.AbsoluteSize.X)
					end
					if child.Size.Y.Scale == 0 then
						tallest = math.max(tallest, child.AbsoluteSize.Y)
					end
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
				watched[child] = {
					child:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure),
					child:GetPropertyChangedSignal("Visible"):Connect(measure),
				}
			end
			measure()
		end
		for _, child in root:GetChildren() do
			track(child)
		end
		runtime.connect(root, "ChildAdded", track)
		runtime.connect(root, "ChildRemoved", function(child: Instance)
			local connections = watched[child]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
				watched[child] = nil
			end
			measure()
		end)
		local geometry = Compose.cell(0)
		local holding: { RBXScriptConnection } = {}
		local function release()
			for _, connection in holding do
				connection:Disconnect()
			end
			table.clear(holding)
		end
		local function bump()
			geometry:set(geometry:peek() + 1)
		end
		local function hold()
			release()
			local parent = root.Parent
			if parent and parent:IsA("GuiObject") then
				table.insert(holding, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(bump))
				table.insert(holding, parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(bump))
			end
			bump()
		end
		runtime.connect(root, "AncestryChanged", hold)
		hold()
		Compose.cleanup(function()
			release()
			for _, connections in watched do
				for _, connection in connections do
					connection:Disconnect()
				end
			end
			table.clear(watched)
		end)
		local size = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			local point = ctx.readSource(spec.anchor, use) :: Env.WorldAnchorPoint
			local edge = read(spec.edge, use) or "clamp"
			assert(EDGES[edge] == true, "Facet WorldMarker edge must be clamp or hide")
			use(geometry)
			local factor = use(unit)
			local scale = if factor > 0 then factor else 1
			local extent = use(size) / scale
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
			local gui = ctx.config.guiService
			if gui and root:FindFirstAncestorWhichIsA("ScreenGui") then
				local ok, inset = pcall(gui.GetGuiInset, gui)
				if ok and typeof(inset) == "Vector2" then
					x, y = x - inset.X, y - inset.Y
				end
			end
			local origin, room = holder.AbsolutePosition, holder.AbsoluteSize / scale
			x, y = (x - origin.X) / scale, (y - origin.Y) / scale
			local half = extent / 2
			local left, top = side("left") + half.X, side("top") + half.Y
			local right, bottom = room.X - side("right") - half.X, room.Y - side("bottom") - half.Y
			local inside = point.onscreen ~= false and x >= left and x <= right and y >= top and y <= bottom
			local function place(at: Vector2)
				local snapped = V2.new(math.round(at.X), math.round(at.Y))
				if (snapped - placed:peek()).Magnitude >= STILL_PIXELS or not shown:peek() then
					placed:set(snapped)
				end
			end
			if inside then
				place(V2.new(x, y))
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
			local reachEdge = math.min(
				if math.abs(dx) > 0.001 then spanX / math.abs(dx) else math.huge,
				if math.abs(dy) > 0.001 then spanY / math.abs(dy) else math.huge
			)
			local turned = math.atan2(dy, dx)
			local delta = (turned - heading:peek() + math.pi) % (2 * math.pi) - math.pi
			if math.abs(delta) >= STILL_RADIANS or not clamped:peek() then
				heading:set(turned)
			end
			local angle = heading:peek()
			place(V2.new(cx + dx * reachEdge, cy + dy * reachEdge))
			local inset = pad() / 2
			local cos, sin = math.cos(angle), math.sin(angle)
			local reach = math.min(
				if math.abs(cos) > 0.001 then math.max(0, half.X - inset) / math.abs(cos) else math.huge,
				if math.abs(sin) > 0.001 then math.max(0, half.Y - inset) / math.abs(sin) else math.huge
			)
			arrow.Position = D2.new(0.5, math.round(cos * reach), 0.5, math.round(sin * reach))
			clamped:set(true)
			shown:set(true)
		end)
		return root
	end)
end
