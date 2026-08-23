--!strict
-- P1.3/P1.5 presenter tests (§12.1, §17 Phase 1 exit gate): modal context
-- priority/sinking/disposal, focus trap + restoration, Cancel routing, and
-- full-slice churn neutrality (mount+render+input+focus together).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("../tests/lib/fake_target")

--[[ ONE SUBSTRATE (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants — the
	viewport is set before anything can solve, and one presenter per adapter. The
	tuple order here, `core, env, adapter, system, pres`, is the one
	`Facet.newPresenter` itself takes and is now the only one in the suite: twelve
	files used to swap positions three and four with the same five names, so a line
	copied between two neighbouring specs bound an action system to a variable
	called `adapter` and said nothing. ]]
local function makeWorld()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

local function settingsScreen()
	return UI.Screen({
		id = "Settings",
		children = {
			UI.Text({ id = "Title", text = "Settings", textSize = 24 }),
			UI.Toggle({ id = "Music", label = "Music", value = false }),
			UI.Toggle({ id = "Sfx", label = "Sfx", value = true }),
			UI.Button({ id = "Save", label = "Save" }),
		},
	})
end

local function confirmModal()
	return UI.Screen({
		id = "Confirm",
		children = {
			UI.Text({ id = "Prompt", text = "Discard changes?", textSize = 18 }),
			UI.Button({ id = "Yes", label = "Yes" }),
			UI.Button({ id = "No", label = "No" }),
		},
	})
end

describe("presenter: screens and modals", function()
	it("presents a screen with document-order focus and device navigation", function()
		local _, _, _, system, pres = makeWorld()
		pres.present(settingsScreen())
		expect(pres.focus.focused:get()).toBe("/Settings/Music")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Settings/Sfx")
	end)

	it("a modal sinks navigation from the base screen and traps focus", function()
		local _, _, _, system, pres = makeWorld()
		pres.present(settingsScreen())
		pres.presentModal(confirmModal())
		expect(pres.focus.focused:get()).toBe("/Confirm/Yes")
		-- device navigation reaches ONLY the modal (sink)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Confirm/No")
		-- wraps inside the trap, never escapes to Settings
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Confirm/Yes")
	end)

	it("Cancel dismisses the modal, restores focus, and disposes its context", function()
		local core, _, _, system, pres = makeWorld()
		pres.present(settingsScreen())
		system.deviceKey("Down", true)
		system.deviceKey("Down", false) -- focus Sfx
		local modal = pres.presentModal(confirmModal())
		expect(pres.depth()).toBe(2)
		system.deviceKey("ButtonB", true)
		system.deviceKey("ButtonB", false)
		expect(pres.depth()).toBe(1)
		expect(pres.focus.focused:get()).toBe("/Settings/Sfx") -- restored
		-- destroyed context: firing its old bindings is a silent no-op
		expect(modal.context.destroyed).toBe(true)
		-- navigation returns to the base screen
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Settings/Save")
	end)

	it("activate routes to the focused control of the top scope", function()
		local _, _, _, system, pres = makeWorld()
		local activated: { string } = {}
		pres.present(settingsScreen(), {
			onActivate = function(path)
				table.insert(activated, path)
			end,
		})
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(activated[1]).toBe("/Settings/Music")
	end)

	it("open/close churn is registry-neutral across the whole slice", function()
		local core, _, adapter, _, pres = makeWorld()
		pres.present(settingsScreen())
		local baseline = core:counters()
		local liveBaseline = adapter.liveCount()
		for _ = 1, 20 do
			local modal = pres.presentModal(confirmModal())
			pres.dismiss(modal)
		end
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
		expect(adapter.liveCount()).toBe(liveBaseline)
	end)
end)

describe("presenter: re-entrant dismiss (phase-2 verifier F-2)", function()
	it("dismissing a modal from inside its own onActivate is safe", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		local pres = presenterLib.new(core, env, adapter, system)
		pres.present(settingsScreen())
		local modal
		modal = pres.presentModal(confirmModal(), {
			onActivate = function(_path)
				pres.dismiss(modal) -- close from within the action dispatch
			end,
		})
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(pres.depth()).toBe(1)
		expect(modal.context.destroyed).toBe(true)
		-- base screen navigation still works after the re-entrant dismiss
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Settings/Sfx")
	end)
end)

--[[ THE STRING-ENUM OPTS ARE VALIDATED AT PRESENT TIME
	(api-architecture-consistency F-15). `makeHandle` has refused an unknown
	`cancelPolicy` since it existed, with a comment stating the rule: "a typo that
	silently kept the default would read as 'the framework ignored my mandatory
	modal'". Two of the four string enums did not follow it — `responder` was
	compared by equality (`responder = "Passive"` silently presented an ENGAGED
	surface that sank nothing) and `scrim` was passed through raw (`scrim = "None"`
	silently DIMMED the screen). Both now fail at the call site like their sibling. ]]
describe("presenter: unknown string-enum opts fail at the call site (F-15)", function()
	it("an unknown responder names the opt and its legal set", function()
		local _, _, _, _, pres = makeWorld()
		local ok, err = pcall(function()
			pres.present(settingsScreen(), { responder = "Passive" } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "responder", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Passive", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "passive", 1, true) ~= nil).toBe(true)
		-- and nothing was presented behind the error
		expect(pres.depth()).toBe(0)
	end)

	it("an unknown scrim names the opt and its legal set", function()
		local _, _, _, _, pres = makeWorld()
		local ok, err = pcall(function()
			pres.presentModal(confirmModal(), { scrim = "None" } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "scrim", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "None", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "none", 1, true) ~= nil).toBe(true)
		expect(pres.depth()).toBe(0)
	end)

	it("the legal values still present: responder passive, scrim scrim/none", function()
		local _, _, _, _, pres = makeWorld()
		local hud = pres.present(settingsScreen(), { responder = "passive" })
		expect(hud.responder:get()).toBe("passive")
		local modal = pres.presentModal(confirmModal(), { scrim = "none" })
		expect(modal.scrimMode).toBe("none")
		local plain = pres.presentModal(confirmModal(), { scrim = "scrim" })
		expect(plain.scrimMode).toBe("scrim")
		expect(pres.depth()).toBe(3)
	end)
end)

--[[ THE FALLBACK IS PRESENTED WITH THE CALLER'S OPTS
	(api-architecture-consistency F-16). `presentCritical` used to hand the
	fallback `{ onActivate = opts.onActivate }` and nothing else, so a critical
	screen declared `rootPolicy = "edgeToEdge"` (or navigationGroups, transition,
	sinkNavigation, …) lost all of it exactly when things had already gone wrong —
	the fallback rendered under the wrong root policy, a second failure stacked on
	the first. ]]
describe("presenter: presentCritical carries the caller's opts to the fallback (F-16)", function()
	local function criticalWorld()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local system = actionsLib.newSystem(core)
		return adapter, presenterLib.new(core, env, adapter, system)
	end

	local function fallbackScreen()
		return UI.Screen({
			id = "SafeMode",
			children = { UI.Button({ id = "Retry", label = "Retry" }) },
		})
	end

	it("a critical fallback under rootPolicy=edgeToEdge resolves the edge-to-edge rect", function()
		local adapter, pres = criticalWorld()
		local handle = pres.presentCritical(function()
			error("screen construction failed")
		end, {
			rootPolicy = "edgeToEdge",
			fallbackScreen = fallbackScreen,
		})
		expect(handle.blueprint.id).toBe("SafeMode")
		-- edgeToEdge clears the 36px CoreGui inset; the default would not
		expect(adapter.node("/SafeMode/Retry").rect.y).toBe(0)
	end)

	it("without the opt the fallback keeps the default content inset", function()
		local adapter, pres = criticalWorld()
		pres.presentCritical(function()
			error("screen construction failed")
		end, { fallbackScreen = fallbackScreen })
		expect(adapter.node("/SafeMode/Retry").rect.y).toBe(36)
	end)

	it("the fallback screen is not asked to present itself as its own fallback", function()
		-- `fallbackScreen` is the one opt that must NOT ride along: the fallback
		-- presents as an ordinary screen, and its own errors stay hard (§17).
		local _, pres = criticalWorld()
		local handle = pres.presentCritical(function()
			error("boom")
		end, {
			responder = "passive",
			fallbackScreen = fallbackScreen,
		})
		expect(handle.blueprint.id).toBe("SafeMode")
		expect(handle.responder:get()).toBe("passive") -- the caller's opt survived
		expect((handle.blueprint :: any).fallbackScreen).toBeNil()
	end)
end)

--[[ `presenter.raise` (registry item 23; W3-D, ADR-0053) — re-band a LIVE
	surface without dismiss+re-present. `examples/gallery/client/
	showcase_chrome.luau`'s `raisePanel` is the real, migrated consumer
	(`tests/gallery_chrome.spec.luau` describe (15) exercises it end-to-end,
	through the real InputAction/demo-picker path); this block is the direct,
	presenter-level unit coverage the seam itself needs. ]]
describe("presenter: raise re-bands a live surface without dismiss+re-present", function()
	it("bumps a base screen into a fresh band slot, in place", function()
		local _, _, adapter, _, pres = makeWorld()
		local handle = pres.present(settingsScreen())
		local before = adapter.rootDisplayOrder("Settings")
		pres.raise(handle)
		local after = adapter.rootDisplayOrder("Settings")
		expect(`raised: {after} (was {before})`).toBe(`raised: {before + 100} (was {before})`)
		expect(handle.displayOrder).toBe(after)
	end)

	it("raises within the MODAL band, never the base band", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(settingsScreen())
		local modal = pres.presentModal(confirmModal())
		pres.raise(modal)
		-- a base-band mistake would land far below this floor (~10000+N*100
		-- against a 40000 floor), so this is the branch assertion, not just "it
		-- went up"
		expect(modal.displayOrder >= pres.SURFACE_LAYER.modal).toBe(true)
	end)

	it("re-homes an owned scrim's displayOrder along with the surface it belongs to", function()
		local _, _, adapter, _, pres = makeWorld()
		pres.present(settingsScreen())
		local modal = pres.presentModal(confirmModal())
		local scrimBefore = adapter.rootDisplayOrder("__scrim__")
		pres.raise(modal)
		local scrimAfter = adapter.rootDisplayOrder("__scrim__")
		expect(`scrim followed: {scrimAfter} = modal - 50 ({modal.displayOrder - 50})`).toBe(
			`scrim followed: {modal.displayOrder - 50} = modal - 50 ({modal.displayOrder - 50})`
		)
		expect(scrimAfter > scrimBefore).toBe(true)
	end)

	it("REFUSES a handle already dismissed — silently, matching `dismiss`'s own shape", function()
		local _, _, _, _, pres = makeWorld()
		local handle = pres.present(settingsScreen())
		pres.dismiss(handle)
		local before = handle.displayOrder
		pres.raise(handle)
		expect(handle.displayOrder).toBe(before)
	end)

	it("REFUSES nil without erroring — a defensive caller must not be punished", function()
		local _, _, _, _, pres = makeWorld()
		pres.present(settingsScreen())
		pres.raise(nil :: any)
	end)

	it("never remounts: zero instance churn and focus never moves", function()
		local core, _, adapter, system, pres = makeWorld()
		local handle = pres.present(settingsScreen())
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Settings/Sfx")
		local baseline = core:counters()
		local liveBaseline = adapter.liveCount()
		pres.raise(handle)
		local after = core:counters()
		for k, v in baseline :: any do
			expect((after :: any)[k]).toBe(v)
		end
		expect(adapter.liveCount()).toBe(liveBaseline)
		-- the ring never moved, because nothing capable of moving it ran
		expect(pres.focus.focused:get()).toBe("/Settings/Sfx")
	end)
end)
