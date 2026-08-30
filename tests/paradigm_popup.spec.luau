--!strict
-- PopupButton dismissal parity (input-paradigms expansion, UI-PARADIGM-001;
-- matrix §B PopupButton "outside-tap-dismiss GAP" + "ButtonB-closes GAP").
--
-- WHAT THIS CLOSES. An OPEN PopupButton is a `UI.When` on an `open` signal inside
-- a PLAIN present() screen — it never engaged the modal machinery, so it had three
-- parity GAPs (matrix §B PopupButton). Three OPTIONAL input-contribution fields
-- (src/input/contribution.luau) close them WITHOUT making the control a modal, and
-- the presenter (src/present/presenter.luau) adopts them:
--
--  1. OUTSIDE-TAP dismiss (`outsideDismiss`). While the popup is open the presenter
--     synthesizes a transparent within-screen catcher beneath the base screen
--     (Zone-A geometry over the contribution's own solved rects, the responder
--     two-zone model), and a tap on a rendered node OUTSIDE the contribution's
--     subtree dismisses it (onNodeTap path test). Non-destructive: selection is
--     never touched. A real modal above the screen suppresses the catcher.
--  2. CANCEL (gamepad ButtonB) close (`handleCancel`). Cancel is offered to the
--     focused/longest-prefix contribution BEFORE the presenter's modal-dismiss /
--     passive-resign / no-op branches; an open popup consumes it and closes.
--  3. FOCUS trap + restore (`transientScope`). While open, focus is trapped in the
--     control's subtree via the focus graph's own trap/restore machinery (Navigate
--     cannot escape into a sibling); on close focus restores to the pre-open focus
--     — the trigger — from ANY close path (row-focused close, Cancel row, ButtonB,
--     outside-tap). rootPath defaults to the control root, so the trigger is the
--     scope entry and focus never jumps into the open rows on open.
--
-- Everything below drives the REAL paths (adapter.tap / system.deviceKey), never
-- callbacks directly.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local popup_button = require("../src/controls/popup_button")
local fake_target = require("../tests/lib/fake_target")

local OPTIONS = {
	{ id = "easy", label = "Easy" },
	{ id = "normal", label = "Normal" },
	{ id = "hard", label = "Hard" },
}

-- headless world: the PopupButton plus a sibling Button AFTER it, so a real
-- rendered focusable exists OUTSIDE the control's subtree — the realistic
-- multi-focusable screen the gaps only surface on (a lone control masks them:
-- the trigger is then the sole ring survivor).
local function world()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local changes: { string } = {}
	local value = core:signal("normal")
	local control = popup_button.build(Facet, core, {
		id = "Difficulty",
		options = OPTIONS,
		value = value,
		onChange = function(id: string)
			table.insert(changes, id)
		end,
	})
	local sibling = Facet.UI.Button({
		id = "Outside",
		label = "Outside",
		width = { type = "fixed", px = 80 },
		height = { type = "fixed", px = 40 },
	})
	local screen = Facet.UI.Screen({ id = "S", children = { control.blueprint, sibling } })
	pres.present(screen, { sinkNavigation = true })
	pres.refresh()
	return {
		core = core,
		adapter = adapter,
		pres = pres,
		control = control,
		value = value,
		changes = changes,
		system = system,
	}
end

local TRIGGER = "/S/Difficulty/Trigger"
local OUTSIDE = "/S/Outside"
local CANCEL = "/S/Difficulty/PopupWhen/then/Popup/Cancel"
local function optPath(id: string): string
	return `/S/Difficulty/PopupWhen/then/Popup/Opt-{id}`
end

-- ===========================================================================
-- 1. OUTSIDE-TAP DISMISS (outsideDismiss seam)
-- ===========================================================================
describe("PopupButton parity: outside-tap dismiss", function()
	it("a tap on a rendered node OUTSIDE the open panel dismisses it (no selection change)", function()
		local w = world()
		w.adapter.tap(TRIGGER) -- open
		w.pres.refresh()
		expect(w.control.dump().open).toBe(true)
		w.adapter.tap(OUTSIDE) -- a tap outside the control's subtree
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false) -- dismissed
		expect(w.value:get()).toBe("normal") -- selection genuinely untouched
		expect(w.pres.focus.focused:get()).toBe(TRIGGER) -- focus restored to the trigger
	end)

	it("the synthesized catcher dismisses on a tap in EMPTY space (Zone B geometry)", function()
		local w = world()
		w.adapter.tap(TRIGGER) -- open
		w.pres.refresh()
		local catcher = w.pres.topPopupCatcherPath()
		expect(catcher).never().toBeNil() -- a catcher is mounted beneath the screen
		-- (700,550) is far below the popup panel — Zone B (outside the painted rects)
		w.adapter.tap(catcher :: string, { x = 700, y = 550 })
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.value:get()).toBe("normal")
	end)

	it("a tap on the trigger itself (inside the subtree) toggles closed, never routes to dismiss", function()
		local w = world()
		w.adapter.tap(TRIGGER) -- open
		w.pres.refresh()
		w.adapter.tap(TRIGGER) -- re-tap: inside the subtree -> toggle, not outside-dismiss
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.value:get()).toBe("normal")
	end)
end)

