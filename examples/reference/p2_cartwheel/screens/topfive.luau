--!strict
-- TOP FIVE — the bar chart with image-under-axis labels (spec §10).
--
-- Bars are `Box` columns whose height is a FILL WEIGHT, not a pixel count: the
-- column and the slack above it share the plot by weight, so the chart reflows
-- with its container and a value change is an arrange pass. Two lines are
-- reserved under every bar for the potion name, so a longer name (or a raised
-- type scale, or the pseudo-locale) cannot make the bars jitter.
--
-- Read-only, and the cells are not focusable: there is nothing here to do.
local parts = require("./parts")

local topfive = {}

function topfive.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local Facet = app.Facet
	local stats = app.services.stats

	local self: any = {}
	local timeframe = core:signal("today")
	self.timeframe = timeframe

	local rows = core:memo(function(use)
		use(stats.version)
		return stats.topFive(use(timeframe))
	end)
	self.rows = rows

	local total = app.motionClock:counter(0, "object")
	local function retarget()
		total:setTarget(stats.totalBottles(timeframe:get()))
	end
	retarget()
	local unsubscribes = {
		core:observe(timeframe, retarget),
		core:observe(stats.version, retarget),
	}

	local totalText = core:memo(function(use)
		return tostring(use(total))
	end)

	local picker = Facet.Controls.Picker(core, {
		id = "Timeframe",
		options = {
			{ value = "today", label = S.t("time.day") },
			{ value = "week", label = S.t("time.week") },
			{ value = "month", label = S.t("time.month") },
			{ value = "year", label = S.t("time.year") },
		},
		selected = timeframe,
		sizeClass = app.state.sizeClass,
	})

	local memos: { any } = {}
	local cells: { any } = {}
	for slot = 1, 5 do
		local row = core:memo(function(use)
			return (use(rows) :: any)[slot]
		end)
		table.insert(memos, row)
		local barWeight = core:memo(function(use)
			local list = use(rows) :: any
			local peak = if list[1] == nil then 1 else math.max(1, list[1].bottles)
			local entry = list[slot]
			local value = if entry == nil then 0 else entry.bottles
			return { type = "fill", weight = math.max(0.001, value / peak) }
		end)
		table.insert(memos, barWeight)
		local slackWeight = core:memo(function(use)
			local list = use(rows) :: any
			local peak = if list[1] == nil then 1 else math.max(1, list[1].bottles)
			local entry = list[slot]
			local value = if entry == nil then 0 else entry.bottles
			return { type = "fill", weight = math.max(0.001, 1 - value / peak) }
		end)
		table.insert(memos, slackWeight)
		local valueText = core:memo(function(use)
			local entry = (use(rows) :: any)[slot]
			return if entry == nil then "0" else tostring(entry.bottles)
		end)
		table.insert(memos, valueText)
		local nameText = core:memo(function(use)
			local entry = (use(rows) :: any)[slot]
			return if entry == nil then "" else entry.potion.name
		end)
		table.insert(memos, nameText)
		local markImage = core:memo(function(use)
			local entry = (use(rows) :: any)[slot]
			return if entry == nil then app.art.marks.menu.image else entry.potion.mark.image
		end)
		table.insert(memos, markImage)
		local markTint = core:memo(function(use)
			local entry = (use(rows) :: any)[slot]
			return if entry == nil then { role = "contentSecondary", blend = 1 } else { direct = entry.potion.hue }
		end)
		table.insert(memos, markTint)

		local column = UI.Box({
			id = "Bar",
			surface = "accent",
			width = { type = "fill", weight = 1 },
			height = barWeight,
		})
		column = UI.corners(column, "control")
		column = UI.gradient(column, { colors = { "control", "accent" }, rotation = 90 })

		table.insert(
			cells,
			UI.VStack({
				id = "Cell" .. slot,
				gap = "xs",
				align = "center",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					parts.badge(app, "Value", valueText),
					UI.Spacer({ id = "Slack", height = slackWeight, width = { type = "fill", weight = 1 } }),
					column,
					UI.Image({
						id = "Mark",
						image = markImage,
						scaleMode = "fit",
						tint = markTint,
						width = { type = "fixed", px = "iconSizes.medium" },
						height = { type = "fixed", px = "iconSizes.medium" },
					}),
					UI.Text({
						id = "Name",
						text = nameText,
						textSize = "caption",
						textAlign = "center",
						lineLimit = 2,
						disclose = true,
					}),
				},
			})
		)
	end

	local page = UI.ScrollView({
		id = "TopFive",
		axis = "y",
		gap = "m",
		padding = "m",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Text({ id = "Title", text = S.t("top.title"), textSize = "title" }),
			picker.blueprint,
			UI.HStack({
				id = "Summary",
				gap = "s",
				align = "center",
				children = {
					UI.Text({ id = "Label", text = S.t("top.totalBottles"), textSize = "caption", role = "secondary" }),
					UI.Text({ id = "Count", text = totalText, textSize = "heading" }),
				},
			}),
			UI.HStack({
				id = "Chart",
				gap = "s",
				align = "end",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = "app.cartwheel.chartH" },
				children = cells,
			}),
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		local out: { any } = {}
		for _, entry in rows:get() :: any do
			table.insert(out, { id = entry.potion.id, bottles = entry.bottles })
		end
		return { timeframe = timeframe:get(), rows = out, total = stats.totalBottles(timeframe:get()) }
	end

	function self.dispose()
		for _, unsubscribe in unsubscribes do
			unsubscribe()
		end
		picker.dispose()
		total:dispose()
		totalText:dispose()
		for _, memo in memos do
			memo:dispose()
		end
		rows:dispose()
		timeframe:dispose()
	end

	return self
end

return topfive
