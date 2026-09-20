--!strict
local harness = require("./lib/harness")
-- Edit-mode preview harness (director Part-2 ws2): the engine-free half —
-- device profiles resolve to environment geometry (viewport + core-safe
-- insets), and applying a profile to an environment re-solves an attached
-- renderer with rect-only writes (the live re-render contract).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local device_profiles = require("../src/preview/device_profiles")
local fake_target = require("../tests/lib/fake_target")
local environment = require("../src/env/environment")
local customFactory = harness.coreFactory

describe("Preview: device profiles", function()
	it("ships presets matching the measured device truths", function()
		-- ground truth 2026-07-20, Studio compact-phone emulator: the engine
		-- CAMERA already excludes the notch and home-bar zones (portrait
		-- camera 389x762 of a 389x843 device; landscape 749x368 of 843x389);
		-- the ONLY in-canvas reserved region is the 58px CoreGui topbar
		-- (GetGuiInset reports exactly that, nothing lateral, nothing bottom)
		local names = device_profiles.list()
		expect(#names).toBe(7) -- + console (input-paradigms) + phoneNotchLandscape (native-substrate NS-A1)
		local phone = device_profiles.get("phone")
		expect(phone.viewport.w).toBe(389) -- portrait: the hard case
		expect(phone.viewport.h).toBe(762)
		expect(phone.insets.top).toBe(58)
		expect(phone.insets.left + phone.insets.right + phone.insets.bottom).toBe(0)
		local phoneLandscape = device_profiles.get("phoneLandscape")
		expect(phoneLandscape.viewport.w).toBe(749)
		expect(phoneLandscape.viewport.h).toBe(368)
		expect(device_profiles.get("tablet") ~= nil).toBe(true)
		-- portrait tablet (director round 4): landscape swapped
		local tp = device_profiles.get("tabletPortrait")
		expect(tp.viewport.w).toBe(768)
		expect(tp.viewport.h).toBe(1024)
		expect(tp.insets.top).toBe(58)
		expect(device_profiles.get("desktop").viewport.w > phoneLandscape.viewport.w).toBe(true)
		expect(device_profiles.get("unknown")).toBe(nil)
	end)

	-- console 10-foot (input-paradigms expansion): a console is a 1080p
	-- Large-display gamepad machine; the profile must carry the full fact set
	-- (displaySize, overscan margins, capabilities, preference), not geometry
	-- alone, so applying it flips the ten-foot presentation AND the gamepad
	-- affordances in one move
	it("ships a console profile whose facts flip distanceProfile and interactionClasses together", function()
		local console = device_profiles.get("console")
		expect(console ~= nil).toBe(true)
		expect(console.viewport.w).toBe(1920)
		expect(console.viewport.h).toBe(1080)
		expect(console.facts.displaySize).toBe("Large")
		expect(console.facts.capabilities.gamepad).toBe(true)
		expect(console.facts.capabilities.mouse).toBe(false)
		expect(console.facts.preferredInput).toBe("Gamepad")
		-- overscan margins: nonzero on all four sides (TVs clip edges)
		expect(console.facts.overscanInsets.left > 0).toBe(true)
		expect(console.facts.overscanInsets.top > 0).toBe(true)

		local core = customFactory.new()
		local env = environment.new(core)
		device_profiles.apply(env, "console")
		expect(env:get("distanceProfile"):peek()).toBe("ten-foot")
		local classes = env:get("interactionClasses"):peek()
		expect(classes.gamepad).toBe(true)
		expect(classes.primary).toBe("gamepad")
		expect(classes.pointer).toBe(false)
		-- and applying a near profile fully restores the desktop facts
		device_profiles.apply(env, "desktop")
		expect(env:get("distanceProfile"):peek()).toBe("near")
		expect(env:get("interactionClasses"):peek().primary).toBe("pointer")
		expect(env:get("overscanInsets"):peek().left).toBe(0)
	end)

	it("applying a profile re-renders an attached tree with rect writes only", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		device_profiles.apply(env, "desktop")
		local adapter = fake_target.new({ ops = true })
		local root = harness.mount(
			core,
			harness.UI.Screen({
				id = "P",
				children = {
					harness.UI.VStack({
						id = "Panel",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {},
					}),
				},
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/P/Panel").rect.w).toBe(device_profiles.get("desktop").viewport.w)
		local factoryRuns = root.counters().factoryRuns
		adapter.takeOps()
		device_profiles.apply(env, "phone")
		-- the camera pre-excludes lateral safe areas: full canvas width
		expect(adapter.node("/P/Panel").rect.w).toBe(device_profiles.get("phone").viewport.w)
		expect(root.counters().factoryRuns).toBe(factoryRuns) -- live re-render, no remount
		for _, op in adapter.takeOps() do
			expect(string.sub(op, 1, 4)).toBe("rect")
		end
	end)

	-- ten-foot overscan (input-paradigms expansion): while distanceProfile is
	-- ten-foot, the renderer composes overscanInsets ON TOP of coreSafeInsets
	-- (TVs clip edges), and leaving the profile restores the full canvas
	it("applying the console profile insets the solved tree by the overscan margins", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		device_profiles.apply(env, "desktop")
		local adapter = fake_target.new({ ops = true })
		local root = harness.mount(
			core,
			harness.UI.Screen({
				id = "P",
				children = {
					harness.UI.VStack({
						id = "Panel",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						children = {},
					}),
				},
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		device_profiles.apply(env, "console")
		local rect = adapter.node("/P/Panel").rect
		expect(rect.x).toBe(90) -- left overscan margin
		expect(rect.y).toBe(58 + 60) -- topbar + top overscan
		expect(rect.w).toBe(1920 - 90 - 90)
		expect(rect.h).toBe(1080 - 58 - 60 - 60)
		device_profiles.apply(env, "desktop")
		expect(adapter.node("/P/Panel").rect.w).toBe(1280)
		expect(adapter.node("/P/Panel").rect.x).toBe(0)
	end)
end)

describe("Preview: notched device-safe profile (native-substrate NS-A1)", function()
	it("phoneNotchLandscape pushes deviceSafeInsets and profile switch resets them", function()
		local core = customFactory.new()
		local env = environment.new(core)
		device_profiles.apply(env, "phoneNotchLandscape")
		local device = env:get("deviceSafeInsets"):peek()
		expect(device.left).toBe(47)
		expect(device.right).toBe(47)
		expect(device.bottom).toBe(21)
		device_profiles.apply(env, "desktop")
		local reset = env:get("deviceSafeInsets"):peek()
		expect(reset.left).toBe(0)
		expect(reset.right).toBe(0)
	end)
end)

describe("Live environment preview", function()
	it("preserves overrides across platform changes and restores the latest live facts", function()
		local preview = require("../src/client/environment_preview")
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		local handle = preview.new(env)
		handle.source:batch(function()
			handle.source:set("viewportRect", { x = 0, y = 0, w = 1440, h = 900 })
			handle.source:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(handle.setProfile("phone")).toBe(true)
		expect(env:get("viewportRect"):peek().w).toBe(389)
		expect(env:get("interactionClasses"):peek().primary).toBe("touch")
		handle.setInput("gamepad")
		handle.source:set("preferredInput", "KeyboardAndMouse")
		expect(env:get("interactionClasses"):peek().primary).toBe("gamepad")
		expect(env:get("distanceProfile"):peek()).toBe("near")
		handle.setOrientation("landscape")
		expect(env:get("viewportRect"):peek().w).toBe(749)
		handle.setProfile("tv")
		handle.setInput("pointer")
		expect(env:get("distanceProfile"):peek()).toBe("ten-foot")
		expect(env:get("interactionClasses"):peek().primary).toBe("pointer")
		handle.source:set("viewportRect", { x = 0, y = 0, w = 1000, h = 600 })
		handle.setProfile("automatic")
		handle.setInput("automatic")
		expect(env:get("viewportRect"):peek().w).toBe(1000)
		expect(env:get("interactionClasses"):peek().primary).toBe("pointer")
		expect(env:get("distanceProfile"):peek()).toBe("near")
		expect(handle.setProfile("typo")).toBe(false)
		env:set("viewportRect", { x = 0, y = 0, w = 777, h = 500 })
		handle.source:batch(function()
			handle.source:set("preferredInput", "Touch")
		end)
		expect(env:get("viewportRect"):peek().w).toBe(777)
		handle.source:set("reducedMotion", true)
		handle.setProfile("tablet")
		handle.setOrientation("landscape")
		expect(env:get("viewportRect"):peek().w).toBe(1000)
		handle.setOrientation("portrait")
		expect(env:get("viewportRect"):peek().w).toBe(768)
		expect(env:get("reducedMotion"):peek()).toBe(true)
		handle.setProfile("phone")
		handle.setOrientation("portrait")
		expect(env:get("viewportRect"):peek().h).toBe(600)
		handle.dispose()
		expect(env:get("viewportRect"):peek().w).toBe(1000)
	end)
end)
