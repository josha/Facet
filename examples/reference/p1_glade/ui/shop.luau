--!strict
-- Glade (RA-P1) — S3 nectar picker, S4 provision shop, S5 Keeper's Charm and
-- S6 wisp info (spec §§9–10).
--
-- Every purchase-shaped verb on these three surfaces runs the SAME lifecycle
-- through `parts.commandButton`: idle → pending (disabled, "Confirming…") →
-- confirmed | rejected, with the rejection's player-facing copy appearing
-- directly under the control that was pressed. There is no optimistic path
-- anywhere in this proof: a count moves when the command confirms and not one
-- frame before.

local seedData = require("../content/seed")
local sceneLib = require("./scene")
local parts = require("./parts")

local shop = {}

local METRICS = seedData.METRICS

-- a modal's body. USED TO read "the presenter's fading surface transition
-- targets the root's single declared canvasGroup CHILD, so every modal in this
-- proof has exactly one" — `Sheet` itself was that child, wrapping the whole
-- card, backdrop included. `GroupTransparency` is one engine scalar over the
-- WHOLE subtree it composites, so a plate declared inside it fades exactly as
-- fast as the text sitting on it: the backdrop can never be legible ahead of
-- the content (task POP, director item 10 + mandate b — measured on this
-- file's own `shop.wisp`, `GroupTransparency` sampled at 1, 0.73, 0.23, 0.003
-- across a 30-tick materialize, the plate riding every one of those numbers).
--
-- `Sheet` is now a plain positioning ZStack, never the fade group. Each caller
-- below puts its OWN opaque plate outside a NESTED `canvasGroup` instead
-- (`page()` right below does it once for S3/S4/S5; `shop.wisp` does it inline
-- for its one-off card shape) — `src/render/transitions.luau`'s
-- `resolveAlphaTarget` finds that descendant and fades it there, while `Sheet`
-- still carries the whole card's slide/scale as one rigid unit (transform
-- needs no group at all; only alpha does).
local function sheet(ctx: any, id: string, children: { any }): any
	return ctx.UI.Screen(id)({

		ctx.UI.ZStack("Sheet")(ctx.withChildren({
			width = ctx.UI.fill(),
			height = ctx.UI.fill(),
		}, children)),
	})
end

shop.sheet = sheet

-- the shared FULL-BLEED page body (S3 picker, S4 provisions, S5 charm): one
-- opaque plate (`Page`, NEVER inside the fade group) and its scrollable
-- content in its own `canvasGroup` (`PageContent`) so the plate paints at its
-- own, immediate opacity while the content fades in over it (task POP).
local function page(ctx: any, children: { any }): any
	return ctx.UI.ScrollView("Page")({
		axis = "y",
		padding = "l",
		surface = "raised",
		width = ctx.UI.fill(),
		height = ctx.UI.fill(),

		ctx.UI.ZStack("PageContent")({
			canvasGroup = true,
			width = ctx.UI.fill(),

			ctx.UI.VStack("PageBody")(ctx.withChildren({
				gap = "l",
				width = ctx.UI.fill(),
			}, children)),
		}),
	})
end

shop.page = page

-- ---- S3: the nectar picker ---------------------------------------------------

-- is a purchase for this nectar in flight right now? While one is, the card's
-- action is disabled and says "Confirming…" — pending never reads as success,
-- and it never reads as "go ahead and use one" either.
local function pendingFor(ctx: any, nectarId: string, scope: any): any
	return ctx.Compose.formula(function(use)
		for _, pack in seedData.packsFor(nectarId) do
			if use(ctx.commerce.status(pack.id)) == "pending" then
				return true
			end
		end
		return false
	end)
end

