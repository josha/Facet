--!strict
-- PopupButton control tests (composite over UI.* primitives). The control is
-- a closed, single-focusable button showing the currently-selected option;
-- activating it opens a popup listing the options (each an activatable row).
-- Activating an option writes the owner-held `value` signal, fires onChange,
-- and closes the popup — the button label reflects the new selection.
-- Activating the trigger again, or the Cancel row, closes without changing
-- the selection. Keyboard/gamepad users navigate the open options and select
-- with Activate. Every interaction goes through the REAL paths (adapter.tap /
-- system.deviceKey), never by calling callbacks directly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local serde = require("@lune/serde")

local LuauUI = require("../src") :: any
local popup_button = require("../src/controls/popup_button")
local fake_target = require("../tests/lib/fake_target")

local OPTIONS = {
	{ id = "easy", label = "Easy" },
	{ id = "normal", label = "Normal" },
	{ id = "hard", label = "Hard" },
}

-- headless world: mount the control under a Screen and present it, wiring the
-- presenter's Activate/Cancel to the control's router (the shipped seam — the
-- host screen routes activation, exactly as tests/table.spec.luau does).
local function world(opts: any?)
	local options = opts or {}
	local core = options.core or LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local changes: { string } = {}
	local value = options.value or core:signal(options.initial or "normal")
	local control = popup_button.build(LuauUI, core, {
		id = "Difficulty",
		options = options.options or OPTIONS,
		value = value,
		onChange = function(id: string)
			table.insert(changes, id)
		end,
	})
	local screen = LuauUI.UI.Screen({ id = "S", children = { control.blueprint } })
	local handle = pres.present(screen, {
		sinkNavigation = true,
		onActivate = function(path, meta)
			control.api.handleActivate(path, meta)
		end,
	})
	pres.refresh()
	return {
		core = core,
		adapter = adapter,
		pres = pres,
		control = control,
		value = value,
		changes = changes,
		handle = handle,
		system = system,
	}
end

local TRIGGER = "/S/Difficulty/Trigger"
local function optPath(id: string): string
	return `/S/Difficulty/PopupWhen/then/Popup/Opt-{id}`
end
local CANCEL = "/S/Difficulty/PopupWhen/then/Popup/Cancel"

describe("PopupButton: build + render", function()
	it("mounts and renders headlessly with no runtime error", function()
		local w = world()
		expect(w.control.blueprint ~= nil).toBe(true)
		expect(w.adapter.node(TRIGGER) ~= nil).toBe(true)
		expect(w.core:lastError()).toBeNil()
	end)

	it("the closed button shows the currently-selected option's label", function()
		local w = world({ initial = "hard" })
		expect(w.adapter.node(TRIGGER).props.label).toBe("Hard")
		-- and the popup is closed: no option rows mounted
		expect(w.adapter.node(optPath("easy"))).toBe(nil)
	end)

	it("the closed control is a SINGLE focusable (only the trigger)", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
		-- one Down wraps back to the trigger: nothing else is focusable closed
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)
end)

describe("PopupButton: pointer interaction (the real tap path)", function()
	it("tapping the trigger opens the popup listing every option", function()
		local w = world()
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		for _, option in OPTIONS do
			expect(w.adapter.node(optPath(option.id)) ~= nil).toBe(true)
			expect(w.adapter.node(optPath(option.id)).props.label).toBe(option.label)
		end
	end)

	it("a TOUCH-typed tap on the trigger opens the popup listing every option", function()
		local w = world()
		-- mirror the pointer case, but with the finger-tap meta the engine
		-- delivers on a Touch input: ScreenTarget builds pointer = "touch" from a
		-- Touch UserInputType (screen_target.luau L561-563). A bare adapter.tap
		-- (meta = nil) is the mouse path; here the seam genuinely sees touch.
		w.adapter.tap(TRIGGER, { source = "pointer", pointer = "touch" })
		w.pres.refresh()
		for _, option in OPTIONS do
			expect(w.adapter.node(optPath(option.id)) ~= nil).toBe(true)
			expect(w.adapter.node(optPath(option.id)).props.label).toBe(option.label)
		end
	end)

	it("activating an option selects it, fires onChange, closes, and relabels", function()
		local w = world({ initial = "normal" })
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		w.adapter.tap(optPath("hard"))
		w.pres.refresh()
		expect(w.value:get()).toBe("hard")
		expect(#w.changes).toBe(1)
		expect(w.changes[1]).toBe("hard")
		-- popup closed
		expect(w.adapter.node(optPath("hard"))).toBe(nil)
		-- label reflects the new selection
		expect(w.adapter.node(TRIGGER).props.label).toBe("Hard")
	end)

	it("re-tapping the trigger while open closes it WITHOUT changing the selection", function()
		local w = world({ initial = "easy" })
		w.adapter.tap(TRIGGER) -- open
		w.pres.refresh()
		expect(w.adapter.node(optPath("normal")) ~= nil).toBe(true)
		w.adapter.tap(TRIGGER) -- toggle closed
		w.pres.refresh()
		expect(w.adapter.node(optPath("normal"))).toBe(nil)
		expect(w.value:get()).toBe("easy")
		expect(#w.changes).toBe(0)
	end)

	it("the Cancel row closes the popup without changing the selection", function()
		local w = world({ initial = "normal" })
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.adapter.node(CANCEL) ~= nil).toBe(true)
		w.adapter.tap(CANCEL)
		w.pres.refresh()
		expect(w.adapter.node(optPath("easy"))).toBe(nil)
		expect(w.value:get()).toBe("normal")
		expect(#w.changes).toBe(0)
	end)

	it("re-selecting the ALREADY-selected option closes without a redundant onChange", function()
		local w = world({ initial = "normal" })
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		w.adapter.tap(optPath("normal")) -- already selected
		w.pres.refresh()
		expect(w.value:get()).toBe("normal")
		expect(#w.changes).toBe(0) -- no change fired
		expect(w.adapter.node(optPath("normal"))).toBe(nil) -- still closes
	end)
end)

describe("PopupButton: keyboard / gamepad", function()
	it("keyboard opens, navigates the options, and Activate selects", function()
		local w = world({ initial = "easy" })
		-- Activate on the focused trigger opens the popup
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.adapter.node(optPath("normal")) ~= nil).toBe(true)
		-- Down walks trigger -> first option -> second option
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("easy"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("normal"))
		-- Activate selects the focused option
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.value:get()).toBe("normal")
		expect(w.changes[1]).toBe("normal")
		-- popup closed; focus returns to the (single) trigger
		expect(w.adapter.node(optPath("normal"))).toBe(nil)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)

	it("gamepad ButtonA drives the same open+select path", function()
		local w = world({ initial = "easy" })
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false) -- to first option (easy)
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false) -- to normal
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false) -- to hard
		expect(w.pres.focus.focused:get()).toBe(optPath("hard"))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		expect(w.value:get()).toBe("hard")
	end)
