--!strict
-- PER-ROW CAPABILITY OPT-OUTS — `rowSelectable` / `rowMovable` / `rowDeletable`
-- across BOTH collection controls (parity round 3, item C; game-director ruling
-- 2026-08-13 to ship all three).
--
-- WHAT THESE ARE. SwiftUI ships `selectionDisabled(_:)` (iOS 17), `deleteDisabled(_:)`
-- and `moveDisabled(_:)` (both iOS 13) as modifiers you attach to a ROW VIEW, taking an
-- ordinary boolean computed from the item. Facet has no per-row-view modifier
-- vocabulary, so the faithful translation is a spec-level per-row closure — which is
-- already this codebase's idiom for exactly this shape five times over (`rowFocusable`,
-- `rowDropTarget`, `rowActions`, `rowHeight`, `dragLabel`).
--
-- THREE RULES THESE ARE HELD TO, each from a rule the repo already paid for:
--
--   1. POSITIVE POLARITY. SwiftUI's names are negative (`…Disabled`, true = off);
--      `rowFocusable` already sits on the same spec table meaning true = on. Shipping
--      `rowFocusable` and `moveDisabled` two lines apart would be a bug factory. The
--      parity doc states the inverse mapping instead.
--
--   2. GATE THE FUNNEL, NOT THE AFFORDANCE. `table.luau`'s own history records being
--      bitten by "a third, wholly separate way to start the identical reorder" that
--      missed a guard. So the predicate is checked where a row actually MOVES / gets
--      SELECTED / gets DELETED, not only where the button is drawn. The affordance is
--      hidden too — but hiding is cosmetics, the funnel is the contract.
--
--   3. A PREDICATE MAY ONLY SUBTRACT. It answers "may THIS ROW participate?", never
--      "can this container do X at all?". Declaring `rowMovable` on a control with no
--      `onReorder`, or `rowSelectable` with `selection = "none"`, is a CONSTRUCTION
--      refusal naming the missing capability (constitution §4: an accepted property
--      must do something).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local fake_target = require("./lib/fake_target")
local virtual_list = require("../src/controls/virtual_list")
local table_control = require("../src/controls/table")

local ITEMS = {
	{ id = "a", name = "Alpha" },
	{ id = "b", name = "Bravo" },
	{ id = "c", name = "Charlie" },
}

local function keyOf(item: any): string
	return item.id
end

-- ── VirtualList worlds ──────────────────────────────────────────────────────
local function vlistWorld(extra: { [string]: any }?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(ITEMS)
	local moved: { { key: string, to: number } } = {}
	local selected: { string } = {}
	local spec: any = {
		id = "VL",
		rows = rows,
		key = keyOf,
		itemExtent = 40,
		viewportExtent = 600,
		selection = "single",
		onSelect = function(_item, key)
			table.insert(selected, key)
		end,
		reorderable = true,
		onReorder = function(key, to)
			table.insert(moved, { key = key, to = to })
		end,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Cell", text = item.name })
		end,
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local vl = virtual_list.build(Facet, core, spec)
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { vl.blueprint } }))
	pres.refresh()
	return {
		core = core,
		pres = pres,
		adapter = adapter,
		vl = vl,
		handle = handle,
		moved = moved,
		selected = selected,
		rows = rows,
	}
end

