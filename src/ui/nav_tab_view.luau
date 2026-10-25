--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Content = require("./content_types")
local ComposeTypes = require("../vendor/compose/core")
local motion = require("./motion")
local adaptive = require("./adaptive")
local segmentMetrics = require("./segment_metrics")
local reservations = require("./reservations")
local ControlTypes = require("./control_types")
local NavigationProps = require("./navigation_props")
local pageLayers = require("./nav_page_layers")
local tabMetrics = require("./nav_tab_metrics")
local tabItem = require("./nav_tab_item")
local tabAccessories = require("./nav_tab_accessories")
local presentationReadiness = require("./presentation_readiness")
local scrollLock = require("./scroll_lock")
local scrollFlash = require("./scroll_flash")
type SelectionLinks = {
	NextSelectionLeft: GuiObject?,
	NextSelectionRight: GuiObject?,
	NextSelectionUp: GuiObject?,
	NextSelectionDown: GuiObject?,
}

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	layers: pageLayers.PageLayers
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local content, layer, checkedSelection = layers.content, layers.layer, layers.checkedSelection
	local tabDepth = 0
	UI.TabView = ctx.construct("TabView", function(spec: NavigationProps.TabViewSpec): Frame
		local retention = spec.retention
		assert(
			retention == nil or retention == "all" or retention == "top",
			"TabView.retention uses Compose all or top"
		)
		local depth = tabDepth
		local tabLevel = motion.level(ctx)
		local nested = Compose.cell(depth > 0)
		local statuses: { [string]: boolean } = {
			neutral = true,
			info = true,
			success = true,
			warning = true,
			error = true,
			accent = true,
			voice = true,
			contrast = true,
		}
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
			spec.labelPlacement == nil or table.find({ "besideIcon", "belowIcon" }, read(spec.labelPlacement)),
			"Invalid TabView.labelPlacement"
		)
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
		local properties = ctx.props(spec, {
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
			"sidebarExpanded",
			"restoreScroll",
			"shoulderNavigation",
			"restoreFocus",
			"indicator",
			"track",
			"indicatorPlacement",
			"iconOnly",
			"textSize",
			"labelPlacement",
			"enabled",
			"onChange",
			"controlSize",
		}, { Name = "TabView", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) })
		local frames = ctx.config.services.RunService
		local preparing = frames ~= nil and frames.PreRender ~= nil and runtime.host.frames ~= nil
		local root = if preparing
			then ctx.fade((properties :: unknown) :: Types.CanvasGroupNativeProps, false, false)
			else Host.Frame(properties)
		if preparing then
			ctx.fadeTo(root, 1)
		end
		local layoutUnit = ctx.layoutUnit(root)
		local dimensions = ctx.layoutSize(root, layoutUnit)
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
		local tenFoot = ctx.tenFoot()
		local displaySize = if ctx.config.guiService
			then ctx.observe.ViewportDisplaySize(ctx.config.guiService)
			else nil
		local function resolvePlacement(use: ComposeTypes.Use): Nav.Placement
			if spec.style == "collapsible" then
				return "topBar"
			end
			local explicit = read(spec.placement, use)
			if explicit and explicit ~= "automatic" then
				return explicit
			end
			local distant = tenFoot(use)
			if spec.style == "sidebarAdaptable" and distant and read(spec.sidebarExpanded, use) == true then
				return "sidebar"
			end
			if use(nested) then
				return "topBar"
			end
			local size, preferred = use(dimensions), use(primaryInput)
			local display = if displaySize then use(displaySize) else nil
			local home: Nav.Placement = adaptive.navPlacement({
				sizeClass = adaptive.sizeClass(size.X),
				heightClass = adaptive.heightClass(size.Y),
				primary = if preferred == E.PreferredInput.Gamepad
					then "gamepad"
					elseif preferred == E.PreferredInput.Touch then "touch"
					else "pointer",
				displaySize = if typeof(display) == "EnumItem" then (display :: EnumItem).Name else nil,
				tenFoot = distant,
			})
			if spec.style == "sidebarAdaptable" and not distant and (home == "sidebar" or home == "topBar") then
				local choice = read(spec.sidebarPreference, use)
				if choice and choice ~= "automatic" then
					return choice
				end
			end
			return home
		end
		local placement = Compose.formula(resolvePlacement :: (ComposeTypes.Use) -> string)
		local function indicatorOf(use: ComposeTypes.Use): Nav.TabSelectionIndicator?
			local chosen = read(spec.indicator, use)
			if (chosen == nil or chosen == "automatic") and spec.style == "sidebarAdaptable" then
				return "pill"
			end
			return chosen
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
		local tabLinks = Compose.cell(0)
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
		local frame: tabMetrics.TabFrame = {
			fit = fit,
			placement = placement,
			visibleTabs = visibleTabs,
			dimensions = dimensions,
			layoutUnit = layoutUnit,
			headHeight = headHeight,
			footHeight = footHeight,
			trailingWidth = trailingWidth,
			indicatorOf = indicatorOf,
		}
		local metrics = tabMetrics(ctx, spec, frame)
		local floating, floatingSize, floatingPosition =
			metrics.floating, metrics.floatingSize, metrics.floatingPosition
		local segmentedTop, inset = metrics.segmentedTop, metrics.inset
		local band, railWidth, bottomInset = metrics.band, metrics.railWidth, metrics.bottomInset
		local barExtent, stripLayout, stripOverflows, stripContent =
			metrics.barExtent, metrics.stripLayout, metrics.stripOverflows, metrics.stripContent
		local INSET = segmentMetrics.inset
		local bar = Host.ScrollingFrame "Tabs" {
			ZIndex = 2,
			BackgroundTransparency = function(use: ComposeTypes.Use): number
				return if segmentedTop(use) then 0 else 1
			end,
			BorderSizePixel = 0,
			ScrollBarThickness = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar" or use(stripOverflows) then 2 else 0
			end,
			VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
			HorizontalScrollBarInset = E.ScrollBarInset.None,
			CanvasSize = D2.fromOffset(0, 0),
			AutomaticCanvasSize = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar" then E.AutomaticSize.Y else E.AutomaticSize.X
			end,
			ScrollingDirection = function(use: ComposeTypes.Use)
				return if use(placement) == "sidebar" then E.ScrollingDirection.Y else E.ScrollingDirection.X
			end,
			Size = function(use: ComposeTypes.Use)
				if segmentedTop(use) then
					return D2.fromOffset(0, band(use) + 2 * INSET)
				end
				return D2.fromScale(1, 1)
			end,
			AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
				return if segmentedTop(use) then E.AutomaticSize.X else E.AutomaticSize.None
			end,
			Host.UIFlexItem {
				FlexMode = function(use: ComposeTypes.Use): Enum.UIFlexMode
					return if segmentedTop(use) then E.UIFlexMode.Shrink else E.UIFlexMode.None
				end,
			},
			Host.UIPadding({
				PaddingLeft = inset,
				PaddingRight = inset,
				PaddingTop = inset,
				PaddingBottom = inset,
			}) :: Types.Child,
			Host.Frame "Strip" {
				BackgroundTransparency = 1,
				Size = function(use: ComposeTypes.Use): UDim2
					return D2.fromScale(1, if use(placement) == "sidebar" then 0 else 1)
				end,
				AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
					return if use(placement) == "sidebar" then E.AutomaticSize.Y else E.AutomaticSize.X
				end,
				stripLayout :: Types.Child,
				tabItem(ctx, UI, surfaces, spec, {
					frame = frame,
					select = select,
					sectionLabels = sectionLabels,
					tabButtons = tabButtons,
					tabMeasures = tabMeasures,
					tabLinks = tabLinks,
					metrics = metrics,
				}),
			},
		}
		scrollLock.own((bar :: unknown) :: ScrollingFrame, ctx)
		scrollFlash(ctx, (bar :: unknown) :: ScrollingFrame, "X", stripOverflows)
		local bandBox = Host.Frame "TabBand" {
			ZIndex = 2,
			BackgroundTransparency = 1,
			Size = function(use: ComposeTypes.Use): UDim2
				if floating(use) then
					return floatingSize(use)
				end
				if segmentedTop(use) then
					return D2.new(1, -use(trailingWidth), 0, band(use) + 2 * INSET)
				end
				return if use(placement) == "sidebar"
					then D2.new(0, railWidth(use) - 16, 1, -use(headHeight) - use(footHeight))
					else D2.new(1, -use(trailingWidth), 0, band(use))
			end,
			Position = function(use: ComposeTypes.Use): UDim2
				if floating(use) then
					return floatingPosition(use)
				end
				return if use(placement) == "sidebar"
					then D2.fromOffset(8, use(headHeight))
					elseif string.find(use(placement), "bottom") then D2.new(0, 0, 1, -band(use))
					else D2.fromOffset(0, 0)
			end,
			Host.UIListLayout {
				FillDirection = E.FillDirection.Horizontal,
				HorizontalAlignment = E.HorizontalAlignment.Center,
				VerticalAlignment = E.VerticalAlignment.Center,
			},
			bar,
		}
		Compose.watch(function(use: ComposeTypes.Use)
			bar:SetAttribute("FacetEntry", use(spec.selection))
			if segmentedTop(use) then
				root:AddTag("facet-top-tabs")
				bandBox:AddTag("facet-top-tabs")
				bar:AddTag("facet-tab-plate")
				bar:AddTag("facet-segmented")
			else
				root:RemoveTag("facet-top-tabs")
				bandBox:RemoveTag("facet-top-tabs")
				bar:RemoveTag("facet-tab-plate")
				bar:RemoveTag("facet-segmented")
			end
		end)
		local ancestry, barAt, barSize =
			Compose.cell(0), ctx.observe.AbsolutePosition(bar), ctx.observe.AbsoluteSize(bar)
		local reserved: Instance? = nil
		runtime.connect(bar, "AncestryChanged", function()
			ancestry:set(ancestry:peek() + 1)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(ancestry)
			local layer = bar:FindFirstAncestorWhichIsA("LayerCollector")
			if reserved and reserved ~= layer then
				reservations.clear(reserved, bar)
			end
			reserved = layer
			if layer and layer:IsA("GuiBase2d") then
				local band = string.find(use(placement), "bottom") ~= nil and use(barSize).Y > 0
				local top = use(barAt).Y - (layer :: GuiBase2d).AbsolutePosition.Y - use(aboveHeight)
				reservations.set(
					layer,
					bar,
					"bottom",
					if band then top else nil,
					if band then use(barSize).Y + use(aboveHeight) + bottomInset(use) else nil
				)
			end
		end)
		Compose.cleanup(function()
			if reserved then
				reservations.clear(reserved, bar)
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			use(tabLinks)
			local vertical = use(placement) == "sidebar"
			local order: { TextButton } = {}
			for _, tab in use(visibleTabs) do
				local button = tabButtons[tab.id]
				if button and button.Parent then
					local live = read(spec.enabled, use) ~= false and tabEnabled(tab.id, use)
					if live then
						table.insert(order, button)
					else
						local links = (button :: unknown) :: SelectionLinks
						links.NextSelectionLeft, links.NextSelectionRight = nil, nil
						links.NextSelectionUp, links.NextSelectionDown = nil, nil
					end
				end
			end
			for index, button in order do
				local before: GuiObject?, after: GuiObject? = order[index - 1], order[index + 1]
				local links = (button :: unknown) :: SelectionLinks
				links.NextSelectionLeft = if vertical then nil else before
				links.NextSelectionRight = if vertical then nil else after
				links.NextSelectionUp = if vertical then before else nil
				links.NextSelectionDown = if vertical then after else nil
			end
		end)
		local barSize, barPosition = ctx.observe.AbsoluteSize(bar), ctx.observe.AbsolutePosition(bar)
		Compose.watch(function(use: ComposeTypes.Use)
			barExtent:set(use(barSize))
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local room = use(barSize).X
			stripOverflows:set(
				use(placement) ~= "sidebar" and room > 0 and use(stripContent).X > room - 2 * inset(use).Offset + 0.5
			)
		end)
		local revealed: string? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			use(ancestry)
			use(tabLinks)
			local selected = use(spec.selection)
			local measure = tabMeasures[selected]
			local button = tabButtons[selected]
			if not measure or not button or not button.Parent then
				return
			end
			use(barSize)
			use(barPosition)
			use(measure.position)
			use(measure.size)
			local extent, origin, at, size =
				bar.AbsoluteSize, bar.AbsolutePosition, button.AbsolutePosition, button.AbsoluteSize
			local vertical = use(placement) == "sidebar"
			local start = if vertical then at.Y - origin.Y else at.X - origin.X
			local length = if vertical then size.Y else size.X
			local visible = if vertical then extent.Y else extent.X
			local key = `{selected}:{visible}:{length}:{use(stripContent).X}:{use(stripOverflows)}`
			if visible <= 0 or length <= 0 or revealed == key then
				return
			end
			revealed = key
			local delta = if start < 0 then start elseif start + length > visible then start + length - visible else 0
			if delta ~= 0 then
				bar.CanvasPosition = if vertical
					then V2.new(bar.CanvasPosition.X, math.max(0, bar.CanvasPosition.Y + delta))
					else V2.new(math.max(0, bar.CanvasPosition.X + delta), bar.CanvasPosition.Y)
			end
		end)
		local prepared: { [string]: ComposeTypes.Cell<boolean> } = {}
		local groupReady: ComposeTypes.Readable<boolean>? = nil
		if spec.transition and (spec.transition.apply or spec.transition.progress) then
			for id in byId do
				prepared[id] = Compose.cell(false)
			end
			groupReady = Compose.formula(function(use: ComposeTypes.Use): boolean
				return use(prepared[use(spec.selection)])
			end)
		end
		local layers = Host.Frame "Content" {
			BackgroundTransparency = 1,

			ClipsDescendants = true,
			Position = function(use: ComposeTypes.Use)
				local place = use(placement)
				return if place == "sidebar"
					then D2.fromOffset(railWidth(use), 0)
					elseif place == "topBar" then D2.fromOffset(0, band(use) + 8)
					else D2.fromOffset(0, 0)
			end,
			Size = function(use: ComposeTypes.Use)
				local place = use(placement)
				return if place == "sidebar"
					then D2.new(1, -(railWidth(use)), 1, 0)
					elseif place == "none" then D2.fromScale(1, 1)
					else D2.new(
						1,
						0,
						1,
						-band(use) - metrics.contentGap(use) - use(aboveHeight) - bottomInset(use)
					)
			end,
			Compose.LayerStack({
				from = visited,
				retention = "all",
				render = function(
					current: ComposeTypes.Readable<string>,
					state: ComposeTypes.Readable<ComposeTypes.LayerStackState>,
					id: string
				): Instance
					local step = if spec.placement == "none" then 0 else 1
					tabDepth += step
					local ok, built = pcall(function(): Instance
						return content(byId[current:peek()].content, nil)
					end)
					tabDepth -= step
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
							Attributes = { FacetTabPage = spec.placement ~= "none" } :: Types.Attributes,
							built,
						},
						state,
						if spec.transition == nil
							then {
								seconds = function(): number
									return if tabLevel() == "limited"
										then ctx.metric("motion.reducedFade")
										else ctx.metric("motion.durations.tabFade")
								end,
								ease = ctx.motionEase("fade"),
							}
							else spec.transition,
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
						not tabsReady,
						prepared[id],
						groupReady
					)
					panels[id] = panel
					local shown = ctx.observe.Visible(panel)
					local interactable = ctx.observe.Interactable(panel)
					local attached = Compose.cell(0)
					runtime.connect(panel, "AncestryChanged", function()
						attached:set(attached:peek() + 1)
					end)
					Compose.watch(function(use: ComposeTypes.Use)
						use(attached)
						if
							not use(shown)
							or not use(interactable)
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
		local track = Host.Frame "Track" {
			ZIndex = 1,
			BorderSizePixel = 0,
			Visible = function(use: ComposeTypes.Use)
				return (metrics.plated(use) or floating(use)) and not use(collapsed) and not segmentedTop(use)
			end,
			Size = function(use: ComposeTypes.Use)
				if floating(use) then
					return floatingSize(use)
				end
				if use(placement) == "sidebar" then
					return D2.new(0, railWidth(use) - 16, 1, -use(headHeight) - use(footHeight))
				end
				return D2.fromOffset(0, 0)
			end,
			Position = function(use: ComposeTypes.Use)
				if floating(use) then
					return floatingPosition(use)
				end
				if use(placement) == "sidebar" then
					return D2.fromOffset(8, use(headHeight))
				end
				return D2.fromOffset(0, 0)
			end,
		}
		if not floating() then
			track:AddTag("facet-segmented")
		end
		track:AddTag("facet-tab-plate")
		surfaces.attach(track, {
			Compose.show(floating, function(): Instance
				return Host.UICorner {
					CornerRadius = function(use: ComposeTypes.Use): UDim
						return D.new(
							0,
							ctx.metric(
								if use(placement) == "sidebar"
									then "controls.tabRailTrack.radius"
									else "controls.tabBottomTrack.radius",
								use
							)
						)
					end,
				}
			end),
		})
		Compose.watch(function(use: ComposeTypes.Use)
			if floating(use) then
				track:RemoveTag("facet-segmented")
			else
				track:AddTag("facet-segmented")
			end
		end)
		surfaces.attach(root, { track, bandBox, layers })
		local canvas, window = ctx.observe.AbsoluteCanvasSize(bar), ctx.observe.AbsoluteWindowSize(bar)
		runtime.decorate(bar, {
			Visible = function(use: ComposeTypes.Use)
				return not use(collapsed) and use(placement) ~= "none"
			end,
			ClipsDescendants = function(use: ComposeTypes.Use): boolean
				local content, room = use(canvas), use(window)
				return content.X > room.X + 0.5 or content.Y > room.Y + 0.5
			end,
		})
		surfaces.attach(root, {
			Compose.show(collapsed, function()
				return UI.Menu "TabsMenu" {
					Size = function(use: ComposeTypes.Use)
						return D2.fromOffset(0, band(use))
					end,
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
		tabAccessories(ctx, surfaces, spec, root, {
			frame = frame,
			aboveHeight = aboveHeight,
			metrics = metrics,
		})
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
			local expanded = spec.sidebarExpanded
			if expanded ~= nil then
				assert(
					type(expanded) == "table" and expanded.set ~= nil,
					"Facet UI.TabView: sidebarExpanded must be a writable Compose cell"
				)
				ctx.action(root, "SidebarCollapse", { "ButtonB" }, function(use: ComposeTypes.Use)
					return use(expanded) == true
						and tenFoot(use)
						and gui ~= nil
						and surfaces.within(use(selectedObject), bar)
				end, function()
					expanded:set(false)
				end, { priority = 1100 + depth })
			end
			local function inChrome(node: GuiObject?): boolean
				local content = root:FindFirstChild("Content")
				return node ~= nil
					and surfaces.within(node, root)
					and not (content and surfaces.within(node, content))
					and not surfaces.within(node, bar)
			end
			local accessory: GuiObject? = nil
			Compose.watch(function(use: ComposeTypes.Use)
				local current = use(selectedObject) :: GuiObject?
				accessory = if inChrome(current) then current else nil
			end)
			local first = true
			Compose.watch(function(use: ComposeTypes.Use)
				use(placement)
				if first then
					first = false
					return
				end
				local button = tabButtons[spec.selection:peek()]
				local current = gui and gui.SelectedObject
				if gui and button and (accessory ~= nil or inChrome(current)) and current ~= button then
					accessory = nil
					gui.SelectedObject = button
				end
			end)
		end
		if preparing then
			root:SetAttribute("FacetPreparing", true)
			local ready = presentationReadiness(ctx, { root })
			Compose.watch(function(use: ComposeTypes.Use)
				if use(ready) then
					ctx.fadeTo(root, 0)
					root:SetAttribute("FacetPreparing", false)
				end
			end)
		end
		return root
	end)
end
