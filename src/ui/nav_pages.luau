--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local Media = require("./media_types")
local Content = require("./content_types")
local ComposeTypes = require("../vendor/compose/core")
local reducedMotion = require("./motion")

type Controls = {
	TabView: Types.Constructor<Nav.TabViewSpec, Frame>,
	NavigationStack: Nav.NavigationStackConstructor,
	PageView: Types.Constructor<Nav.PageViewSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
	Menu: Nav.MenuConstructor,
	Picker: Nav.PickerConstructor,
	StatusIndicator: Types.Constructor<Media.StatusIndicatorProps, TextLabel>,
	badged: Content.Badged,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local tabDepth = 0
	local navigationDepth = 0
	local TAB_FADE: Nav.Transition = { seconds = 0.2, ease = Compose.easing.outQuad }
	local PUSH_SPRING = { period = 0.3, damping = 1, tolerance = 1e-3 }
	local PARALLAX = 0.3
	local DIM = 0.1
	local function content<P>(
		builder: Instance | ((Nav.NavigationEntry<P>?) -> Instance),
		entry: Nav.NavigationEntry<P>?
	): Instance
		return if type(builder) == "function" then builder(entry) else builder
	end
	local function checkTransition(transition: Nav.Transition | false?): ()
		if transition == nil or transition == false then
			return
		end
		assert(type(transition) == "table", "Navigation transition uses Compose tween options")
		for key in transition do
			assert(key == "seconds" or key == "ease", "Navigation transition uses Compose tween options: seconds, ease")
		end
	end
	local function layer(
		properties: Types.CanvasGroupNativeProps & Types.FrameNativeProps,
		state: ComposeTypes.Readable<ComposeTypes.LayerStackState>,
		transition: Nav.Transition | false?,
		hidden: (() -> ())?,
		immediate: boolean?
	): GuiObject
		if transition == nil or transition == false then
			local node = Host.Frame(properties)
			if hidden then
				Compose.watch(function(use: ComposeTypes.Use)
					if not use(state).top then
						hidden()
					end
				end)
			end
			return node
		end
		checkTransition(transition)
		local mounted = Compose.cell(false)
		local gui = surfaces.service("GuiService")
		local reduced = if gui then ctx.observe.ReducedMotionEnabled(gui) else Compose.cell(false)
		local opacity = runtime.tween(function(use: ComposeTypes.Use)
			return if (immediate or use(mounted)) and use(state).top then 1 else 0
		end, transition)
		local function still(use: ComposeTypes.Use): boolean
			return use(reduced) or read(ctx.config.reducedMotion, use) == true
		end
		properties.GroupTransparency = function(use: ComposeTypes.Use)
			return if still(use) then 0 else 1 - use(opacity)
		end
		properties.Visible = function(use: ComposeTypes.Use)
			return use(state).top or not still(use) and use(opacity) > 0
		end
		properties.Interactable = function(use: ComposeTypes.Use)
			return use(state).top
		end
		local panel = Host.CanvasGroup(properties)
		local parent = ctx.observe.Parent(panel)
		Compose.watch(function(use: ComposeTypes.Use)
			mounted:set(use(parent) ~= nil)
		end)
		if hidden then
			Compose.watch(function(use: ComposeTypes.Use)
				if not use(state).top and (use(reduced) or use(opacity) == 0) then
					hidden()
				end
			end)
		end
		return panel
	end

	local function checkedSelection(
		selection: ComposeTypes.Cell<string>,
		entries: { Nav.Tab },
		label: string
	): { [string]: Nav.Tab }
		assert(selection and selection.set, label .. ".selection requires a writable Compose cell")
		assert(type(entries) == "table" and #entries > 0, label .. " requires entries")
		local byId: { [string]: Nav.Tab } = {}
		for _, entry in entries do
			assert(type(entry.id) == "string" and byId[entry.id] == nil, label .. " entries require unique string ids")
			byId[entry.id] = entry
		end
		assert(byId[selection:peek()], label .. ".selection must name an entry")
		return byId
	end

	UI.TabView = ctx.construct("TabView", function(spec: Nav.TabViewSpec): Frame
		assert(
			spec.retention == nil or spec.retention == "all" or spec.retention == "top",
			"TabView.retention uses Compose all or top"
		)
		local depth = tabDepth
		local nested = Compose.cell(depth > 0)
		local statuses: { [string]: boolean } =
			{ neutral = true, info = true, success = true, warning = true, error = true, accent = true }
		local forms: { [string]: boolean } = { dot = true, ring = true, square = true, dash = true }
		for _, tab in read(spec.tabs) do
			local indicator = tab.indicator
			if indicator ~= nil then
				assert(
					type(indicator) == "table",
					"Facet UI.TabView: tab.indicator must be a StatusIndicator spec table { form?, status?, count?, max? }"
				)
				assert(
					indicator.status == nil or statuses[indicator.status],
					"Facet UI.TabView: tab.indicator.status must be neutral, info, success, warning, error or accent"
				)
				assert(
					indicator.form == nil or forms[indicator.form],
					"Facet UI.TabView: tab.indicator.form must be dot, ring, square or dash"
				)
			end
		end
		local fit = spec.textSize == nil or spec.textSize == "fit"
		assert(
			spec.style == nil or table.find({ "automatic", "sidebarAdaptable", "collapsible" }, spec.style),
			"Invalid TabView.style"
		)
		local sectionLabels: { [string]: string } = {}
		for _, section in (spec.sections or {} :: { { id: string, label: string } }) do
			assert(
				type(section.id) == "string" and type(section.label) == "string" and sectionLabels[section.id] == nil,
				"TabView sections require unique ids and labels"
			)
			sectionLabels[section.id] = section.label
		end
		local byId = checkedSelection(spec.selection, read(spec.tabs), "TabView")
		local tabMap = Compose.formula(function(use: ComposeTypes.Use)
			local result: { [string]: Nav.Tab } = {}
			for _, tab in read(spec.tabs, use) do
				assert(type(tab.id) == "string" and result[tab.id] == nil, "TabView tabs require unique string ids")
				assert(
					tab.section == nil or sectionLabels[tab.section] ~= nil,
					"TabView tab.section must name a declared section"
				)
				result[tab.id] = tab
			end
			return result
		end)
		local root = Host.Frame(ctx.props(spec, {
			"selection",
			"tabs",
			"sections",
			"customization",
			"accessories",
			"railWidth",
			"transition",
			"retention",
			"placement",
			"style",
			"sidebarPreference",
			"restoreScroll",
			"shoulderNavigation",
			"restoreFocus",
			"indicator",
			"iconOnly",
			"textSize",
			"enabled",
			"onChange",
			"controlSize",
		}, { Name = "TabView", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) }))
		local dimensions = ctx.observe.AbsoluteSize(root)
		local function locate()
			local at: Instance? = root.Parent
			local inside = depth > 0
			while at and not inside do
				inside = at:GetAttribute("FacetTabPage") == true
				at = at.Parent
			end
			if nested:peek() ~= inside then
				nested:set(inside)
			end
		end
		runtime.connect(root, "AncestryChanged", locate)
		locate()
		local input = surfaces.service("UserInputService")
		local primaryInput = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		local function resolvePlacement(use: ComposeTypes.Use): Nav.Placement
			if spec.style == "collapsible" then
				return "topBar"
			end
			local explicit = read(spec.placement, use)
			if explicit and explicit ~= "automatic" then
				return explicit
			end
			if use(nested) then
				return "topBar"
			end
			local size = use(dimensions)
			if use(primaryInput) == E.PreferredInput.Gamepad then
				return "topBar"
			end
			if size.X >= 960 or (spec.style == "sidebarAdaptable" and size.X >= 720) then
				local preferred = read(spec.sidebarPreference, use)
				return if preferred and preferred ~= "automatic" then preferred else "sidebar"
			end
			return if size.Y > 0 and size.X / size.Y > 1.4 then "bottomBarCompact" else "bottomBar"
		end
		local placement = Compose.formula(resolvePlacement)
		local function railWidth(use: ComposeTypes.Use): number
			return read(spec.railWidth, use) or math.clamp(math.floor(use(dimensions).X * 0.2), 200, 280)
		end

		local COMPACT_HEIGHT = 480
		local collapsed = Compose.formula(function(use: ComposeTypes.Use): boolean
			if spec.style == "collapsible" then
				return true
			end
			if not use(nested) or (spec.style ~= nil and spec.style ~= "automatic") then
				return false
			end
			local explicit = read(spec.placement, use)
			if explicit and explicit ~= "automatic" then
				return false
			end
			local size = use(dimensions)
			return size.Y > 0 and size.Y < COMPACT_HEIGHT
		end)
		local headHeight, footHeight, trailingWidth, aboveHeight =
			Compose.cell(0), Compose.cell(0), Compose.cell(0), Compose.cell(0)
		local visibleTabs = Compose.formula(function(use: ComposeTypes.Use)
			local customized = read(spec.customization, use)
			local byId = use(tabMap)
			if not customized then
				return read(spec.tabs, use)
			end
			local ordered: { Nav.Tab } = {}
			local added: { [string]: boolean } = {}
			local hidden: { [string]: boolean } = {}
			for _, id in (customized.hidden or {} :: { string }) do
				hidden[id] = true
			end
			for _, id in (customized.order or {} :: { string }) do
				local tab = byId[id]
				if tab and not added[id] and (not hidden[id] or tab.required) then
					table.insert(ordered, tab)
					added[id] = true
				end
			end
			for _, tab in read(spec.tabs, use) do
				if not added[tab.id] and (not hidden[tab.id] or tab.required) then
					table.insert(ordered, tab)
				end
			end
			assert(#ordered > 0, "TabView customization must leave a visible tab")
			return ordered
		end)
		local visited = Compose.cell({} :: { string })
		local tabsReady = false
		local panels: { [string]: GuiObject } = {}
		local bookmarks: { [string]: GuiObject? } = {}
		local bookmarkPaths: { [string]: { string } } = {}
		local tabButtons: { [string]: TextButton } = {}
		local tabMeasures: { [string]: { position: ComposeTypes.Readable<Vector2>, size: ComposeTypes.Readable<Vector2> } } =
			{}
		local gui = surfaces.service("GuiService")
		local selectedObject = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local previous: string?
		local handoff: string?
		Compose.watch(function(use: ComposeTypes.Use)
			local id = use(spec.selection)
			byId = use(tabMap)
			local allowed = false
			for _, tab in use(visibleTabs) do
				if tab.id == id then
					allowed = true
					break
				end
			end
			if not allowed then
				spec.selection:set(use(visibleTabs)[1].id)
				return
			end
			local retained = {}
			for _, old in visited:peek() do
				if byId[old] then
					table.insert(retained, old)
				end
			end
			if #retained ~= #visited:peek() then
				visited:set(retained)
			end
			if previous == id then
				return
			end
			local leaving = false
			local previousPanel = if previous then panels[previous] else nil
			if gui and previousPanel and surfaces.within(gui.SelectedObject, previousPanel) then
				leaving = true
				bookmarks[previous :: string] = gui.SelectedObject
			end
			local order = table.clone(visited:peek())
			local at = table.find(order, id)
			if at then
				table.remove(order, at)
			end
			table.insert(order, id)
			visited:set(order)
			local bookmark = bookmarks[id]
			handoff = if spec.restoreFocus ~= false
					and gui
					and (leaving or (bookmark and bookmark.Parent))
				then id
				else nil
			if spec.restoreScroll == false and panels[id] then
				local function reset(node: Instance): ()
					if node:IsA("ScrollingFrame") then
						node.CanvasPosition = V2.zero
					end
					for _, child in node:GetChildren() do
						reset(child)
					end
				end
				reset(panels[id])
			end
			previous = id
		end)
		local function tabEnabled(id: string, use: ComposeTypes.Use?): boolean
			local tab = read(tabMap, use)[id]
			return tab ~= nil and read(tab.enabled, use) ~= false
		end
		local function select(id: string): ()
			if read(spec.enabled) == false or id == spec.selection:peek() or not tabEnabled(id) then
				return
			end
			spec.selection:set(id)
			if spec.onChange then
				spec.onChange(id)
			end
		end
		local wordWidths: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local barExtent: ComposeTypes.Cell<Vector2> = Compose.cell(V2.zero)
		local crowded = Compose.formula(function(use: ComposeTypes.Use): boolean
			if not fit or string.find(use(placement), "bottom") == nil then
				return false
			end
			local extent = use(barExtent).X
			if extent <= 0 then
				return false
			end
			local count = math.max(1, #use(visibleTabs))
			local available = extent / count - 4 - 2 * ctx.controlSize(nil, "paddingX", use)
			local scale = ctx.metric("typography.caption.size", use) / ctx.metric("typography.control.size", use)
			for _, width in use(wordWidths) do
				if width * scale > available + 0.5 then
					return true
				end
			end
			return false
		end)
		local function tabHeight(use: ComposeTypes.Use?): number
			return if spec.controlSize == nil then 44 else ctx.controlSize(spec.controlSize, "height", use)
		end
		local bar = Host.ScrollingFrame "Tabs" {
			ZIndex = 2,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar" then E.AutomaticSize.Y else E.AutomaticSize.X
			end,
			ScrollingDirection = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar" then E.ScrollingDirection.Y else E.ScrollingDirection.X
			end,
			Size = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar"
					then D2.new(0, railWidth(use) - 16, 1, -use(headHeight) - use(footHeight))
					else D2.new(1, -use(trailingWidth), 0, 44)
			end,
			Position = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar"
					then D2.fromOffset(8, use(headHeight))
					elseif string.find(use(placement), "bottom") then D2.new(0, 0, 1, -44)
					else D2.fromOffset(0, 0)
			end,
			Host.UIListLayout({
				FillDirection = function(use: ComposeTypes.Use)
					return if use(placement) == "sidebar" then E.FillDirection.Vertical else E.FillDirection.Horizontal
				end,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = function(use: ComposeTypes.Use)
					return if use(placement) == "sidebar" then E.VerticalAlignment.Top else E.VerticalAlignment.Center
				end,
				Padding = D.new(0, 4),
			}) :: Types.Child,
			Compose.keyed({
				from = visibleTabs,
				key = function(tab: Nav.Tab): string
					return tab.id
				end,
				render = function(
					current: ComposeTypes.Readable<Nav.Tab>,
					index: ComposeTypes.Readable<number>
				): Instance
					local tab = current:peek()
					local button = UI.Button({
						Name = tab.id,
						controlSize = spec.controlSize,
						label = function(use: ComposeTypes.Use)
							local tab = use(current)
							if read(spec.iconOnly, use) then
								return ""
							end
							local badge = if tab.icon then nil else read(tab.badge, use)
							return tostring(read(tab.label, use) or tab.id)
								.. (if badge ~= nil and badge ~= "" then " (" .. tostring(badge) .. ")" else "")
						end,
						icon = tab.icon,
						TextSize = if fit then nil else (spec.textSize :: unknown) :: Types.Value<number>,
						LayoutOrder = index,
						Size = function(use: ComposeTypes.Use)
							local place = use(placement)
							local height = tabHeight(use)
							if fit and string.find(place, "bottom") ~= nil and not use(crowded) then
								return D2.new(1 / math.max(1, #use(visibleTabs)), -4, 0, height)
							end
							return if place == "sidebar" then D2.new(1, 0, 0, height) else D2.fromOffset(0, height)
						end,
						AutomaticSize = function(use: ComposeTypes.Use)
							local place = use(placement)
							return if place == "sidebar"
									or (fit and string.find(place, "bottom") ~= nil and not use(crowded))
								then E.AutomaticSize.None
								else E.AutomaticSize.X
						end,
						TextXAlignment = function(use: ComposeTypes.Use)
							return if use(placement) == "sidebar"
								then E.TextXAlignment.Left
								else E.TextXAlignment.Center
						end,
						TextTruncate = E.TextTruncate.AtEnd,
						enabled = function(use: ComposeTypes.Use): boolean
							return read(spec.enabled, use) ~= false and read(use(current).enabled, use) ~= false
						end,
						selected = function(use: ComposeTypes.Use)
							return use(spec.selection) == tab.id and read(spec.indicator, use) == "pill"
						end,
						onActivate = function()
							select(tab.id)
						end,
					})
					button:AddTag("facet-tab-item")
					if fit then
						local measure = ctx.text({
							Name = "LabelMeasure",
							Visible = false,
							TextWrapped = false,
							Text = function(use: ComposeTypes.Use): string
								return tostring(read(use(current).label, use) or tab.id)
							end,
							TextSize = function(use: ComposeTypes.Use): number
								return (ctx.metric("typography.control.size", use))
							end,
						})
						surfaces.attach(button, { measure :: Types.Child })
						local natural = ctx.observe.TextBounds(measure)
						local room = ctx.observe.AbsoluteSize(button)
						Compose.watch(function(use: ComposeTypes.Use)
							local width = use(natural).X
							local widths = table.clone(wordWidths:peek())
							widths[tab.id] = width
							wordWidths:set(widths)
						end)
						Compose.cleanup(function()
							local widths = table.clone(wordWidths:peek())
							widths[tab.id] = nil
							wordWidths:set(widths)
						end)
						local target = Compose.formula(function(use: ComposeTypes.Use): number?
							local width = use(natural).X
							local available = use(room).X - 2 * ctx.controlSize(nil, "paddingX", use)
							if
								string.find(use(placement), "bottom") == nil
								or use(crowded)
								or width <= 0
								or available <= 0
							then
								return nil
							end
							local largest = ctx.metric("typography.control.size", use)
							local smallest = ctx.metric("typography.caption.size", use)
							return math.clamp(math.floor(largest * available / width), smallest, largest)
						end)
						local drop = Compose.cell(0)
						Compose.watch(function(use: ComposeTypes.Use)
							use(target)
							drop:set(0)
						end)
						Compose.watch(function(use: ComposeTypes.Use)
							local size = use(target)
							if size == nil then
								button:ResetPropertyToDefault("TextSize")
								return
							end
							local smallest = ctx.metric("typography.caption.size", use)
							button.TextSize = math.max(smallest, size - use(drop))
						end)
						local fits, drawn = ctx.observe.TextFits(button), ctx.observe.TextBounds(button)
						Compose.watch(function(use: ComposeTypes.Use)
							local whole, bounds = use(fits), use(drawn)
							local smallest = ctx.metric("typography.caption.size", use)
							if not whole and bounds.X > 0 and target:peek() ~= nil and button.TextSize > smallest then
								drop:set(drop:peek() + 1)
							end
						end)
						button:SetAttribute("FacetTextFit", true)
					end
					local glyph = button:FindFirstChild("LeadingIcon", true)
					if tab.icon and tab.badge ~= nil and glyph then
						local corner = UI.badged(
							Host.Frame({ Name = "Anchor", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) }),
							function(use: ComposeTypes.Use): string?
								local badge = read(use(current).badge, use)
								return if badge == nil then nil else tostring(badge)
							end
						)
						runtime.decorate(corner, { Size = D2.fromScale(1, 1), AutomaticSize = E.AutomaticSize.None })
						runtime.mount(function()
							return corner
						end, glyph)
					end
					local indicator = tab.indicator
					if indicator then
						surfaces.attach(button, {
							UI.StatusIndicator({
								Name = "Status",
								status = indicator.status,
								form = indicator.form,
								count = indicator.count,
								max = indicator.max,
								AnchorPoint = V2.new(1, 0),
								Position = D2.new(1, -4, 0, 4),
								ZIndex = 3,
							}) :: Types.Child,
						})
					end
					Compose.watch(function(use: ComposeTypes.Use)
						local current = use(spec.selection) == tab.id
						local place = use(placement)
						local filled = current
							and read(spec.indicator, use) ~= "none"
							and (place == "sidebar" or string.find(place, "bottom") ~= nil)
						local tags: { [string]: boolean } =
							{ ["facet-tab-current"] = current, ["facet-tab-filled"] = filled }
						for name, active in tags do
							if active then
								button:AddTag(name)
							elseif button:HasTag(name) then
								button:RemoveTag(name)
							end
						end
					end)
					surfaces.attach(button, {
						Host.UISizeConstraint({
							MinSize = function(use: ComposeTypes.Use)
								return V2.new(44, tabHeight(use))
							end,
						}),
						Compose.show(function(use: ComposeTypes.Use)
							return use(spec.selection) == tab.id
								and read(spec.indicator, use) ~= "none"
								and read(spec.indicator, use) ~= "pill"
								and use(placement) == "topBar"
						end, function()
							return ctx.styled(
								Host.Frame "SelectionIndicator" {
									Size = D2.new(1, 0, 0, 2),
									Position = D2.new(0, 0, 1, -2),
									BorderSizePixel = 0,
								},
								"selection-indicator"
							)
						end),
					})
					Compose.watch(function(use: ComposeTypes.Use)
						button:SetAttribute("FacetLabel", read(use(current).label, use) or tab.id)
					end)
					tabButtons[tab.id] = button
					tabMeasures[tab.id] = {
						position = ctx.observe.AbsolutePosition(button),
						size = ctx.observe.AbsoluteSize(button),
					}
					Compose.cleanup(function()
						tabButtons[tab.id], tabMeasures[tab.id] = nil, nil
					end)
					if next(sectionLabels) then
						return ctx.column({
							Compose.show(function(use: ComposeTypes.Use)
								local at = use(index)
								local tabs = use(visibleTabs)
								return use(placement) == "sidebar"
									and use(current).section ~= nil
									and (at == 1 or tabs[at - 1].section ~= use(current).section)
							end, function()
								return ctx.text({
									Name = "Section",
									Text = function(use: ComposeTypes.Use)
										return sectionLabels[assert(use(current).section)]
									end,
									Size = D2.new(1, 0, 0, 28),
									AutomaticSize = E.AutomaticSize.None,
								})
							end),
							button,
						}, {
							Name = "TabRow-" .. tab.id,
							LayoutOrder = index,
							Size = function(use: ComposeTypes.Use)
								return if use(placement) == "sidebar" then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 44)
							end,
							AutomaticSize = function(use: ComposeTypes.Use)
								return if use(placement) == "sidebar" then E.AutomaticSize.Y else E.AutomaticSize.X
							end,
						})
					end
					return button
				end,
			}),
		}
		Compose.watch(function(use: ComposeTypes.Use)
			bar:SetAttribute("FacetEntry", use(spec.selection))
		end)
		local barSize, barPosition = ctx.observe.AbsoluteSize(bar), ctx.observe.AbsolutePosition(bar)
		Compose.watch(function(use: ComposeTypes.Use)
			barExtent:set(use(barSize))
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local selected = use(spec.selection)
			local measure = tabMeasures[selected]
			if not measure then
				return
			end
			local extent, origin, at, size = use(barSize), use(barPosition), use(measure.position), use(measure.size)
			local vertical = use(placement) == "sidebar"
			local start = if vertical then at.Y - origin.Y else at.X - origin.X
			local length = if vertical then size.Y else size.X
			local visible = if vertical then extent.Y else extent.X
			if visible <= 0 then
				return
			end
			local delta = if start < 0 then start elseif start + length > visible then start + length - visible else 0
			if delta ~= 0 then
				bar.CanvasPosition = if vertical
					then V2.new(bar.CanvasPosition.X, math.max(0, bar.CanvasPosition.Y + delta))
					else V2.new(math.max(0, bar.CanvasPosition.X + delta), bar.CanvasPosition.Y)
			end
		end)
		local layers = Host.Frame "Content" {
			BackgroundTransparency = 1,

			ClipsDescendants = true,
			Position = function(use: ComposeTypes.Use)
				local place = use(placement)
				return if place == "sidebar"
					then D2.fromOffset(railWidth(use), 0)
					elseif place == "topBar" then D2.fromOffset(0, 52)
					else D2.fromOffset(0, 0)
			end,
			Size = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar"
					then D2.new(1, -(railWidth(use)), 1, 0)
					else D2.new(1, 0, 1, -52 - use(aboveHeight))
			end,
			Compose.LayerStack({
				from = visited,
				retention = "all",
				render = function(
					current: ComposeTypes.Readable<string>,
					state: ComposeTypes.Readable<ComposeTypes.LayerStackState>,
					id: string
				): Instance
					tabDepth += 1
					local ok, built = pcall(function(): Instance
						return content(byId[current:peek()].content, nil)
					end)
					tabDepth -= 1
					if not ok then
						error(built, 0)
					end
					local panel = layer(
						{
							Name = id,
							BackgroundTransparency = 1,
							Size = D2.fromScale(1, 1),
							Visible = function(use: ComposeTypes.Use)
								return use(state).top
							end,
							SelectionGroup = true,
							Attributes = { FacetTabPage = true } :: Types.Attributes,
							built,
						},
						state,
						if spec.transition == nil then TAB_FADE else spec.transition,
						if spec.retention == "top"
							then function()
								if spec.selection:peek() == id then
									return
								end
								local retained = {}
								for _, key in visited:peek() do
									if key ~= id then
										table.insert(retained, key)
									end
								end
								visited:set(retained)
							end
							else nil,
						not tabsReady
					)
					panels[id] = panel
					local shown = ctx.observe.Visible(panel)
					local attached = Compose.cell(0)
					runtime.connect(panel, "AncestryChanged", function()
						attached:set(attached:peek() + 1)
					end)
					Compose.watch(function(use: ComposeTypes.Use)
						use(attached)
						if
							not use(shown)
							or not use(state).top
							or handoff ~= id
							or not gui
							or panel:FindFirstAncestorWhichIsA("LayerCollector") == nil
						then
							return
						end
						handoff = nil
						local bookmark = bookmarks[id]
						if not bookmark and bookmarkPaths[id] then
							local node: Instance? = panel
							for _, name in bookmarkPaths[id] do
								node = if node then node:FindFirstChild(name) else nil
							end
							bookmark = if node and node:IsA("GuiObject") then node else nil
						end
						bookmarkPaths[id] = nil
						local button = tabButtons[id]
						gui.SelectedObject = if bookmark
								and surfaces.within(bookmark, panel)
								and bookmark.Visible
								and bookmark.Interactable
							then bookmark
							else surfaces.firstSelectable(panel) or (if button
									and button.Parent
									and button.Visible
								then button
								else nil)
					end)
					Compose.cleanup(function()
						local bookmark = bookmarks[id]
						if bookmark and surfaces.within(bookmark, panel) then
							local names: { string } = {}
							local node: Instance? = bookmark
							while node and node ~= panel do
								table.insert(names, 1, node.Name)
								node = node.Parent
							end
							bookmarkPaths[id] = names
						end
						panels[id], bookmarks[id] = nil, nil
					end)
					return panel
				end,
			}),
		}
		tabsReady = true
		surfaces.attach(root, { bar, layers })
		runtime.decorate(bar, {
			Visible = function(use: ComposeTypes.Use)
				return not use(collapsed)
			end,
		})
		surfaces.attach(root, {
			Compose.show(collapsed, function()
				return UI.Menu "TabsMenu" {
					Size = D2.fromOffset(0, 44),
					AutomaticSize = E.AutomaticSize.X,
					disclosure = true,
					label = function(use: ComposeTypes.Use)
						local tab = use(tabMap)[use(spec.selection)]
						return read(tab.label, use) or tab.id
					end,
					items = function(use: ComposeTypes.Use)
						local items: { Nav.MenuItem<string> } = {}
						for _, tab in use(visibleTabs) do
							table.insert(items, {
								id = tab.id,
								label = tab.label or tab.id,
								icon = tab.icon,
								enabled = tab.enabled,
								marked = function(use: ComposeTypes.Use)
									return use(spec.selection) == tab.id
								end,
								onSelect = function()
									select(tab.id)
								end,
							})
						end
						return items
					end,
				}
			end),
		})
		local slots: { [string]: { [string]: boolean } } = {
			head = { sidebar = true },
			foot = { sidebar = true },
			trailing = { topBar = true, bottomBar = true, bottomBarCompact = true },
			aboveBar = { bottomBar = true, bottomBarCompact = true },
		}
		local accessories: { [string]: (Nav.Placement) -> Instance? } = spec.accessories or {}
		for slot, build in accessories do
			assert(
				slots[slot] and type(build) == "function",
				"TabView accessories require head, foot, trailing or aboveBar builders"
			)
			if spec.placement and spec.placement ~= "automatic" and type(spec.placement) == "string" then
				assert(slots[slot][spec.placement], "TabView accessory is unavailable in this placement")
			end
			surfaces.attach(root, {
				Compose.keyed({
					from = function(use: ComposeTypes.Use): { Nav.Placement }
						local place = use(placement) :: Nav.Placement
						local result: { Nav.Placement } = {}
						if slots[slot][place] then
							table.insert(result, place)
						end
						return result
					end,
					render = function(current: ComposeTypes.Readable<Nav.Placement>): Instance
						local built = build(current:peek())
						if built == nil then
							return Host.Folder({})
						end
						local accessory = Host.Frame("Accessory-" .. slot)({
							BackgroundTransparency = 1,
							ClipsDescendants = true,
							Size = function(use: ComposeTypes.Use)
								return if slot == "head" or slot == "foot"
									then D2.fromOffset(railWidth(use), 0)
									elseif slot == "trailing" then D2.fromOffset(0, 44)
									else D2.new(1, 0, 0, 0)
							end,
							AutomaticSize = if slot == "trailing" then E.AutomaticSize.X else E.AutomaticSize.Y,
							built,
						})
						local measure = ctx.observe.AbsoluteSize(accessory)
						local metric: ComposeTypes.Cell<number> = if slot == "head"
							then headHeight
							elseif slot == "foot" then footHeight
							elseif slot == "trailing" then trailingWidth
							else aboveHeight
						Compose.watch(function(use: ComposeTypes.Use)
							local size = use(measure)
							metric:set(if slot == "trailing" then size.X else size.Y)
						end)
						Compose.cleanup(function()
							metric:set(0)
						end)
						runtime.decorate(accessory, {
							Name = "Accessory-" .. slot,
							ZIndex = 5,
							Position = function(use: ComposeTypes.Use)
								local place = use(placement)
								if slot == "head" then
									return D2.fromOffset(0, 0)
								end
								if slot == "foot" then
									return D2.new(0, 0, 1, -use(footHeight))
								end
								if slot == "aboveBar" then
									return D2.new(0, 0, 1, -44 - use(aboveHeight))
								end
								return D2.new(
									1,
									-use(trailingWidth),
									if place == "topBar" then 0 else 1,
									if place == "topBar" then 0 else -44
								)
							end,
						})
						return accessory
					end,
				}),
			})
		end
		local function advance(direction: number): ()
			local list = visibleTabs:peek()
			local at = 1
			for index, tab in list do
				if tab.id == spec.selection:peek() then
					at = index
					break
				end
			end
			local nextIndex = at
			for _ = 1, #list do
				local candidate = if spec.shoulderNavigation == "content"
					then math.clamp(nextIndex + direction, 1, #list)
					else (nextIndex - 1 + direction) % #list + 1
				if candidate == nextIndex then
					break
				end
				nextIndex = candidate
				if tabEnabled(list[nextIndex].id) then
					break
				end
			end
			select(list[nextIndex].id)
		end
		if ctx.action then
			local active = function(use: ComposeTypes.Use)
				return read(spec.enabled, use) ~= false
					and gui ~= nil
					and surfaces.within(use(selectedObject), if spec.shoulderNavigation == "content" then root else bar)
			end
			ctx.action(root, "PreviousTab", { "ButtonL1" }, active, function()
				advance(-1)
			end, { priority = 50 + depth })
			ctx.action(root, "NextTab", { "ButtonR1" }, active, function()
				advance(1)
			end, { priority = 50 + depth })
		end
		return root
	end)

	local function navigationStack<P>(spec: Nav.NavigationStackSpec<P>): Frame
		assert(
			type(spec.path) == "table" and spec.path.set and spec.root and spec.destinations,
			"NavigationStack requires path, root and destinations"
		)
		checkTransition(spec.transition)
		local gui = surfaces.service("GuiService")
		local selectedObject = if gui then ctx.observe.SelectedObject(gui) else Compose.cell(nil :: GuiObject?)
		local depth = navigationDepth
		local rootEntry: Nav.NavigationEntry<P> = { id = "@root" }
		local errorText: ComposeTypes.Cell<string?> = Compose.cell(nil :: string?)
		local accepted = { rootEntry }
		local reduce = reducedMotion(ctx)
		local timing: Nav.Transition? = if type(spec.transition) == "table" then spec.transition else nil
		local animated = spec.transition == nil
		local function validate(path: { Nav.NavigationEntry<P> }): { Nav.NavigationEntry<P> }
			assert(type(path) == "table", "NavigationStack.path must contain an array")
			local list = { rootEntry }
			for _, entry in path do
				assert(
					type(entry) == "table" and type(entry.id) == "string" and spec.destinations[entry.id],
					"NavigationStack path has an undeclared destination"
				)
				table.insert(list, entry)
			end
			return list
		end
		validate(spec.path:peek())
		local entries = Compose.formula(function(use: ComposeTypes.Use)
			local ok, list = pcall(validate, use(spec.path))
			if ok then
				accepted = list
				errorText:set(nil)
			else
				errorText:set(tostring(list))
			end
			return accepted
		end)
		local leaving: ComposeTypes.Cell<Nav.NavigationEntry<P>?> = Compose.cell(nil :: Nav.NavigationEntry<P>?)
		local shownList = entries:peek()
		Compose.watch(function(use: ComposeTypes.Use)
			local list = use(entries)
			local former = shownList
			shownList = list
			local top = former[#former]
			local departing = leaving:peek()
			if table.find(list, top) == nil and animated and not reduce() then
				leaving:set(top)
			elseif departing and table.find(list, departing) then
				leaving:set(nil)
			end
		end)
		local displayed = Compose.formula(function(use: ComposeTypes.Use)
			local list = use(entries)
			local departing = use(leaving)
			if departing == nil or table.find(list, departing) then
				return list
			end
			local result = table.clone(list)
			table.insert(result, departing)
			return result
		end)
		local offsets: ComposeTypes.Cell<{ [Nav.NavigationEntry<P>]: (ComposeTypes.Use?) -> number }> = Compose.cell({})
		local stackReady = false
		local handoff = false
		local function pop()
			local path = table.clone(spec.path:peek())
			if #path > 0 then
				table.remove(path)
				spec.path:set(path)
			end
		end
		local function frontOffset(use: ComposeTypes.Use): number
			local list = use(displayed)
			local measure = use(offsets)[list[#list]]
			return if measure then measure(use) else 0
		end
		local root: Frame
		local backdrop: ComposeTypes.Cell<Color3?> = Compose.cell(nil :: Color3?)
		local moving = Compose.formula(function(use: ComposeTypes.Use): boolean
			return frontOffset(use) > 0 or use(leaving) ~= nil
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(moving) then
				return
			end
			local at: Instance? = root and root.Parent
			while at do
				if at:IsA("GuiObject") and (at:GetStyled("BackgroundTransparency") :: number) < 1 then
					backdrop:set(at:GetStyled("BackgroundColor3") :: Color3)
					return
				end
				at = at.Parent
			end
			backdrop:set(nil)
		end)
		root = Host.Frame(ctx.props(spec, { "path", "root", "destinations", "backLabel", "transition" }, {
			Name = "NavigationStack",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			ClipsDescendants = function(use: ComposeTypes.Use)
				return frontOffset(use) > 0
			end,
			Compose.LayerStack({
				from = displayed,
				retention = "all",
				render = function(
					current: ComposeTypes.Readable<Nav.NavigationEntry<P>>,
					state: ComposeTypes.Readable<ComposeTypes.LayerStackState>
				): Instance
					local entry = current:peek()
					local destination = if entry == rootEntry then spec.root else spec.destinations[entry.id]
					local chrome = if entry ~= rootEntry or destination.title and destination.title ~= "" then 44 else 0
					local role = Compose.formula(function(use: ComposeTypes.Use): string
						local list = use(entries)
						local at = table.find(list, entry)
						return if at == nil then "exiting" elseif at == #list then "top" else "covered"
					end)
					local entering = Compose.cell(stackReady and animated and not reduce())
					local function target(use: ComposeTypes.Use): number
						return if use(role) == "exiting" or use(entering) and not reduce(use) then 1 else 0
					end
					local travel: ComposeTypes.Readable<number> = if animated
						then runtime.spring(target, {
							period = PUSH_SPRING.period,
							damping = PUSH_SPRING.damping,
							tolerance = PUSH_SPRING.tolerance,
							reducedMotion = function(use: ComposeTypes.Use): boolean
								return reduce(use)
							end,
						})
						else Compose.cell(0)
					entering:set(false)
					local function offset(use: ComposeTypes.Use?): number
						if not animated or reduce(use) then
							return if read(role, use) == "exiting" then 1 else 0
						end
						return read(travel, use)
					end
					local registered = table.clone(offsets:peek())
					registered[entry] = offset
					offsets:set(registered)
					Compose.cleanup(function()
						local remaining = table.clone(offsets:peek())
						remaining[entry] = nil
						offsets:set(remaining)
					end)
					local function placement(use: ComposeTypes.Use): (string, number)
						local list = use(displayed)
						local at = table.find(list, entry)
						if at == #list then
							return "front", offset(use)
						end
						if at == #list - 1 then
							local above = use(offsets)[list[#list]]
							local moved = if above then above(use) else 0
							if moved > 0 or use(role) == "top" then
								return "beneath", moved
							end
						end
						return "rest", 0
					end
					local function reveal(use: ComposeTypes.Use): number
						local place, moved = placement(use)
						return if place == "beneath" then moved + PARALLAX * (1 - moved) else 1
					end
					local navigationBar = Host.Frame "NavigationBar" {
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, chrome),
						Visible = chrome > 0,
						ctx.styled(
							ctx.text({
								Name = "Title",
								Text = destination.title or "",
								Size = D2.fromScale(1, 1),
								TextTruncate = E.TextTruncate.AtEnd,
								TextXAlignment = function(use: ComposeTypes.Use)
									return if use(state).index > 1
										then E.TextXAlignment.Center
										else E.TextXAlignment.Left
								end,
							}),
							if entry == rootEntry then "type-title" else "type-heading"
						) :: Types.Child,
						Compose.show(function(use: ComposeTypes.Use)
							return use(state).index > 1
						end, function()
							return UI.Button "Back" {
								label = spec.backLabel or "Back",
								icon = "chevron.leading",
								appearance = "link",
								AnchorPoint = V2.new(0, 0.5),
								Position = D2.fromScale(0, 0.5),
								onActivate = pop,
							}
						end),
					}
					local destinationFrame = Host.Frame "Destination" {
						BackgroundTransparency = 1,
						Position = D2.fromOffset(0, chrome),
						Size = D2.new(1, 0, 1, -chrome),
						Compose.boundary(function()
							navigationDepth += 1
							local ok, built =
								pcall(content, destination.content, if entry == rootEntry then nil else entry)
							navigationDepth -= 1
							if not ok then
								error(built, 0)
							end
							return built
						end, function(failure)
							errorText:set(tostring(failure))
							return ctx.text({
								Name = "DestinationError",
								Text = "This page could not be displayed.",
								TextWrapped = true,
							})
						end),
					}
					local panel: GuiObject
					if timing then
						panel = layer({
							Name = entry.id,
							BackgroundTransparency = 1,
							Size = D2.fromScale(1, 1),
							Visible = function(use: ComposeTypes.Use)
								return use(state).top
							end,
							navigationBar,
							destinationFrame,
						}, state, timing)
					else
						panel = Host.Frame(entry.id)({
							BackgroundTransparency = function(use: ComposeTypes.Use)
								return if use(moving)
										and use(backdrop) ~= nil
										and placement(use) ~= "rest"
									then 0
									else 1
							end,
							BackgroundColor3 = function(use: ComposeTypes.Use)
								return use(backdrop) or ctx.types.Color3.new(0, 0, 0)
							end,
							BorderSizePixel = 0,
							Size = D2.fromScale(1, 1),
							Position = function(use: ComposeTypes.Use)
								local place, moved = placement(use)
								return if place == "front"
									then D2.fromScale(moved, 0)
									elseif place == "beneath" then D2.fromScale(-PARALLAX * (1 - moved), 0)
									else D2.fromScale(0, 0)
							end,
							ClipsDescendants = function(use: ComposeTypes.Use)
								return reveal(use) < 1
							end,
							Visible = function(use: ComposeTypes.Use)
								local place = placement(use)
								return place == "beneath" or place == "front" and use(role) ~= "covered"
							end,
							Interactable = function(use: ComposeTypes.Use)
								return use(role) == "top"
							end,
							Host.Frame "Page" {
								BackgroundTransparency = 1,
								Size = D2.fromScale(1, 1),
								navigationBar,
								destinationFrame,
							} :: Types.Child,
							Compose.show(function(use: ComposeTypes.Use)
								return placement(use) == "beneath"
							end, function()
								return Host.Frame "Dim" {
									BackgroundColor3 = ctx.types.Color3.new(0, 0, 0),
									BorderSizePixel = 0,
									Size = D2.fromScale(1, 1),
									ZIndex = 10,
									Interactable = false,
									BackgroundTransparency = function(use: ComposeTypes.Use)
										local _, moved = placement(use)
										return 1 - DIM * (1 - moved)
									end,
								}
							end) :: Types.Child,
						})
					end
					Compose.watch(function(use: ComposeTypes.Use)
						if use(role) ~= "exiting" then
							return
						end
						if gui and surfaces.within(gui.SelectedObject, panel) then
							handoff = true
							gui.SelectedObject = nil
						end
						if offset(use) >= 1 and leaving:peek() == entry then
							leaving:set(nil)
						end
					end)
					local visible, parent = ctx.observe.Visible(panel), ctx.observe.Parent(panel)
					local remembered: GuiObject?
					local previousTop: boolean?
					local focusing = surfaces.selecting()
					Compose.watch(function(use: ComposeTypes.Use)
						local selected = use(selectedObject)
						if selected and selected:IsA("GuiObject") and surfaces.within(selected, panel) then
							remembered = selected :: GuiObject
						end
					end)
					Compose.watch(function(use: ComposeTypes.Use)
						local top = use(role) == "top"
						if not use(parent) then
							return
						end
						if
							gui
							and top
							and use(visible)
							and use(parent)
							and previousTop ~= true
							and (previousTop == false or use(state).index > 1)
							and (gui.SelectedObject ~= nil or handoff or focusing(use))
						then
							handoff = false
							gui.SelectedObject = if remembered
									and remembered.Parent
									and remembered.Visible
									and remembered.Interactable
								then remembered
								else surfaces.firstSelectable(panel)
						end
						previousTop = top
					end)
					return panel
				end,
			}),
		}))
		stackReady = true
		if ctx.action then
			ctx.action(root, "NavigationBack", { "Escape", "ButtonB" }, function(use: ComposeTypes.Use)
				return #use(spec.path) > 0 and (depth == 0 or surfaces.within(use(selectedObject), root))
			end, pop, { priority = 1000 + depth })
		end
		Compose.watch(function(use: ComposeTypes.Use)
			root:SetAttribute("FacetError", use(errorText))
		end)
		return root
	end

	UI.NavigationStack = ctx.construct("NavigationStack", navigationStack)

	UI.PageView = ctx.construct("PageView", function(spec: Nav.PageViewSpec): Frame
		local byId = checkedSelection(spec.selection, spec.pages, "PageView")
		local indexById: { [string]: number } = {}
		for index, page in spec.pages do
			indexById[page.id] = index
		end
		local footerHeight = (if spec.summary ~= false then 24 else 0)
			+ (if spec.indicators ~= false then 48 else 0)
			+ (if spec.controls ~= false then 48 else 0)
		local pageNodes: { [string]: Frame } = {}
		local gui = surfaces.service("GuiService")
		local reduced = if gui then ctx.observe.ReducedMotionEnabled(gui) else Compose.cell(false)
		local layout = Host.UIPageLayout "PagesLayout" {
			Animated = function(use: ComposeTypes.Use)
				return read(ctx.config.reducedMotion, use) ~= true and not use(reduced)
			end,
			Circular = false,
			FillDirection = E.FillDirection.Horizontal,
			SortOrder = E.SortOrder.LayoutOrder,
			GamepadInputEnabled = true,
			TouchInputEnabled = true,
			ScrollWheelInputEnabled = false,
		}
		local children: { Types.Child } = { layout }
		for index, page in spec.pages do
			local node = Host.Frame(page.id)({
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				LayoutOrder = index,
				content(page.content, nil),
			})
			pageNodes[page.id] = node
			table.insert(children, node)
		end
		local pages = Host.Frame "Pages" {
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 1, -footerHeight),
			ClipsDescendants = true,
		}
		surfaces.attach(pages, children)
		local changing = false
		local parent = ctx.observe.Parent(pages)
		Compose.watch(function(use: ComposeTypes.Use)
			local id = use(spec.selection)
			assert(byId[id], "PageView.selection must name a declared page")
			if use(parent) then
				changing = true
				layout:JumpTo(pageNodes[id])
				changing = false
			end
		end)
		local gui = surfaces.service("GuiService")
		local current = ctx.observe.CurrentPage(layout)
		Compose.watch(function(use: ComposeTypes.Use)
			local page = use(current)
			if
				gui
				and page
				and gui.SelectedObject
				and surfaces.within(gui.SelectedObject, pages)
				and not surfaces.within(gui.SelectedObject, page)
			then
				gui.SelectedObject = surfaces.firstSelectable(page)
			end
			if not changing and page and byId[page.Name] and page.Name ~= spec.selection:peek() then
				spec.selection:set(page.Name)
			end
		end)
		local function step(amount: number): ()
			local at = math.clamp(indexById[spec.selection:peek()] + amount, 1, #spec.pages)
			spec.selection:set(spec.pages[at].id)
		end
		if gui and ctx.action then
			local selectedObject = ctx.observe.SelectedObject(gui)
			local function inside(use: ComposeTypes.Use): boolean
				return surfaces.within(use(selectedObject), pages)
			end
			ctx.action(pages, "PageForward", { E.KeyCode.Right, E.KeyCode.DPadRight }, inside, function()
				step(1)
			end, { priority = 1500, capture = true })
			ctx.action(pages, "PageBack", { E.KeyCode.Left, E.KeyCode.DPadLeft }, inside, function()
				step(-1)
			end, { priority = 1500, capture = true })
		end
		local footer: { Types.Child } = {}
		if spec.summary ~= false then
			table.insert(
				footer,
				ctx.text({
					Name = "Summary",
					Text = function(use: ComposeTypes.Use)
						return `Page {indexById[use(spec.selection)]} of {#spec.pages}`
					end,
				})
			)
		end
		if spec.indicators ~= false then
			local options: { Nav.PickerOption<string> } = {}
			for index, page in spec.pages do
				table.insert(options, { value = page.id, label = tostring(index) })
			end
			table.insert(
				footer,
				UI.Picker "Indicators" {
					selected = spec.selection,
					options = options,
					multiple = false :: false,
					style = "segmented" :: "segmented",
				}
			)
		end
		if spec.controls ~= false then
			table.insert(
				footer,
				ctx.row({
					UI.Button "Previous" {
						label = "Previous",
						enabled = function(use: ComposeTypes.Use)
							return indexById[use(spec.selection)] > 1
						end,
						onActivate = function()
							step(-1)
						end,
					},
					UI.Button "Next" {
						label = "Next",
						enabled = function(use: ComposeTypes.Use)
							return indexById[use(spec.selection)] < #spec.pages
						end,
						onActivate = function()
							step(1)
						end,
					},
				})
			)
		end
		return Host.Frame(ctx.props(spec, { "pages", "selection", "indicators", "summary", "controls" }, {
			Name = "PageView",
			BackgroundTransparency = 1,
			Size = D2.fromScale(1, 1),
			pages,
			ctx.column(footer, {
				Name = "Footer",
				Position = D2.new(0, 0, 1, -footerHeight),
				Size = D2.new(1, 0, 0, footerHeight),
				AutomaticSize = E.AutomaticSize.None,
			}),
		}))
	end)
end