describe("row capability opt-outs — VirtualList", function()
	it("rowSelectable = false STOPS the selection at the funnel, not just at the affordance", function()
		local w = vlistWorld({
			rowSelectable = function(item: any)
				return item.id ~= "b"
			end,
		})
		-- the public verb IS the funnel: every tap, key and pad press routes here
		w.vl.select("a")
		w.vl.select("b") -- refused
		w.vl.select("c")
		expect(w.selected).toEqual({ "a", "c" })
		-- and the model is not left holding the refused row
		expect(w.vl.dump().selectedKey).toBe("c")
	end)

	it("rowMovable = false refuses the GRAB — a pinned row never arms, on any input", function()
		-- `toggleGrab` is VirtualList's public reorder entry (the gamepad grab,
		-- and the seam the keyboard path shares). A pinned row must not arm:
		-- arming it would put the player in a drag they can never legally drop.
		local w = vlistWorld({
			rowMovable = function(item: any)
				return item.id ~= "a"
			end,
		})
		w.vl.toggleGrab("a")
		expect(w.vl.armedKey:get()).toBe(nil) -- refused
		w.vl.toggleGrab("c")
		expect(w.vl.armedKey:get()).toBe("c") -- allowed
	end)

	it("an absent predicate changes nothing — every row participates, byte-identical to today", function()
		local w = vlistWorld()
		w.vl.select("b")
		w.vl.toggleGrab("a")
		expect(w.selected).toEqual({ "b" })
		expect(w.vl.armedKey:get()).toBe("a")
	end)

	it("a predicate that THROWS is quarantined and fails CLOSED (the row does not participate)", function()
		-- constitution §7: a callback computing a value the framework needs has a
		-- stated fallback on throw. For a capability gate the two directions are
		-- NOT symmetric — fail open and a consumer bug silently deletes a row the
		-- author was protecting; fail closed and a row stubbornly refuses to
		-- move. So it fails closed.
		--
		-- IT IS SWALLOWED RATHER THAN RECORDED, and that is a known gap, not a
		-- choice. §8's ladder says a quarantined callback is "recorded via
		-- lastError", but `core`'s `fail` is a private local
		-- (`core/custom.luau:60`) and `Core` publishes only `lastError()` to
		-- READ. A composite has no channel to write one — which is why every
		-- shipped quarantine in `row_actions.luau` is a bare `pcall` too
		-- (`:1542`, `:1620`, `:1889`, `:3336`). Asserted as it really is, so
		-- nobody reads a green suite as "the throw was reported".
		local w = vlistWorld({
			rowMovable = function(_item: any): boolean
				error("consumer bug")
			end,
		})
		w.vl.toggleGrab("a")
		expect(w.vl.armedKey:get()).toBe(nil)
		expect(w.core:lastError()).toBe(nil) -- the honest state: silent
	end)
end)

describe("row capability opt-outs — construction refusals (a predicate may only subtract)", function()
	local function buildVL(extra: { [string]: any })
		local core = Facet.newCore()
		local rows = core:signal(ITEMS)
		local spec: any = {
			id = "VL",
			rows = rows,
			key = keyOf,
			itemExtent = 40,
			viewportExtent = 600,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Cell", text = item.name })
			end,
		}
		for k, v in extra do
			spec[k] = v
		end
		return function()
			virtual_list.build(Facet, core, spec)
		end
	end

	it("rowSelectable on a selection = 'none' list is refused, naming the missing capability", function()
		local ok, err = pcall(buildVL({
			selection = "none",
			rowSelectable = function()
				return true
			end,
		}))
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "rowSelectable", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "selection", 1, true) ~= nil).toBe(true)
	end)

	it("rowMovable without onReorder is refused, naming the missing capability", function()
		local ok, err = pcall(buildVL({
			rowMovable = function()
				return true
			end,
		}))
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "rowMovable", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "onReorder", 1, true) ~= nil).toBe(true)
	end)

	it("rowDeletable without rowActions is refused, naming the missing capability", function()
		local ok, err = pcall(buildVL({
			rowDeletable = function()
				return true
			end,
		}))
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "rowDeletable", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "rowActions", 1, true) ~= nil).toBe(true)
	end)
end)

local function isSelected(tbl: any, key: string): boolean
	for _, k in tbl.dump().selectedKeys do
		if k == key then
			return true
		end
	end
	return false
end

