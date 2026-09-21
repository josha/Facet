--!strict
local harness = require("./lib/harness")
-- The UNIFIED COLLECTION (rows SF-L1/L2/L3): one
-- VirtualList that windows, selects, reorders, accepts drops and edge-scrolls at
-- the same time. Reorder and drop ride the PUBLIC drag contract, so every case
-- below drives the real acquisition path and asserts what the game's callbacks
-- were handed — never a private helper.
--
-- The churn cases are the point of the row: a 250 ms re-sort in the middle of a
-- drag must not remount rows, reset selection, move focus or stale the verdict.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

-- a reorderable / droppable VirtualList presented with ZERO opts
local function world(opts: any?)
	local options = opts or {}
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new({ ops = true })
	local pres = harness.newPresenter(core, env, adapter, system)

	local rows = Compose.cell(makeRows(options.count or 40))
	local reorders: { any } = {}
	local drops: { any } = {}
	local selections: { any } = {}
	local events: { any } = {}

	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = options.rowHeight or 40,
		viewportHeight = options.viewportHeight or 400,
		overscan = options.overscan or 2,
		selection = options.selection,
		selectionPaint = options.selectionPaint,
		onSelect = function(item: any, key: string)
			table.insert(selections, key)
			local _ = item
		end,
		reorderable = options.reorderable,
		onReorder = if options.reorderable
			then function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
				-- APPLY the requested move, like an owner would: order is owner
				-- state, and the list renders what it is handed
				local current = rows:peek() :: { any }
				local next: { any } = {}
				local moved: any = nil
				for _, item in current do
					if item.id == key then
						moved = item
					else
						table.insert(next, item)
					end
				end
				table.insert(next, math.clamp(toIndex, 1, #next + 1), moved)
				rows:set(next)
			end
			else nil,
		dropSurface = options.dropSurface,
		rowDropTarget = options.rowDropTarget,
		rowFocusable = options.rowFocusable,
		autoscroll = options.autoscroll,
		motionClock = options.motionClock,
		reorderMotion = options.reorderMotion,
		cell = function(item: any)
			return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = options.onActivate,
	})
	local screen = harness.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)
	handle.controller.setDragCollaborators({
		feedback = {
			emit = function(event: string, info: any)
				table.insert(events, { event = event, info = info })
			end,
		},
	})

	local w: any = {
		core = core,
		env = env,
		system = system,
		adapter = adapter,
		pres = pres,
		list = list,
		rows = rows,
		reorders = reorders,
		drops = drops,
		selections = selections,
		events = events,
		handle = handle,
		unbindScroll = unbindScroll,
	}
	function w.registry(): any
		return handle.controller.dragRegistry()
	end
	function w.hitPath(key: string): string
		return `/S/VL/Canvas/W/[{key}]/Row/Hit`
	end
	function w.rowY(key: string): number
		local r = handle.controller.rectOf(w.hitPath(key))
		assert(r ~= nil, `row {key} is not mounted`)
		return r.y + r.h / 2
	end
	function w.hostRect()
		return handle.controller.rectOf("/S/VL")
	end
	function w.lift(key: string)
		local y = w.rowY(key)
		adapter.driveDragStart(w.hitPath(key), { x = 100, y = y, pointerType = "mouse" })
		adapter.driveDragContinue(w.hitPath(key), { x = 100, y = y + 10, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	function w.moveTo(key: string, y: number)
		adapter.driveDragContinue(w.hitPath(key), { x = 100, y = y, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	function w.release(key: string, y: number)
		adapter.driveDragEnd(w.hitPath(key), { x = 100, y = y, pointerType = "mouse" })
	end
	function w.order(): { string }
		local out: { string } = {}
		for _, item in rows:peek() :: { any } do
			table.insert(out, item.id)
		end
		return out
	end
	function w.eventNames(): { string }
		local out: { string } = {}
		for _, entry in events do
			table.insert(out, entry.event)
		end
		return out
	end
	return w
end

describe("unified collection: selection (SF-L1)", function()
	it('selection defaults to "none": activation never selects', function()
		local w = world()
		w.adapter.tap(w.hitPath("r3"))
		expect(w.list.selectedKey:peek()).toBe(nil)
		expect(w.list.dump().selection).toBe("none")
	end)

	it("single selection: an Activate from ANY paradigm selects the row", function()
		local w = world({ selection = "single" })
		w.adapter.tap(w.hitPath("r3")) -- pointer
		expect(w.list.selectedKey:peek()).toBe("r3")
		-- ...then walk the graph focus down two rows and press ButtonA
		for _ = 1, 2 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		w.system.deviceKey("ButtonA", true) -- gamepad
		w.system.deviceKey("ButtonA", false)
		expect(w.list.selectedKey:peek()).toBe("r5")
		expect(w.selections).toEqual({ "r3", "r5" })
	end)

	it("selection PRUNES with the data: a removed row is never a phantom selection", function()
		local w = world({ selection = "single" })
		w.list.select("r3")
		expect(w.list.selectedKey:peek()).toBe("r3")
		local next = {}
		for _, item in w.rows:peek() :: { any } do
			if item.id ~= "r3" then
				table.insert(next, item)
			end
		end
		w.rows:set(next)
		expect(w.list.selectedKey:peek()).toBe(nil)
	end)

	it("selection survives a re-sort that keeps the row", function()
		local w = world({ selection = "single" })
		w.list.select("r5")
		local reversed = {}
		local items = w.rows:peek() :: { any }
		for i = #items, 1, -1 do
			table.insert(reversed, items[i])
		end
		w.rows:set(reversed)
		w.pres.refresh()
		expect(w.list.selectedKey:peek()).toBe("r5")
	end)

	it("clearSelection empties it", function()
		local w = world({ selection = "single" })
		w.list.select("r2")
		w.list.clearSelection()
		expect(w.list.selectedKey:peek()).toBe(nil)
	end)

	it("the SELECTED row declares the native state, so the theme paints it (R2-F6)", function()
		-- the list owns selection, so the list is what says the row is selected —
		-- `selected` rides a style tag (`controlSelected`), which is why a cell never
		-- has to spend an ELEVATION role saying "chosen". Table parity.
		local w = world({ selection = "single" })
		w.list.select("r3")
		w.pres.refresh()
		expect(w.adapter.node(w.hitPath("r3")).props.selected).toBe(true)
		expect(w.adapter.node(w.hitPath("r4")).props.selected).toBe(false)
		-- ...and it MOVES with the selection rather than latching
		w.list.select("r4")
		w.pres.refresh()
		expect(w.adapter.node(w.hitPath("r3")).props.selected).toBe(false)
		expect(w.adapter.node(w.hitPath("r4")).props.selected).toBe(true)
	end)

	it("selectionPaint='none' keeps the SELECTION and drops only the PAINT", function()
		--[[ Some lists carry "which one is chosen" in a channel that is not the row.
			Rascal Rally's sponsor standings is the case that asked for this: the
			selected racer is the one the CAMERA is watching, and the director ruled
			(2026-08-03) that the watched row must paint nothing — "byte-identical to
			its siblings". The list still owns the selection (it is what `onSelect`
			reports and what activation moves), so `selection = "none"` is the wrong
			instrument: it would silently delete the selection itself.

			So the state and its paint are separated. Everything below is the SAME as
			the case above except the one declaration. ]]
		local w = world({ selection = "single", selectionPaint = "none" })
		w.list.select("r3")
		w.pres.refresh()
		-- the selection is REAL...
		expect(w.list.selectedKey:peek()).toBe("r3")
		-- ...and no row declares the native state, so no theme can paint one
		expect(w.adapter.node(w.hitPath("r3")).props.selected).toBeNil()
		expect(w.adapter.node(w.hitPath("r4")).props.selected).toBeNil()
		-- and selecting elsewhere still moves it, silently
		w.list.select("r4")
		w.pres.refresh()
		expect(w.list.selectedKey:peek()).toBe("r4")
		expect(w.adapter.node(w.hitPath("r4")).props.selected).toBeNil()
	end)

	it("selectionPaint refuses an unknown value (constitution §4)", function()
		expect(function()
			world({ selection = "single", selectionPaint = "subtle" })
		end).toThrow()
	end)

	it("a list with selection OFF declares nothing: those rows are unchanged", function()
		local w = world()
		w.adapter.tap(w.hitPath("r3"))
		w.pres.refresh()
		expect(w.adapter.node(w.hitPath("r3")).props.selected).toBeNil()
	end)
end)

describe("unified collection: pointer reorder over the public contract (SF-L1)", function()
	it("a row lifts past the promotion token and reorders on release", function()
		local w = world({ reorderable = true })
		expect(w.order()[1]).toBe("r1")
		w.lift("r1")
		expect(w.registry().isActive()).toBe(true)
		expect(w.registry().payload().key).toBe("r1")
		-- drop below r4's midpoint: the insertion line sits under row 4
		w.moveTo("r1", w.rowY("r4") + 5)
		w.release("r1", w.rowY("r4") + 5)
		expect(#w.reorders).toBe(1)
		expect(w.reorders[1].key).toBe("r1")
		expect(w.reorders[1].toIndex).toBe(4)
		expect(w.order()[4]).toBe("r1")
	end)

	it("a drop that reproduces the current order emits NOTHING", function()
		local w = world({ reorderable = true })
		w.lift("r3")
		w.moveTo("r3", w.rowY("r3"))
		w.release("r3", w.rowY("r3"))
		expect(#w.reorders).toBe(0)
	end)

	it("an upward move lands above the row it was dropped on", function()
		local w = world({ reorderable = true })
		w.lift("r5")
		local target = w.rowY("r2") - 15 -- the top half of row 2
		w.moveTo("r5", target)
		w.release("r5", target)
		expect(w.reorders[1].toIndex).toBe(2)
		expect(w.order()[2]).toBe("r5")
	end)

	it("the drop line tracks the insertion point through the PRESENTATION channel", function()
		local w = world({ reorderable = true })
		local before = #w.adapter.takeOps()
		w.lift("r1")
		w.moveTo("r1", w.rowY("r4") + 5)
		expect(w.list.dropIndex:peek()).toBe(4)
		local ops = w.adapter.takeOps()
		local sawTransform = false
		for _, op in ops do
			if string.find(op, "/S/VL/Canvas/DropLine", 1, true) ~= nil then
				sawTransform = true
			end
		end
		expect(sawTransform).toBe(true)
		expect(before >= 0).toBe(true)
		-- and it is parked again on the terminal
		w.release("r1", w.rowY("r4") + 5)
		expect(w.list.dropIndex:peek()).toBe(nil)
	end)

	it("touch DECLINES the row body so the native pan keeps scrolling", function()
		local w = world({ reorderable = true })
		local declined = w.registry().pointerDown(w.hitPath("r1"), { x = 100, y = 100, pointerType = "touch" })
		expect(declined).toBe(false)
		expect(w.registry().isActive()).toBe(false)
	end)

	it("a plain (non-reorderable) list declares no drag sources at all", function()
		local w = world()
		expect(type(w.handle.controller.dragRegistry)).toBe("function")
		expect(#w.handle.controller.dragRegistry().dump().sources).toBe(0)
	end)
end)

describe("unified collection: the armed (non-pointer) reorder (SF-D4)", function()
	it("Activate arms, Navigate moves the predicted slot, Activate commits", function()
		local w = world({ reorderable = true })
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.list.armedKey:peek()).toBe("r1")
		expect(w.registry().mode()).toBe("armed")
		-- three Navigates move the predicted target, NOT focus
		for _ = 1, 3 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		expect(w.list.dropIndex:peek()).toBe(4)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.reorders[1]).toEqual({ key = "r1", toIndex = 4 })
		expect(w.list.armedKey:peek()).toBe(nil)
		expect(w.order()[4]).toBe("r1")
	end)

	it("Cancel disarms without reordering", function()
		local w = world({ reorderable = true })
		w.list.focusKey("r2")
		expect(w.list.toggleGrab()).toBe(true)
		expect(w.list.armedKey:peek()).toBe("r2")
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		expect(w.list.armedKey:peek()).toBe(nil)
		expect(#w.reorders).toBe(0)
		expect(w.order()[2]).toBe("r2")
	end)

	it("toggleGrab is the dedicated verb: grab then commit, same session", function()
		local w = world({ reorderable = true })
		w.list.focusKey("r1")
		w.list.toggleGrab()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.list.toggleGrab() -- commit
		expect(w.reorders[1].toIndex).toBe(2)
	end)

	it("the armed navigation SCROLLS the list, so rows past the window are reachable", function()
		local w = world({ reorderable = true, count = 40 })
		w.list.focusKey("r1")
		w.list.toggleGrab()
		for _ = 1, 15 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
			w.pres.refresh()
		end
		expect(w.list.dropIndex:peek()).toBe(16)
		expect(w.list.debugWindow().r16).toBe(true) -- materialized by keep-visible
		w.list.toggleGrab()
		expect(w.reorders[1].toIndex).toBe(16)
	end)
end)

describe("unified collection: rows as drop targets (SF-L1)", function()
	it("a foreign payload lands on the row the game asked for", function()
		local landed: { any } = {}
		local w = world({
			dropSurface = true,
			rowDropTarget = function(item: any)
				return {
					accepts = function(payload: any)
						if payload == "poison" then
							return false, "POISONED"
						end
						return true
					end,
					onDrop = function(payload: any, info: any)
						table.insert(landed, { payload = payload, key = info.key, index = info.index })
					end,
				}
			end,
		})
		local registry = w.registry()
		-- an external source registered straight into the surface registry (the
		-- cross-container case: a card in a hand, dropped onto a list row)
		registry.registerSource("/S/VL", { payload = "card", dragMotion = "object", declineTouch = false })
		expect(registry.arm("/S/VL")).toBe(true)
		expect(registry.armTo(w.hitPath("r4"))).toBe(true)
		expect(registry.verdict:peek().legal).toBe(true)
		registry.commit()
		expect(#landed).toBe(1)
		expect(landed[1].key).toBe("r4")
		expect(landed[1].index).toBe(4)
	end)

	it("the game's refusal reason reaches the verdict and the reject event", function()
		local w = world({
			dropSurface = true,
			rowDropTarget = function()
				return {
					accepts = function()
						return false, "FULL"
					end,
					onDrop = function() end,
				}
			end,
		})
		local registry = w.registry()
		registry.registerSource("/S/VL", { payload = "card" })
		registry.arm("/S/VL")
		registry.armTo(w.hitPath("r2"))
		expect(registry.verdict:peek().legal).toBe(false)
		expect(registry.verdict:peek().reason).toBe("FULL")
		registry.commit()
		local reject: any = nil
		for _, entry in w.events do
			if entry.event == "reject" then
				reject = entry.info
			end
		end
		expect(reject.reason).toBe("FULL")
	end)

	it("a reorder payload from ANOTHER list is refused", function()
		local w = world({ reorderable = true })
		local registry = w.registry()
		registry.registerSource("/S/VL", { payload = { kind = "__facet_reorder", key = "x", list = "OtherList" } })
		registry.arm("/S/VL")
		registry.armTo(w.hitPath("r2"))
		expect(registry.verdict:peek().legal).toBe(false)
		expect(registry.verdict:peek().reason).toBe("FOREIGN_LIST")
	end)

	it("the hit-test is over VISIBLE rows only: an unmounted row is not a target", function()
		local w = world({ dropSurface = true })
		local registry = w.registry()
		expect(w.list.debugWindow().r30).toBe(nil) -- outside the window
		local targets = registry.dump().targets
		local found = false
		for _, path in targets do
			if string.find(path, "%[r30%]") ~= nil then
				found = true
			end
		end
		expect(found).toBe(false)
	end)
end)

describe("unified collection: edge autoscroll wired to the host (SF-L2)", function()
	it("dwelling at the bottom edge arms, scrolls, and re-resolves the verdict IN THE SAME frame", function()
		local w = world({ reorderable = true })
		local host = w.hostRect()
		local edgeY = host.y + host.h - 5 -- deep in the bottom band
		w.lift("r1")
		w.moveTo("r1", edgeY)
		-- dwell: nothing moves before 300 ms
		expect(w.list.stepAutoscroll(0).delta).toBe(0)
		expect(w.list.stepAutoscroll(0.2).delta).toBe(0)
		expect(w.list.scrollTop:peek()).toBe(0)
		local armed = w.list.stepAutoscroll(0.35)
		expect(armed.state).toBe("active")
		expect(armed.justArmed).toBe(true)
		local before = w.list.scrollTop:peek()
		w.list.stepAutoscroll(0.6)
		expect(w.list.scrollTop:peek() > before).toBe(true)
		-- the verdict now names a row further down the list, on the SAME frame as
		-- the scroll write — not one frame behind it
		expect(w.list.dropIndex:peek() ~= nil).toBe(true)
	end)

	it("short content is inert: a list with nothing to scroll never arms", function()
		local w = world({ reorderable = true, count = 4 }) -- 160 px of rows in a 400 px viewport
		local host = w.hostRect()
		w.lift("r1")
		w.moveTo("r1", host.y + host.h - 5)
		w.list.stepAutoscroll(0)
		expect(w.list.stepAutoscroll(1).state).toBe("idle")
		expect(w.list.scrollTop:peek()).toBe(0)
	end)

	it("a NON-pointer (armed) session never autoscrolls: focus-follow already does", function()
		local w = world({ reorderable = true })
		w.list.focusKey("r1")
		w.list.toggleGrab()
		w.list.stepAutoscroll(0)
		expect(w.list.stepAutoscroll(1)).toBe(nil)
		expect(w.list.autoscroll:peek().state).toBe("idle")
	end)

	it("with no session at all the model is reset, not left armed", function()
		local w = world({ reorderable = true })
		expect(w.list.stepAutoscroll(0)).toBe(nil)
		expect(w.list.autoscroll:peek().state).toBe("idle")
	end)

	it("autoscroll is off by default on a plain list (no drag, no bands)", function()
		local w = world()
		expect(w.list.stepAutoscroll(0)).toBe(nil)
	end)
end)

describe("unified collection: identity and focus under live churn (SF-L1)", function()
	it("a re-sort MID-DRAG keeps the session, the payload and mounted identity", function()
		local w = world({ reorderable = true })
		w.lift("r1")
		expect(w.registry().isActive()).toBe(true)
		local mountedBefore = w.list.debugWindow()
		local factoryBefore = w.handle.root.counters().factoryRuns
		-- the owner re-sorts underneath the drag (a 250 ms server tick)
		local items = w.rows:peek() :: { any }
		local churned = table.clone(items)
		table.remove(churned, 2)
		table.insert(churned, 5, items[2])
		w.rows:set(churned)
		w.pres.refresh()
		expect(w.registry().isActive()).toBe(true)
		expect(w.registry().payload().key).toBe("r1")
		-- the same keys are still mounted: a re-sort moves rows, it never
		-- remounts them
		for key in mountedBefore do
			expect(w.list.debugWindow()[key]).toBe(true)
		end
		expect(w.handle.root.counters().factoryRuns).toBe(factoryBefore)
	end)

	it("selection and focus survive a re-sort during a drag", function()
		local w = world({ reorderable = true, selection = "single" })
		w.list.select("r6")
		w.list.focusKey("r6")
		w.lift("r1")
		local items = w.rows:peek() :: { any }
		local reversed = {}
		for i = #items, 1, -1 do
			table.insert(reversed, items[i])
		end
		w.rows:set(reversed)
		w.pres.refresh()
		expect(w.list.selectedKey:peek()).toBe("r6")
		expect(w.list.focusedKey:peek()).toBe("r6")
		expect(w.registry().isActive()).toBe(true)
	end)

	it("removing the HOVERED row mid-drag clears the verdict and keeps the session (F5)", function()
		local w = world({ reorderable = true })
		w.lift("r1")
		w.moveTo("r1", w.rowY("r4"))
		expect(w.registry().verdict:peek().targetId ~= nil).toBe(true)
		local next = {}
		for _, item in w.rows:peek() :: { any } do
			if item.id ~= "r4" then
				table.insert(next, item)
			end
		end
		w.rows:set(next)
		w.pres.refresh()
		expect(w.registry().isActive()).toBe(true)
		-- a different row now occupies that y, so the session simply re-targets:
		-- what must NOT happen is the session dying with the row
		expect(w.registry().payload().key).toBe("r1")
	end)

	it("reorder motion slides the moved rows through presentation, never a re-solve", function()
		local now = 0
		local core = harness.newCore()
		local clock = Facet.motion.newClock(core, {
			now = function()
				return now
			end,
		})
		local w = world({ reorderable = true, motionClock = clock, reorderMotion = "object" })
		local solvesBefore = w.handle.controller.stats().solves
		w.list.select("r1")
		local items = w.rows:peek() :: { any }
		local churned = table.clone(items)
		table.remove(churned, 1)
		table.insert(churned, 3, items[1])
		w.rows:set(churned)
		w.pres.refresh()
		clock:step(0.016)
		-- the slide is presentation-only: the solve count moved by the structural
		-- refresh, and NOT once per animated frame
		local solvesAfter = w.handle.controller.stats().solves
		clock:step(0.016)
		clock:step(0.016)
		expect(w.handle.controller.stats().solves).toBe(solvesAfter)
		expect(solvesAfter >= solvesBefore).toBe(true)
		clock:dispose()
	end)
end)

describe("unified collection: focus-skip on rows (SF-L3)", function()
	it("an ineligible row is skipped by navigation but still activates on a tap", function()
		local activated: { string } = {}
		local blocked: { [string]: boolean } = { r2 = true }
		local w = world({
			rowFocusable = function(item: any)
				return blocked[item.id] ~= true
			end,
			onActivate = function(item: any)
				table.insert(activated, item.id)
			end,
		})
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.pres.refresh()
		expect(w.list.focusedKey:peek()).toBe("r3") -- r2 was skipped
		-- ...and r2 is still fully inspectable
		w.adapter.tap(w.hitPath("r2"))
		expect(activated).toEqual({ "r2" })
	end)

	it("the predicate flips mid-navigation and the ring follows on the NEXT press", function()
		local blocked: { [string]: boolean } = {}
		local w = world({
			rowFocusable = function(item: any)
				return blocked[item.id] ~= true
			end,
		})
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.list.focusedKey:peek()).toBe("r2")
		blocked.r3 = true
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.pres.refresh()
		expect(w.list.focusedKey:peek()).toBe("r4")
	end)

	it("the row a live session is aiming at never loses focusability mid-gesture", function()
		local blocked: { [string]: boolean } = {}
		local w = world({
			reorderable = true,
			rowFocusable = function(item: any)
				return blocked[item.id] ~= true
			end,
		})
		w.lift("r1")
		w.moveTo("r1", w.rowY("r4"))
		expect(w.registry().interactionTarget()).toBe(w.hitPath("r4"))
		-- the game's own rule now says r4 is ineligible...
		blocked.r4 = true
		-- ...but it is what the gesture is aiming at, so the targeting holds and
		-- the predicted slot does not move out from under the player
		w.pres.refresh()
		expect(w.registry().interactionTarget()).toBe(w.hitPath("r4"))
		expect(w.list.dropIndex:peek()).toBe(4)
		-- and the commit still lands: an exempt row resolves through the session,
		-- it never vanishes mid-gesture
		w.release("r1", w.rowY("r4"))
		expect(#w.reorders).toBe(1)
	end)
end)

describe("unified collection: uniform derived row height (finding F13)", function()
	it("accepts a Readable row height and re-derives the whole list from it", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, system)
		local rowHeight = Compose.cell(40)
		local rows = Compose.cell(makeRows(40))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = rowHeight,
			viewportHeight = 400,
			overscan = 0,
			cell = function(item: any)
				return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local handle = pres.present(harness.UI.Screen({ id = "S", children = { list.blueprint } }))
		pres.refresh()
		expect(list.dump().rowHeight).toBe(40)
		local windowAt40 = 0
		for _ in list.debugWindow() do
			windowAt40 += 1
		end
		-- the theme grew: ONE number moves and the whole list re-derives
		rowHeight:set(80)
		pres.refresh()
		expect(list.dump().rowHeight).toBe(80)
		local windowAt80 = 0
		for _ in list.debugWindow() do
			windowAt80 += 1
		end
		expect(windowAt80 < windowAt40).toBe(true)
		list.dispose()
	end)

	it("accepts a Readable VIEWPORT height, so a rotation re-windows in place (R2-F7)", function()
		-- the same lesson one level up (review R2-F7): a window height fixed at build
		-- is wrong for the rest of the session the moment the device turns. Both
		-- consumers of the number move together — the painted host box and the
		-- windowing arithmetic — or the list paints rows it did not mount.
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, system)
		local rows = Compose.cell(makeRows(60))
		local viewportHeight = Compose.formula(function(use)
			local vp: any = use(env:get("viewportRect"))
			return math.floor(vp.h * 0.5)
		end)
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = viewportHeight,
			overscan = 0,
			cell = function(item: any)
				return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		pres.present(harness.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } }))
		pres.refresh()
		expect(list.dump().viewportHeight).toBe(400)
		local tall = 0
		for _ in list.debugWindow() do
			tall += 1
		end
		expect(adapter.node("/S/VL").rect.h).toBe(400)
		-- the device turns: one environment fact moves and the window follows
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 400 })
		pres.refresh()
		expect(list.dump().viewportHeight).toBe(200)
		local wide = 0
		for _ in list.debugWindow() do
			wide += 1
		end
		expect(wide < tall).toBe(true)
		-- the PAINTED box moved with the arithmetic: the two can never disagree
		expect(adapter.node("/S/VL").rect.h).toBe(200)
		list.dispose()
	end)

	it("ACCEPTS a per-row height, and windows on the running offsets it implies", function()
		--[[ THIS CASE USED TO ASSERT THE OPPOSITE. Until 2026-08-14 a per-row extent
			was refused with "uniformity is what the windowing math rests on" — true of
			`index × pitch`, and the reason the refusal was written. The widened
			overflow sweep then measured what the refusal costs (a `row_actions` row
			declaring 84 and measuring 249 at `preferredTextOffset = 14` on a 320×640
			phone), and the game director ruled to build variable extents rather than
			keep the ban (`docs/handoff/2026-08-13-rulings-needed.md` ruling 7).

			The characterization is REVERSED here rather than deleted, because "what
			happens when a caller hands in a function" is still a contract this file
			owns — it is now a running-offset index, and the numbers below are what
			that means. `virtual_list_variable_extents.spec` holds the whole feature. ]]
		local core = harness.newCore()
		local rows = Compose.cell(makeRows(6))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = function(_item: any, index: number)
				return if index % 2 == 0 then 80 else 40
			end,
			viewportHeight = 400,
			cell = function()
				return harness.UI.Text({ id = "L", text = "x" })
			end,
		})
		local d = list.dump()
		expect(d.itemExtentMode).toBe("variable")
		expect(d.contentExtent).toBe(3 * 40 + 3 * 80)
		-- ...and the deprecated alias reaches the same feature: one field, two names
		expect(d.rowHeight).toBe(nil)
		list.dispose()
	end)
