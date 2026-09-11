--!strict
-- One user flow, real presenter and theme snapshots; simulated facts are headless
-- evidence only. Tap/keyboard delivery and page scopes are observable here.
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src") :: any
local world = require("./lib/world")
local scenario = require("../examples/gallery/scenarios/navigation_stack")
local snapshot = require("../src/themes/snapshot")
local themes = {
	Facet.themes.neutralPackage(),
	require("../examples/themes/classic_desktop"),
	require("../examples/themes/fantasy_parchment"),
}
local function find(w, suffix)
	for _, path in w.adapter.paths() do
		if path:sub(-#suffix) == suffix then
			return path
		end
	end
	error("missing " .. suffix)
end
describe("Showcase navigation journey", function()
	it("adapts one flow across themed viewport/input facts and cleans every page", function()
		for _, theme in themes do
			for _, view in
				{
					{ w = 390, h = 844, input = "touch", display = "Small" },
					{ w = 844, h = 390, input = "touch", display = "Small" },
					{ w = 1024, h = 768, input = "touch", display = "Small" },
					{ w = 1280, h = 800, input = "mouse", display = "Medium" },
					{ w = 1920, h = 1080, input = "gamepad", display = "Large" },
				}
			do
				local w = world.new({
					viewport = { x = 0, y = 0, w = view.w, h = view.h },
					capabilities = {
						touch = view.input == "touch",
						mouse = view.input == "mouse",
						keyboard = true,
						gamepad = view.input == "gamepad",
					},
					preferredInput = if view.input == "touch"
						then "Touch"
						elseif view.input == "gamepad" then "Gamepad"
						else "KeyboardAndMouse",
					displaySize = view.display,
					themeMetrics = snapshot.resolve(
						if theme.build then theme.build(Facet.themes) else theme,
						nil,
						{ displaySize = view.display }
					),
					reducedMotion = true,
				})
				local built = scenario.build({ Facet = Facet, core = w.core, env = w.env, presenter = w.pres })
				w.present(built.screen)
				w.adapter.tap(find(w, "/Continue"))
				w.settle(4)
				expect(built.report().navigation.depth).toBe(1)
				expect(built.report().axis).toBe(if w.env:get("sizeClass"):get() == "compact" then "y" else "x")
				local gap = w.adapter.node(find(w, "/FlexibleGap"))
				expect(gap.rect.w >= 0).toBe(true)
				built.steps.baseline()
				built.steps.spacing()
				w.settle(4)
				w.adapter.tap(find(w, "/Review"))
				w.settle(4)
				expect(built.report().navigation.depth).toBe(2)
				w.adapter.tap(find(w, "/StartAgain"))
				w.settle(4)
				expect(built.report().navigation.depth).toBe(0)
				expect(built.report().notes).toBe("Meet at sunrise.")
				w.pres.dismiss(w.handle)
				built.dispose()
				local result = built.report()
				expect(result.visits).toBe(result.exits)
				expect(result.navigation.livePages).toBe(0)
			end
		end
	end)
end)

describe("Showcase mobile controller and ten-foot distinction", function()
	it(
		"phone gamepad preserves compact flow through touch switches while ten-foot uses larger theme geometry",
		function()
			local function build(viewport, display, touch)
				local w = world.new({
					viewport = viewport,
					displaySize = display,
					capabilities = { touch = touch, gamepad = true, mouse = false, keyboard = false },
					preferredInput = "Gamepad",
					reducedMotion = true,
				})
				local built = scenario.build({ Facet = Facet, core = w.core, env = w.env, presenter = w.pres })
				w.present(built.screen)
				return w, built
			end
			local phone, journey = build({ x = 0, y = 0, w = 390, h = 844 }, "Small", true)
			expect(phone.env:get("interactionClasses"):get().primary).toBe("gamepad")
			expect(phone.env:get("distanceProfile"):get()).toBe("near")
			expect(phone.env:get("sizeClass"):get()).toBe("compact")
			expect(journey.report().axis).toBe("y")
			local launcher = find(phone, "/Continue")
			local phoneTitleHeight = phone.adapter.node(find(phone, "/NavBar/Title")).rect.h
			local phoneButtonHeight = phone.adapter.node(launcher).rect.h
			phone.pres.focus.focusOn(launcher)
			phone.press("ButtonA")
			phone.settle(4)
			expect(journey.report().navigation.depth).toBe(1)
			local review = find(phone, "/Review")
			local reviewNode = phone.adapter.node(review)
			local visits = journey.report().visits
			for _, preference in { "Touch", "Gamepad", "Touch" } do
				phone.env:set("preferredInput", preference)
				phone.settle(4)
				expect(phone.env:get("interactionClasses"):get().primary).toBe(
					if preference == "Touch" then "touch" else "gamepad"
				)
				expect(journey.report().navigation.depth).toBe(1)
				expect(journey.report().axis).toBe("y")
				expect(journey.report().visits).toBe(visits)
				expect(phone.adapter.node(review)).toBe(reviewNode)
			end
			phone.adapter.touchTap(review)
			phone.settle(4)
			expect(journey.report().navigation.depth).toBe(2)
			phone.env:set("preferredInput", "Gamepad")
			phone.settle(4)
			expect(journey.report().navigation.depth).toBe(2)
			phone.press("ButtonB")
			phone.settle(4)
			expect(phone.pres.focus.focused:get()).toBe(review)
			phone.press("ButtonB")
			phone.settle(4)
			expect(journey.report().navigation.depth).toBe(0)
			expect(phone.pres.focus.focused:get()).toBe(launcher)
			expect(journey.report().notes).toBe("Meet at sunrise.")
			local tv, distantJourney = build({ x = 0, y = 0, w = 1920, h = 1080 }, "Large", false)
			expect(tv.env:get("interactionClasses"):get().primary).toBe("gamepad")
			expect(tv.env:get("distanceProfile"):get()).toBe("ten-foot")
			expect(tv.env:get("sizeClass"):get()).toBe("regular")
			expect(distantJourney.report().axis).toBe("x")
			expect(tv.adapter.node(find(tv, "/NavBar/Title")).rect.h > phoneTitleHeight).toBe(true)
			expect(tv.adapter.node(find(tv, "/Continue")).rect.h > phoneButtonHeight).toBe(true)
			phone.pres.dismiss(phone.handle)
			journey.dispose()
			tv.pres.dismiss(tv.handle)
			distantJourney.dispose()
			expect(journey.report().visits).toBe(journey.report().exits)
			expect(distantJourney.report().visits).toBe(distantJourney.report().exits)
		end
	)
end)

describe("Showcase composed search restoration", function()
	it("native search filtering survives adaptation and restores its result after returning", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 390, h = 844 },
			preferredInput = "KeyboardAndMouse",
			reducedMotion = true,
		})
		local built = scenario.build({ Facet = Facet, core = w.core, env = w.env, presenter = w.pres })
		w.present(built.screen)
		local field = find(w, "/Field")
		local fieldNode = w.adapter.node(field)
		w.adapter.focusText(field)
		w.adapter.typeText(field, "FoReSt")
		w.adapter.commitText(field)
		w.settle(3)
		expect(built.report().query).toBe("FoReSt")
		local result = find(w, "/Result-forest")
		local count = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "/Result-", 1, true) then
				count += 1
			end
		end
		expect(count).toBe(1)
		w.env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 800 })
		w.settle(3)
		expect(w.adapter.node(field)).toBe(fieldNode)
		expect(built.report().axis).toBe("x")
		w.pres.focus.focusOn(result)
		w.press("Return")
		w.settle(4)
		expect(built.report().navigation.depth).toBe(1)
		w.press("ButtonB")
		w.settle(4)
		expect(built.report().navigation.depth).toBe(0)
		expect(built.report().query).toBe("FoReSt")
		expect(w.pres.focus.focused:get()).toBe(result)
		field = find(w, "/Field")
		w.adapter.focusText(field)
		w.adapter.typeText(field, "zzz")
		w.adapter.commitText(field)
		w.settle(3)
		count = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "/Result-", 1, true) then
				count += 1
			end
		end
		expect(count).toBe(0)
		local clear = find(w, "/Clear")
		w.adapter.tap(clear)
		w.settle(3)
		expect(built.report().query).toBe("")
		count = 0
		for _, path in w.adapter.paths() do
			if string.find(path, "/Result-", 1, true) then
				count += 1
			end
		end
		expect(count).toBe(3)
		w.pres.dismiss(w.handle)
		built.dispose()
		expect(built.report().visits).toBe(built.report().exits)
	end)
end)
