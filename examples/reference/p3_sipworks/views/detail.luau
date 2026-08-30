--!strict
-- Blend detail (spec §7) and the order flow's CTA band (spec §8).
--
-- The body is fully BOUND to `selectedBlendId`: the header texts are memos and
-- the description runs and botanical tiles are keyed `ForEach`es, so choosing
-- another blend in the regular two-pane layout re-solves the pane instead of
-- rebuilding it — which is what keeps the scroll offset and the focus ring
-- where the player left them.

local dims = require("../content/dims")
local parts = require("./parts")
local listView = require("./list")
local rewardsService = require("../services/rewards")

local rewardsThreshold = rewardsService.THRESHOLD

local detail = {}

local function ownIn(scope: any, readable: any): any
	scope:own(function()
		readable:dispose()
	end)
	return readable
end

-- ---------------------------------------------------------------------------
-- the adaptive header (spec §7)
-- ---------------------------------------------------------------------------

local function descriptionRuns(app: any, id: string): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local runs = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		local blend = if blendId ~= nil then catalog.blend(blendId) else nil
		if blend == nil then
			return {}
		end
		local locale = use(i18n.locale)
		local out = {}
		for index, paragraph in blend.paragraphs do
			table.insert(out, {
				key = blendId .. "#" .. index,
				text = i18n.nameAt(locale, "paragraph", blendId .. "#" .. index, paragraph.text),
				emphasis = paragraph.emphasis == true,
			})
		end
		return out
	end))

	return UI.VStack({
		id = id,
		gap = "xs",
		width = dims.fill,
		children = {
			UI.ForEach({
				id = "Runs",
				items = runs,
				key = function(run: any)
					return run.key
				end,
				row = function(run: any)
					-- THE DECLARED EMPHASIS APPROXIMATION (ledger §D): emphasis is
					-- a whole paragraph drawn at the `strong` type role. There is no
					-- rich-text span engine here and none is claimed.
					return UI.Text({
						id = "Run",
						text = run.text,
						textSize = if run.emphasis then "strong" else "body",
						width = dims.fill,
					})
				end,
			}),
		},
	})
end

