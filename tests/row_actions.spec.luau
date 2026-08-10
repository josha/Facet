--!strict
-- RowActions control spec (Task 3: composite skeleton, static reveal). Mirrors
-- tests/chip.spec.luau's presenterWorld/renderWorld idioms. This file proves:
--   1. the spec/ActionSpec authoring contract (unknown keys, empty-list refusal);
--   2. the true inert passthrough when neither edge has actions;
--   3. the lazy tray structure (Action:<id> buttons, destructive role);
--   4. long-label survival at the theme's buttonMinWidth floor;
--   5. the static _open/_close/dump seam (Tasks 4-6 build motion on it);
--   6. registry neutrality on dispose;
-- and, because the tray buttons are reached through the composite's OWN
-- input contribution (contribution.attach + a routed handleActivate — see
-- src/controls/row_actions.luau), the four-input REACHABILITY and PARADIGM
-- proofs the extension checker requires of every interactive control
-- (ui_todo §0; UI-PARADIGM-001), exercised through the standard tap/
-- deviceKey device-true paths, same as tests/chip.spec.luau.
--
-- RowActions owns NO in-flight gesture state as of this task (no pointer
-- handling — Step 3 of the plan): hotSwitch = false in the registry row is
-- accurate for what ships here, and Tasks 5-8 (drag/touch/keyboard-adjust)
-- must revisit it once a mid-gesture class flip has something to carry.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local fake_target = require("../tests/lib/fake_target")
local lt = require("./lib/large_text")

-- renderer-level modules for the headless mount->attach->render axis (hover,
-- ten-foot focus), mirroring tests/chip.spec.luau's renderWorld
local mountLib = require("../src/mount")
local renderer = require("../src/render/renderer")

local ROW = "/S/Row"
local TRAILING_TRAY = ROW .. "/TrayTrailingWhen/then/TrayTrailing"
local DELETE_PATH = TRAILING_TRAY .. "/Action:delete"

-- a REALISTIC row height (a List/Table row is never text-line-tall) — the
-- tray Buttons fill it, so a too-short fixture would blame the composite for
-- what is really an unrealistic caller-provided row box.
local function content(id: string?)
	return LuauUI.UI.Text({ id = id or "Body", text = "Row content", height = { type = "fixed", px = 48 } })
end

