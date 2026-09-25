--!strict
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local Shared = require("./types")
local Theme = require("./theme_types")

export type Place = (GuiObject, number) -> ()
export type Kit = {
	spacing: (Shared.Value<Shared.Space>?, ComposeTypes.Use?) -> number,
	insets: (Shared.Value<Shared.Padding>?) -> UIPadding?,
	extent: (Shared.Box, Shared.Extent, Shared.Extent) -> (Shared.Value<UDim2>, Shared.Value<Enum.AutomaticSize>),
	list: (Shared.Flow, boolean) -> UIListLayout,
	ordered: ({ ComposeTypes.Child }, Place?) -> { ComposeTypes.Child },
	assemble: <P>(P, unknown?, { Instance? }, { ComposeTypes.Child }, Place?) -> P,
	stack: (
		{ ComposeTypes.Child },
		Shared.FrameNativeProps?,
		Shared.Flow,
		boolean,
		Shared.Extent?,
		Shared.Extent?
	) -> Frame,
}

local registry = setmetatable({} :: { [Shared.Context]: Kit }, { __mode = "k" })
local layoutKit = {}

function layoutKit.of(ctx: Shared.Context): Kit
	return assert(registry[ctx], "Facet layout requires a controls context")
end

function layoutKit.attach(ctx: Shared.Context): Kit
	local Host, read, types, config, Compose = ctx.Host, ctx.read, ctx.types, ctx.config, ctx.Compose
	local themes = bindThemes(Compose)
	local Enum = types.Enum
	local defaultMetrics = themes.neutralPackage().metrics
	local kit = {} :: Kit
	local function live(value: unknown): boolean
		return Compose.isReadable(value) or type(value) == "function"
	end
	local function derive<T>(compute: (ComposeTypes.Use?) -> T, ...: unknown): Shared.Value<T>
		for index = 1, select("#", ...) do
			if live((select(index, ...))) then
				return function(use: ComposeTypes.Use): T
					return compute(use)
				end
			end
		end
		return compute(nil)
	end
	local steps: { [string]: number } = defaultMetrics.space
	function kit.spacing(value: Shared.Value<Shared.Space>?, use: ComposeTypes.Use?): number
		local step = read(value, use)
		if step == nil then
			return 0
		end
		if type(step) == "number" then
			assert(step >= 0 and step < math.huge, "Facet spacing must be a finite number of pixels, 0 or more")
			return step
		end
		assert(type(step) == "string", "Facet spacing must be a number or a spacing step")
		local package: Theme.ThemePackage? = read(config.theme, use)
		local space: { [string]: number } = if package and type(package.metrics.space) == "table"
			then package.metrics.space
			else steps
		local pixels: number? = space[step] or steps[step]
		assert(
			type(pixels) == "number",
			`Facet spacing step "{step}" is not in the theme; use xs, s, m, l, xl or a number`
		)
		return pixels
	end
	local function spacingValue(value: Shared.Value<Shared.Space>?): Shared.Value<UDim>
		return derive(function(use)
			return types.UDim.new(0, kit.spacing(value, use))
		end, value, if type(read(value)) == "string" then config.theme else nil)
	end
	function kit.insets(padding: Shared.Value<Shared.Padding>?): UIPadding?
		if padding == nil then
			return nil
		end
		local function side(name: "top" | "right" | "bottom" | "left"): Shared.Value<UDim>
			local function pick(use: ComposeTypes.Use?): Shared.Space?
				local value = read(padding, use)
				if type(value) == "table" then
					local sides = value :: Shared.Sides
					return if name == "top"
						then sides.top
						elseif name == "right" then sides.right
						elseif name == "bottom" then sides.bottom
						else sides.left
				end
				return value
			end
			return derive(function(use)
				return types.UDim.new(0, kit.spacing(pick(use), use))
			end, padding, if type(pick(nil)) == "string" then config.theme else nil)
		end
		return Host.UIPadding({
			PaddingTop = side("top"),
			PaddingRight = side("right"),
			PaddingBottom = side("bottom"),
			PaddingLeft = side("left"),
		})
	end
	local function valid(value: unknown, names: { [string]: boolean }): boolean
		return type(value) == "string" and names[value] == true
	end
	local extents = { fill = true, hug = true }
	local function checked(value: Shared.Extent): Shared.Extent
		assert(
			valid(value, extents) or (type(value) == "number" and value >= 0),
			"Facet width and height must be fill, hug or a number of pixels"
		)
		return value
	end
	function kit.extent(
		box: Shared.Box,
		width: Shared.Extent,
		height: Shared.Extent
	): (Shared.Value<UDim2>, Shared.Value<Enum.AutomaticSize>)
		local function resolve(use: ComposeTypes.Use?): (Shared.Extent, Shared.Extent)
			local w: Shared.Extent? = read(box.width, use)
			local h: Shared.Extent? = read(box.height, use)
			return checked(if w == nil then width else w), checked(if h == nil then height else h)
		end
		local function scale(value: Shared.Extent): number
			return if value == "fill" then 1 else 0
		end
		local function offset(value: Shared.Extent): number
			return if type(value) == "number" then value else 0
		end
		return derive(function(use)
			local w: Shared.Extent, h: Shared.Extent = resolve(use)
			return types.UDim2.new(scale(w), offset(w), scale(h), offset(h))
		end, box.width, box.height),
			derive(function(use)
				local w: Shared.Extent, h: Shared.Extent = resolve(use)
				local wide, tall = w == "hug", h == "hug"
				return if wide and tall
					then Enum.AutomaticSize.XY
					elseif wide then Enum.AutomaticSize.X
					elseif tall then Enum.AutomaticSize.Y
					else Enum.AutomaticSize.None
			end, box.width, box.height)
	end
	local function edge<T>(value: Shared.Align | Shared.Distribute, start: T, center: T, finish: T): T
		return if value == "center" then center elseif value == "end" then finish else start
	end
	function kit.list(flow: Shared.Flow, vertical: boolean): UIListLayout
		local native: Shared.UIListLayoutNativeProps = {
			FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}
		if flow.gap ~= nil then
			native.Padding = spacingValue(flow.gap)
		end
		if flow.wrap ~= nil then
			native.Wraps = flow.wrap
		end
		local H, V = Enum.HorizontalAlignment, Enum.VerticalAlignment
		if flow.align ~= nil then
			local function align(use: ComposeTypes.Use?): Shared.Align
				local value: Shared.Align? = read(flow.align, use)
				assert(
					value == nil or valid(value, { start = true, center = true, ["end"] = true, stretch = true }),
					"Facet align must be start, center, end or stretch"
				)
				return if value == nil then "start" else value
			end
			if vertical then
				native.HorizontalAlignment = derive(function(use)
					return edge(align(use), H.Left, H.Center, H.Right)
				end, flow.align)
			else
				native.VerticalAlignment = derive(function(use)
					return edge(align(use), V.Top, V.Center, V.Bottom)
				end, flow.align)
			end
			if live(flow.align) or align(nil) == "stretch" then
				native.ItemLineAlignment = derive(function(use)
					return if align(use) == "stretch"
						then Enum.ItemLineAlignment.Stretch
						else Enum.ItemLineAlignment.Automatic
				end, flow.align)
				local cross = derive(function(use)
					return if align(use) == "stretch" then Enum.UIFlexAlignment.Fill else Enum.UIFlexAlignment.None
				end, flow.align)
				if vertical then
					native.HorizontalFlex = cross
				else
					native.VerticalFlex = cross
				end
			end
		end
		if flow.distribute ~= nil then
			local spread = {
				spaceBetween = Enum.UIFlexAlignment.SpaceBetween,
				spaceAround = Enum.UIFlexAlignment.SpaceAround,
				spaceEvenly = Enum.UIFlexAlignment.SpaceEvenly,
			}
			local function distribute(use: ComposeTypes.Use?): Shared.Distribute
				local value: Shared.Distribute? = read(flow.distribute, use)
				assert(
					value == nil
						or valid(value, { start = true, center = true, ["end"] = true })
						or valid(value, { spaceBetween = true, spaceAround = true, spaceEvenly = true }),
					"Facet distribute must be start, center, end, spaceBetween, spaceAround or spaceEvenly"
				)
				return if value == nil then "start" else value
			end
			local function flex(use: ComposeTypes.Use?): Enum.UIFlexAlignment
				return spread[distribute(use)] or Enum.UIFlexAlignment.None
			end
			if vertical then
				native.VerticalAlignment = derive(function(use)
					return edge(distribute(use), V.Top, V.Center, V.Bottom)
				end, flow.distribute)
				if live(flow.distribute) or spread[distribute(nil)] then
					native.VerticalFlex = derive(flex, flow.distribute)
				end
			else
				native.HorizontalAlignment = derive(function(use)
					return edge(distribute(use), H.Left, H.Center, H.Right)
				end, flow.distribute)
				if live(flow.distribute) or spread[distribute(nil)] then
					native.HorizontalFlex = derive(flex, flow.distribute)
				end
			end
		end
		return Host.UIListLayout(native)
	end
	function kit.ordered(children: { ComposeTypes.Child }, place: ((GuiObject, number) -> ())?): { ComposeTypes.Child }
		local result: { ComposeTypes.Child } = {}
		for index, child in children do
			local function stamp(node: Instance)
				if node:IsA("GuiObject") then
					local gui = node :: GuiObject
					gui.LayoutOrder = index
					if place then
						place(gui, index)
					end
				end
			end
			if type(child) == "function" then
				local directive = child :: ComposeTypes.Directive
				result[index] = function(mountPoint: ComposeTypes.MountPoint)
					directive({
						parent = mountPoint.parent,
						host = mountPoint.host,
						ordersChildren = mountPoint.ordersChildren,
						moveTo = mountPoint.moveTo,
						remove = mountPoint.remove,
						count = mountPoint.count,
						insert = function(node: unknown, at: number?)
							stamp(node :: Instance)
							mountPoint.insert(node, at)
						end,
					})
				end
			else
				stamp(child :: Instance)
				result[index] = child
			end
		end
		return result
	end
	function kit.assemble<P>(
		native: P,
		properties: unknown?,
		helpers: { Instance? },
		children: { ComposeTypes.Child },
		place: ((GuiObject, number) -> ())?
	): P
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for index = 1, #helpers do
			local helper = helpers[index]
			if helper then
				fields[#fields + 1] = helper
			end
		end
		for key, value in ((properties or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				fields[#fields + 1] = value
			else
				fields[key] = value
			end
		end
		for _, child in kit.ordered(children, place) do
			fields[#fields + 1] = child
		end
		return native
	end
	function kit.stack(
		children: { ComposeTypes.Child },
		properties: Shared.FrameNativeProps?,
		flow: Shared.Flow,
		vertical: boolean,
		width: Shared.Extent?,
		height: Shared.Extent?
	): Frame
		local size, automatic = kit.extent(flow, width or "hug", height or "hug")
		local native: Shared.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		return Host.Frame(
			kit.assemble(native, properties, { kit.list(flow, vertical), kit.insets(flow.padding) }, children)
		)
	end
	registry[ctx] = kit
	return kit
end

return layoutKit
