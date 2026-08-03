--!strict
--[[
	`newVirtualList.focusPolicy` — DOES THE CURSOR FOLLOW THE ITEM OR THE SLOT?

	A list whose ORDER changes under the player asks a question a keyed list
	cannot answer on its own. VirtualList's focus has always been BY ITEM KEY, so
	a live standings list re-sorting every 250 ms walks the pad cursor up and down
	the rows on its own: the ring rides the racer, and the racer keeps changing
	slots. Rascal Rally's legacy sponsor list carries a director ruling against
	exactly that ("selection riding a racer's button visibly JUMPS slots on every
	overtake"), and the LuauUI port had to re-implement it CONSUMER-SIDE, driving
	the control's logical `focusedKey` and the presenter's focus graph by hand —
	two focus authorities, which is the split brain this field exists to remove.

	The contract pinned here:

	  · `"key"` is the DEFAULT and is the pre-field control byte for byte — no
	    pin, no observers, no graph binding, focus follows the item;
	  · `"index"` retargets focus to whoever occupies the previously-focused SLOT,
	    clamped to the last slot when the list shrank;
	  · the retarget drives the REAL focus authority — the logical key AND the
	    screen's focus graph — through the framework's own `focusKey`, so it is an
	    ORDINARY focus move: keep-visible applies and the ring-visibility origin is
	    left alone (the policy never summons a ring a touch player put away);
	  · it never fights a LIVE DRAG, and it falls THROUGH to the item when the
	    slot's new occupant is focus-ineligible;
	  · an illegal value is refused at construction, naming both legal ones.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

local function hit(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row/Hit`
end

-- a VirtualList inside a Screen, presented with ZERO opts (full auto-composition,
-- so the focus graph reaches the control the way it does on a real surface)
local function world(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local rows = core:signal(options.rows or makeRows(options.count or 8))
	local list = virtual_list.build(LuauUI, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = options.rowHeight or 40,
		rowGap = options.rowGap,
		viewportHeight = options.viewportHeight or 400,
		overscan = options.overscan or 2,
		focusPolicy = options.focusPolicy,
		rowFocusable = options.rowFocusable,
		reorderable = options.reorderable,
		onReorder = if options.reorderable then function() end else nil,
		grabOnActivate = if options.reorderable then false else nil,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function() end,
	})
	local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { list.blueprint } }))
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)
	local w: any = {
		core = core,
		system = system,
		adapter = adapter,
		pres = pres,
		list = list,
		rows = rows,
		handle = handle,
		unbindScroll = unbindScroll,
	}
	-- walk the pad onto `key` through the REAL device path, so both halves of
	-- focus (graph + logical) are seated exactly as a player would seat them
	function w.padTo(key: string)
		pres.focus.focusOn(hit(key))
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("DPadUp", true)
		system.deviceKey("DPadUp", false)
		assert(pres.focus.focused:get() == hit(key), `pad did not land on {key}`)
		assert(list.focusedKey:get() == key, `logical focus did not land on {key}`)
	end
	function w.reverse()
		local items = rows:get() :: { any }
		local out: { any } = {}
		for i = #items, 1, -1 do
			table.insert(out, items[i])
		end
		rows:set(out)
	end
	return w
end

-- ===========================================================================
describe('VirtualList focusPolicy "key" (the default: focus follows the ITEM)', function()
	it("the field is ABSENT by default and the dump says so, with no pin held", function()
		local w = world()
		expect(w.list.dump().focusPolicy).toBe("key")
		expect(w.list.dump().pinnedSlot).toBe(nil)
	end)

	it("a re-sort under the cursor carries focus WITH the item — both halves", function()
		local w = world({ count = 8 })
		w.padTo("r2")
		w.reverse() -- r8..r1, so r2 falls from slot 2 to slot 7
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		-- and no pin was ever taken: the policy's machinery is not allocated
		expect(w.list.dump().pinnedSlot).toBe(nil)
	end)

	it('an EXPLICIT "key" is the same answer as an absent field', function()
		local w = world({ count = 8, focusPolicy = "key" })
		w.padTo("r2")
		w.reverse()
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(w.list.dump().focusPolicy).toBe("key")
	end)

	it("removal still lands on the nearest survivor, preferring the follower", function()
		local w = world({ count = 8 })
		w.padTo("r5")
		local next = makeRows(8)
		table.remove(next, 5) -- r5 gone; slot 5 is now r6
		w.rows:set(next)
		expect(w.list.focusedKey:get()).toBe("r6")
	end)
end)

-- ===========================================================================
describe('VirtualList focusPolicy "index" (focus stays on the SLOT)', function()
	it("a re-sort under the cursor retargets to the slot's new occupant — BOTH halves", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r2")
		expect(w.list.dump().pinnedSlot).toBe(2)
		w.reverse() -- r8..r1: slot 2 is now r7, and r2 fell to slot 7
		w.pres.refresh()
		-- the LOGICAL focus is the row that now occupies slot 2…
		expect(w.list.focusedKey:get()).toBe("r7")
		-- …and so is the GRAPH's, which is the half that paints the ring and the
		-- half Activate dispatches against. One authority, no consumer loop.
		expect(w.pres.focus.focused:get()).toBe(hit("r7"))
		expect(w.list.dump().pinnedSlot).toBe(2)
	end)

	it("the pin SURVIVES repeated re-sorts (the 250 ms standings case)", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r3")
		for _ = 1, 4 do
			w.reverse()
			w.pres.refresh()
		end
		-- four reverses = the original order, and the cursor never left slot 3
		expect(w.list.focusedKey:get()).toBe("r3")
		expect(w.pres.focus.focused:get()).toBe(hit("r3"))
		expect(w.list.dump().pinnedSlot).toBe(3)
	end)

	it("a data update that does NOT move the focused row leaves focus alone", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r2")
		-- relabel every row: a fresh array, same order, same keys
		local same: { any } = {}
		for i, item in w.rows:get() :: { any } do
			table.insert(same, { id = item.id, label = `Row {i}!` })
		end
		w.rows:set(same)
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
	end)

	it("SHRINK clamps the pin to the last slot", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r6")
		expect(w.list.dump().pinnedSlot).toBe(6)
		-- the focused row SURVIVES but the list collapses to three rows, so slot 6
		-- no longer exists: the pin clamps to the last one
		w.rows:set({ { id = "r6", label = "Row 6" }, { id = "r1", label = "Row 1" }, { id = "r2", label = "Row 2" } })
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r2") -- the last slot
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		expect(w.list.dump().pinnedSlot).toBe(3)
	end)

	it("REMOVAL of the focused row is the same slot, clamped (the shared survivor rule)", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r5")
		local next = makeRows(8)
		table.remove(next, 5)
		w.rows:set(next)
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r6") -- whoever took slot 5
		expect(w.list.dump().pinnedSlot).toBe(5)
	end)

	it("it falls THROUGH to the item when the slot's new occupant is focus-INELIGIBLE", function()
		local w = world({
			count = 8,
			focusPolicy = "index",
			rowFocusable = function(item: any): boolean
				return item.id ~= "r7"
			end,
		})
		w.padTo("r2")
		w.reverse() -- slot 2 would become r7, which is out of play
		w.pres.refresh()
		-- parking the ring where Activate can do nothing is worse than the jump
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
	end)

	it("it never fights a LIVE DRAG: a re-sort mid-session leaves the aim alone", function()
		local w = world({ count = 8, focusPolicy = "index", reorderable = true })
		w.padTo("r2")
		-- lift r4 through the public pointer promotion path
		local rect = w.handle.controller.rectOf(hit("r4"))
		local y = rect.y + rect.h / 2
		w.adapter.driveDragStart(hit("r4"), { x = 100, y = y, pointerType = "mouse" })
		w.adapter.driveDragContinue(hit("r4"), { x = 100, y = y + 10, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(w.handle.controller.dragRegistry().isActive()).toBe(true)
		w.reverse() -- the owner re-sorts underneath the live drag
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r2"))
		-- …and the pin RESUMES once the session is over: rotate the (already
		-- reversed) order by one, which puts r6 on the still-pinned slot 2
		w.adapter.driveDragEnd(hit("r4"), { x = 100, y = y + 10, pointerType = "mouse" })
		w.pres.refresh()
		local rotated = table.clone(w.rows:get() :: { any })
		table.insert(rotated, table.remove(rotated, 1))
		w.rows:set(rotated)
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r6")
		expect(w.pres.focus.focused:get()).toBe(hit("r6"))
	end)

	it("the retarget is an ORDINARY focus move: keep-visible applies", function()
		-- 8 rows of 60 in a 200 px band = 3 visible + 2 overscan, so a slot can be
		-- MOUNTED and still out of the band — exactly where keep-visible earns its
		-- keep. The pitch carries the gutter, so this also pins that the retarget
		-- reads the same rowGap arithmetic every other windowing number does.
		local w = world({ count = 8, focusPolicy = "index", rowHeight = 54, rowGap = 6, viewportHeight = 200 })
		w.adapter.driveScroll("/S/VL", { x = 0, y = 180 }) -- band = slots 4..6
		w.pres.refresh()
		w.padTo("r5")
		-- scroll back to the top: r5's slot is now mounted (overscan) but off-band
		w.adapter.driveScroll("/S/VL", { x = 0, y = 0 })
		w.pres.refresh()
		w.adapter.takeOps()
		w.reverse() -- slot 5 becomes r4
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r4")
		expect(w.pres.focus.focused:get()).toBe(hit("r4"))
		-- the framework issued its ONE programmatic scroll write to bring the newly
		-- focused SLOT into the band, on the pitch (54 + 6), not the row height
		local sawPos = false
		for _, op in w.adapter.takeOps() do
			if string.find(op, "scrollpos /S/VL=") ~= nil then
				sawPos = true
			end
		end
		expect(sawPos).toBe(true)
		-- minimal downward scroll: slot 5's TOP is (5-1)*pitch and its own box is
		-- rowHeight tall — keep-visible owes a visible ROW, never the trailing gutter
		expect(w.list.scrollTop:get()).toBe((5 - 1) * 60 + 54 - 200)
	end)

	it("an EXPLICIT focus move answering the same update WINS over the pin", function()
		-- the consumer's own reaction to a republish (here: "always follow the
		-- leader") is notified BEFORE the control's index observer, because `rows`
		-- is the written signal and `indexByKey` is only its dependent. The pin must
		-- read as "not caught up yet" rather than overwrite the choice just made —
		-- the case the (key, slot) PAIR exists for.
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r2")
		w.core:observe(w.rows, function(current: { any })
			w.list.focusKey(current[1].id)
		end)
		w.reverse() -- slot 2 would become r7; the consumer asks for slot 1's r8
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r8")
		expect(w.list.dump().pinnedSlot).toBe(1)
	end)

	it("the policy never SUMMONS a focus ring the player put away", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.padTo("r2")
		-- a tap is a pointer act: focus still MOVES, but the ring goes away (DB-3b)
		w.adapter.tap(hit("r2"))
		expect(w.pres.focus.focusVisible:get()).toBe(false)
		w.reverse()
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r7")
		expect(w.pres.focus.focused:get()).toBe(hit("r7"))
		-- the retarget answered no navigation question, so it paints no ring
		expect(w.pres.focus.focusVisible:get()).toBe(false)
	end)

	it("the RING is only moved when it was on the retargeted row (live canary 2026-08-02)", function()
		--[[ The two halves can legitimately be apart before any re-sort: a tap on a
			focus-INELIGIBLE row still activates and still sets the logical key, while
			`focusOn` refuses it — so the ring is somewhere else, possibly on another
			control. A pin that yanked it into this list on the next republish would
			be a focus move nobody asked for. The LOGICAL retarget still happens. ]]
		local w = world({
			count = 8,
			focusPolicy = "index",
			rowFocusable = function(item: any): boolean
				return item.id ~= "r2"
			end,
		})
		w.pres.focus.focusOn(hit("r4"))
		w.adapter.tap(hit("r2")) -- activates, sets the logical key, refuses the ring
		expect(w.list.focusedKey:get()).toBe("r2")
		expect(w.pres.focus.focused:get()).toBe(hit("r4"))
		w.reverse() -- r2 leaves slot 2; slot 2's new occupant is r7 (eligible)
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe("r7")
		expect(w.pres.focus.focused:get()).toBe(hit("r4")) -- the ring stayed put
	end)

	it("with nothing focused, a re-sort focuses nothing", function()
		local w = world({ count = 8, focusPolicy = "index" })
		w.pres.focus.focusOn(hit("r1")) -- graph only; the control was never told
		expect(w.list.focusedKey:get()).toBe(nil)
		w.reverse()
		w.pres.refresh()
		expect(w.list.focusedKey:get()).toBe(nil)
		expect(w.list.dump().pinnedSlot).toBe(nil)
	end)
end)

-- ===========================================================================
describe("VirtualList focusPolicy validation (constitution §4)", function()
	it("an illegal value is refused at construction, naming BOTH legal ones", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = core:signal(makeRows(2)),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 200,
				focusPolicy = "slot",
				cell = function()
					return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "focusPolicy", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), '"key"', 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), '"index"', 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "'slot'", 1, true) ~= nil).toBe(true)
	end)

	it("the closed spec set knows the field: a near-miss is refused by name", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = core:signal(makeRows(2)),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 200,
				focusPolicey = "index",
				cell = function()
					return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "focusPolicey", 1, true) ~= nil).toBe(true)
	end)
end)
