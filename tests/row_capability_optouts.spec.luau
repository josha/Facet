--!strict
-- PER-ROW CAPABILITY OPT-OUTS — `rowSelectable` / `rowMovable` / `rowDeletable`
-- across BOTH collection controls (parity round 3, item C; game-director ruling
-- 2026-08-13 to ship all three).
--
-- WHAT THESE ARE. SwiftUI ships `selectionDisabled(_:)` (iOS 17), `deleteDisabled(_:)`
-- and `moveDisabled(_:)` (both iOS 13) as modifiers you attach to a ROW VIEW, taking an
-- ordinary boolean computed from the item. LuauUI has no per-row-view modifier
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

local LuauUI = require("../src")
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
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
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
			return LuauUI.UI.Text({ id = "Cell", text = item.name })
		end,
	}
	for k, v in extra or {} do
		spec[k] = v
	end
	local vl = virtual_list.build(LuauUI, core, spec)
	local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { vl.blueprint } }))
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
		local core = LuauUI.newCore()
		local rows = core:signal(ITEMS)
		local spec: any = {
			id = "VL",
			rows = rows,
			key = keyOf,
			itemExtent = 40,
			viewportExtent = 600,
			cell = function(item: any)
				return LuauUI.UI.Text({ id = "Cell", text = item.name })
			end,
		}
		for k, v in extra do
			spec[k] = v
		end
		return function()
			virtual_list.build(LuauUI, core, spec)
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
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 500, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
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
	local tbl = table_control.build(LuauUI, core, spec)
	local handle = pres.present(LuauUI.UI.Screen({ id = "T0", children = { tbl.blueprint } }))
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
		-- LuauUI decides: a pinned row holds its INDEX, so a move that would
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
		local core = LuauUI.newCore()
		local rows = core:signal({ { id = "a" } })
		local ok, err = pcall(function()
			virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 400,
				wrap = true,
				cell = function()
					return LuauUI.UI.Text({ id = "Cell", text = "x" })
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
