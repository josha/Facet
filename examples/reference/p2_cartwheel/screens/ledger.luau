--!strict
-- THE LEDGER — the history chart, its lock, and the two-state upsell (§12).
--
-- THE LOCK IS AN UNMOUNT, NOT A FADE (declared correction, spec §12). The
-- capability ledger's sketch was "draw the series at zero opacity under a
-- badge"; `UI.Path` has no per-path transparency at all (an engine limit stated
-- in api.md), so an opacity lock would have been a lock that never locked. On a
-- gated, unentitled timeframe the series Paths are simply NOT MOUNTED — axes,
-- ticks and legend stay, a scrim and a lock chip cover the plot. Same
-- information shape, honest mechanism, and nothing paints that should not.
local data = require("../content/data")
local parts = require("./parts")

local ledger = {}

local GATED = { month = true, year = true }
local SERIES_ROLES = { "accent", "content", "secondary" }

function ledger.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local Facet = app.Facet
	local stats = app.services.stats
	local entitlement = app.services.entitlement

	local self: any = {}
	local timeframe = core:signal("twoWeeks")
	local upsellCollapsed = core:signal(false)
	self.timeframe = timeframe
	self.upsellCollapsed = upsellCollapsed

	local entitled = entitlement.fullLedger
	local locked = core:memo(function(use)
		return GATED[use(timeframe)] == true and not use(entitled)
	end)
	local unlocked = core:memo(function(use)
		return not use(locked)
	end)
	local showUpsell = core:memo(function(use)
		return not use(entitled)
	end)
	local upsellExpanded = core:memo(function(use)
		return use(showUpsell) and not use(upsellCollapsed)
	end)
	local upsellRow = core:memo(function(use)
		return use(showUpsell) and use(upsellCollapsed)
	end)
	self.locked = locked

	-- locked options SIGNAL BEFORE THE TAP: the label says so while the
	-- entitlement is absent, so nothing is discovered by being refused
	local optionLabels: { any } = {}
	for _, entry in { { "twoWeeks", "time.twoWeeks" }, { "month", "time.month" }, { "year", "time.year" } } do
		local key = entry[1] :: string
		local labelKey = entry[2] :: string
		if GATED[key] then
			table.insert(optionLabels, { value = key, label = S.t("ledger.lockedOption", { name = S.t(labelKey) }) })
		else
			table.insert(optionLabels, { value = key, label = S.t(labelKey) })
		end
	end

	local picker = Facet.Controls.Picker(core, {
		id = "Timeframe",
		options = optionLabels,
		selected = timeframe,
		sizeClass = app.state.sizeClass,
	})

	-- ---- the plot ------------------------------------------------------------

	local seriesMemos: { any } = {}
	local seriesPaths: { any } = {}
	for index, plaza in data.plazas :: any do
		local points = core:memo(function(use)
			return parts.polyline(stats.series(plaza.id, use(timeframe)))
		end)
		table.insert(seriesMemos, points)
		table.insert(
			seriesPaths,
			UI.Path({
				id = "Series" .. index,
				points = points,
				role = SERIES_ROLES[index] or "content",
				thickness = "controls.table.indicatorThickness",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
			})
		)
	end

	local gridLines: { any } = {}
	for line = 0, 3 do
		table.insert(
			gridLines,
			UI.Box({
				id = "Grid" .. line,
				surface = "base",
				anchor = "topLeft",
				offsetY = { scale = line / 4 },
				width = { type = "percent", fraction = 1 },
				height = { type = "fixed", px = "strokes.hairline" },
			})
		)
	end

	local axisCaptions: { any } = {}
	-- the LAST tick is suppressed: it would sit on the plot's own edge
	for tick = 0, 2 do
		table.insert(
			axisCaptions,
			UI.Text({
				id = "Tick" .. tick,
				text = tostring(100 - tick * 25),
				textSize = "caption",
				role = "secondary",
				lineLimit = 1,
			})
		)
	end

	local legendChips: { any } = {}
	for index, plaza in data.plazas :: any do
		table.insert(legendChips, parts.chip(app, "Legend" .. index, plaza.name))
	end

	local plot = UI.ZStack({
		id = "Plot",
		width = { type = "fill", weight = 1 },
		height = { type = "fixed", px = "app.cartwheel.chartH" },
		children = {
			UI.Anchor({
				id = "Grid",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = gridLines,
			}),
			UI.When({
				id = "SeriesWhen",
				condition = unlocked,
				thenView = function()
					return UI.ZStack({
						id = "Series",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = seriesPaths,
					})
				end,
			}),
			UI.When({
				id = "LockWhen",
				condition = locked,
				thenView = function()
					return UI.ZStack({
						id = "Lock",
						canvasGroup = true,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						alignH = "center",
						alignV = "center",
						children = {
							UI.Box({
								id = "Scrim",
								surface = "scrim",
								width = { type = "fill", weight = 1 },
								height = { type = "fill", weight = 1 },
							}),
							parts.chip(app, "Badge", S.t("ledger.locked")),
						},
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
		},
	})

	-- ---- the two-state upsell ------------------------------------------------

	local unlockPending = core:memo(function(use)
		return use(app.commands.status("purchase:ledger")) == "pending"
	end)
	local unlockIdle = core:memo(function(use)
		return not use(unlockPending)
	end)

	local function unlock()
		app.actions.purchase("ledger")
	end

	local upsell = UI.VStack({
		id = "Upsell",
		gap = "s",
		width = { type = "fill", weight = 1 },
		children = {
			UI.When({
				id = "ExpandedWhen",
				condition = upsellExpanded,
				thenView = function()
					return UI.ZStack({
						id = "ExpandedHost",
						canvasGroup = true,
						width = { type = "fill", weight = 1 },
						height = { type = "content" },
						children = {
							parts.card(app, {
								id = "Expanded",
								children = {
									UI.HStack({
										id = "Head",
										gap = "s",
										align = "center",
										width = { type = "fill", weight = 1 },
										children = {
											-- the heading TAKES the slack rather than a
											-- spacer beside it: a fixed-width heading plus a
											-- 44px disc overflowed a phone-width card by 7px
											UI.Text({
												id = "Heading",
												text = S.t("ledger.unlockTitle"),
												textSize = "heading",
												width = { type = "fill", weight = 1 },
												lineLimit = 2,
												disclose = true,
											}),
											UI.Button({
												id = "Dismiss",
												label = S.t("ledger.close"),
												shape = "circle",
												icon = "close",
												onActivate = function()
													upsellCollapsed:set(true)
												end,
											}),
										},
									}),
									UI.Text({
										id = "Body",
										text = S.t("ledger.unlockBody"),
										textSize = "body",
										role = "secondary",
									}),
									UI.Button({
										id = "Unlock",
										label = S.t("ledger.unlock"),
										surface = "accent",
										enabled = unlockIdle,
										onActivate = unlock,
									}),
								},
							}),
						},
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
			UI.When({
				id = "RowWhen",
				condition = upsellRow,
				thenView = function()
					return UI.ZStack({
						id = "RowHost",
						canvasGroup = true,
						width = { type = "fill", weight = 1 },
						height = { type = "content" },
						children = {
							UI.HStack({
								id = "Row",
								gap = "s",
								align = "center",
								width = { type = "fill", weight = 1 },
								children = {
									UI.Text({
										id = "Line",
										text = S.t("ledger.unlockRow", { credits = data.fullLedgerCredits }),
										textSize = "caption",
										role = "secondary",
										lineLimit = 2,
										disclose = true,
									}),
									UI.Spacer({ id = "Gap", width = { type = "fill", weight = 1 } }),
									UI.Button({
										id = "Unlock",
										label = S.t("ledger.unlock"),
										enabled = unlockIdle,
										onActivate = unlock,
									}),
								},
							}),
						},
					})
				end,
				transition = { enter = "fade", class = "container" },
			}),
			UI.When({
				id = "WorkingWhen",
				condition = unlockPending,
				thenView = function()
					return parts.chip(app, "Working", S.t("command.working"))
				end,
			}),
		},
	})

	local page = UI.ScrollView({
		id = "Ledger",
		axis = "y",
		gap = "m",
		padding = "m",
		width = { type = "fill", weight = 1 },
		height = { type = "fill", weight = 1 },
		children = {
			UI.Text({ id = "Title", text = S.t("ledger.title"), textSize = "title" }),
			picker.blueprint,
			UI.HStack({
				id = "Chart",
				gap = "s",
				align = "start",
				width = { type = "fill", weight = 1 },
				children = {
					UI.VStack({ id = "Axis", gap = "m", children = axisCaptions }),
					UI.VStack({
						id = "PlotHost",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = {
							plot,
							-- a chart legend is plaza NAMES, so its chips are ragged by
							-- nature; the uniform grid this used to be gave all three the
							-- widest name's width (135x23 each, measured 1440x900) and left
							-- a dead third cell on the second row
							UI.HStack({
								id = "Legend",
								wrap = true,
								gap = "xs",
								children = legendChips,
							}),
						},
					}),
				},
			}),
			upsell,
		},
	})

	function self.view(): any
		return page
	end

	function self.dump(): any
		return {
			timeframe = timeframe:get(),
			locked = locked:get(),
			entitled = entitled:get(),
			upsell = if not showUpsell:get() then "none" elseif upsellCollapsed:get() then "row" else "expanded",
			series = #seriesPaths,
		}
	end

	function self.dispose()
		picker.dispose()
		unlockIdle:dispose()
		unlockPending:dispose()
		for _, memo in seriesMemos do
			memo:dispose()
		end
		upsellRow:dispose()
		upsellExpanded:dispose()
		showUpsell:dispose()
		unlocked:dispose()
		locked:dispose()
		upsellCollapsed:dispose()
		timeframe:dispose()
	end

	return self
end

return ledger
