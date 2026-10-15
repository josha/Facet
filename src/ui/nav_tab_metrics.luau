--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local segmentMetrics = require("./segment_metrics")
local NavigationProps = require("./navigation_props")

export type TabFrame = {
	fit: boolean,
	placement: ComposeTypes.Formula<string>,
	visibleTabs: ComposeTypes.Formula<{ Nav.Tab }>,
	dimensions: ComposeTypes.Readable<Vector2>,
	layoutUnit: ComposeTypes.Readable<number>,
	headHeight: ComposeTypes.Cell<number>,
	footHeight: ComposeTypes.Cell<number>,
	trailingWidth: ComposeTypes.Cell<number>,
	indicatorOf: (ComposeTypes.Use) -> Nav.TabSelectionIndicator?,
}

export type TabMetrics = {
	wordWidths: ComposeTypes.Cell<{ [string]: number }>,
	barExtent: ComposeTypes.Cell<Vector2>,
	stacked: (ComposeTypes.Use?) -> boolean,
	crowded: ComposeTypes.Formula<boolean>,
	labelLine: (ComposeTypes.Use?) -> number,
	floating: (ComposeTypes.Use?) -> boolean,
	bottomInset: (ComposeTypes.Use?) -> number,
	contentGap: (ComposeTypes.Use) -> number,
	badgeClearances: ComposeTypes.Cell<{ [string]: number }>,
	iconGap: (ComposeTypes.Use?) -> number,
	band: (ComposeTypes.Use?) -> number,
	tabHeight: (ComposeTypes.Use?) -> number,
	segmentedTop: (ComposeTypes.Use) -> boolean,
	plated: (ComposeTypes.Use) -> boolean,
	inset: (ComposeTypes.Use) -> UDim,
	stripOverflows: ComposeTypes.Cell<boolean>,
	stripLayout: UIListLayout,
	stripContent: ComposeTypes.Cell<Vector2>,
	railWidth: (ComposeTypes.Use) -> number,
	segmentWidth: (ComposeTypes.Use) -> (number, number),
	floatingSize: (ComposeTypes.Use) -> UDim2,
	floatingPosition: (ComposeTypes.Use) -> UDim2,
}