local function nectarCard(ctx: any, nectar: any, gladeId: string, scope: any): any
	local UI = ctx.UI
	local name = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("nectar." .. nectar.id)
	end)
	local summary = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("summary." .. nectar.id)
	end)
	local pending = pendingFor(ctx, nectar.id, scope)
	local owned = if nectar.premium then ctx.commerce.satchelOf(nectar.id) else nil

	local mode = ctx.Compose.formula(function(use)
		if use(pending) then
			return "pending"
		end
		if not nectar.premium then
			return "choose"
		end
		return if use(owned) > 0 then "use" else "shop"
	end)
	local actionLabel = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		local phase = use(mode)
		if phase == "pending" then
			return ctx.Lnow("picker.pending")
		elseif phase == "use" then
			return ctx.Lnow("picker.use")
		elseif phase == "shop" then
			return ctx.Lnow("picker.shop")
		end
		return ctx.Lnow("picker.choose")
	end)
	local actionEnabled = ctx.Compose.formula(function(use)
		return use(mode) ~= "pending"
	end)

	local well: { any } = {}
	if nectar.premium then
		-- the owned count, counted UP on the badge when a purchase confirms
		local counter = ctx.ownMotion(ctx.clock:counter(owned:peek(), "reward"))
		ctx.observe(owned, function(value: number)
			counter:setTarget(value)
		end)
		local countText = ctx.Compose.formula(function(use)
			return tostring(math.floor(use(counter)))
		end)
		table.insert(
			well,
			UI.Text("Count")({
				text = countText,
				surface = "badge",
				textSize = "numeral",
				textAlign = "center",
				alignH = "end",
				alignV = "end",
			})
		)
	end

	return UI.shadow(
		UI.VStack("NectarCard_" .. nectar.id)({
			surface = "raised",
			padding = "m",
			gap = "s",
			width = { type = "fixed", px = METRICS.nectarCardMin },

			parts.well(ctx, "Art", nectar.art, METRICS.portrait, well),
			UI.Text("Name")({ text = name, textSize = "label", lineLimit = 1, disclose = true }),
			-- two lines are RESERVED by the layout so a shelf of cards never
			-- jitters as summaries of different lengths scroll past
			UI.Text("Summary")({
				text = summary,
				textSize = "body",
				role = "secondary",
				lineLimit = 2,
				disclose = true,
			}),
			-- no `compactLabel`: this button's label IS its phase, and a
			-- construction-only compact form cannot follow it (see
			-- `parts.commandButton`). An ellipsized "Confirming…" is honest;
			-- the word "Shop" drawn during a pending purchase is not.
			UI.Button("Act_" .. nectar.id)({
				label = actionLabel,
				enabled = actionEnabled,
				width = UI.fill(),
				onActivate = function()
					local phase = mode:peek()
					if phase == "shop" then
						ctx.nav.openShop()
					elseif phase == "use" or phase == "choose" then
						ctx.nav.chooseNectar(gladeId, nectar.id)
					end
				end,
			}),
		}),
		"raised"
	)
end

local function shelf(ctx: any, id: string, nectars: { any }, gladeId: string, scope: any): any
	local children: { any } = {}
	for _, nectar in nectars do
		table.insert(children, nectarCard(ctx, nectar, gladeId, scope))
	end
	return ctx.UI.ScrollView(id)(ctx.withChildren({
		axis = "x",
		gap = "m",
		width = ctx.UI.fill(),
	}, children))
end

function shop.picker(ctx: any, gladeId: string, scope: any): any
	local UI = ctx.UI
	return sheet(ctx, "NectarPicker", {
		page(ctx, {
			UI.HStack("TitleRow")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				parts.heading(ctx, "Title", ctx.L("picker.title")),
				UI.Spacer("Push")({}),
				UI.Button("Done")({
					label = ctx.L("picker.done"),
					compactLabel = "OK",
					onActivate = function()
						ctx.nav.dismissTop()
					end,
				}),
			}),
			UI.Button("ShopRow")({
				label = ctx.L("picker.shopRow"),
				width = UI.fill(),
				align = "start",
				onActivate = function()
					ctx.nav.openShop()
				end,
			}),
			parts.heading(ctx, "PremiumTitle", ctx.L("picker.premium")),
			shelf(ctx, "PremiumShelf", seedData.PREMIUM, gladeId, scope),
			parts.heading(ctx, "StandardTitle", ctx.L("picker.standard")),
			shelf(ctx, "StandardShelf", seedData.STANDARD, gladeId, scope),
		}),
	})
end

-- ---- S4: the provision shop --------------------------------------------------

local function packCard(ctx: any, pack: any, wide: boolean, scope: any): any
	local UI = ctx.UI
	local nectarName = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("nectar." .. pack.nectar)
	end)
	local sizeLabel = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if pack.quantity > 1 then "shop.bundle" else "shop.single")
	end)
	local price = ctx.commerce.priceOf(pack.id)

	local width = if wide then UI.fill() else { type = "fixed", px = METRICS.packCardMin }
	local body: { any } = {
		parts.well(ctx, "Art", pack.art, METRICS.portrait),
		UI.Text("Name")({ text = nectarName, textSize = "label", lineLimit = 1, disclose = true }),
		parts.caption(ctx, "Size", sizeLabel),
		-- the price NEVER truncates and is never composed in UI copy: the service
		-- publishes the whole string
		parts.chip(ctx, "Price", price),
		parts.commandButton(ctx, {
			id = "Buy_" .. pack.id,
			commandId = pack.id,
			label = ctx.L("shop.buy"),
			onActivate = function()
				ctx.nav.buyPack(pack.id)
			end,
		}),
		parts.rejectionNotice(ctx, "Reject_" .. pack.id, pack.id),
	}
	if pack.hero then
		table.insert(
			body,
			1,
			--[[ decorative and duplicated by the hero's own position, so the chip
				caps its own growth rather than pushing the card around.

				IT USED TO CARRY `alignH = "end"` TOO — a request to sit at the card's
				trailing edge. Its parent `Pack_*` is a VSTACK, which reads no `alignH`
				off a child, so the chip has always sat at the LEADING edge instead
				(§2.1 placement audit, 2026-08-13). `lineAlign = "end"` is the exact
				spelling that would deliver it and it WOULD move pixels, so the prop is
				deleted and the intent is queued in
				`docs/plans/unfulfilled-placement-intents.md`. ]]
			UI.Text("BestValue")({
				text = ctx.L("shop.bestValue"),
				surface = "chip",
				textSize = "caption",
				lineLimit = 1,
			})
		)
	end

	return UI.shadow(
		UI.VStack("Pack_" .. pack.id)(ctx.withChildren({
			surface = "raised",
			padding = "m",
			gap = "s",
			width = width,
		}, body)),
		"raised"
	)