-- ===========================================================================
-- 2. GAMEPAD ButtonB CANCEL (Bundle.handleCancel seam)
-- ===========================================================================
describe("PopupButton parity: gamepad Cancel", function()
	it("gamepad ButtonB while open closes the popup (no selection change)", function()
		local w = world()
		w.system.deviceKey("ButtonA", true) -- open via trigger Activate
		w.system.deviceKey("ButtonA", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(true)
		w.system.deviceKey("ButtonB", true) -- Cancel
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false) -- closed
		expect(w.value:get()).toBe("normal") -- selection genuinely untouched
		expect(w.pres.focus.focused:get()).toBe(TRIGGER) -- focus restored to the trigger
	end)

	it("gamepad ButtonB with the popup CLOSED does not consume Cancel (falls through)", function()
		-- handleCancel returns false when there is nothing to cancel, so a plain
		-- base screen behaves exactly as before (no-op Cancel, focus unmoved).
		local w = world()
		expect(w.control.dump().open).toBe(false)
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)
end)

-- ===========================================================================
-- 3. FOCUS TRAP while open (transientScope seam)
-- ===========================================================================
describe("PopupButton parity: focus is trapped while open", function()
	it("REGRESSION: closing always lands focus on a LIVE focusable (never nil/dangling)", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		w.system.deviceKey("Down", true) -- focus first option
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("easy"))
		w.control.api.close()
		w.pres.refresh()
		local landed = w.pres.focus.focused:get()
		expect(landed ~= nil).toBe(true)
		expect(landed == TRIGGER or landed == OUTSIDE).toBe(true) -- a live node, options gone
		expect(w.adapter.node(optPath("easy"))).toBe(nil) -- the popup really closed
	end)

	it("REGRESSION: re-activating the trigger to close keeps focus on the trigger", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open; focus stays on trigger
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
		w.system.deviceKey("Return", true) -- re-activate closes
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER) -- focus never left the trigger
	end)

	it("gamepad Navigate cannot ESCAPE the open popup into a sibling (focus trap)", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		for _ = 1, 4 do -- Trigger -> easy -> normal -> hard -> Cancel
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
		end
		expect(w.pres.focus.focused:get()).toBe(CANCEL)
		w.system.deviceKey("Down", true) -- one more Down at the end of the ring
		w.system.deviceKey("Down", false)
		-- TRAPPED: the flat ring wraps back to the control's own trigger — it NEVER
		-- leaks out to the sibling OUTSIDE, and the popup stays open.
		local landed = w.pres.focus.focused:get() :: string
		expect(landed).never().toBe(OUTSIDE)
		expect(string.sub(landed, 1, #"/S/Difficulty")).toBe("/S/Difficulty") -- still inside
		expect(landed).toBe(TRIGGER) -- specifically: wrapped to the trigger
		expect(w.control.dump().open).toBe(true)
	end)
end)

-- ===========================================================================
-- 4. CLOSE RESTORES FOCUS TO THE TRIGGER from any close path
-- ===========================================================================
describe("PopupButton parity: close restores focus to the trigger from any path", function()
	it("row-focused close (api.close) restores focus to the trigger", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		w.system.deviceKey("Down", true) -- focus a row
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("easy"))
		w.control.api.close()
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)

	it("Cancel-row Activate closes without selecting and restores focus to the trigger", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		for _ = 1, 4 do -- navigate down onto the Cancel row
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
		end
		expect(w.pres.focus.focused:get()).toBe(CANCEL)
		w.system.deviceKey("Return", true) -- Cancel closes without selecting
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.value:get()).toBe("normal") -- non-destructive close
		expect(w.pres.focus.focused:get()).toBe(TRIGGER) -- restored to the invoker
	end)

	it("gamepad ButtonB close restores focus to the trigger from a focused row", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		w.system.deviceKey("Down", true) -- focus a row
		w.system.deviceKey("Down", false)
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("normal"))
		w.system.deviceKey("ButtonB", true) -- Cancel closes
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)

	it("outside-tap close restores focus to the trigger from a focused row", function()
		local w = world()
		w.system.deviceKey("Return", true) -- open
		w.system.deviceKey("Return", false)
		w.pres.refresh()
		w.system.deviceKey("Down", true) -- focus a row
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(optPath("easy"))
		w.adapter.tap(OUTSIDE) -- outside-tap dismiss
		w.pres.refresh()
		expect(w.control.dump().open).toBe(false)
		expect(w.pres.focus.focused:get()).toBe(TRIGGER)
	end)
end)

-- ===========================================================================
-- Verifier finding RT-F1 (reactive-runtime review, 2026-07-21): dismissing the
-- base screen while the popup is still OPEN must be registry-neutral — the
-- synthesized catcher and the transient trap scope go down with the handle.
-- ===========================================================================
describe("PopupButton parity: dismiss-while-open is registry-neutral", function()
	it("open popup -> pres.dismiss + dispose returns every core counter to baseline", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local value = core:signal("normal")
		local control = popup_button.build(Facet, core, {
			id = "Difficulty",
			options = OPTIONS,
			value = value,
			onChange = function() end,
		})
		local screen = Facet.UI.Screen({ id = "S", children = { control.blueprint } })
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		adapter.tap("/S/Difficulty/Trigger")
		pres.refresh() -- popup OPEN: catcher synthesized, trap scope pushed
		pres.dismiss(handle) -- dismiss with the popup STILL open
		control.dispose()
		value:dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)
