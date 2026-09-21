--!strict
--[[ THE SHOWCASE SHIPS NO FINDING OF FACET'S OWN.

	Every defect this file pins was ALREADY BEING REPORTED by
	`controller.diagnostics()` on the very frame it happened, and every one of them
	shipped anyway, because nothing read that list. Between them they were: a
	`UI.offset` on a ZStack child that moved nothing (the Featured pill jammed into
	the card's corner, the Avatar HUD flush against the screen instead of inside
	its preview); `alignH`/`alignV` on stack children that centred nothing (two
	empty states pinned to their top-left corner, a hero's pitch not centred
	against its art, a status caption on the top line of a 46px row); a hero whose
	art stood 16px past the card's own rounded corners; the detail page's rating
	row 205px wider than a small phone; a shelf switch 92px off the right edge; a
	welcome greeting painting over the composer on a landscape phone; and a
	navigation route solved to height 0 with its whole body painted below the panel
	meant to clip it.

	So the assertion is the whole list, not a chosen shape from it: mount each
	screen at each of the sizes the showcase claims to run at, in each of the
	states a player can put it in, and require Facet to have nothing to say. A
	finding here is a real defect at that cell — an inert prop is a design
	intention that silently did not happen, and an overflow is paint outside a box.

	It is deliberately a SWEEP rather than a handful of cases: every one of the
	defects above lived in a cell no spec had a reason to visit, and the sweep's
	cost is one mount per cell. ]]
local t = require("./lib/testkit")
local nativeWorld = require("./lib/native_world")
local Facet = require("../src")
local screens = require("../examples/virtual_monitors/screens")
local themeMod = require("../examples/virtual_monitors/theme")
local catalogMod = require("../examples/virtual_monitors/catalog")
local chatMod = require("../examples/virtual_monitors/chat_model")
local Compose = Facet.Compose

-- The device matrix the showcase claims: a small and a regular phone in both
-- orientations, both tablet orientations, the 920x640 monitor canvas the spatial
-- presentation paints on, a laptop, a headset profile and a 1080p television.
--[[ ...and the last row is a TELEVISION, which is a different screen from a
	1080p monitor even though the pixels match. A ten-foot display resolves the
	package at `displaySize = "Large"`: every token — type, padding, target floors,
	icon sizes — comes back about half again as big, while any raw pixel number an
	author wrote stays exactly where it was. That gap is its own defect class, and
	the two it caught here were both of it: a segmented switch pinned at 164px
	showed "Br…"/"Sav…", and a carousel reserving a flat 121px of chrome around its
	art under-reserved by 47 and clipped the card's bottom edge off. Neither could
	appear at any of the near-distance rows above. ]]
local VIEWPORTS = {
	{ name = "phone-small-portrait", w = 320, h = 568 },
	{ name = "phone-portrait", w = 393, h = 794 },
	{ name = "phone-landscape", w = 794, h = 393 },
	{ name = "tablet-portrait", w = 834, h = 1112 },
	{ name = "tablet-landscape", w = 1112, h = 834 },
	{ name = "monitor-canvas", w = 920, h = 640 },
	{ name = "headset", w = 1440, h = 900 },
	{ name = "desktop-1080p", w = 1919, h = 1022 },
	{ name = "desktop-1920x1080", w = 1920, h = 1080 },
	{ name = "ten-foot-television", w = 1920, h = 1080, displaySize = "Large" },
}