-- presenter harness: the four-input auto-composition path (chip.spec's house
-- style). `build` receives `core` and returns the row_actions instance.
local function presenterWorld(build: (core: any) -> any)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local ra = build(core)
	local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	return { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
end

-- a world whose trailing tray is ALREADY revealed before the first present —
-- the honest way to reach a lazily-mounted tray button's device-true story
-- without this spec depending on Tasks 5-8's drag/touch gesture machinery
-- (hard rule: prove reachability through the standard Button path, or stop).
local function openTrailingWorld(actions: { any }?)
	local fired: { string } = {}
	local w = presenterWorld(function(core)
		return row_actions.build(LuauUI, core, {
			id = "Row",
			content = content(),
			trailing = actions or {
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
	end)
	-- ^ presenterWorld already called present()+refresh() with the tray
	-- CLOSED; open it now and refresh again so the buttons exist to focus.
	w.ra._open("trailing")
	w.pres.refresh()
	return {
		core = w.core,
		env = w.env,
		system = w.system,
		adapter = w.adapter,
		pres = w.pres,
		ra = w.ra,
		fired = fired,
	}
end

-- renderer harness: mount a row_actions (trailing tray pre-opened) and attach
-- the renderer directly, mirroring chip.spec.luau's renderWorld.
local function renderWorldOpen(envSetup: ((any) -> ())?, actions: { any }?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if envSetup then
		envSetup(env)
	end
	local ra = row_actions.build(LuauUI, core, {
		id = "Row",
		content = content(),
		trailing = actions or { { id = "delete", label = "Delete", onAction = function() end } },
	})
	ra._open("trailing")
	local root = mountLib.mount(core, LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } }))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller, ra = ra }
end

describe("RowActions control", function()
	-- 1. AUTHORING CONTRACT (constitution §4; ARCH-1) ------------------------
	it("validates unknown spec keys", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, { contnet = content() } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an empty action list", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, { content = content(), leading = {} })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "nil", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an unknown ActionSpec key", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, {
				content = content(),
				trailing = { { label = "Delete", onAction = function() end, oaction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		-- "onAction" is a 2-edit neighbor of "oaction" (drop 'n', case-fold 'A')
		expect(string.find(tostring(err), "you mean", 1, true) ~= nil).toBe(true)
	end)

	it("rejects an ActionSpec with an unknown role", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			return row_actions.build(LuauUI, core, {
				content = content(),
				trailing = { { label = "Delete", role = "scary", onAction = function() end } :: any },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "normal, destructive", 1, true) ~= nil).toBe(true)
	end)

	-- 2. INERT PASSTHROUGH (perf directive) -----------------------------------
	it("is an inert passthrough with no actions", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, { id = "Row", content = content("Body") })
		end)
		expect(w.adapter.node("/S/Body") ~= nil).toBe(true) -- content mounted, unwrapped
		expect(w.adapter.node(ROW) == nil).toBe(true) -- no RowActions wrapper node at all
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
	end)

	-- 3. LAZY TRAY STRUCTURE ---------------------------------------------------
	it("mounts trailing tray buttons with ids Action:<id> only once revealed", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		-- CLOSED: zero tray GuiObjects (the perf directive's lazy mount)
		expect(w.adapter.node(DELETE_PATH) == nil).toBe(true)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(DELETE_PATH) ~= nil).toBe(true)
		expect(w.adapter.node(DELETE_PATH).props.label).toBe("Delete")
	end)

	it("destructive action paints danger tokens; normal action paints the default role", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{ id = "delete", label = "Delete", role = "destructive", onAction = function() end },
					{ id = "flag", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:delete").props.role).toBe("destructive")
		expect(w.adapter.node(TRAILING_TRAY .. "/Action:flag").props.role).toBe("default")
	end)

	-- 4. LOCALIZATION SAFETY ----------------------------------------------------
	it("labels survive 1.4x pseudo-loc without clipping (button never narrower than buttonMinWidth)", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = lt.PSEUDO, onAction = function() end } },
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		local node = w.adapter.node(DELETE_PATH)
		expect(node ~= nil).toBe(true)
		-- the composite never truncates the label itself (no clip anywhere in
		-- this file) — the floor is the theme's buttonMinWidth (64px, Task 2)
		expect(node.props.label).toBe(lt.PSEUDO)
		expect(node.rect.w >= 64).toBe(true)
	end)

	-- 5. THE STATIC REVEAL SEAM (Tasks 4-6 build motion on this) ---------------
	it("_open slides content by tray width; _close returns it; dump reflects openEdge", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)

		w.ra._open("trailing")
		w.pres.refresh()
		local trayRect = w.adapter.node(TRAILING_TRAY).rect
		expect(w.ra.dump().offset).toBe(-trayRect.w)
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(w.ra.dump().phase).toBe("open")
		expect(w.ra._isOpen()).toBe(true)

		w.ra._close()
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra.dump().openEdge).toBe(nil)
		expect(w.ra.dump().phase).toBe("closed")
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("_open on an edge with no actions is a no-op", function()
		local w = presenterWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
			})
		end)
		w.ra._open("leading") -- no leading actions declared
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	-- 6. DISPOSAL / REGISTRY NEUTRALITY ------------------------------------------
	it("dispose unmounts and releases the scope", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = { { id = "delete", label = "Delete", onAction = function() end } },
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen)
		pres.refresh()
		ra._open("trailing")
		pres.refresh()
		adapter.tap(DELETE_PATH)

		pres.dismiss(handle)
		ra.dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	-- 7. FOUR-INPUT REACHABILITY (ui_todo §0) — device-true, all four classes.
	-- Proven through the standard UI.Button path a revealed tray action IS
	-- (hard rule: honest reachability through what this task actually built,
	-- not a fabricated proof of the swipe gesture itself — that is Tasks 5-8).
	it("RowActions pointer: a tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		expect(#w.fired).toBe(0)
		w.adapter.tap(DELETE_PATH)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions touch: a touch tap on a revealed tray action activates it (device-true)", function()
		local w = openTrailingWorld()
		w.adapter.tap(DELETE_PATH, { source = "pointer", pointer = "touch" })
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions keyboard: focus + Return activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(w.fired[1]).toBe("delete")
	end)

	it("RowActions gamepad: focus + ButtonA activates a revealed tray action", function()
		local w = openTrailingWorld()
		expect(w.pres.focus.focused:get()).toBe(DELETE_PATH)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.fired[1]).toBe("delete")
	end)

	-- 8. PARADIGM AXIS (UI-PARADIGM-001) — the STRUCTURAL IDIOM per class. Every
	-- tray action IS a standard UI.Button, so it inherits the Button contract's
	-- own affordances; these cases prove the composite does not defeat them.
	it("RowActions pointer affordance: the pointer structural idiom (hover on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = false })
			env:set("preferredInput", "KeyboardAndMouse")
		end)
		expect(w.adapter.node(DELETE_PATH).hoverEnabled).toBe(true)
		w.adapter.hover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(true)
		w.adapter.unhover(DELETE_PATH)
		expect(w.adapter.node(DELETE_PATH).hovered).toBe(false)
	end)

	it("RowActions touch affordance: the touch structural idiom (44px floor on a revealed tray action)", function()
		local w = renderWorldOpen(function(env)
			env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = false })
			env:set("preferredInput", "Touch")
		end)
		expect(w.adapter.node(DELETE_PATH).rect.h >= 44).toBe(true)
	end)

	it("RowActions keyboard affordance: the keyboard structural idiom (focus ring/Navigate/Activate)", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local fired: { string } = {}
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = {
				{
					id = "flag",
					label = "Flag",
					onAction = function()
						table.insert(fired, "flag")
					end,
				},
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
		ra._open("trailing")
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		pres.present(screen)
		pres.refresh()
		local flagPath = TRAILING_TRAY .. "/Action:flag"
		local deletePath = TRAILING_TRAY .. "/Action:delete"
		expect(pres.focus.focused:get()).toBe(flagPath) -- Navigate order: leftmost tray button first
		expect(adapter.node(flagPath).focused).toBe(true)
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		expect(pres.focus.focused:get()).toBe(deletePath) -- Navigate moved the ring
		expect(adapter.node(deletePath).focused).toBe(true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		expect(fired[1]).toBe("delete") -- Activate hit the focused action only
	end)

	it(
		"RowActions gamepad affordance: the gamepad structural idiom (ten-foot focus on a revealed tray action)",
		function()
			local big = renderWorldOpen(function(env)
				env:set("displaySize", "Large")
			end)
			big.controller.setFocusPath(DELETE_PATH)
			local near = renderWorldOpen(function(env)
				env:set("displaySize", "Medium")
			end)
			near.controller.setFocusPath(DELETE_PATH)
			expect(big.adapter.node(DELETE_PATH).focusProfile).toBe("ten-foot")
			expect(near.adapter.node(DELETE_PATH).focusProfile).toBe("near")
		end
	)
end)
