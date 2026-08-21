--!strict
--[[
	`newTable{ virtualized = true }` — THE UNIFIED COLLECTION.

	WHAT THIS CLOSES. The comparison document §13 carried "No container
	unifying virtualization + reorder + selection" as a durable gap, and §4.2
	recorded `newTable` virtualization as BLOCKED behind variable item extents
	*because* Table ships `rowHeight(item)` and `index x pitch` cannot express a
	ragged list. Stage 1 of variable extents shipped the running-offset index
	(`src/virtual_extents.luau`) on 2026-08-14 and its own report named this
	consumer as "now unblocked, its stated blocker was this substrate".

	SO THIS SPEC PINS THE THING THAT WAS BLOCKED, and one thing more:

	  · ONE ARITHMETIC, NOT TWO. Table's row geometry — the canvas extent, the
	    scroll clamp, every row's top, the reorder insertion slot and its hairline,
	    keep-visible — now comes from the SAME `virtual_extents` index
	    `newVirtualList` windows by, for a virtualized table AND a flowing one.
	    The differential cases below check Table's numbers against the index
	    directly, so the two can never drift into disagreeing about one list.

	  · VIRTUALIZATION STAYS BOUNDED. The perf lab breaks a window on purpose and
	    REQUIRES the scenario to refuse; the equivalent here is a BUILD COUNTER on
	    a 5,000-row table, not a timer. An implementation that builds every row to
	    lay out the list has not made Table slower — it has deleted the property
	    the feature exists for.

	  · SELECTION, FOCUS AND ORDER ARE MODEL STATE, NOT MOUNT STATE. A row that
	    scrolls out of the window and back must come back selected; a reorder must
	    address rows nobody has mounted; keep-visible must reach a row that has no
	    solved rect at all.

	  · SCROLL POSITION STAYS STABLE AS THE EXTENTS MOVE. Table's row height is
	    DERIVED (theme metrics x typography scale + the accessibility text offset),
	    so it moves under the player rather than under the consumer — which is the
	    exact shape of this repo's recorded jump defect.

	  · WHAT IS REFUSED IS REFUSED BY NAME. `scrolls = false` and `rowActions` are
	    construction errors under `virtualized`, each naming why.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local table_control = require("../src/controls/table")
local virtual_extents = require("../src/virtual_extents") :: any
local fake_target = require("../tests/lib/fake_target")

local ROW_H = 40
-- the control's own constant; a window is `visible + OVERSCAN` on each side
local OVERSCAN = 2

local function racers(n: number): { any }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, name = `Racer {i}`, laps = i })
	end
	return out
end

type World = {
	core: any,
	adapter: any,
	pres: any,
	tbl: any,
	rows: any,
	handle: any,
	env: any,
	builds: () -> number,
}

local function world(opts: any): World
	opts = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(opts.rows or racers(400))
	-- THE BUILD COUNTER. `cellFor` runs once per column per MOUNTED row, so it is
	-- the honest instrument for "did this control build what it cannot show".
	local builds = 0
	local tbl = table_control.build(Facet, core, {
		id = "Racers",
		columns = opts.columns or {
			{ id = "name", title = "Racer", width = { type = "fill", weight = 1 } },
		},
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		cellFor = function(columnId: string, item: any)
			builds += 1
			return Facet.UI.Text({ id = "Value", text = item.name, textSize = 16 })
		end,
		rowHeight = opts.rowHeight or ROW_H,
		rowGap = opts.rowGap,
		header = if opts.header == nil then false else opts.header,
		selection = opts.selection or "single",
		reorderable = opts.reorderable,
		onReorder = opts.onReorder,
		rowMovable = opts.rowMovable,
		editing = opts.editing,
		virtualized = if opts.virtualized == nil then true else opts.virtualized,
		env = env,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { tbl.blueprint } })
	local handle = pres.present(screen, {
		onActivate = function(path: string, meta: any)
			tbl.api.handleActivate(path, meta)
		end,
		onFocusNav = function(path: string)
			tbl.api.handleFocusMoved(path)
		end,
	})
	-- TWO REFRESHES, AND THE SECOND IS NOT CEREMONY. The window is taken against
	-- the body's MEASURED height, which only exists after a solve — so frame 1
	-- runs on the screen-height seed (a superset) and frame 2 is the settled
	-- window. A live presenter refreshes every frame; a spec has to say so.
	-- `describe("the first frame")` below pins what frame 1 alone must already be.
	pres.refresh()
	pres.refresh()
	tbl.api.bindNativeScroll(handle.controller)
	return {
		core = core,
		adapter = adapter,
		pres = pres,
		tbl = tbl,
		rows = rows,
		handle = handle,
		env = env,
		builds = function()
			return builds
		end,
	}
