--!strict
-- UI-PARADIGM-002 (affordance matrix §C, text-entry rows): hot-switch transition
-- semantics for a field that is EDITING (sinking context up) when the live
-- interaction-class set flips mid-edit.
--
--   * CARRY  — a device ARRIVING mid-edit never ends editing: the edit and its
--     sinking context survive, typed text is intact, the newly-live class simply
--     ALSO gains its idiom (a hardware keyboard supersedes the on-screen one).
--   * CANCEL -> commit-or-revert — the editing SURFACE class goes away mid-edit
--     (the on-screen keyboard is dismissed by a dock: touch was the entry surface
--     at edit-start, touch leaves the live set, and no hardware keyboard remains
--     to supersede it). The engine may not report this as a FocusLost, so the
--     control ends the edit through the EXISTING commit path: the sink context
--     comes down, navigation resumes, and the value model keeps the last accepted
--     text (never silently dropped).
--
-- Keyed off the LIVE interaction-class set (ADR-0015), never preferredInput alone.
-- Every interaction goes through the real paths (adapter.tap / adapter.focusText /
-- system.deviceKey / env class flips), never a direct callback.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local text_input = require("../src/controls/text_input")
local fake_target = require("../tests/lib/fake_target")

local FIELD = "/S/Name/Field"

local TOUCH_ONLY = { keyboard = false, mouse = false, touch = true, gamepad = false }
local TOUCH_PLUS_KEYBOARD = { keyboard = true, mouse = false, touch = true, gamepad = false }
local GAMEPAD_ONLY = { keyboard = false, mouse = false, touch = false, gamepad = true }
local KEYBOARD_ONLY = { keyboard = true, mouse = false, touch = false, gamepad = false }

local function world(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	if options.caps ~= nil then
		env:set("capabilities", options.caps)
	end
	if options.preferredInput ~= nil then
		env:set("preferredInput", options.preferredInput)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)

	local commits: { { text: string, reason: string } } = {}
	local value = core:signal(options.initial or "")
	local control = text_input.build(LuauUI, core, {
		id = "Name",
		value = value,
		onCommit = function(text: string, reason: string)
			table.insert(commits, { text = text, reason = reason })
		end,
		env = env,
		actionSystem = system,
	})
	local screen = LuauUI.UI.Screen({ id = "S", children = { control.blueprint } })
	local handle = pres.present(screen, {
		sinkNavigation = true,
		onActivate = function(path, meta)
			control.api.handleActivate(path, meta)
		end,
		onGeometry = function(rectOf)
			control.api.syncGeometry(rectOf)
		end,
		keepVisibleOffset = control.api.keepVisibleOffset,
	})
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		system = system,
		control = control,
		value = value,
		commits = commits,
		handle = handle,
	}
end

-- a nav probe BELOW the edit context (fires when nobody sinks): proves the sink
-- is up (probe swallowed) while editing and DOWN (probe fires) after the edit ends
local function probe(w: any)
	local ctx = w.system.createContext({ name = "Probe", priority = 3000, sink = false })
	local nav = ctx.createAction("ProbeNav", "Direction1D")
	nav.bind({ keyCode = "DPadDown", direction = 1 })
	local fired = { n = 0 }
	w.core:observe(nav.state, function(dir)
		if dir == 1 then
			fired.n += 1
		end
	end)
	return fired
end

describe("UI-PARADIGM-002 text entry: CARRY when a device arrives mid-edit", function()
	it("a gamepad arriving mid-edit CARRIES the edit (editing stays, text intact)", function()
		local w = world({ caps = TOUCH_ONLY, preferredInput = "Touch" })
		w.adapter.tap(FIELD, { pointer = "touch" })
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		expect(w.control.api.editing:get()).toBe(true)
		-- a gamepad ARRIVES (class added) — never ends editing
		w.env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = true })
		expect(w.control.api.editing:get()).toBe(true)
		expect(w.value:get()).toBe("hi")
		expect(#w.commits).toBe(0)
	end)

	it("touch leaving mid-edit CARRIES while a hardware keyboard stays live (keyboard supersedes the OSK)", function()
		local w = world({ caps = TOUCH_PLUS_KEYBOARD, preferredInput = "Touch" })
		w.adapter.tap(FIELD, { pointer = "touch" })
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		expect(w.control.api.editing:get()).toBe(true)
		-- touch leaves but the hardware keyboard remains: editing continues
		w.env:set("capabilities", KEYBOARD_ONLY)
		expect(w.control.api.editing:get()).toBe(true)
		expect(#w.commits).toBe(0)
	end)
end)

describe("UI-PARADIGM-002 text entry: CANCEL -> commit when the editing surface leaves", function()
	it("touch (the on-screen-keyboard surface) leaving mid-edit ends the edit via commit (no wedge)", function()
		local w = world({ caps = TOUCH_ONLY, preferredInput = "Touch" })
		w.adapter.tap(FIELD, { pointer = "touch" })
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		expect(w.control.api.editing:get()).toBe(true)
		-- DOCK: handheld -> TV. Touch capability lost, no hardware keyboard, gamepad
		-- becomes primary so touch is not force-live; the on-screen keyboard is gone.
		w.env:set("preferredInput", "Gamepad")
		w.env:set("capabilities", GAMEPAD_ONLY)
		-- the edit ended through the ordinary commit path
		expect(w.control.api.editing:get()).toBe(false)
		expect(#w.commits).toBe(1)
		expect(w.commits[1].reason).toBe("focusLost")
		-- the value model kept the last accepted text — never dropped
		expect(w.value:get()).toBe("hi")
	end)

	it("after the editing-surface loss the sink context comes down and navigation resumes", function()
		local w = world({ caps = TOUCH_ONLY, preferredInput = "Touch" })
		local fired = probe(w)
		w.adapter.tap(FIELD, { pointer = "touch" })
		w.adapter.focusText(FIELD)
		w.adapter.typeText(FIELD, "hi")
		-- while editing, the sink swallows the probe's Navigate
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(fired.n).toBe(0)
		-- editing-surface loss (dock) commits and brings the sink down
		w.env:set("preferredInput", "Gamepad")
		w.env:set("capabilities", GAMEPAD_ONLY)
		expect(w.control.api.editing:get()).toBe(false)
		-- navigation resumes: the probe fires again
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(fired.n).toBe(1)
	end)

	it("the keep-visible offset resets when the on-screen keyboard clears on dock (mid-edit)", function()
		local w = world({ caps = TOUCH_ONLY, preferredInput = "Touch" })
		w.adapter.tap(FIELD, { pointer = "touch" })
		expect(w.control.api.editing:get()).toBe(true)
		local rect = w.handle.controller.rectOf(FIELD)
		local keyboardTop = rect.y + rect.h - 20
		w.env:set("keyboardOcclusionRect", { x = 0, y = keyboardTop, w = 800, h = 600 - keyboardTop })
		expect(w.control.api.keepVisibleOffset:get()).toBeGreaterThan(0)
		-- DOCK: the OSK is dismissed (occlusion clears) and touch leaves
		w.env:set("preferredInput", "Gamepad")
		w.env:set("keyboardOcclusionRect", nil)
		w.env:set("capabilities", GAMEPAD_ONLY)
		expect(w.control.api.keepVisibleOffset:get()).toBe(0)
		expect(w.control.api.editing:get()).toBe(false)
	end)
end)
