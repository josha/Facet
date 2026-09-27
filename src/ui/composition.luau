--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Layout = require("./layout_types")
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion")
local resolver = require("./composition_resolve")

type Declared = {
	zone: Layout.Zone,
	rank: number,
	mayDrop: boolean,
	sizes: { ComposeTypes.Cell<Vector2> },
	form: ComposeTypes.Cell<number>,
	animate: boolean,
}

local POP = 0.15
local EXPAND_EDGE = { "trailing", "bottom", "leading" }

return function(ctx: Types.Context, UI: Layout.LayoutControls)
	local Host, read, Compose, runtime = ctx.Host, ctx.read, ctx.Compose, ctx.runtime
	local kit = layoutKit.of(ctx)
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local declared = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Declared }

	UI.Region = ctx.construct("Region", function(spec: Layout.RegionProps): Frame
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
			spec.form == nil or (Compose.isReadable(spec.form) and type((spec.form :: any).set) == "function"),
			"Facet Region form must be a writable cell"
		)
		assert(
			spec.expand == nil or type(spec.expand) == "function",
			"Facet Region expand must be a function that returns the richest content"
		)
		local form: ComposeTypes.Cell<number> = spec.form or Compose.cell(1)
		form:set(1)
		local reduced = reducedMotion(ctx)
		local pop = runtime.timeline({ duration = POP, autoplay = false })
		pop:seek(POP)
		local scale = Compose.formula(function(use: ComposeTypes.Use): number
			return if reduced(use) then 1 else 0.94 + 0.06 * (1 - (1 - use(pop.progress)) ^ 3)
		end)
		local properties = (
			ctx.props(spec, { "zone", "rank", "mayDrop", "form", "expand" }, {
				BorderSizePixel = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = function(use: ComposeTypes.Use): boolean
					return use(form) > 0
				end,
			}) :: unknown
		) :: { [unknown]: unknown }
		local sizes: { ComposeTypes.Cell<Vector2> } = {}
		for index = 1, #properties do
			local child = properties[index] :: any
			assert(
				type(child) ~= "string" and type(child.IsA) == "function" and child:IsA("GuiObject"),
				"Facet Region forms must be GuiObjects, richest first"
			)
			local observed, settled = ctx.observe.AbsoluteSize(child), Compose.cell(V2.zero)
			Compose.watch(function(use: ComposeTypes.Use)
				local size = use(observed)
				if use(scale) == 1 then
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
		properties[#properties + 1] = Host.UIScale "Pop" { Scale = scale }
		if spec.expand then
			local open, floor = Compose.cell(false), ctx.hitFloor()
			local cell = resolver.CELLS[zone]
			local edge = if cell[1] == 2 and cell[2] == 3 then "top" else EXPAND_EDGE[cell[1]]
			Compose.watch(function(use: ComposeTypes.Use)
				if use(form) <= 1 and open:peek() then
					open:set(false)
				end
			end)
			properties[#properties + 1] = (UI :: any).Popover "Expand" {
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value and form:peek() > 1)
				end,
				compact = "popover",
				edge = edge,
				content = spec.expand,
				trigger = Host.TextButton "Expand" {
					Text = "",
					BackgroundTransparency = 1,
					ZIndex = -1,
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = function(use: ComposeTypes.Use): UDim2
						local shown = sizes[use(form)]
						local size = if shown then use(shown) else V2.zero
						return D2.new(1, math.max(0, floor(use) - size.X), 1, math.max(0, floor(use) - size.Y))
					end,
					Visible = function(use: ComposeTypes.Use): boolean
						return use(form) > 1
					end,
				},
			}
		end
		local node = kit.plain(Host.Frame(properties :: any), spec)
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
			animate = false,
		}
		return node
	end)

	local function zoneFrame(
		name: string,
		column: number,
		row: number,
		gap: Types.Value<Types.Space>,
		children: { Frame }
	): Frame
		local fields: { [unknown]: unknown } = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = V2.new((column - 1) / 2, (row - 1) / 2),
			Position = D2.fromScale((column - 1) / 2, (row - 1) / 2),
			Size = D2.new(),
			AutomaticSize = E.AutomaticSize.XY,
			Host.UIListLayout({
				SortOrder = E.SortOrder.LayoutOrder,
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
		return Host.Frame(name)(fields :: any)
	end

	UI.Composition = ctx.construct("Composition", function(spec: Layout.CompositionProps): Frame
		local properties = (ctx.props(spec, { "gap", "padding", "topbar" }) :: unknown) :: {
			[unknown]: unknown,
		}
		local regions: { Frame } = {}
		local helpers: { Instance } = {}
		for index = 1, #properties do
			local child = properties[index] :: any
			if declared[child] then
				table.insert(regions, child)
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
		properties.BorderSizePixel = 0
		properties.Size = if properties.Size == nil then D2.fromScale(1, 1) else properties.Size
		properties[#properties + 1] = kit.insets(function(use: ComposeTypes.Use): Types.Padding
			local value = read(base, use)
			local sides: Types.Sides = if type(value) == "table"
				then value :: Types.Sides
				else { top = value, right = value, bottom = value, left = value }
			return {
				top = kit.spacing(sides.top, use) + use(under),
				right = sides.right,
				bottom = sides.bottom,
				left = sides.left,
			}
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
		local zones: { [string]: Frame } = {}
		local placed: { Frame } = {}
		for zone, children in members do
			local cell = resolver.CELLS[zone]
			local frame =
				zoneFrame(string.upper(string.sub(zone, 1, 1)) .. string.sub(zone, 2), cell[1], cell[2], gap, children)
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
		local root = kit.plain(Host.Frame(properties :: any), spec)
		kit.underTopbar(root, under)
		local riding: (ComposeTypes.Use) -> boolean = function()
			return false
		end
		local stripGui: ScreenGui? = nil
		if #stripRegions > 0 then
			local screen: ComposeTypes.Cell<ScreenGui?> = Compose.cell(nil :: ScreenGui?)
			local holder: ComposeTypes.Cell<Instance?> = Compose.cell(nil :: Instance?)
			local enabled = Compose.cell(true)
			local watched: RBXScriptConnection? = nil
			local function locate()
				local host = root:FindFirstAncestorWhichIsA("ScreenGui")
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
			local band = if ctx.config.guiService then ctx.observe.TopbarInset(ctx.config.guiService) else nil
			riding = function(use: ComposeTypes.Use): boolean
				local rect: Rect? = if band then use(band) else nil
				return read(spec.topbar, use) ~= false and use(holder) ~= nil and rect ~= nil and rect.Width > 0
			end
			local topbarZone = Host.Frame "Topbar" {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 0,
				Size = function(use: ComposeTypes.Use): UDim2
					return if riding(use) then D2.fromScale(1, 1) else D2.new()
				end,
				AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
					return if riding(use) then E.AutomaticSize.None else E.AutomaticSize.XY
				end,
				Host.UIListLayout({
					SortOrder = E.SortOrder.LayoutOrder,
					HorizontalAlignment = E.HorizontalAlignment.Center,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				}),
				table.unpack(stripRegions),
			}
			local created = Host.ScreenGui "CompositionTopbar" {
				ResetOnSpawn = false,
				ZIndexBehavior = E.ZIndexBehavior.Sibling,
				ScreenInsets = E.ScreenInsets.TopbarSafeInsets,
				DisplayOrder = function(use: ComposeTypes.Use): number
					local host = use(screen)
					return if host then host.DisplayOrder else 0
				end,
				Enabled = enabled,
				(Host :: any).StyleLink({
					StyleSheet = function(use: ComposeTypes.Use): StyleSheet?
						local host = use(screen)
						local link = host and host:FindFirstChildWhichIsA("StyleLink")
						return if link then link.StyleSheet else nil
					end,
				}),
			}
			stripGui = created
			runtime.decorate(created, {
				Parent = function(use: ComposeTypes.Use): Instance?
					return if riding(use) then use(holder) else nil
				end,
			})
			runtime.decorate(topbarZone, {
				Parent = function(use: ComposeTypes.Use): Instance?
					return if riding(use) then created else zones.top
				end,
			})
		end
		local box = ctx.layoutSize(safe)
		local last: Vector2? = nil
		local stripSize = if stripGui then ctx.observe.AbsoluteSize(stripGui) else nil
		Compose.watch(function(use: ComposeTypes.Use)
			local extent = use(box)
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
			local band = if stripSize and riding(use) then use(stripSize) else nil
			local chosen = resolver.resolve(
				extent.X,
				extent.Y,
				kit.spacing(gap, use),
				list,
				if band and band.X > 0 then { x = band.X, y = band.Y } else nil
			)
			local moved = last ~= nil and last.X > 0 and last ~= extent
			last = extent
			for index, region in regions do
				declared[region].animate = moved
				declared[region].form:set(chosen[index])
			end
		end)
		return root
	end)
end
