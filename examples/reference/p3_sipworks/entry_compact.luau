--!strict
-- THE COMPACT ENTRY FLOW (spec §11) — the second way into Sipworks.
--
-- Production analog: a join `launchData` deep link, validated server-side
-- (responsibility ledger). The App Clip install overlay and its location check
-- have no host equivalent and are not simulated.
--
-- WHAT IS SHARED, BYTE FOR BYTE: `blendRow`, the menu list, search and its
-- botanical suggestions, the whole blend detail (header, tiles, the botanical
-- card and its flip), the order flow (guard, lifecycle, Order-Placed), and the
-- Catalog / Order / I18n services. This module builds a SHELL, not a second
-- app — it calls the same factories `views/shell.luau` calls, which is a suite
-- pin (`sipworks_spec`: "both entries reach the same blueprint functions").
--
-- WHAT THE COMPACT SHELL HIDES: the Composition shell itself (the root is a
-- plain `Screen` over the Menu list), Favorites / Stamps / Blend Book and every
-- route to them, the favorite affordances (`app.entry` gates them inside the
-- shared row and detail factories — no dead verbs), and the redeem branch (no
-- rewards context here, so the CTA is always pay-shaped). Stamps still accrue
-- silently in RewardsService, exactly as the spec says.

local metrics = require("./content/metrics")
local listView = require("./views/list")

local entryCompact = {}

function entryCompact.build(app: any): any
	local UI = app.UI
	local core = app.core

	local items = app.own(core:memo(function(use)
		return app.visibleBlends(use, "menu")
	end))

	return UI.Screen({
		id = "SipworksCompact",
		padding = 0,
		surface = "base",
		children = {
			UI.VStack({
				id = "Menu",
				gap = "s",
				padding = "s",
				width = metrics.fill,
				height = metrics.fill,
				children = {
					listView.searchBar(app),
					listView.blendList(app, {
						id = "List",
						items = items,
						onActivate = function(blendId: string)
							app.commands.openBlend(blendId, "menu")
						end,
					}),
				},
			}),
		},
	})
end

return entryCompact
