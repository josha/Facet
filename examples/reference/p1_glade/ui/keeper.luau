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
	local UI = ctx.UI
	local core = ctx.core
	local scope = ctx.scope

	local tierLabel = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		local tier = use(ctx.commerce.charmTier())
		if tier == "none" then
			return ctx.Lnow("keeper.charmStatusNone")
		end
		return ctx.Lnow("keeper.charmStatus", { tier = ctx.Lnow("charm.tier." .. tier) })
	end))
	local charmCta = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow(if use(ctx.commerce.charmTier()) == "none" then "keeper.charmNone" else "keeper.charmUpgrade")
	end))
	local charmOffered = scope:own(core:memo(function(use)
		return use(ctx.commerce.charmTier()) ~= "lumen"
	end))
	local joined = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		return ctx.Lnow("keeper.joined", { date = seedData.KEEPER.joined })
	end))
	local restoreLabel = scope:own(core:memo(function(use)
		local _ = use(ctx.state.locale)
		if use(ctx.commerce.status("restore")) == "pending" then
			return ctx.Lnow("keeper.restoring")
		end
		return ctx.Lnow("keeper.restore")
	end))

	return UI.ScrollView({
		id = "KeeperPage",
		axis = "y",
		gap = "l",
		padding = "l",
		width = UI.fill(),
		height = UI.fill(),
		children = {
			UI.HStack({
				id = "Header",
				gap = "m",
				align = "center",
				width = UI.fill(),
				children = {
					sceneLib.portrait(ctx, "Portrait", "tidewisp", METRICS.heroPortrait),
					UI.VStack({
						id = "Who",
						gap = "xs",
						width = UI.fill(),
						children = {
							UI.Text({
								id = "Name",
								text = ctx.state.keeperName,
								textSize = "heading",
								lineLimit = 1,
								disclose = true,
							}),
							parts.caption(ctx, "Joined", joined),
						},
					}),
				},
			}),
			UI.VStack({
				id = "CharmRow",
				surface = "raised",
				padding = "m",
				gap = "s",
				width = UI.fill(),
				children = {
					parts.caption(ctx, "Status", tierLabel),
					UI.When({
						id = "CharmCta",
						condition = charmOffered,
						transition = { enter = "fade", class = "container" },
						thenView = function(): any
							return UI.ZStack({
								id = "CtaGroup",
								canvasGroup = true,
								children = {
									UI.Button({
										id = "OpenCharm",
										label = charmCta,
										onActivate = function()
											ctx.nav.openCharm()
										end,
									}),
								},
							})
						end,
					}),
				},
			}),
			UI.VStack({
				id = "RestoreRow",
				gap = "s",
				width = UI.fill(),
				children = {
					parts.commandButton(ctx, {
						id = "Restore",
						commandId = "restore",
						label = restoreLabel,
						onActivate = function()
							ctx.nav.restore()
						end,
					}),
					parts.rejectionNotice(ctx, "RestoreReject", "restore"),
				},
			}),
			UI.Button({
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
		},
	})
end

-- ---- S7a: the edit form ------------------------------------------------------
-- Done commits the drafts to the keeper facts; Cancel discards them. No
-- validation, deliberately: the reference form has none and inventing one would
-- be a different screen.
function keeper.editForm(ctx: any, scope: any): any
	local UI = ctx.UI
	local nameField = ctx.Facet.Controls.TextInput(ctx.core, {
		id = "NameField",
		value = ctx.state.draftName,
		placeholder = ctx.L("keeper.displayName"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})
	local contactField = ctx.Facet.Controls.TextInput(ctx.core, {
		id = "ContactField",
		value = ctx.state.draftContact,
		placeholder = ctx.L("keeper.contact"),
		clearButton = true,
		env = ctx.env,
		actionSystem = ctx.actionSystem,
	})
	scope:own(nameField)
	scope:own(contactField)

	return shopLib.sheet(ctx, "EditKeeperForm", {
		UI.ScrollView({
			id = "Page",
			axis = "y",
			gap = "l",
			padding = "l",
			surface = "raised",
			width = UI.fill(),
			height = UI.fill(),
			children = {
				parts.heading(ctx, "Title", ctx.L("keeper.editTitle")),
				UI.VStack({
					id = "Fields",
					gap = "m",
					width = UI.fill(),
					children = {
						UI.VStack({
							id = "NameRow",
							gap = "xs",
							width = UI.fill(),
							children = {
								parts.caption(ctx, "NameLabel", ctx.L("keeper.displayName")),
								nameField.blueprint,
							},
						}),
						UI.VStack({
							id = "ContactRow",
							gap = "xs",
							width = UI.fill(),
							children = {
								parts.caption(ctx, "ContactLabel", ctx.L("keeper.contact")),
								contactField.blueprint,
							},
						}),
					},
				}),
				UI.HStack({
					id = "Actions",
					gap = "s",
					width = UI.fill(),
					children = {
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
					},
				}),
			},
		}),
	})
end

-- ---- S7b: the Fresh Start confirm -------------------------------------------
function keeper.confirmReset(ctx: any): any
	local UI = ctx.UI
	return shopLib.sheet(ctx, "FreshStartConfirm", {
		UI.VStack({
			id = "Alert",
			surface = "raised",
			padding = "l",
			gap = "m",
			alignH = "center",
			alignV = "center",
			children = {
				parts.heading(ctx, "Title", ctx.L("keeper.confirmTitle")),
				parts.body(ctx, "Body", ctx.L("keeper.confirmBody")),
				UI.HStack({
					id = "Actions",
					gap = "s",
					children = {
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
					},
				}),
			},
		}),
	})
end

return keeper
