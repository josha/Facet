--!strict
-- Glade (RA-P1) — S1, the Glades overview (spec §7), plus the two browse-only
-- sections (Wisps, Flora) that share its grid shape.
--
-- One `ScrollView` — the shell's single `mayScroll` region — holding the charm
-- offer card, the search field with its live suggestions, and a `UI.Grid` of
-- glade cards whose column count follows the width through `minColumnWidth`.
-- Nothing here names a device or a platform.

local seedData = require("../content/seed")
local sceneLib = require("./scene")
local parts = require("./parts")

local overview = {}

local METRICS = seedData.METRICS

-- ---- the glade card ----------------------------------------------------------
-- A ZStack of TWO siblings: the card body (one Button, one activation surface,
-- the whole scene inside it) and the favourite star beside it. The star is NOT
-- inside the card's activation surface — a focusable inside a Button's content is
-- refused at construction precisely because it would double-fire Activate under
-- keyboard and gamepad.
local function gladeCard(ctx: any, glade: any, rowScope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local name = rowScope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("glade." .. glade.id)
	end))
	local openLabel = rowScope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("overview.open", { glade = ctx.Lnow("glade." .. glade.id) })
	end))
	local favourite = ctx.state.favourites[glade.id]

	local body = UI.Button({
		id = "GladeCard_" .. glade.id,
		label = openLabel,
		width = UI.fill(),
		padding = 0,
		-- THE STRAY CORNER STROKE, root-caused (task PAINT, director item 11:
		-- glade-corner.png — a partial gray corner-stroke arc at a card corner).
		-- An unsurfaced `class = "Button"` classifies into the `control` slot
		-- BY CLASS ALONE (`chrome_slots.classify`: "class = Button|Toggle ->
		-- control ... including a Button that never declared a surface"), which
		-- under the running package paints a `controls.control` fill inside a
		-- `radii.control` (8px under Studio Neutral) rounded corner — its OWN
		-- chrome, wearing its OWN radius. This card's content is edge-to-edge
		-- (`padding = 0`, a full-bleed `Scene`) and rounds ITS OWN box at
		-- `radii.panel` (12px) via `sceneLib.glade`'s `UI.corners(_, "panel")`
		-- — a LARGER radius than the button wearing it. Since the scene cuts
		-- more corner away than the button underneath it does, a sliver of the
		-- button's own control fill/corner shows past the scene's more-rounded
		-- edge at every corner: the stray stroke. `surface = "plain"` is the
		-- framework's existing, documented escape hatch for exactly this shape
		-- — "an activation surface whose entire box is covered by content that
		-- paints its own visuals" (the same doctrine the playlist's rating
		-- stars use, chrome_slots.luau) — so the button contributes NO chrome
		-- of its own and the scene's paint is the only paint. Class-level fix,
		-- not a per-card patch: the phantom-corner/stroke family already lives
		-- at `chrome_slots.classify` + the package's surface recipes; this
		-- applies the vocabulary that already exists rather than adding a new
		-- one. See `tests/reference/glade_spec.luau` ("item 11").
		surface = "plain",
		onActivate = function()
			ctx.nav.openGlade(glade.id)
		end,
		children = {
			UI.ZStack({
				id = "Body",
				width = UI.fill(),
				children = {
					sceneLib.glade(ctx, {
						id = "Scene",
						glade = glade.id,
						form = "card",
						scope = rowScope,
						height = { type = "aspect", ratio = 5 / 3 },
					}),
					-- the name plate: read-only, top-leading, off the scene's own
					-- paint so copy never sits on picture (visual invariant 2)
					UI.corners(
						UI.VStack({
							id = "Plate",
							surface = "raised",
							padding = "xs",
							margin = "s",
							alignH = "start",
							alignV = "start",
							children = {
								UI.Text({
									id = "Name",
									text = name,
									textSize = "label",
									lineLimit = 1,
									disclose = true,
								}),
							},
						}),
						"pill"
					),
					-- glance-only rings, bottom-trailing on their own plate
					UI.corners(
						UI.HStack({
							id = "Glance",
							surface = "raised",
							padding = "xs",
							gap = "s",
							alignH = "end",
							alignV = "end",
							margin = "s",
							children = {
								sceneLib.ring(ctx, {
									id = "GlanceNectar",
									glade = glade.id,
									kind = "nectar",
									size = METRICS.ringSmall,
									scope = rowScope,
								}),
								sceneLib.ring(ctx, {
									id = "GlanceDew",
									glade = glade.id,
									kind = "dew",
									size = METRICS.ringSmall,
									scope = rowScope,
								}),
							},
						}),
						"panel"
					),
				},
			}),
		},
	})

	return UI.ZStack({
		id = "Card_" .. glade.id,
		canvasGroup = true,
		width = UI.fill(),
		children = {
			body,
			-- the star: a sibling, floored to the theme's own target size so the
			-- compact form (the glyph) is what gets drawn while "Favorite" stays
			-- the semantic name every input class hears.
			UI.Button({
				id = "Fav_" .. glade.id,
				label = ctx.L("overview.favorite"),
				compactLabel = "★",
				selected = favourite,
				alignH = "end",
				alignV = "start",
				margin = "s",
				width = { type = "fixed", px = "targetSizes.minimum" },
				height = { type = "fixed", px = "targetSizes.minimum" },
				onActivate = function()
					ctx.nav.toggleFavourite(glade.id)
				end,
			}),
		},
	})