-- ── Table ───────────────────────────────────────────────────────────────────
local function tableWorld(extra: { [string]: any }?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 500, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(ITEMS)
	local moved: { any } = {}
	local spec: any = {
		id = "T",
		rows = rows,
		key = keyOf,
		header = false,
		rowHeight = 32,
		selection = "multi",
		reorderable = true,
		onReorder = function(keys, slot)
			table.insert(moved, { keys = keys, slot = slot })
		end,
		columns = {
			{
				id = "name",
				title = "Name",
				width = { type = "fill", weight = 1 },
				value = function(item: any)
					return item.name
				end,
			},
		},
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local tbl = table_control.build(Facet, core, spec)
	local handle = pres.present(Facet.UI.Screen({ id = "T0", children = { tbl.blueprint } }))
	pres.refresh()
	return { core = core, pres = pres, adapter = adapter, tbl = tbl, handle = handle, moved = moved, rows = rows }
end

describe("row capability opt-outs — Table", function()
	it("rowSelectable = false refuses at api.select, in EVERY selection mode path", function()
		local w = tableWorld({
			rowSelectable = function(item: any)
				return item.id ~= "b"
			end,
		})
		w.tbl.api.select("a")
		w.tbl.api.select("b") -- refused
		expect(isSelected(w.tbl, "a")).toBe(true)
		expect(isSelected(w.tbl, "b")).toBe(false)
		-- the additive-toggle branch is a SEPARATE path in api.select and must
		-- refuse too — this is the "gate the funnel" rule, and a guard on only
		-- the single-select branch would pass a naive test
		w.tbl.api.select("b", { mode = "replace" })
		expect(isSelected(w.tbl, "b")).toBe(false)
		w.tbl.api.select("b", { mode = "range" })
		expect(isSelected(w.tbl, "b")).toBe(false)
	end)

	it("rowMovable = false refuses at api.moveRow — Table has FIVE reorder entry points", function()
		local w = tableWorld({
			rowMovable = function(item: any)
				return item.id ~= "a"
			end,
		})
		expect(w.tbl.api.moveRow("a", 1)).toBe(false)
		expect(#w.moved).toBe(0)
		expect(w.tbl.api.moveRow("c", -1)).toBe(true)
		expect(#w.moved).toBe(1)
	end)

	it("a pinned row is not a DESTINATION either: a movable row cannot displace it", function()
		-- moveDisabled's source-vs-destination question is one Apple does not
		-- document (its page is an abstract and a declaration, no discussion).
		-- Facet decides: a pinned row holds its INDEX, so a move that would
		-- shift it is refused. Otherwise "pinned" would mean "cannot be dragged
		-- but can be pushed around", which is not what an author means by it.
		local w = tableWorld({
			rowMovable = function(item: any)
				return item.id ~= "a" -- 'a' is pinned at index 1
			end,
		})
		-- moving 'c' to the front would displace the pinned 'a'
		expect(w.tbl.api.moveRow("c", -2)).toBe(false)
		expect(#w.moved).toBe(0)
	end)

	it("an absent predicate changes nothing on Table either", function()
		local w = tableWorld()
		w.tbl.api.select("b")
		expect(isSelected(w.tbl, "b")).toBe(true)
		expect(w.tbl.api.moveRow("a", 1)).toBe(true)
	end)
end)

--[[ THE REFUSAL THAT HAD NO REASON (owed by the flow-wrap build, closed after).

	`wrap` is not in `newVirtualList`'s closed key set, so it was already refused —
	but by the generic unknown-field guard, which leaves an author guessing whether
	it is a typo, an unbuilt feature, or a deliberate decision. It is the third, and
	a refusal that does not say why gets re-filed as a feature request. ]]
describe("flow-wrap x virtualization: refused, and the refusal names the conflict", function()
	it("newVirtualList refuses `wrap` and explains the index x itemExtent arithmetic", function()
		local core = Facet.newCore()
		local rows = core:signal({ { id = "a" } })
		local ok, err = pcall(function()
			virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 400,
				wrap = true,
				cell = function()
					return Facet.UI.Text({ id = "Cell", text = "x" })
				end,
			})
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		-- the DECISION, not just the rejection
		expect(string.find(message, "do not compose", 1, true) ~= nil).toBe(true)
		-- the REASON, in the arithmetic's own terms
		expect(string.find(message, "itemExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "ragged", 1, true) ~= nil).toBe(true)
		-- and the WORKING ALTERNATIVE, which is what stops it being re-filed
		expect(string.find(message, "ScrollView", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ═══ `rowDeletable` WAS ACCEPTED, VALIDATED, DOCUMENTED — AND INERT ═══════
	Found by the fresh-context architecture gate, 2026-08-14, and it is the exact
	defect this file's own header rule 2 is written against. `rowSelectable` had
	two `allows` gate sites and `rowMovable` had four; `rowDeletable` had ZERO.
	Every mention of it in `src/` was the closed-key-set entry or the construction
	refusal — `row_actions.luau` did not reference the property at all. So an
	author holding a documented, deliberately fail-CLOSED delete guard held an
	inert one, and the row they were protecting deleted through all four routes.

	THE FUNNEL IS `row_actions.doCommitAction` — the swipe commit, the revealed
	tray's Delete button, the edit-mode ⊖, the `Delete`/`Backspace` key and the
	action menu's destructive row ALL reach it, which is why one gate there covers
	every route (director, parity round 3: "both routes gate the same funnel...
	with one predicate evaluated in one place"). `row_actions` has no notion of an
	item, so each host threads the already-resolved verdict in as `spec.deletable`,
	a thunk it evaluates at commit time.

	THESE ARE THE BEHAVIOURAL CASES the shipping commit did not have: `46eb1fc`
	claimed six mutations proved to bite, and all six were `rowSelectable` /
	`rowMovable`. The only `rowDeletable` case in this file was the construction
	refusal above — which passes just as happily when the predicate does nothing. ]]

local ROW_KEYS_DELETE = "Delete"

-- ── Table: all FOUR delete routes ───────────────────────────────────────────
local function deletableTableWorld(protectedId: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local clock = { t = 100 }
	local pres = Facet.newPresenter(core, env, adapter, system, {
		now = function()
			return clock.t
		end,
	})
	local fired: { string } = {}
	local editing = core:signal(true) -- the ⊖ route needs edit mode
	local spec: any = {
		id = "T",
		rows = core:signal(ITEMS),
		key = keyOf,
		header = false,
		rowHeight = 40,
		selection = "single",
		env = env,
		editing = editing,
		rowActions = function(item: any)
			return {
				-- a NON-destructive action on the other edge: `rowDeletable` answers
				-- "may this row be DELETED", so this one must keep working on a
				-- protected row. Without it here, a gate that dropped its
				-- `role == "destructive"` qualifier would pass every case in this
				-- file (measured — mutation M7).
				leading = {
					{
						id = "flag",
						label = "Flag",
						onAction = function()
							table.insert(fired, `flag:{item.id}`)
						end,
					},
				},
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, item.id)
						end,
					},
				},
				fullSwipe = true, -- the swipe route needs a committing full swipe
			}
		end,
		columns = {
			{
				id = "name",
				title = "Name",
				width = { type = "fill", weight = 1 },
				value = function(item: any)
					return item.name
				end,
			},
		},
	}
	if protectedId ~= nil then
		spec.rowDeletable = function(item: any)
			return item.id ~= protectedId
		end
	end
	local tbl = table_control.build(Facet, core, spec)
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }), {
		onActivate = function(path, meta)
			tbl.api.handleActivate(path, meta)
		end,
	})
	pres.refresh()
	local w: any =
		{ core = core, adapter = adapter, pres = pres, system = system, tbl = tbl, handle = handle, fired = fired }
	function w.settle(frames: number?)
		for _ = 1, frames or 200 do
			clock.t += 1 / 60
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	function w.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
		w.settle(3)
	end
	function w.root(key: string): string
		return `/S/T/Main/Body/Rows/[{key}@0]/RowActions-{key}`
	end
	function w.hit(key: string): string
		return `{w.root(key)}/Content/Row/Hit`
	end
	-- a FULL swipe: far enough past COMMIT_FRACTION of the row width to commit
	function w.fullSwipe(key: string)
		local rect = w.adapter.node(w.hit(key)).rect
		local originX = rect.x + rect.w - 8
		local y = rect.y + rect.h / 2
		w.adapter.pointerDown(w.hit(key), originX, y, "mouse")
		w.settle(1)
		for i = 1, 10 do
			w.adapter.pointerMove(originX - rect.w * 0.95 * (i / 10), y, "mouse")
			w.settle(1)
		end
		w.adapter.pointerUp(originX - rect.w * 0.95, y)
		w.settle(300)
	end
	return w
end

describe("rowDeletable — Table: a protected row survives ALL FOUR delete routes", function()
	it("ROUTE 1 (full swipe): the protected row refuses to commit; an unprotected one deletes", function()
		local w = deletableTableWorld("b")
		local closedX = w.adapter.node(w.hit("b")).rect.x
		w.fullSwipe("b")
		expect(w.fired).toEqual({})
		--[[ ...AND IT IS STILL ON SCREEN. A refused commit takes `settleTo`'s
			ordinary settle, which aims at `verdict.target` — ±the whole ROW WIDTH for
			a full swipe. What keeps the row from parking off-screen is `syncGeometry`'s
			open-edge re-assert, which re-aims the spring at the TRAY width on the next
			sync; this pins that, because "refused to delete AND vanished" would be the
			worst of both answers and nothing else in the suite would have seen it. ]]
		local afterX = w.adapter.node(w.hit("b")).rect.x
		local travel = closedX - afterX
		expect(`refused swipe moved the row: {travel > 0}`).toBe("refused swipe moved the row: true")
		local rowW = w.adapter.node(w.hit("b")).rect.w
		expect(`...but not a whole row width: {travel < rowW}`).toBe("...but not a whole row width: true")
		w.fullSwipe("a")
		expect(w.fired).toEqual({ "a" })
	end)

	it("ROUTE 1b (revealed tray button): tapping Delete on a protected row fires nothing", function()
		local w = deletableTableWorld("b")
		-- open without committing, then tap the tray's own Delete
		local rect = w.adapter.node(w.hit("b")).rect
		local originX, y = rect.x + rect.w - 8, rect.y + rect.h / 2
		w.adapter.pointerDown(w.hit("b"), originX, y, "mouse")
		w.settle(1)
		for i = 1, 8 do
			w.adapter.pointerMove(originX - rect.w * 0.25 * (i / 8), y, "mouse")
			w.settle(1)
		end
		w.adapter.pointerUp(originX - rect.w * 0.25, y)
		w.settle(200)
		local button = `{w.root("b")}/TrayTrailingWhen/then/TrayTrailing/Action:delete`
		expect(`tray open: {w.adapter.node(button) ~= nil}`).toBe("tray open: true")
		w.adapter.tap(button)
		w.settle(300)
		expect(w.fired).toEqual({})
	end)

	it("ROUTE 2 (edit-mode ⊖): the minus on a protected row deletes nothing", function()
		local w = deletableTableWorld("b")
		local minus = `{w.root("b")}/EditAffordanceWhen/then/EditAffordance`
		expect(`minus mounted: {w.adapter.node(minus) ~= nil}`).toBe("minus mounted: true")
		w.adapter.tap(minus)
		w.settle(300)
		expect(w.fired).toEqual({})
		-- ...and the same affordance on an UNPROTECTED row still deletes (the
		-- control that makes the line above mean something)
		w.adapter.tap(`{w.root("a")}/EditAffordanceWhen/then/EditAffordance`)
		w.settle(300)
		expect(w.fired).toEqual({ "a" })
	end)

	it("ROUTE 3 (Delete key): the keyboard route is refused on a protected row", function()
		local w = deletableTableWorld("b")
		w.pres.focus.focusOn(w.hit("b"))
		w.pres.refresh()
		w.press(ROW_KEYS_DELETE)
		w.settle(300)
		expect(w.fired).toEqual({})
		w.pres.focus.focusOn(w.hit("a"))
		w.pres.refresh()
		w.press(ROW_KEYS_DELETE)
		w.settle(300)
		expect(w.fired).toEqual({ "a" })
	end)

	it("ROUTE 4 (action menu): the menu's destructive row is refused too", function()
		local w = deletableTableWorld("b")
		w.pres.focus.focusOn(w.hit("b"))
		w.pres.refresh()
		w.press("ButtonX")
		w.settle(30)
		local menuRow = "/RowActionsMenu-RowActions-b/Menu/MenuRows/Action:delete"
		expect(`menu open: {w.adapter.node(menuRow) ~= nil}`).toBe("menu open: true")
		w.adapter.tap(menuRow)
		w.settle(300)
		expect(w.fired).toEqual({})
	end)

	it("an absent rowDeletable deletes through every route, unchanged", function()
		local w = deletableTableWorld(nil)
		w.fullSwipe("b")
		expect(w.fired).toEqual({ "b" })
	end)

	it("the predicate subtracts DELETE ONLY: a protected row still flags, archives, pins", function()
		--[[ `rowDeletable` answers "may this row be DELETED", not "may this row do
			anything". A gate that forgot its `role == "destructive"` qualifier would
			silently make a protected row inert to every action it has — and would
			pass every other case in this file, because they all fire the destructive
			one. ]]
		--[[ Driven as a FULL LEADING SWIPE, deliberately. A tray-button TAP on a
			non-destructive action never enters `doCommitAction` at all
			(`fireTrayAction`'s own else-branch fires and closes), so it cannot see a
			gate that lives there — it passed the mutation happily. A full swipe on a
			non-destructive first action DOES go through the funnel
			(`settleTo` -> `doCommit` -> `doCommitAction`'s "fires immediately and
			springs back" branch), which is the one drive that can catch this. ]]
		local w = deletableTableWorld("b")
		local rect = w.adapter.node(w.hit("b")).rect
		local originX, y = rect.x + 8, rect.y + rect.h / 2
		w.adapter.pointerDown(w.hit("b"), originX, y, "mouse")
		w.settle(1)
		for i = 1, 10 do
			w.adapter.pointerMove(originX + rect.w * 0.95 * (i / 10), y, "mouse")
			w.settle(1)
		end
		w.adapter.pointerUp(originX + rect.w * 0.95, y)
		w.settle(300)
		expect(w.fired).toEqual({ "flag:b" })
	end)
end)

-- ── hosted VirtualList: the same funnel, the other host ─────────────────────
local function deletableVListWorld(protectedId: string?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local clock = { t = 100 }
	local pres = Facet.newPresenter(core, env, adapter, system, {
		now = function()
			return clock.t
		end,
	})
	local fired: { string } = {}
	local spec: any = {
		id = "VL",
		rows = core:signal(ITEMS),
		key = keyOf,
		rowHeight = 40,
		viewportHeight = 400,
		env = env,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.name, textSize = 14 })
		end,
		rowActions = function(item: any)
			return {
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, item.id)
						end,
					},
				},
				fullSwipe = true,
			}
		end,
	}
	if protectedId ~= nil then
		spec.rowDeletable = function(item: any)
			return item.id ~= protectedId
		end
	end
	local list = virtual_list.build(Facet, core, spec)
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	local w: any =
		{ core = core, adapter = adapter, pres = pres, system = system, list = list, handle = handle, fired = fired }
	function w.settle(frames: number?)
		for _ = 1, frames or 200 do
			clock.t += 1 / 60
			pres.tick(1 / 60)
			pres.refresh()
		end
	end
	function w.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
		w.settle(3)
	end
	function w.hit(key: string): string
		return `/S/VL/Canvas/W/[{key}]/Row/Hit`
	end
	function w.fullSwipe(key: string)
		local rect = w.adapter.node(w.hit(key)).rect
		local originX = rect.x + rect.w - 8
		local y = rect.y + rect.h / 2
		w.adapter.pointerDown(w.hit(key), originX, y, "mouse")
		w.settle(1)
		for i = 1, 10 do
			w.adapter.pointerMove(originX - rect.w * 0.95 * (i / 10), y, "mouse")
			w.settle(1)
		end
		w.adapter.pointerUp(originX - rect.w * 0.95, y)
		w.settle(300)
	end
	return w
end

describe("rowDeletable — hosted VirtualList: the same predicate, the other host", function()
	it("ROUTE 1 (full swipe): a protected row refuses; an unprotected one deletes", function()
		local w = deletableVListWorld("b")
		w.fullSwipe("b")
		expect(w.fired).toEqual({})
		w.fullSwipe("a")
		expect(w.fired).toEqual({ "a" })
	end)

	--[[ ONE WORLD PER PRESS, and it is not fussiness: a SECOND hosted Delete in
		the same session does not fire even with no predicate at all (measured — the
		control below is that measurement, and it holds identically on stock `main`).
		Writing the refusal and its control as two presses in one world would have
		produced a case that reddens for a reason that has nothing to do with
		`rowDeletable`. ]]
	it("ROUTE 3 (Delete key): the list's own key surface is refused on a protected row", function()
		local w = deletableVListWorld("b")
		w.pres.focus.focusOn(w.hit("b"))
		w.pres.refresh()
		w.press(ROW_KEYS_DELETE)
		w.settle(300)
		expect(w.fired).toEqual({})
	end)

	it("...and the SAME drive on an UNPROTECTED row deletes — the control that makes it evidence", function()
		local w = deletableVListWorld("b")
		w.pres.focus.focusOn(w.hit("a"))
		w.pres.refresh()
		w.press(ROW_KEYS_DELETE)
		w.settle(300)
		expect(w.fired).toEqual({ "a" })
	end)

	it("ROUTE 4 (action menu): the menu's destructive row is refused too", function()
		local w = deletableVListWorld("b")
		w.pres.focus.focusOn(w.hit("b"))
		w.pres.refresh()
		w.press("ButtonX")
		w.settle(30)
		local menuRow = "/RowActionsMenu-VL:b/Menu/MenuRows/Action:delete"
		expect(`menu open: {w.adapter.node(menuRow) ~= nil}`).toBe("menu open: true")
		w.adapter.tap(menuRow)
		w.settle(300)
		expect(w.fired).toEqual({})
	end)

	it("an absent rowDeletable deletes through the hosted funnel, unchanged", function()
		local w = deletableVListWorld(nil)
		w.fullSwipe("b")
		expect(w.fired).toEqual({ "b" })
	end)
end)
