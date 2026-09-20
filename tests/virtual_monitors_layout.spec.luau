--!strict
--[[
	TWO SHOWCASE LAYOUT DEFECTS, EACH OF THEM INVISIBLE TO A SPEC THAT ONLY ASKS
	WHETHER A NODE MOUNTED.

	(d) THE DETAIL PAGE'S INFORMATION AREA WAS BELOW THE FOLD. The hero took
	    `viewport.h * 0.56`, the Information area took its natural height, and
	    the panel around both declares `clipChildren`. On the 920x640 monitor
	    canvas that put the description, the sparkline and the "More like this"
	    button outside the panel with nothing to scroll and no affordance saying
	    anything was there. Every existing case still passed, because every one
	    of those nodes MOUNTED — they were simply unreachable. The hero now
	    reserves room for the Information area and the route itself scrolls.

	(e) `hidden` RESERVES ITS BOX. The Catalog column declared
	    `hidden = savedShown` with `height = fill`, beside a Saved table that
	    also declares `height = fill`. `hidden` stops painting and stops taking
	    taps; it does NOT release the layout box (that is the whole difference
	    between it and `UI.When`/`Compose.show`, and the schema says so). So on
	    the Saved shelf the invisible Catalog went on claiming half the column
	    and the Saved table got half the height it asked for. The grid's scroll
	    position was never the reason to keep it mounted: `scrollNavigation`
	    holds that in a cell the showcase owns.

	Both are measured at the three canvases the showcase actually runs on.
]]

local t = require("./lib/testkit")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local nativeWorld = require("./lib/native_world")
local screens = require("../examples/virtual_monitors/screens")
local catalogModule = require("../examples/virtual_monitors/catalog")

local CANVASES = {
	{ name = "the 920x640 monitor canvas", w = 920, h = 640 },
	{ name = "a 393x852 phone", w = 393, h = 852 },
	{ name = "a 1920x1080 display", w = 1920, h = 1080 },
}

local function discoverWorld(size: { w: number, h: number }, extra: { [string]: any }?)
	local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = size.w, h = size.h })
	local catalog = catalogModule.new(Compose)
	local callbacks: { [string]: any } = { catalog = catalog }
	for key, value in extra or {} do
		callbacks[key] = value
	end
	local apps = screens.create(Facet, app, callbacks)
	app.mount(apps.Discover)
	settle(3)
	local function suffixed(suffix: string): string?
		for _, path in adapter.paths() do
			if path:sub(-#suffix) == suffix then
				return path
			end
		end
		return nil
	end
	return {
		app = app,
		adapter = adapter,
		settle = settle,
		catalog = catalog,
		suffixed = suffixed,
		node = function(suffix: string): any
			local path = suffixed(suffix)
			return if path == nil then nil else adapter.node(path)
		end,
	}
end

local function bottom(rect: any): number
	return rect.y + rect.h
end

t.describe("(d) the detail page's Information area is reachable at every canvas", function()
	for _, canvas in CANVASES do
		t.it(`{canvas.name}: the info route scrolls inside the panel`, function()
			local selected = Compose.cell(nil)
			local w = discoverWorld(canvas, { selectedGame = selected })
			selected:set(w.catalog.items:peek()[1])
			w.settle(3)

			local details = assert(w.node("/Expand/then/Details"), "the detail panel")
			local information = assert(w.node("/Body/Information"), "the Information area")
			--[[ THE PANEL CONTAINS ITS INFORMATION AREA. Before the fix this was
				false at 920x640 by more than a hundred pixels, inside a panel that
				CLIPS — the definition of "below the fold with no way to reach it". ]]
			t.expect(information.rect.h > 0).toBe(true)
			t.expect(bottom(information.rect) <= bottom(details.rect) + 1).toBe(true)

			-- ...and the route is a SCROLLER, so what does not fit is still reachable
			local scroll = assert(w.node("/InfoScroll"), "the info route must scroll")
			t.expect(scroll.rect.h > 0).toBe(true)
			t.expect(bottom(scroll.rect) <= bottom(details.rect) + 1).toBe(true)

			-- and everything the route offers is inside it
			for _, id in { "/Sparkline", "/MoreLikeThis" } do
				local found = assert(w.node(id), id)
				t.expect(found.rect.y >= scroll.rect.y - 1).toBe(true)
			end
		end)
	end
end)

t.describe("(e) the Saved shelf gets the whole column, not half of it", function()
	for _, canvas in CANVASES do
		t.it(`{canvas.name}: the Catalog releases its box instead of hiding in it`, function()
			local shelf = Compose.cell("browse")
			local saved = Compose.cell({})
			local savedOrder = Compose.cell({})
			local w = discoverWorld(canvas, {
				discoveryShelf = shelf,
				savedGames = saved,
				savedOrder = savedOrder,
			})
			local browse = assert(w.node("/Content/Desktop/Browse"), "the Browse column")
			local catalogHeight = assert(w.node("/Browse/Catalog"), "the Catalog column").rect.h

			-- `savedGames` is the id SET; `savedOrder` is the order they list in
			local items = w.catalog.items:peek()
			saved:set({ [items[1].id] = true, [items[2].id] = true })
			savedOrder:set({ items[1].id, items[2].id })
			shelf:set("saved")
			w.settle(3)

			--[[ THE INVISIBLE COLUMN IS GONE, not merely unpainted. A `hidden`
				node is still in `adapter.paths()` with its solved box. ]]
			t.expect(w.node("/Browse/Catalog")).toBeNil()

			local table_ = assert(w.node("/Browse/Saved"), "the Saved table")
			--[[ ...and the table gets what the Catalog used to. Before the fix two
				`height = fill` siblings split the column and this was about half. ]]
			t.expect(table_.rect.h > catalogHeight * 0.9).toBe(true)
			t.expect(bottom(table_.rect) <= bottom(browse.rect) + 1).toBe(true)

			-- and switching back restores the grid, at its own scroll position
			shelf:set("browse")
			w.settle(3)
			t.expect(w.node("/Browse/Catalog") ~= nil).toBe(true)
			t.expect(w.node("/Catalog/Games") ~= nil).toBe(true)
		end)
	end
end)
