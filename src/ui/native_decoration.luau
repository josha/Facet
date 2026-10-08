--!strict
local ComposeTypes = require("../vendor/compose/core")
local Engine = require("./engine_types")
type Insets = { [string]: UDim }
local observeGeometry = require("./geometry_observation")

return function(
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	types: Engine.RobloxTypes,
	target: GuiObject?,
	node: GuiObject,
	options: { inset: boolean? }?
): GuiObject
	if target == nil then
		return node
	end
	local settings: { inset: boolean? } = options or {}
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	local D2 = types.UDim2
	if target:FindFirstChildWhichIsA("UIPadding") == nil then
		runtime.mount(function()
			return Host.UIPadding({})
		end, target)
	end
	local container = Host.Frame(node.Name .. "Bounds")({
		Size = D2.fromOffset(0, 0),
		AnchorPoint = types.Vector2.new(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = node.ZIndex,
		node,
	})
	local boundary = Host.Frame(node.Name .. "Boundary")({
		Size = D2.fromOffset(1, 1),
		Position = D2.fromScale(1, 1),
		AnchorPoint = types.Vector2.new(1, 1),
		AutomaticSize = types.Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = node.ZIndex,
		container,
	})
	local scale = (observeGeometry(Compose, runtime, boundary, "AbsoluteSize") :: unknown) :: ComposeTypes.Cell<Vector2>
	local size = (observeGeometry(Compose, runtime, target, "AbsoluteSize") :: unknown) :: ComposeTypes.Cell<Vector2>
	local at = (observeGeometry(Compose, runtime, target, "AbsolutePosition") :: unknown) :: ComposeTypes.Cell<Vector2>
	local boundaryAt = (
		observeGeometry(Compose, runtime, boundary, "AbsolutePosition") :: unknown
	) :: ComposeTypes.Cell<Vector2>
	local insets = Compose.cell({} :: Insets)
	local connections: { RBXScriptConnection }, paddingConnections: { RBXScriptConnection } = {}, {}
	local function disconnectPadding()
		for _, connection in paddingConnections do
			connection:Disconnect()
		end
		table.clear(paddingConnections)
	end
	local function paddingChanged()
		disconnectPadding()
		local padding = target:FindFirstChildWhichIsA("UIPadding")
		if padding == nil then
			insets:set({})
			return
		end
		local function refresh()
			local values: Insets = {}
			for _, side in { "Left", "Right", "Top", "Bottom" } do
				values[side] = padding:GetStyled("Padding" .. side) :: UDim
			end
			insets:set(values)
		end
		for _, side in { "Left", "Right", "Top", "Bottom" } do
			table.insert(paddingConnections, padding:GetStyledPropertyChangedSignal("Padding" .. side):Connect(refresh))
			table.insert(paddingConnections, padding:GetPropertyChangedSignal("Padding" .. side):Connect(refresh))
		end
		refresh()
	end
	local function childChanged(child: Instance)
		if child:IsA("UIPadding") then
			paddingChanged()
		end
	end
	table.insert(connections, target.ChildAdded:Connect(childChanged))
	table.insert(connections, target.ChildRemoved:Connect(childChanged))
	paddingChanged()
	Compose.cleanup(function()
		disconnectPadding()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	local bounds = Compose.formula(function(use)
		local rendered, factor, padding = use(size), use(scale), use(insets)
		if factor.X <= 0 or factor.Y <= 0 then
			return { x = 0, y = 0, width = 0, height = 0 }
		end
		local pixels = types.Vector2.new(rendered.X / factor.X, rendered.Y / factor.Y)
		local distance = use(at) - use(boundaryAt)
		local offset = types.Vector2.new(distance.X / factor.X, distance.Y / factor.Y)
		local function inset(side: string, length: number): number
			local value = padding[side]
			return if value then value.Scale * length + value.Offset else 0
		end
		local left, top = inset("Left", pixels.X), inset("Top", pixels.Y)
		local right, bottom = inset("Right", pixels.X), inset("Bottom", pixels.Y)
		return if settings.inset
			then {
				x = offset.X + pixels.X - right,
				y = offset.Y + pixels.Y - bottom,
				width = math.max(0, pixels.X - left - right),
				height = math.max(0, pixels.Y - top - bottom),
			}
			else { x = offset.X + pixels.X, y = offset.Y + pixels.Y, width = pixels.X, height = pixels.Y }
	end)
	if target:IsA("ScrollingFrame") then
		local frame = target :: ScrollingFrame
		local canvas = (
			observeGeometry(Compose, runtime, frame, "CanvasPosition") :: unknown
		) :: ComposeTypes.Cell<Vector2>
		runtime.decorate(boundary, {
			Position = function(use: ComposeTypes.Use): UDim2
				local rendered: Vector2, factor: Vector2, at: Vector2 = use(size), use(scale), use(canvas)
				local padding: Insets = use(insets)
				if factor.X <= 0 or factor.Y <= 0 then
					return D2.fromScale(1, 1)
				end
				local width, height = rendered.X / factor.X, rendered.Y / factor.Y
				local function inset(side: string, length: number): number
					local value = padding[side]
					return if value then value.Scale * length + value.Offset else 0
				end
				return D2.fromOffset(
					at.X + width - inset("Left", width) - inset("Right", width),
					at.Y + height - inset("Top", height) - inset("Bottom", height)
				)
			end,
		})
	end
	runtime.decorate(container, {
		Size = function(use)
			local box: { width: number, height: number } = use(bounds)
			return D2.fromOffset(math.ceil(box.width - 1e-3), math.ceil(box.height - 1e-3))
		end,
		Position = function(use)
			local box = use(bounds)
			return D2.fromOffset(box.x, box.y)
		end,
	})
	return boundary
end
