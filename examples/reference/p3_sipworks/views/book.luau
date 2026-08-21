--!strict
-- The Blend Book (spec §10): a purchase-shaped unlock card and the recipe view
-- it opens.
--
-- LOCKED ROWS ARE ABSENT, NOT DISABLED. The recipe list's source set is the
-- unlocked set, so a confirmed purchase makes twelve rows ENTER the `ForEach`
-- with the same `materialize` transition every other insert uses — the animated
-- reveal is the list doing its job, not a bespoke sequence.

local metrics = require("../content/metrics")
local parts = require("./parts")

local book = {}

-- ---------------------------------------------------------------------------
-- the unlock card
-- ---------------------------------------------------------------------------

function book.unlockCard(app: any): any
	local UI = app.UI
	local core = app.core
	local unlock = app.services.unlock

	local locked = app.own(core:memo(function(use)
		return not use(unlock.unlocked)
	end))
	local loading = app.own(core:memo(function(use)
		return use(unlock.availability) ~= "available"
	end))
	local available = app.own(core:memo(function(use)
		return use(unlock.availability) == "available"
	end))
	local buyLabel = app.own(core:memo(function(use)
		local locale = use(app.services.i18n.locale)
		if use(unlock.status) == "pending" then
			return app.services.i18n.at(locale, "unlock.pending")
		end
		return app.services.i18n.at(locale, "unlock.buy", { price = unlock.product.price })
	end))
	local buyEnabled = app.own(core:memo(function(use)
		return use(unlock.status) ~= "pending"
	end))

	return UI.When({
		id = "Unlock",
		condition = locked,
		transition = { enter = "materialize" },
		thenView = function()
			return UI.ZStack({
				id = "UnlockBox",
				canvasGroup = true,
				width = metrics.fill,
				children = {
					UI.VStack({
						id = "Card",
						surface = "raised",
						corners = UI.cornersData("panel"),
						stroke = UI.strokeData({}),
						gap = 0,
						width = metrics.fill,
						children = {
							parts.artPlate(app, "blend", "amber-harvest", {
								id = "Cover",
								width = metrics.fill,
								height = metrics.aspect(2.4),
								markSize = "title",
							}),
							UI.VStack({
								id = "Bar",
								-- the translucent bar is the MATERIALS adaptation: a
								-- `raised` plate, never a blur
								surface = "raised",
								padding = "m",
								gap = "xs",
								width = metrics.fill,
								children = {
									UI.Text({
										id = "Name",
										text = app.text(unlock.product.nameKey),
										textSize = "heading",
									}),
									UI.Text({
										id = "Description",
										text = app.text(unlock.product.descriptionKey),
										role = "secondary",
										textSize = "body",
										lineLimit = 2,
										disclose = true,
										width = metrics.fill,
									}),
									-- WHILE THE PRODUCT IS STILL LOADING NO BUY BUTTON
									-- IS MOUNTED (spec §10): a price nobody knows yet
									-- must not be pressable.
									UI.When({
										id = "Loading",
										condition = loading,
										thenView = function()
											return UI.Text({
												id = "Price",
												text = app.text("unlock.loading"),
												role = "secondary",
												textSize = "caption",
											})
										end,
									}),
									UI.When({
										id = "Offer",
										condition = available,
										thenView = function()
											return UI.Button({
												id = "UnlockBuy",
												label = buyLabel,
												enabled = buyEnabled,
												surface = "accent",
												corners = UI.cornersData("pill"),
												width = metrics.fill,
												onActivate = function()
													app.commands.buyBlendBook()
												end,
											})
										end,
									}),
								},
							}),
						},
					}),
				},
			})
		end,
	})
end

-- ---------------------------------------------------------------------------
-- the recipe view
-- ---------------------------------------------------------------------------

