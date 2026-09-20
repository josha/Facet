--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local scenario = require("../examples/gallery/scenarios/card_rail")
t.describe("adaptive card shelves", function()
	t.it("keeps three navigable shelves, with one-up mobile and larger distant cards", function()
		local results = {}
		for _, device in
			{
				{ w = 390, h = 844, input = "Touch", distance = "near" },
				{ w = 1920, h = 1080, input = "Mouse", distance = "near" },
				{ w = 1920, h = 1080, input = "Gamepad", distance = "ten-foot" },
			}
		do
			local w = world.new({
				newAdapter = function()
					local a = require("./lib/fake_target").new()
					a.scrollBarThickness = 8
					return a
				end,
				viewport = { x = 0, y = 0, w = device.w, h = device.h },
				preferredInput = device.input,
				env = { viewingDistance = device.distance },
			})
			local s = scenario.build({
				Facet = Facet,
				app = w.app,
				UI = w.UI,
				Compose = w.Compose,
				core = w.core,
				env = w.env,
				presenter = w.pres,
				actionSystem = w.system,
			})
			w.present(s.screen, s.present)
			s.handle = w.handle
			w.settle(3)
			local shelves = {
				"/CardRail/Page/RailPane/Rail",
				"/CardRail/Page/WeekendRailPane/WeekendRail",
				"/CardRail/Page/RecommendedRailPane/RecommendedRail",
			}
			for _, shelf in shelves do
				t.expect(w.adapter.node(shelf) ~= nil).toBe(true)
			end
			local railWidth = w.adapter.node(shelves[1]).rect.w
			local itemExtent = s.itemExtent()
			local d = {
				itemExtent = itemExtent,
				cardsPerView = math.floor((railWidth + s.cardGap) / (itemExtent + s.cardGap)),
			}
			t.expect(railWidth - d.cardsPerView * itemExtent - (d.cardsPerView - 1) * s.cardGap >= 40).toBe(true)
			table.insert(results, d)
			if device.input == "Gamepad" then
				local first
				for _, path in w.adapter.paths() do
					local slot = string.match(path, "^(" .. shelves[1] .. "/.+)/Slot/Card/Name$")
					if slot and w.adapter.node(path).props.text == "Livery 001" then
						first = slot .. "/Hit"
					end
				end
				w.pres.focus.focusOn(first)
				w.settle(2)
				w.press("DPadDown")
				t.expect(string.find(w.pres.focus.focused:peek(), "WeekendRail", 1, true) ~= nil).toBe(true)
			end
			w.pres.dismiss(w.handle)
			s.dispose()
		end
		t.expect(results[1].cardsPerView).toBe(1)
		t.expect(results[2].cardsPerView > results[3].cardsPerView).toBe(true)
		t.expect(results[3].itemExtent > results[2].itemExtent).toBe(true)
	end)
	t.it("settles a theme and text-size change when an aspect shelf crosses the scrollbar threshold", function()
		local top = require("../examples/gallery/client/demo_picker").barReservation(58, nil, 8)
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1320, h = 742 },
			preferredInput = "KeyboardAndMouse",
			capabilities = { mouse = true, keyboard = true, touch = false, gamepad = false },
			env = { coreSafeInsets = { top = top, bottom = 0, left = 0, right = 0 }, displaySize = "Medium" },
			newAdapter = function()
				local a = require("./lib/fake_target").new()
				a.scrollBarThickness = require("./lib/fake_target").SCROLL_BAR_RESERVE
				return a
			end,
		})
		local s = scenario.build({
			Facet = Facet,
			app = w.app,
			UI = w.UI,
			Compose = w.Compose,
			core = w.core,
			env = w.env,
			presenter = w.pres,
			actionSystem = w.system,
		})
		w.present(s.screen, s.present)
		w.settle(3)
		w.env:set("preferredTextOffset", 14)
		w.settle(3)
		local pkg = require("../examples/themes/classic_desktop").build(Facet.themes)
		w.env:set("themeMetrics", Facet.themes.resolve(pkg, nil, {}))
		w.env:set("preferredTextOffset", 0)
		w.settle(3)
		local path = "/CardRail/Page/RailPane/Rail"
		local width = w.adapter.node(path).rect.w
		w.settle(3)
		t.expect(w.adapter.node(path).rect.w).toBe(width)
		w.env:set("viewportRect", { x = 0, y = 0, w = 1320, h = 2000 })
		w.settle(3)
		t.expect(w.controller.scrollBarInsetOf("/CardRail/Page")).toBeNil()
		t.expect(w.core.lastError()).toBeNil()
		w.pres.dismiss(w.handle)
		s.dispose()
	end)
end)
