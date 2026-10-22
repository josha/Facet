--!strict
local ComposeTypes = require("../vendor/compose/core")
local bindThemes = require("./themes")
local Shared = require("./types")
local Theme = require("./theme_types")

export type Place = (GuiObject, number) -> ()
export type Room = { top: number, right: number, bottom: number, left: number }
export type Kit = {
	spacing: (Shared.Value<Shared.Space>?, ComposeTypes.Use?) -> number,
	insets: (Shared.Value<Shared.Padding>?, ComposeTypes.Readable<Room>?) -> UIPadding?,
	shadowRoom: (GuiObject, ComposeTypes.Cell<Room>) -> (),
	extent: (Shared.Box, Shared.Extent, Shared.Extent) -> (Shared.Value<UDim2>, Shared.Value<Enum.AutomaticSize>),
	list: (Shared.Flow, Shared.Value<boolean>) -> UIListLayout,
	underTopbar: (GuiObject, ComposeTypes.Cell<number>) -> (),
	ordered: ({ ComposeTypes.Child }, Place?) -> { ComposeTypes.Child },
	assemble: <P>(P, unknown?, { Instance? }, { ComposeTypes.Child }, Place?) -> P,
	plain: <N>(N & Instance, unknown?) -> N & Instance,
	stack: (
		{ ComposeTypes.Child },
		Shared.FrameNativeProps?,
		Shared.Flow,
		Shared.Value<boolean>,
		Shared.Extent?,
		Shared.Extent?
	) -> Frame,
	regrow: (Frame, UIListLayout) -> (),
}

local layoutKit = {}

function layoutKit.of(ctx: Shared.Context): Kit
	return (assert(ctx.layoutKit :: Kit?, "Facet layout requires a controls context"))
end