end

function shop.provisions(ctx: any, scope: any): any
	local UI = ctx.UI
	local children: { any } = {}
	local hero: any = nil
	for _, pack in seedData.PACKS do
		if pack.hero then
			hero = pack
		end
	end
	table.insert(
		children,
		UI.HStack("TitleRow")({
			gap = "s",
			align = "center",
			width = UI.fill(),

			parts.heading(ctx, "Title", ctx.L("shop.title")),
			UI.Spacer("Push")({}),
			UI.Button("Close")({
				label = ctx.L("wisp.close"),
				compactLabel = { icon = "close" },
				onActivate = function()
					ctx.nav.dismissTop()
				end,
			}),
		})
	)
	if hero ~= nil then
		table.insert(children, packCard(ctx, hero, true, scope))
	end
	table.insert(children, parts.heading(ctx, "MoreTitle", ctx.L("shop.more")))
	for _, nectar in seedData.PREMIUM do
		local row: { any } = {}
		for _, pack in seedData.packsFor(nectar.id) do
			table.insert(row, packCard(ctx, pack, false, scope))
		end
		local name = ctx.Compose.formula(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("nectar." .. nectar.id)
		end)
		table.insert(children, parts.caption(ctx, "Shelf_" .. nectar.id .. "_Title", name))
		table.insert(
			children,
			UI.ScrollView("Shelf_" .. nectar.id)(ctx.withChildren({
				axis = "x",
				gap = "m",
				width = UI.fill(),
			}, row))
		)
	end

	return sheet(ctx, "ProvisionShop", { page(ctx, children) })
end

-- ---- S5: the Keeper's Charm --------------------------------------------------

function shop.charm(ctx: any, scope: any): any
	local UI = ctx.UI
	local upgrading = ctx.Compose.formula(function(use)
		return use(ctx.commerce.charmTier()) ~= "none"
	end)
	local pitch = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if use(upgrading) then "charm.upgradePitch" else "charm.pitch")
	end)

	local tiers: { any } = {}
	for _, tier in seedData.CHARM_TIERS do
		-- UPGRADE-ONLY MODE: a tier at or below the one held is not offered. The
		-- gate is a `When` over the tier fact, so buying Grove takes Ember's card
		-- off the screen with no rebuild and no branch in a factory.
		local offered = ctx.Compose.formula(function(use)
			return tier.rank > (seedData.CHARM_RANK[use(ctx.commerce.charmTier())] or 0)
		end)
		local name = ctx.Compose.formula(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("charm.tier." .. tier.id)
		end)
		local tagline = ctx.Compose.formula(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("charm.tagline." .. tier.id)
		end)
		table.insert(
			tiers,
			ctx.when("TierGate_" .. tier.id)({
				condition = offered,
				transition = { enter = "fade", class = "container" },
				thenView = function(): any
					-- `TierGroup` is a plain positioning ZStack now (task POP):
					-- `Tier_*` is the opaque plate and stays a DIRECT child of it,
					-- never of the fade group, so it paints immediately; `TierContent`
					-- is the one canvasGroup `resolveAlphaTarget` finds one level
					-- further in, and only its rows ramp in over the plate.
					return UI.ZStack("TierGroup")({
						width = UI.fill(),

						UI.VStack("Tier_" .. tier.id)({
							surface = "raised",
							padding = "m",
							width = UI.fill(),

							UI.ZStack("TierContent")({
								canvasGroup = true,
								width = UI.fill(),

								UI.VStack("TierBody")({
									gap = "s",
									width = UI.fill(),

									UI.Text("Name")({ text = name, textSize = "heading" }),
									parts.body(ctx, "Tagline", tagline),
									parts.chip(ctx, "Price", ctx.commerce.charmPriceOf(tier.id)),
									parts.commandButton(ctx, {
										id = "BuyCharm_" .. tier.id,
										commandId = tier.id,
										label = ctx.L("charm.buy"),
										onActivate = function()
											ctx.nav.buyCharm(tier.id)
										end,
									}),
									parts.rejectionNotice(ctx, "RejectCharm_" .. tier.id, tier.id),
								}),
							}),
						}),
					})
				end,
			})
		)
	end

	return sheet(ctx, "CharmShop", {
		page(ctx, {
			UI.HStack("TitleRow")({
				gap = "s",
				align = "center",
				width = UI.fill(),

				UI.Spacer("Push")({}),
				UI.Button("Close")({
					label = ctx.L("wisp.close"),
					compactLabel = { icon = "close" },
					onActivate = function()
						ctx.nav.dismissTop()
					end,
				}),
			}),
			-- the marketing header: the hero species floating over a soft glow
			UI.ZStack("Header")({
				width = UI.fill(),

				UI.corners(
					UI.Box("Glow")({
						surface = "raised",
						alignH = "center",
						alignV = "center",
						width = { type = "fixed", px = METRICS.heroPortrait * 2 },
						height = { type = "fixed", px = METRICS.heroPortrait },
					}),
					"pill"
				),
				UI.VStack("HeaderCopy")({
					gap = "s",
					align = "center",
					width = UI.fill(),

					sceneLib.portrait(ctx, "Hero", "tidewisp", METRICS.heroPortrait),
					UI.Text("Title")({ text = ctx.L("charm.title"), textSize = "title" }),
					parts.body(ctx, "Pitch", pitch),
				}),
			}),
			UI.VStack("Tiers")(ctx.withChildren({
				gap = "m",
				width = UI.fill(),
			}, tiers)),
		}),
	})