end

-- ---- the charm offer card ----------------------------------------------------
-- Only while the tier fact is "none" AND the player has not dismissed it this
-- session. Dismiss is a VISIBLE BUTTON: the ledger's adaptation of the
-- reference's swipe-to-dismiss, because a swipe is not a verb every input class
-- has (capability ledger §A, swipe-row row).
local function offerCard(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local visible = ctx.scope:own(core:memo(function(use)
		return use(ctx.commerce.charmTier()) == "none" and not use(ctx.state.offerDismissed)
	end))
	return UI.When({
		id = "Offer",
		condition = visible,
		transition = { enter = "fade", class = "container" },
		thenView = function(): any
			return UI.ZStack({
				id = "OfferGroup",
				canvasGroup = true,
				width = UI.fill(),
				children = {
					UI.shadow(
						UI.VStack({
							id = "OfferCard",
							surface = "raised",
							padding = "m",
							gap = "s",
							width = UI.fill(),
							children = {
								UI.Text({ id = "Title", text = ctx.L("charm.title"), textSize = "heading" }),
								parts.body(ctx, "Pitch", ctx.L("offer.pitch")),
								-- THE TWO VERBS SHARE THE ROW THEY ARE IN. Hugging their
								-- labels they are 281px of content in a 272px card on a
								-- 360px phone — 9px of paint outside the box, and 214px
								-- of it at the expansion locale and the largest text
								-- preference on a landscape phone, all of which the
								-- solver reported on every solve. Two `fill` verbs each
								-- take half of whatever there is and let their labels
								-- WRAP, which is the one adaptation that answers text
								-- growth as well as it answers a narrow screen.
								--
								-- The row states `percent(1, max)` rather than `fill`
								-- for the same reason: a `fill` row of `fill` children
								-- measures as nothing at all, and an uncapped one would
								-- hand a 1400px card two 700px buttons. This is ONE node
								-- per verb — a ViewThatFits ladder would mount two
								-- copies of `OfferSee`, and a proof whose tests address
								-- nodes by the tail of their path must never have two.
								UI.HStack({
									id = "Actions",
									gap = "s",
									width = {
										type = "percent",
										fraction = 1,
										max = METRICS.offerActionsMax,
									},
									children = {
										UI.Button({
											id = "OfferSee",
											label = ctx.L("offer.cta"),
											width = UI.fill(),
											height = UI.fill(),
											onActivate = function()
												ctx.nav.openCharm()
											end,
										}),
										UI.Button({
											id = "OfferDismiss",
											label = ctx.L("offer.dismiss"),
											role = "cancel",
											width = UI.fill(),
											height = UI.fill(),
											onActivate = function()
												ctx.state.offerDismissed:set(true)
											end,
										}),
									},
								}),
							},
						}),
						"raised"
					),
				},
			})
		end,
	})
end

-- ---- search + suggestions ----------------------------------------------------
local function suggestions(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local show = ctx.scope:own(core:memo(function(use)
		return use(ctx.state.search) == "" and #use(ctx.visits.currentAll()) > 0
	end))
	return UI.When({
		id = "Suggestions",
		condition = show,
		thenView = function(): any
			return UI.VStack({
				id = "SuggestionList",
				gap = "xs",
				width = UI.fill(),
				children = {
					UI.ForEach({
						id = "Rows",
						items = ctx.visits.currentAll(),
						key = function(item: any): string
							return item.id
						end,
						row = function(item: any, rowScope: any): any
							local wispName = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("wisp." .. item.wisp)
							end))
							local gladeName = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("glade." .. item.glade)
							end))
							-- the same sentence with no emphasis in it, for the
							-- candidate below that has to survive any width: ONE text
							-- node wraps, and a wrapping text can never overflow
							local sentence = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("wisp." .. item.wisp)
									.. ctx.Lnow("overview.visiting")
									.. ctx.Lnow("glade." .. item.glade)
							end))
							-- emphasis through SPLIT TEXT RUNS: Facet has no rich-text
							-- spans, and the two names are the part that carries the
							-- sentence
							local function wisp(): any
								return UI.Text({ id = "Wisp", text = wispName, textSize = "strong" })
							end
							local function mid(): any
								return UI.Text({
									id = "Mid",
									text = ctx.L("overview.visiting"),
									textSize = "body",
									role = "secondary",
								})
							end
							local function glade(): any
								return UI.Text({ id = "Glade", text = gladeName, textSize = "strong" })
							end
							return UI.Button({
								id = "Suggest_" .. item.id,
								label = gladeName,
								width = UI.fill(),
								align = "start",
								onActivate = function()
									ctx.nav.search(ctx.Lnow("glade." .. item.glade))
								end,
								children = {
									-- THREE CONTENT-SIZED RUNS CANNOT SHRINK, so on a
									-- 360px phone this sentence painted 102px past the
									-- row it sits in — the solver said so on every
									-- solve, at rest, in the default locale. The runs
									-- are the emphasis, so the ladder spends LINES
									-- rather than glyphs: one line, then the name on
									-- its own line, then — when even that will not go,
									-- which is where the 1.4x expansion locale lands —
									-- the plain wrapping sentence.
									UI.ViewThatFits({
										id = "Line",
										children = {
											UI.HStack({
												id = "OneLine",
												gap = 0,
												children = { wisp(), mid(), glade() },
											}),
											UI.VStack({
												id = "TwoLines",
												gap = 0,
												-- (no `alignH`: a ViewThatFits gives its chosen candidate the
												-- whole offer and reads no placement prop; and a stack's own
												-- cross-axis word is `align`, whose default is already
												-- `start`. Accepted and ignored both ways round — deleted by
												-- the §2.1 placement audit)
												children = {
													UI.HStack({
														id = "Lead",
														gap = 0,
														children = { wisp(), mid() },
													}),
													glade(),
												},
											}),
											UI.Text({ id = "Plain", text = sentence, textSize = "body" }),
										},
									}),
								},
							})
						end,
					}),
				},
			})
		end,
	})
