--!strict
-- The Blend Book (spec §10): a purchase-shaped unlock card and the recipe view
-- it opens.
--
-- LOCKED ROWS ARE ABSENT, NOT DISABLED. The recipe list's source set is the
-- unlocked set, so a confirmed purchase makes twelve rows ENTER the `ForEach`
-- with the same `materialize` transition every other insert uses — the animated
-- reveal is the list doing its job, not a bespoke sequence.

local dims = require("../content/dims")
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

	--[[ task POP fix round 1 (sweep found this real): `Card` is itself the
		plate (`surface = "raised"`) AND, before this fix, the direct
		container of its own content — `materialize` (which fades) targets
		`UnlockBox`, so `Card` used to ride the same `GroupTransparency` ramp
		as its own cover art/price text (`newpop.mov`'s mechanism). `Card`
		stays the outer, non-canvasGroup plate; `Group` is the ONE new
		canvasGroup, nested one level in, wrapping what used to be `Card`'s
		direct children. ]]
	return UI.When({
		id = "Unlock",
		condition = locked,
		transition = { enter = "materialize" },
		thenView = function()
			return UI.ZStack({
				id = "UnlockBox",
				width = dims.fill,
				children = {
					UI.VStack({
						id = "Card",
						surface = "raised",
						corners = UI.cornersData("panel"),
						stroke = UI.strokeData({}),
						gap = 0,
						width = dims.fill,
						children = {
							UI.ZStack({
								id = "Group",
								canvasGroup = true,
								width = dims.fill,
								children = {
									UI.VStack({
										id = "GroupStack",
										gap = 0,
										width = dims.fill,
										children = {
											parts.artPlate(app, "blend", "amber-harvest", {
												id = "Cover",
												width = dims.fill,
												height = dims.aspect(2.4),
												markSize = "title",
											}),
											UI.VStack({
												id = "Bar",
												-- the translucent bar is the MATERIALS adaptation: a
												-- `raised` plate, never a blur
												surface = "raised",
												padding = "m",
												gap = "xs",
												width = dims.fill,
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
														width = dims.fill,
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
																width = dims.fill,
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

	-- registry item 13 (W3-D, ADR-0053): was a hand-built HStack (a circle
	-- Button with a literal "<" glyph child); the shared bar draws the
	-- framework's own chevron icon instead — see nav_bar.luau's header for
	-- why that is a deliberate, disclosed visual change, not an oversight.
	-- The title's bounded width (identity text, truncating into its
	-- disclosure rather than widening the pane) is this site's own dim,
	-- passed through verbatim.
	return UI.VStack({
		id = options.id or "Recipe",
		gap = "s",
		width = dims.fill,
		height = dims.fill,
		children = {
			app.Facet.navBar({
				id = "TopBar",
				padding = "m",
				onBack = if options.showBack
					then function()
						app.commands.closeRecipe()
					end
					else nil,
				backLabel = app.text("nav.back"),
				title = title,
				titleSize = "heading",
				titleWidth = dims.minMax("app.sip.tileArt", "app.sip.tileArt", "app.sip.listPaneMax"),
			}),
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "m",
				padding = "m",
				width = dims.fill,
				height = dims.fill,
				children = {
					UI.ZStack({
						id = "Hero",
						width = dims.fill,
						height = dims.aspect(1.5),
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
										width = dims.fill,
										height = dims.fill,
										markSize = "title",
									})
								end,
							}),
							-- the batch stepper rides the hero's lower edge on an
							-- `Anchor`, which is placement and not layout: the hero
							-- keeps its whole box
							UI.Anchor({
								id = "BatchAnchor",
								width = dims.fill,
								height = dims.fill,
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
						width = dims.minMax("app.sip.tileArt", "app.sip.tileArt", "app.sip.listPaneMax"),
					}),
					UI.VStack({
						id = "Measures",
						gap = "xs",
						width = dims.fill,
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
		width = dims.fill,
		children = {
			parts.artPlate(app, "botanical", botanical.id, {
				width = dims.fixed("app.sip.rowArt"),
				height = dims.fixed("app.sip.rowArt"),
			}),
			-- A FLOOR, NOT A FILL. A `fill` child still MEASURES its content, so a
			-- capped-but-long localized name kept the row 70px wider than the pane
			-- it lives in (1.4x copy at the largest text preference, in the tablet
			-- two-pane row). A `minMax` floor is what lets the row compress and the
			-- name truncate into its disclosure.
			UI.VStack({
				id = "Lines",
				gap = "xs",
				width = dims.minMax("app.sip.tileArt", "app.sip.tileArt", "app.sip.listPaneMax"),
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
						width = dims.fill,
					}),
				},
			}),
			UI.Toggle({
				id = "Got-" .. botanical.id,
				width = dims.fixed("app.sip.gatherToggle"),
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
