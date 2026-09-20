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
	local Compose = app.Compose
	local S = app.S
	local Facet = app.Facet
	local stats = app.services.stats

	local self: any = {}
	local timeframe = Compose.cell("today")
	self.timeframe = timeframe

	local rows = Compose.formula(function(use)
		use(stats.version)
		return stats.topFive(use(timeframe))
	end)
	self.rows = rows

	local total = app.motionClock:counter(0, "object")
	Compose.cleanup(function()
		total:dispose()
	end)
	local function retarget()
		total:setTarget(stats.totalBottles(timeframe:peek()))
	end
	retarget()
	local unsubscribes = {
		app.observe(timeframe, retarget),
		app.observe(stats.version, retarget),
	}

	local totalText = Compose.formula(function(use)
		return tostring(use(total))
	end)

	-- The page is built per visit: a node belongs to the mount that made it.
	local function buildPage(): any
		local picker = UI.Picker("Timeframe")({
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
			local row = Compose.formula(function(use)
				return (use(rows) :: any)[slot]
			end)
			table.insert(memos, row)
			local barWeight = Compose.formula(function(use)
				local list = use(rows) :: any
				local peak = if list[1] == nil then 1 else math.max(1, list[1].bottles)
				local entry = list[slot]
				local value = if entry == nil then 0 else entry.bottles
				return UI.fill(math.max(0.001, value / peak))
			end)
			table.insert(memos, barWeight)
			local slackWeight = Compose.formula(function(use)
				local list = use(rows) :: any
				local peak = if list[1] == nil then 1 else math.max(1, list[1].bottles)
				local entry = list[slot]
				local value = if entry == nil then 0 else entry.bottles
				return UI.fill(math.max(0.001, 1 - value / peak))
			end)
			table.insert(memos, slackWeight)
			local valueText = Compose.formula(function(use)
				local entry = (use(rows) :: any)[slot]
				return if entry == nil then "0" else tostring(entry.bottles)
			end)
			table.insert(memos, valueText)
			local nameText = Compose.formula(function(use)
				local entry = (use(rows) :: any)[slot]
				return if entry == nil then "" else entry.potion.name
			end)
			table.insert(memos, nameText)
			local markImage = Compose.formula(function(use)
				local entry = (use(rows) :: any)[slot]
				return if entry == nil then app.art.marks.menu.image else entry.potion.mark.image
			end)
			table.insert(memos, markImage)
			local markTint = Compose.formula(function(use)
				local entry = (use(rows) :: any)[slot]
				return if entry == nil then { role = "contentSecondary", blend = 1 } else { direct = entry.potion.hue }
			end)
			table.insert(memos, markTint)

			local column = UI.Box("Bar")({
				surface = "accent",
				width = UI.fill(),
				height = barWeight,
			})
			column = UI.corners(column, "control")
			column = UI.gradient(column, { colors = { "control", "accent" }, rotation = 90 })

			table.insert(
				cells,
				UI.VStack("Cell" .. slot)({
					gap = "xs",
					align = "center",
					width = UI.fill(),
					height = UI.fill(),

					parts.badge(app, "Value", valueText),
					UI.Spacer("Slack")({ height = slackWeight, width = UI.fill() }),
					column,
					UI.Image("Mark")({
						image = markImage,
						scaleMode = "fit",
						tint = markTint,
						width = { type = "fixed", px = "iconSizes.medium" },
						height = { type = "fixed", px = "iconSizes.medium" },
					}),
					UI.Text("Name")({
						text = nameText,
						textSize = "caption",
						textAlign = "center",
						lineLimit = 2,
						disclose = true,
					}),
				})
			)
		end

		local page = UI.ScrollView("TopFive")({
			axis = "y",
			gap = "m",
			padding = "m",
			width = UI.fill(),
			height = UI.fill(),

			UI.Text("Title")({ text = S.t("top.title"), textSize = "title" }),
			picker,
			UI.HStack("Summary")({
				gap = "s",
				align = "center",

				UI.Text("Label")({ text = S.t("top.totalBottles"), textSize = "caption", role = "secondary" }),
				UI.Text("Count")({ text = totalText, textSize = "heading" }),
			}),
			UI.HStack("Chart")(app.withChildren({
				gap = "s",
				align = "end",
				width = UI.fill(),
				height = { type = "fixed", px = "app.cartwheel.chartH" },
			}, cells)),
		})

		return page
	end

	self.view = buildPage

	function self.dump(): any
		local out: { any } = {}
		for _, entry in rows:peek() :: any do
			table.insert(out, { id = entry.potion.id, bottles = entry.bottles })
		end
		return { timeframe = timeframe:peek(), rows = out, total = stats.totalBottles(timeframe:peek()) }
	end

	return self
end

return topfive