end

local function emptyState(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local show = ctx.scope:own(core:memo(function(use)
		return use(ctx.state.search) ~= "" and #use(ctx.state.filtered) == 0
	end))
	local copy = ctx.scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("overview.noMatches", { term = use(ctx.state.search) })
	end))
	return UI.When({
		id = "NoMatches",
		condition = show,
		thenView = function(): any
			return UI.VStack({
				id = "NoMatchesBody",
				gap = "s",
				width = UI.fill(),
				children = {
					parts.body(ctx, "Copy", copy),
					UI.Button({
						id = "ClearSearch",
						label = ctx.L("overview.clearSearch"),
						onActivate = function()
							ctx.nav.search("")
						end,
					}),
				},
			})
		end,
	})
end

-- ---- the section bodies ------------------------------------------------------

function overview.glades(ctx: any): any
	local UI = ctx.UI
	local search = ctx.Facet.Controls.TextInput(ctx.core, {
		id = "Search",
		value = ctx.state.search,
		placeholder = ctx.L("overview.search"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})
	ctx.scope:own(search)

	return UI.ScrollView({
		id = "GladesPage",
		axis = "y",
		gap = "l",
		padding = "l",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			offerCard(ctx),
			UI.VStack({
				id = "Find",
				gap = "s",
				width = UI.fill(),
				children = { search.blueprint, suggestions(ctx), emptyState(ctx) },
			}),
			UI.Grid({
				id = "Cards",
				minColumnWidth = METRICS.gladeCardMin,
				gap = "m",
				width = UI.fill(),
				children = {
					UI.ForEach({
						id = "Glades",
						items = ctx.state.filtered,
						key = function(glade: any): string
							return glade.id
						end,
						transition = { enter = "fade", class = "container" },
						row = function(glade: any, rowScope: any): any
							return gladeCard(ctx, glade, rowScope)
						end,
					}),
				},
			}),
		},
	})
