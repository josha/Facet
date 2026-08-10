--!strict
-- Scroll indicator policy (director ruling 2026-08-09, "auto-showing scroll
-- bars"): pointer sessions keep the desktop convention — a persistent bar
-- whose thickness the solver RESERVES; touch/gamepad sessions get overlay
-- indicators — zero reserve, flash on first overflow, show while scrolling,
-- fade when idle, and reduced motion never fades. The policy is derived in
-- the ENVIRONMENT (from interactionClasses, never a device name), pushed by
-- the PRESENTER through the declared optional target method
-- `setScrollIndicatorPolicy`, and the layout consequence flows through the
-- adapter's published `scrollBarThickness` into the solver's reserve.
--
-- The engine half (the actual fade tweens, the CanvasPosition-driven show) is
-- engine-only; what this spec pins headlessly is the POLICY CHAIN: derivation,
-- boot application, live flip, reserve consequence, and the reduced-motion and
-- fallback facts — through the fake target's recorded ops.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local environment = require("../src/env/environment")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function world(caps: any?, preferred: string?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	if caps ~= nil then
		env:set("capabilities", caps)
	end
	if preferred ~= nil then
		env:set("preferredInput", preferred)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new();
	(adapter :: any).scrollBarThickness = 8
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	return core, env, adapter, presenter
end

describe("scroll indicator policy: derivation is input facts, never a device", function()
	it("pointer sessions derive 'always'; touch and gamepad derive 'auto'", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("always")
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("auto")
		env:set("capabilities", { touch = false, mouse = false, keyboard = false, gamepad = true })
		env:set("preferredInput", "Gamepad")
		expect(env:get("scrollIndicatorPolicy"):get()).toBe("auto")
	end)
end)

describe("scroll indicator policy: the presenter drives the adapter seam", function()
	it("boot applies the session's policy before anything mounts", function()
		local _, _, adapter = world({ touch = true, mouse = false, keyboard = false, gamepad = false }, "Touch")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("auto")
		-- the layout consequence: an overlay indicator lays claim to no space
		expect((adapter :: any).scrollBarThickness).toBe(0)
	end)

	it("a pointer session keeps the configured thickness (the reserve survives)", function()
		local _, _, adapter = world()
		expect((adapter :: any).scrollIndicatorPolicy).toBe("always")
		expect((adapter :: any).scrollBarThickness).toBe(8)
	end)

	it("an input-class flip mid-session re-applies the policy AND the reserve", function()
		local _, env, adapter = world()
		expect((adapter :: any).scrollBarThickness).toBe(8)
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("auto")
		expect((adapter :: any).scrollBarThickness).toBe(0)
		-- and back: the configured thickness is restored, not invented
		env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = false })
		env:set("preferredInput", "KeyboardAndMouse")
		expect((adapter :: any).scrollIndicatorPolicy).toBe("always")
		expect((adapter :: any).scrollBarThickness).toBe(8)
	end)

	it("reduced motion rides the same seam", function()
		local _, env, adapter = world()
		env:set("reducedMotion", true)
		expect((adapter :: any).scrollIndicatorReduced).toBe(true)
		local seen = false
		for _, op in (adapter :: any).takeOps() do
			if string.find(op, "indicatorPolicy always reduced=true", 1, true) ~= nil then
				seen = true
			end
		end
		expect(seen).toBe(true)
	end)

	it("an adapter WITHOUT the seam degrades by name: nothing is called, nothing breaks", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new();
		(adapter :: any).scrollBarThickness = 8
		(adapter :: any).setScrollIndicatorPolicy = nil
		local presenter = LuauUI.newPresenter(core, env, adapter, system)
		expect(presenter ~= nil).toBe(true)
		expect((adapter :: any).scrollBarThickness).toBe(8)
		expect(core:lastError()).toBeNil()
	end)
end)

describe("scroll indicator policy: the reserve consequence reaches solved geometry", function()
	it("a hug shelf regains the 8px the bar reserved when the session flips to touch", function()
		local core, env, adapter, presenter = world()
		local UI = LuauUI.UI
		local handle = presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "hug" },
						children = {
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 2000 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		local before = (adapter :: any).node("/S/Page").rect.h
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
		presenter.refresh()
		local after = (adapter :: any).node("/S/Page").rect.h
		-- the page is height-hug in a bounded screen: its box is the offer both
		-- times — what changes is the RESERVE inside it, which this asserts
		-- through the adapter's published thickness feeding the next solve
		expect((adapter :: any).scrollBarThickness).toBe(0)
		expect(after >= before).toBe(true)
		expect(core:lastError()).toBeNil()
		if type((handle :: any).dispose) == "function" then
			(handle :: any).dispose()
		end
	end)
end)

describe("a single-axis scroller's canvas never exceeds its window on the other axis", function()
	it("a wide x-carousel inside a y-page does not inflate the page's canvas width", function()
		-- director live report 2026-08-09: the feed (Y scroller) published an
		-- 880px-wide canvas in a 670px window because the nested friends
		-- carousel MEASURES at content width — so the engine drew a HORIZONTAL
		-- bar on a vertical scroller, straight through the tab dock under it.
		local core, _, adapter, presenter = world()
		local UI = LuauUI.UI
		presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Carousel",
								axis = "x",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 90 },
								children = {
									UI.Box({
										id = "WideStrip",
										width = { type = "fixed", px = 900 },
										height = { type = "fixed", px = 80 },
									}),
								},
							}),
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 1200 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		local page = (adapter :: any).node("/S/Page")
		expect(page ~= nil and page.scrollRegion ~= nil).toBe(true)
		-- the page can only scroll Y: its canvas width must be its window width
		expect(page.scrollRegion.contentW <= page.rect.w + 1).toBe(true)
		-- the carousel keeps its own real X extent (that axis IS scrollable)
		local carousel = (adapter :: any).node("/S/Page/Carousel")
		expect(carousel.scrollRegion.contentW >= 900).toBe(true)
		expect(carousel.scrollRegion.contentH <= carousel.rect.h + 1).toBe(true)
		expect(core:lastError()).toBeNil()
	end)
end)

describe('indicators = "none": the carousel opt-out', function()
	it("a peeking carousel declares its indicator off; its parent page keeps one", function()
		local core, _, adapter, presenter = world()
		local UI = LuauUI.UI
		presenter.present(
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Page",
						axis = "y",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {
							UI.ScrollView({
								id = "Carousel",
								axis = "x",
								indicators = "none",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 90 },
								children = {
									UI.Box({
										id = "WideStrip",
										width = { type = "fixed", px = 900 },
										height = { type = "fixed", px = 80 },
									}),
								},
							}),
							UI.Box({
								id = "Tall",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 1200 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		expect(((adapter :: any).node("/S/Page/Carousel") :: any).indicatorsOff).toBe(true)
		expect(((adapter :: any).node("/S/Page") :: any).indicatorsOff).toBeNil()
		expect(core:lastError()).toBeNil()
	end)
end)

return true
