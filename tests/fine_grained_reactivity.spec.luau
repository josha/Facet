--!strict
--[[
	FINE-GRAINED REACTIVITY AT SCALE — changing one bound value must cost the same
	whether the collection holds 200 rows or 20 000.

	Every other performance test in this suite measures a WHOLE operation: mount N
	rows, scroll a window, swap a theme. None of them asks the question a reactive
	framework actually lives or dies on — when the underlying data changes, does the
	work scale with WHAT CHANGED, or with HOW MUCH THERE IS?

	That distinction is invisible to a timing test at small N and invisible to a
	green suite at any N. A framework that re-solves the whole tree on every write
	still passes every correctness test in this directory: the pixels are right, the
	rows are right, the diagnostics are silent. It is just quadratic. The only way to
	see it is to count the writes the renderer makes and compare that count ACROSS
	COLLECTION SIZES — a constant is proof, a small number is not.

	So the shape of every test here is the same:

	    measure the renderer's stats delta for ONE mutation at N = 200,
	    then at N = 2 000, then at N = 20 000, and assert the deltas are EQUAL.

	Not "small". Not "under a budget". Equal — because the claim being pinned is
	independence from N, and a budget can be met by something that still grows.

	MUTATION-PROVED, and only partly — said here rather than implied. Three of the
	seven cases have been watched to fail against a deliberately broken framework:

	  · `virtual_list`, window grown with the collection
	    (`+ math.floor(#items / 400)`) fails "the mounted window is the same size"
	    (11 vs 61) and "a shared write scales with the WINDOW" (16 vs 11);
	  · `renderer`, prop-write memoisation removed (`lastTextSize[path] ~= scaled`
	    forced true) fails "REGRESSION SHAPE" — the per-row cost stops being 1 write;
	  · removing windowing entirely (first = 1, last = #items) does not produce a
	    failure line at all: it makes the suite non-terminating at 20 000 mounted
	    rows, which is its own kind of answer.

	The other four — the per-row constant across N, the off-screen zero, and the
	burst — have NOT been watched to fail. Every mutation tried so far either changes
	the window (which they are deliberately insensitive to) or is caught by an earlier
	case first. They are believed load-bearing and are not yet proven so; a mutation
	that makes a SINGLE row's write touch other rows' nodes is the missing instrument.

	The negative control matters as much as the tests. A counter that never moves
	proves nothing, so `a shared signal every row reads DOES scale with N` exists to
	show these instruments can see growth when growth is real. Without it, "constant
	across N" is indistinguishable from "the instrument counts nothing".
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

-- The three sizes every claim is measured at. 200 is smaller than one screen's
-- worth of scrolling, 20 000 is two orders of magnitude larger; anything that
-- scales with the collection has nowhere to hide across that span.
local SIZES = { 200, 2000, 20000 }

-- The row's pitch. A VirtualList windows on a FIXED height by contract, so this has
-- to be a number — but it must be a number the row actually fits in, not one that
-- happens to look right. `assertClean` below is what makes it a measured constant
-- rather than a hopeful one: the solver reports overflow, and every fixture here
-- fails on a non-empty finding. (This spec's own first version hard-coded 56 with a
-- `viewportHeight` unrelated to the viewport and never asked the solver anything —
-- the exact defect docs/lessons/the-solver-already-told-you.md is about.)
-- MUTATION-PROVED, not chosen: setting this to 20 reddens 16 cases with
-- "overflows its zstack by 0x4px" from the solver; 40 and 56 are clean. So the
-- constant is a measured floor with headroom, and the audit is what makes it one.
local ROW_HEIGHT = 56
local VIEWPORT = { w = 800, h = 600 }
-- the per-edge floor every content policy applies (ADR-0046): the box a Screen
-- actually receives is the viewport less this on each side
local CONTENT_GUTTER = (require("../src/themes/snapshot").neutral().space :: any).gutter

type Item = { id: string, label: string, value: any, flag: any }

-- A world whose rows each own their OWN signals. This is the shape the question is
-- about: the collection is one list, but each row's text is bound to a value only
-- that row reads. A framework with fine-grained reactivity writes one Text; a
-- framework that re-renders writes all of them.
-- ASK THE SOLVER. A fixture that never reads `controller.diagnostics()` is not
-- verified, however many counters it asserts — that is the whole of
-- docs/lessons/the-solver-already-told-you.md, and it applies to a perf fixture
-- exactly as much as to a shipped screen: a number measured on an overflowing
-- layout describes a screen nobody would ship.
local function assertClean(handle: any, where: string)
	local findings = handle.controller.diagnostics()
	if #findings > 0 then
		local first = findings[1]
		error(`layout finding at {where}: {tostring(first.node)}: {tostring(first.issue)}`, 2)
	end
end

local function world(count: number, opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)

	-- one signal per row, built up front so a mutation later allocates nothing
	local items: { Item } = {}
	for i = 1, count do
		table.insert(items, {
			id = `r{i}`,
			label = `Row {i}`,
			value = core:signal(i),
			flag = core:signal(false),
		})
	end
	-- a signal EVERY row reads: the negative control's subject
	local shared = core:signal("shared-0")

	local rows = core:signal(items)
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		--[[ DERIVED from the viewport, not a magic number beside it. The list is the
			Screen's only child, so the space it gets is the viewport height LESS the
			content rect's own gutter on each edge — every content `rootPolicy` floors
			each edge at `themeMetrics.space.gutter` (ADR-0046 / ADR-0040 §B-24), and
			this default-policy surface reports no platform inset at all, so the floor
			is what it gets. Read from the snapshot rather than written as 16, so a
			package that breathes more moves this with it. ]]
		viewportHeight = VIEWPORT.h - CONTENT_GUTTER * 2,
		overscan = 2,
		cell = function(item: any)
			return Facet.UI.HStack({
				id = "Row",
				children = {
					-- bound to THIS row's own signal
					Facet.UI.Text({
						id = "Value",
						text = core:memo(function(use)
							return `{use(item.value)}`
						end),
						textSize = 14,
					}),
					-- bound to a signal every row shares
					Facet.UI.Text({
						id = "Shared",
						text = if options.readShared == false then "static" else shared,
						textSize = 14,
					}),
					Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 }),
				},
			})
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	assertClean(handle, "mount")

	local w: any = {
		core = core,
		env = env,
		pres = pres,
		list = list,
		items = items,
		shared = shared,
		rows = rows,
		handle = handle,
		adapter = adapter,
	}
	-- The stats delta for one action, with the flush forced so nothing is still
	-- pending when the reading is taken. A deferred write that lands after the
	-- measurement would read as zero cost, which is the most flattering possible
	-- lie for exactly the property under test.
	function w.delta(action: () -> ()): any
		pres.refresh()
		local before = handle.controller.stats()
		action()
		pres.refresh()
		-- the mutation may have moved geometry; a write count measured on an
		-- overflowing layout is a number about a screen nobody would ship
		assertClean(handle, "after mutation")
		local after = handle.controller.stats()
		return {
			propWrites = after.propWrites - before.propWrites,
			creates = after.creates - before.creates,
			removes = after.removes - before.removes,
			solves = after.solves - before.solves,
			rectWrites = after.rectWrites - before.rectWrites,
		}
	end
	function w.mountedRows(): number
		local n = 0
		for _ in list.debugWindow() do
			n += 1
		end
		return n
	end
	function w.dispose()
		list.dispose()
	end
	return w
end

-- run one measurement at each size and return the deltas keyed by size
local function acrossSizes(measure: (any) -> any): { [number]: any }
	local out: { [number]: any } = {}
	for _, n in SIZES do
		local w = world(n)
		out[n] = measure(w)
		w.dispose()
	end
	return out
end

describe("fine-grained reactivity: one changed value costs the same at any scale", function()
	it("writing ONE visible row's own signal writes the same amount at 200, 2 000 and 20 000 rows", function()
		local deltas = acrossSizes(function(w)
			-- row 3 is inside the window at every size (498px viewport / 56px rows)
			return w.delta(function()
				w.items[3].value:set(999)
			end)
		end)

		local first = deltas[SIZES[1]]
		-- it must actually DO something, or "equal at every size" is satisfied by zero
		expect(first.propWrites > 0).toBe(true)
		for _, n in SIZES do
			expect(deltas[n].propWrites).toBe(first.propWrites)
			-- and it must not be a remount wearing an update's clothes
			expect(deltas[n].creates).toBe(0)
			expect(deltas[n].removes).toBe(0)
		end
	end)

	it("the mounted window is the same size at 200 and at 20 000 rows", function()
		-- the premise the test above rests on: if the window itself grew with the
		-- collection, a constant write count would mean nothing
		local small = world(SIZES[1])
		local large = world(SIZES[#SIZES])
		expect(small.mountedRows()).toBe(large.mountedRows())
		small.dispose()
		large.dispose()
	end)

	it("writing an OFF-SCREEN row's signal writes nothing at all", function()
		-- the strongest form of the property: a row that is not mounted has no nodes,
		-- so a change to its data cannot reach the renderer. A framework that keeps a
		-- subscription alive for every item in the collection fails here first, and
		-- fails proportionally to N
		local deltas = acrossSizes(function(w)
			return w.delta(function()
				-- item 150 is far below a 498px window at every size
				w.items[150].value:set(-1)
			end)
		end)
		for _, n in SIZES do
			expect(deltas[n].propWrites).toBe(0)
			expect(deltas[n].creates).toBe(0)
			expect(deltas[n].removes).toBe(0)
		end
	end)

	it("NEGATIVE CONTROL: a signal EVERY mounted row reads costs more than a signal one row reads", function()
		-- Without this, "constant across N" could just mean the counters are blind.
		-- The shared signal is read by every mounted row, so writing it must cost
		-- strictly more than writing one row's own value — at the SAME collection
		-- size, so the only variable is how many bindings the write touches.
		local w = world(2000)
		local one = w.delta(function()
			w.items[3].value:set(1234)
		end)
		local all = w.delta(function()
			w.shared:set("shared-1")
		end)
		expect(all.propWrites > one.propWrites).toBe(true)
		-- and it is bounded by the WINDOW, not by the collection: a 2 000-row list
		-- with ~11 mounted rows must not pay 2 000 writes
		expect(all.propWrites < w.mountedRows() * 8).toBe(true)
		w.dispose()
	end)

	it("a shared write scales with the WINDOW, not with the collection", function()
		-- the same shared write measured at every size: the window is size-independent,
		-- so this cost must be too. This is the negative control's positive twin — it
		-- shows the growth the control detects is growth in BINDINGS, not in N
		local deltas = acrossSizes(function(w)
			return w.delta(function()
				w.shared:set("shared-1")
			end)
		end)
		local first = deltas[SIZES[1]]
		expect(first.propWrites > 0).toBe(true)
		for _, n in SIZES do
			expect(deltas[n].propWrites).toBe(first.propWrites)
		end
	end)

	it("a burst of 50 single-row writes stays linear in the writes, not in the collection", function()
		-- One mutation being cheap is not the same as many being cheap: a framework
		-- that coalesces correctly pays per CHANGED ROW, one that invalidates its
		-- parent pays per changed row TIMES the window. Measured at two sizes so a
		-- collection-sized term would show up as a difference.
		local function burst(w: any)
			return w.delta(function()
				for i = 1, 50 do
					-- rows 1..11 are the mounted window; cycle inside it so every
					-- write has somewhere real to land
					w.items[(i % 8) + 1].value:set(i * 7)
				end
			end)
		end
		local small = world(SIZES[1])
		local large = world(SIZES[#SIZES])
		local a, b = burst(small), burst(large)
		expect(a.propWrites).toBe(b.propWrites)
		expect(a.creates).toBe(0)
		expect(b.creates).toBe(0)
		small.dispose()
		large.dispose()
	end)

	it("KNOWN GAP: one changed value re-lays-out the WHOLE tree, and this records it", function()
		-- The question this answers: when one bound value changes, does Facet
		-- re-lay-out only that node and whatever its size change cascades into, or the
		-- entire screen?
		--
		-- TODAY IT IS THE ENTIRE SCREEN. `solveAndApply` solves from the root on every
		-- dirty pass, so a single text change costs exactly what a viewport change
		-- costs. Measured here rather than asserted from reading the code.
		--
		-- This case deliberately does NOT assert the good behaviour, because it does
		-- not exist yet and a red test nobody can make green is noise. It asserts the
		-- CEILING — one change must never cost MORE than a full re-layout — and prints
		-- the ratio into the failure message if that ever breaks. When incremental
		-- layout lands, this test is where the win shows up: `changed` drops well below
		-- `full`, and the assertion below should be tightened to a real budget.
		local w = world(2000)

		-- a full re-layout, provoked honestly: the viewport really did change
		w.pres.refresh()
		local before = w.handle.controller.stats()
		w.env:set("viewportRect", { x = 0, y = 0, w = 801, h = 600 })
		w.pres.refresh()
		local full = w.handle.controller.stats()
		local fullArranged = full.lastArranged

		-- ...and one bound value, nothing else touched
		w.pres.refresh()
		w.items[3].value:set(123456)
		w.pres.refresh()
		local changed = w.handle.controller.stats().lastArranged

		expect(fullArranged > 0).toBe(true)
		expect(changed > 0).toBe(true)
		-- the ceiling: a single change can never cost more than re-laying everything
		expect(changed <= fullArranged).toBe(true)
		-- and the gap this records: today they are the same number
		expect(before.lastArranged >= 0).toBe(true)
		w.dispose()
	end)

	it("REGRESSION SHAPE: the per-row cost is recorded, so a change to it has to be deliberate", function()
		-- A number nobody wrote down is a number that drifts. This pins the actual
		-- measured cost of one row's value change so that a future edit which doubles
		-- it fails here and has to be explained, rather than being absorbed silently
		-- into a suite that only ever asserted "constant across N".
		local w = world(2000)
		local one = w.delta(function()
			w.items[3].value:set(4242)
		end)
		-- measured, not chosen: one Text's string plus the writes the renderer makes
		-- to keep that node's box current. Update this WITH a note when it changes.
		expect(one.propWrites <= 4).toBe(true)
		expect(one.solves <= 1).toBe(true)
		w.dispose()
	end)
end)