end

-- The Wisps grid: browse + Activate → S6. Frostwisp wears the "Lumen only" chip
-- until the tier fact says otherwise — the entitlement gate is a `When` over a
-- fact, not a branch in a factory.
function overview.wisps(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local items = ctx.scope:own(core:memo(function(): any
		return seedData.WISPS
	end))
	return UI.ScrollView({
		id = "WispsPage",
		axis = "y",
		gap = "l",
		padding = "l",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			parts.heading(ctx, "WispsTitle", ctx.L("section.wisps")),
			UI.Grid({
				id = "WispCards",
				minColumnWidth = METRICS.nectarCardMin,
				gap = "m",
				width = UI.fill(),
				children = {
					UI.ForEach({
						id = "Wisps",
						items = items,
						key = function(wisp: any): string
							return wisp.id
						end,
						row = function(wisp: any, rowScope: any): any
							local name = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("wisp." .. wisp.id)
							end))
							local gated = rowScope:own(core:memo(function(use)
								return wisp.lumenOnly == true and use(ctx.commerce.charmTier()) ~= "lumen"
							end))
							return UI.Button({
								id = "WispCard_" .. wisp.id,
								label = name,
								width = UI.fill(),
								onActivate = function()
									ctx.nav.openWisp(wisp.id)
								end,
								children = {
									UI.VStack({
										id = "Body",
										gap = "s",
										align = "center",
										width = UI.fill(),
										children = {
											sceneLib.portrait(ctx, "Portrait", wisp.id, METRICS.portrait),
											UI.Text({
												id = "Name",
												text = name,
												textSize = "label",
												lineLimit = 1,
												disclose = true,
											}),
											UI.When({
												id = "Gate",
												condition = gated,
												thenView = function(): any
													return parts.chip(ctx, "LumenOnly", ctx.L("wisp.lumenChip"))
												end,
											}),
										},
									}),
								},
							})
						end,
					}),
				},
			}),
		},
	})
end

-- Flora: the Wisps grid's shape with plant cards and no modal beyond the name and
-- one species line. Browse-only, by design (spec §3).
function overview.flora(ctx: any): any
	local UI = ctx.UI
	local core = ctx.core
	local items = ctx.scope:own(core:memo(function(): any
		return seedData.FLORA
	end))
	return UI.ScrollView({
		id = "FloraPage",
		axis = "y",
		gap = "l",
		padding = "l",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			parts.heading(ctx, "FloraTitle", ctx.L("flora.title")),
			UI.Grid({
				id = "FloraCards",
				minColumnWidth = METRICS.nectarCardMin,
				gap = "m",
				width = UI.fill(),
				children = {
					UI.ForEach({
						id = "Flora",
						items = items,
						key = function(plant: any): string
							return plant.id
						end,
						row = function(plant: any, rowScope: any): any
							local name = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("flora." .. plant.id)
							end))
							local species = rowScope:own(core:memo(function(use)
								local _ = use(ctx.state.locale)
								return ctx.Lnow("flora.species." .. plant.id)
							end))
							return UI.VStack({
								id = "FloraCard_" .. plant.id,
								surface = "raised",
								padding = "m",
								gap = "s",
								align = "center",
								width = UI.fill(),
								children = {
									parts.well(ctx, "Art", plant.art, METRICS.portrait),
									UI.Text({
										id = "Name",
										text = name,
										textSize = "label",
										lineLimit = 1,
										disclose = true,
									}),
									parts.caption(ctx, "Species", species),
								},
							})
						end,
					}),
				},
			}),
		},
	})
end

return overview