return function(ctx: Types.Context, spec: NavigationProps.TabViewSpec, view: TabFrame): TabMetrics
	local Host, Compose, read = ctx.Host, ctx.Compose, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local fit, placement, visibleTabs = view.fit, view.placement, view.visibleTabs
	local dimensions, layoutUnit, indicatorOf = view.dimensions, view.layoutUnit, view.indicatorOf
	local headHeight, footHeight, trailingWidth = view.headHeight, view.footHeight, view.trailingWidth
	local wordWidths: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
	local barExtent: ComposeTypes.Cell<Vector2> = Compose.cell(V2.zero)
	local function stacked(use: ComposeTypes.Use?): boolean
		local choice = read(spec.labelPlacement, use)
		return not read(spec.iconOnly, use)
			and string.find(read(placement, use), "bottom") ~= nil
			and choice == "belowIcon"
	end
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
	local function labelLine(use: ComposeTypes.Use?): number
		local authored = if fit then nil else read(spec.textSize, use)
		local size = if type(authored) == "number" then authored else ctx.metric("typography.control.size", use)
		return math.ceil(size * ctx.metric("typography.control.lineHeight", use))
	end
	local function floating(use: ComposeTypes.Use?): boolean
		local choice = read(spec.track, use)
		assert(choice == nil or choice == "automatic" or choice == "floating", "Invalid TabView.track")
		local place = read(placement, use)
		return choice == "floating" and (place == "sidebar" or string.find(place, "bottom") ~= nil)
	end
	local function bottomInset(use: ComposeTypes.Use?): number
		return if floating(use) and read(placement, use) ~= "sidebar"
			then ctx.metric("controls.tabBottomTrack.bottomInset", use)
			else 0
	end
	local function contentGap(use: ComposeTypes.Use): number
		return if floating(use) then ctx.metric("controls.tabBottomTrack.contentGap", use) else 8
	end
	local badgeClearances = Compose.cell({} :: { [string]: number })
	local function iconGap(use: ComposeTypes.Use?): number
		local gap = ctx.metric("space.xs", use)
		if read(spec.indicator, use) == "mark" and read(spec.indicatorPlacement, use) == "belowIcon" then
			gap =
				math.max(gap, ctx.metric("controls.tabMark.height", use) + 2 * ctx.metric("controls.tabMark.gap", use))
		end
		local clearances: { [string]: number } = if use then use(badgeClearances) else badgeClearances:peek()
		for _, clearance in clearances do
			gap = math.max(gap, clearance)
		end
		return gap
	end
	local function band(use: ComposeTypes.Use?): number
		local minimum = ctx.metric("targetSizes.minimum", use)
		if floating(use) and read(placement, use) ~= "sidebar" then
			minimum = math.max(minimum, ctx.metric("controls.tabBottomTrack.height", use))
		end
		return if stacked(use)
			then math.max(
				minimum,
				ctx.controlSize(spec.controlSize, "iconSize", use)
					+ labelLine(use)
					+ iconGap(use)
					+ math.max(
						0,
						ctx.controlSize(spec.controlSize, "height", use)
							- ctx.controlSize(spec.controlSize, "iconSize", use),
						if read(spec.indicator, use) == "mark"
							then 2 * (ctx.metric("controls.tabMark.height", use) + ctx.metric(
								"controls.tabMark.gap",
								use
							))
							else 0
					)
			)
			else minimum
	end
	local function tabHeight(use: ComposeTypes.Use?): number
		return if spec.controlSize == nil
				or stacked(use)
				or (floating(use) and read(placement, use) ~= "sidebar")
			then band(use)
			else ctx.controlSize(spec.controlSize, "height", use)
	end
	local INSET = segmentMetrics.inset
	local function segmentedTop(use: ComposeTypes.Use): boolean
		return use(placement) == "topBar" and indicatorOf(use) == "pill"
	end
	local function plated(use: ComposeTypes.Use): boolean
		return indicatorOf(use) == "pill" and (use(placement) == "topBar" or use(placement) == "sidebar")
	end
	local function inset(use: ComposeTypes.Use): UDim
		return D.new(0, if plated(use) then INSET else 0)
	end
	local stripOverflows = Compose.cell(false)
	local stripLayout = Host.UIListLayout({
		FillDirection = function(use: ComposeTypes.Use)
			return if use(placement) == "sidebar" then E.FillDirection.Vertical else E.FillDirection.Horizontal
		end,
		SortOrder = E.SortOrder.LayoutOrder,
		HorizontalAlignment = function(use: ComposeTypes.Use)
			return if use(stripOverflows) then E.HorizontalAlignment.Left else E.HorizontalAlignment.Center
		end,
		VerticalAlignment = function(use: ComposeTypes.Use)
			return if use(placement) == "sidebar" then E.VerticalAlignment.Top else E.VerticalAlignment.Center
		end,
		Padding = D.new(0, 4),
	})
	local stripContent = ctx.observe.AbsoluteContentSize(stripLayout)
	local function railWidth(use: ComposeTypes.Use): number
		local authored = read(spec.railWidth, use)
		if authored then
			return authored
		end
		local widest = 0
		for _, width in use(wordWidths) do
			widest = math.max(widest, width)
		end
		if widest <= 0 then
			return math.clamp(math.floor(use(dimensions).X * 0.2), 200, 280)
		end
		local unit = use(layoutUnit)
		local glyph = 0
		for _, tab in use(visibleTabs) do
			if tab.icon then
				glyph = ctx.controlSize(spec.controlSize, "iconSize", use) + ctx.metric("space.xs", use)
				break
			end
		end
		local label = widest / (if unit > 0 then unit else 1)
		local plate = if indicatorOf(use) == "pill" then 2 * INSET else 0
		local package = read(ctx.config.theme, use)
		local skin = package and package.chrome and package.chrome.control
		local insets = if skin then skin.contentInsets else nil
		local carve = if insets then (insets.left or 0) + (insets.right or 0) else 0
		return math.ceil(label + glyph + 2 * ctx.controlSize(spec.controlSize, "paddingX", use) + carve) + 16 + plate
	end
	local function segmentWidth(use: ComposeTypes.Use): (number, number)
		local unit = use(layoutUnit)
		local scale = if unit > 0 then unit else 1
		local room = use(dimensions).X - use(trailingWidth) / scale
		local width = math.ceil(math.min(room, use(stripContent).X / scale + 2 * INSET))
		return width, math.max(0, math.floor((room - width) / 2))
	end
	local function floatingSize(use: ComposeTypes.Use): UDim2
		return if use(placement) == "sidebar"
			then D2.new(
				0,
				railWidth(use) - 2 * ctx.metric("controls.tabRailTrack.sideInset", use),
				1,
				-use(headHeight)
					- use(footHeight)
					- ctx.metric("controls.tabRailTrack.topInset", use)
					- ctx.metric("controls.tabRailTrack.bottomInset", use)
			)
			else D2.new(
				1,
				-2 * ctx.metric("controls.tabBottomTrack.sideInset", use) - use(trailingWidth),
				0,
				band(use)
			)
	end
	local function floatingPosition(use: ComposeTypes.Use): UDim2
		return if use(placement) == "sidebar"
			then D2.fromOffset(
				ctx.metric("controls.tabRailTrack.sideInset", use),
				use(headHeight) + ctx.metric("controls.tabRailTrack.topInset", use)
			)
			else D2.new(0, ctx.metric("controls.tabBottomTrack.sideInset", use), 1, -band(use) - bottomInset(use))
	end
	return {
		wordWidths = wordWidths,
		barExtent = barExtent,
		stacked = stacked,
		crowded = crowded,
		labelLine = labelLine,
		floating = floating,
		bottomInset = bottomInset,
		contentGap = contentGap,
		badgeClearances = badgeClearances,
		iconGap = iconGap,
		band = band,
		tabHeight = tabHeight,
		segmentedTop = segmentedTop,
		plated = plated,
		inset = inset,
		stripOverflows = stripOverflows,
		stripLayout = stripLayout,
		stripContent = stripContent,
		railWidth = railWidth,
		segmentWidth = segmentWidth,
		floatingSize = floatingSize,
		floatingPosition = floatingPosition,
	}
end
