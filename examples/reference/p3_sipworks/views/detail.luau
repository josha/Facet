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

-- A row owns what its builder makes.
local function ownIn(_row: any, readable: any): any
	return readable
end

-- ---------------------------------------------------------------------------
-- the adaptive header (spec §7)
-- ---------------------------------------------------------------------------

local function descriptionRuns(app: any, id: string): any
	local UI = app.UI
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local runs = app.own(app.Compose.formula(function(use)
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

	return UI.VStack(id)({
		gap = "xs",
		width = dims.fill,

		app.forEach("Runs")({
			items = runs,
			key = function(run: any)
				return run.key
			end,
			row = function(run: any)
				-- THE DECLARED EMPHASIS APPROXIMATION (ledger §D): emphasis is
				-- a whole paragraph drawn at the `strong` type role. There is no
				-- rich-text span engine here and none is claimed.
				return UI.Text("Run")({
					text = run.text,
					textSize = if run.emphasis then "strong" else "body",
					width = dims.fill,
				})
			end,
		}),
	})
end

local function header(app: any): any
	local UI = app.UI
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local title = app.own(app.Compose.formula(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return ""
		end
		return i18n.nameAt(use(i18n.locale), "blend", blendId, catalog.blend(blendId).title)
	end))
	local caffeine = app.own(app.Compose.formula(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return ""
		end
		return i18n.at(use(i18n.locale), "row.caffeine", { n = catalog.caffeineMg(blendId) })
	end))
	local function texts(id: string, width: any): any
		return UI.VStack(id)({
			gap = "s",
			padding = "l",
			width = width,

			UI.Text("Title")({ text = title, textSize = "title", width = dims.fill }),
			descriptionRuns(app, "Description" .. id),
			UI.Text("Caffeine")({ text = caffeine, role = "secondary", textSize = "caption" }),
		})
	end

	-- The art plate is bound to the SELECTION through a keyed `ForEach` of
	-- exactly one item — the framework's own idiom for "this subtree belongs to
	-- that key", and the reason changing blends re-keys the picture instead of
	-- rebuilding the header.
	local function art(id: string, width: any, height: any): any
		return app.forEach(id)({
			items = app.own(app.Compose.formula(function(use)
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

	return UI.ViewThatFits("Header")({

		-- 1. the WIDE CARD. It states a real minimum for its text column
		-- rather than a `fill`: a fill child inside a candidate always fits,
		-- so a fill here would make this candidate win on a phone.
		UI.HStack("WideCard")({
			surface = "raised",
			corners = UI.cornersData("panel"),
			stroke = UI.strokeData({}),
			gap = "m",
			align = "center",

			texts("WideText", dims.fixed("app.sip.headerTextMin")),
			-- the art matches the CARD's height rather than pinning it: a
			-- fixed-height plate beside a text column that grows (a longer
			-- description, a bigger type preference, a 1.4x locale) is the
			-- fixed-px-height defect class, and the solver's overflow
			-- diagnostic caught exactly that at desktop width.
			UI.ZStack("WideArt")({
				width = dims.fixed("app.sip.headerArtW"),
				height = dims.fill,
				art("WideArtFor", dims.fill, dims.fill),
			}),
		}),
		-- 2. the FULL-BLEED fallback
		UI.VStack("FullBleed")({
			gap = "s",
			width = dims.fill,

			UI.ZStack("BleedArt")({
				width = dims.fill,
				height = dims.aspect(1.2),
				art("BleedArtFor", dims.fill, dims.fill),
			}),
			texts("BleedText", dims.fill),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- the botanical grid (spec §7)
-- ---------------------------------------------------------------------------

local function botanicalGrid(app: any): any
	local UI = app.UI
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local ids = app.own(app.Compose.formula(function(use)
		local blendId = use(app.state.selectedBlendId)
		if blendId == nil then
			return {}
		end
		return catalog.tileBotanicals(blendId)
	end))

	return UI.VStack("Botanicals")({
		gap = "s",
		width = dims.fill,

		-- a floor rather than a natural width, for the reason the recipe's own
		-- heading carries the same shape
		UI.Text("Heading")({
			text = app.text("ingredients.menu"),
			textSize = "heading",
			width = dims.minMax("app.sip.tileArt", "app.sip.tileArt", "app.sip.listPaneMax"),
		}),
		UI.Grid("Tiles")({
			-- "intrinsic" — no column narrower than the widest child MEASURES.
			-- A px literal here reads as a guess about a font, and it is worse
			-- than one: the grid's pitch is innerWidth/columns, so a literal
			-- equal to the art's width produced three columns whose CELLS were
			-- 8px narrower than the art in them.
			minColumnWidth = "intrinsic",
			itemSizing = "uniform",
			gap = "m",
			width = dims.fill,

			app.forEach("Cells")({
				items = ids,
				key = function(id: string)
					return id
				end,
				row = function(botanicalId: string, itemScope: any)
					local botanical = catalog.botanical(botanicalId)
					local label = ownIn(
						itemScope,
						app.Compose.formula(function(use)
							return i18n.nameAt(use(i18n.locale), "botanical", botanicalId, botanical.name)
						end)
					)
					return UI.Button("Tile-" .. botanicalId)({
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

						-- A BUTTON LAYS ITS OWN CONTENT ALONG ONE AXIS, and
						-- that axis is horizontal — so the tile's art and
						-- label need a stack of their own. Without it the
						-- label sat BESIDE the art and every tile overflowed
						-- its grid cell (found by `controller.diagnostics()`,
						-- never by a screenshot).
						UI.VStack("Cell")({
							gap = "xs",
							align = "center",
							width = dims.fixed("app.sip.tileArt"),

							parts.artPlate(app, "botanical", botanicalId, {
								width = dims.fill,
								height = dims.fixed("app.sip.tileArt"),
							}),
							-- the label takes the CELL's width rather than
							-- stating one of its own, so a long localized
							-- name truncates (and discloses) instead of
							-- widening the grid
							UI.Text("Name")({
								text = label,
								textSize = "label",
								lineLimit = 1,
								disclose = true,
								textAlign = "center",
								width = dims.fill,
							}),
						}),
					})
				end,
			}),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- the CTA band (spec §8)
-- ---------------------------------------------------------------------------

local function ctaBand(app: any): any
	local UI = app.UI
	local i18n = app.services.i18n
	local order = app.services.order
	local rewards = app.services.rewards

	local paused = app.own(app.Compose.formula(function(use)
		return not use(order.paymentsEnabled)
	end))
	-- THE REJECTION, AT THE POINT OF ACTION. OrderService acknowledges a refusal
	-- on the same turn (its status is back to `idle` before anything renders) and
	-- the toast that announced it expires in four seconds, so a player who looked
	-- away had nothing left to read. The task's own latch is what this notice is
	-- over: it says what happened, says the stamps were not touched, and leaves
	-- the CTA right underneath it to press again.
	local refused = app.own(app.Compose.formula(function(use)
		return app.entry == "full" and use(app.services.task.refused)
	end))
	-- ONE node, one id, one geometry (spec §8 asks for exactly that), and the
	-- label is a binding — so the pay/redeem swap and the pending state cost no
	-- remount and can never leave two CTAs on screen at once.
	local label = app.own(app.Compose.formula(function(use)
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
	local enabled = app.own(app.Compose.formula(function(use)
		return use(order.status) ~= "pending"
	end))

	return UI.VStack("Cta")({
		gap = "xs",
		width = dims.fill,

		UI.Divider("Rule")({}),
		app.when("GuardNotice")({
			condition = paused,
			transition = { enter = "fade" },
			thenView = function()
				return UI.ZStack("NoticeBox")({
					canvasGroup = true,
					width = dims.fill,

					UI.Text("Notice")({
						text = app.text("guard.paused"),
						surface = "chip",
						role = "secondary",
						textSize = "caption",
						width = dims.fill,
					}),
				})
			end,
		}),
		app.when("RejectNotice")({
			condition = refused,
			transition = { enter = "fade" },
			thenView = function()
				return UI.ZStack("RejectBox")({
					canvasGroup = true,
					width = dims.fill,

					UI.Text("Reject")({
						text = app.text("task.next.rejected"),
						surface = "chip",
						textSize = "caption",
						width = dims.fill,
					}),
				})
			end,
		}),
		UI.HStack("Band")({
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
			-- and a cap a theme cannot move is not a theme number
			height = dims.atLeast("app.sip.ctaBand", "app.sip.ctaBandMax"),
			-- the "bar material" adaptation: a stated raised plate
			surface = "raised",

			UI.corners(
				UI.Button("OrderCTA")({
					label = label,
					enabled = enabled,
					surface = "accent",
					width = dims.fill,
					onActivate = function()
						app.commands.orderCta()
					end,
				}),
				UI.cornersData("pill")
			),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- the detail body, used by BOTH the compact pushed surface and the regular
-- detail pane — one factory, two placements (spec §5)
-- ---------------------------------------------------------------------------

function detail.body(app: any, opts: any): any
	local UI = app.UI
	local options = opts or {}
	-- registry item 13 (W3-D): was a hand-built HStack (a circle
	-- Button with a literal "<" glyph child); the shared bar draws the
	-- framework's own chevron icon instead — see nav_bar.luau's header for
	-- why that is a deliberate, disclosed visual change, not an oversight
	local topBarTrailing: { any } = {}
	if app.entry == "full" then
		table.insert(topBarTrailing, detail.favoriteSlot(app))
	end

	local body = UI.VStack(options.id or "Detail")({
		gap = "s",
		width = dims.fill,
		height = dims.fill,

		parts.navBar(app, {
			id = "TopBar",
			padding = if options.navigationHosted then 0 else "m",
			onBack = if options.showBack
				then function()
					app.commands.closeDetail()
				end
				else nil,
			backLabel = app.text("nav.back"),
			trailing = topBarTrailing,
		}),
		UI.ScrollView("Page")({
			axis = "y",
			gap = "m",
			padding = if options.navigationHosted then 0 else "m",
			width = dims.fill,
			height = dims.fill,

			UI.VStack("Content")({
				gap = "m",
				width = dims.fill,
				header(app),
				botanicalGrid(app),
			}),
		}),
		ctaBand(app),
	})
	if options.navigationHosted then
		-- The stack already spends one header. Keep the favorite, details and
		-- order action in one scroller so a short window can reach every verb.
		return UI.VStack(options.id or "Detail")({
			width = dims.fill,
			height = dims.fill,

			UI.ScrollView("Page")({
				axis = "y",
				gap = "m",
				width = dims.fill,
				height = dims.fill,
				body.children[1],
				body.children[2].children[1],
				body.children[3],
			}),
		})
	end
	return body
end

-- the detail's favorite heart is the row's twin on the SAME signal: one keyed
-- region so it re-targets with the selection without remounting the top bar
function detail.favoriteSlot(app: any): any
	local UI = app.UI
	return app.forEach("FavoriteSlot")({
		items = app.own(app.Compose.formula(function(use)
			local blendId = use(app.state.selectedBlendId)
			return if blendId == nil then {} else { blendId }
		end)),
		key = function(blendId: string)
			return blendId
		end,
		row = function(blendId: string, itemScope: any)
			return listView.favoriteButton(app, blendId, "Favorite")
		end,
	})
end

-- ---------------------------------------------------------------------------
-- the botanical card (the declared hero-card approximation, spec §7)
-- ---------------------------------------------------------------------------

function detail.botanicalCard(app: any, blendId: string, botanicalId: string, progress: any): any
	local UI = app.UI
	local i18n = app.services.i18n
	local catalog = app.services.catalog
	local botanical = catalog.botanical(botanicalId)

	local name = app.own(app.Compose.formula(function(use)
		return i18n.nameAt(use(i18n.locale), "botanical", botanicalId, botanical.name)
	end))

	local function frontFace(): any
		return UI.VStack("Front")({
			gap = "s",
			padding = "m",
			align = "center",
			width = dims.fill,
			height = dims.fill,

			parts.artPlate(app, "botanical", botanicalId, {
				id = "CardArt",
				width = dims.fill,
				height = dims.fill,
				markSize = "title",
			}),
			UI.Text("Name")({ text = name, textSize = "title", textAlign = "center", lineLimit = 2 }),
			UI.HStack("Actions")({
				gap = "m",
				align = "center",

				UI.Button("CardClose")({
					label = app.text("card.close"),
					shape = "circle",
					icon = "close",
					onActivate = function()
						app.commands.closeBotanical()
					end,
				}),
				UI.Button("CardFacts")({
					label = app.text("card.factsOpen"),
					shape = "circle",
					icon = "more",
					onActivate = function()
						app.commands.flipCard(true)
					end,
				}),
			}),
		})
	end

	local function backFace(): any
		local rows: { any } = {
			UI.Text("FactsTitle")({ text = app.text("facts.title"), textSize = "heading" }),
		}
		for index, fact in catalog.factsFor(blendId, botanicalId) do
			if index > 1 then
				table.insert(rows, UI.Divider("Rule" .. index)({}))
			end
			local kind = fact.kind
			local value = fact.value
			table.insert(
				rows,
				parts.factRow(
					app,
					"Fact" .. index,
					app.text(fact.key),
					app.own(app.Compose.formula(function(use)
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
			UI.Button("CardFactsClose")({
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
		return UI.ZStack("Back")({
			width = dims.fill,
			height = dims.fill,

			UI.Box("Plate")({
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
			UI.ScrollView("Rows")(app.withChildren({
				axis = "y",
				gap = "s",
				padding = "s",
				width = dims.percent(1),
				height = dims.percent(1),
			}, rows)),
		})
	end

	--[[ task POP fix round 1 (sweep found this real): `Card` is itself the
		plate (`surface = "raised"`) AND, before this fix, the direct
		container of the flip content — `Body`'s `materialize`/`fade` push
		transition (`presenter.presentModal`) used to fade `Card`'s own
		background in lockstep with the flip face's text (`newpop.mov`'s
		mechanism). `Card` stays the outer, non-canvasGroup plate; `Group` is
		the ONE new canvasGroup, nested one level in. ]]
	return UI.Screen("BotanicalCard")({
		padding = 0,

		UI.ZStack("Body")({
			width = dims.fill,
			height = dims.fill,
			alignH = "center",
			alignV = "center",

			UI.ZStack("Card")({
				width = dims.percentMax(0.92, "app.sip.cardW"),
				height = dims.percentMax(0.9, "app.sip.cardH"),
				surface = "raised",
				corners = UI.cornersData("panel"),
				shadow = UI.shadowData("overlay"),

				UI.ZStack("Group")({
					canvasGroup = true,
					width = dims.fill,
					height = dims.fill,

					parts.flipPlate(app, {
						id = "Flip",
						progress = progress,
						width = dims.fill,
						height = dims.fill,
						front = frontFace,
						back = backFace,
					}),
				}),
			}),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- the guard alert (spec §8) — a blocked verb that explains itself
-- ---------------------------------------------------------------------------

function detail.guardAlert(app: any, reasonKey: string): any
	local UI = app.UI
	local body = if app.services.i18n.has(reasonKey) then reasonKey else "guard.fallback"
	return UI.Screen("GuardAlert")({
		padding = "m",

		UI.ZStack("Body")({
			canvasGroup = true,
			width = dims.fill,
			height = dims.fill,
			alignH = "center",
			alignV = "center",

			-- THE REASON IS NEVER CUT. A guard alert exists to explain
			-- itself, so at a small viewport (or 1.4x copy at the largest
			-- text preference) the alert SCROLLS instead of painting its
			-- body outside the screen.
			UI.ScrollView("AlertScroll")({
				axis = "y",
				width = dims.percentMax(0.92, "app.sip.cardW"),
				height = dims.percent(0.9),

				UI.VStack("Alert")({
					surface = "raised",
					corners = UI.cornersData("panel"),
					padding = "m",
					gap = "s",
					align = "center",
					width = dims.fill,

					UI.Text("Title")({
						text = app.text("guard.title"),
						textSize = "heading",
					}),
					UI.Text("Reason")({
						text = app.text(body),
						role = "secondary",
						textSize = "body",
						width = dims.fill,
					}),
					UI.corners(
						UI.Button("GuardOK")({
							label = app.text("common.ok"),
							onActivate = function()
								app.commands.dismissGuard()
							end,
						}),
						UI.cornersData("pill")
					),
				}),
			}),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- the Order-Placed screen and its flip disc (spec §8)
-- ---------------------------------------------------------------------------

function detail.orderPlaced(app: any, blendId: string, progress: any): any
	local UI = app.UI
	local i18n = app.services.i18n
	local catalog = app.services.catalog

	local pickup = app.own(app.Compose.formula(function(use)
		local locale = use(i18n.locale)
		return i18n.at(locale, "placed.pickup", {
			title = i18n.nameAt(locale, "blend", blendId, catalog.blend(blendId).title),
		})
	end))

	local function face(id: string, headingKey: string, body: any): any
		return UI.VStack(id)({
			gap = "s",
			padding = "m",
			align = "center",
			width = dims.fill,
			height = dims.fill,

			UI.Text("Heading")({
				text = app.text(headingKey),
				textSize = "heading",
				textAlign = "center",
				lineLimit = 2,
				disclose = true,
				width = dims.fill,
			}),
			UI.Text("Body")({
				text = body,
				role = "secondary",
				textSize = "body",
				textAlign = "center",
				lineLimit = 3,
				disclose = true,
				width = dims.fill,
			}),
		})
	end

	return UI.Screen("OrderPlaced")({
		padding = 0,

		UI.ZStack("Body")({
			canvasGroup = true,
			width = dims.fill,
			height = dims.fill,
			alignH = "center",
			alignV = "center",

			parts.artPlate(app, "blend", blendId, {
				id = "Backdrop",
				width = dims.fill,
				height = dims.fill,
				markSize = "title",
			}),
			-- the veil: a stated translucent plate over the art, never a blur
			UI.Box("Veil")({
				width = dims.fill,
				height = dims.fill,
				tint = { role = "surface", blend = 1, transparency = 0.35 },
			}),
			UI.ZStack("Disc")({
				-- a share of the viewport, capped at the spec's disc, and
				-- 1:1 by derivation rather than by two numbers agreeing
				width = dims.percentMax(0.8, "app.sip.orderCard"),
				height = dims.aspect(1),
				surface = "raised",
				corners = UI.cornersData("pill"),

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
			}),
			-- the slot places the button in the corner; its padding is the button's margin
			UI.ZStack("DoneSlot")({
				alignH = "end",
				alignV = "start",
				padding = "m",
				UI.corners(
					UI.Button("Done")({
						label = app.text("common.done"),
						onActivate = function()
							app.commands.dismissOrderPlaced()
						end,
					}),
					UI.cornersData("pill")
				),
			}),
		}),
	})
end

return detail