local function header(app: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local title = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return ""
		end
		return i18n.nameAt(use(i18n.locale), "blend", blendId, catalog.blend(blendId).title)
	end))
	local caffeine = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return ""
		end
		return i18n.at(use(i18n.locale), "row.caffeine", { n = catalog.caffeineMg(blendId) })
	end))
	local function texts(id: string, width: any): any
		return UI.VStack({
			id = id,
			gap = "s",
			padding = "l",
			width = width,
			children = {
				UI.Text({ id = "Title", text = title, textSize = "title", width = dims.fill }),
				descriptionRuns(app, "Description" .. id),
				UI.Text({ id = "Caffeine", text = caffeine, role = "secondary", textSize = "caption" }),
			},
		})
	end

	-- The art plate is bound to the SELECTION through a keyed `ForEach` of
	-- exactly one item — the framework's own idiom for "this subtree belongs to
	-- that key", and the reason changing blends re-keys the picture instead of
	-- rebuilding the header.
	local function art(id: string, width: any, height: any): any
		return UI.ForEach({
			id = id,
			items = app.own(core:memo(function(use)
				local blendId = use(app.state.selectedBlendId)
				return if blendId == nil then {} else { blendId }
			end)),
			key = function(blendId: string)
				return blendId
			end,
			row = function(blendId: string)
				return parts.artPlate(app, "blend", blendId, {
					id = "Plate",
					width = width,
					height = height,
					markSize = "title",
				})
			end,
		})
	end

	return UI.ViewThatFits({
		id = "Header",
		children = {
			-- 1. the WIDE CARD. It states a real minimum for its text column
			-- rather than a `fill`: a fill child inside a candidate always fits,
			-- so a fill here would make this candidate win on a phone.
			UI.HStack({
				id = "WideCard",
				surface = "raised",
				corners = UI.cornersData("panel"),
				stroke = UI.strokeData({}),
				gap = "m",
				align = "center",
				children = {
					texts("WideText", dims.fixed("app.sip.headerTextMin")),
					-- the art matches the CARD's height rather than pinning it: a
					-- fixed-height plate beside a text column that grows (a longer
					-- description, a bigger type preference, a 1.4x locale) is the
					-- fixed-px-height defect class, and the solver's overflow
					-- diagnostic caught exactly that at desktop width.
					UI.ZStack({
						id = "WideArt",
						width = dims.fixed("app.sip.headerArtW"),
						height = dims.fill,
						children = { art("WideArtFor", dims.fill, dims.fill) },
					}),
				},
			}),
			-- 2. the FULL-BLEED fallback
			UI.VStack({
				id = "FullBleed",
				gap = "s",
				width = dims.fill,
				children = {
					UI.ZStack({
						id = "BleedArt",
						width = dims.fill,
						height = dims.aspect(1.2),
						children = { art("BleedArtFor", dims.fill, dims.fill) },
					}),
					texts("BleedText", dims.fill),
				},
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the botanical grid (spec §7)
-- ---------------------------------------------------------------------------

local function botanicalGrid(app: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local ids = app.own(core:memo(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return {}
		end
		return catalog.tileBotanicals(blendId)
	end))

	return UI.VStack({
		id = "Botanicals",
		gap = "s",
		width = dims.fill,
		children = {
			-- a floor rather than a natural width, for the reason the recipe's own
			-- heading carries the same shape
			UI.Text({
				id = "Heading",
				text = app.text("ingredients.menu"),
				textSize = "heading",
				width = dims.minMax("app.sip.tileArt", "app.sip.tileArt", "app.sip.listPaneMax"),
			}),
			UI.Grid({
				id = "Tiles",
				-- "intrinsic" — no column narrower than the widest child MEASURES.
				-- A px literal here reads as a guess about a font, and it is worse
				-- than one: the grid's pitch is innerWidth/columns, so a literal
				-- equal to the art's width produced three columns whose CELLS were
				-- 8px narrower than the art in them.
				minColumnWidth = "intrinsic",
				itemSizing = "uniform",
				gap = "m",
				width = dims.fill,
				children = {
					UI.ForEach({
						id = "Cells",
						items = ids,
						key = function(id: string)
							return id
						end,
						row = function(botanicalId: string, itemScope: any)
							local botanical = catalog.botanical(botanicalId)
							local label = ownIn(
								itemScope,
								core:memo(function(use)
									return i18n.nameAt(use(i18n.locale), "botanical", botanicalId, botanical.name)
								end)
							)
							return UI.Button({
								id = "Tile-" .. botanicalId,
								label = label,
								-- no padding of its own: the Grid's intrinsic column
								-- is measured from the cell's content, and a control
								-- inset the column did not count for is 29px of
								-- overflow per tile (measured at 1.4x + largest text)
								padding = 0,
								gap = "xs",
								align = "center",
								onActivate = function()
									app.commands.openBotanical(botanicalId)
								end,
								children = {
									-- A BUTTON LAYS ITS OWN CONTENT ALONG ONE AXIS, and
									-- that axis is horizontal — so the tile's art and
									-- label need a stack of their own. Without it the
									-- label sat BESIDE the art and every tile overflowed
									-- its grid cell (found by `controller.diagnostics()`,
									-- never by a screenshot).
									UI.VStack({
										id = "Cell",
										gap = "xs",
										align = "center",
										width = dims.fixed("app.sip.tileArt"),
										children = {
											parts.artPlate(app, "botanical", botanicalId, {
												width = dims.fill,
												height = dims.fixed("app.sip.tileArt"),
											}),
											-- the label takes the CELL's width rather than
											-- stating one of its own, so a long localized
											-- name truncates (and discloses) instead of
											-- widening the grid
											UI.Text({
												id = "Name",
												text = label,
												textSize = "label",
												lineLimit = 1,
												disclose = true,
												textAlign = "center",
												width = dims.fill,
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

-- ---------------------------------------------------------------------------
-- the CTA band (spec §8)
-- ---------------------------------------------------------------------------

local function ctaBand(app: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local order = app.services.order
	local rewards = app.services.rewards

	local paused = app.own(core:memo(function(use)
		return not use(order.paymentsEnabled)
	end))
	-- THE REJECTION, AT THE POINT OF ACTION. OrderService acknowledges a refusal
	-- on the same turn (its status is back to `idle` before anything renders) and
	-- the toast that announced it expires in four seconds, so a player who looked
	-- away had nothing left to read. The task's own latch is what this notice is
	-- over: it says what happened, says the stamps were not touched, and leaves
	-- the CTA right underneath it to press again.
	local refused = app.own(core:memo(function(use)
		return app.entry == "full" and use(app.services.task.refused)
	end))
	-- ONE node, one id, one geometry (spec §8 asks for exactly that), and the
	-- label is a binding — so the pay/redeem swap and the pending state cost no
	-- remount and can never leave two CTAs on screen at once.
	local label = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		if use(order.status) == "pending" then
			return i18n.at(locale, "order.pending")
		end
		-- the redeem branch does not exist in the compact-link entry (spec §11),
		-- and the LABEL has to agree with the command or the CTA would promise a
		-- free pour the flow would then charge for
		if app.entry == "full" and use(rewards.earned) - use(rewards.spent) >= rewardsThreshold then
			return i18n.at(locale, "order.redeem")
		end
		return i18n.at(locale, "order.place", { price = order.price })
	end))
	local enabled = app.own(core:memo(function(use)
		return use(order.status) ~= "pending"
	end))

	return UI.VStack({
		id = "Cta",
		gap = "xs",
		width = dims.fill,
		children = {
			UI.Divider({ id = "Rule" }),
			UI.When({
				id = "GuardNotice",
				condition = paused,
				transition = { enter = "fade" },
				thenView = function()
					return UI.ZStack({
						id = "NoticeBox",
						canvasGroup = true,
						width = dims.fill,
						children = {
							UI.Text({
								id = "Notice",
								text = app.text("guard.paused"),
								surface = "chip",
								role = "secondary",
								textSize = "caption",
								width = dims.fill,
							}),
						},
					})
				end,
			}),
			UI.When({
				id = "RejectNotice",
				condition = refused,
				transition = { enter = "fade" },
				thenView = function()
					return UI.ZStack({
						id = "RejectBox",
						canvasGroup = true,
						width = dims.fill,
						children = {
							UI.Text({
								id = "Reject",
								text = app.text("task.next.rejected"),
								surface = "chip",
								textSize = "caption",
								width = dims.fill,
							}),
						},
					})
				end,
			}),
			UI.HStack({
				id = "Band",
				padding = "s",
				align = "center",
				width = dims.fill,
				-- A FLOOR, NOT A FIXED BAND. A theme's `control` chrome reserves its
				-- own content insets (Fantasy Parchment's are 20px per side), and a
				-- band pinned at 64px left the CTA's label a 12px box to draw in —
				-- the solver said so in as many words. The band states its minimum
				-- and grows with whatever the installed package needs.
				-- the cap is its own NAME rather than `3 *` the floor: the metric
				-- vocabulary sums names and negates them, it does not multiply one,
				-- and a cap a theme cannot move is not a theme number (ADR-0042)
				height = dims.atLeast("app.sip.ctaBand", "app.sip.ctaBandMax"),
				-- the "bar material" adaptation: a stated raised plate
				surface = "raised",
				children = {
					UI.Button({
						id = "OrderCTA",
						label = label,
						enabled = enabled,
						surface = "accent",
						corners = UI.cornersData("pill"),
						width = dims.fill,
						onActivate = function()
							app.commands.orderCta()
						end,
					}),
				},
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the detail body, used by BOTH the compact pushed surface and the regular
-- detail pane — one factory, two placements (spec §5)
-- ---------------------------------------------------------------------------

function detail.body(app: any, opts: any): any
	local UI = app.UI
	local options = opts or {}
	-- registry item 13 (W3-D, ADR-0053): was a hand-built HStack (a circle
	-- Button with a literal "<" glyph child); the shared bar draws the
	-- framework's own chevron icon instead — see nav_bar.luau's header for
	-- why that is a deliberate, disclosed visual change, not an oversight
	local topBarTrailing: { any } = {}
	if app.entry == "full" then
		table.insert(topBarTrailing, detail.favoriteSlot(app))
	end

	return UI.VStack({
		id = options.id or "Detail",
		gap = "s",
		width = dims.fill,
		height = dims.fill,
		children = {
			app.Facet.navBar({
				id = "TopBar",
				padding = "m",
				onBack = if options.showBack
					then function()
						app.commands.closeDetail()
					end
					else nil,
				backLabel = app.text("nav.back"),
				trailing = topBarTrailing,
			}),
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "m",
				padding = "m",
				width = dims.fill,
				height = dims.fill,
				children = {
					UI.VStack({
						id = "Content",
						gap = "m",
						width = dims.fill,
						children = { header(app), botanicalGrid(app) },
					}),
				},
			}),
			ctaBand(app),
		},
	})
end

-- the detail's favorite heart is the row's twin on the SAME signal: one keyed
-- region so it re-targets with the selection without remounting the top bar
function detail.favoriteSlot(app: any): any
	local UI = app.UI
	local core = app.core
	return UI.ForEach({
		id = "FavoriteSlot",
		items = app.own(core:memo(function(use)
			local blendId = use(app.state.selectedBlendId)
			return if blendId == nil then {} else { blendId }
		end)),
		key = function(blendId: string)
			return blendId
		end,
		row = function(blendId: string, itemScope: any)
			return listView.favoriteButton(app, blendId, itemScope, "Favorite")
		end,
	})
end

-- ---------------------------------------------------------------------------
-- the botanical card (the declared hero-card approximation, spec §7)
-- ---------------------------------------------------------------------------

function detail.botanicalCard(app: any, blendId: string, botanicalId: string, progress: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog
	local botanical = catalog.botanical(botanicalId)

	local name = app.own(core:memo(function(use)
		return i18n.nameAt(use(i18n.locale), "botanical", botanicalId, botanical.name)
	end))

	local function frontFace(): any
		return UI.VStack({
			id = "Front",
			gap = "s",
			padding = "m",
			align = "center",
			width = dims.fill,
			height = dims.fill,
			children = {
				parts.artPlate(app, "botanical", botanicalId, {
					id = "CardArt",
					width = dims.fill,
					height = dims.fill,
					markSize = "title",
				}),
				UI.Text({ id = "Name", text = name, textSize = "title", textAlign = "center", lineLimit = 2 }),
				UI.HStack({
					id = "Actions",
					gap = "m",
					align = "center",
					children = {
						UI.Button({
							id = "CardClose",
							label = app.text("card.close"),
							shape = "circle",
							icon = "close",
							onActivate = function()
								app.commands.closeBotanical()
							end,
						}),
						UI.Button({
							id = "CardFacts",
							label = app.text("card.factsOpen"),
							shape = "circle",
							icon = "more",
							onActivate = function()
								app.commands.flipCard(true)
							end,
						}),
					},
				}),
			},
		})
	end

	local function backFace(): any
		local rows: { any } = {
			UI.Text({ id = "FactsTitle", text = app.text("facts.title"), textSize = "heading" }),
		}
		for index, fact in catalog.factsFor(blendId, botanicalId) do
			if index > 1 then
				table.insert(rows, UI.Divider({ id = "Rule" .. index }))
			end
			local kind = fact.kind
			local value = fact.value
			table.insert(
				rows,
				parts.factRow(
					app,
					"Fact" .. index,
					app.text(fact.key),
					app.own(core:memo(function(use)
						local locale = use(i18n.locale)
						local key = if kind == "grams"
							then "facts.grams"
							elseif kind == "mg" then "facts.mg"
							elseif kind == "minutes" then "facts.minutes"
							else "facts.warmthValue"
						return i18n.at(locale, key, { value = i18n.numberAt(locale, value) })
					end))
				)
			)
		end
		table.insert(
			rows,
			UI.Button({
				id = "CardFactsClose",
				label = app.text("card.factsClose"),
				shape = "circle",
				icon = "chevron.leading",
				onActivate = function()
					app.commands.flipCard(false)
				end,
			})
		)
		-- THE MATERIALS ADAPTATION (ledger §A): Roblox cannot blur UI behind UI,
		-- so the facts face is a stated TRANSLUCENT plate — a tinted `Box`
		-- (the one class that takes the continuous channel) under the rows —
		-- and it is never called a blur anywhere in this proof.
		return UI.ZStack({
			id = "Back",
			width = dims.fill,
			height = dims.fill,
			children = {
				UI.Box({
					id = "Plate",
					width = dims.fill,
					height = dims.fill,
					surface = "raised",
					tint = { role = "surfaceStrong", blend = 1, transparency = 0.1 },
				}),
				-- MEASURED ROWS SCROLL. A card is a fixed box and a facts table is
				-- as tall as the reader's type preference makes it, so the rows
				-- get a scroller instead of painting over the card's edge.
				-- AN EXPLICIT BOX ON BOTH AXES. A `fill` scroller still measures its
				-- own content, so the facts rows' natural width leaked out through
				-- the face and past the card's edge; a percent box is a real box and
				-- stops the propagation on the axis it names.
				UI.ScrollView({
					id = "Rows",
					axis = "y",
					gap = "s",
					padding = "s",
					width = dims.percent(1),
					height = dims.percent(1),
					children = rows,
				}),
			},
		})
	end

	--[[ task POP fix round 1 (sweep found this real): `Card` is itself the
		plate (`surface = "raised"`) AND, before this fix, the direct
		container of the flip content — `Body`'s `materialize`/`fade` push
		transition (`presenter.presentModal`) used to fade `Card`'s own
		background in lockstep with the flip face's text (`newpop.mov`'s
		mechanism). `Card` stays the outer, non-canvasGroup plate; `Group` is
		the ONE new canvasGroup, nested one level in. ]]
	return UI.Screen({
		id = "BotanicalCard",
		padding = 0,
		children = {
			UI.ZStack({
				id = "Body",
				width = dims.fill,
				height = dims.fill,
				alignH = "center",
				alignV = "center",
				children = {
					UI.ZStack({
						id = "Card",
						width = dims.percentMax(0.92, "app.sip.cardW"),
						height = dims.percentMax(0.9, "app.sip.cardH"),
						surface = "raised",
						corners = UI.cornersData("panel"),
						shadow = UI.shadowData("overlay"),
						children = {
							UI.ZStack({
								id = "Group",
								canvasGroup = true,
								width = dims.fill,
								height = dims.fill,
								children = {
									parts.flipPlate(app, {
										id = "Flip",
										progress = progress,
										width = dims.fill,
										height = dims.fill,
										front = frontFace,
										back = backFace,
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the guard alert (spec §8) — a blocked verb that explains itself
-- ---------------------------------------------------------------------------

function detail.guardAlert(app: any, reasonKey: string): any
	local UI = app.UI
	local body = if app.services.i18n.has(reasonKey) then reasonKey else "guard.fallback"
	return UI.Screen({
		id = "GuardAlert",
		padding = "m",
		children = {
			UI.ZStack({
				id = "Body",
				canvasGroup = true,
				width = dims.fill,
				height = dims.fill,
				alignH = "center",
				alignV = "center",
				children = {
					-- THE REASON IS NEVER CUT. A guard alert exists to explain
					-- itself, so at a small viewport (or 1.4x copy at the largest
					-- text preference) the alert SCROLLS instead of painting its
					-- body outside the screen.
					UI.ScrollView({
						id = "AlertScroll",
						axis = "y",
						width = dims.percentMax(0.92, "app.sip.cardW"),
						height = dims.percent(0.9),
						children = {
							UI.VStack({
								id = "Alert",
								surface = "raised",
								corners = UI.cornersData("panel"),
								padding = "m",
								gap = "s",
								align = "center",
								width = dims.fill,
								children = {
									UI.Text({
										id = "Title",
										text = app.text("guard.title"),
										textSize = "heading",
									}),
									UI.Text({
										id = "Reason",
										text = app.text(body),
										role = "secondary",
										textSize = "body",
										width = dims.fill,
									}),
									UI.Button({
										id = "GuardOK",
										label = app.text("common.ok"),
										corners = UI.cornersData("pill"),
										onActivate = function()
											app.commands.dismissGuard()
										end,
									}),
								},
							}),
						},
					}),
				},
			}),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the Order-Placed screen and its flip disc (spec §8)
-- ---------------------------------------------------------------------------

function detail.orderPlaced(app: any, blendId: string, progress: any): any
	local UI = app.UI
	local core = app.core
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local pickup = app.own(core:memo(function(use)
		local locale = use(i18n.locale)
		return i18n.at(locale, "placed.pickup", {
			title = i18n.nameAt(locale, "blend", blendId, catalog.blend(blendId).title),
		})
	end))

	local function face(id: string, headingKey: string, body: any): any
		return UI.VStack({
			id = id,
			gap = "s",
			padding = "m",
			align = "center",
			width = dims.fill,
			height = dims.fill,
			children = {
				UI.Text({
					id = "Heading",
					text = app.text(headingKey),
					textSize = "heading",
					textAlign = "center",
					lineLimit = 2,
					disclose = true,
					width = dims.fill,
				}),
				UI.Text({
					id = "Body",
					text = body,
					role = "secondary",
					textSize = "body",
					textAlign = "center",
					lineLimit = 3,
					disclose = true,
					width = dims.fill,
				}),
			},
		})
	end

	return UI.Screen({
		id = "OrderPlaced",
		padding = 0,
		children = {
			UI.ZStack({
				id = "Body",
				canvasGroup = true,
				width = dims.fill,
				height = dims.fill,
				alignH = "center",
				alignV = "center",
				children = {
					parts.artPlate(app, "blend", blendId, {
						id = "Backdrop",
						width = dims.fill,
						height = dims.fill,
						markSize = "title",
					}),
					-- the veil: a stated translucent plate over the art, never a blur
					UI.Box({
						id = "Veil",
						width = dims.fill,
						height = dims.fill,
						tint = { role = "surface", blend = 1, transparency = 0.35 },
					}),
					UI.ZStack({
						id = "Disc",
						-- a share of the viewport, capped at the spec's disc, and
						-- 1:1 by derivation rather than by two numbers agreeing
						width = dims.percentMax(0.8, "app.sip.orderCard"),
						height = dims.aspect(1),
						surface = "raised",
						corners = UI.cornersData("pill"),
						children = {
							parts.flipPlate(app, {
								id = "Flip",
								progress = progress,
								width = dims.fill,
								height = dims.fill,
								front = function()
									return face("Waiting", "placed.thanks", app.text("placed.notify"))
								end,
								back = function()
									return face("Ready", "placed.ready", pickup)
								end,
							}),
						},
					}),
					UI.Button({
						id = "Done",
						label = app.text("common.done"),
						corners = UI.cornersData("pill"),
						alignH = "end",
						alignV = "start",
						margin = "m",
						onActivate = function()
							app.commands.dismissOrderPlaced()
						end,
					}),
				},
			}),
		},
	})
end

return detail
