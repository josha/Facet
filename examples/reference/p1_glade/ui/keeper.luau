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
	local function Keeper(): any
		local locale = ctx.state.locale
		local charmTier = (ctx.commerce.charmTier())
		local restoreStatus = (ctx.commerce.status("restore"))
		local UI = ctx.UI
		local tierLabel = ctx.Compose.formula(function(use)
			local _ = use(locale)
			local tier = use(charmTier)
			if tier == "none" then
				return ctx.Lnow("keeper.charmStatusNone")
			end
			return ctx.Lnow("keeper.charmStatus", { tier = ctx.Lnow("charm.tier." .. tier) })
		end)
		local charmCta = ctx.Compose.formula(function(use)
			local _ = use(locale)
			return ctx.Lnow(if use(charmTier) == "none" then "keeper.charmNone" else "keeper.charmUpgrade")
		end)
		local charmOffered = ctx.Compose.formula(function(use)
			return use(charmTier) ~= "lumen"
		end)
		local joined = ctx.Compose.formula(function(use)
			local _ = use(locale)
			return ctx.Lnow("keeper.joined", { date = seedData.KEEPER.joined })
		end)
		local restoreLabel = ctx.Compose.formula(function(use)
			local _ = use(locale)
			if use(restoreStatus) == "pending" then
				return ctx.Lnow("keeper.restoring")
			end
			return ctx.Lnow("keeper.restore")
		end)
		return UI.ScrollView("KeeperPage")({
			axis = "y",
			gap = "l",
			padding = "l",
			width = UI.fill(),
			height = UI.fill(),
			UI.HStack("Header")({
				gap = "m",
				align = "center",
				width = UI.fill(),
				sceneLib.portrait(ctx, "Portrait", "tidewisp", METRICS.heroPortrait),
				UI.VStack("Who")({
					gap = "xs",
					width = UI.fill(),
					UI.Text("Name")({
						text = ctx.state.keeperName,
						textSize = "heading",
						lineLimit = 1,
						disclose = true,
					}),
					parts.caption(ctx, "Joined", joined),
				}),
			}),
			UI.VStack("CharmRow")({
				surface = "raised",
				padding = "m",
				gap = "s",
				width = UI.fill(),
				parts.caption(ctx, "Status", tierLabel),
				ctx.when("CharmCta")({
					condition = charmOffered,
					transition = { enter = "fade", class = "container" },
					thenView = function(): any
						return UI.ZStack("CtaGroup")({
							canvasGroup = true,
							UI.Button("OpenCharm")({
								label = charmCta,
								onActivate = function()
									ctx.nav.openCharm()
								end,
							}),
						})
					end,
				}),
			}),
			UI.VStack("RestoreRow")({
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
			UI.Button("EditKeeper")({
				label = ctx.L("keeper.edit"),
				compactLabel = { icon = "edit" },
				onActivate = function()
					ctx.nav.openEdit()
				end,
			}),
			UI.Button("FreshStart")({
				label = ctx.L("keeper.freshStart"),
				role = "destructive",
				onActivate = function()
					ctx.nav.openFreshStart()
				end,
			}),
		})
	end
	return Keeper()
end

function keeper.editForm(ctx: any, scope: any): any
	local UI = ctx.UI
	local nameField = UI.TextInput("NameField")({
		value = ctx.state.draftName,
		placeholder = ctx.L("keeper.displayName"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})
	local contactField = UI.TextInput("ContactField")({
		value = ctx.state.draftContact,
		placeholder = ctx.L("keeper.contact"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})

	-- NavigationStack supplies the page title and Back chrome.
	return shopLib.page(ctx, {
		UI.VStack("Fields")({
			gap = "m",
			width = UI.fill(),

			UI.VStack("NameRow")({
				gap = "xs",
				width = UI.fill(),

				parts.caption(ctx, "NameLabel", ctx.L("keeper.displayName")),
				nameField,
			}),
			UI.VStack("ContactRow")({
				gap = "xs",
				width = UI.fill(),

				parts.caption(ctx, "ContactLabel", ctx.L("keeper.contact")),
				contactField,
			}),
		}),
		UI.HStack("Actions")({
			gap = "s",
			width = UI.fill(),

			UI.Button("SaveKeeper")({
				label = ctx.L("keeper.save"),
				compactLabel = "OK",
				onActivate = function()
					ctx.nav.saveKeeper()
				end,
			}),
			UI.Button("CancelKeeper")({
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
		UI.VStack("Alert")({
			surface = "raised",
			padding = "l",
			alignH = "center",
			alignV = "center",

			UI.ZStack("AlertContent")({
				canvasGroup = true,

				UI.VStack("AlertBody")({
					gap = "m",

					parts.heading(ctx, "Title", ctx.L("keeper.confirmTitle")),
					parts.body(ctx, "Body", ctx.L("keeper.confirmBody")),
					UI.HStack("Actions")({
						gap = "s",

						UI.Button("KeepGlades")({
							label = ctx.L("keeper.keep"),
							role = "cancel",
							onActivate = function()
								ctx.nav.dismissTop()
							end,
						}),
						UI.Button("StartOver")({
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