end)

describe("PopupButton: reactive discipline", function()
	it("opening/closing is the only structural change; a selection does not rerun the factory", function()
		local w = world({ initial = "normal" })
		-- open once so the trigger stays mounted across the selection
		local runsClosed = w.handle.root.counters().factoryRuns
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		-- selecting an option is a value write on the owner signal; the trigger
		-- subtree is NOT rebuilt (label is a binding, not a structural swap)
		local before = w.handle.root.counters().factoryRuns
		w.value:set("hard")
		w.pres.refresh()
		expect(w.handle.root.counters().factoryRuns).toBe(before)
		expect(w.adapter.node(TRIGGER).props.label).toBe("Hard")
		local _ = runsClosed
	end)

	it("dump() is deterministic and reflects open state, value, and options", function()
		local w = world({ initial = "normal" })
		local d1 = serde.encode("json", w.control.dump(), true)
		expect(d1).toBe(serde.encode("json", w.control.dump(), true))
		expect(w.control.dump().open).toBe(false)
		expect(w.control.dump().value).toBe("normal")
		w.adapter.tap(TRIGGER)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(true)
		expect(#w.control.dump().options).toBe(3)
	end)

	it("build/mount/interact/dispose returns every registry to its baseline", function()
		-- the presenter/env/action-system are process-lifetime singletons with
		-- no dispose seam (they allocate a fixed set of registry entries once),
		-- so the baseline is taken AFTER the harness exists — exactly as
		-- tests/table.spec.luau does. This isolates the CONTROL's neutrality:
		-- build + mount + open/select/open/cancel churn + dismiss + dispose.
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local value = core:signal("normal")
		local control = popup_button.build(LuauUI, core, {
			id = "Difficulty",
			options = OPTIONS,
			value = value,
			onChange = function() end,
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { control.blueprint } })
		local handle = pres.present(screen, {
			sinkNavigation = true,
			onActivate = function(path, meta)
				control.api.handleActivate(path, meta)
			end,
		})
		pres.refresh()
		-- exercise: open, select, open, cancel
		adapter.tap(TRIGGER)
		pres.refresh()
		adapter.tap(optPath("hard"))
		pres.refresh()
		adapter.tap(TRIGGER)
		pres.refresh()
		adapter.tap(CANCEL)
		pres.refresh()
		pres.dismiss(handle)
		control.dispose()
		value:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)

describe("PopupButton: build-time contract", function()
	it("option ids must be path-safe (a '/' would corrupt path routing)", function()
		local core = LuauUI.newCore()
		local ok = pcall(function()
			popup_button.build(LuauUI, core, {
				id = "Bad",
				options = { { id = "a/b", label = "Nope" } },
				value = core:signal("a/b"),
			})
		end)
		expect(ok).toBe(false)
	end)

	-- CTRL-01 (api-architecture-consistency F-1). A read-only Memo has kind
	-- "memo" and a `:set` that asserts, so accepting one here deferred the crash
	-- to the user's FIRST selection (`select()` calls `spec.value:set`). Every
	-- sibling — Stepper, Slider, Rating, Picker, DisclosureGroup, TextInput —
	-- rejects exactly this at BUILD.
	it("rejects a read-only Memo `value` at BUILD, naming the control and the field", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			popup_button.build(LuauUI, core, {
				id = "Difficulty",
				options = OPTIONS,
				value = core:memo(function()
					return "normal"
				end),
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "PopupButton", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "value", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
	end)

	it("rejects a non-signal `value` at BUILD", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			popup_button.build(LuauUI, core, { id = "Difficulty", options = OPTIONS, value = "normal" :: any })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "SETTABLE Signal", 1, true) ~= nil).toBe(true)
	end)
end)
