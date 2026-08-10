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

-- a modal's body: the presenter's fading surface transition targets the root's
-- single declared canvasGroup child, so every modal in this proof has exactly one
local function sheet(ctx: any, id: string, children: { any }): any
	return ctx.UI.Screen({
		id = id,
		children = {
			ctx.UI.ZStack({
				id = "Sheet",
				canvasGroup = true,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = children,
			}),
		},
	})
end

shop.sheet = sheet

-- ---- S3: the nectar picker ---------------------------------------------------

-- is a purchase for this nectar in flight right now? While one is, the card's
-- action is disabled and says "Confirming…" — pending never reads as success,
-- and it never reads as "go ahead and use one" either.
local function pendingFor(ctx: any, nectarId: string, scope: any): any
	return scope:own(ctx.core:memo(function(use)
		for _, pack in seedData.packsFor(nectarId) do
			if use(ctx.commerce.status(pack.id)) == "pending" then
				return true
			end
		end
		return false
	end))
end

local function nectarCard(ctx: any, nectar: any, gladeId: string, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local name = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("nectar." .. nectar.id)
	end))
	local summary = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("summary." .. nectar.id)
	end))
	local pending = pendingFor(ctx, nectar.id, scope)
	local owned = if nectar.premium then ctx.commerce.satchelOf(nectar.id) else nil

	local mode = scope:own(core:memo(function(use)
		if use(pending) then
			return "pending"
		end
		if not nectar.premium then
			return "choose"
		end
		return if use(owned) > 0 then "use" else "shop"
	end))
	local actionLabel = scope:own(core:memo(function(use)
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
	end))
	local actionEnabled = scope:own(core:memo(function(use)
		return use(mode) ~= "pending"
	end))

	local well: { any } = {}
	if nectar.premium then
		-- the owned count, counted UP on the badge when a purchase confirms
		local counter = scope:own(ctx.clock:counter(owned:get(), "reward"))
		scope:own(core:observe(owned, function(value: number)
			counter:setTarget(value)
		end))
		local countText = scope:own(core:memo(function(use)
			return tostring(math.floor(use(counter)))
		end))
		table.insert(
			well,
			UI.Text({
				id = "Count",
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
		UI.VStack({
			id = "NectarCard_" .. nectar.id,
			surface = "raised",
			padding = "m",
			gap = "s",
			width = { type = "fixed", px = METRICS.nectarCardMin },
			children = {
				parts.well(ctx, "Art", nectar.art, METRICS.portrait, well),
				UI.Text({ id = "Name", text = name, textSize = "label", lineLimit = 1, disclose = true }),
				-- two lines are RESERVED by the layout so a shelf of cards never
				-- jitters as summaries of different lengths scroll past
				UI.Text({
					id = "Summary",
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
				UI.Button({
					id = "Act_" .. nectar.id,
					label = actionLabel,
					enabled = actionEnabled,
					width = { type = "fill", weight = 1 },
					onActivate = function()
						local phase = mode:get()
						if phase == "shop" then
							ctx.nav.openShop()
						elseif phase == "use" or phase == "choose" then
							ctx.nav.chooseNectar(gladeId, nectar.id)
						end
					end,
				}),
			},
		}),
		"raised"
	)
end

local function shelf(ctx: any, id: string, nectars: { any }, gladeId: string, scope: any): any
	local children: { any } = {}
	for _, nectar in nectars do
		table.insert(children, nectarCard(ctx, nectar, gladeId, scope))
	end
	return ctx.UI.ScrollView({
		id = id,
		axis = "x",
		gap = "m",
		width = { type = "fill", weight = 1 },
		children = children,
	})
end

function shop.picker(ctx: any, gladeId: string, scope: any): any
	local UI = ctx.UI
	return sheet(ctx, "NectarPicker", {
		UI.ScrollView({
			id = "Page",
			axis = "y",
			gap = "l",
			padding = "l",
			surface = "raised",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.HStack({
					id = "TitleRow",
					gap = "s",
					align = "center",
					width = { type = "fill", weight = 1 },
					children = {
						parts.heading(ctx, "Title", ctx.L("picker.title")),
						UI.Spacer({ id = "Push" }),
						UI.Button({
							id = "Done",
							label = ctx.L("picker.done"),
							compactLabel = "OK",
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
					},
				}),
				UI.Button({
					id = "ShopRow",
					label = ctx.L("picker.shopRow"),
					width = { type = "fill", weight = 1 },
					align = "start",
					onActivate = function()
						ctx.nav.openShop()
					end,
				}),
				parts.heading(ctx, "PremiumTitle", ctx.L("picker.premium")),
				shelf(ctx, "PremiumShelf", seedData.PREMIUM, gladeId, scope),
				parts.heading(ctx, "StandardTitle", ctx.L("picker.standard")),
				shelf(ctx, "StandardShelf", seedData.STANDARD, gladeId, scope),
			},
		}),
	})
end

-- ---- S4: the provision shop --------------------------------------------------

local function packCard(ctx: any, pack: any, wide: boolean, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local nectarName = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("nectar." .. pack.nectar)
	end))
	local sizeLabel = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if pack.quantity > 1 then "shop.bundle" else "shop.single")
	end))
	local price = ctx.commerce.priceOf(pack.id)

	local width = if wide then { type = "fill", weight = 1 } else { type = "fixed", px = METRICS.packCardMin }
	local body: { any } = {
		parts.well(ctx, "Art", pack.art, METRICS.portrait),
		UI.Text({ id = "Name", text = nectarName, textSize = "label", lineLimit = 1, disclose = true }),
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
			-- decorative and duplicated by the hero's own position, so the chip caps
			-- its own growth rather than pushing the card around
			UI.Text({
				id = "BestValue",
				text = ctx.L("shop.bestValue"),
				surface = "chip",
				textSize = "caption",
				lineLimit = 1,
				alignH = "end",
			})
		)
	end

	return UI.shadow(
		UI.VStack({
			id = "Pack_" .. pack.id,
			surface = "raised",
			padding = "m",
			gap = "s",
			width = width,
			children = body,
		}),
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
		UI.HStack({
			id = "TitleRow",
			gap = "s",
			align = "center",
			width = { type = "fill", weight = 1 },
			children = {
				parts.heading(ctx, "Title", ctx.L("shop.title")),
				UI.Spacer({ id = "Push" }),
				UI.Button({
					id = "Close",
					label = ctx.L("wisp.close"),
					compactLabel = { icon = "close" },
					onActivate = function()
						ctx.nav.dismissTop()
					end,
				}),
			},
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
		local name = scope:own(ctx.core:memo(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("nectar." .. nectar.id)
		end))
		table.insert(children, parts.caption(ctx, "Shelf_" .. nectar.id .. "_Title", name))
		table.insert(
			children,
			UI.ScrollView({
				id = "Shelf_" .. nectar.id,
				axis = "x",
				gap = "m",
				width = { type = "fill", weight = 1 },
				children = row,
			})
		)
	end

	return sheet(ctx, "ProvisionShop", {
		UI.ScrollView({
			id = "Page",
			axis = "y",
			gap = "l",
			padding = "l",
			surface = "raised",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = children,
		}),
	})
end

-- ---- S5: the Keeper's Charm --------------------------------------------------

function shop.charm(ctx: any, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local upgrading = scope:own(core:memo(function(use)
		return use(ctx.commerce.charmTier()) ~= "none"
	end))
	local pitch = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if use(upgrading) then "charm.upgradePitch" else "charm.pitch")
	end))

	local tiers: { any } = {}
	for _, tier in seedData.CHARM_TIERS do
		-- UPGRADE-ONLY MODE: a tier at or below the one held is not offered. The
		-- gate is a `When` over the tier fact, so buying Grove takes Ember's card
		-- off the screen with no rebuild and no branch in a factory.
		local offered = scope:own(core:memo(function(use)
			return tier.rank > (seedData.CHARM_RANK[use(ctx.commerce.charmTier())] or 0)
		end))
		local name = scope:own(core:memo(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("charm.tier." .. tier.id)
		end))
		local tagline = scope:own(core:memo(function(use)
			local _ = use(ctx.state.locale)
			return ctx.Lnow("charm.tagline." .. tier.id)
		end))
		table.insert(
			tiers,
			UI.When({
				id = "TierGate_" .. tier.id,
				condition = offered,
				transition = { enter = "fade", class = "container" },
				thenView = function(): any
					return UI.ZStack({
						id = "TierGroup",
						canvasGroup = true,
						width = { type = "fill", weight = 1 },
						children = {
							UI.VStack({
								id = "Tier_" .. tier.id,
								surface = "raised",
								padding = "m",
								gap = "s",
								width = { type = "fill", weight = 1 },
								children = {
									UI.Text({ id = "Name", text = name, textSize = "heading" }),
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
								},
							}),
						},
					})
				end,
			})
		)
	end

	return sheet(ctx, "CharmShop", {
		UI.ScrollView({
			id = "Page",
			axis = "y",
			gap = "l",
			padding = "l",
			surface = "raised",
			width = { type = "fill", weight = 1 },
			height = { type = "fill", weight = 1 },
			children = {
				UI.HStack({
					id = "TitleRow",
					gap = "s",
					align = "center",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Spacer({ id = "Push" }),
						UI.Button({
							id = "Close",
							label = ctx.L("wisp.close"),
							compactLabel = { icon = "close" },
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
					},
				}),
				-- the marketing header: the hero species floating over a soft glow
				UI.ZStack({
					id = "Header",
					width = { type = "fill", weight = 1 },
					children = {
						UI.corners(
							UI.Box({
								id = "Glow",
								surface = "raised",
								alignH = "center",
								alignV = "center",
								width = { type = "fixed", px = METRICS.heroPortrait * 2 },
								height = { type = "fixed", px = METRICS.heroPortrait },
							}),
							"pill"
						),
						UI.VStack({
							id = "HeaderCopy",
							gap = "s",
							align = "center",
							width = { type = "fill", weight = 1 },
							children = {
								sceneLib.portrait(ctx, "Hero", "tidewisp", METRICS.heroPortrait),
								UI.Text({ id = "Title", text = ctx.L("charm.title"), textSize = "title" }),
								parts.body(ctx, "Pitch", pitch),
							},
						}),
					},
				}),
				UI.VStack({
					id = "Tiers",
					gap = "m",
					width = { type = "fill", weight = 1 },
					children = tiers,
				}),
			},
		}),
	})
end

-- ---- S6: wisp info -----------------------------------------------------------

function shop.wisp(ctx: any, wispId: string, scope: any): any
	local UI = ctx.UI
	local core = ctx.core
	local species = seedData.WISP_BY_ID[wispId]
	local name = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("wisp." .. wispId)
	end))
	local line = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("species." .. wispId)
	end))
	local seen = scope:own(core:memo(function(use)
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
	end))
	local favourite = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("wisp.favourite", { nectar = ctx.Lnow("nectar." .. species.favourite) })
	end))
	local gated = scope:own(core:memo(function(use)
		return species.lumenOnly == true and use(ctx.commerce.charmTier()) ~= "lumen"
	end))

	return sheet(ctx, "WispInfo", {
		UI.VStack({
			id = "Panel",
			surface = "raised",
			padding = "l",
			gap = "m",
			align = "center",
			width = { type = "fill", weight = 1 },
			children = {
				UI.HStack({
					id = "TitleRow",
					gap = "s",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Spacer({ id = "Push" }),
						UI.Button({
							id = "Close",
							label = ctx.L("wisp.close"),
							compactLabel = { icon = "close" },
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
					},
				}),
				sceneLib.portrait(ctx, "Portrait", wispId, METRICS.heroPortrait),
				UI.Text({ id = "Name", text = name, textSize = "heading" }),
				parts.body(ctx, "Species", line),
				parts.caption(ctx, "Seen", seen),
				parts.chip(ctx, "Favourite", favourite),
				UI.When({
					id = "LumenGate",
					condition = gated,
					transition = { enter = "fade", class = "container" },
					thenView = function(): any
						return UI.ZStack({
							id = "GateGroup",
							canvasGroup = true,
							children = {
								UI.VStack({
									id = "GateBody",
									gap = "s",
									align = "center",
									children = {
										parts.chip(ctx, "LumenChip", ctx.L("wisp.lumenPitch")),
										UI.Button({
											id = "SeeCharm",
											label = ctx.L("offer.cta"),
											onActivate = function()
												ctx.nav.openCharm()
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
	})
end

return shop