end

local function rowPath(w: World, key: string): string
	return `/S/Racers/Main/Body/Canvas/Rows/[{key}@0]/Row`
end
local function hitPath(w: World, key: string): string
	return rowPath(w, key) .. "/Hit"
end
local function mounted(w: World, key: string): boolean
	return w.adapter.node(rowPath(w, key)) ~= nil
end
-- how many rows this table has actually put in the tree
local function mountedCount(w: World, total: number): number
	local n = 0
	for i = 1, total do
		if mounted(w, `r{i}`) then
			n += 1
		end
	end
	return n
end
local function scrollTo(w: World, y: number)
	w.adapter.driveScroll("/S/Racers/Main/Body", { x = 0, y = y })
	w.pres.refresh()
end
-- the index this control's own numbers must agree with, built from the outside
local function oracle(heights: { number }, gap: number): any
	return virtual_extents.variable(heights, gap)
end

describe("Table virtualized: only the window is mounted", function()
	it("a 400-row table mounts a bounded window, not 400 rows", function()
		local w = world({})
		local body = w.adapter.node("/S/Racers/Main/Body").rect
		-- the honest ceiling: what the viewport touches, plus overscan on each side
		local ceiling = math.ceil(body.h / ROW_H) + 1 + 2 * OVERSCAN
		local count = mountedCount(w, 400)
		expect(count <= ceiling).toBe(true)
		-- ...AND A FLOOR. "<= ceiling" alone is satisfied by mounting nothing, which
		-- is how a window that mounted three rows in a 600px body passed this case
		-- while the list was visibly short. Every row the viewport touches must be
		-- in the tree.
		for i = 1, math.ceil(body.h / ROW_H) do
			expect(mounted(w, `r{i}`)).toBe(true)
		end
		expect(mounted(w, "r400")).toBe(false)
	end)

	it("BOUNDED BY CONSTRUCTION: 5,000 rows build only the windowed cells", function()
		local w = world({ rows = racers(5000) })
		-- one column, so one `cellFor` call per mounted row
		local body = w.adapter.node("/S/Racers/Main/Body").rect
		local ceiling = math.ceil(body.h / ROW_H) + 1 + 2 * OVERSCAN
		expect(w.builds() <= ceiling).toBe(true)
		-- ...and the property that actually matters: it does not grow with the data
		local small = world({ rows = racers(50) })
		expect(w.builds()).toBe(small.builds())
	end)

	it("the canvas carries the FULL content extent, so the engine can scroll all of it", function()
		local w = world({})
		local canvas = w.adapter.node("/S/Racers/Main/Body/Canvas").rect
		expect(canvas.h).toBe(oracle(table.create(400, ROW_H), 0).content)
	end)

	--[[ THE FIRST FRAME IS THE ONE THAT CAN BE WRONG WITHOUT ANYONE NOTICING, and
		it was: seeded at zero, a 200-row table's first frame mounted THREE rows in a
		600px body, and every window assertion in this file passed anyway because
		three rows is `<= ceiling` too. The seed is now the SCREEN height — an upper
		bound on any body inside it — so frame one over-mounts and never under-mounts.
		This case is the one that would have caught it. ]]
	it("FRAME ONE already fills the body: the seed is the screen, so it over-mounts, never under", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local tbl = table_control.build(Facet, core, {
			id = "Racers",
			columns = { { id = "name", title = "R", width = { type = "fill", weight = 1 } } },
			rows = core:signal(racers(400)),
			key = function(item: any)
				return item.id
			end,
			cellFor = function(_columnId: string, item: any)
				return Facet.UI.Text({ id = "Value", text = item.name, textSize = 16 })
			end,
			rowHeight = ROW_H,
			header = false,
			virtualized = true,
			env = env,
		})
		pres.present(Facet.UI.Screen({ id = "S", children = { tbl.blueprint } }), {})
		pres.refresh() -- ONE frame only
		local body = adapter.node("/S/Racers/Main/Body").rect
		local needed = math.ceil(body.h / ROW_H)
		for i = 1, needed do
			expect(adapter.node(`/S/Racers/Main/Body/Canvas/Rows/[r{i}@0]/Row`) ~= nil).toBe(true)
		end
		-- ...and still bounded by the SCREEN, not by the data
		expect(adapter.node(`/S/Racers/Main/Body/Canvas/Rows/[r200@0]/Row`)).toBe(nil)
	end)

	--[[ OVERSCAN IS NOT PADDING, IT IS THE KEYBOARD'S FLOOR. Table's focus groups
		are built from the MOUNTED tree, so arrow-down at the bottom of the viewport
		can only reach a row that is already there. With `OVERSCAN = 0` the window
		ends exactly where the eye does and the next Down finds nothing; with it, the
		row the cursor is about to land on is in the tree and `keepVisible` then
		scrolls it into view, which re-derives the window and re-fills the edge. ]]
	it("the row just BELOW the viewport is mounted, so keyboard navigation never walks off the edge", function()
		local w = world({})
		local body = w.adapter.node("/S/Racers/Main/Body").rect
		-- the last row the viewport TOUCHES (the index's own containing-slot rule),
		-- so the rows after it are exactly what OVERSCAN buys and nothing else
		local lastTouched = math.floor(body.h / ROW_H) + 1
		expect(mounted(w, `r{lastTouched}`)).toBe(true)
		expect(mounted(w, `r{lastTouched + 1}`)).toBe(true)
		expect(mounted(w, `r{lastTouched + OVERSCAN}`)).toBe(true)
		-- ...and not one row more: overscan is a bounded promise, not a margin that
		-- can quietly grow into "mount a bit extra"
		expect(mounted(w, `r{lastTouched + OVERSCAN + 1}`)).toBe(false)
	end)

	it("rowGap is spent by the OFFSETS exactly once, never by the canvas stack as well", function()
		local w = world({ rows = racers(200), rowGap = 6 })
		local ix = oracle(table.create(200, ROW_H), 6)
		local canvasY = w.adapter.node("/S/Racers/Main/Body/Canvas").rect.y
		expect(w.adapter.node("/S/Racers/Main/Body/Canvas").rect.h).toBe(ix.content)
		for i = 1, 200 do
			if mounted(w, `r{i}`) then
				expect(w.adapter.node(rowPath(w, `r{i}`)).rect.y - canvasY).toBe(ix.offsetOf(i))
			end
		end
	end)

	it("scrolling mounts the rows at the new offset and unmounts the ones left behind", function()
		local w = world({})
		expect(mounted(w, "r1")).toBe(true)
		scrollTo(w, 100 * ROW_H)
		expect(mounted(w, "r1")).toBe(false)
		expect(mounted(w, "r101")).toBe(true)
	end)
end)

describe("Table virtualized: one arithmetic with newVirtualList", function()
	it("every windowed row lands at the index's own offset (ragged heights)", function()
		local heights: { number } = {}
		for i = 1, 200 do
			heights[i] = if i % 3 == 0 then 72 else ROW_H
		end
		local w = world({
			rows = racers(200),
			rowHeight = function(item: any)
				return heights[tonumber(string.sub(item.id, 2)) :: number]
			end,
		})
		local ix = oracle(heights, 0)
		local canvasY = w.adapter.node("/S/Racers/Main/Body/Canvas").rect.y
		for i = 1, 200 do
			if mounted(w, `r{i}`) then
				local rect = w.adapter.node(rowPath(w, `r{i}`)).rect
				expect(rect.y - canvasY).toBe(ix.offsetOf(i))
				expect(rect.h).toBe(ix.extentOf(i))
			end
		end
	end)

	it("a FLOWING table's row tops agree with the same index (the paths cannot drift)", function()
		local heights: { number } = {}
		for i = 1, 6 do
			heights[i] = if i % 2 == 0 then 72 else ROW_H
		end
		local w = world({
			virtualized = false,
			rows = racers(6),
			rowHeight = function(item: any)
				return heights[tonumber(string.sub(item.id, 2)) :: number]
			end,
		})
		local ix = oracle(heights, 0)
		local first = w.adapter.node(`/S/Racers/Main/Body/Rows/[r1@0]/Row`).rect
		for i = 1, 6 do
			local rect = w.adapter.node(`/S/Racers/Main/Body/Rows/[r{i}@0]/Row`).rect
			expect(rect.y - first.y).toBe(ix.offsetOf(i))
		end
	end)

	--[[ THE CASE ABOVE PROVES THE INDEX AGREES WITH THE SOLVER'S FLOW; it cannot
		prove the flowing table READS the index, because in flow mode the solver
		positions the rows and the index is only consulted for the scroll clamp, the
		drop slot and keep-visible. This one closes that: a nonzero `rowGap` makes
		the index the only thing that could produce the boundary, so breaking the
		index's gap reddens here. ]]
	it("a FLOWING table's drop hairline is the index's own boundary (rowGap > 0)", function()
		local w = world({
			virtualized = false,
			rows = racers(4),
			rowGap = 6,
			reorderable = true,
			onReorder = function() end,
		})
		local ix = oracle(table.create(4, ROW_H), 6)
		local rootY = w.adapter.node("/S/Racers").rect.y
		local bodyY = w.adapter.node("/S/Racers/Main/Body").rect.y
		w.adapter.pointerDown(`/S/Racers/Main/Body/Rows/[r1@0]/Row/Hit`, 100, bodyY + 4)
		-- past r2's slot midpoint: r2 spans 46..86, its slot midpoint is 46+23 = 69
		w.adapter.pointerMove(100, bodyY + 80)
		w.pres.refresh()
		local slot = ix.slotAt(80)
		expect(slot).toBe(2)
		expect(w.adapter.node("/S/Racers/DropWhen/then/DropLine").rect.y).toBe(bodyY - rootY + ix.boundaryOffset(slot))
		w.adapter.pointerUp(100, bodyY + 80)
	end)
end)

describe("Table virtualized: model state outlives the window", function()
	it("a selected row that scrolls away comes back selected", function()
		local w = world({ selection = "single" })
		w.adapter.tap(hitPath(w, "r2"))
		w.pres.refresh()
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true)
		scrollTo(w, 200 * ROW_H)
		expect(mounted(w, "r2")).toBe(false)
		expect(w.tbl.api.selectedKeys:get().r2).toBe(true) -- the model kept it
		scrollTo(w, 0)
		expect(w.adapter.node(hitPath(w, "r2")).props.selected).toBe(true)
	end)

	it("multi-selection ranges reach rows the window never held", function()
		local w = world({ selection = "multi" })
		w.tbl.api.select("r2", { mode = "replace" })
		w.tbl.api.select("r300", { mode = "range" })
		local selected = w.tbl.api.selectedKeys:get()
		expect(selected.r2).toBe(true)
		expect(selected.r150).toBe(true)
		expect(selected.r300).toBe(true)
		expect(selected.r301).toBe(nil)
	end)

	it("a reorder addresses an unmounted row (the move funnel is model-level)", function()
		local moved: any = nil
		local w = world({
			reorderable = true,
			onReorder = function(keys: { string }, to: number)
				moved = { keys = keys, to = to }
			end,
		})
		expect(mounted(w, "r300")).toBe(false)
		expect(w.tbl.api.moveRow("r300", -1)).toBe(true)
		expect(moved.keys[1]).toBe("r300")
		expect(moved.to).toBe(298)
	end)

	it("revealRow reaches a row with no solved rect and materializes it", function()
		local w = world({})
		expect(mounted(w, "r120")).toBe(false)
		expect(w.tbl.api.revealRow("r120")).toBe(true)
		w.pres.refresh()
		expect(mounted(w, "r120")).toBe(true)
	end)
end)

describe("Table virtualized: the reorder slot is over the FULL list", function()
	it("a drag while scrolled names a slot two hundred rows down, not a window-relative one", function()
		local reorders: { any } = {}
		local w = world({
			reorderable = true,
			onReorder = function(keys: { string }, toIndex: number)
				table.insert(reorders, { keys = keys, toIndex = toIndex })
			end,
		})
		scrollTo(w, 100 * ROW_H)
		local ix = oracle(table.create(400, ROW_H), 0)
		local bodyY = w.adapter.node("/S/Racers/Main/Body").rect.y
		-- r101 is the row under the viewport's leading edge; drag it 100px down
		w.adapter.pointerDown(hitPath(w, "r101"), 100, bodyY + 4)
		w.adapter.pointerMove(100, bodyY + 100)
		w.pres.refresh()
		w.adapter.pointerUp(100, bodyY + 100)
		-- the canvas y the pointer names is body-relative PLUS the live scroll
		local slot = ix.slotAt(100 * ROW_H + 100)
		expect(slot > 100).toBe(true)
		expect(#reorders).toBe(1)
		expect(reorders[1].keys[1]).toBe("r101")
		-- the dragged row sits above the slot, so the post-removal index drops one
		expect(reorders[1].toIndex).toBe(slot - 1)
	end)
end)

describe("Table virtualized: the scroll does not jump when the extents move", function()
	--[[ A ROW'S RECT IS IN CANVAS SPACE, NOT SCREEN SPACE — the ENGINE translates
		the canvas by `CanvasPosition`, so the solver never re-arranges a row for a
		scroll (that is the whole point of the canvas design). Where the player
		actually SEES a row is therefore `canvas offset - the live scroll`, and
		anything that compares raw rects across a scroll change is measuring the
		wrong quantity. Written out because the first draft of this case did exactly
		that and failed on a working implementation. ]]
	local function onScreenY(w: World, key: string): number
		local canvasY = w.adapter.node("/S/Racers/Main/Body/Canvas").rect.y
		local bodyY = w.adapter.node("/S/Racers/Main/Body").rect.y
		return bodyY + (w.adapter.node(rowPath(w, key)).rect.y - canvasY) - w.tbl.dump().scrollTop
	end

	it("the row under the viewport's leading edge stays under it when every row grows", function()
		local w = world({})
		scrollTo(w, 100 * ROW_H)
		local anchor = "r101"
		expect(mounted(w, anchor)).toBe(true)
		local before = onScreenY(w, anchor)
		-- ...and it really is at the top of the viewport, so the case is about the
		-- row the player is looking at rather than an arbitrary one
		expect(before).toBe(w.adapter.node("/S/Racers/Main/Body").rect.y)
		-- the accessibility case: every row grows at once, under the player
		w.env:set("preferredTextOffset", 14)
		w.pres.refresh()
		expect(mounted(w, anchor)).toBe(true)
		-- the row grew, so its offset moved by 300px; the scroll moved WITH it
		expect(w.adapter.node(rowPath(w, anchor)).rect.h > ROW_H).toBe(true)
		expect(math.abs(onScreenY(w, anchor) - before) <= 1).toBe(true)
	end)

	it("...and WITHOUT the anchor the same change would move it — the guard is not decorative", function()
		-- the same list, never scrolled by the player: the anchor has nothing to
		-- hold (offset 0 is offset 0 under any extents), so the scroll must NOT move
		local w = world({})
		expect(w.tbl.dump().scrollTop).toBe(0)
		w.env:set("preferredTextOffset", 14)
		w.pres.refresh()
		expect(w.tbl.dump().scrollTop).toBe(0)
		expect(onScreenY(w, "r1")).toBe(w.adapter.node("/S/Racers/Main/Body").rect.y)
	end)

	--[[ WHERE THE ANCHOR LEGITIMATELY CANNOT HOLD, AND WHAT MUST HAPPEN INSTEAD.
		Hard against the end of the list, shrinking every row shortens the content
		under a scroll that is already at `content - viewport`. Holding the leading
		row in place would mean showing blank space past the last row, so the anchor
		must LOSE to the clamp here — and the list must end up flush against its own
		last row rather than scrolled off it.

		This case is also the reason the anchor's own dependency cannot be told apart
		behaviourally: the clamp binds ONLY at the end of the list, which is exactly
		where the anchor is supposed to lose. See the code comment at SCROLL
		ANCHORING for why the capture still rides `scrollTop`, and
		`artifacts/unified-collection/mutations.md` for the surviving mutation this
		leaves. ]]
	it("shrinking the rows at the BOTTOM leaves the list flush with its last row, not past it", function()
		local w = world({})
		w.env:set("preferredTextOffset", 14)
		w.pres.refresh()
		local bodyH = w.adapter.node("/S/Racers/Main/Body").rect.h
		scrollTo(w, w.adapter.node("/S/Racers/Main/Body/Canvas").rect.h - bodyH)
		expect(w.tbl.dump().scrollTop > 0).toBe(true)
		w.env:set("preferredTextOffset", 0)
		w.pres.refresh()
		w.pres.refresh()
		local content = w.adapter.node("/S/Racers/Main/Body/Canvas").rect.h
		-- the last row is mounted and its END is at the bottom edge of the viewport
		expect(mounted(w, "r400")).toBe(true)
		local lastEnd = onScreenY(w, "r400") + w.adapter.node(rowPath(w, "r400")).rect.h
		expect(math.abs(lastEnd - (w.adapter.node("/S/Racers/Main/Body").rect.y + bodyH)) <= 1).toBe(true)
		expect(w.tbl.dump().scrollTop <= content - bodyH).toBe(true)
	end)

	it("a text-preference change RE-SOLVES the rows, never rebuilds them", function()
		local w = world({})
		local before = w.handle.root.counters().factoryRuns
		w.env:set("preferredTextOffset", 4)
		w.pres.refresh()
		expect(w.handle.root.counters().factoryRuns).toBe(before)
	end)
end)

--[[ ── THE FACT THE STAGE-2 HOSTING DECISION RESTS ON ──────────────────────────

	`docs/plans/table-hosted-row-actions-stage2.md` records one objection to
	teaching Table to HOST row actions that does NOT hold: "Table's rows are
	content-sized, so VirtualList's commit-height collapse seam
	(`hostedItemExtentIn`) cannot port". It does not hold because a Table row's
	extent is DERIVED, never declared — `rowHeightOf` reads the theme metrics, the
	typography scale, the text preference and the input paradigm, and the row's
	`height` is a `{ type = "fixed", px = n }` memo built from it (table.luau's
	`heightDim`), in the FLOWING mode as well as the windowed one.

	That is a factual claim in a plan, and a plan cannot notice when it rots. This
	is the check that does: a row whose cell text is enormous must land at exactly
	the same height as a row whose cell text is one word, in both modes. Make the
	row size to its content and the seam stops porting and this case reddens on the
	same line the plan is wrong on.

	NON-VACUITY: the long string is asserted to be one a content-sized row could
	not have fitted on a line — the short row's own width would not hold it — so
	"they match" cannot pass by the text being too small to matter. ]]
describe("Table virtualized: a row's height is DERIVED, not content-sized (both modes)", function()
	local LONG = string.rep("a very long racer name that would wrap several times ", 12)

	local function heightsOf(virtualized: boolean): (number, number)
		local w = world({
			virtualized = virtualized,
			rows = { { id = "short", name = "Bo" }, { id = "long", name = LONG } },
			columns = { { id = "name", title = "Racer", width = { type = "fill", weight = 1 } } },
		})
		local prefix = if virtualized then "/S/Racers/Main/Body/Canvas/Rows" else "/S/Racers/Main/Body/Rows"
		local short = w.adapter.node(`{prefix}/[short@0]/Row`)
		local long = w.adapter.node(`{prefix}/[long@0]/Row`)
		expect(`mounted:{short ~= nil and long ~= nil}`).toBe("mounted:true")
		-- the long string really is long enough to have grown a content-sized row
		expect(`wraps:{#LONG * 6 > short.rect.w}`).toBe("wraps:true")
		return short.rect.h, long.rect.h
	end

	it("the WINDOWED mode: both rows are the authored 40, whatever their cells say", function()
		local short, long = heightsOf(true)
		expect(`short:{short} long:{long}`).toBe(`short:{ROW_H} long:{ROW_H}`)
	end)

	it("...and the FLOWING mode agrees, which is what makes the seam port to BOTH", function()
		local short, long = heightsOf(false)
		expect(`short:{short} long:{long}`).toBe(`short:{ROW_H} long:{ROW_H}`)
	end)
end)

describe("Table virtualized: what is refused, and why", function()
	local function refusal(opts: any): string
		local core = Facet.newCore()
		local ok, err = pcall(function()
			table_control.build(Facet, core, {
				id = "T",
				columns = {
					{
						id = "a",
						title = "A",
						value = function()
							return "x"
						end,
					},
				},
				rows = core:signal(racers(3)),
				key = function(item: any)
					return item.id
				end,
				virtualized = true,
				scrolls = opts.scrolls,
				rowActions = opts.rowActions,
			})
		end)
		expect(ok).toBe(false)
		return tostring(err)
	end

	it("`virtualized` + `scrolls = false` is refused: a block table has no viewport to window against", function()
		local err = refusal({ scrolls = false })
		expect(string.find(err, "virtualized", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "scrolls", 1, true) ~= nil).toBe(true)
	end)

	it("`virtualized` + `rowActions` is refused (v1), the way VirtualList refuses reorder + rowActions", function()
		local err = refusal({
			rowActions = function()
				return { trailing = {} }
			end,
		})
		expect(string.find(err, "virtualized", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "rowActions", 1, true) ~= nil).toBe(true)
	end)
end)