function layoutKit.attach(ctx: Shared.Context): Kit
	local Host, read, types, config, Compose, runtime =
		ctx.Host, ctx.read, ctx.types, ctx.config, ctx.Compose, ctx.runtime
	local themes = bindThemes(Compose)
	local Enum = types.Enum
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
			else ctx.neutralMetrics(use).space
		local pixels: number? = space[step] or ctx.neutralMetrics(use).space[step]
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
	function kit.insets(padding: Shared.Value<Shared.Padding>?, room: ComposeTypes.Readable<Room>?): UIPadding?
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
				local value: unknown = pick(use)
				local extra = if room and use then (use(room) :: Room)[name] elseif room then room:peek()[name] else 0
				if typeof(value) == "UDim" then
					local given = value :: UDim
					return if extra > 0 then types.UDim.new(given.Scale, given.Offset + extra) else given
				end
				return types.UDim.new(0, kit.spacing(value :: Shared.Space?, use) + extra)
			end, padding, if type(pick(nil)) == "string" then config.theme else nil, room)
		end
		return Host.UIPadding({
			PaddingTop = side("top"),
			PaddingRight = side("right"),
			PaddingBottom = side("bottom"),
			PaddingLeft = side("left"),
		})
	end
	function kit.shadowRoom(frame: GuiObject, room: ComposeTypes.Cell<Room>)
		local function measure()
			local top, right, bottom, left = 0, 0, 0, 0
			for _, child in frame:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					for _, item in child:GetChildren() do
						if item:IsA("UIShadow") and item.Enabled then
							local shadow = item :: UIShadow
							local blur = shadow.BlurRadius.Offset
							local ox, oy = shadow.Offset.X.Offset, shadow.Offset.Y.Offset
							local sx, sy = shadow.Spread.X.Offset, shadow.Spread.Y.Offset
							top = math.max(top, -oy + sy + blur)
							bottom = math.max(bottom, oy + sy + blur)
							left = math.max(left, -ox + sx + blur)
							right = math.max(right, ox + sx + blur)
						end
					end
				end
			end
			local now = room:peek()
			if now.top ~= top or now.right ~= right or now.bottom ~= bottom or now.left ~= left then
				room:set({ top = top, right = right, bottom = bottom, left = left })
			end
		end
		local owner = assert(Compose.currentOwner(), "Facet stack shadow room needs an owner")
		local function connect(node: Instance, event: string, handler: (...unknown) -> ()): () -> ()
			return Compose.withOwner(owner, function(): () -> ()
				return runtime.connect(node, event, handler)
			end)
		end
		local stops: { [Instance]: { () -> () } } = {}
		local function forget(item: Instance)
			local list = stops[item]
			if list then
				for _, stop in list do
					stop()
				end
			end
			stops[item] = nil
		end
		local function watchShadow(item: Instance)
			if item:IsA("UIShadow") and stops[item] == nil then
				stops[item] = { connect(item, "Changed", measure) }
			end
		end
		local function watchChild(child: Instance)
			if not child:IsA("GuiObject") or stops[child] ~= nil then
				return
			end
			stops[child] = {
				connect(child, "Changed", function(property: unknown)
					if property == "Visible" then
						measure()
					end
				end),
				connect(child, "ChildAdded", function(added: unknown)
					local item = added :: Instance
					if item:IsA("UIShadow") then
						watchShadow(item)
						measure()
					end
				end),
				connect(child, "ChildRemoved", function(removed: unknown)
					local item = removed :: Instance
					if item:IsA("UIShadow") then
						forget(item)
						measure()
					end
				end),
			}
			for _, item in child:GetChildren() do
				watchShadow(item)
			end
		end
		for _, child in frame:GetChildren() do
			watchChild(child)
		end
		connect(frame, "ChildAdded", function(added: unknown)
			local child = added :: Instance
			watchChild(child)
			measure()
		end)
		connect(frame, "ChildRemoved", function(removed: unknown)
			local child = removed :: Instance
			if child:IsA("GuiObject") then
				for _, item in child:GetChildren() do
					forget(item)
				end
				forget(child)
				measure()
			end
		end)
		measure()
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
	function kit.list(flow: Shared.Flow, vertical: Shared.Value<boolean>): UIListLayout
		local function column(use: ComposeTypes.Use?): boolean
			return read(vertical, use) == true
		end
		local steady = not live(vertical)
		local function uses(onColumn: unknown, onRow: unknown): boolean
			if steady then
				return if column(nil) then onColumn ~= nil else onRow ~= nil
			end
			return onColumn ~= nil or onRow ~= nil
		end
		local native: Shared.UIListLayoutNativeProps = {
			FillDirection = derive(function(use)
				return if column(use) then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
			end, vertical),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}
		if flow.gap ~= nil then
			native.Padding = spacingValue(flow.gap)
		end
		if flow.wrap ~= nil then
			native.Wraps = flow.wrap
		end
		local H, V = Enum.HorizontalAlignment, Enum.VerticalAlignment
		local function align(use: ComposeTypes.Use?): Shared.Align
			local value: Shared.Align? = read(flow.align, use)
			assert(
				value == nil or valid(value, { start = true, center = true, ["end"] = true, stretch = true }),
				"Facet align must be start, center, end or stretch"
			)
			return if value == nil then "start" else value
		end
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
		if uses(flow.align, flow.distribute) then
			native.HorizontalAlignment = derive(function(use)
				return edge(if column(use) then align(use) else distribute(use), H.Left, H.Center, H.Right)
			end, vertical, flow.align, flow.distribute)
		end
		if uses(flow.distribute, flow.align) then
			native.VerticalAlignment = derive(function(use)
				return edge(if column(use) then distribute(use) else align(use), V.Top, V.Center, V.Bottom)
			end, vertical, flow.align, flow.distribute)
		end
		local cross = if flow.align ~= nil and (live(flow.align) or align(nil) == "stretch") then flow.align else nil
		local main = if flow.distribute ~= nil and (live(flow.distribute) or spread[distribute(nil)])
			then flow.distribute
			else nil
		if cross ~= nil then
			native.ItemLineAlignment = derive(function(use)
				return if align(use) == "stretch"
					then Enum.ItemLineAlignment.Stretch
					else Enum.ItemLineAlignment.Automatic
			end, flow.align)
		end
		local function flex(use: ComposeTypes.Use?, stretching: boolean): Enum.UIFlexAlignment
			if stretching then
				return if cross ~= nil and align(use) == "stretch"
					then Enum.UIFlexAlignment.Fill
					else Enum.UIFlexAlignment.None
			end
			return if main ~= nil
				then spread[distribute(use)] or Enum.UIFlexAlignment.None
				else Enum.UIFlexAlignment.None
		end
		if uses(cross, main) then
			native.HorizontalFlex = derive(function(use)
				return flex(use, column(use))
			end, vertical, cross, main)
		end
		if uses(main, cross) then
			native.VerticalFlex = derive(function(use)
				return flex(use, not column(use))
			end, vertical, cross, main)
		end
		return Host.UIListLayout(native)
	end

	local SPAN = 65536
	function kit.ordered(children: { ComposeTypes.Child }, place: ((GuiObject, number) -> ())?): { ComposeTypes.Child }
		local spaced = false
		for _, child in children do
			spaced = spaced or type(child) == "function"
		end
		local result: { ComposeTypes.Child } = {}
		for index, child in children do
			local base = if spaced then index * SPAN else index
			if type(child) == "function" then
				local directive = child :: ComposeTypes.Directive
				result[index] = function(mountPoint: ComposeTypes.MountPoint)
					local slot: { Instance } = {}
					local stamped: { [Instance]: number } = {}
					local own: { [Instance]: number } = {}
					local watches: { [Instance]: RBXScriptConnection } = {}
					local function restamp()
						for at, node in slot do
							if node:IsA("GuiObject") then
								local order = base + (own[node] or at)
								stamped[node] = order;
								(node :: GuiObject).LayoutOrder = order
							end
						end
					end
					local function forget(node: Instance)
						local found = table.find(slot, node)
						if found then
							table.remove(slot, found)
						end
						if watches[node] then
							watches[node]:Disconnect()
						end
						watches[node], stamped[node], own[node] = nil, nil, nil
					end
					Compose.cleanup(function()
						for node in watches do
							forget(node)
						end
					end)
					directive({
						parent = mountPoint.parent,
						host = mountPoint.host,
						ordersChildren = true,
						count = mountPoint.count,
						insert = function(node: unknown, at: number?)
							local gui = node :: Instance
							table.insert(slot, at or #slot + 1, gui)
							if gui:IsA("GuiObject") then
								local authored = (gui :: GuiObject).LayoutOrder
								if authored ~= 0 then
									own[gui] = authored
								end
								watches[gui] = gui:GetPropertyChangedSignal("LayoutOrder"):Connect(function()
									local order = (gui :: GuiObject).LayoutOrder
									if order ~= stamped[gui] then
										own[gui] = order
										restamp()
									end
								end)
								if place then
									place(gui :: GuiObject, index)
								end
							end
							restamp()
							mountPoint.insert(node, at)
						end,
						moveTo = function(node: unknown, at: number)
							table.remove(slot, assert(table.find(slot, node :: Instance)))
							table.insert(slot, at, node :: Instance)
							restamp()
							if mountPoint.ordersChildren then
								mountPoint.moveTo(node, at)
							end
						end,
						remove = function(node: unknown)
							forget(node :: Instance)
							mountPoint.remove(node)
							restamp()
						end,
					})
				end
			else
				if (child :: Instance):IsA("GuiObject") then
					local gui = child :: GuiObject
					gui.LayoutOrder = base
					if place then
						place(gui, index)
					end
				end
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

	function kit.plain<N>(node: N & Instance, properties: unknown?): N & Instance
		if ((properties or {}) :: { BackgroundTransparency: unknown? }).BackgroundTransparency == nil then
			node:AddTag("facet-layout")
		end
		return node
	end
	function kit.stack(
		children: { ComposeTypes.Child },
		properties: Shared.FrameNativeProps?,
		flow: Shared.Flow,
		vertical: Shared.Value<boolean>,
		width: Shared.Extent?,
		height: Shared.Extent?
	): Frame
		local size, automatic = kit.extent(flow, width or "hug", height or "hug")
		local native: Shared.FrameNativeProps = {
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local room: ComposeTypes.Cell<Room>? = if flow.padding ~= nil
			then Compose.cell({ top = 0, right = 0, bottom = 0, left = 0 } :: Room)
			else nil
		local list = kit.list(flow, vertical)
		local frame = Host.Frame(kit.assemble(native, properties, { list, kit.insets(flow.padding, room) }, children))
		if room then
			kit.shadowRoom(frame, room)
		end
		if flow.align == "stretch" or live(flow.align) then
			kit.regrow(frame, list)
		end
		return kit.plain(frame, properties)
	end
	function kit.regrow(frame: Frame, list: UIListLayout)
		local frames = config.services and config.services.RunService
		if frames == nil then
			return
		end
		local function span(node: GuiObject, column: boolean): (number, number)
			local at, size = node.AbsolutePosition, node.AbsoluteSize
			return if column then at.X else at.Y, if column then size.X else size.Y
		end
		local function needs(column: boolean): string
			local key: { string } = {}
			for _, child in frame:GetChildren() do
				if not child:IsA("GuiObject") or not child.Visible then
					continue
				end
				local start = span(child, column)
				local pad = child:FindFirstChildWhichIsA("UIPadding")
				local sides = if pad == nil
					then 0
					elseif column then pad.PaddingLeft.Offset + pad.PaddingRight.Offset
					else pad.PaddingTop.Offset + pad.PaddingBottom.Offset
				local need = 0
				local inner = child:FindFirstChildWhichIsA("UIListLayout")
				if inner then
					local content = inner.AbsoluteContentSize
					need = (if column then content.X else content.Y) + sides
				end
				if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
					local bounds = child.TextBounds
					need = math.max(need, (if column then bounds.X else bounds.Y) + sides)
				end
				for _, inside in child:GetChildren() do
					if inside:IsA("GuiObject") and inside.Visible then
						local at, size = span(inside, column)
						need = math.max(need, at + size - start)
					end
				end
				table.insert(key, tostring(math.round(need)))
			end
			return table.concat(key, ",")
		end
		local released: string? = nil
		local pending = false
		local releasing = false
		local function check()
			pending = false
			if releasing or frame.Parent == nil then
				return
			end
			local column = list.FillDirection == Enum.FillDirection.Vertical
			local property = if column then "HorizontalFlex" else "VerticalFlex"
			local flex = ((list :: unknown) :: { [string]: Enum.UIFlexAlignment })[property]
			if flex ~= Enum.UIFlexAlignment.Fill then
				return
			end
			local key = needs(column)
			if key == released then
				return
			end
			released, releasing = key, true
			local native = (list :: unknown) :: { [string]: Enum.UIFlexAlignment }
			native[property] = Enum.UIFlexAlignment.None
			local connection: RBXScriptConnection? = nil
			connection = frames.Heartbeat:Connect(function()
				if connection then
					connection:Disconnect()
				end
				releasing = false
				if native[property] == Enum.UIFlexAlignment.None then
					native[property] = Enum.UIFlexAlignment.Fill
				end
			end)
		end
		local function schedule()
			if pending then
				return
			end
			pending = true
			local connection: RBXScriptConnection? = nil
			connection = frames.Heartbeat:Connect(function()
				if connection then
					connection:Disconnect()
				end
				check()
			end)
		end
		local watched: { [Instance]: { RBXScriptConnection } } = {}
		local function forget(child: Instance)
			for _, connection in watched[child] or {} do
				connection:Disconnect()
			end
			watched[child] = nil
		end
		local function watch(child: Instance)
			if watched[child] or not child:IsA("GuiObject") then
				return
			end
			local connections: { RBXScriptConnection } = {}
			watched[child] = connections
			local function track(node: Instance)
				if node:IsA("GuiObject") then
					table.insert(connections, node:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
					if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
						table.insert(connections, node:GetPropertyChangedSignal("TextBounds"):Connect(schedule))
					end
				elseif node:IsA("UIListLayout") then
					table.insert(connections, node:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(schedule))
				end
			end
			track(child)
			for _, inside in child:GetChildren() do
				track(inside)
			end
			table.insert(
				connections,
				child.ChildAdded:Connect(function(inside: Instance)
					track(inside)
					schedule()
				end)
			)
			schedule()
		end
		for _, child in frame:GetChildren() do
			watch(child)
		end
		runtime.connect(frame, "ChildAdded", watch)
		runtime.connect(frame, "ChildRemoved", forget)
		Compose.cleanup(function()
			for child in watched do
				forget(child)
			end
		end)
	end
	function kit.underTopbar(frame: GuiObject, under: ComposeTypes.Cell<number>)
		local gui = config.guiService
		if gui == nil then
			return
		end
		local topbar, position, parent =
			ctx.observe.TopbarInset(gui), ctx.observe.AbsolutePosition(frame), ctx.observe.Parent(frame)
		local function measure()
			local band, top = gui.TopbarInset, frame.AbsolutePosition.Y
			local ok, inset = pcall(gui.GetGuiInset, gui)
			under:set(
				if typeof(band) == "Rect" and frame:FindFirstAncestorWhichIsA("ScreenGui")
					then math.max(0, band.Max.Y - (if ok and typeof(inset) == "Vector2" then inset.Y else 0) - top)
					else 0
			)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			use(parent)
			use(topbar)
			use(position)
			measure()
		end)
		local frames = config.services and config.services.RunService
		if frames then
			runtime.connect(frames, "Heartbeat", measure)
		end
	end
	ctx.layoutKit = kit
	return kit
end

return layoutKit
