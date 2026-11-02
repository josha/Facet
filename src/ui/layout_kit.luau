--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local extentMatch = require("./extent_match")
local sizeFloor = require("./size_floor")
local Theme = require("./theme_types")

export type Place = (GuiObject, number) -> ()
export type Room = { top: number, right: number, bottom: number, left: number }

local function plain<N>(node: N & Instance, properties: unknown?): N & Instance
	if type(properties) ~= "table" or properties.BackgroundTransparency == nil then
		node:AddTag("facet-layout")
	end
	return node
end

export type Kit = {
	spacing: (Shared.Input<Shared.Space>?, ComposeTypes.Use?) -> number,
	insets: (Shared.Input<Shared.Padding>?, ComposeTypes.ReadOnlyValue<Room>?) -> UIPadding?,
	shadowRoom: (GuiObject, ComposeTypes.Value<Room>) -> (),
	extent: (Shared.Box, Shared.Extent, Shared.Extent) -> (Shared.Input<UDim2>, Shared.Input<Enum.AutomaticSize>),
	list: (Shared.Flow, Shared.Input<boolean>, boolean?) -> UIListLayout,
	underTopbar: (GuiObject, ComposeTypes.Value<number>) -> (),
	ordered: (Shared.ChildList, Place?) -> { ComposeTypes.Child },
	assemble: <P>(P, unknown?, { Instance? }, Shared.ChildList, Place?) -> P,
	plain: typeof(plain),
	stack: (
		Shared.ChildList,
		Shared.FrameNativeProps?,
		Shared.Flow,
		Shared.Input<boolean>,
		Shared.Extent?,
		Shared.Extent?
	) -> Frame,
	liftTarget: (GuiObject) -> GuiObject,
	intrinsic: (GuiObject, boolean, number) -> number,
	lifter: (GuiObject, "x" | "y") -> (number) -> boolean,
	follow: (GuiObject, "x" | "y", (ComposeTypes.Use?) -> number) -> () -> boolean,
	match: (Frame, boolean, (ComposeTypes.Use?) -> boolean) -> (),
	frameless: () -> boolean,
	nextFrame: (() -> ()) -> () -> (),
}

local layoutKit = {}

function layoutKit.of(ctx: Shared.Context): Kit
	return (assert(ctx.layoutKit :: Kit?, "Facet layout requires a controls context"))
end

