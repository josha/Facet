--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Engine = require("./engine_types")
local Layout = require("./layout_types")
local layoutKit = require("./layout_kit")
export type LayoutControls = Layout.LayoutControls

return function(ctx: Types.Context, controls: Layout.LayoutControls?): Layout.LayoutControls
	local Host, read, Compose, runtime = ctx.Host, ctx.read, ctx.Compose, ctx.runtime
	local kit = layoutKit.of(ctx)
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local UI: Layout.LayoutControls = controls or ({} :: Layout.LayoutControls)
	local flowKeys = { "gap", "padding", "align", "distribute", "wrap", "width", "height" }
	local function split(spec: unknown, keys: { string }): ({ [unknown]: unknown }, { ComposeTypes.Child })
		local fields = spec :: { [unknown]: unknown }
		local named: { [unknown]: unknown } = {}
		local children: { ComposeTypes.Child } = {}
		for key, value in fields do
			if type(key) ~= "number" then
				named[key] = value
			end
		end
		for index = 1, #fields do
			children[index] = fields[index] :: ComposeTypes.Child
		end
		return ctx.props(named, keys), children
	end
	local function stack(spec: Layout.StackProps, vertical: boolean): Frame
		local properties, children = split(spec, flowKeys)
		return kit.stack(children, (properties :: unknown) :: Engine.FrameNativeProps, spec, vertical)
	end

	UI.VStack = ctx.construct("VStack", function(spec: Layout.StackProps): Frame
		return stack(spec, true)
	end)

	UI.HStack = ctx.construct("HStack", function(spec: Layout.StackProps): Frame
		return stack(spec, false)
	end)

	UI.Screen = ctx.construct("Screen", function(spec: Layout.ScreenProps): Frame
		local properties, children = split(spec, { "gap", "padding", "align", "distribute", "width", "height" })
		local flow: Types.Flow = {
			gap = spec.gap,
			align = spec.align,
			distribute = spec.distribute,
			padding = if spec.padding == nil then "m" else spec.padding,
			width = spec.width,
			height = spec.height,
		}
		return kit.stack(children, (properties :: unknown) :: Engine.FrameNativeProps, flow, true, "fill", "fill")
	end)

	UI.ZStack = ctx.construct("ZStack", function(spec: Layout.ZStackProps): Frame
		local properties, children = split(spec, { "padding", "width", "height", "alignH", "alignV" })
		local size, automatic = kit.extent(spec, "hug", "hug")
		local aligned = spec.alignH ~= nil or spec.alignV ~= nil
		local function fraction(value: Layout.Edge?): number
			assert(
				value == nil or value == "start" or value == "center" or value == "end",
				"Facet ZStack alignH and alignV must be start, center or end"
			)
			return if value == "center" then 0.5 elseif value == "end" then 1 else 0
		end
		local placed = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<Vector2> }
		local members = Compose.cell(0)
		local function hugs(value: Layout.Extent?): boolean
			return value == nil or value == "hug"
		end
		local native: Engine.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local frame =
			Host.Frame(kit.assemble(native, properties, { kit.insets(spec.padding) }, children, function(node, index)
				if node.ZIndex == 1 then
					node.ZIndex = index
				end
				if aligned then
					placed[node] = ctx.observe(node, "AbsoluteSize")
					members:update(function(count: number): number
						return count + 1
					end)
				end
			end))
		if aligned then
			Compose.watch(function(use: ComposeTypes.Use)
				use(members)
				local x, y = fraction(read(spec.alignH, use)), fraction(read(spec.alignV, use))
				local wide, tall = hugs(read(spec.width, use)), hugs(read(spec.height, use))
				local nodes: { GuiObject } = {}
				local extents: { [GuiObject]: Vector2 } = {}
				local widest, tallest = 0, 0
				for node, observed in placed do
					if node.Parent == frame then
						local extent = use(observed)
						table.insert(nodes, node)
						extents[node] = extent
						widest, tallest = math.max(widest, extent.X), math.max(tallest, extent.Y)
					end
				end
				for _, node in nodes do
					local extent = extents[node]
					node.AnchorPoint = V2.new(if wide then 0 else x, if tall then 0 else y)
					node.Position = D2.new(
						if wide then 0 else x,
						if wide then math.floor(x * (widest - extent.X) + 0.5) else 0,
						if tall then 0 else y,
						if tall then math.floor(y * (tallest - extent.Y) + 0.5) else 0
					)
				end
			end)
		end
		return frame
	end)

	UI.ScrollView = ctx.construct("ScrollView", function(spec: Layout.ScrollViewProps): ScrollingFrame
		local properties, children = split(spec, { "axis", "gap", "padding", "align", "distribute", "width", "height" })
		local axis = spec.axis or "y"
		assert(axis == "x" or axis == "y" or axis == "xy", "Facet ScrollView axis must be x, y or xy")
		local size, automatic = kit.extent(spec, "fill", "fill")
		local native: Engine.ScrollingFrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
			CanvasSize = D2.new(),
			AutomaticCanvasSize = if axis == "x"
				then E.AutomaticSize.X
				elseif axis == "y" then E.AutomaticSize.Y
				else E.AutomaticSize.XY,
			ScrollingDirection = if axis == "x"
				then E.ScrollingDirection.X
				elseif axis == "y" then E.ScrollingDirection.Y
				else E.ScrollingDirection.XY,
		}
		if axis ~= "x" then
			native.VerticalScrollBarInset = E.ScrollBarInset.ScrollBar
		end
		if axis ~= "y" then
			native.HorizontalScrollBarInset = E.ScrollBarInset.ScrollBar
		end
		local flow: Types.Flow = { gap = spec.gap, align = spec.align, distribute = spec.distribute }
		return Host.ScrollingFrame(
			kit.assemble(native, properties, { kit.list(flow, axis ~= "x"), kit.insets(spec.padding) }, children)
		)
	end)

	UI.Grid = ctx.construct("Grid", function(spec: Layout.GridProps): Frame
		local properties, children = split(
			spec,
			{ "columns", "gap", "rowGap", "cellHeight", "aspectRatio", "align", "padding", "width", "height" }
		)
		local size, automatic = kit.extent(spec, "fill", "hug")
		local function columns(use: ComposeTypes.Use?): number
			local count = read(spec.columns, use)
			assert(
				type(count) == "number" and count >= 1 and count % 1 == 0,
				"Facet Grid columns must be a whole number, 1 or more"
			)
			return count
		end
		local layout: Engine.UIGridLayoutNativeProps = {
			SortOrder = E.SortOrder.LayoutOrder,
			FillDirection = E.FillDirection.Horizontal,
			FillDirectionMaxCells = function(use: ComposeTypes.Use): number
				return columns(use)
			end,
			CellPadding = function(use: ComposeTypes.Use): UDim2
				local gap = kit.spacing(spec.gap, use)
				return D2.fromOffset(gap, if spec.rowGap == nil then gap else kit.spacing(spec.rowGap, use))
			end,
			CellSize = function(use: ComposeTypes.Use): UDim2
				local count = columns(use)
				local gap = kit.spacing(spec.gap, use)
				local height = read(spec.cellHeight, use)
				return D2.new(
					1 / count,
					-math.ceil(gap * (count - 1) / count),
					0,
					if height == nil then ctx.controlSize(ctx.config.controlSize, "height", use) else height
				)
			end,
		}
		if spec.align ~= nil then
			layout.HorizontalAlignment = function(use: ComposeTypes.Use): Enum.HorizontalAlignment
				local value = read(spec.align, use)
				assert(
					value == "start" or value == "center" or value == "end",
					"Facet Grid align must be start, center or end"
				)
				return if value == "center"
					then E.HorizontalAlignment.Center
					elseif value == "end" then E.HorizontalAlignment.Right
					else E.HorizontalAlignment.Left
			end
		end
		if spec.aspectRatio ~= nil then
			layout[1] = Host.UIAspectRatioConstraint({ AspectRatio = spec.aspectRatio })
		end
		local native: Engine.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		return Host.Frame(
			kit.assemble(native, properties, { Host.UIGridLayout(layout), kit.insets(spec.padding) }, children)
		)
	end)

	UI.ErrorBoundary = ctx.construct("ErrorBoundary", function(spec: Layout.ErrorBoundaryProps): Frame
		assert(type(spec.view) == "function", "Facet ErrorBoundary requires a view function")
		assert(type(spec.fallback) == "function", "Facet ErrorBoundary requires a fallback function")
		local properties = ctx.props(spec, { "view", "fallback", "onError", "width", "height" })
		local box: Types.Box = { width = spec.width, height = spec.height }
		local size, automatic = kit.extent(box, "hug", "hug")
		local failed: ComposeTypes.Cell<string?> = Compose.cell(nil :: string?)
		local native: Engine.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local region = Compose.boundary(function()
			failed:set(nil)
			return (spec.view() :: unknown) :: ComposeTypes.Node
		end, function(failure: unknown, retry: () -> ())
			failed:set(tostring(failure))
			local report: ((unknown) -> ())? = spec.onError or ctx.config.onError
			if report then
				report(failure)
			end
			return (spec.fallback(failure, retry) :: unknown) :: ComposeTypes.Node
		end)
		local root = Host.Frame(kit.assemble(native, properties, {}, { region }))
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("FacetError", use(failed))
		end)
		return root
	end)

	local function stackAxis(node: Frame, axis: ("x" | "y")?): (ComposeTypes.Use) -> "x" | "y"
		if axis ~= nil then
			assert(axis == "x" or axis == "y", "Facet axis must be x or y")
			return function(): "x" | "y"
				return axis
			end
		end
		local direction: ComposeTypes.Cell<"x" | "y"> = Compose.cell("y" :: "x" | "y")
		local connections: { RBXScriptConnection } = {}
		local function release()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end
		local function attach()
			release()
			local holder = node.Parent
			if holder == nil then
				return
			end
			local layout = holder:FindFirstChildWhichIsA("UIListLayout")
			if layout == nil then
				table.insert(connections, holder.ChildAdded:Connect(attach))
				direction:set("y")
				return
			end
			local function update()
				direction:set(if layout.FillDirection == E.FillDirection.Horizontal then "x" else "y")
			end
			table.insert(connections, layout:GetPropertyChangedSignal("FillDirection"):Connect(update))
			update()
		end
		runtime.connect(node, "AncestryChanged", attach)
		Compose.cleanup(release)
		attach()
		return function(use: ComposeTypes.Use): "x" | "y"
			return if use(direction) == "x" then "x" else "y"
		end
	end

	UI.Divider = ctx.construct("Divider", function(spec: Layout.DividerProps): Frame
		local thickness = spec.thickness
		assert(
			thickness == nil or type(thickness) == "string" or (type(thickness) == "number" and thickness > 0),
			"Facet Divider thickness must be a positive number or a theme metric name"
		)
		local function weight(use: ComposeTypes.Use?): number
			if type(thickness) == "number" then
				return thickness
			end
			local path = if type(thickness) == "string" then thickness else "strokes.hairline"
			return if string.find(path, ".", 1, true) then ctx.metric(path, use) else kit.spacing(path, use)
		end
		local native: Engine.FrameNativeProps = {
			Name = "Divider",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}
		local node = ctx.styled(Host.Frame(ctx.props(spec, { "axis", "thickness", "appearance" }, native)), "divider")
		local along = stackAxis(node, spec.axis)
		if spec.Size == nil then
			runtime.decorate(node, {
				Size = function(use: ComposeTypes.Use): UDim2
					local pixels = weight(use)
					return if along(use) == "x" then D2.new(0, pixels, 1, 0) else D2.new(1, 0, 0, pixels)
				end,
			})
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local appearance = read(spec.appearance, use) or "standard"
			assert(
				appearance == "standard" or appearance == "strong",
				"Facet Divider appearance must be standard or strong"
			)
			if appearance == "strong" then
				node:AddTag("facet-divider-strong")
			elseif node:HasTag("facet-divider-strong") then
				node:RemoveTag("facet-divider-strong")
			end
		end)
		return node
	end)

	UI.Spacer = ctx.construct("Spacer", function(spec: Layout.SpacerProps): Frame
		local native: Engine.FrameNativeProps = {
			Name = "Spacer",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
		}
		local node = Host.Frame(ctx.props(spec, { "minLength" }, native))
		local along = stackAxis(node, nil)
		if spec.Size == nil then
			runtime.decorate(node, {
				Size = function(use: ComposeTypes.Use): UDim2
					local floor = kit.spacing(spec.minLength, use)
					return if along(use) == "x" then D2.fromOffset(floor, 0) else D2.fromOffset(0, floor)
				end,
			})
		end
		return node
	end)

	UI.fill = function(weight: number?): UIFlexItem
		if weight == nil then
			return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
		end
		assert(type(weight) == "number" and weight > 0, "Facet fill weight must be a positive number")
		return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Custom, GrowRatio = weight, ShrinkRatio = weight })
	end

	return UI
end
