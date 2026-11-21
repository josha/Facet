--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Layout = require("./layout_types")
local Overlay = require("./overlay_types")
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion").reduced
local gameplayHold = require("./gameplay_hold")
local resolver = require("./composition_resolve")
local ControlTypes = require("./control_types")
local LayoutProps = require("./layout_props")
local presentationReadiness = require("./presentation_readiness")
local regionPresence = require("./region_presence")
local extentMatch = require("./extent_match")
local reservations = require("./reservations")
local preparation = require("./preparation")

type Declared = {
	zone: Layout.Zone,
	rank: number,
	mayDrop: boolean,
	sizes: { ComposeTypes.Value<Vector2> },
	form: ComposeTypes.Value<number>,
	yielding: ComposeTypes.Value<boolean>,
	lift: ComposeTypes.Value<number>,
	hangs: { ComposeTypes.Value<number> },
	authored: Types.Input<boolean>?,
	floors: { () -> boolean },
	contents: { GuiObject },
	leading: boolean,
	trailing: boolean,
	animate: boolean,
	reveals: boolean,
	reveal: { host: (Instance) -> (), back: () -> () }?,
	label: string?,
	icon: string?,
}
type Resolution = {
	chosen: { number },
	down: { boolean },
	moved: resolver.Shift,
	overflow: { number },
	packed: resolver.Rows,
}

local RESOLUTIONS = 16
local POP_TAG = "facet-region-pop"
local POP_REST = "Rest"

local function regionsKey(list: { resolver.Declared }): string
	local parts: { string } = {}
	for _, entry in list do
		table.insert(
			parts,
			`{entry.zone}:{entry.rank}:{entry.mayDrop}:{entry.leading == true}:{entry.trailing == true}`
		)
		for _, size in entry.sizes do
			table.insert(parts, `{size.x}x{size.y}`)
		end
		local hangs = entry.hangs
		if hangs then
			table.insert(parts, "h")
			for _, hang in hangs do
				table.insert(parts, tostring(hang))
			end
		end
		table.insert(parts, "/")
	end
	return table.concat(parts, ",")
end

local EXPAND_EDGE: { Overlay.Edge } = { "trailing", "bottom", "leading" }
local ENGINE_BUTTON = 44
local ENGINE_MARGIN = 2
local SETTLE_PASSES = 30
local SIMILAR_ROW = 0.5
local PHONES: { { X: number, Y: number } } = { { X = 358, Y = 812 }, { X = 812, Y = 358 } }
local STICK_REACH, JUMP_REACH, JUMP_INSET, JUMP_SIZE = 111, 132, 60, 72

local function phoneControls(phone: { X: number, Y: number }): { resolver.Area }
	local stick = if phone.X > phone.Y then phone.X * 0.4 else phone.X
	return {
		{ left = 0, right = stick, reach = STICK_REACH },
		{ left = phone.X - JUMP_INSET - JUMP_SIZE, right = phone.X - JUMP_INSET, reach = JUMP_REACH },
	}
end
local OUTSIDE = "facet-button-outside"
local OVER_WORLD = "facet-over-world"
local BACKED_TAGS = {
	"facet-badge",
	"facet-button",
	"facet-card",
	"facet-chip",
	"facet-field",
	"facet-menu",
	"facet-notice",
	"facet-pane",
	"facet-panel",
	"facet-sheet",
	"facet-surface",
	"facet-tab",
}

local MIDDLE = { "top", "center", "bottom" }

local function lowered(moved: resolver.Shift, column: number, row: number): number
	local lift = moved.lift[column * 4 + row] or 0
	return if row == 3
		then -moved.hang - (if column == 2 then moved.bottom else 0) + lift
		elseif row == 1 and column == 2 then moved.top
		else lift
end

local function sameLift(a: { [number]: number }, b: { [number]: number }): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function sameAreas(a: { resolver.Area }, b: { resolver.Area }): boolean
	if #a ~= #b then
		return false
	end
	for index, area in a do
		local other = b[index]
		if area.left ~= other.left or area.right ~= other.right or area.reach ~= other.reach then
			return false
		end
	end
	return true
end

local function leaned(moved: resolver.Shift, column: number, row: number): number
	return if column ~= 2 then 0 elseif row == 1 then moved.leanTop elseif row == 3 then moved.leanBottom else 0