function book.recipeView(app: any, opts: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog
	local options = opts or {}

	local title = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return ""
		end
		return i18n.nameAt(use(i18n.locale), "blend", blendId, catalog.blend(blendId).title)
	end))
	local measures = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return {}
		end
		local out = {}
		for _, measure in catalog.recipeMeasures(blendId) do
			table.insert(out, { key = blendId .. "/" .. measure.botanicalId, measure = measure, blendId = blendId })
		end
		return out
	end))
	local heroId = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		return if blendId == nil then {} else { blendId }
	end))

	local topBar: { any } = {}
	if options.showBack then
		table.insert(
			topBar,
			UI.Button({
				id = "Back",
				label = app.text("nav.back"),
				shape = "circle",
				onActivate = function()
					app.commands.closeRecipe()
				end,
				children = { UI.Text({ id = "Mark", text = "<", textSize = "strong", textAlign = "center" }) },
			})
		)
	end
	-- the top bar's title is bounded identity text: it truncates into its
	-- disclosure rather than making the whole pane wider than the pane it is in
	table.insert(
		topBar,
		UI.Text({
			id = "Title",
			text = title,
			textSize = "heading",
			lineLimit = 1,
			disclose = true,
			width = metrics.minMax(metrics.tileArt, metrics.tileArt, metrics.listPaneMax),
		})
	)

	return UI.VStack({
		id = options.id or "Recipe",
		gap = "s",
		width = metrics.fill,
		height = metrics.fill,
		children = {
			UI.HStack({
				id = "TopBar",
				padding = "m",
				gap = "s",
				align = "center",
				width = metrics.fill,
				children = topBar,
			}),
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "m",
				padding = "m",
				width = metrics.fill,
				height = metrics.fill,
				children = {
					UI.ZStack({
						id = "Hero",
						width = metrics.fill,
						height = metrics.aspect(1.5),
						children = {
							UI.ForEach({
								id = "HeroArt",
								items = heroId,
								key = function(blendId: string)
									return blendId
								end,
								row = function(blendId: string)
									return parts.artPlate(app, "blend", blendId, {
										id = "Plate",
										width = metrics.fill,
										height = metrics.fill,
										markSize = "title",
									})
								end,
							}),
							-- the batch stepper rides the hero's lower edge on an
							-- `Anchor`, which is placement and not layout: the hero
							-- keeps its whole box
							UI.Anchor({
								id = "BatchAnchor",
								width = metrics.fill,
								height = metrics.fill,
								children = {
									UI.ZStack({
										id = "BatchHost",
										anchor = "bottom",
										offsetY = "-m",
										children = { app.batch.blueprint },
									}),
								},
							}),
						},
					}),
					-- A HEADING NEEDS A FLOOR, not a natural width. A wrapping label
					-- still MEASURES the width its string wants, so a 1.4x heading at
					-- the largest text preference made the whole recipe pane 114px
					-- wider than the pane it sits in.
					UI.Text({
						id = "Heading",
						text = app.text("ingredients.recipe"),
						textSize = "heading",
						width = metrics.minMax(metrics.tileArt, metrics.tileArt, metrics.listPaneMax),
					}),
					UI.VStack({
						id = "Measures",
						gap = "xs",
						width = metrics.fill,
						children = {
							UI.ForEach({
								id = "Rows",
								items = measures,
								key = function(entry: any)
									return entry.key
								end,
								row = function(entry: any, itemScope: any)
									return book.measureRow(app, entry, itemScope)
								end,
							}),
						},
					}),
				},
			}),
		},
	})
end

-- one measured ingredient: name, quantity × batch, and the session-local
-- gathered check
function book.measureRow(app: any, entry: any, itemScope: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog
	local botanical = catalog.botanical(entry.measure.botanicalId)

	local function own(readable: any): any
		itemScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	local name = own(core:memo(function(use)
		return i18n.nameAt(use(i18n.locale), "botanical", botanical.id, botanical.name)
	end))
	-- THE DERIVED QUANTITY: it re-formats live on every Adjust of the stepper,
	-- with no remount, because it is a memo over the batch signal.
	local quantity = own(core:memo(function(use)
		local locale = use(i18n.locale)
		local batch = use(app.state.batch)
		return i18n.measureAt(locale, entry.measure.value * batch, entry.measure.unit)
	end))
	local gathered = app.gatheredSignal(entry.key)

	return UI.HStack({
		id = "Row-" .. botanical.id,
		-- THE TIGHTEST LEGAL GAP, because this row cannot compress. Its three
		-- columns are a fixed thumbnail, a `minMax` name floor and the gathered
		-- check's own capped band — none of them yields — so the gaps are the only
		-- slack there is, and the wider step spent exactly the 4px the row
		-- overflowed by on a 320px phone once the page scroller reserved its bar.
		gap = "xs",
		padding = "s",
		align = "center",
		width = metrics.fill,
		children = {
			parts.artPlate(app, "botanical", botanical.id, {
				width = metrics.fixed(metrics.rowArt),
				height = metrics.fixed(metrics.rowArt),
			}),
			-- A FLOOR, NOT A FILL. A `fill` child still MEASURES its content, so a
			-- capped-but-long localized name kept the row 70px wider than the pane
			-- it lives in (1.4x copy at the largest text preference, in the tablet
			-- two-pane row). A `minMax` floor is what lets the row compress and the
			-- name truncate into its disclosure.
			UI.VStack({
				id = "Lines",
				gap = "xs",
				width = metrics.minMax(metrics.tileArt, metrics.tileArt, metrics.listPaneMax),
				children = {
					UI.Text({ id = "Name", text = name, textSize = "strong", lineLimit = 1, disclose = true }),
					-- a measured quantity is ONE short token; capping it keeps the row
					-- the height of its own thumbnail at every text preference, and
					-- `disclose` keeps the whole value reachable if it ever truncates
					UI.Text({
						id = "Quantity",
						text = quantity,
						role = "secondary",
						textSize = "caption",
						lineLimit = 1,
						disclose = true,
						width = metrics.fill,
					}),
				},
			}),
			UI.Toggle({
				id = "Got-" .. botanical.id,
				width = metrics.fixed(metrics.gatherToggleAt(app)),
				label = own(core:memo(function(use)
					return i18n.at(use(i18n.locale), "recipe.gathered", { name = use(name) })
				end)),
				value = gathered,
				disclose = true,
			}),
		},
	})
end

return book
