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
		local properties, children =
			split(spec, { "gap", "padding", "align", "distribute", "width", "height", "chrome" })
		local chrome = spec.chrome or "device"
		assert(
			chrome == "device" or chrome == "band" or chrome == "edge",
			"Facet UI.Screen: chrome must be device, band or edge"
		)
		local base: Types.Value<Types.Padding> = if spec.padding == nil then "m" else spec.padding
		local under = Compose.cell(0)
		local distant = ctx.tenFoot()
		local authored = ctx.config.environment and ctx.config.environment.overscanInsets
		local FRACTION = { top = 60 / 1080, bottom = 60 / 1080, left = 90 / 1920, right = 90 / 1920 }
		local flow: Types.Flow = {
			gap = spec.gap,
			align = spec.align,
			distribute = spec.distribute,
			padding = function(use: ComposeTypes.Use): Types.Padding
				local value = read(base, use)
				local sides: Types.Sides = if type(value) == "table"
					then value :: Types.Sides
					else { top = value, right = value, bottom = value, left = value }
				local margins = read(authored, use)
				local function side(name: "top" | "right" | "bottom" | "left", extra: number): UDim
					local pixels = kit.spacing((sides :: { [string]: Types.Space? })[name], use) + extra
					if type(margins) == "table" and chrome ~= "edge" then
						return ctx.types.UDim.new(0, pixels + ((margins :: { [string]: number })[name] or 0))
					end
					local fraction = if margins == nil and chrome ~= "edge" and distant(use) then FRACTION[name] else 0
					return ctx.types.UDim.new(fraction, pixels)
				end
				return (
					{
						top = side("top", if chrome == "device" then use(under) else 0),
						right = side("right", 0),
						bottom = side("bottom", 0),
						left = side("left", 0),
					} :: unknown
				) :: Types.Padding
			end,
			width = spec.width,
			height = spec.height,
		}
		local frame =
			kit.stack(children, (properties :: unknown) :: Engine.FrameNativeProps, flow, true, "fill", "fill")
		kit.underTopbar(frame, under)
		return frame
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
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local frame = kit.plain(
			Host.Frame(kit.assemble(native, properties, { kit.insets(spec.padding) }, children, function(node, index)
				if node.ZIndex == 1 then
					node.ZIndex = index
				end
				if aligned then
					placed[node] = ctx.observe.AbsoluteSize(node)
					members:update(function(count: number): number
						return count + 1
					end)
				end
			end)),
			properties
		)
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
						widest = math.max(widest, extent.X)
						tallest = math.max(tallest, extent.Y)
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
		return kit.plain(
			Host.ScrollingFrame(
				kit.assemble(native, properties, { kit.list(flow, axis ~= "x"), kit.insets(spec.padding) }, children)
			),
			properties
		)
	end)

	UI.Grid = ctx.construct("Grid", function(spec: Layout.GridProps): Frame
		local properties, children = split(
			spec,
			{ "columns", "flow", "gap", "rowGap", "cellHeight", "aspectRatio", "align", "padding", "width", "height" }
		)
		local size, automatic = kit.extent(spec, "fill", "hug")
		local flow = spec.flow or "row"
		assert(flow == "row" or flow == "column", "Facet Grid flow must be row or column")
		local cells = Compose.cell(0)
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
			FillDirection = if flow == "column" then E.FillDirection.Vertical else E.FillDirection.Horizontal,
			FillDirectionMaxCells = function(use: ComposeTypes.Use): number
				local count = columns(use)
				if flow == "column" then
					return math.max(1, math.ceil(use(cells) / count))
				end
				return count
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
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local node = kit.plain(
			Host.Frame(
				kit.assemble(native, properties, { Host.UIGridLayout(layout), kit.insets(spec.padding) }, children)
			),
			properties
		)
		if flow == "column" then
			local function count()
				local total = 0
				for _, child in node:GetChildren() do
					if child:IsA("GuiObject") then
						total += 1
					end
				end
				cells:set(total)
			end
			runtime.connect(node, "ChildAdded", count)
			runtime.connect(node, "ChildRemoved", count)
			count()
		end
		return node
	end)

	local function scrolls(holder: Instance?, horizontal: boolean): boolean
		if holder == nil or not holder:IsA("ScrollingFrame") then
			return false
		end
		local direction = (holder :: ScrollingFrame).ScrollingDirection
		return direction == E.ScrollingDirection.XY
			or direction == (if horizontal then E.ScrollingDirection.X else E.ScrollingDirection.Y)
	end
	local function tracked(
		node: GuiObject,
		sizes: { [GuiObject]: ComposeTypes.Cell<Vector2> },
		parents: { [GuiObject]: ComposeTypes.Cell<Instance?> },
		members: ComposeTypes.Cell<number>
	)
		sizes[node] = ctx.observe.AbsoluteSize(node)
		parents[node] = ctx.observe.Parent(node)
		members:update(function(count: number): number
			return count + 1
		end)
	end

	UI.AdaptiveStack = ctx.construct("AdaptiveStack", function(spec: Layout.AdaptiveStackProps): Frame
		local properties, children = split(spec, { "axis", "gap", "padding", "align", "distribute", "width", "height" })
		local flow: Types.Flow = {
			gap = spec.gap,
			padding = spec.padding,
			align = spec.align,
			distribute = spec.distribute,
			width = spec.width,
			height = spec.height,
		}
		local axis = spec.axis
		if axis ~= nil then
			local function column(use: ComposeTypes.Use?): boolean
				local value = read(axis, use)
				assert(value == "x" or value == "y", "Facet AdaptiveStack axis must be x or y")
				return value == "y"
			end
			local vertical: Types.Value<boolean> = if Compose.isReadable(axis) or type(axis) == "function"
				then column
				else column(nil)
			return kit.stack(children, (properties :: unknown) :: Engine.FrameNativeProps, flow, vertical)
		end
		local vertical = Compose.cell(false)
		local sizes = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<Vector2> }
		local parents = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<Instance?> }
		local shown = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<boolean> }
		local members = Compose.cell(0)
		local size, automatic = kit.extent(flow, "fill", "hug")
		local layout = kit.list(flow, vertical)
		local native: Engine.FrameNativeProps = {
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local node = kit.plain(
			Host.Frame(kit.assemble(native, properties, { layout, kit.insets(spec.padding) }, children, function(child)
				shown[child] = ctx.observe.Visible(child)
				tracked(child, sizes, parents, members)
			end)),
			properties
		)
		local box, holder, content =
			ctx.observe.AbsoluteSize(node), ctx.observe.Parent(node), ctx.observe.AbsoluteContentSize(layout)
		local rowNeed, lastCount = 0, 0
		local retried: string?, refused: string? = nil, nil
		Compose.watch(function(use: ComposeTypes.Use)
			use(members)
			local width, row = use(box).X, use(content).X
			if scrolls(use(holder), true) then
				vertical:set(false)
				return
			end
			local padding = node:FindFirstChildWhichIsA("UIPadding")
			local offered = if padding then width - padding.PaddingLeft.Offset - padding.PaddingRight.Offset else width
			local count, total = 0, 0
			for child, extent in sizes do
				if use(parents[child]) == node and use(shown[child]) then
					count += 1
					if child.Size.X.Scale == 0 and child:FindFirstChildWhichIsA("UIFlexItem") == nil then
						total += use(extent).X
					end
				end
			end
			local key = `{total}/{count}/{offered}`
			if not vertical:peek() then
				rowNeed = row
				if rowNeed > offered then
					refused = retried
				end
			elseif read(spec.align, use) ~= "stretch" then
				rowNeed = if key == refused
					then math.huge
					else total + kit.spacing(spec.gap, use) * math.max(count - 1, 0)
			elseif count ~= lastCount then
				rowNeed = 0
			end
			lastCount = count
			if width > 0 then
				if vertical:peek() and rowNeed <= offered then
					retried = key
				end
				vertical:set(rowNeed > offered)
			end
		end)
		return node
	end)

	UI.ViewThatFits = ctx.construct("ViewThatFits", function(spec: Layout.ViewThatFitsProps): Frame
		local properties, children = split(spec, { "width", "height" })
		assert(#children > 0, "Facet ViewThatFits needs at least one candidate")
		local sizes = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<Vector2> }
		local parents = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: ComposeTypes.Cell<Instance?> }
		local members = Compose.cell(0)
		local box: Types.Box = { width = spec.width, height = spec.height }
		local size, automatic = kit.extent(box, "fill", "hug")
		local native: Engine.FrameNativeProps = {
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local node = kit.plain(
			Host.Frame(kit.assemble(native, properties, { kit.list({}, true) }, children, function(child)
				tracked(child, sizes, parents, members)
			end)),
			properties
		)
		local offered, holder = ctx.observe.AbsoluteSize(node), ctx.observe.Parent(node)
		Compose.watch(function(use: ComposeTypes.Use)
			use(members)
			local offer, parent = use(offered), use(holder)
			local openX = read(spec.width, use) == "hug" or offer.X <= 0 or scrolls(parent, true)
			local height = read(spec.height, use)
			local openY = height == nil or height == "hug" or offer.Y <= 0 or scrolls(parent, false)
			local candidates: { GuiObject } = {}
			for child in sizes do
				if use(parents[child]) == node then
					table.insert(candidates, child)
				end
			end
			table.sort(candidates, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			local winner = candidates[#candidates]
			for _, child in candidates do
				local extent = use(sizes[child])
				if (openX or extent.X <= offer.X) and (openY or extent.Y <= offer.Y) then
					winner = child
					break
				end
			end
			for _, child in candidates do
				child.Visible = child == winner
			end
		end)
		return node
	end)

	UI.ErrorBoundary = ctx.construct("ErrorBoundary", function(spec: Layout.ErrorBoundaryProps): Frame
		assert(type(spec.view) == "function", "Facet ErrorBoundary requires a view function")
		assert(type(spec.fallback) == "function", "Facet ErrorBoundary requires a fallback function")
		local properties = ctx.props(spec, { "view", "fallback", "onError", "width", "height" })
		local box: Types.Box = { width = spec.width, height = spec.height }
		local size, automatic = kit.extent(box, "hug", "hug")
		local failed: ComposeTypes.Cell<string?> = Compose.cell(nil :: string?)
		local native: Engine.FrameNativeProps = {
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
		local root = kit.plain(Host.Frame(kit.assemble(native, properties, {}, { region })), properties)
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
			BorderSizePixel = 0,
			Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
		}
		local node = kit.plain(Host.Frame(ctx.props(spec, { "minLength" }, native)), spec)
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