end)

describe('unified collection: following the tail (follow = "end")', function()
	local function followWorld(follow: any, threshold: number?)
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local rows = Compose.cell(makeRows(40))
		local list
		pres.present(function()
			list = virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 400,
				follow = follow,
				followThreshold = threshold,
				cell = function(item: any)
					return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
				end,
			})
			return harness.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } })
		end)
		local w: any = { adapter = adapter, pres = pres, rows = rows }
		function w.settle()
			for _ = 1, 3 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		function w.offset(): number
			return adapter.scrollPositionOf("/S/VL").y
		end
		function w.grow(count: number)
			rows:set(makeRows(count))
			w.settle()
		end
		w.settle()
		return w
	end

	it("opens on the tail and re-pins it as rows are appended", function()
		local w = followWorld("end", 8)
		expect(w.offset()).toBe(40 * 40 - 400)
		w.grow(43)
		expect(w.offset()).toBe(43 * 40 - 400)
	end)

	it("a reader who scrolled away keeps their place, and rejoins by returning to the end", function()
		local w = followWorld("end", 8)
		w.adapter.driveScroll("/S/VL", { x = 0, y = 480 })
		w.settle()
		w.grow(44)
		expect(w.offset()).toBe(480)
		-- within the threshold of the end counts as reading the tail again
		w.adapter.driveScroll("/S/VL", { x = 0, y = 44 * 40 - 400 - 6 })
		w.settle()
		w.grow(45)
		expect(w.offset()).toBe(45 * 40 - 400)
	end)

	--[[ THE PHONE'S "IT IS LIKE IT IS STUCK". A thread pinned at the end while a
		reply streams could not be panned away from at all: every frame of content
		growth re-pinned the end, and one frame of a pan never moves the whole
		`followThreshold`, so the player was snapped back faster than they could
		travel. The threshold test alone cannot see this — the offsets that matter
		are all INSIDE it. Direction is what tells the two apart. Measured on the
		phone profile: canvas 1216 in a 389 window, a 230 px pan moved the offset
		827 -> 827. ]]
	it("a pan that starts INSIDE the threshold is honoured, and growth stops moving the view", function()
		local w = followWorld("end", 48)
		expect(w.offset()).toBe(1200)
		-- one frame of a pan: 12 px away from the end, well inside the threshold
		w.adapter.driveScroll("/S/VL", { x = 0, y = 1188 })
		w.settle()
		w.grow(43)
		expect(w.offset()).toBe(1188) -- NOT re-pinned to 1320
		-- ...and the next frames of the same pan accumulate instead of fighting
		w.adapter.driveScroll("/S/VL", { x = 0, y = 1100 })
		w.settle()
		w.grow(46)
		expect(w.offset()).toBe(1100)
	end)

	it("returning to the end resumes following after a yield", function()
		local w = followWorld("end", 48)
		w.adapter.driveScroll("/S/VL", { x = 0, y = 1188 })
		w.settle()
		w.grow(43)
		expect(w.offset()).toBe(1188)
		-- the player comes back: within the threshold of the CURRENT end
		w.adapter.driveScroll("/S/VL", { x = 0, y = 43 * 40 - 400 - 10 })
		w.settle()
		w.grow(44)
		expect(w.offset()).toBe(44 * 40 - 400)
	end)

	it("NEGATIVE CONTROL: a list that does not follow never moves on growth", function()
		local w = followWorld(nil)
		expect(w.offset()).toBe(0)
		w.grow(43)
		expect(w.offset()).toBe(0)
	end)

	it("an illegal follow, and a threshold with nothing to follow, are refused at construction", function()
		local function build(extra: any)
			local core = harness.newCore()
			local spec: any = {
				id = "VL",
				rows = Compose.cell(makeRows(4)),
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 400,
				cell = function(item: any)
					return harness.UI.Text({ id = "Label", text = item.label })
				end,
			}
			for key, value in extra do
				spec[key] = value
			end
			return pcall(virtual_list.build, Facet, core, spec)
		end
		local ok, err = build({ follow = "start" })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), '"end"', 1, true) ~= nil).toBe(true)
		local okThreshold, errThreshold = build({ followThreshold = 8 })
		expect(okThreshold).toBe(false)
		expect(string.find(tostring(errThreshold), "followThreshold", 1, true) ~= nil).toBe(true)
		expect((build({ follow = "end", followThreshold = -1 }))).toBe(false)
	end)

	it("a live follow flip stops tail-following and resumes it, without remounting the list", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local rows = Compose.cell(makeRows(40))
		local follow = Compose.cell("end")
		local list
		pres.present(function()
			list = virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 400,
				follow = follow,
				followThreshold = 8,
				cell = function(item: any)
					return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
				end,
			})
			return harness.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } })
		end)
		local mountedList = list
		local function settle()
			for _ = 1, 3 do
				pres.tick(1 / 60)
				pres.refresh()
			end
		end
		local function offset(): number
			return adapter.scrollPositionOf("/S/VL").y
		end
		settle()
		expect(offset()).toBe(40 * 40 - 400)
		-- Flip live to "none": growth no longer re-pins the tail.
		follow:set("none")
		settle()
		rows:set(makeRows(42))
		settle()
		expect(offset()).toBe(40 * 40 - 400)
		-- Still parked near the (moved) tail, so flipping back "end" resumes
		-- immediately — the same live-flip moment `followThreshold` already
		-- measures against for an engine-reported scroll.
		adapter.driveScroll("/S/VL", { x = 0, y = 42 * 40 - 400 - 6 })
		settle()
		follow:set("end")
		settle()
		expect(offset()).toBe(42 * 40 - 400)
		rows:set(makeRows(45))
		settle()
		expect(offset()).toBe(45 * 40 - 400)
		-- Never remounted: same control record throughout the flips.
		expect(list).toBe(mountedList)
	end)