end

-- ---- S6: wisp info -----------------------------------------------------------

function shop.wisp(ctx: any, wispId: string, scope: any): any
	local UI = ctx.UI
	local species = seedData.WISP_BY_ID[wispId]
	local name = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("wisp." .. wispId)
	end)
	local line = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("species." .. wispId)
	end)
	local seen = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		local at = use(ctx.now)
		local last = ctx.visits.lastSeen(wispId)
		if last == nil then
			return ctx.Lnow("wisp.neverSeen")
		end
		return ctx.Lnow("wisp.lastSeen", {
			when = ctx.fmt.relative(at - last.at),
			glade = ctx.Lnow("glade." .. last.glade),
		})
	end)
	local favourite = ctx.Compose.formula(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("wisp.favourite", { nectar = ctx.Lnow("nectar." .. species.favourite) })
	end)
	local gated = ctx.Compose.formula(function(use)
		return species.lumenOnly == true and use(ctx.commerce.charmTier()) ~= "lumen"
	end)

	return sheet(ctx, "WispInfo", {
		-- `Panel` is the opaque plate and is NEVER inside the fade group (task
		-- POP): it stays a direct child of `Sheet` (itself no longer a
		-- canvasGroup — see `sheet`'s header), so it paints at its own, immediate
		-- opacity from the first frame. `PanelContent`, one level in, is the ONE
		-- canvasGroup `resolveAlphaTarget` finds and fades — the card still
		-- slides/scales as a single rigid unit (`Panel`'s own `UIScale`), only its
		-- CONTENT ramps in over the plate that was always there.
		UI.VStack("Panel")({
			surface = "raised",
			padding = "l",
			width = UI.fill(),

			UI.ZStack("PanelContent")({
				canvasGroup = true,
				width = UI.fill(),

				UI.VStack("PanelBody")({
					gap = "m",
					align = "center",
					width = UI.fill(),

					UI.HStack("TitleRow")({
						gap = "s",
						width = UI.fill(),

						UI.Spacer("Push")({}),
						UI.Button("Close")({
							label = ctx.L("wisp.close"),
							compactLabel = { icon = "close" },
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
					}),
					sceneLib.portrait(ctx, "Portrait", wispId, METRICS.heroPortrait),
					UI.Text("Name")({ text = name, textSize = "heading" }),
					parts.body(ctx, "Species", line),
					parts.caption(ctx, "Seen", seen),
					parts.chip(ctx, "Favourite", favourite),
					ctx.when("LumenGate")({
						condition = gated,
						transition = { enter = "fade", class = "container" },
						thenView = function(): any
							return UI.ZStack("GateGroup")({
								canvasGroup = true,

								UI.VStack("GateBody")({
									gap = "s",
									align = "center",

									parts.chip(ctx, "LumenChip", ctx.L("wisp.lumenPitch")),
									UI.Button("SeeCharm")({
										label = ctx.L("offer.cta"),
										onActivate = function()
											ctx.nav.openCharm()
										end,
									}),
								}),
							})
						end,
					}),
				}),
			}),
		}),
	})
end

return shop