end

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, read, Compose, runtime = ctx.Host, ctx.read, ctx.Compose, ctx.runtime
	local readPadding = read<<Types.Padding>>
	local readOverscan = read<<Types.OverscanInsets?>>
	local kit = layoutKit.of(ctx)
	local E, D, D2, V2 = ctx.types.Enum, ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2
	local declared: { [Instance]: Declared } = setmetatable({}, { __mode = "k" })
	local layoutSize = ctx.layoutSize
	local function overhang(
		content: GuiObject,
		unit: ComposeTypes.ReadOnlyValue<number>
	): ComposeTypes.ReadOnlyValue<number>
		local reach = Compose.cell(0)
		local owner = assert(Compose.currentOwner())
		local outside: { [Instance]: boolean } = {}
		local scope: ComposeTypes.Owner? = nil
		local pending: (() -> ())? = nil
		local function measure()
			pending = nil
			if ComposeTypes.owner.isDisposed(owner) then
				return
			end
			local edge = content.AbsolutePosition.Y + content.AbsoluteSize.Y
			local most = 0
			for item in outside do
				local node = item :: GuiObject
				local shown = node.AbsoluteSize.Y > 0
				local at: Instance? = node
				while shown and at and at ~= content do
					if at:IsA("GuiObject") and not at.Visible then
						shown = false
					end
					at = at.Parent
				end
				if shown then
					most = math.max(most, node.AbsolutePosition.Y + node.AbsoluteSize.Y - edge)
				end
			end
			reach:set(most / unit:peek())
		end
		local function settle()
			if kit.frameless() then
				measure()
			elseif pending == nil then
				pending = kit.nextFrame(measure)
			end
		end
		local function track()
			if ComposeTypes.owner.isDisposed(owner) then
				return
			end
			if scope then
				ComposeTypes.owner.dispose(scope)
				scope = nil
			end
			if next(outside) == nil then
				reach:set(0)
				return
			end
			local watching = ComposeTypes.owner.createChild(owner)
			scope = watching
			Compose.withOwner(watching, function()
				local places: { ComposeTypes.ReadOnlyValue<Vector2> } = {}
				local shown: { ComposeTypes.ReadOnlyValue<boolean> } = {}
				local function observe(node: GuiObject)
					table.insert(places, ctx.observe.AbsolutePosition(node))
					table.insert(places, ctx.observe.AbsoluteSize(node))
				end
				observe(content)
				for item in outside do
					local node = item :: GuiObject
					observe(node)
					local at: Instance? = node
					while at and at ~= content do
						if at:IsA("GuiObject") then
							table.insert(shown, ctx.observe.Visible(at))
						end
						at = at.Parent
					end
					runtime.connect(node, "AncestryChanged", function(changed: Instance)
						if changed:IsDescendantOf(content) then
							track()
						end
					end)
				end
				Compose.watch(function(use: ComposeTypes.Use)
					use(unit)
					for _, place in places do
						use(place)
					end
					for _, visible in shown do
						use(visible)
					end
					settle()
				end)
			end)
		end
		for _, node in content:GetDescendants() do
			if node:IsA("GuiObject") and node:HasTag(OUTSIDE) then
				outside[node] = true
			end
		end
		runtime.connect(content, "DescendantAdded", function(added: Instance)
			if not outside[added] and added:IsA("GuiObject") and added:HasTag(OUTSIDE) then
				outside[added] = true
				track()
			end
		end)
		runtime.connect(content, "DescendantRemoving", function(removed: Instance)
			if outside[removed] then
				outside[removed] = nil
				track()
			end
		end)
		Compose.cleanup(function()
			if pending then
				pending()
				pending = nil
			end
		end)
		track()
		return reach
	end

	local function mark(name: string, label: string?, icon: string?, region: string): Instance
		return UI.Badge(name)({ label = label, icon = icon, name = label or region })
	end
	local function backed(node: Instance, form: Instance): boolean
		local at: Instance? = node
		while at do
			if at:IsA("GuiButton") or at:FindFirstChild("Backdrop") or at:FindFirstChild("Ground") then
				return true
			end
			if (at:IsA("ImageLabel") or at:IsA("ImageButton")) and at.Image ~= "" then
				return true
			end
			for _, tag in BACKED_TAGS do
				if at:HasTag(tag) then
					return true
				end
			end
			if at == form then
				return false
			end
			at = at.Parent
		end
		return false
	end
	local function holdFill(item: UIFlexItem, form: Instance)
		local child = item.Parent
		local holder = if child then child.Parent else nil
		local list = if holder then holder:FindFirstChildWhichIsA("UIListLayout") else nil
		if list == nil then
			return
		end
		local along = if list.FillDirection == E.FillDirection.Horizontal then E.AutomaticSize.X else E.AutomaticSize.Y
		local at: Instance? = holder
		while at and at ~= form do
			local hugs = at:IsA("GuiObject")
				and not at:IsA("ScrollingFrame")
				and (at.AutomaticSize == E.AutomaticSize.XY or at.AutomaticSize == along)
			local limit = at:FindFirstChildWhichIsA("UISizeConstraint")
			local most = if limit == nil
				then math.huge
				elseif along == E.AutomaticSize.X then limit.MaxSize.X
				else limit.MaxSize.Y
			if not hugs or most < math.huge then
				return
			end
			at = at.Parent
		end
		if at == nil then
			return
		end
		if item.FlexMode == E.UIFlexMode.Fill then
			item.FlexMode = E.UIFlexMode.Grow
		elseif item.FlexMode == E.UIFlexMode.Shrink then
			item.FlexMode = E.UIFlexMode.None
		elseif item.FlexMode == E.UIFlexMode.Custom then
			item.ShrinkRatio = 0
		end
	end
	local function bareText(form: GuiObject): boolean
		local found = form:IsA("TextLabel") and not backed(form, form)
		for _, node in form:GetDescendants() do
			if node:IsA("GuiButton") then
				return false
			elseif node:IsA("TextLabel") and not backed(node, form) then
				found = true
			end
		end
		return found
	end
	local function outlineOverWorld(form: GuiObject)
		local function outline(node: Instance)
			if node:IsA("TextLabel") and not node:HasTag(OVER_WORLD) and not backed(node, form) then
				node:AddTag(OVER_WORLD)
			end
		end
		for _, node in form:GetDescendants() do
			outline(node)
		end
		outline(form)
		runtime.connect(form, "DescendantAdded", outline)
	end
	UI.Region = ctx.construct("Region", function(spec: LayoutProps.RegionProps): Frame
		local zone, rank = spec.zone, spec.rank
		assert(
			type(zone) == "string" and (zone == "action" or resolver.CELLS[zone] ~= nil),
			"Facet Region zone must be topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight, topbar or action"
		)
		assert(
			type(rank) == "number" and rank >= 1 and rank % 1 == 0,
			"Facet Region rank must be a whole number, 1 or more"
		)
		assert(spec.mayDrop == nil or type(spec.mayDrop) == "boolean", "Facet Region mayDrop must be a boolean")
		assert(
			spec.form == nil or (Compose.isValue(spec.form) and type(spec.form.set) == "function"),
			"Facet Region form must be a writable cell"
		)
		assert(
			spec.expand == nil or type(spec.expand) == "function",
			"Facet Region expand must be a function that returns the richest content"
		)
		assert(spec.reveal == nil or type(spec.reveal) == "boolean", "Facet Region reveal must be a boolean")
		assert(spec.plate == nil or type(spec.plate) == "boolean", "Facet Region plate must be a boolean")
		assert(spec.label == nil or type(spec.label) == "string", "Facet Region label must be a string")
		assert(spec.icon == nil or type(spec.icon) == "string", "Facet Region icon must be an icon name")
		local label = if spec.label ~= "" then spec.label else nil
		local icon = if spec.icon and ctx.iconShows(spec.icon) then spec.icon else nil
		assert(
			spec.leading == nil or (type(spec.leading) == "boolean" and (spec.leading == false or zone == "topbar")),
			"Facet Region leading must be a boolean, and only a topbar region can lead"
		)
		assert(
			spec.trailing == nil or (type(spec.trailing) == "boolean" and (spec.trailing == false or zone == "topbar")),
			"Facet Region trailing must be a boolean, and only a topbar region can trail"
		)
		assert(not (spec.leading and spec.trailing), "Facet Region cannot both lead and trail")
		local form: ComposeTypes.Value<number> = spec.form or Compose.cell(1)
		form:set(1)
		local absent = Compose.selector(form)(0)
		local reduced = reducedMotion(ctx)
		local popping = false
		local settles: { (ComposeTypes.Use?) -> () } = {}
		local popNode = Host.UIScale "Pop" {}
		popNode:AddTag(POP_TAG)
		local popLater = if runtime.host.frames then runtime.scheduler() else nil
		local function popIn()
			local later = popLater
			if later == nil then
				return
			end
			popping = true
			popNode.Name = POP_REST
			later.replace("rest", 0, function()
				popNode.Name = "Pop"
			end)
			later.replace("settle", ctx.metric("motion.durations.regionPop"), function()
				popping = false
				for _, settle in settles do
					settle()
				end
			end)
		end
		local yielding = Compose.cell(false)
		local lift = Compose.cell(0)
		local properties: Types.FrameProps = ctx.props(
			spec,
			{ "zone", "rank", "mayDrop", "form", "expand", "reveal", "plate", "label", "icon", "leading", "trailing" },
			{
				BorderSizePixel = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = function(use: ComposeTypes.Use): boolean
					return not use(absent) and not use(yielding)
				end,
			}
		)
		local open, hosted = Compose.cell(false), Compose.cell(false)
		local richest: GuiObject? = nil
		local unnamed: Frame? = nil
		if spec.mayDrop == true and spec.reveal ~= false then
			if label or icon then
				local named = if type(spec.Name) == "string" then spec.Name else "Region"
				properties[#properties + 1] = mark("Reveal", label, icon, named)
			else
				local generic = ctx.styled(
					Host.Frame "Reveal" {
						Size = D2.fromOffset(28, 20),
						Host.UICorner { CornerRadius = ctx.round },
						ctx.icon("more", {
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							Size = D2.fromOffset(16, 16),
						}),
					},
					"badge"
				)
				unnamed = generic
				properties[#properties + 1] = generic
			end
		end
		local sizes: { ComposeTypes.Value<Vector2> } = {}
		local hangs: { ComposeTypes.Value<number> } = {}
		local floors: { () -> boolean } = {}
		local contents: { GuiObject } = {}
		local forms: { Frame } = {}
		local below = zone == "action" or resolver.CELLS[zone][2] == 3
		for index = 1, #properties do
			local given: unknown = properties[index]
			local child = given :: GuiObject
			if not (typeof(given) == "Instance" and given:IsA("GuiObject")) then
				local message =
					"Facet Region forms must be GuiObjects, richest first. Put reactive children inside a stable form."
				if not ctx.recover(message .. " This Region wraps the child in a form.") then
					error(message, 0)
				end
				child = Host.Frame {
					BackgroundTransparency = 1,
					Size = D2.new(),
					AutomaticSize = E.AutomaticSize.XY,
					given :: ComposeTypes.Child,
				}
			end
			local list = child:FindFirstChildWhichIsA("UIListLayout")
			local hugs = child.AutomaticSize == E.AutomaticSize.X or child.AutomaticSize == E.AutomaticSize.XY
			if list and hugs and list.FillDirection == E.FillDirection.Horizontal and list.Wraps then
				list.Wraps = false
			end
			if spec.plate ~= false then
				if zone == "topbar" and bareText(child) then
					child = UI.HStack "Readout" {
						surface = "panel",
						align = "center",
						padding = { top = "s", bottom = "s", left = "m", right = "m" },
						child,
					}
				else
					outlineOverWorld(child)
				end
			end
			contents[index] = child
			if index == 1 then
				richest = child
			end
			floors[index] = kit.follow(child, "y", function(use: ComposeTypes.Use?): number
				local raised = if use then use(lift) else lift:peek()
				local away = if use then use(hosted) else hosted:peek()
				return if away and index == 1 then 0 else raised
			end)
			local unit = ctx.layoutUnit(child)
			local observed, settled = layoutSize(child, unit), Compose.cell(V2.zero)
			sizes[index] = settled
			local hang = Compose.cell(0)
			local reach = if below then overhang(child, unit) else nil
			local function settle(use: ComposeTypes.Use?)
				local size = if use then use(observed) else observed:peek()
				local value = if reach then (if use then use(reach) else reach:peek()) else 0
				local away = index == 1 and (if use then use(hosted) else hosted:peek())
				if not popping and not away then
					settled:set(size)
					hang:set(value)
				end
			end
			table.insert(settles, settle)
			Compose.watch(settle)
			hangs[index] = hang
			local frame = Host.Frame("Form" .. index)({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = form:peek() == index,
				child,
			})
			properties[index] = frame
			forms[index] = frame
			for _, inner in frame:GetDescendants() do
				if inner:IsA("UIFlexItem") then
					holdFill(inner, frame)
				end
			end
			runtime.connect(frame, "DescendantAdded", function(inner: Instance)
				if inner:IsA("UIFlexItem") then
					holdFill(inner, frame)
				end
			end)
		end
		assert(#sizes > 0, "Facet Region needs at least one form")
		local floor = ctx.hitFloor()
		properties[#properties + 1] = popNode
		local owner = assert(Compose.currentOwner())
		local home: Instance = forms[1]
		local function returnHome()
			if ComposeTypes.owner.isDisposed(owner) then
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
			local cell = resolver.CELLS[if zone == "action" then "bottom" else zone]
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
				compact = "popover",
				closeButton = false,
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
		if spec.Size == nil and spec.AutomaticSize == nil and spec.reveal ~= false then
			properties.AutomaticSize = E.AutomaticSize.None
			properties.Size = function(use: ComposeTypes.Use): UDim2
				local index = use(form)
				local shown = sizes[index]
				local size = if shown then use(shown) else V2.zero
				local minimum = if index > 1 and (#sizes > 1 or spec.expand) then floor(use) else 0
				return D2.fromOffset(math.max(size.X, minimum), math.max(size.Y, minimum))
			end
		end
		local node = kit.plain(Host.Frame(properties), spec)
		if unnamed then
			unnamed:SetAttribute("FacetReveal", node.Name)
		end
		local authored = spec.Visible
		regionPresence[node] = Compose.formula(function(use: ComposeTypes.Use): boolean
			return not use(absent) and read(authored, use) ~= false
		end)
		local shown: number? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local current = use(form)
			if shown and forms[shown] then
				forms[shown].Visible = false
			end
			if forms[current] then
				forms[current].Visible = true
			end
			node:SetAttribute("FacetForm", current)
			if shown ~= nil and current > 0 and current ~= shown and declared[node].animate and not reduced() then
				popIn()
			end
			shown = current
		end)
		declared[node] = {
			zone = zone,
			rank = rank,
			mayDrop = spec.mayDrop == true,
			sizes = sizes,
			form = form,
			yielding = yielding,
			lift = lift,
			hangs = hangs,
			authored = authored,
			floors = floors,
			contents = contents,
			leading = spec.leading == true,
			trailing = spec.trailing == true,
			animate = false,
			reveals = spec.reveal ~= false,
			reveal = if spec.reveal ~= false then { host = hostInto, back = returnHome } else nil,
			label = label,
			icon = icon,
		}
		return node
	end)

	local function zoneFrame(
		name: string,
		column: number,
		row: number,
		gap: Types.Input<Types.Space>,
		children: { Frame },
		shift: ComposeTypes.ReadOnlyValue<resolver.Shift>,
		rows: ComposeTypes.ReadOnlyValue<resolver.Rows>
	): Frame
		local flowing = column == 2 and row ~= 2
		local wrapping = flowing and (#children ~= 1 or row == 3)
		local fields: Types.FrameProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = V2.new((column - 1) / 2, (row - 1) / 2),
			ZIndex = if column == 2 then 2 else 1,
			Position = function(use: ComposeTypes.Use): UDim2
				local moved = use(shift)
				return D2.new((column - 1) / 2, leaned(moved, column, row), (row - 1) / 2, lowered(moved, column, row))
			end,
			Size = function(use: ComposeTypes.Use): UDim2
				local packed = if wrapping then (if row == 1 then use(rows).top else use(rows).bottom) else 0
				return if packed > 0 then D2.fromOffset(math.ceil(packed), 0) else D2.new()
			end,
			AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
				local packed = if wrapping then (if row == 1 then use(rows).top else use(rows).bottom) else 0
				return if packed > 0 then E.AutomaticSize.Y else E.AutomaticSize.XY
			end,
			Host.UIListLayout {
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
			},
		}
		for _, child in children do
			fields[#fields + 1] = child
		end
		return Host.Frame(fields, name)
	end

	UI.Composition = ctx.construct("Composition", function(spec: LayoutProps.CompositionProps): Frame
		local properties: Types.FrameProps = ctx.props(spec, { "gap", "padding", "topbar", "rows", "passive" })
		local regions: { Frame } = {}
		local helpers: { Instance } = {}
		for index = 1, #properties do
			local child = properties[index] :: GuiObject
			if declared[child] then
				table.insert(regions, child :: Frame)
			else
				assert(
					type(child) == "table" or typeof(child) == "Instance",
					"Facet Composition children must be UI.Region nodes. Put Compose.show inside a stable Region form, not around the Region."
				)
				assert(
					type(child.IsA) == "function" and child:IsA("UIFlexItem"),
					"Facet Composition children must be UI.Region nodes or a UIFlexItem. Put Compose.show inside a stable Region form, not around the Region."
				)
				table.insert(helpers, child)
			end
			properties[index] = nil
		end
		for _, helper in helpers do
			properties[#properties + 1] = helper
		end
		local gap: Types.Input<Types.Space> = if spec.gap == nil then "s" else spec.gap
		local base: Types.Input<Types.Padding> = if spec.padding == nil then "s" else spec.padding
		local literalPadding = kit.literal(base)
		local under = Compose.cell(0)
		local touch = Compose.cell(0)
		local touchAreas: ComposeTypes.Value<{ resolver.Area }> = Compose.cell({}, sameAreas)
		local direct = Compose.cell(false)
		local nested: ComposeTypes.Value<{ [string]: number }?> = Compose.cell(nil :: { [string]: number }?)
		local distant = ctx.tenFoot()
		local overscan = ctx.config.environment and ctx.config.environment.overscanInsets
		local FRACTION = { top = 60 / 1080, bottom = 60 / 1080, left = 90 / 1920, right = 90 / 1920 }
		properties.BorderSizePixel = 0
		local hostClearance = Compose.cell(0)
		properties.Size = if properties.Size == nil
			then function(use: ComposeTypes.Use): UDim2
				return D2.new(1, 0, 1, use(hostClearance))
			end
			else properties.Size
		properties[#properties + 1] = kit.insets(function(use: ComposeTypes.Use): Types.Padding
			local value = readPadding(base, use)
			local sides: Types.Sides = if type(value) == "table"
				then value
				else { top = value, right = value, bottom = value, left = value }
			local margins = readOverscan(overscan, use)
			local framed = use(direct)
			local within = if framed then nil else use(nested)
			local function side(name: "top" | "right" | "bottom" | "left", pixels: number): UDim
				if within then
					return D.new(0, pixels + within[name])
				end
				if framed and type(margins) == "table" then
					local inset = if name == "top"
						then margins.top
						elseif name == "right" then margins.right
						elseif name == "bottom" then margins.bottom
						else margins.left
					return D.new(0, pixels + inset)
				end
				return D.new(if framed and margins == nil and distant(use) then FRACTION[name] else 0, pixels)
			end
			return (
				{
					top = side("top", kit.spacing(sides.top, use, literalPadding) + use(under)),
					right = side("right", kit.spacing(sides.right, use, literalPadding)),
					bottom = side("bottom", kit.spacing(sides.bottom, use, literalPadding)),
					left = side("left", kit.spacing(sides.left, use, literalPadding)),
				} :: unknown
			) :: Types.Padding
		end)
		local members: { [string]: { Frame } } = {}
		local stripRegions: { Frame } = {}
		local actionRegions: { Frame } = {}
		for order, region in regions do
			local zone = declared[region].zone
			region.LayoutOrder = order
			local home = if zone == "topbar" then "top" else zone
			if zone == "action" then
				table.insert(actionRegions, region)
				members.bottom = members.bottom or {}
				members.bottomRight = members.bottomRight or {}
			else
				members[home] = members[home] or {}
			end
			if zone == "topbar" then
				table.insert(stripRegions, region)
			elseif zone ~= "action" then
				table.insert(members[home], region)
			end
		end
		local leadsAny, trailsAny = false, false
		for _, region in stripRegions do
			leadsAny = leadsAny or declared[region].leading
			trailsAny = trailsAny or declared[region].trailing
		end
		local stripLanes = 1 + (if leadsAny then 1 else 0) + (if trailsAny then 1 else 0)
		local function stripEnd(use: ComposeTypes.Use): number
			local value = readPadding(base, use)
			local right: Types.Space? = if type(value) == "table" then value.right else value
			return math.max(kit.spacing(gap, use), kit.spacing(right, use, literalPadding))
		end
		local function landingFrame(name: string, alignment: Enum.HorizontalAlignment): Frame
			return Host.Frame(name)({
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 0,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Host.UIListLayout {
					SortOrder = E.SortOrder.LayoutOrder,
					HorizontalAlignment = alignment,
					Padding = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				},
			})
		end
		local landedZone: Frame? = nil
		local landedTrailing: Frame? = nil
		local landedLeading: Frame? = nil
		if #stripRegions > 0 then
			landedZone = landingFrame("Landed", E.HorizontalAlignment.Center)
			for _, region in stripRegions do
				if declared[region].trailing and landedTrailing == nil then
					landedTrailing = landingFrame("LandedTrailing", E.HorizontalAlignment.Right)
					members.topRight = members.topRight or {}
				end
				if declared[region].leading and landedLeading == nil then
					landedLeading = landingFrame("LandedLeading", E.HorizontalAlignment.Left)
					members.topLeft = members.topLeft or {}
				end
			end
		end
		local zones: { [string]: Frame } = {}
		local placed: { Frame } = {}
		local resting: resolver.Shift = { top = 0, bottom = 0, hang = 0, leanTop = 0, leanBottom = 0, lift = {} }
		local shift: ComposeTypes.Value<resolver.Shift> = Compose.cell(resting)
		local rows: ComposeTypes.Value<resolver.Rows> = Compose.cell({ top = 0, bottom = 0 })
		for zone, children in members do
			local cell = resolver.CELLS[zone]
			local frame = zoneFrame(
				string.upper(string.sub(zone, 1, 1)) .. string.sub(zone, 2),
				cell[1],
				cell[2],
				gap,
				if zone == "top" and landedZone
					then { landedZone, table.unpack(children) }
					elseif zone == "topRight" and landedTrailing then {
						landedTrailing,
						table.unpack(children),
					}
					elseif zone == "topLeft" and landedLeading then {
						landedLeading,
						table.unpack(children),
					}
					else children,
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
		local unfitDetails = Host.StringValue { Name = "FacetUnfitDetails", Value = "" }
		properties[#properties + 1] = unfitDetails
		local frames = ctx.config.services.RunService
		local preparing = frames ~= nil and frames.PreRender ~= nil and runtime.host.frames ~= nil
		local root = kit.plain(
			if preparing
				then ctx.fade((properties :: unknown) :: Types.CanvasGroupProps, false, false)
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
			preparation.begin(ctx, root)
			local roots: { GuiObject } = {}
			for _, region in regions do
				table.insert(roots, region)
			end
			local ready = presentationReadiness(ctx, roots)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(ready) then
					ctx.fadeTo(root, 0)
					preparation.finish(ctx, root)
				end
			end)
		end
		kit.underTopbar(root, under)
		kit.touchClearance(root, touch, touchAreas)
		do
			local host = ctx.observe.Parent(root)
			Compose.watch(function(use: ComposeTypes.Use)
				local parent = use(host)
				if parent == nil then
					hostClearance:set(0)
					return
				end
				local function read()
					local value = parent:GetAttribute("FacetTouchClearance")
					local list = parent:FindFirstChildWhichIsA("UIListLayout")
					local fromTop = list == nil or list.VerticalAlignment == E.VerticalAlignment.Top
					hostClearance:set(if fromTop and type(value) == "number" then value else 0)
				end
				local changed = parent:GetAttributeChangedSignal("FacetTouchClearance"):Connect(read)
				Compose.cleanup(function()
					changed:Disconnect()
				end)
				read()
			end)
		end
		do
			local owner = assert(Compose.currentOwner())
			local measuring: ComposeTypes.Owner? = nil
			local function measure()
				if ComposeTypes.owner.isDisposed(owner) then
					return
				end
				if measuring then
					ComposeTypes.owner.dispose(measuring)
					measuring = nil
				end
				local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
				if layer == nil or root.Parent == layer or not layer:IsA("GuiBase2d") then
					nested:set(nil)
					return
				end
				local scope = ComposeTypes.owner.createChild(owner)
				measuring = scope
				Compose.withOwner(scope, function()
					local position, size = ctx.observe.AbsolutePosition(root), ctx.observe.AbsoluteSize(root)
					local origin = ctx.observe.AbsolutePosition(layer :: GuiBase2d)
					local extent = ctx.observe.AbsoluteSize(layer :: GuiBase2d)
					local unit = ctx.layoutUnit(root)
					Compose.watch(function(use: ComposeTypes.Use)
						local margins = readOverscan(overscan, use)
						local at, box, start, bounds = use(position), use(size), use(origin), use(extent)
						if
							not (type(margins) == "table" or (margins == nil and distant(use)))
							or box.X <= 0
							or bounds.X <= 0
						then
							nested:set(nil)
							return
						end
						local scale = use(unit)
						local function remaining(
							name: "top" | "right" | "bottom" | "left",
							span: number,
							gap: number
						): number
							local fraction: number = FRACTION[name]
							local inset = if type(margins) == "table"
								then ((margins :: { [string]: number })[name] or 0) * scale
								else span * fraction
							return math.max(0, inset - gap) / scale
						end
						nested:set({
							top = remaining("top", bounds.Y, at.Y - start.Y),
							left = remaining("left", bounds.X, at.X - start.X),
							bottom = remaining("bottom", bounds.Y, start.Y + bounds.Y - at.Y - box.Y),
							right = remaining("right", bounds.X, start.X + bounds.X - at.X - box.X),
						})
					end)
				end)
			end
			runtime.connect(root, "AncestryChanged", measure)
			measure()
		end
		local riding: (ComposeTypes.Use) -> boolean = function()
			return false
		end
		local landed: ComposeTypes.Value<{ boolean }> = Compose.cell({})
		local stripGui: ScreenGui? = nil
		local topbarBand = if #stripRegions > 0 and ctx.config.guiService
			then ctx.observe.TopbarInset(ctx.config.guiService)
			else nil
		if #stripRegions > 0 then
			local screen = Compose.cell<<ScreenGui?>>(nil)
			local holder = Compose.cell<<Instance?>>(nil)
			local enabled = Compose.cell(true)
			local owner = assert(Compose.currentOwner())
			local chain: ComposeTypes.Owner? = nil
			local function locate()
				if ComposeTypes.owner.isDisposed(owner) then
					return
				end
				local host = root:FindFirstAncestorWhichIsA("ScreenGui")
				if not host then
					local surface = root:FindFirstAncestorWhichIsA("SurfaceGui")
					local source = if surface then ctx.overlayHosts[surface] else nil
					if source and source:IsA("ScreenGui") then
						host = source
					end
				end
				if chain then
					ComposeTypes.owner.dispose(chain)
				end
				local watching = ComposeTypes.owner.createChild(owner)
				chain = watching
				Compose.withOwner(watching, function()
					local sources: { ComposeTypes.ReadOnlyValue<boolean> } = {}
					local at: Instance? = root
					while at and not at:IsA("LayerCollector") do
						if at:IsA("GuiObject") then
							table.insert(sources, ctx.observe.Visible(at))
						end
						at = at.Parent
					end
					if host then
						table.insert(sources, ctx.observe.Enabled(host))
					end
					Compose.watch(function(use: ComposeTypes.Use)
						local shown = true
						for _, source in sources do
							if use(source) == false then
								shown = false
							end
						end
						enabled:set(shown)
					end)
				end)
				screen:set(host)
				holder:set(if host then host.Parent else nil)
			end
			runtime.connect(root, "AncestryChanged", locate)
			locate()
			local band = topbarBand
			riding = function(use: ComposeTypes.Use): boolean
				local rect: Rect? = if band then use(band) else nil
				return read(spec.topbar, use) ~= false and use(holder) ~= nil and rect ~= nil and rect.Width > 0
			end
			local function row(name: string, alignment: Enum.HorizontalAlignment, fields: Types.FrameProps): Frame
				fields.BackgroundTransparency = 1
				fields.BorderSizePixel = 0
				fields[#fields + 1] = Host.UIListLayout {
					FillDirection = E.FillDirection.Horizontal,
					SortOrder = E.SortOrder.LayoutOrder,
					HorizontalAlignment = alignment,
					VerticalAlignment = E.VerticalAlignment.Center,
					Padding = function(use: ComposeTypes.Use): UDim
						return D.new(0, kit.spacing(gap, use))
					end,
				}
				return Host.Frame(fields, name)
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
				Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill },
			})
			local trailingRow = row("Trailing", E.HorizontalAlignment.Right, {
				LayoutOrder = 3,
				Size = D2.new(),
				AutomaticSize = E.AutomaticSize.XY,
				Visible = trailsAny,
			})
			local topbarZone = row("Topbar", E.HorizontalAlignment.Left, {
				Size = D2.fromScale(1, 1),
				Host.UIPadding {
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
						return D.new(0, stripEnd(use))
					end,
				},
				leadingRow,
				middleRow,
				trailingRow,
			})
			for _, region in stripRegions do
				local home = if declared[region].leading
					then leadingRow
					elseif declared[region].trailing then trailingRow
					else middleRow
				local landing = if declared[region].trailing
					then assert(landedTrailing)
					elseif declared[region].leading then assert(landedLeading)
					else assert(landedZone)
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
					return if host then host.DisplayOrder - 1 else 0
				end,
				Enabled = enabled,
				Host.StyleLink {
					StyleSheet = function(use: ComposeTypes.Use): StyleSheet?
						local host = use(screen)
						local link = host and host:FindFirstChildWhichIsA("StyleLink")
						return if link then link.StyleSheet else nil
					end,
				},
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
		local safeSize = ctx.observe.AbsoluteSize(safe)
		local safeOrigin = ctx.observe.AbsolutePosition(safe)
		local rootOrigin = ctx.observe.AbsolutePosition(root)
		local zoneOffset = Compose.formula(function(use: ComposeTypes.Use): number
			return (use(safeOrigin).X - use(rootOrigin).X) / use(safeUnit)
		end)
		local touchControls = if ctx.config.guiService
			then runtime.observe(ctx.config.guiService, "TouchControlsEnabled")
			else nil
		local holding = gameplayHold.held(ctx)
		local actionZone = Compose.formula(function(use: ComposeTypes.Use): resolver.Zone
			local size = use(safeSize) / use(safeUnit)
			return if size.Y > size.X then "bottom" else "bottomRight"
		end)
		for _, region in actionRegions do
			runtime.decorate(region, {
				Parent = function(use: ComposeTypes.Use): Instance?
					return zones[use(actionZone)]
				end,
			})
		end
		for zone, own in members do
			local children = table.clone(own)
			if zone == "bottom" or zone == "bottomRight" then
				table.move(actionRegions, 1, #actionRegions, #children + 1, children)
			end
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
					if
						entry.reveal
						and use(entry.form) == 0
						and (entry.zone ~= "action" or use(actionZone) == zone)
					then
						table.insert(list, region)
					end
				end
				return list
			end)
			local lone = Compose.formula(function(use: ComposeTypes.Use): Frame?
				local list = use(dropped)
				local only = list[1]
				local entry = if #list == 1 and only then declared[only] else nil
				return if entry and (entry.label or entry.icon) then only else nil
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
			local across = if column ~= 2 then zones[MIDDLE[row]] else nil
			local acrossSize = if across then ctx.observe.AbsoluteSize(across) else nil
			local markSize = Compose.cell(V2.zero)
			local others: { { row: number, size: ComposeTypes.ReadOnlyValue<Vector2> } } = {}
			for name, place in resolver.CELLS do
				local other = zones[name]
				if across and other and name ~= "topbar" and place[1] == column and place[2] ~= row then
					table.insert(others, { row = place[2], size = ctx.observe.AbsoluteSize(other) })
				end
			end
			local function place(use: ComposeTypes.Use): (UDim2, Vector2)
				local unit, space = use(safeUnit), kit.spacing(gap, use)
				local size = use(zoneSize) / unit
				local moved = use(shift)
				local screen = use(safeSize) / unit
				local at = (screen - size) * anchor + V2.new(leaned(moved, column, row), lowered(moved, column, row))
				if column == 2 then
					return if row == 3
						then D2.fromOffset(at.X + size.X / 2, at.Y - space)
						else D2.fromOffset(at.X + size.X / 2, at.Y + size.Y + space),
						V2.new(0.5, if row == 3 then 1 else 0)
				end
				local x = if column == 1 then at.X + size.X + space else at.X - space
				local y, hold = at.Y + size.Y * (row - 1) / 2, (row - 1) / 2
				local mid = if acrossSize then use(acrossSize) / unit else V2.zero
				if mid.X > 0 and mid.Y > 0 then
					local side = floor(use)
					local wide = math.max(side, use(markSize).X / unit)
					local left = (screen.X - mid.X) / 2 + leaned(moved, 2, row)
					local top = (screen.Y - mid.Y) * (row - 1) / 2 + lowered(moved, 2, row)
					local reaches = if column == 1 then x + wide + space > left else x - wide - space < left + mid.X
					local head = y - hold * side
					if reaches and head < top + mid.Y + space and head + side + space > top then
						local low = if row == 1 then top + mid.Y + space else top - space - side
						local mine = if column == 1 then x else x - wide
						local free = low >= 0 and low + side <= screen.Y
						for _, other in others do
							local box = use(other.size) / unit
							local first = (screen.Y - box.Y) * (other.row - 1) / 2 + lowered(moved, column, other.row)
							local start = (screen.X - box.X) * (column - 1) / 2 + leaned(moved, column, other.row)
							if
								box.X > 0
								and box.Y > 0
								and low < first + box.Y + space
								and low + side + space > first
								and mine < start + box.X + space
								and mine + wide + space > start
							then
								free = false
							end
						end
						if free then
							y, hold = if row == 1 then low else low + side, if row == 1 then 0 else 1
						end
					end
				end
				return D2.fromOffset(x, y), V2.new(if column == 1 then 0 else 1, hold)
			end
			local build: (() -> ())? = Compose.bindOwner(function()
				runtime.mount(function()
					local marks: { { region: Frame, size: ComposeTypes.ReadOnlyValue<Vector2> } } = {}
					local parts: Types.TextButtonProps = {
						Text = "",
						BackgroundTransparency = 1,
						ZIndex = 5,
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
								Visible = function(use: ComposeTypes.Use): boolean
									return use(lone) == nil
								end,
								Host.UICorner { CornerRadius = ctx.round },
								ctx.icon("more", {
									AnchorPoint = V2.new(0.5, 0.5),
									Position = D2.fromScale(0.5, 0.5),
									Size = D2.fromOffset(16, 16),
								}),
							},
							"badge"
						),
					}
					for _, region in children do
						local entry = declared[region]
						if entry.reveal and (entry.label or entry.icon) then
							local named = Host.Frame("Mark" .. region.Name)({
								BackgroundTransparency = 1,
								AnchorPoint = V2.new(0.5, 0.5),
								Position = D2.fromScale(0.5, 0.5),
								Size = D2.new(),
								AutomaticSize = E.AutomaticSize.XY,
								Visible = function(use: ComposeTypes.Use): boolean
									return use(lone) == region
								end,
								mark("Mark", entry.label, entry.icon, region.Name),
							})
							parts[#parts + 1] = named
							table.insert(marks, { region = region, size = ctx.observe.AbsoluteSize(named) })
						end
					end
					parts.Size = function(use: ComposeTypes.Use): UDim2
						local side = floor(use)
						local wide = side
						local only = use(lone)
						for _, named in marks do
							if named.region == only then
								wide = math.max(wide, use(named.size).X / use(safeUnit))
							end
						end
						return D2.fromOffset(wide, side)
					end
					local trigger = Host.TextButton("ZoneReveal" .. frame.Name)(parts)
					local reach = ctx.observe.AbsoluteSize(trigger)
					Compose.watch(function(use: ComposeTypes.Use)
						markSize:set(use(reach))
					end)
					Compose.watch(function(use: ComposeTypes.Use)
						local names: { string } = {}
						if use(lone) == nil then
							for _, region in use(dropped) do
								local entry = declared[region]
								if not (entry.label or entry.icon) then
									table.insert(names, region.Name)
								end
							end
						end
						trigger:SetAttribute("FacetReveal", if #names > 0 then table.concat(names, ", ") else nil)
					end)
					return UI.Popover("Hidden" .. frame.Name)({
						isPresented = open,
						onPresentedChange = function(value: boolean)
							open:set(value and #dropped:peek() > 0)
						end,
						compact = "popover",
						closeButton = false,
						edge = if column == 2 and row == 3 then "top" else EXPAND_EDGE[column],
						content = function(): Instance
							release()
							local slots: Types.FrameProps = {
								Name = "ZoneHidden",
								BackgroundTransparency = 1,
								Size = D2.new(),
								AutomaticSize = E.AutomaticSize.XY,
								Host.UIListLayout {
									SortOrder = E.SortOrder.LayoutOrder,
									Padding = function(use: ComposeTypes.Use): UDim
										return D.new(0, kit.spacing(gap, use))
									end,
								},
							}
							local slotFrames = {}
							for index, region in dropped:peek() do
								local title = declared[region].label
								local slot = Host.Frame("Hidden" .. region.Name)({
									LayoutOrder = index,
									BackgroundTransparency = 1,
									Size = D2.new(),
									AutomaticSize = E.AutomaticSize.XY,
									if title then Host.UIListLayout { SortOrder = E.SortOrder.LayoutOrder } else nil,
									if title
										then UI.Text "Label" { text = title, textRole = "caption", LayoutOrder = -1 }
										else nil,
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
						trigger = trigger,
					})
				end, safe)
			end)
			local eager = false
			for _, region in children do
				eager = eager or (declared[region].mayDrop and declared[region].reveal ~= nil)
			end
			Compose.watch(function(use: ComposeTypes.Use)
				local make = build
				if make and (eager or #use(dropped) > 0) then
					build = nil
					make()
				end
			end)
		end
		local resolutions: { [string]: Resolution } = {}
		local resolutionCount = 0
		local function resolved(
			width: number,
			height: number,
			spacing: number,
			list: { resolver.Declared },
			listKey: string,
			band: resolver.Strip?,
			areas: { resolver.Area }?,
			holds: { boolean }?
		): Resolution
			local reserved: { string } = {}
			for _, area in areas or {} do
				table.insert(reserved, `{area.left}:{area.right}:{area.reach}`)
			end
			local key =
				`{width},{height},{spacing},{if band then `{band.x},{band.y},{band.lanes}` else "-"}|{table.concat(
					reserved,
					";"
				)}|{listKey}|{holds ~= nil}`
			local known = resolutions[key]
			if known then
				return known
			end
			local chosen, down, moved, overflow, packed, colliding =
				resolver.resolve(width, height, spacing, list, band, nil, nil, areas)
			local trial = list
			local order: { number } = {}
			local function hide(index: number)
				trial = table.clone(trial)
				local hidden = table.clone(trial[index])
				hidden.sizes = {}
				trial[index] = hidden
			end
			for _ = 1, if holds then #list else 0 do
				local pick: number? = nil
				local worst = -math.huge
				for _, index in colliding do
					local rank = trial[index].rank
					if holds and holds[index] and not table.find(order, index) and rank >= worst then
						pick, worst = index, rank
					end
				end
				if pick == nil then
					break
				end
				table.insert(order, pick)
				hide(pick)
				chosen, down, moved, overflow, packed, colliding =
					resolver.resolve(width, height, spacing, trial, band, nil, nil, areas)
			end
			for at = #order - 1, 1, -1 do
				local index = order[at]
				local before = trial
				trial = table.clone(trial)
				trial[index] = list[index]
				local again, low, shift, missed, rows, hits =
					resolver.resolve(width, height, spacing, trial, band, nil, nil, areas)
				if #hits <= #colliding and not table.find(hits, index) then
					chosen, down, moved, overflow, packed, colliding = again, low, shift, missed, rows, hits
					table.remove(order, at)
				else
					trial = before
				end
			end
			if #order > 0 then
				overflow = table.clone(overflow)
				for _, index in order do
					chosen[index] = 0
					if not table.find(overflow, index) then
						table.insert(overflow, index)
					end
				end
				table.sort(overflow)
			end
			local made: Resolution =
				{ chosen = chosen, down = down, moved = moved, overflow = overflow, packed = packed }
			if resolutionCount >= RESOLUTIONS then
				table.clear(resolutions)
				resolutionCount = 0
			end
			resolutions[key] = made
			resolutionCount += 1
			return made
		end
		local warned: { [Frame]: boolean } = {}
		local overflowing: { [Frame]: boolean } = {}
		local streaks: { [Frame]: number } = {}
		local later = runtime.scheduler()
		local last: Vector2? = nil
		local placement = Compose.cell<<{ string }>>({}, function(a: { string }, b: { string }): boolean
			local same = #a == #b
			for index, zone in a do
				same = same and zone == b[index]
			end
			return same
		end)
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
			local extent = use(safeSize) / use(safeUnit)
			local rides = riding(use)
			local list: { resolver.Declared } = {}
			for index, region in regions do
				local entry = declared[region]
				local measured, hangs, hanging = {}, {}, false
				for form, observed in entry.sizes do
					local value = use(observed)
					measured[form] = { x = value.X, y = value.Y }
					hangs[form] = use(entry.hangs[form])
					hanging = hanging or hangs[form] > 0
				end
				list[index] = {
					zone = if entry.zone == "action" then use(actionZone) else entry.zone,
					rank = entry.rank,
					mayDrop = entry.mayDrop,
					sizes = measured,
					hangs = if hanging and read(entry.authored, use) ~= false then hangs else nil,
					leading = entry.leading,
					trailing = entry.trailing,
				}
			end
			local strip = if stripSize and rides then use(stripSize) else nil
			if strip and (strip.X <= 0 or strip.Y <= 0) and topbarBand and stripUnit then
				local inset = use(topbarBand)
				strip = V2.new(inset.Width, inset.Height) / use(stripUnit)
			end
			local band: resolver.Strip? = if strip
				then {
					x = strip.X - kit.spacing(gap, use) - stripEnd(use),
					y = math.min(strip.Y - ENGINE_MARGIN, ENGINE_BUTTON),
					lanes = stripLanes,
				}
				else nil
			local spacing = kit.spacing(gap, use)
			local listKey = regionsKey(list)
			local holds: { boolean } = {}
			for index, region in regions do
				holds[index] = declared[region].reveal ~= nil and declared[region].zone ~= "topbar"
			end
			local offset = use(zoneOffset)
			local areas: { resolver.Area } = {}
			for _, area in use(touchAreas) do
				table.insert(areas, { left = area.left - offset, right = area.right - offset, reach = area.reach })
			end
			local result = resolved(
				extent.X,
				extent.Y,
				spacing,
				list,
				listKey,
				if band and strip and strip.X > 0 then band else nil,
				areas,
				holds
			)
			local chosen, down, moved, overflow, packed =
				result.chosen, result.down, result.moved, result.overflow, result.packed
			local unfit: { string } = {}
			local function misfits(width: number, missed: { number }): { string }
				local names: { string } = {}
				for _, index in missed do
					table.insert(names, regions[index].Name)
				end
				for index, region in regions do
					local entry = declared[region]
					local full = list[index].sizes[1]
					local opens = entry.reveals and (entry.mayDrop or #entry.contents > 1)
					if opens and full and full.x > width and not table.find(names, region.Name) then
						table.insert(names, region.Name)
					end
				end
				return names
			end
			local here = misfits(extent.X, overflow)
			if #here > 0 then
				table.insert(unfit, `{math.floor(extent.X)} by {math.floor(extent.Y)} now: {table.concat(here, ", ")}`)
			end
			for _, phone in if distant(use) then {} else PHONES do
				if extent.X > phone.X or extent.Y > phone.Y then
					local observed = touchControls
					local shown = if observed then use(observed) ~= false or use(holding) else true
					local controls = if shown then phoneControls(phone) else nil
					local missed = resolved(phone.X, phone.Y, spacing, list, listKey, nil, controls).overflow
					local names = misfits(phone.X, missed)
					if #names > 0 then
						table.insert(
							unfit,
							`{math.floor(phone.X)} by {math.floor(phone.Y)}: {table.concat(names, ", ")}`
						)
					end
				end
			end
			local verdict = if #unfit > 0 then table.concat(unfit, "; ") else nil
			unfitDetails.Value = verdict or ""
			local failed = if verdict ~= nil then true else nil
			if root:GetAttribute("FacetUnfit") ~= failed then
				root:SetAttribute("FacetUnfit", failed)
			end
			local before = landed:peek()
			local same = #before == #down
			for index, value in down do
				same = same and before[index] == value
			end
			if not same then
				landed:set(down)
			end
			local stacked = if moved.top > 0 then true else nil
			if root:GetAttribute("FacetTopStacked") ~= stacked then
				root:SetAttribute("FacetTopStacked", stacked)
			end
			local was = shift:peek()
			if
				was.top ~= moved.top
				or was.bottom ~= moved.bottom
				or was.hang ~= moved.hang
				or was.leanTop ~= moved.leanTop
				or was.leanBottom ~= moved.leanBottom
				or not sameLift(was.lift, moved.lift)
			then
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
							local size = safeSize:peek() / safeUnit:peek()
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
				if zone == "topbar" and (down[index] or not stripped) then
					return if list[index].trailing then "topRight" else "top"
				end
				return zone
			end
			local filled: { [string]: boolean } = {}
			local empty: { [number]: boolean } = {}
			local occupied: { string } = {}
			for index, entry in list do
				local size = if chosen[index] > 0 then entry.sizes[chosen[index]] else nil
				occupied[index] = ""
				if size and (size.x <= 0 or size.y <= 0) then
					empty[index] = true
				elseif size then
					local home = placed(index)
					filled[home] = true
					if extent.X > 0 and extent.Y > 0 and not (entry.zone == "topbar" and rides and not down[index]) then
						occupied[index] = home
					end
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
						if #line < 2 then
							table.clear(line)
							return
						end
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
						table.sort(members, function(a: unknown, b: unknown): boolean
							return natural[a] > natural[b]
						end)
						local matched: { [unknown]: boolean } = {}
						local done = settling >= SETTLE_PASSES
						local steps = stepping and not done
						if steps then
							done = true
						end
						local at = 1
						while at <= #members do
							local lead = natural[members[at]]
							local group: { unknown } = {}
							while at <= #members and natural[members[at]] >= lead * SIMILAR_ROW do
								table.insert(group, members[at])
								at += 1
							end
							if #group < 2 then
								continue
							end
							for _, key in group do
								matched[key] = true
							end
							if steps then
								local mins, settled = extentMatch.step(
									heights,
									group,
									measured,
									natural,
									if kit.frameless() then 0 else nil
								)
								for _, key in group do
									lastMins[key] = mins[key]
								end
								done = done and settled
							end
						end
						unsettled = unsettled or not done
						for _, index in line do
							local region = regions[index]
							if not matched[region] then
								extentMatch.forget(heights, region)
								lastMins[region] = nil
								lifts[index] = 0
								continue
							end
							local floor = declared[region].floors[chosen[index]]
							if floor and not floor() and declared[region].lift:peek() > 0 then
								extentMatch.forget(heights, region)
							end
							lifts[index] = lastMins[region] or 0
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
			placement:set(occupied)
		end)
		local ancestry = Compose.cell(0)
		local function moved()
			ancestry:set(ancestry:peek() + 1)
		end
		runtime.connect(root, "AncestryChanged", moved)
		local shown = ctx.observe.Visible(root)
		local regionShown: { ComposeTypes.ReadOnlyValue<unknown> } = {}
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
			local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
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
			if layer.Enabled and use(shown) ~= false then
				for index, zone in now do
					if zone ~= "" and use(regionShown[index]) ~= false then
						held[zone] = true
					end
				end
			end
			local changed = reservations.setZones(layer, root, held, ctx.config.compositionScope)
				or layer.Parent ~= claimedParent
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
		assert(spec.passive == nil or type(spec.passive) == "boolean", "Facet Composition passive must be a boolean")
		if spec.passive ~= false then
			local options: Types.ResponderOptions =
				{ passive = true, gameplayGuard = false, engageOnPress = false, resignOnActivate = true }
			ctx.responder(root, options)
			if stripGui then
				ctx.responder(stripGui, options)
			end
		end
		return root
	end)
end
