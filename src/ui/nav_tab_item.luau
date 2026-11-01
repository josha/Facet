--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local Content = require("./content_types")
local ComposeTypes = require("../vendor/compose/core")
local NavigationProps = require("./navigation_props")
local tabMetrics = require("./nav_tab_metrics")
local textMeasure = require("./text_measure")

export type TabItemView = {
	isCurrent: (string) -> ComposeTypes.ReadOnlyValue<boolean>,
	frame: tabMetrics.TabFrame,
	select: (string) -> (),
	sectionLabels: { [string]: string },
	tabButtons: { [string]: TextButton },
	tabMeasures: {
		[string]: { position: ComposeTypes.ReadOnlyValue<Vector2>, size: ComposeTypes.ReadOnlyValue<Vector2> },
	},
	tabLinks: ComposeTypes.Value<number>,
	metrics: tabMetrics.TabMetrics,
}

local CORNER_OVERLAP = 0.25

return function(
	ctx: Types.Context,
	UI: ControlTypes.Controls,
	surfaces: Nav.Surfaces,
	spec: NavigationProps.TabViewSpec,
	view: TabItemView
): Types.Child
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local readText = read<<string?>>
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local frame = view.frame
	local fit, placement, visibleTabs = frame.fit, frame.placement, frame.visibleTabs
	local layoutUnit, indicatorOf, select = frame.layoutUnit, frame.indicatorOf, view.select
	local isCurrent = view.isCurrent
	local sectionLabels, tabButtons, tabMeasures, tabLinks =
		view.sectionLabels, view.tabButtons, view.tabMeasures, view.tabLinks
	local metrics = view.metrics
	local wordWidths, stacked, crowded, labelLine, iconGap =
		metrics.wordWidths, metrics.stacked, metrics.crowded, metrics.labelLine, metrics.iconGap
	local badgeClearances, band, tabHeight = metrics.badgeClearances, metrics.band, metrics.tabHeight
	return Compose.keyed({
		from = visibleTabs,
		key = function(tab: Nav.Tab): string
			return tab.id
		end,
		render = function(
			current: ComposeTypes.ReadOnlyValue<Nav.Tab>,
			index: ComposeTypes.ReadOnlyValue<number>
		): Instance
			local tab = current:peek()
			local button = UI.Button {
				Name = tab.id,
				controlSize = spec.controlSize,
				label = function(use: ComposeTypes.Use)
					local tab = use(current)
					if read(spec.iconOnly, use) then
						return ""
					end
					return tostring(read(tab.label, use) or tab.id)
				end,
				name = function(use: ComposeTypes.Use): string
					local tab = use(current)
					local badge = read(tab.badge, use)
					return tostring(read(tab.label, use) or tab.id)
						.. (if badge ~= nil and badge ~= "" then ` ({badge})` else "")
				end,
				icon = tab.icon,
				glyph = tab.glyph,
				subtitle = if tab.badge ~= nil
						and tab.icon == nil
						and tab.glyph == nil
					then function(): string
						return ""
					end
					else nil,
				TextSize = if fit then nil else (spec.textSize :: unknown) :: Types.Input<number>,
				LayoutOrder = index,
				Size = function(use: ComposeTypes.Use)
					local place = use(placement)
					local height = tabHeight(use)
					if string.find(place, "bottom") ~= nil and (stacked(use) or (fit and not use(crowded))) then
						return D2.new(1 / math.max(1, #use(visibleTabs)), -4, 0, height)
					end
					return if place == "sidebar" then D2.new(1, 0, 0, height) else D2.fromOffset(0, height)
				end,
				AutomaticSize = function(use: ComposeTypes.Use)
					local place = use(placement)
					return if place == "sidebar"
							or (string.find(place, "bottom") ~= nil and (stacked(use) or (fit and not use(crowded))))
						then E.AutomaticSize.None
						else E.AutomaticSize.X
				end,
				TextXAlignment = function(use: ComposeTypes.Use)
					return if use(placement) == "sidebar" and read(spec.railWidth, use) ~= nil
						then E.TextXAlignment.Left
						else E.TextXAlignment.Center
				end,
				TextTruncate = E.TextTruncate.AtEnd,
				enabled = function(use: ComposeTypes.Use): boolean
					return read(spec.enabled, use) ~= false and read(use(current).enabled, use) ~= false
				end,
				selected = function(use: ComposeTypes.Use)
					local indicator = indicatorOf(use)
					if not use(isCurrent(tab.id)) or indicator == "none" or indicator == "mark" then
						return false
					end
					local place = use(placement)
					return indicator == "pill" or place == "sidebar" or string.find(place, "bottom") ~= nil
				end,
				onActivate = function()
					select(tab.id)
				end,
			}
			button:AddTag("facet-tab-item")
			local content = button:FindFirstChild("Content")
			if content ~= nil and content:IsA("GuiObject") then
				content.AnchorPoint = ctx.types.Vector2.new(0.5, 0.5)
				content.Position = D2.fromScale(0.5, 0.5)
			end
			do
				local measure = ctx.text({
					Name = "LabelMeasure",
					Visible = false,
					TextWrapped = false,
					Text = function(use: ComposeTypes.Use): string
						return tostring(read(use(current).label, use) or tab.id)
					end,
					TextSize = function(use: ComposeTypes.Use): number
						local authored = if fit then nil else read(spec.textSize, use)
						return if type(authored) == "number"
							then authored
							else ctx.metric("typography.control.size", use)
					end,
				})
				surfaces.attach(button, { measure })
				local natural = textMeasure.natural(ctx, measure, function()
					local bounds = ctx.observe.TextBounds(measure)
					return Compose.formula(function(use: ComposeTypes.Use): Vector2
						return use(bounds) / use(layoutUnit)
					end)
				end)
				Compose.watch(function(use: ComposeTypes.Use)
					local width = use(natural).X * use(layoutUnit)
					if width == math.huge then
						return
					end
					local widths = table.clone(wordWidths:peek())
					widths[tab.id] = width
					wordWidths:set(widths)
				end)
				Compose.cleanup(function()
					local widths = table.clone(wordWidths:peek())
					widths[tab.id] = nil
					wordWidths:set(widths)
				end)
			end
			if fit then
				local measure = button:FindFirstChild("LabelMeasure") :: TextLabel
				local measured = textMeasure.natural(ctx, measure, function()
					local bounds = ctx.observe.TextBounds(measure)
					return Compose.formula(function(use: ComposeTypes.Use): Vector2
						return use(bounds) / use(layoutUnit)
					end)
				end)
				local natural = Compose.formula(function(use: ComposeTypes.Use): Vector2
					return use(measured) * use(layoutUnit)
				end)
				local room = ctx.observe.AbsoluteSize(button)
				local function budget(use: ComposeTypes.Use): (number, number, number, boolean)
					local width = use(natural).X
					local unit = use(layoutUnit)
					local glyphWidth = if not stacked(use) and (use(current).icon or use(current).glyph)
						then (ctx.controlSize(spec.controlSize, "iconSize", use) + ctx.metric("space.xs", use)) * unit
						else 0
					local padded = use(room).X
						- 2 * ctx.controlSize(spec.controlSize, "paddingX", use) * unit
						- glyphWidth
					local snug = use(room).X - glyphWidth - 2 * ctx.metric("space.xs", use) * unit
					local fitting = string.find(use(placement), "bottom") ~= nil and not use(crowded)
					return width, padded, snug, fitting
				end
				local tight = Compose.formula(function(use: ComposeTypes.Use): boolean
					local width, padded, _, fitting = budget(use)
					return fitting and width > 0 and padded > 0 and width > padded
				end)
				Compose.watch(function(use: ComposeTypes.Use)
					if use(tight) then
						button:AddTag("facet-button-tight")
					elseif button:HasTag("facet-button-tight") then
						button:RemoveTag("facet-button-tight")
					end
				end)
				local target = Compose.formula(function(use: ComposeTypes.Use): number?
					local width, padded, snug, fitting = budget(use)
					local available = if use(tight) then snug else padded
					if not fitting or width <= 0 or available <= 0 then
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
				local caption = button:FindFirstChild("Title", true)
				local title: TextLabel? = if caption and caption:IsA("TextLabel") then caption else nil
				Compose.watch(function(use: ComposeTypes.Use)
					local size = use(target)
					if size == nil then
						button:ResetPropertyToDefault("TextSize")
						if title then
							title:ResetPropertyToDefault("TextSize")
						end
						return
					end
					local smallest = ctx.metric("typography.caption.size", use)
					button.TextSize = math.max(smallest, size - use(drop))
					if title then
						title.TextSize = button.TextSize
					end
				end)
				local fits, drawn = ctx.observe.TextFits(title or button), ctx.observe.TextBounds(title or button)
				Compose.watch(function(use: ComposeTypes.Use)
					local whole, bounds = use(fits), use(drawn)
					local smallest = ctx.metric("typography.caption.size", use)
					if not whole and bounds.X > 0 and target:peek() ~= nil and button.TextSize > smallest then
						drop:set(drop:peek() + 1)
					end
				end)
				button:SetAttribute("FacetTextFit", true)
			end
			local leading = button:FindFirstChild(if tab.glyph then "LeadingGlyph" else "LeadingIcon", true)
			local glyph: GuiObject? = if leading and leading:IsA("GuiObject") then leading else nil
			if glyph and tab.glyph then
				glyph:AddTag("facet-tab-glyph")
			end
			local rowContent = button:FindFirstChild("Content")
			local flow = rowContent and rowContent:FindFirstChildWhichIsA("UIListLayout")
			local title = rowContent and rowContent:FindFirstChild("Title") :: TextLabel?
			if glyph and flow and title then
				local restGap = flow.Padding
				local contentWidth = ctx.observe.AbsoluteSize(rowContent :: GuiObject)
				runtime.decorate(flow, {
					FillDirection = function(use)
						return if stacked(use) then E.FillDirection.Vertical else E.FillDirection.Horizontal
					end,
					Padding = function(use)
						return if stacked(use) then D.new(0, iconGap(use)) else restGap
					end,
				})
				runtime.decorate(title, {
					Size = function(use: ComposeTypes.Use)
						if stacked(use) then
							return D2.new(1, 0, 0, labelLine(use))
						end
						if string.find(use(placement), "bottom") then
							local unit = use(layoutUnit)
							local room = use(contentWidth).X / unit
								- ctx.controlSize(spec.controlSize, "iconSize", use)
								- (flow:GetStyled("Padding") :: UDim).Offset
							local measured = use(wordWidths)[tab.id]
							local width = if measured and measured > 0
								then math.min(math.ceil(measured / unit), room)
								else room
							return D2.fromOffset(math.max(0, width), labelLine(use))
						end
						return D2.fromOffset(0, 0)
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if string.find(use(placement), "bottom")
							then E.AutomaticSize.None
							else E.AutomaticSize.XY
					end,
					TextXAlignment = E.TextXAlignment.Center,
					TextWrapped = false,
					TextTruncate = E.TextTruncate.AtEnd,
				})
			end
			local function badgeOf(use: ComposeTypes.Use): string?
				local badge = read(use(current).badge, use)
				return if badge == nil or badge == "" then nil else tostring(badge)
			end
			if tab.badge ~= nil and glyph then
				local icon = glyph :: GuiObject
				local corner = UI.badged(
					Host.Frame { Name = "Anchor", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) },
					badgeOf
				)
				local sealSize = Compose.cell(V2.zero)
				local iconBox, iconSize = ctx.observe.AbsoluteSize(icon), ctx.observe.Size(icon)
				local function reach(use: ComposeTypes.Use): (number, number, number)
					local seal, box = use(sealSize), use(iconBox).X
					local side = (use(iconSize) :: UDim2).X.Offset
					local ratio = if side > 0 and box > 0 then side / box else 1
					local lift = side * CORNER_OVERLAP
					return math.round(math.max(0, seal.X * ratio / 2 - lift)),
						math.round(math.max(0, seal.Y * ratio / 2 - lift)),
						ratio
				end
				runtime.decorate(corner, {
					Size = function(use: ComposeTypes.Use): UDim2
						local across, up = reach(use)
						return D2.new(1, across, 1, up)
					end,
					Position = function(use: ComposeTypes.Use): UDim2
						local across, up = reach(use)
						local anchor = readText(use(current).badgeAnchor, use) or "topTrailing"
						assert(
							table.find({ "topLeading", "topTrailing", "bottomLeading", "bottomTrailing" }, anchor),
							"Invalid TabView tab.badgeAnchor"
						)
						return D2.fromOffset(
							if string.find(anchor, "Leading") then -across else 0,
							if string.find(anchor, "bottom") then 0 else -up
						)
					end,
					AutomaticSize = E.AutomaticSize.None,
				})
				runtime.mount(function()
					return corner
				end, icon)
				local seal = corner:FindFirstChild("Seal")
				local holder = if seal then seal:FindFirstChild("Corner") else nil
				if holder then
					runtime.decorate(holder, {
						Position = function(use: ComposeTypes.Use): UDim2
							local anchor = readText(use(current).badgeAnchor, use) or "topTrailing"
							return D2.fromScale(
								if string.find(anchor, "Leading") then 0 else 1,
								if string.find(anchor, "bottom") then 1 else 0
							)
						end,
					})
					local tracked: RBXScriptConnection?
					local function track()
						if tracked then
							tracked:Disconnect()
						end
						local seal = holder:FindFirstChildWhichIsA("GuiObject")
						local function measure()
							sealSize:set(if seal and seal.Parent == holder then seal.AbsoluteSize else V2.zero)
						end
						tracked = if seal then seal:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure) else nil
						measure()
					end
					local added, removed = holder.ChildAdded:Connect(track), holder.ChildRemoved:Connect(track)
					track()
					Compose.cleanup(function()
						added:Disconnect()
						removed:Disconnect()
						if tracked then
							tracked:Disconnect()
						end
					end)
				end
				local flow = icon.Parent and icon.Parent:FindFirstChildWhichIsA("UIListLayout")
				Compose.watch(function(use: ComposeTypes.Use)
					local anchor = readText(use(current).badgeAnchor, use) or "topTrailing"
					local _, up, ratio = reach(use)
					local clearance = if string.find(anchor, "bottom")
						then up + use(sealSize).Y * ratio / 2 + ctx.metric("space.xs", use)
						else 0
					local values = badgeClearances:peek()
					if values[tab.id] ~= clearance then
						local nextValues = table.clone(values)
						nextValues[tab.id] = clearance
						badgeClearances:set(nextValues)
					end
				end)
				Compose.cleanup(function()
					local values = table.clone(badgeClearances:peek())
					values[tab.id] = nil
					badgeClearances:set(values)
				end)
				if flow then
					local gap = flow.Padding.Offset
					runtime.decorate(flow, {
						Padding = function(use: ComposeTypes.Use): UDim
							if stacked(use) then
								return D.new(0, iconGap(use))
							end
							local width = use(sealSize).X
							if width <= 0 or read(spec.iconOnly, use) then
								return D.new(0, gap)
							end
							local across, _, ratio = reach(use)
							local overhang = math.ceil(across + width * ratio / 2)
							return D.new(0, math.max(gap, overhang + ctx.metric("space.xs", use)))
						end,
					})
				end
			end
			local row = button:FindFirstChild("Content")
			if tab.badge ~= nil and not glyph and row then
				runtime.mountFragment(function()
					return {
						Compose.show(function(use: ComposeTypes.Use): boolean
							return badgeOf(use) ~= nil
						end, function()
							return UI.Badge {
								Name = "Count",
								LayoutOrder = 900,
								label = function(use: ComposeTypes.Use): string
									return badgeOf(use) or ""
								end,
							}
						end),
					}
				end, row)
			end
			local indicator = tab.indicator
			if indicator then
				surfaces.attach(button, {
					UI.StatusIndicator {
						Name = "Status",
						status = indicator.status,
						form = indicator.form,
						count = indicator.count,
						max = indicator.max,
						AnchorPoint = V2.new(1, 0),
						Position = D2.new(1, -4, 0, 4),
						ZIndex = 3,
					},
				})
			end
			local shownCurrent, shownFilled = false, false
			Compose.watch(function(use: ComposeTypes.Use)
				local current = use(isCurrent(tab.id))
				local place = use(placement)
				local filled = current
					and indicatorOf(use) ~= "none"
					and indicatorOf(use) ~= "mark"
					and (
						place == "sidebar"
						or string.find(place, "bottom") ~= nil
						or (spec.style == "sidebarAdaptable" and metrics.segmentedTop(use))
					)
				if current ~= shownCurrent then
					shownCurrent = current
					if current then
						button:AddTag("facet-tab-current")
					else
						button:RemoveTag("facet-tab-current")
					end
				end
				if filled ~= shownFilled then
					shownFilled = filled
					if filled then
						button:AddTag("facet-tab-filled")
					else
						button:RemoveTag("facet-tab-filled")
					end
				end
			end)
			surfaces.attach(button, {
				Host.UISizeConstraint {
					MinSize = function(use: ComposeTypes.Use)
						return V2.new(band(use), tabHeight(use))
					end,
				},
				Compose.show(function(use: ComposeTypes.Use): boolean
					return use(isCurrent(tab.id))
						and indicatorOf(use) == "mark"
						and (use(placement) == "sidebar" or string.find(use(placement), "bottom") ~= nil)
				end, function(): Instance
					local insetSelection = Compose.formula(function(use: ComposeTypes.Use): boolean
						local choice = read(spec.indicatorPlacement, use)
						assert(
							choice == nil or choice == "aboveIcon" or choice == "belowIcon" or choice == "inset",
							"Invalid TabView.indicatorPlacement"
						)
						return use(placement) == "sidebar" or choice == "inset" or glyph == nil
					end)
					local function buildMark(): Frame
						return ctx.styled(
							Host.Frame "SelectionIndicator" {
								BorderSizePixel = 0,
								ZIndex = button.ZIndex,
								AnchorPoint = function(use: ComposeTypes.Use): Vector2
									return if use(insetSelection)
										then V2.zero
										else V2.new(
											0.5,
											if read(spec.indicatorPlacement, use) == "belowIcon" then 0 else 1
										)
								end,
								Size = function(use: ComposeTypes.Use): UDim2
									return if use(insetSelection)
										then D2.new(
											1,
											-2 * ctx.metric("controls.tabRailSelection.insetX", use),
											1,
											-2 * ctx.metric("controls.tabRailSelection.insetY", use)
										)
										else D2.fromOffset(
											ctx.metric("controls.tabMark.width", use),
											ctx.metric("controls.tabMark.height", use)
										)
								end,
								Position = function(use: ComposeTypes.Use): UDim2
									return if use(insetSelection)
										then D2.fromOffset(
											ctx.metric("controls.tabRailSelection.insetX", use),
											ctx.metric("controls.tabRailSelection.insetY", use)
										)
										else if read(spec.indicatorPlacement, use) == "belowIcon"
											then D2.new(0.5, 0, 1, ctx.metric("controls.tabMark.gap", use))
											else D2.new(0.5, 0, 0, -ctx.metric("controls.tabMark.gap", use))
								end,
								Host.UICorner {
									CornerRadius = function(use: ComposeTypes.Use): UDim
										return D.new(
											0,
											ctx.metric(
												if use(insetSelection)
													then "controls.tabRailSelection.radius"
													else "controls.tabMark.radius",
												use
											)
										)
									end,
								},
							},
							"selection-indicator"
						)
					end
					return Host.Folder {
						Compose.keyed {
							from = function(use: ComposeTypes.Use): { GuiObject }
								return { if use(insetSelection) then button else assert(glyph) }
							end,
							render = function(target: ComposeTypes.ReadOnlyValue<GuiObject>): Instance
								return Host.Folder {
									Compose.portal(target:peek(), function()
										return { buildMark() }
									end),
								}
							end,
						},
					}
				end),
				Compose.show(function(use: ComposeTypes.Use)
					return indicatorOf(use) ~= "none" and indicatorOf(use) ~= "pill" and use(placement) == "topBar"
				end, function()
					return ctx.styled(
						Host.Frame "SelectionIndicator" {
							Visible = function(use: ComposeTypes.Use): boolean
								return use(isCurrent(tab.id))
							end,
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
			tabLinks:set(tabLinks:peek() + 1)
			Compose.cleanup(function()
				tabButtons[tab.id], tabMeasures[tab.id] = nil, nil
				tabLinks:set(tabLinks:peek() + 1)
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
						return if use(placement) == "sidebar" then D2.new(1, 0, 0, 0) else D2.fromOffset(0, band(use))
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if use(placement) == "sidebar" then E.AutomaticSize.Y else E.AutomaticSize.X
					end,
				})
			end
			return button
		end,
	})
end