end)

describe("unified collection: teardown", function()
	it("build/mount/reorder/drop/dispose returns the core to baseline", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new({ ops = true })
		local pres = harness.newPresenter(core, env, adapter, system)
		local baseline = core.owner.size()

		local rows = Compose.cell(makeRows(30))
		-- built inside the presented component, so the window's rows belong to the
		-- surface and leave with it
		local list
		local handle = pres.present(function()
			list = virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 400,
				selection = "single",
				reorderable = true,
				onReorder = function() end,
				dropSurface = true,
				cell = function(item: any)
					return harness.UI.Text({ id = "Label", text = item.label, textSize = 14 })
				end,
			})
			return harness.UI.Screen({ id = "S", children = { list.blueprint } })
		end)
		pres.refresh()
		local unbind = list.bindNativeScroll(handle.controller)
		local hit = "/S/VL/Canvas/W/[r1]/Row/Hit"
		local r = handle.controller.rectOf(hit)
		adapter.driveDragStart(hit, { x = 100, y = r.y + 5, pointerType = "mouse" })
		adapter.driveDragContinue(hit, { x = 100, y = r.y + 60, pointerType = "mouse" }, { x = 0, y = 0 })
		adapter.driveDragEnd(hit, { x = 100, y = r.y + 60, pointerType = "mouse" })
		list.select("r2")
		list.stepAutoscroll(0.1)

		unbind()
		pres.dismiss(handle)
		list.dispose()

		local after = core.owner.size()
		expect(after).toBe(baseline)
	end)
end)

-- CTRL-08b (api-architecture-consistency F-25). `virtualization.spec.luau`
-- compares `root.dump()` — the MOUNT tree — so the CONTROL's dump determinism
-- and its schema string were unpinned.
describe("unified collection: the control dump (CTRL-08b)", function()
	it("list.dump() is deterministic and carries its schema string", function()
		local serde = require("@lune/serde")
		local w = world({ count = 40, selection = "single", reorderable = true })
		expect(w.list.dump().schema).toBe("facet-virtual-list-dump/1")
		local d1 = serde.encode("json", w.list.dump(), true)
		expect(d1).toBe(serde.encode("json", w.list.dump(), true))
		-- ...and still deterministic once live state has moved
		w.list.select("r3")
		w.list.scrollTop:set(200)
		w.pres.refresh()
		local d2 = serde.encode("json", w.list.dump(), true)
		expect(d2).toBe(serde.encode("json", w.list.dump(), true))
		expect(d2 ~= d1).toBe(true)
		expect(w.list.dump().selectedKey).toBe("r3")
		expect(w.list.dump().scrollTop).toBe(200)
	end)
end)
