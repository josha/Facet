--!strict
-- Glade (RA-P1) — S7 keeper, S7a edit form, S7b Fresh Start confirm (spec §10).
--
-- "Restore provisions" is a FAKE ledger re-sync and the proof says so plainly:
-- Roblox has no system restore chrome to reach, so this is a proof-owned command
-- with the same three-phase lifecycle every other purchase-shaped verb uses. It
-- is listed in the capability ledger as no-host-equivalent and is not a
-- simulation of one.
--
-- Fresh Start is the loop's reset: the confirm alert refuses an outside tap
-- (`outsideTapCancel = false`) because a destructive choice must be made, not
-- fallen out of, and confirming reseeds every service from the same seed the
-- session started from — which is what makes the dump byte-identical.

local seedData = require("../content/seed")
local sceneLib = require("./scene")
local shopLib = require("./shop")
local parts = require("./parts")

local keeper = {}

local METRICS = seedData.METRICS

function keeper.section(ctx: any): any
	local Keeper = ctx.Facet.component(function(ui)
		local locale = ui.read(ctx.state.locale)
		local charmTier = ui.read(ctx.commerce.charmTier())
		local restoreStatus = ui.read(ctx.commerce.status("restore"))
		local UI = ctx.Facet.View
		local tierLabel = ui.memo(function()
			local _ = locale()
			local tier = charmTier()
			if tier == "none" then
				return ctx.Lnow("keeper.charmStatusNone")
			end
			return ctx.Lnow("keeper.charmStatus", { tier = ctx.Lnow("charm.tier." .. tier) })
		end)
		local charmCta = ui.memo(function()
			local _ = locale()
			return ctx.Lnow(if charmTier() == "none" then "keeper.charmNone" else "keeper.charmUpgrade")
		end)
		local charmOffered = ui.memo(function()
			return charmTier() ~= "lumen"
		end)
		local joined = ui.memo(function()
			local _ = locale()
			return ctx.Lnow("keeper.joined", { date = seedData.KEEPER.joined })
		end)
		local restoreLabel = ui.memo(function()
			local _ = locale()
			if restoreStatus() == "pending" then
				return ctx.Lnow("keeper.restoring")
			end
			return ctx.Lnow("keeper.restore")
		end)
		return UI.ScrollView({
			id = "KeeperPage",
			axis = "y",
			gap = "l",
			padding = "l",
			width = UI.fill(),
			height = UI.fill(),
			UI.HStack({
				id = "Header",
				gap = "m",
				align = "center",
				width = UI.fill(),
				sceneLib.portrait(ctx, "Portrait", "tidewisp", METRICS.heroPortrait),
				UI.VStack({
					id = "Who",
					gap = "xs",
					width = UI.fill(),
					UI.Text({
						id = "Name",
						text = ctx.state.keeperName,
						textSize = "heading",
						lineLimit = 1,
						disclose = true,
					}),
					parts.caption(ctx, "Joined", joined),
				}),
			}),
			UI.VStack({
				id = "CharmRow",
				surface = "raised",
				padding = "m",
				gap = "s",
				width = UI.fill(),
				parts.caption(ctx, "Status", tierLabel),
				UI.When({
					id = "CharmCta",
					condition = charmOffered,
					transition = { enter = "fade", class = "container" },
					thenView = function(): any
						return UI.ZStack({
							id = "CtaGroup",
							canvasGroup = true,
							UI.Button({
								id = "OpenCharm",
								label = charmCta,
								onActivate = function()
									ctx.nav.openCharm()
								end,
							}),
						})
					end,
				}),
			}),
			UI.VStack({
				id = "RestoreRow",
				gap = "s",
				width = UI.fill(),
				parts.commandButton(ctx, {
					id = "Restore",
					commandId = "restore",
					label = restoreLabel,
					onActivate = function()
						ctx.nav.restore()
					end,
				}),
				parts.rejectionNotice(ctx, "RestoreReject", "restore"),
			}),
			ctx.Facet.UI.Button({
				id = "EditKeeper",
				label = ctx.L("keeper.edit"),
				compactLabel = { icon = "edit" },
				onActivate = function()
					ctx.nav.openEdit()
				end,
			}),
			UI.Button({
				id = "FreshStart",
				label = ctx.L("keeper.freshStart"),
				role = "destructive",
				onActivate = function()
					ctx.nav.openFreshStart()
				end,
			}),
		})
	end)
	return Keeper({})
end

function keeper.editForm(ctx: any, scope: any): any
	local UI = ctx.UI
	local nameField = ctx.Facet.View.TextInput({
		id = "NameField",
		value = ctx.state.draftName,
		placeholder = ctx.L("keeper.displayName"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})
	local contactField = ctx.Facet.View.TextInput({
		id = "ContactField",
		value = ctx.state.draftContact,
		placeholder = ctx.L("keeper.contact"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})

	-- NavigationStack supplies the page title and Back chrome.
	return shopLib.page(ctx, {
		UI.VStack({
			id = "Fields",
			gap = "m",
			width = UI.fill(),

			UI.VStack({
				id = "NameRow",
				gap = "xs",
				width = UI.fill(),

				parts.caption(ctx, "NameLabel", ctx.L("keeper.displayName")),
				nameField,
			}),
			UI.VStack({
				id = "ContactRow",
				gap = "xs",
				width = UI.fill(),

				parts.caption(ctx, "ContactLabel", ctx.L("keeper.contact")),
				contactField,
			}),
		}),
		UI.HStack({
			id = "Actions",
			gap = "s",
			width = UI.fill(),

			UI.Button({
				id = "SaveKeeper",
				label = ctx.L("keeper.save"),
				compactLabel = "OK",
				onActivate = function()
					ctx.nav.saveKeeper()
				end,
			}),
			UI.Button({
				id = "CancelKeeper",
				label = ctx.L("keeper.cancel"),
				role = "cancel",
				onActivate = function()
					ctx.nav.dismissTop()
				end,
			}),
		}),
	})
end

-- ---- S7b: the Fresh Start confirm -------------------------------------------
function keeper.confirmReset(ctx: any): any
	local UI = ctx.UI
	return shopLib.sheet(ctx, "FreshStartConfirm", {
		-- `Alert` is the opaque plate and stays OUTSIDE the fade group (task
		-- POP, the same shape as `shop.wisp`'s `Panel`): it keeps the
		-- positioning props (`alignH`/`alignV`) so the card still centres in
		-- `Sheet`; `AlertContent`, one level in, is the ONE canvasGroup that
		-- actually fades.
		UI.VStack({
			id = "Alert",
			surface = "raised",
			padding = "l",
			alignH = "center",
			alignV = "center",

			UI.ZStack({
				id = "AlertContent",
				canvasGroup = true,

				UI.VStack({
					id = "AlertBody",
					gap = "m",

					parts.heading(ctx, "Title", ctx.L("keeper.confirmTitle")),
					parts.body(ctx, "Body", ctx.L("keeper.confirmBody")),
					UI.HStack({
						id = "Actions",
						gap = "s",

						UI.Button({
							id = "KeepGlades",
							label = ctx.L("keeper.keep"),
							role = "cancel",
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
						UI.Button({
							id = "StartOver",
							label = ctx.L("keeper.startOver"),
							role = "destructive",
							onActivate = function()
								ctx.nav.confirmFreshStart()
							end,
						}),
					}),
				}),
			}),
		}),
	})
end

return keeper