local function report(findings: { any }, where: string): string
	local lines = { where .. ": " .. tostring(#findings) .. " finding(s) Facet reported and this screen shipped" }
	for _, finding in findings do
		table.insert(lines, ("  %s\n    %s"):format(tostring(finding.node), tostring(finding.issue)))
	end
	return table.concat(lines, "\n")
end

-- One mount, one settle, one read. `reducedMotion` is pinned so a cell is the
-- same box every run: a transition mid-flight is a different (and legitimate)
-- geometry, and this sweep is about the resting one.
local function sweep(appName: string, caseName: string, callbacks: any)
	for _, vp in VIEWPORTS do
		local package = themeMod.create(Facet, appName)
		-- the metrics THIS display resolves the package to, which is what a raw
		-- pixel number in the showcase has to keep step with
		local metrics = if vp.displaySize ~= nil
			then Facet.themes.resolve(package, nil, { displaySize = vp.displaySize })
			else package.metrics
		local app, _, settle = nativeWorld({ x = 0, y = 0, w = vp.w, h = vp.h }, metrics)
		app.environment:set("reducedMotion", true)
		if vp.displaySize ~= nil then
			app.environment:set("displaySize", "Large")
		end
		local views = screens.create(Facet, app, callbacks())
		local _, _, handle = app.mount(function()
			return app.controls.Screen("S")({ views[appName]() })
		end)
		settle(20)
		local findings = handle.controller.diagnostics()
		if #findings > 0 then
			error(report(findings, ("%s / %s / %s (%dx%d)"):format(appName, caseName, vp.name, vp.w, vp.h)), 0)
		end
		app.dispose()
	end
end

local function loadedCatalog()
	local catalog = catalogMod.new(Compose)
	-- Three pages in, so the feed is long enough for the grid to window and for
	-- "More like this" to have same-genre matches to offer.
	for _ = 1, 40 do
		catalog.seen(#catalog.items:peek())
		catalog.step(1 / 60)
	end
	return catalog
end

t.describe("Virtual Monitors reports no layout finding of Facet's own", function()
	t.it("mounts Discover clean in every shelf, filter and detail state", function()
		local catalog = loadedCatalog()
		local items = catalog.items:peek()
		local cases: { { string | any } } = {
			{
				"browse",
				function()
					return { spatial = false, catalog = catalog }
				end,
			},
			{
				"detail",
				function()
					return { spatial = false, catalog = catalog, selectedGame = Compose.cell(items[1]) }
				end,
			},
			{
				"detail-more-like-this",
				function()
					return {
						spatial = false,
						catalog = catalog,
						selectedGame = Compose.cell(items[1]),
						discoveryPath = Compose.cell({ { id = "similar" } }),
					}
				end,
			},
			{
				"saved-empty",
				function()
					return { spatial = false, catalog = catalog, discoveryShelf = Compose.cell("saved") }
				end,
			},
			{
				"saved-with-rows",
				function()
					return {
						spatial = false,
						catalog = catalog,
						discoveryShelf = Compose.cell("saved"),
						savedGames = Compose.cell({
							[items[1].id] = true,
							[items[2].id] = true,
							[items[3].id] = true,
						}),
						savedNotes = Compose.cell({ [items[1].id] = "good with friends" }),
					}
				end,
			},
			{
				"filters-match-nothing",
				function()
					return { spatial = false, catalog = catalog, discoveryQuery = Compose.cell("zzzzzz") }
				end,
			},
		}
		for _, case in cases do
			sweep("Discover", case[1] :: string, case[2] :: any)
		end
		catalog.dispose()
	end)

	t.it("mounts Avatar clean with its sheet, its tips and its settings collapsed", function()
		sweep("Avatar", "default", function()
			return { spatial = false }
		end)
		sweep("Avatar", "look-summary-sheet", function()
			return { spatial = false, avatarSummaryShown = Compose.cell(true) }
		end)
		sweep("Avatar", "tips-expanded", function()
			return { spatial = false, avatarTipsExpanded = Compose.cell(true) }
		end)
		sweep("Avatar", "appearance-collapsed", function()
			return { spatial = false, avatarSettingsExpanded = Compose.cell(false) }
		end)
	end)

	t.it("mounts the Assistant clean empty, mid-reply and with a thread", function()
		sweep("Chat", "empty", function()
			return { spatial = false }
		end)
		-- One conversation per cell: a chat model is stateful, and a settled thread
		-- and a streaming one are two different screens.
		sweep("Chat", "streaming", function()
			local chat = chatMod.new(Compose)
			chat.draft:set("What game should I play with friends?")
			chat.send()
			for _ = 1, 20 do
				chat.step(1 / 60)
			end
			return { spatial = false, chat = chat }
		end)
		sweep("Chat", "thread", function()
			local chat = chatMod.new(Compose)
			for _, prompt in { "What game should I play with friends?", "Tell me more about the second one" } do
				chat.draft:set(prompt)
				chat.send()
				for _ = 1, 400 do
					chat.step(1 / 60)
				end
			end
			return { spatial = false, chat = chat }
		end)
	end)
end)
