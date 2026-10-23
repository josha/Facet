--!strict
local ComposeTypes = require("../vendor/compose/core")
local Engine = require("./engine_types")
type Insets = { [string]: UDim }

return function(
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	types: Engine.RobloxTypes,
	target: GuiObject?,
	node: GuiObject,
	options: { inset: boolean?, immediate: boolean? }?
): GuiObject
	if target == nil then
		return node
	end
	local settings: { inset: boolean?, immediate: boolean? } = options or {}
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	local D2 = types.UDim2
	local frame: ComposeTypes.ObserveOptions? = if not settings.immediate and getfenv(0).game
		then { frame = true }
		else nil
	local poll: ComposeTypes.ObserveOptions? = if frame then { frame = true, poll = true } else nil
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
	local scale = (runtime.observe(boundary, "AbsoluteSize", poll) :: unknown) :: ComposeTypes.Cell<Vector2>
	local size = (runtime.observe(target, "AbsoluteSize", poll) :: unknown) :: ComposeTypes.Cell<Vector2>
	local at = (runtime.observe(target, "AbsolutePosition", frame) :: unknown) :: ComposeTypes.Cell<Vector2>
	local rotation = (runtime.observe(target, "AbsoluteRotation", frame) :: unknown) :: ComposeTypes.Cell<number>
	local boundaryAt = (runtime.observe(boundary, "AbsolutePosition", frame) :: unknown) :: ComposeTypes.Cell<Vector2>
	local insets = Compose.cell({} :: Insets)
	local padding = Compose.cell(target:FindFirstChildWhichIsA("UIPadding"))
	local function childChanged(child: Instance)
		if child:IsA("UIPadding") then
			padding:set(target:FindFirstChildWhichIsA("UIPadding"))
		end
	end
	runtime.connect(target, "ChildAdded", childChanged)
	runtime.connect(target, "ChildRemoved", childChanged)
	Compose.watch(function(use)
		local current = use(padding)
		if current == nil then
			insets:set({})
			return
		end
		local function refresh()
			local values: Insets = {}
			for _, side in { "Left", "Right", "Top", "Bottom" } do
				values[side] = current:GetStyled("Padding" .. side) :: UDim
			end
			insets:set(values)
		end
		runtime.connect(current, "StyledPropertiesChanged", refresh)
		runtime.connect(current, "Changed", refresh)
		refresh()
	end)
	local bounds = Compose.formula(function(use)
		local rendered, factor, padding = use(size), use(scale), use(insets)
		if factor.X <= 0 or factor.Y <= 0 then
			return { x = 0, y = 0, width = 0, height = 0 }
		end
		local pixels = types.Vector2.new(rendered.X / factor.X, rendered.Y / factor.Y)
		local distance = use(at) + rendered / 2 - use(boundaryAt) - factor / 2
		local angle = math.rad(use(rotation))
		local cosine, sine = math.cos(angle), math.sin(angle)
		local offset = types.Vector2.new(
			(distance.X * cosine + distance.Y * sine) / factor.X - pixels.X / 2 + 0.5,
			(distance.Y * cosine - distance.X * sine) / factor.Y - pixels.Y / 2 + 0.5
		)
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
		local canvas = (runtime.observe(frame, "CanvasPosition") :: unknown) :: ComposeTypes.Cell<Vector2>
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
			return if settings.inset
				then D2.fromOffset(math.ceil(box.width - 1e-3), math.ceil(box.height - 1e-3))
				else D2.fromOffset(box.width, box.height)
		end,
		Position = function(use)
			local box = use(bounds)
			return D2.fromOffset(box.x, box.y)
		end,
	})
	return boundary
end
