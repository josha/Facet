--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local segmentMetrics = require("./segment_metrics")
local NavigationProps = require("./navigation_props")
local tabMetrics = require("./nav_tab_metrics")

export type TabAccessoryView = {
	frame: tabMetrics.TabFrame,
	aboveHeight: ComposeTypes.Cell<number>,
	metrics: tabMetrics.TabMetrics,
}

return function(
	ctx: Types.Context,
	surfaces: Nav.Surfaces,
	spec: NavigationProps.TabViewSpec,
	root: Frame,
	view: TabAccessoryView
): ()
	local Host, Compose, runtime = ctx.Host, ctx.Compose, ctx.runtime
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local INSET = segmentMetrics.inset
	local frame = view.frame
	local placement, headHeight, footHeight, trailingWidth =
		frame.placement, frame.headHeight, frame.footHeight, frame.trailingWidth
	local aboveHeight = view.aboveHeight
	local metrics = view.metrics
	local band, bottomInset = metrics.band, metrics.bottomInset
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
								then D2.fromOffset(metrics.railWidth(use), 0)
								elseif slot == "trailing" then D2.fromOffset(0, band(use))
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
								return D2.new(0, 0, 1, -band(use) - bottomInset(use) - use(aboveHeight))
							end
							return D2.new(
								1,
								-use(trailingWidth),
								if place == "topBar" then 0 else 1,
								if metrics.segmentedTop(use)
									then INSET
									elseif place == "topBar" then 0
									else -band(use) - bottomInset(use)
							)
						end,
					})
					return accessory
				end,
			}),
		})
	end
end
