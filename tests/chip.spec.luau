--!strict
-- Chip control spec. A Chip is a small toggleable tag/filter pill: Activate
-- (pointer tap / click / keyboard Return / gamepad ButtonA) flips the owner-held
-- `selected` signal and calls `onToggle`; the surface reflects selection. It owns
-- NO in-flight state, so the paradigm axis is: pointer HOVER preview, touch 44px
-- floor, keyboard focus-ring + Navigate→Activate, gamepad ten-foot focus — and
-- hotSwitch = false (nothing to carry/cancel mid-gesture).
--
-- Every interaction runs through a REAL device path: adapter.tap (pointer/touch)
-- and system.deviceKey (keyboard/gamepad) via the presenter's zero-opt auto
-- composition; hover/focus-profile idioms run through the renderer's synthetic
-- hover/focus seams. No callback is ever called directly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local Facet = require("../src") :: any
local chip = require("../src/controls/chip")
local fake_target = require("../tests/lib/fake_target")

-- renderer-level modules for the headless mount→attach→render axis (hover,
-- ten-foot focus, layout), mirroring tests/paradigm_hover + paradigm_tenfoot
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")

local CHIP = "/S/Chip"
local CHIP2 = "/S/Chip2"

-- presenter harness: the four-input auto-composition path (auto_input house style)
local function presenterWorld(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local selected = core:signal(options.selected == true)
	local toggles: { boolean } = {}
	local c = chip.build(Facet, core, {
		id = "Chip",
		label = "Rain",
		selected = selected,
		onToggle = function(v: boolean)
			table.insert(toggles, v)
		end,
	})
	local children = { c.blueprint }
	local selected2 = nil
	local c2 = nil
	if options.sibling then
		selected2 = core:signal(false)
		c2 = chip.build(Facet, core, { id = "Chip2", label = "Snow", selected = selected2 })
		table.insert(children, c2.blueprint)
	end
	local screen = Facet.UI.Screen({ id = "S", children = children })
	local handle = pres.present(screen) -- ZERO opts: full auto-composition
	pres.refresh()
	return {
		core = core,
		env = env,
		system = system,
		adapter = adapter,
		pres = pres,
		chip = c,
		selected = selected,
		toggles = toggles,
		selected2 = selected2,
		chip2 = c2,
		handle = handle,
	}
end

-- renderer harness: mount a chip inside a Screen and attach the renderer directly
local function renderWorld(envSetup: ((any) -> ())?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup then
		envSetup(env)
	end
	local selected = core:signal(false)
	local c = chip.build(Facet, core, { id = "Chip", label = "Rain", selected = selected })
	local root = mountLib.mount(core, Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller, chip = c, selected = selected }
end

describe("Chip control", function()
	-- 1. BUILD + RENDER (playbook step 2.1) --------------------------------
	it("builds, mounts, and renders headlessly with no error", function()
		local w = renderWorld()
		expect(w.chip.blueprint ~= nil).toBeTruthy()
		expect(w.adapter.node(CHIP) ~= nil).toBe(true)
		expect(w.adapter.node(CHIP).props.label).toBe("Rain")
		expect(w.core:lastError()).toBe(nil)
	end)

	-- 2. FOUR-INPUT REACHABILITY (ui_todo §0) — device-true, all four classes
	it("Chip pointer: a tap activates through the presenter (device-true)", function()
		local w = presenterWorld()
		expect(w.selected:get()).toBe(false)
		w.adapter.tap(CHIP) -- mouse pointer tap (meta = nil)
		expect(w.selected:get()).toBe(true)
		w.pres.refresh() -- flush the binding to the rendered surface
		expect(w.adapter.node(CHIP).props.selected).toBe(true) -- surface reflects it
		expect(w.toggles[1]).toBe(true) -- onToggle fired with the new value
		w.adapter.tap(CHIP)
		expect(w.selected:get()).toBe(false)
	end)

	it("Chip touch: a touch tap/pan drives the control (device-true)", function()
		local w = presenterWorld()
		-- a touch-typed activation: the engine's Activated meta carries
		-- pointer="touch" (screen_target.luau), distinct from the mouse path
		w.adapter.tap(CHIP, { source = "pointer", pointer = "touch" })
		expect(w.selected:get()).toBe(true)
		expect(w.toggles[1]).toBe(true)
		w.adapter.tap(CHIP, { source = "pointer", pointer = "touch" })
		expect(w.selected:get()).toBe(false)
	end)

	it("Chip keyboard: focus + Return drives the control", function()
		local w = presenterWorld()
		expect(w.pres.focus.focused:get()).toBe(CHIP) -- auto-focused sole focusable
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.selected:get()).toBe(true)
		expect(w.toggles[1]).toBe(true)
	end)

	it("Chip gamepad: focus + ButtonA drives the control", function()
		local w = presenterWorld()
		expect(w.pres.focus.focused:get()).toBe(CHIP)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.selected:get()).toBe(true)
	end)

	-- 3. PARADIGM AXIS (UI-PARADIGM-001) — the STRUCTURAL IDIOM per class,
	-- distinct from mere reachability above.
	it("Chip pointer affordance: the pointer structural idiom (hover/direct-drag/wheel)", function()
		-- the free HOVER preview layer: a pointer-live renderer wires hover onto
		-- the interactive chip surface; synthetic hover flips its state.
		local w = renderWorld(function(env)
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			env:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(w.adapter.node(CHIP).hoverEnabled).toBe(true)
		w.adapter.hover(CHIP)
		expect(w.adapter.node(CHIP).hovered).toBe(true)
		w.adapter.unhover(CHIP)
		expect(w.adapter.node(CHIP).hovered).toBe(false)
	end)

	it("Chip touch affordance: the touch structural idiom (44px/naked-pan-scroll/edit-grip)", function()
		-- the 44px hit floor: the chip enforces the Button contract's minHitSize
		-- as a real layout minimum, so a finger always has a 44px target.
		local w = renderWorld(function(env)
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
			env:set("preferredInput", "Touch")
		end)
		expect(w.adapter.node(CHIP).rect.h >= 44).toBe(true)
		-- and a pure-touch device allocates NO hover wiring (hover is pointer-only;
		-- nothing essential lives behind it — the tap still activates below)
		expect(w.adapter.node(CHIP).hoverEnabled ~= true).toBe(true)
	end)

	it("Chip keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate/Adjust)", function()
		-- Navigate (arrows) moves the visible focus RING between siblings, then
		-- Activate (Return) fires on the focused one — the keyboard idiom, which
		-- reachability (single pre-focused chip) does not exercise.
		local w = presenterWorld({ sibling = true })
		expect(w.pres.focus.focused:get()).toBe(CHIP)
		expect(w.adapter.node(CHIP).focused).toBe(true) -- the ring is on chip 1
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(CHIP2) -- Navigate moved the ring
		expect(w.adapter.node(CHIP2).focused).toBe(true)
		expect(w.adapter.node(CHIP).focused).toBe(false)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.selected2:get()).toBe(true) -- Activate hit the focused chip only
		expect(w.selected:get()).toBe(false)
	end)

	it("Chip gamepad affordance: the gamepad structural idiom (focus/grab/A-B/ten-foot)", function()
		-- the ten-foot focus strengthening (matrix D.4): a Large display renders a
		-- STRONGER focus profile than a near Medium display — the gamepad/10-foot
		-- idiom, distinct from the ButtonA reachability proof.
		local big = renderWorld(function(env)
			env:set("displaySize", "Large")
		end)
		big.controller.setFocusPath(CHIP)
		local near = renderWorld(function(env)
			env:set("displaySize", "Medium")
		end)
		near.controller.setFocusPath(CHIP)
		expect(big.adapter.node(CHIP).focusProfile).toBe("ten-foot")
		expect(near.adapter.node(CHIP).focusProfile).toBe("near")
		expect(big.adapter.node(CHIP).focusProfile ~= near.adapter.node(CHIP).focusProfile).toBe(true)
	end)

	-- 4. NO FACTORY RERUNS for a binding change (playbook step 2.4) --------
	it("flipping selected updates the surface with no factory rerun", function()
		local w = presenterWorld()
		local runsBefore = w.handle.root.counters().factoryRuns
		w.adapter.tap(CHIP)
		w.pres.refresh()
		expect(w.adapter.node(CHIP).props.selected).toBe(true)
		expect(w.handle.root.counters().factoryRuns).toBe(runsBefore) -- state-driven
	end)

	-- 5. DUMP DETERMINISM (playbook step 2.5) ------------------------------
	it("dump() is deterministic and reflects the live state", function()
		local w = presenterWorld()
		local d1 = serde.encode("json", w.chip.dump(), true)
		expect(d1).toBe(serde.encode("json", w.chip.dump(), true))
		expect(w.chip.dump().selected).toBe(false)
		w.adapter.tap(CHIP)
		expect(w.chip.dump().selected).toBe(true)
		expect(w.chip.dump().label).toBe("Rain")
	end)

	-- 6. REGISTRY NEUTRALITY (playbook step 2.6) ---------------------------
	it("build/mount/present/interact/dispose returns every registry to baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters() -- AFTER the long-lived singletons

		local selected = core:signal(false)
		local c = chip.build(Facet, core, { id = "Chip", label = "Rain", selected = selected })
		local screen = Facet.UI.Screen({ id = "S", children = { c.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		adapter.tap(CHIP)
		system.deviceKey("ButtonA", true)
		system.deviceKey("ButtonA", false)

		pres.dismiss(handle)
		c.dispose()
		selected:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	-- 7. BUILD-TIME CONTRACT (CTRL-03, api-architecture-consistency F-2) -----
	-- `selected` is the owner's data model and the control's single mutation
	-- site. A missing one used to error on the first TAP ("attempt to index
	-- nil"); a read-only Memo used to error with "cannot set a memo" from deep
	-- inside core. Both are BUILD errors now, exactly like every sibling.
	it("rejects a missing `selected` at BUILD, naming the control and the field", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return chip.build(Facet, core, { id = "Rain", label = "Rain" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Chip", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "selected", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a read-only Memo `selected` at BUILD", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return chip.build(Facet, core, {
				id = "Rain",
				label = "Rain",
				selected = core:memo(function()
					return false
				end),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Chip", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
	end)
end)
