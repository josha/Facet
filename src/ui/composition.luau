--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Layout = require("./layout_types")
local Overlay = require("./overlay_types")
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion").reduced
local resolver = require("./composition_resolve")
local ControlTypes = require("./control_types")
local LayoutProps = require("./layout_props")
local presentationReadiness = require("./presentation_readiness")
local regionPresence = require("./region_presence")
local extentMatch = require("./extent_match")
local reservations = require("./reservations")

type Declared = {
	zone: Layout.Zone,
	rank: number,
	mayDrop: boolean,
	sizes: { ComposeTypes.Cell<Vector2> },
	form: ComposeTypes.Cell<number>,
	yielding: ComposeTypes.Cell<boolean>,
	lift: ComposeTypes.Cell<number>,
	floors: { () -> boolean },
	contents: { GuiObject },
	leading: boolean,
	trailing: boolean,
	animate: boolean,
	reveal: { host: (Instance) -> (), back: () -> () }?,
}
type Placement = { regions: { resolver.Declared }, forms: { number }, landed: { boolean }, riding: boolean }

local EXPAND_EDGE: { Overlay.Edge } = { "trailing", "bottom", "leading" }
local ENGINE_BUTTON = 44
local ENGINE_MARGIN = 2
local SETTLE_PASSES = 30

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, read, Compose, runtime = ctx.Host, ctx.read, ctx.Compose, ctx.runtime
	local kit = layoutKit.of(ctx)
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local declared = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Declared }
	local function layoutSize(node: GuiBase2d, scale: ComposeTypes.Readable<number>?): ComposeTypes.Readable<Vector2>
		local size = ctx.observe.AbsoluteSize(node)
		local unit = scale or ctx.layoutUnit(node)
		return Compose.formula(function(use: ComposeTypes.Use): Vector2
			return use(size) / use(unit)
		end)
	end

	UI.Region = ctx.construct("Region", function(spec: LayoutProps.RegionProps): Frame
		local zone, rank = spec.zone, spec.rank
		assert(
			type(zone) == "string" and resolver.CELLS[zone] ~= nil,
			"Facet Region zone must be topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight or topbar"
		)
		assert(
			type(rank) == "number" and rank >= 1 and rank % 1 == 0,
			"Facet Region rank must be a whole number, 1 or more"
		)
		assert(spec.mayDrop == nil or type(spec.mayDrop) == "boolean", "Facet Region mayDrop must be a boolean")
		assert(
			spec.form == nil or (Compose.isReadable(spec.form) and type(spec.form.set) == "function"),
			"Facet Region form must be a writable cell"
		)
		assert(
			spec.expand == nil or type(spec.expand) == "function",
			"Facet Region expand must be a function that returns the richest content"
		)
		assert(spec.reveal == nil or type(spec.reveal) == "boolean", "Facet Region reveal must be a boolean")
		assert(
			spec.leading == nil or (type(spec.leading) == "boolean" and (spec.leading == false or zone == "topbar")),
			"Facet Region leading must be a boolean, and only a topbar region can lead"
		)
		assert(
			spec.trailing == nil or (type(spec.trailing) == "boolean" and (spec.trailing == false or zone == "topbar")),
			"Facet Region trailing must be a boolean, and only a topbar region can trail"
		)
		assert(not (spec.leading and spec.trailing), "Facet Region cannot both lead and trail")
		local form: ComposeTypes.Cell<number> = spec.form or Compose.cell(1)
		form:set(1)
		local reduced = reducedMotion(ctx)
		local popSeconds = ctx.metric("motion.durations.regionPop")
		local present = ctx.motionEase("present")
		local pop = runtime.timeline({ duration = popSeconds, autoplay = false })
		pop:seek(popSeconds)
		local scale = Compose.formula(function(use: ComposeTypes.Use): number
			local rest = ctx.metric("motion.materialize.modal", use)
			return if reduced(use) then 1 else rest + (1 - rest) * present(use(pop.progress))
		end)
		local yielding = Compose.cell(false)
		local lift = Compose.cell(0)
		local properties = (
			ctx.props(
				spec,
				{ "zone", "rank", "mayDrop", "form", "expand", "reveal", "leading", "trailing" },
				{
					BorderSizePixel = 0,
					Size = D2.new(),
					AutomaticSize = E.AutomaticSize.XY,
					Visible = function(use: ComposeTypes.Use): boolean
						return use(form) > 0 and not use(yielding)
					end,
				}
			) :: unknown
		) :: Types.FrameNativeProps
		local open, hosted = Compose.cell(false), Compose.cell(false)
		local richest = properties[1] :: GuiObject?
		if spec.mayDrop == true and spec.reveal ~= false then
			properties[#properties + 1] = ctx.styled(
				Host.Frame "Reveal" {
					Size = D2.fromOffset(28, 20),
					Host.UICorner({ CornerRadius = ctx.round }),
					ctx.icon("more", {
						AnchorPoint = V2.new(0.5, 0.5),
						Position = D2.fromScale(0.5, 0.5),
						Size = D2.fromOffset(16, 16),
					}),
				},
				"badge"
			)
		end
		local sizes: { ComposeTypes.Cell<Vector2> } = {}
		local floors: { () -> boolean } = {}
		local contents: { GuiObject } = {}
		for index = 1, #properties do
			local child = properties[index] :: GuiObject
			contents[index] = child
			assert(
				type(child) ~= "string" and type(child.IsA) == "function" and child:IsA("GuiObject"),
				"Facet Region forms must be GuiObjects, richest first"
			)
			floors[index] = kit.follow(child, "y", function(use: ComposeTypes.Use?): number
				local raised = if use then use(lift) else lift:peek()
				local away = if use then use(hosted) else hosted:peek()
				return if away and index == 1 then 0 else raised
			end)
			local observed, settled = layoutSize(child), Compose.cell(V2.zero)
			Compose.watch(function(use: ComposeTypes.Use)
				local size = use(observed)
				if use(scale) == 1 and not (index == 1 and use(hosted)) then
					settled:set(size)
				end
			end)
			sizes[index] = settled
			properties[index] = Host.Frame("Form" .. index)({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = function(use: ComposeTypes.Use): boolean
					return use(form) == index
				end,
				child,
			})
		end
		assert(#sizes > 0, "Facet Region needs at least one form")
		local floor = ctx.hitFloor()
		properties[#properties + 1] = Host.UIScale "Pop" { Scale = scale }
		local owner = assert(Compose.currentOwner())
		local home = properties[1] :: Instance
		local function returnHome()
			if owner.isDisposed() then
				return
			end
			local content = assert(richest)
			if content.Parent ~= home then
				content.Parent = home
			end
			hosted:set(false)
		end
		local function hostInto(parent: Instance)
			if spec.expand then
				spec.expand().Parent = parent
				return
			end
			hosted:set(true)
			assert(richest).Parent = parent
		end
		if spec.reveal ~= false and (#sizes > 1 or spec.expand) then
			local content = spec.expand
				or function(): Instance
					local holder = Host.Frame "Hosted" {
						BackgroundTransparency = 1,
						Size = D2.new(),
						AutomaticSize = E.AutomaticSize.XY,
					}
					hostInto(holder)
					Compose.cleanup(returnHome)
					return holder
				end
			local cell = resolver.CELLS[zone]
			local edge: Overlay.Edge = if cell[1] == 2 and cell[2] == 3 then "top" else EXPAND_EDGE[cell[1]]
			Compose.watch(function(use: ComposeTypes.Use)
				if use(form) <= 1 and open:peek() then
					open:set(false)
				end
			end)
			properties[#properties + 1] = UI.Popover "Expand" {
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value and form:peek() > 1)
				end,
				compact = "popover" :: "popover",
				edge = edge,
				content = content,
				trigger = Host.TextButton "Expand" {
					Text = "",
					BackgroundTransparency = 1,
					ZIndex = -1,
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.fromScale(1, 1),
					Visible = function(use: ComposeTypes.Use): boolean
						return use(form) > 1
					end,
				},
			}
		end
		if spec.Size == nil and spec.AutomaticSize == nil then
			properties.AutomaticSize = E.AutomaticSize.None
			properties.Size = function(use: ComposeTypes.Use): UDim2
				local index = use(form)
				local shown = sizes[index]
				local size = if shown then use(shown) else V2.zero
				local minimum = if index > 1
						and spec.reveal ~= false
						and (#sizes > 1 or spec.expand)
					then floor(use)
					else 0
				return D2.fromOffset(math.max(size.X, minimum), math.max(size.Y, minimum))
			end
		end
		local node = kit.plain(Host.Frame(properties), spec)
		regionPresence[node] = Compose.formula(function(use: ComposeTypes.Use): boolean
			return use(form) > 0
				and read(((spec :: unknown) :: { Visible: Types.Value<boolean>? }).Visible, use) ~= false
		end)
		local shown: number? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(form)
			node:SetAttribute("FacetForm", current)
			if shown ~= nil and current > 0 and current ~= shown and declared[node].animate and not reduced() then
				pop:restart()
			end
			shown = current
		end)
		declared[node] = {
			zone = zone :: Layout.Zone,
			rank = rank,
			mayDrop = spec.mayDrop == true,
			sizes = sizes,
			form = form,
			yielding = yielding,
			lift = lift,
			floors = floors,
			contents = contents,
			leading = spec.leading == true,
			trailing = spec.trailing == true,
			animate = false,
			reveal = if spec.reveal ~= false and spec.mayDrop == true
				then { host = hostInto, back = returnHome }
				else nil,
		}
		return node
	end)

	local function zoneFrame(
		name: string,
		column: number,
		row: number,
		gap: Types.Value<Types.Space>,
		children: { Frame },
		shift: ComposeTypes.Readable<resolver.Shift>,
		rows: ComposeTypes.Readable<resolver.Rows>
	): Frame
		local flowing = column == 2 and row ~= 2
		local fields: Types.FrameNativeProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = V2.new((column - 1) / 2, (row - 1) / 2),
			ZIndex = if column == 2 then 2 else 1,
			Position = function(use: ComposeTypes.Use): UDim2
				local moved = use(shift)
				local down = if column ~= 2
					then 0
					elseif row == 1 then moved.top
					elseif row == 3 then -moved.bottom
					else 0
				return D2.new((column - 1) / 2, 0, (row - 1) / 2, down)
			end,
			Size = function(use: ComposeTypes.Use): UDim2
				local packed = if flowing then (if row == 1 then use(rows).top else use(rows).bottom) else 0
				return if packed > 0 then D2.fromOffset(math.ceil(packed), 0) else D2.new()
			end,
			AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
				local packed = if flowing then (if row == 1 then use(rows).top else use(rows).bottom) else 0
				return if packed > 0 then E.AutomaticSize.Y else E.AutomaticSize.XY
			end,
			Host.UIListLayout({
				SortOrder = E.SortOrder.LayoutOrder,
				FillDirection = if flowing then E.FillDirection.Horizontal else E.FillDirection.Vertical,
				Wraps = flowing,
				ItemLineAlignment = if not flowing
					then E.ItemLineAlignment.Automatic
					elseif row == 1 then E.ItemLineAlignment.Start
					else E.ItemLineAlignment.End,
				VerticalAlignment = if flowing and row == 3
					then E.VerticalAlignment.Bottom
					else E.VerticalAlignment.Top,
				HorizontalAlignment = if column == 1
					then E.HorizontalAlignment.Left
					elseif column == 2 then E.HorizontalAlignment.Center
					else E.HorizontalAlignment.Right,
				Padding = function(use: ComposeTypes.Use): UDim
					return D.new(0, kit.spacing(gap, use))
				end,
			}),
		}
		for _, child in children do
			fields[#fields + 1] = child
		end
		return Host.Frame(name)(fields)
	end

	UI.Composition = ctx.construct("Composition", function(spec: LayoutProps.CompositionProps): Frame
		local properties = (ctx.props(spec, { "gap", "padding", "topbar", "rows" }) :: unknown) :: Types.FrameNativeProps
		local regions: { Frame } = {}
		local helpers: { Instance } = {}
		for index = 1, #properties do
			local child = properties[index] :: GuiObject
			if declared[child] then
				table.insert(regions, child :: Frame)
			else
				assert(
					type(child) == "table" or typeof(child) == "Instance",
					"Facet Composition children must be UI.Region nodes"
				)
				assert(
					type(child.IsA) == "function" and child:IsA("UIFlexItem"),
					"Facet Composition children must be UI.Region nodes or a UIFlexItem"
				)
				table.insert(helpers, child)
			end
			properties[index] = nil
		end
		for _, helper in helpers do
			properties[#properties + 1] = helper
		end
		local gap: Types.Value<Types.Space> = if spec.gap == nil then "s" else spec.gap
		local base: Types.Value<Types.Padding> = if spec.padding == nil then "s" else spec.padding
		local under = Compose.cell(0)
		local direct = Compose.cell(false)
		local distant = ctx.tenFoot()
		local overscan = ctx.config.environment and ctx.config.environment.overscanInsets
		local FRACTION = { top = 60 / 1080, bottom = 60 / 1080, left = 90 / 1920, right = 90 / 1920 }
		properties.BorderSizePixel = 0
		properties.Size = if properties.Size == nil then D2.fromScale(1, 1) else properties.Size
		properties[#properties + 1] = kit.insets(function(use: ComposeTypes.Use): Types.Padding
			local value = read(base, use)
			local sides: Types.Sides = if type(value) == "table"
				then value :: Types.Sides
				else { top = value, right = value, bottom = value, left = value }
			local margins = read(overscan, use)
			local framed = use(direct)
			local function side(name: "top" | "right" | "bottom" | "left", pixels: number): UDim
				if framed and type(margins) == "table" then
					return D.new(0, pixels + ((margins :: { [string]: number })[name] or 0))
				end
				return D.new(if framed and margins == nil and distant(use) then FRACTION[name] else 0, pixels)
			end
			return (
				{
					top = side("top", kit.spacing(sides.top, use) + use(under)),
					right = side("right", kit.spacing(sides.right, use)),
					bottom = side("bottom", kit.spacing(sides.bottom, use)),
					left = side("left", kit.spacing(sides.left, use)),
				} :: unknown
			) :: Types.Padding
		end)
		local members: { [string]: { Frame } } = {}
		local stripRegions: { Frame } = {}
		for order, region in regions do
			local zone = declared[region].zone
			region.LayoutOrder = order
			local home = if zone == "topbar" then "top" else zone
			members[home] = members[home] or {}
			if zone == "topbar" then
				table.insert(stripRegions, region)
			else
				table.insert(members[home], region)
			end
		end
		local landedZone: Frame? = nil
		if #stripRegions > 0 then
			landedZone = Host.Frame "Landed" {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Host.UIListLayout({
					SortOrder = E.SortOrder.LayoutOrder,
					HorizontalAlignment = E.HorizontalAlignment.Center,
					Padding = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				}),
			}
		end
		local zones: { [string]: Frame } = {}
		local placed: { Frame } = {}
		local shift: ComposeTypes.Cell<resolver.Shift> = Compose.cell({ top = 0, bottom = 0 } :: resolver.Shift)
		local rows: ComposeTypes.Cell<resolver.Rows> = Compose.cell({ top = 0, bottom = 0 } :: resolver.Rows)
		for zone, children in members do
			local cell = resolver.CELLS[zone]
			local frame = zoneFrame(
				string.upper(string.sub(zone, 1, 1)) .. string.sub(zone, 2),
				cell[1],
				cell[2],
				gap,
				if zone == "top" and landedZone then { landedZone :: Frame, table.unpack(children) } else children,
				shift,
				rows
			)
			zones[zone] = frame
			table.insert(placed, frame)
		end
		local safe = Host.Frame "Zones" {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			table.unpack(placed),
		}
		properties[#properties + 1] = safe
		local frames = ctx.config.services.RunService
		local preparing = frames ~= nil and frames.PreRender ~= nil and runtime.host.frames ~= nil
		local root = kit.plain(
			if preparing
				then ctx.fade((properties :: unknown) :: Types.CanvasGroupNativeProps, false, false)
				else Host.Frame(properties),
			spec
		)
		local function placed()
			local parent: Instance? = root.Parent
			direct:set(if parent then parent:IsA("LayerCollector") else false)
		end
		placed()
		runtime.connect(root, "AncestryChanged", placed)
		if preparing then
			ctx.fadeTo(root, 1)
			root:SetAttribute("FacetPreparing", true)
			local roots: { GuiObject } = {}
			for _, region in regions do
				table.insert(roots, region)
			end
			local ready = presentationReadiness(ctx, roots)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(ready) then
					ctx.fadeTo(root, 0)
					root:SetAttribute("FacetPreparing", false)
				end
			end)
		end
		kit.underTopbar(root, under)
		local riding: (ComposeTypes.Use) -> boolean = function()
			return false
		end
		local landed: ComposeTypes.Cell<{ boolean }> = Compose.cell({} :: { boolean })
		local stripGui: ScreenGui? = nil
		local topbarBand = if #stripRegions > 0 and ctx.config.guiService
			then ctx.observe.TopbarInset(ctx.config.guiService)
			else nil
		if #stripRegions > 0 then
			local screen: ComposeTypes.Cell<ScreenGui?> = Compose.cell(nil :: ScreenGui?)
			local holder: ComposeTypes.Cell<Instance?> = Compose.cell(nil :: Instance?)
			local enabled = Compose.cell(true)
			local watched: RBXScriptConnection? = nil
			local function locate()
				local host = root:FindFirstAncestorWhichIsA("ScreenGui")
				if not host then
					local surface = root:FindFirstAncestorWhichIsA("SurfaceGui")
					local source = if surface then ctx.overlayHosts[surface] else nil
					if source and source:IsA("ScreenGui") then
						host = source
					end
				end
				if host ~= screen:peek() then
					if watched then
						watched:Disconnect()
						watched = nil
					end
					if host then
						local current = host
						watched = current:GetPropertyChangedSignal("Enabled"):Connect(function()
							enabled:set(current.Enabled)
						end)
						enabled:set(current.Enabled)
					end
				end
				screen:set(host)
				holder:set(if host then host.Parent else nil)
			end
			runtime.connect(root, "AncestryChanged", locate)
			Compose.cleanup(function()
				if watched then
					watched:Disconnect()
				end
			end)
			locate()
			local band = topbarBand
			riding = function(use: ComposeTypes.Use): boolean
				local rect: Rect? = if band then use(band) else nil
				return read(spec.topbar, use) ~= false and use(holder) ~= nil and rect ~= nil and rect.Width > 0
			end
			local function row(name: string, alignment: Enum.HorizontalAlignment, fields: Types.FrameNativeProps): Frame
				fields.BackgroundTransparency = 1
				fields.BorderSizePixel = 0
				fields[#fields + 1] = Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
					HorizontalAlignment = alignment,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				})
				return Host.Frame(name)(fields)
			end
			local leadsAny, trailsAny = false, false
			for _, region in stripRegions do
				leadsAny = leadsAny or declared[region].leading
				trailsAny = trailsAny or declared[region].trailing
			end
			local leadingRow = row("Leading", E.HorizontalAlignment.Left, {
				LayoutOrder = 1,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = leadsAny,
			})
			local middleRow = row("Middle", E.HorizontalAlignment.Center, {
				LayoutOrder = 2,
				Size = D2.fromScale(0, 1),
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
			})
			local trailingRow = row("Trailing", E.HorizontalAlignment.Right, {
				LayoutOrder = 3,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = trailsAny,
			})
			local topbarZone = row("Topbar", E.HorizontalAlignment.Left, {
				Size = D2.fromScale(1, 1),
				Host.UIPadding({
					PaddingTop = function(use: ComposeTypes.Use): UDim
						local rect: Rect? = if band then use(band) else nil
						local tall = if rect then rect.Height else 0
						return D.new(0, math.max(0, tall - ENGINE_BUTTON - ENGINE_MARGIN))
					end,
					PaddingBottom = D.new(0, ENGINE_MARGIN),
					PaddingLeft = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
					PaddingRight = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				}),
				leadingRow,
				middleRow,
				trailingRow,
			})
			local landing = assert(landedZone)
			for _, region in stripRegions do
				local home = if declared[region].leading
					then leadingRow
					elseif declared[region].trailing then trailingRow
					else middleRow
				local order = assert(table.find(regions, region))
				runtime.decorate(region, {
					Parent = function(use: ComposeTypes.Use): Instance?
						return if riding(use) and not use(landed)[order] then home else landing
					end,
				})
			end
			local created = Host.ScreenGui "CompositionTopbar" {
				ResetOnSpawn = false,
				ZIndexBehavior = E.ZIndexBehavior.Sibling,
				ScreenInsets = E.ScreenInsets.TopbarSafeInsets,
				DisplayOrder = function(use: ComposeTypes.Use): number
					local host = use(screen)
					return if host then host.DisplayOrder else 0
				end,
				Enabled = enabled,
				Host.StyleLink({
					StyleSheet = function(use: ComposeTypes.Use): StyleSheet?
						local host = use(screen)
						local link = host and host:FindFirstChildWhichIsA("StyleLink")
						return if link then link.StyleSheet else nil
					end,
				}),
				topbarZone,
			}
			stripGui = created
			Compose.watch(function(use: ComposeTypes.Use)
				local host = use(screen)
				if host then
					ctx.overlayHosts[created] = host
				end
			end)
			runtime.decorate(created, {
				Parent = function(use: ComposeTypes.Use): Instance?
					return if riding(use) then use(holder) else nil
				end,
			})
		end
		local safeUnit = ctx.layoutUnit(safe)
		local floor = ctx.hitFloor()
		local safeBox = layoutSize(safe, safeUnit)
		for zone, children in members do
			local revealing = false
			for _, region in children do
				revealing = revealing or declared[region].reveal ~= nil
			end
			if not revealing then
				continue
			end
			local cell = resolver.CELLS[zone]
			local column, row = cell[1], cell[2]
			local frame = zones[zone]
			local zoneSize = ctx.observe.AbsoluteSize(frame)
			local anchor = V2.new((column - 1) / 2, (row - 1) / 2)
			local dropped = Compose.formula(function(use: ComposeTypes.Use): { Frame }
				local list = {}
				for _, region in children do
					local entry = declared[region]
					if entry.reveal and use(entry.form) == 0 then
						table.insert(list, region)
					end
				end
				return list
			end)
			local open = Compose.cell(false)
			local hosting: { Frame } = {}
			local function release()
				for _, region in hosting do
					assert(declared[region].reveal).back()
				end
				hosting = {}
			end
			local gathered = dropped:peek()
			Compose.watch(function(use: ComposeTypes.Use)
				local list = use(dropped)
				local same = #list == #gathered
				for index, region in list do
					same = same and gathered[index] == region
				end
				gathered = list
				if not same and open:peek() then
					open:set(false)
				end
			end)
			local function place(use: ComposeTypes.Use): (UDim2, Vector2)
				local unit, space = use(safeUnit), kit.spacing(gap, use)
				local size = use(zoneSize) / unit
				local moved = use(shift)
				local at = (use(safeBox) - size) * anchor
					+ V2.new(
						0,
						if column ~= 2 then 0 elseif row == 1 then moved.top elseif row == 3 then -moved.bottom else 0
					)
				if column == 2 then
					return if row == 3
						then D2.fromOffset(at.X + size.X / 2, at.Y - space)
						else D2.fromOffset(at.X + size.X / 2, at.Y + size.Y + space),
						V2.new(0.5, if row == 3 then 1 else 0)
				end
				local x = if column == 1 then at.X + size.X + space else at.X - space
				return D2.fromOffset(x, at.Y + size.Y * (row - 1) / 2),
					V2.new(if column == 1 then 0 else 1, (row - 1) / 2)
			end
			runtime.mount(function()
				return UI.Popover("Hidden" .. frame.Name) {
					isPresented = open,
					onPresentedChange = function(value: boolean)
						open:set(value and #dropped:peek() > 0)
					end,
					compact = "popover" :: "popover",
					edge = (if column == 2 and row == 3 then "top" else EXPAND_EDGE[column]) :: Overlay.Edge,
					content = function(): Instance
						release()
						local slots: Types.FrameNativeProps = {
							Name = "ZoneHidden",
							BackgroundTransparency = 1,
							Size = D2.new(),
							AutomaticSize = E.AutomaticSize.XY,
							Host.UIListLayout({
								SortOrder = E.SortOrder.LayoutOrder,
								Padding = function(use: ComposeTypes.Use): UDim
									return D.new(0, kit.spacing(gap, use))
								end,
							}),
						}
						local slotFrames = {}
						for index, region in dropped:peek() do
							local slot = Host.Frame("Hidden" .. region.Name)({
								LayoutOrder = index,
								BackgroundTransparency = 1,
								Size = D2.new(),
								AutomaticSize = E.AutomaticSize.XY,
							})
							slots[#slots + 1] = slot
							slotFrames[region] = slot
						end
						local holder = Host.Frame(slots)
						for region, slot in slotFrames do
							assert(declared[region].reveal).host(slot)
							table.insert(hosting, region)
						end
						Compose.cleanup(release)
						return holder
					end,
					trigger = Host.TextButton("ZoneReveal" .. frame.Name) {
						Text = "",
						BackgroundTransparency = 1,
						ZIndex = 5,
						Size = function(use: ComposeTypes.Use): UDim2
							return D2.fromOffset(floor(use), floor(use))
						end,
						Position = function(use: ComposeTypes.Use): UDim2
							return (place(use))
						end,
						AnchorPoint = function(use: ComposeTypes.Use): Vector2
							local _, anchor = place(use)
							return anchor
						end,
						Visible = function(use: ComposeTypes.Use): boolean
							return #use(dropped) > 0
						end,
						ctx.styled(
							Host.Frame "Badge" {
								AnchorPoint = V2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
								Size = D2.fromOffset(28, 20),
								Host.UICorner({ CornerRadius = ctx.round }),
								ctx.icon("more", {
									AnchorPoint = V2.new(0.5, 0.5),
									Position = D2.fromScale(0.5, 0.5),
									Size = D2.fromOffset(16, 16),
								}),
							},
							"badge"
						),
					},
				}
			end, safe)
		end
		local box = layoutSize(safe, safeUnit)
		local warned: { [Frame]: boolean } = {}
		local overflowing: { [Frame]: boolean } = {}
		local streaks: { [Frame]: number } = {}
		local later = runtime.scheduler()
		local last: Vector2? = nil
		local placement: ComposeTypes.Cell<Placement?> = Compose.cell(nil :: Placement?)
		local stripUnit = if stripGui then ctx.layoutUnit(stripGui) else nil
		local stripSize = if stripGui then layoutSize(stripGui, stripUnit) else nil
		local heights = extentMatch.new()
		local pulse, settling, lastStep = Compose.cell(0), 0, -1
		local cancelPulse: (() -> ())? = nil
		local lastMins: { [unknown]: number } = {}
		local seenContent: { [unknown]: number } = {}
		Compose.cleanup(function()
			if cancelPulse then
				cancelPulse()
				cancelPulse = nil
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local beat = use(pulse)
			local stepping = beat ~= lastStep or kit.frameless()
			lastStep = beat
			local unsettled = false
			local extent = use(box)
			local rides = riding(use)
			local list: { resolver.Declared } = {}
			for index, region in regions do
				local entry = declared[region]
				local measured = {}
				for form, observed in entry.sizes do
					local value = use(observed)
					measured[form] = { x = value.X, y = value.Y }
				end
				list[index] = { zone = entry.zone, rank = entry.rank, mayDrop = entry.mayDrop, sizes = measured }
			end
			local strip = if stripSize and rides then use(stripSize) else nil
			if strip and (strip.X <= 0 or strip.Y <= 0) and topbarBand and stripUnit then
				local inset = use(topbarBand)
				strip = V2.new(inset.Width, inset.Height) / use(stripUnit)
			end
			local band = if strip
				then {
					x = strip.X - 2 * kit.spacing(gap, use),
					y = math.min(strip.Y - ENGINE_MARGIN, ENGINE_BUTTON),
				}
				else nil
			local chosen, down, moved, overflow, packed = resolver.resolve(
				extent.X,
				extent.Y,
				kit.spacing(gap, use),
				list,
				if band and strip and strip.X > 0 then band else nil
			)
			local before = landed:peek()
			local same = #before == #down
			for index, value in down do
				same = same and before[index] == value
			end
			if not same then
				landed:set(down)
			end
			local was = shift:peek()
			if was.top ~= moved.top or was.bottom ~= moved.bottom then
				shift:set(moved)
			end
			local wrapped = rows:peek()
			if wrapped.top ~= packed.top or wrapped.bottom ~= packed.bottom then
				rows:set(packed)
			end
			local still: { [Frame]: boolean } = {}
			for _, index in overflow do
				local region = regions[index]
				still[region] = true
				if not overflowing[region] and not warned[region] then
					local streak = (streaks[region] or 0) + 1
					streaks[region] = streak
					later.after(2, function()
						if overflowing[region] and streaks[region] == streak and not warned[region] then
							warned[region] = true
							local size = box:peek()
							warn(
								`Facet Composition: Region '{region.Name}' does not fit {math.floor(size.X)} by {math.floor(
									size.Y
								)} even at its last form and nothing else can give way. Give it a smaller form, mayDrop = true or a higher rank number`
							)
						end
					end)
				end
			end
			overflowing = still
			local resized = last ~= nil and last.X > 0 and last ~= extent
			last = extent
			local stripped = band ~= nil and strip ~= nil and strip.X > 0
			local function placed(index: number): string
				local zone = list[index].zone
				return if zone == "topbar" and (down[index] or not stripped) then "top" else zone
			end
			local filled: { [string]: boolean } = {}
			local empty: { [number]: boolean } = {}
			for index, entry in list do
				local size = if chosen[index] > 0 then entry.sizes[chosen[index]] else nil
				if size and (size.x <= 0 or size.y <= 0) then
					empty[index] = true
				elseif size then
					filled[placed(index)] = true
				end
			end
			for index, region in regions do
				declared[region].animate = resized
				declared[region].form:set(chosen[index])
				declared[region].yielding:set(empty[index] == true and filled[placed(index)] == true)
			end
			local lifts: { [number]: number } = {}
			if read(spec.rows, use) ~= "fit" then
				local spacing = kit.spacing(gap, use)
				for _, edge in { "top", "bottom" } do
					local room = if edge == "top" then packed.top else packed.bottom
					local used = -1
					if edge == "top" then
						for index, entry in list do
							local size = if chosen[index] > 0 then entry.sizes[chosen[index]] else nil
							if entry.zone == "topbar" and placed(index) == "top" and size and not empty[index] then
								used = math.max(used, size.x)
							end
						end
					end
					local line: { number } = {}
					local function close()
						local members: { unknown } = {}
						local measured: { [unknown]: number } = {}
						local natural: { [unknown]: number } = {}
						for _, index in line do
							local region = regions[index]
							local size = list[index].sizes[chosen[index]].y
							local content = declared[region].contents[chosen[index]]
							local scale = if size > 0 then content.AbsoluteSize.Y / size else 1
							table.insert(members, region)
							measured[region] = size
							local own = kit.intrinsic(content, false, if scale > 0 then scale else 1)
							natural[region] = own
							local before = seenContent[region]
							if before == nil or math.abs(before - own) >= 0.5 then
								settling = 0
							end
							seenContent[region] = own
						end
						local mins, done = lastMins, settling >= SETTLE_PASSES
						if stepping and not done then
							mins, done = extentMatch.step(
								heights,
								members,
								measured,
								natural,
								if kit.frameless() then 0 else nil
							)
							for _, key in members do
								lastMins[key] = mins[key]
							end
						end
						unsettled = unsettled or not done
						for _, index in line do
							local region = regions[index]
							local floor = declared[region].floors[chosen[index]]
							if floor and not floor() and declared[region].lift:peek() > 0 then
								extentMatch.forget(heights, region)
							end
							lifts[index] = mins[region] or 0
						end
						table.clear(line)
					end
					for index, entry in list do
						local size = if chosen[index] > 0 then entry.sizes[chosen[index]] else nil
						if entry.zone == edge and size and not empty[index] then
							if used >= 0 and used + spacing + size.x > room + 0.5 then
								close()
								used = -1
							end
							used = if used < 0 then size.x else used + spacing + size.x
							table.insert(line, index)
						end
					end
					close()
				end
			end
			for index, region in regions do
				local value = lifts[index]
				if value == nil then
					extentMatch.forget(heights, region)
					lastMins[region] = nil
					seenContent[region] = nil
				end
				if declared[region].lift:peek() ~= (value or 0) then
					declared[region].lift:set(value or 0)
				end
			end
			if stepping then
				settling += 1
			end
			if unsettled and cancelPulse == nil and settling < SETTLE_PASSES and not kit.frameless() then
				cancelPulse = kit.nextFrame(function()
					cancelPulse = nil
					pulse:set(pulse:peek() + 1)
				end)
			end
			placement:set(
				if extent.X > 0 and extent.Y > 0
					then { regions = list, forms = chosen, landed = down, riding = rides }
					else nil
			)
		end)
		local ancestry = Compose.cell(0)
		local function moved()
			ancestry:set(ancestry:peek() + 1)
		end
		runtime.connect(root, "AncestryChanged", moved)
		local shown = ctx.observe.Visible(root)
		local regionShown: { ComposeTypes.Readable<unknown> } = {}
		for index, region in regions do
			regionShown[index] = ctx.observe.Visible(region)
		end
		local claimed: LayerCollector? = nil
		local claimedParent: Instance? = nil
		local enabling: RBXScriptConnection? = nil
		local checking = false
		local function report()
			checking = false
			local layer = claimed
			if layer == nil then
				return
			end
			for _, contest in reservations.contests(layer, root) do
				reservations.note(root, contest.token, contest.zone)
				warn(
					`Facet Composition: Compositions '{root.Name}' and '{contest.token.Name}' both place regions in the {contest.zone} zone of one screen. Each Composition lays out only its own regions, so the regions can overlap. Keep the HUD of a screen in one Composition`
				)
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			use(ancestry)
			local layer = root:FindFirstAncestorWhichIsA("LayerCollector") :: LayerCollector?
			if layer ~= claimed then
				if enabling then
					enabling:Disconnect()
					enabling = nil
				end
				if claimed then
					reservations.clearZones(claimed, root)
				end
				claimed = layer
				if layer then
					enabling = layer:GetPropertyChangedSignal("Enabled"):Connect(moved)
				end
			end
			local now = use(placement)
			if layer == nil then
				return
			end
			local held: { [string]: boolean } = {}
			if now and layer.Enabled and use(shown) ~= false then
				local forms = table.clone(now.forms)
				for index in forms do
					if use(regionShown[index]) == false then
						forms[index] = 0
					end
				end
				held = resolver.occupied(now.regions, forms, now.landed, now.riding)
			end
			local changed = reservations.setZones(layer, root, held) or layer.Parent ~= claimedParent
			claimedParent = layer.Parent
			if changed and not checking and #reservations.contests(layer, root) > 0 then
				checking = true
				later.after(2, report)
			end
		end)
		Compose.cleanup(function()
			if enabling then
				enabling:Disconnect()
			end
			if claimed then
				reservations.clearZones(claimed, root)
			end
		end)
		return root
	end)
end