function layoutKit.attach(ctx: Shared.Context): Kit
	local Host, read, types, config, Compose, runtime =
		ctx.Host, ctx.read, ctx.types, ctx.config, ctx.Compose, ctx.runtime
	local Enum = types.Enum
	local kit = {} :: Kit
	local function live(value: unknown): boolean
		return Compose.isValue(value) or type(value) == "function"
	end
	local function derive<T>(compute: (ComposeTypes.Use?) -> T, ...: unknown): Shared.Input<T>
		for index = 1, select("#", ...) do
			if live((select(index, ...))) then
				return function(use: ComposeTypes.Use): T
					return compute(use)
				end
			end
		end
		return compute(nil)
	end
	function kit.spacing(value: Shared.Input<Shared.Space>?, use: ComposeTypes.Use?): number
		local step = read(value, use)
		if step == nil then
			return 0
		end
		if type(step) == "number" then
			assert(step >= 0 and step < math.huge, "Facet spacing must be a finite number of pixels, 0 or more")
			return step
		end
		assert(type(step) == "string", "Facet spacing must be a number or a spacing step")
		local package: Theme.ReadOnlyThemePackage? = read<<Theme.ReadOnlyThemePackage?>>(config.theme, use)
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
	local function spacingValue(value: Shared.Input<Shared.Space>?): Shared.Input<UDim>
		return derive(function(use)
			return types.UDim.new(0, kit.spacing(value, use))
		end, value, if type(read(value)) == "string" then config.theme else nil)
	end
	function kit.insets(padding: Shared.Input<Shared.Padding>?, room: ComposeTypes.ReadOnlyValue<Room>?): UIPadding?
		if padding == nil then
			return nil
		end
		local function side(name: "top" | "right" | "bottom" | "left"): Shared.Input<UDim>
			local function pick(use: ComposeTypes.Use?): Shared.Space?
				local value = read<<Shared.Padding?>>(padding, use)
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
				local insets = if room and use then use(room) elseif room then room:peek() else nil
				local extra = if insets == nil
					then 0
					elseif name == "top" then insets.top
					elseif name == "right" then insets.right
					elseif name == "bottom" then insets.bottom
					else insets.left
				if typeof(value) == "UDim" then
					local given = value
					return if extra > 0 then types.UDim.new(given.Scale, given.Offset + extra) else given
				end
				return types.UDim.new(0, kit.spacing(value :: Shared.Space?, use) + extra)
			end, padding, if type(pick(nil)) == "string" then config.theme else nil, room)
		end
		return Host.UIPadding {
			PaddingTop = side("top"),
			PaddingRight = side("right"),
			PaddingBottom = side("bottom"),
			PaddingLeft = side("left"),
		}
	end
	function kit.shadowRoom(frame: GuiObject, room: ComposeTypes.Value<Room>)
		local function measure()
			local top, right, bottom, left = 0, 0, 0, 0
			for _, child in frame:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					for _, item in child:GetChildren() do
						if item:IsA("UIShadow") and item.Enabled then
							local shadow = item
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
		if type(value) == "number" and value == value then
			return math.max(value, 0)
		end
		assert(
			valid(value, extents),
			`Facet width and height must be fill, hug or a number of pixels, got {tostring(value)}`
		)
		return value
	end
	function kit.extent(
		box: Shared.Box,
		width: Shared.Extent,
		height: Shared.Extent
	): (Shared.Input<UDim2>, Shared.Input<Enum.AutomaticSize>)
		local function resolve(use: ComposeTypes.Use?): (Shared.Extent, Shared.Extent)
			local w = read<<Shared.Extent?>>(box.width, use)
			local h = read<<Shared.Extent?>>(box.height, use)
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
	function kit.list(flow: Shared.Flow, vertical: Shared.Input<boolean>, matched: boolean?): UIListLayout
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
		local native: Shared.UIListLayoutProps = {
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
			local value = read<<Shared.Align?>>(flow.align, use)
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
			local value = read<<Shared.Distribute?>>(flow.distribute, use)
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
		local cross = if not matched
				and flow.align ~= nil
				and (live(flow.align) or align(nil) == "stretch")
			then flow.align
			else nil
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
	local STEP = 64
	function kit.ordered(children: Shared.ChildList, place: ((GuiObject, number) -> ())?): { ComposeTypes.Child }
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
					local function stamp(node: Instance, order: number)
						stamped[node] = order
						if node:IsA("GuiObject") and node.LayoutOrder ~= order then
							node.LayoutOrder = order
						end
					end
					local function restamp()
						local step = if next(own) == nil
							then math.clamp(math.floor((SPAN - 1) / (#slot + 1)), 1, STEP)
							else 1
						for at, node in slot do
							if node:IsA("GuiObject") then
								stamp(node, base + (own[node] or at * step))
							end
						end
					end
					local function settle(at: number)
						local node = slot[at]
						if next(own) ~= nil or not node:IsA("GuiObject") then
							restamp()
							return
						end
						local before, after = base, base + SPAN
						for index = at - 1, 1, -1 do
							local order = stamped[slot[index]]
							if order then
								before = order
								break
							end
						end
						for index = at + 1, #slot do
							local order = stamped[slot[index]]
							if order then
								after = order
								break
							end
						end
						if after - before < 2 then
							restamp()
						elseif after == base + SPAN then
							stamp(node, before + math.min(STEP, (after - before) // 2))
						else
							stamp(node, before + (after - before) // 2)
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
								local authored = gui.LayoutOrder
								if authored ~= 0 then
									own[gui] = authored
								end
								watches[gui] = gui:GetPropertyChangedSignal("LayoutOrder"):Connect(function()
									local order = gui.LayoutOrder
									if order ~= stamped[gui] then
										own[gui] = order
										restamp()
									end
								end)
								if place then
									place(gui, index)
								end
							end
							settle(at or #slot)
							mountPoint.insert(gui, at)
						end,
						moveTo = function(node: unknown, at: number)
							table.remove(slot, assert(table.find(slot, node :: Instance)))
							table.insert(slot, at, node :: Instance)
							stamped[node :: Instance] = nil
							settle(at)
							if mountPoint.ordersChildren then
								mountPoint.moveTo(node :: Instance, at)
							end
						end,
						remove = function(node: unknown)
							forget(node :: Instance)
							mountPoint.remove(node :: Instance)
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
		children: Shared.ChildList,
		place: ((GuiObject, number) -> ())?
	): P
		local fields = (native :: unknown) :: { [unknown]: unknown }
		for index = 1, #helpers do
			local helper = helpers[index]
			if helper then
				fields[#fields + 1] = helper
			end
		end
		for key, value in (properties or {}) :: { [unknown]: unknown } do
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

	kit.plain = plain
	function kit.stack(
		children: Shared.ChildList,
		properties: Shared.FrameNativeProps?,
		flow: Shared.Flow,
		vertical: Shared.Input<boolean>,
		width: Shared.Extent?,
		height: Shared.Extent?
	): Frame
		local size, automatic = kit.extent(flow, width or "hug", height or "hug")
		local native: Shared.FrameNativeProps = {
			BorderSizePixel = 0,
			Size = size,
			AutomaticSize = automatic,
		}
		local room: ComposeTypes.Value<Room>? = if flow.padding ~= nil
			then Compose.cell({ top = 0, right = 0, bottom = 0, left = 0 })
			else nil
		local column = if live(vertical) then nil else read(vertical) == true
		local across: unknown = if column == nil
			then false
			elseif column then read(flow.width) or width
			else read(flow.height) or height
		local matched = (flow.align == "stretch" or live(flow.align))
			and (across == nil or across == "hug")
			and not live(if column then flow.width else flow.height)
		local list = kit.list(flow, vertical, matched)
		local frame = Host.Frame(kit.assemble(native, properties, { list, kit.insets(flow.padding, room) }, children))
		if room then
			kit.shadowRoom(frame, room)
		end
		if matched then
			kit.match(frame, column == true, function(use: ComposeTypes.Use?): boolean
				return read(flow.align, use) == "stretch"
			end)
		end
		if flow.wrap ~= nil and flow.wrap ~= false then
			local content = ctx.observe.AbsoluteContentSize(list)
			local unit = ctx.layoutUnit(frame, "WrapUnit")
			local liftX, liftY = kit.lifter(frame, "x"), kit.lifter(frame, "y")
			Compose.watch(function(use: ComposeTypes.Use)
				local size, scale = use(content), use(unit)
				local inset = if room then use(room) else { top = 0, right = 0, bottom = 0, left = 0 }
				local wraps, vertical = read(flow.wrap, use) == true, read(vertical, use)
				liftX(if wraps and vertical then size.X / scale + inset.left + inset.right else 0)
				liftY(if wraps and not vertical then size.Y / scale + inset.top + inset.bottom else 0)
			end)
		end
		return kit.plain(frame, properties)
	end
	local PLATES = { "facet-panel", "facet-surface", "facet-pane" }
	local function plated(node: Instance): boolean
		for _, tag in PLATES do
			if node:HasTag(tag) then
				return true
			end
		end
		return false
	end
	function kit.liftTarget(node: GuiObject): GuiObject
		local at = node
		while at:IsA("Frame") and not plated(at) and at:FindFirstChildWhichIsA("UIGridStyleLayout") do
			local only: GuiObject? = nil
			local count = 0
			for _, child in at:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					count += 1
					only = child
				end
			end
			if count ~= 1 or only == nil then
				break
			end
			at = assert(only)
		end
		return at
	end
	local mounted = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: boolean }
	local FLOORS: { [string]: boolean } = { Lift = true, TargetFloor = true }
	local function floorOf(target: GuiObject, owner: ComposeTypes.Owner): sizeFloor.Floor?
		for _, child in target:GetChildren() do
			if child:IsA("UISizeConstraint") and not FLOORS[child.Name] then
				return nil
			end
		end
		local floor = sizeFloor.of(target, Compose.cell)
		if not mounted[target] and target:FindFirstChild("TargetFloor") == nil then
			mounted[target] = true
			Compose.withOwner(owner, function()
				runtime.mount(function()
					return Host.UISizeConstraint "Lift" {
						MinSize = function(use: ComposeTypes.Use): Vector2
							return types.Vector2.new(use(floor.x), use(floor.y))
						end,
					}
				end, target)
			end)
		end
		return floor
	end
	local function lifted(node: GuiObject, horizontal: boolean): boolean
		local floor = sizeFloor.peek(node)
		return floor ~= nil and (if horizontal then floor.x:peek() else floor.y:peek()) > 0
	end
	function kit.intrinsic(node: GuiObject, horizontal: boolean, scale: number): number
		local function pixels(value: Vector2): number
			return (if horizontal then value.X else value.Y) / scale
		end
		local pad = node:FindFirstChildWhichIsA("UIPadding")
		local sides = if pad == nil
			then 0
			elseif horizontal then pad.PaddingLeft.Offset + pad.PaddingRight.Offset
			else pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		local text = 0
		if (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) and node.Text ~= "" then
			text = pixels(node.TextBounds)
		end
		local list = node:FindFirstChildWhichIsA("UIListLayout")
		local along = list ~= nil and ((list.FillDirection == Enum.FillDirection.Horizontal) == horizontal)
		local stretched = false
		if list and not along then
			local cross = if list.FillDirection == Enum.FillDirection.Vertical
				then list.HorizontalFlex
				else list.VerticalFlex
			stretched = cross ~= Enum.UIFlexAlignment.None or list.ItemLineAlignment == Enum.ItemLineAlignment.Stretch
		end
		local total, count = 0, 0
		for _, child in node:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				local size = child.Size
				local scaled = (if horizontal then size.X.Scale else size.Y.Scale) ~= 0
				local flexed = list ~= nil
					and (stretched or (along and child:FindFirstChildWhichIsA("UIFlexItem") ~= nil))
				local extent = if scaled
						or flexed
						or lifted(child, horizontal)
					then kit.intrinsic(child, horizontal, scale)
					else pixels(child.AbsoluteSize)
				if list and along then
					total += extent
					count += 1
				elseif list then
					total = math.max(total, extent)
				else
					local offset = if horizontal then child.Position.X.Offset else child.Position.Y.Offset
					total = math.max(total, extent + math.max(0, offset))
				end
			end
		end
		if list and along and count > 1 then
			total += list.Padding.Offset * (count - 1)
		end
		local own = if horizontal then node.Size.X.Offset else node.Size.Y.Offset
		return math.max(own, text + sides, total + sides)
	end
	function kit.lifter(source: GuiObject, axis: "x" | "y"): (number) -> boolean
		local owner = assert(Compose.currentOwner(), "Facet lift needs an owner")
		local target: GuiObject? = nil
		local function apply(node: GuiObject, floor: sizeFloor.Floor, value: number)
			local size = if axis == "x" then floor.x else floor.y
			local shrinking = value < size:peek()
			size:set(value)
			if shrinking then
				local automatic = node.AutomaticSize
				node.AutomaticSize = Enum.AutomaticSize.None
				node.AutomaticSize = automatic
			end
		end
		local function aimed(value: number): GuiObject?
			if value <= 0 or ComposeTypes.owner.isDisposed(owner) then
				return nil
			end
			local aim = kit.liftTarget(source)
			local automatic = aim.AutomaticSize
			if
				automatic ~= Enum.AutomaticSize.XY
				and automatic ~= (if axis == "x" then Enum.AutomaticSize.X else Enum.AutomaticSize.Y)
			then
				return nil
			end
			return aim
		end
		local function release()
			local held = if target then sizeFloor.peek(target) else nil
			if held and target then
				apply(target, held, 0)
			end
			target = nil
		end
		Compose.cleanup(release)
		return function(value: number): boolean
			local aim = aimed(value)
			local floor = if aim then floorOf(aim, owner) else nil
			if aim ~= target or floor == nil then
				release()
			end
			if aim == nil or floor == nil then
				return false
			end
			target = aim
			apply(aim, floor, value)
			return true
		end
	end
	function kit.follow(source: GuiObject, axis: "x" | "y", value: (ComposeTypes.Use?) -> number): () -> boolean
		local frames = config.services and config.services.RunService
		local owner = assert(Compose.currentOwner(), "Facet lift needs an owner")
		local lift = kit.lifter(source, axis)
		local applied = false
		local pending = false
		local function apply()
			pending = false
			if not ComposeTypes.owner.isDisposed(owner) then
				applied = lift(value())
			end
		end
		local function later()
			if pending then
				return
			end
			if frames == nil then
				apply()
				return
			end
			pending = true
			local connection: RBXScriptConnection? = nil
			connection = frames.Heartbeat:Connect(function()
				if connection then
					connection:Disconnect()
				end
				apply()
			end)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			applied = lift(value(use))
		end)
		runtime.connect(source, "DescendantAdded", later)
		runtime.connect(source, "DescendantRemoving", later)
		return function(): boolean
			return applied
		end
	end
	function kit.frameless(): boolean
		return config.services == nil or config.services.RunService == nil
	end
	function kit.nextFrame(callback: () -> ()): () -> ()
		local frames = config.services and config.services.RunService
		if frames == nil then
			callback()
			return function() end
		end
		local connection: RBXScriptConnection? = nil
		connection = frames.Heartbeat:Connect(function()
			if connection then
				connection:Disconnect()
			end
			callback()
		end)
		return function()
			if connection then
				connection:Disconnect()
			end
		end
	end
	function kit.match(frame: Frame, column: boolean, active: (ComposeTypes.Use?) -> boolean)
		local owner = assert(Compose.currentOwner(), "Facet stack matching needs an owner")
		local frames = config.services and config.services.RunService
		local axis: "x" | "y" = if column then "x" else "y"
		local floors = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: (number) -> boolean }
		local unliftable = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [GuiObject]: boolean }
		local unit = ctx.layoutUnit(frame, "MatchUnit")
		local function extent(node: GuiObject): number
			local scale = unit:peek()
			return (if column then node.AbsoluteSize.X else node.AbsoluteSize.Y) / (if scale > 0 then scale else 1)
		end
		local state = extentMatch.new()
		local SETTLE_FRAMES = 30
		local settling = 0
		local seen: { [unknown]: number } = {}
		local function check(): boolean
			if ComposeTypes.owner.isDisposed(owner) then
				return true
			end
			local members: { unknown } = {}
			local measured: { [unknown]: number } = {}
			local natural: { [unknown]: number } = {}
			local scale = unit:peek()
			local fresh = false
			for _, child in frame:GetChildren() do
				if child:IsA("GuiObject") and child.Visible and floors[child] and not unliftable[child] then
					table.insert(members, child)
					measured[child] = extent(child)
					local own = kit.intrinsic(child, column, if scale > 0 then scale else 1)
					natural[child] = own
					local before = seen[child]
					if before == nil or math.abs(before - own) >= 0.5 then
						fresh = true
					end
				end
			end
			local count = 0
			for key in seen do
				count += 1
				if natural[key] == nil then
					fresh = true
				end
			end
			if count ~= #members then
				fresh = true
			end
			table.clear(seen)
			for key, own in natural do
				seen[key] = own
			end
			local on = active()
			if fresh then
				settling = 0
			end
			if on and settling >= SETTLE_FRAMES then
				return true
			end
			settling += 1
			local mins: { [unknown]: number }, settled = {}, true
			if on then
				mins, settled = extentMatch.step(state, members, measured, natural, if frames then nil else 0)
			end
			for child, lift in floors do
				local member = child.Parent == frame and child.Visible and not unliftable[child]
				local value = if member then mins[child] or 0 else 0
				if not lift(value) and value > 0 then
					unliftable[child] = true
					extentMatch.forget(state, child)
					settling = 0
				elseif value <= 0 and (not member or not on) then
					extentMatch.forget(state, child)
				end
			end
			return settled
		end
		local pending = false
		local function schedule()
			if pending or ComposeTypes.owner.isDisposed(owner) then
				return
			end
			if frames == nil then
				check()
				return
			end
			pending = true
			local connection: RBXScriptConnection? = nil
			connection = frames.Heartbeat:Connect(function()
				if connection then
					connection:Disconnect()
				end
				pending = false
				if not check() then
					schedule()
				end
			end)
		end
		local function changed()
			schedule()
		end
		local watched: { [Instance]: { RBXScriptConnection } } = {}
		local function forget(child: Instance)
			local connections = watched[child]
			if connections then
				for _, connection in connections do
					connection:Disconnect()
				end
			end
			watched[child] = nil
			local lift = if child:IsA("GuiObject") then floors[child] else nil
			if lift then
				lift(0)
			end
			if child:IsA("GuiObject") then
				unliftable[child] = nil
			end
			extentMatch.forget(state, child)
			schedule()
		end
		local function watch(child: Instance)
			if watched[child] or not child:IsA("GuiObject") then
				return
			end
			local node = child
			if floors[node] == nil then
				floors[node] = Compose.withOwner(owner, function(): (number) -> boolean
					return kit.lifter(node, axis)
				end)
			end
			watched[child] = {
				node:GetPropertyChangedSignal("AbsoluteSize"):Connect(changed),
				node:GetPropertyChangedSignal("Visible"):Connect(changed),
				node.DescendantAdded:Connect(changed),
				node.DescendantRemoving:Connect(changed),
			}
			schedule()
		end
		for _, child in frame:GetChildren() do
			watch(child)
		end
		runtime.connect(frame, "ChildAdded", watch)
		runtime.connect(frame, "ChildRemoved", forget)
		Compose.watch(function(use: ComposeTypes.Use)
			active(use)
			schedule()
		end)
		Compose.cleanup(function()
			for _, connections in watched do
				for _, connection in connections do
					connection:Disconnect()
				end
			end
			table.clear(watched)
		end)
	end
	function kit.underTopbar(frame: GuiObject, under: ComposeTypes.Value<number>)
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
