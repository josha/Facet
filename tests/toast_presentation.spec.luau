--!strict
-- TOAST PRESENTATION (ADR-0022 Decision 4; acceptance rows SF-T1, SF-T3). The
-- scheduler's rules are proven in `toast_schedule.spec`; this file proves the
-- SURFACE — and every assertion here is about something a toast must NOT do:
--
--   * it must not take input. A control beneath a toast still activates, because
--     the toast layer is presenter-private: not in the stack, no input context,
--     no tap handler, nothing to intercept with.
--   * it must not touch focus. The focus graph reads identically before, during
--     and after — same focused path, same scope depth, same navigation ring.
--   * it must not out-stack a modal, and must out-stack the base screen.
--   * under reduced motion it must show the SAME toasts for the SAME time. Only
--     the pixels change; the information does not (SF-T3).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

local function world(reduced: boolean?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	if reduced then
		env:set("reducedMotion", true)
	end
	local adapter = fake_target.new()
	local system = actionsLib.newSystem(core)
	local pres = presenterLib.new(core, env, adapter, system)
	return core, env, adapter, system, pres
end

local function baseScreen()
	return UI.Screen({
		id = "Base",
		children = {
			UI.Button({ id = "Play", label = "Play" }),
			UI.Button({ id = "Quit", label = "Quit" }),
		},
	})
end

local function toastBody(text: string)
	return UI.VStack({ id = "Body", children = { UI.Text({ id = "Line", text = text }) } })
end

local function toastPaths(adapter: any): { string }
	local out: { string } = {}
	for _, path in adapter.paths() do
		if string.find(path, "/__toast__/", 1, true) ~= nil then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

local function visibleTexts(adapter: any): { string }
	local out: { string } = {}
	for _, path in toastPaths(adapter) do
		local node = adapter.node(path)
		if node ~= nil and node.class == "Text" then
			table.insert(out, tostring(node.props.text))
		end
	end
	table.sort(out)
	return out
end

describe("toast presentation: the layer is input-transparent", function()
	it("a control beneath a live toast still activates", function()
		local _, _, adapter, _, pres = world()
		local activated: { string } = {}
		pres.present(baseScreen(), {
			onActivate = function(path: string?)
				table.insert(activated, tostring(path))
			end,
		})
		pres.presentToast(toastBody("Lap 2"))
		pres.tick(FRAME)
		expect(#visibleTexts(adapter)).toBe(1)
		adapter.tap("/Base/Play")
		expect(activated[1]).toBe("/Base/Play")
	end)

	it("the toast layer is not a presented surface: it never joins the stack", function()
		local _, _, _, _, pres = world()
		pres.present(baseScreen())
		expect(pres.depth()).toBe(1)
		pres.presentToast(toastBody("hi"))
		expect(pres.depth()).toBe(1)
		expect(pres.toastCounts().visible).toBe(1)
	end)

	it("focus is untouched before, during and after", function()
		local _, _, _, system, pres = world()
		pres.present(baseScreen())
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		local before = pres.focus.focused:get()
		local scopeBefore = pres.focus.activeScopeName()

		local handle = pres.presentToast(toastBody("Lap 2"), { duration = 1, readFloor = 0 })
		pres.tick(FRAME)
		expect(pres.focus.focused:get()).toBe(before)
		-- and navigation still moves within the BASE screen's ring only
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		local moved = pres.focus.focused:get()
		expect(string.find(tostring(moved), "__toast__", 1, true)).toBeNil()

		handle.dismiss()
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(string.find(tostring(pres.focus.focused:get()), "__toast__", 1, true)).toBeNil()
		-- the scope stack is exactly what it was: a toast pushes nothing
		expect(pres.focus.activeScopeName()).toBe(scopeBefore)
	end)

	it("no toast node is focusable, so no navigation can ever reach one", function()
		local _, _, adapter, _, pres = world()
		pres.present(baseScreen())
		pres.presentToast(toastBody("Lap 2"))
		pres.tick(FRAME)
		local seen = 0
		for _, path in toastPaths(adapter) do
			local node = adapter.node(path)
			seen += 1
			expect(node.class ~= "Button" and node.class ~= "Toggle" and node.class ~= "TextField").toBe(true)
		end
		expect(seen > 0).toBe(true)
	end)
end)

describe("toast presentation: stacking", function()
	it("the toast layer sits above every base screen and below every modal", function()
		local _, _, adapter, _, pres = world()
		local base = pres.present(baseScreen())
		pres.presentToast(toastBody("hi"))
		pres.tick(FRAME)
		local modal = pres.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
		local toastOrder = adapter.rootDisplayOrder("__toast__")
		expect(toastOrder ~= nil).toBe(true)
		expect(base.displayOrder < (toastOrder :: number)).toBe(true)
		expect((toastOrder :: number) < modal.displayOrder).toBe(true)
		expect(presenterLib.SURFACE_LAYER.toast < presenterLib.SURFACE_LAYER.dragProxy).toBe(true)
		expect(presenterLib.SURFACE_LAYER.dragProxy < presenterLib.SURFACE_LAYER.modal).toBe(true)
	end)

	it("a bottom-docked strip grows UPWARD from the safe-area inset (review R2-F10)", function()
		-- the edge nothing exercised: `position = "bottom"` was only ever proven by
		-- its enter direction. What a player sees is the GEOMETRY — the strip pinned
		-- clear of the home indicator, each new message taking the edge and pushing
		-- its predecessor up rather than the stack marching off-screen.
		local _, env, adapter, _, pres = world()
		env:set("coreSafeInsets", { top = 0, bottom = 34, left = 0, right = 0 })
		pres.present(baseScreen())
		pres.presentToast(toastBody("first"), { position = "bottom", duration = 20, readFloor = 0 })
		for _ = 1, 30 do
			pres.tick(FRAME)
		end
		local aloneY = adapter.node("/__toast__/Items/[1]/Toast").rect.y
		pres.presentToast(toastBody("second"), { position = "bottom", duration = 20, readFloor = 0 })
		for _ = 1, 30 do
			pres.tick(FRAME)
		end
		local first = adapter.node("/__toast__/Items/[1]/Toast").rect
		local second = adapter.node("/__toast__/Items/[2]/Toast").rect
		-- the newest sits at the edge, the older one moved UP to make room
		expect(first.y < aloneY).toBe(true)
		expect(second.y > first.y).toBe(true)
		-- ...and the strip stops at the inset, never under the home indicator
		local viewport: any = env:get("viewportRect"):get()
		expect(second.y + second.h <= viewport.h - 34).toBe(true)
	end)

	it("a base screen presented AFTER a modal still sits below it (bands, not a counter)", function()
		local _, _, _, _, pres = world()
		local modal = pres.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
		local late = pres.present(baseScreen())
		expect(late.displayOrder < modal.displayOrder).toBe(true)
	end)

	-- REDTEAM FIX (item 3, MAJOR; final-review-findings.md). `displayLayer`
	-- (the +100-per-present band-offset counter behind `late.displayOrder`
	-- above) used to only ever count UP — a long-lived session cycling
	-- present/dismiss never got it back down, so 100 cycles alone push a
	-- FUTURE base screen's own displayOrder past the toast band, and 300
	-- cycles push it past the modal band too — silently reordering surfaces
	-- that were never even touched. Strengthened from the header-comment-only
	-- pin above into an actual 400-cycle proof: `self.dismiss` now resets
	-- `displayLayer` to 0 the instant the surface stack goes empty (nothing
	-- presented depends on the counter's value at that point), so a fresh
	-- present after any number of prior cycles starts from the SAME band
	-- floor a first-ever present would.
	it("400 present/dismiss cycles never push a base screen's displayOrder out of its band", function()
		local _, _, _, _, pres = world()
		for _ = 1, 400 do
			local h = pres.present(baseScreen())
			pres.dismiss(h)
		end
		local final = pres.present(baseScreen())
		expect(final.displayOrder >= presenterLib.SURFACE_LAYER.base).toBe(true)
		expect(final.displayOrder < presenterLib.SURFACE_LAYER.toast).toBe(true)
	end)

	-- the modal band survives the identical cycling, and — belt — a fresh
	-- present right after the 400-cycle sweep lands at the SAME displayOrder
	-- a first-ever present would (the counter genuinely reset, not merely
	-- "still under the next band up" by coincidence of the band width).
	it(
		"400 present/dismiss cycles leave the NEXT present's displayOrder identical to a first-ever present's",
		function()
			local _, _, _, _, presA = world()
			local first = presA.present(baseScreen())

			local _, _, _, _, presB = world()
			for _ = 1, 400 do
				local h = presB.present(baseScreen())
				presB.dismiss(h)
			end
			local afterCycling = presB.present(baseScreen())

			expect(afterCycling.displayOrder).toBe(first.displayOrder)
			local modalAfterCycling =
				presB.presentModal(UI.Screen({ id = "M", children = { UI.Button({ id = "Y", label = "y" }) } }))
			expect(modalAfterCycling.displayOrder >= presenterLib.SURFACE_LAYER.modal).toBe(true)
			expect(modalAfterCycling.displayOrder < presenterLib.SURFACE_LAYER.modal + 30000).toBe(true) -- still comfortably inside the modal band, not pushed out by dragProxy's own headroom
		end
	)
end)

describe("toast presentation: the layer's lifetime", function()
	it("the layer appears with the first toast and retires once the last one has left", function()
		local _, _, adapter, _, pres = world()
		pres.present(baseScreen())
		expect(adapter.node("/__toast__")).toBeNil()
		pres.presentToast(toastBody("Lap 2"), { duration = 1, readFloor = 0 })
		pres.tick(FRAME)
		expect(adapter.node("/__toast__") ~= nil).toBe(true)
		-- run out the duration AND the exit transition
		for _ = 1, 200 do
			pres.tick(FRAME)
		end
		expect(pres.toastCounts().visible).toBe(0)
		-- the whole surface is gone: no instances, no controller, no scope
		expect(adapter.node("/__toast__")).toBeNil()
		expect(#toastPaths(adapter)).toBe(0)
	end)

	it("a toast retires itself on schedule and says why", function()
		local _, _, _, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			if event.type == "dismiss" then
				table.insert(events, event)
			end
		end)
		pres.present(baseScreen())
		pres.presentToast(toastBody("Lap 2"), { duration = 2, readFloor = 0 })
		for _ = 1, 60 do
			pres.tick(FRAME)
		end
		expect(#events).toBe(0)
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(events[1].type).toBe("dismiss")
		expect(events[1].reason).toBe("timeout")
	end)

	it("an explicit dismiss retires it early with reason `manual`", function()
		local _, _, _, _, pres = world()
		local events: { any } = {}
		pres.onFeedback(function(event)
			if event.type == "dismiss" then
				table.insert(events, event)
			end
		end)
		pres.present(baseScreen())
		local handle = pres.presentToast(toastBody("Lap 2"), { context = { subject = "lap" } })
		expect(handle.dismiss()).toBe(true)
		expect(events[1].reason).toBe("manual")
		expect(events[1].context.context.subject).toBe("lap")
	end)

	it("churning toasts through mount and retire returns the core to baseline", function()
		local core, _, _, _, pres = world()
		pres.present(baseScreen())
		local baseline = core:counters()
		for i = 1, 20 do
			local handle = pres.presentToast(toastBody(`t{i}`), { duration = 0.2, readFloor = 0 })
			pres.tick(FRAME)
			handle.dismiss()
			for _ = 1, 60 do
				pres.tick(FRAME)
			end
		end
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(value)
		end
	end)
end)

describe("toast presentation: reduced motion keeps the whole information surface", function()
	it("the same toasts appear for the same time; only the transition is instant", function()
		local function runAxis(reduced: boolean): { visibleAt: { number }, dismissals: number }
			local _, _, adapter, _, pres = world(reduced)
			local dismissals = 0
			pres.onFeedback(function(event)
				if event.type == "dismiss" then
					dismissals += 1
				end
			end)
			pres.present(baseScreen())
			for i = 1, 5 do
				pres.presentToast(toastBody(`t{i}`), { duration = 1, readFloor = 0 })
			end
			local visibleAt: { number } = {}
			for frame = 1, 200 do
				pres.tick(FRAME)
				if frame % 20 == 0 then
					table.insert(visibleAt, pres.toastCounts().visible)
				end
			end
			expect(adapter ~= nil).toBe(true)
			return { visibleAt = visibleAt, dismissals = dismissals }
		end
		local full = runAxis(false)
		local reduced = runAxis(true)
		expect(table.concat(reduced.visibleAt, ",")).toBe(table.concat(full.visibleAt, ","))
		expect(reduced.dismissals).toBe(full.dismissals)
		expect(reduced.dismissals).toBe(5) -- every queued toast was shown, none dropped
	end)

	it("under reduced motion a toast is fully painted on its first frame", function()
		local _, _, adapter, _, pres = world(true)
		pres.present(baseScreen())
		pres.presentToast(toastBody("Lap 2"))
		pres.tick(FRAME)
		local group = adapter.node("/__toast__/Items/[1]/Toast")
		expect(group ~= nil).toBe(true)
		expect(group.canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("with motion the same toast starts displaced and transparent, then settles", function()
		local _, _, adapter, _, pres = world(false)
		pres.present(baseScreen())
		pres.presentToast(toastBody("Lap 2"))
		local group = adapter.node("/__toast__/Items/[1]/Toast")
		expect(group.canvasGroupInstance.groupTransparency).toBe(1)
		expect(group.props.transform.y).toBe(-24) -- docked at the top: it comes DOWN
		for _ = 1, 90 do
			pres.tick(FRAME)
		end
		expect(adapter.node("/__toast__/Items/[1]/Toast").canvasGroupInstance.groupTransparency).toBe(0)
	end)

	it("a bottom-docked toast comes up from its own edge instead", function()
		local _, _, adapter, _, pres = world(false)
		pres.present(baseScreen())
		pres.presentToast(toastBody("Lap 2"), { position = "bottom" })
		expect(adapter.node("/__toast__/Items/[1]/Toast").props.transform.y).toBe(24)
	end)
end)
