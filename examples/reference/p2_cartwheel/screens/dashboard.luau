--!strict
-- THE CART — the dashboard (spec §5).
--
-- Eye order: hero band, then the newest brew, then the three glance cards. One
-- scroller (invariant 4). Four cards in a `Composition` that is legal at two
-- lanes only while each lane clears `cardMin` AND every card region's `floor`
-- resolves against the LIVE theme — which is what makes a raised type scale flip
-- the grid to one column with no branch on the text fact (ledger §C row 2).
local data = require("../content/data")
local parts = require("./parts")

local dashboard = {}

local RACK_ROWS = { 5, 4, 5 }

function dashboard.new(app: any): any
	local UI = app.UI
	local core = app.core
	local S = app.S
	local orders = app.services.orders
	local ambient = app.services.ambient

	local self: any = {}

	-- ---- the five newest brews, keyed ---------------------------------------
	local recent = core:memo(function(use)
		local out: { any } = {}
		for _, brew in use(orders.brews) :: any do
			table.insert(out, brew)
			if #out >= 5 then
				break
			end
		end
		return out
	end)
	local heroItems = core:memo(function(use)
		local first = (use(recent) :: any)[1]
		return if first == nil then {} else { first }
	end)
	local tileItems = core:memo(function(use)
		local out: { any } = {}
		local list = use(recent) :: any
		for index = 2, #list do
			table.insert(out, list[index])
		end
		return out
	end)

	-- ---- the numeric pulse (spec §5, §18) -----------------------------------
	-- A counter publishes WHOLE numbers and never overshoots a quantity, so the
	-- tally counts up to the new brew's bottles instead of flickering past it.
	-- Reduced motion places the final count and fires the same settle event —
	-- the role flip is what carries the emphasis there, and it is not motion.
	local tally = app.motionClock:counter(0, "reward")
	local tallyRole = core:signal("secondary")
	local pulse = app.motionClock:spring(0, "reward")
	self.tally = tally

	local function retarget()
		local first = (recent:get() :: any)[1]
		if first == nil then
			return
		end
		tally:setTarget(first.bottles)
	end
	retarget()

	orders.onArrival(function()
		tallyRole:set("content")
		retarget()
		pulse:setTarget(1)
	end)
	tally:onSettle(function()
		tallyRole:set("secondary")
		pulse:setTarget(0)
	end)

	--[[ the presentation-channel half of the pulse: a scale nudge on the footer,
		DECLARED on the node rather than written at it.

		This used to be an `app.onTick` calling `setPresentationTransform` every
		frame — including the resting frames, where it wrote `nil` over and over.
		`scale` is a reactive prop on every rendered class (blueprint_schema), it is
		paint-only (the solver never sees it, so the box, the hit target and the
		focus order are the unscaled ones), and it MULTIPLIES with any scale the
		framework is applying — which is exactly what a nudge on top of a press dip
		wants. A MotionValue IS a `Readable<number>`, so one memo over the spring is
		the whole binding.

		`celebration.luau` next door is still imperative and correctly so: it moves
		a TRANSLATION, and `offset` takes numbers rather than Readables, so it has
		no declarative twin to reach for. That is the difference worth copying —
		reach for the write when there is no prop, not because a sibling did. ]]
	local tallyScale = app.scope:own(core:memo(function(use)
		return 1 + 0.06 * use(pulse)
	end))

	local tallyText = core:memo(function(use)
		local first = (use(recent) :: any)[1]
		if first == nil then
			return S.t("brews.empty")
		end
		return S.t("cart.tally", { id = first.id, bottles = use(tally) })
	end)

	-- ---- the parallax header (spec §5, §18) ---------------------------------
	-- Four tinted layers on fractional Anchor offsets, each on its own long
	-- `decay` spring with a LIVE target read off the domain clock, plus a
	-- four-frame flipbook for the cart itself. Reduced motion aims nothing and
	-- parks the flipbook on frame 1, so every layer is still.
	local reduced = app.reducedMotion
	local layerSprings: { any } = {}
	local LAYER_PERIODS = { 37, 23, 17, 11 }
	local LAYER_TRAVEL = { 0.02, 0.05, 0.09, 0.16 }
	for index = 1, 4 do
		local spring = app.motionClock:spring(0, "decay")
		layerSprings[index] = spring
		if not reduced:get() then
			spring:setTarget(function()
				local period = LAYER_PERIODS[index]
				return math.sin(app.clock.now() * (2 * math.pi / period)) * LAYER_TRAVEL[index]
			end)
		end
	end
	local flipFrame = core:memo(function(use)
		if use(reduced) then
			return 1
		end
		return (math.floor(use(app.clock.nowSignal) / 0.25) % 4) + 1
	end)

	-- every inline memo below is collected so `dispose` returns the core's memo
	-- count to its baseline: a screen that rebuilds without owning its memos
	-- leaks a handful per cycle, which a build/dispose loop makes visible
	local extraMemos: { any } = {}
	local function own(memo: any): any
		table.insert(extraMemos, memo)
		return memo
	end

	local function heroLayer(index: number, mark: any, anchorY: number): any
		return UI.Image({
			id = "Layer" .. index,
			image = mark.image,
			scaleMode = "fit",
			tint = { role = "contentSecondary", blend = 0.35 + index * 0.15 },
			anchor = "topLeft",
			offsetX = own(core:memo(function(use)
				return { scale = 0.12 + index * 0.18 + use(layerSprings[index]) }
			end)),
			offsetY = { scale = anchorY },
			width = { type = "fixed", px = "controlSizes.regular.height" },
			height = { type = "fixed", px = "controlSizes.regular.height" },
		})
	end

	local heroBand = UI.ZStack({
		id = "HeroBand",
		width = UI.fill(),
		height = { type = "fixed", px = "app.cartwheel.heroH" },
		children = {
			UI.gradient(
				UI.Box({
					id = "Sky",
					surface = "base",
					width = UI.fill(),
					height = UI.fill(),
				}),
				{ colors = { "surfaceStrong", "surface" }, rotation = 90 }
			),
			UI.Anchor({
				id = "Layers",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					heroLayer(1, app.art.marks.chevronUp, 0.16),
					heroLayer(2, app.art.marks.menu, 0.34),
					-- the cart itself: a four-frame asset swap on the domain clock
					UI.Image({
						id = "Cart",
						image = own(core:memo(function(use)
							local frame = use(flipFrame)
							return app.art.markFor(frame).image
						end)),
						scaleMode = "fit",
						tint = { role = "accent", blend = 1 },
						anchor = "topLeft",
						offsetX = own(core:memo(function(use)
							return { scale = 0.46 + use(layerSprings[3]) }
						end)),
						offsetY = { scale = 0.42 },
						width = { type = "fixed", px = "controlSizes.regular.height" },
						height = { type = "fixed", px = "controlSizes.regular.height" },
					}),
					heroLayer(4, app.art.marks.more, 0.62),
				},
			}),
			UI.Text({ id = "Brand", text = S.t("app.title"), textSize = "title", padding = "m" }),
		},
	})

	-- ---- card 1: Recent Brews (hero + tiles) --------------------------------

	local function brewTile(item: any, big: boolean): any
		local size = if big then "controls.image.defaultSize" else "controlSizes.regular.height"
		local plate = UI.Box({
			id = "Plate",
			surface = "base",
			width = UI.fill(),
			height = UI.fill(),
		})
		plate = UI.corners(plate, "control")
		plate = UI.stroke(plate, {})
		return UI.ZStack({
			id = "Tile" .. tostring(item.id),
			canvasGroup = true,
			width = UI.fill(),
			height = { type = "content" },
			children = {
				plate,
				UI.VStack({
					id = "Body",
					padding = "s",
					gap = "xs",
					align = "center",
					children = {
						parts.thumbStack(app, "Thumbs", item.items, size),
						UI.Text({
							id = "Id",
							text = S.t("brews.rowLabel", { id = item.id }),
							textSize = "caption",
							role = "secondary",
							lineLimit = 1,
							disclose = true,
						}),
					},
				}),
			},
		})
	end

	local arrivalTransition = { enter = "slide-left", fade = true, class = "container" }

	local recentCard = parts.card(app, {
		id = "RecentBrews",
		children = {
			parts.cardHeaderButton(app, {
				id = "OpenBrews",
				title = S.t("cart.newBrews"),
				label = S.t("cart.openBrews"),
				onActivate = function()
					app.actions.selectSection("brews")
				end,
			}),
			UI.Composition({
				id = "HeroTiles",
				-- `leadFirst` (framework-gaps-phase2 item 12): the built-in mirror of
				-- `twoLane` — `lead` in the solo lane, so a hero/nav-shaped lane never
				-- resolves to the RIGHT of what it fronts. Used to be a CUSTOM
				-- arrangement reusing the `"twoLane"` name for different lanes; see
				-- `shell.luau`'s header for the full account.
				arrangements = { "leadFirst", "column" },
				laneGap = "s",
				groupGap = "s",
				groups = {
					{ id = "hero", lane = "lead", sizing = "hug" },
					{ id = "tiles", lane = "main", sizing = "fill" },
				},
				children = {
					UI.Region({
						id = "Hero",
						group = "hero",
						rank = 1,
						floor = { lines = 2 },
						children = {
							UI.VStack({
								id = "HeroSlot",
								gap = "xs",
								width = UI.fill(),
								children = {
									UI.ForEach({
										id = "HeroRow",
										items = heroItems,
										key = function(item)
											return tostring(item.id)
										end,
										row = function(item)
											return brewTile(item, true)
										end,
										transition = arrivalTransition,
									}),
								},
							}),
						},
					}),
					UI.Region({
						id = "Tiles",
						group = "tiles",
						rank = 2,
						floor = { lines = 2 },
						sizing = "fill",
						children = {
							UI.Grid({
								id = "TileGrid",
								columns = 2,
								gap = "s",
								children = {
									UI.ForEach({
										id = "TileRows",
										items = tileItems,
										key = function(item)
											return tostring(item.id)
										end,
										row = function(item)
											return brewTile(item, false)
										end,
										transition = arrivalTransition,
									}),
								},
							}),
						},
					}),
				},
			}),
			UI.Text({
				id = "Tally",
				text = tallyText,
				textSize = "caption",
				role = tallyRole,
				scale = tallyScale,
			}),
		},
	})

	-- ---- card 2: Skyglow (banded line approximation) ------------------------

	local skySamples = ambient.samples("willowmere")
	local skyEntry = ambient.forPlaza("willowmere")

	local bandBoxes: { any } = {}
	for index, band in skyEntry.bands do
		table.insert(
			bandBoxes,
			UI.Box({
				id = "Band" .. index,
				surface = "base",
				anchor = "topLeft",
				offsetX = { scale = band.from },
				width = { type = "percent", fraction = band.to - band.from },
				height = { type = "percent", fraction = 1 },
			})
		)
	end
	for index, mark in skyEntry.marks do
		table.insert(
			bandBoxes,
			UI.Image({
				id = "Mark" .. index,
				image = if mark.kind == "lit" then app.art.marks.chevronDown.image else app.art.marks.chevronUp.image,
				scaleMode = "fit",
				tint = { role = "contentSecondary", blend = 1 },
				anchor = "topLeft",
				offsetX = { scale = mark.at, offset = "-xs" },
				offsetY = { scale = 0.02 },
				width = { type = "fixed", px = "iconSizes.small" },
				height = { type = "fixed", px = "iconSizes.small" },
			})
		)
	end

	local axisLabels: { any } = {}
	for index = 1, #skySamples, 3 do
		table.insert(
			axisLabels,
			UI.Text({
				id = "Tick" .. index,
				text = tostring(index),
				textSize = "caption",
				role = "secondary",
				lineLimit = 1,
			})
		)
	end

	local skyCard = parts.card(app, {
		id = "Skyglow",
		children = {
			parts.cardHeaderButton(app, {
				id = "OpenPlaza",
				title = S.t("cart.skyglow"),
				label = S.t("cart.skyglowLink"),
				onActivate = function()
					app.actions.selectSection("plaza:willowmere")
				end,
			}),
			UI.ZStack({
				id = "Plot",
				width = UI.fill(),
				height = { type = "fixed", px = "app.cartwheel.chartH" },
				children = {
					UI.Anchor({
						id = "Bands",
						width = UI.fill(),
						height = UI.fill(),
						children = bandBoxes,
					}),
					UI.Path({
						id = "Line",
						points = parts.polyline(skySamples),
						role = "accent",
						thickness = "controls.table.indicatorThickness",
						width = UI.fill(),
						height = UI.fill(),
					}),
				},
			}),
			UI.HStack({
				id = "Axis",
				gap = "s",
				children = axisLabels,
			}),
			UI.Text({ id = "AxisNote", text = S.t("cart.skyCharge"), textSize = "caption", role = "secondary" }),
		},
	})

	-- ---- card 3: the Potion Rack (staggered lattice) ------------------------

	local rackChildren: { any } = {}
	local rackIndex = 0
	for rowIndex, count in RACK_ROWS do
		for column = 1, count do
			rackIndex += 1
			local potion = (data.potions :: any)[rackIndex]
			if potion == nil then
				break
			end
			local offset = if rowIndex % 2 == 0 then 0.5 / count else 0
			table.insert(
				rackChildren,
				UI.Image({
					id = "Bottle" .. rackIndex,
					image = potion.mark.image,
					scaleMode = "fit",
					tint = { direct = potion.hue },
					anchor = "topLeft",
					offsetX = { scale = (column - 1) / count + offset },
					offsetY = { scale = (rowIndex - 1) / #RACK_ROWS },
					width = { type = "fixed", px = "iconSizes.medium" },
					height = { type = "fixed", px = "iconSizes.medium" },
				})
			)
		end
	end

	local rackCard = parts.card(app, {
		id = "Rack",
		children = {
			parts.cardHeaderButton(app, {
				id = "OpenPotions",
				title = S.t("cart.rack"),
				label = S.t("cart.openPotions"),
				onActivate = function()
					app.actions.selectSection("potions")
				end,
			}),
			UI.Anchor({
				id = "Lattice",
				width = UI.fill(),
				height = { type = "fixed", px = "app.cartwheel.previewMin" },
				children = rackChildren,
			}),
		},
	})

	-- ---- card 4: Town Chatter (tag cloud) -----------------------------------
	--[[ BOUNDED GAP #3 IS NOW SPENT. The capability ledger nominated
		"stack `wrap`/flow" as a candidate bounded gap, scoped to exactly this
		cloud, "only if P2's tag cloud reads wrong as a uniform grid". It did:
		`Grid{ minColumnWidth = "intrinsic", itemSizing = "uniform" }` was the
		DECLARED approximation of the reference's ragged flow layout (ledger §A),
		and it forced every chip to the WIDEST chip's width — measured 2026-08-13
		at 1440x900, all sixteen tags came out 135x23 on a uniform 3-column pitch.
		A tidy cloud, not a ragged one.

		`wrap = true` (parity round 3) is the whole fix: each chip takes its own
		natural width and the lines are ragged. It is a PROP on the stack the row
		already wanted to be, so nothing else here changes. ]]

	local chipChildren: { any } = {}
	for index, tag in data.chatterTags :: any do
		table.insert(chipChildren, parts.chip(app, "Tag" .. index, tag))
	end

	local chatterCard = parts.card(app, {
		id = "ChatterCard",
		children = {
			parts.cardHeaderButton(app, {
				id = "OpenChatter",
				title = S.t("cart.chatter"),
				label = S.t("nav.chatter"),
				onActivate = function()
					app.actions.selectSection("chatter")
				end,
			}),
			UI.HStack({
				id = "Cloud",
				wrap = true,
				gap = "xs",
				children = chipChildren,
			}),
			UI.Text({ id = "CloudFooter", text = S.t("cart.chatterFooter"), textSize = "caption", role = "secondary" }),
		},
	})

	-- ---- the page ------------------------------------------------------------

	-- no `canvasGroup` here: the shell's own section wrapper is the fade group,
	-- and a group inside a group is a second render buffer for one fade
	local page = UI.ZStack({
		id = "Cart",
		overflow = "clip",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "m",
				padding = "m",
				width = UI.fill(),
				height = UI.fill(),
				children = {
					heroBand,
					UI.Composition({
						id = "CardGrid",
						-- `leadFirst` (framework-gaps-phase2 item 12): see `shell.luau`'s
						-- header for the full account of why this used to be a CUSTOM
						-- arrangement reusing the `"twoLane"` name for different lanes.
						arrangements = { "leadFirst", "column" },
						laneGap = "m",
						groupGap = "m",
						groups = {
							{ id = "left", lane = "lead", sizing = "fill", minWidth = "app.cartwheel.cardMin" },
							{ id = "right", lane = "main", sizing = "fill", minWidth = "app.cartwheel.cardMin" },
						},
						children = {
							UI.Region({
								id = "Recent",
								group = "left",
								rank = 1,
								floor = { lines = 3 },
								children = { recentCard },
							}),
							UI.Region({
								id = "Sky",
								group = "right",
								rank = 2,
								floor = { lines = 3 },
								children = { skyCard },
							}),
							UI.Region({
								id = "RackSlot",
								group = "left",
								rank = 3,
								floor = { lines = 2 },
								children = { rackCard },
							}),
							UI.Region({
								id = "ChatterSlot",
								group = "right",
								rank = 4,
								floor = { lines = 2 },
								children = { chatterCard },
							}),
						},
					}),
				},
			}),
		},
	})

	self.footerPath = app.paths.cart .. "/Page/CardGrid/Recent/RecentBrews/Tally"

	function self.view(): any
		return page
	end

	function self.dispose()
		for _, memo in extraMemos do
			memo:dispose()
		end
		tally:dispose()
		pulse:dispose()
		for _, spring in layerSprings do
			spring:dispose()
		end
		tallyRole:dispose()
		flipFrame:dispose()
		tallyText:dispose()
		heroItems:dispose()
		tileItems:dispose()
		recent:dispose()
	end

	return self
end

return dashboard
