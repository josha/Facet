--!strict
--[[ A GUTTER MAY BE A THEME TOKEN — `newVirtualList.rowGap`, `newVirtualGrid.rowGap`
	and `newVirtualGrid.gap`, on the contract `newTable.rowGap` has carried since
	2026-08-06.

	THE GAP THIS CLOSES (purity audit §5, and it is the `vlistGap` bug itself).
	`newTable.rowGap` takes "a theme metric name ('xs'..'xl' or a dotted path)"
	because the gap is used in ARITHMETIC and a name that reached `cum += height +
	rowGap` used to throw. The two virtualized collections do that arithmetic too
	and refused a string outright — and `VirtualGrid.gap` refused even a `Readable`.
	So a consumer who wanted a theme-tracking gutter on a virtualized collection had
	exactly ONE legal route: hand-write a memo that reads the live snapshot and
	hands back pixels. `controls/row_actions.luau`'s `vlistGap()` was that memo, and
	it is the precedent this whole round is about: the framework required the
	boilerplate the precedent was written for.

	WHAT THIS SPEC PINS:

	  · the THREE FORMS on all three fields — a number, a theme metric name (space
	    step or dotted path), and a `Readable` of either;
	  · VALUE IDENTITY at the neutral package: the token form and the number it
	    resolves to produce the same arithmetic, to the pixel, on the content
	    extent and the window;
	  · a name that resolves NOWHERE is REFUSED and names itself — the one place
	    this deliberately diverges from `newTable`, which falls back to 0 and so
	    turns `rowGap = "6"` into no gutter at all (constitution §4: an unknown
	    value is an authoring mistake, never a silent no-op);
	  · the answer is LIVE — a theme swap under a mounted list moves the gutter
	    with no rebuild, which is the whole reason a name beats a number.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local virtual_grid = require("../src/controls/virtual_grid")
local themeSnapshot = require("../src/themes/snapshot")
local surfaceEnv = require("../src/env/surface_env")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = table.create(n)
	for i = 1, n do
		rows[i] = { id = `r{i}`, label = `Row {i}` }
	end
	return rows
end

local function newList(core: any, opts: any): any
	return virtual_list.build(Facet, core, {
		id = opts.id or "VL",
		rows = opts.rows,
		key = function(item: any)
			return item.id
		end,
		itemExtent = opts.itemExtent or 40,
		rowGap = opts.rowGap,
		viewportExtent = opts.viewportExtent or 200,
		env = opts.env,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

local function newGrid(core: any, opts: any): any
	return virtual_grid.build(Facet, core, {
		id = opts.id or "VG",
		items = opts.items,
		key = function(item: any)
			return item.id
		end,
		columns = opts.columns or 3,
		itemExtent = opts.itemExtent or 40,
		rowGap = opts.rowGap,
		gap = opts.gap,
		viewportExtent = opts.viewportExtent or 200,
		env = opts.env,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

-- the neutral package's own numbers, read rather than copied: a literal here
-- would pin this spec to today's theme instead of to the resolution.
local NEUTRAL = themeSnapshot.neutral()
local XS = themeSnapshot.resolveNumber(NEUTRAL, "xs") :: number
local TABLE_ROW_GAP = themeSnapshot.resolveNumber(NEUTRAL, "controls.table.rowGap") :: number

describe("an AMBIGUOUS core is refused, not resolved against neutral", function()
	--[[ TWO DIFFERENT NILS (fix round 1, finding H). `surfaceEnv.find` answers nil
		both for "nothing published" — a headless mount, a legal caller that degrades
		to the neutral package — and for AMBIGUOUS, meaning this core carries more
		than one live environment. Collapsing them meant a themed gutter silently
		resolved against neutral on a core where the framework could not tell which
		surface the control belonged to, and `viewportExtent = "auto"` seeded its
		first window from a screen it could not name. That is the framework guessing,
		and refuse-don't-guess is the standing rule; `surfaceEnv.resolve` already
		spells the message for every control that adopts it, so it is CALLED rather
		than restated. ]]
	local function twoSurfaces(): any
		local core = Facet.newCore()
		for _ = 1, 2 do
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
			surfaceEnv.publish(core, env)
		end
		return core
	end

	it("a NAMED gutter on an ambiguous core refuses, and the message names the way out", function()
		local core = twoSurfaces()
		local ok, err = pcall(function()
			newList(core, { rows = core:signal(makeRows(4)), rowGap = "xs" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "MORE THAN ONE environment", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "newVirtualList", 1, true) ~= nil).toBe(true)
	end)

	it('...and so does `viewportExtent = "auto"`, whose seed is a screen it cannot name', function()
		local core = twoSurfaces()
		expect(pcall(function()
			newList(core, { rows = core:signal(makeRows(4)), viewportExtent = "auto" })
		end)).toBe(false)
		local gridCore = twoSurfaces()
		expect(pcall(function()
			newGrid(gridCore, { items = gridCore:signal(makeRows(9)), viewportExtent = "auto" })
		end)).toBe(false)
	end)

	it("a build that needs NO environment is still built on an ambiguous core", function()
		--[[ THE NARROWING, and it is what stops this from being a new refusal on a
			shape that worked yesterday: a plain numeric list asks the environment
			nothing, so an ambiguous core is none of its business. Without this case
			the three above would pass just as happily against a control that refused
			every ambiguous core outright. ]]
		local core = twoSurfaces()
		local list = newList(core, { rows = core:signal(makeRows(4)), rowGap = 6, viewportExtent = 200 })
		expect(list.dump().rowGap).toBe(6)
		list.dispose()
	end)

	it("NOTHING published is still the headless case, and still resolves against neutral", function()
		-- the other nil, unchanged: a name on a core with no environment at all is a
		-- legal headless mount and answers from the neutral package
		local core = Facet.newCore()
		local list = newList(core, { rows = core:signal(makeRows(4)), rowGap = "xs" })
		expect(list.dump().rowGap).toBe(XS)
		list.dispose()
	end)
end)

describe("a virtualized gutter takes a theme metric name", function()
	it("VirtualList.rowGap resolves a space step, and the arithmetic is the number's", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(8))
		local named = newList(core, { rows = rows, rowGap = "xs" })
		local numeric = newList(core, { rows = rows, rowGap = XS, id = "VL2" })
		expect(named.dump().rowGap).toBe(XS)
		-- VALUE IDENTITY, not just an equal gutter: the content extent is what every
		-- offset, clamp and window boundary is derived from
		expect(named.dump().contentExtent).toBe(numeric.dump().contentExtent)
		named.dispose()
		numeric.dispose()
	end)

	it("...and a DOTTED PATH into the metrics, exactly as newTable spells it", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local list = newList(core, { rows = rows, rowGap = "controls.table.rowGap" })
		expect(list.dump().rowGap).toBe(TABLE_ROW_GAP)
		list.dispose()
	end)

	it("VirtualGrid.rowGap and VirtualGrid.gap both take one", function()
		local core = Facet.newCore()
		local items = core:signal(makeRows(30))
		local grid = newGrid(core, { items = items, rowGap = "xs", gap = "controls.table.rowGap" })
		local d = grid.dump()
		expect(`{d.rowGap}|{d.gap}`).toBe(`{XS}|{TABLE_ROW_GAP}`)
		grid.dispose()
	end)

	it("VirtualGrid.gap takes a Readable — the field that refused even that", function()
		local core = Facet.newCore()
		local items = core:signal(makeRows(30))
		local gap = core:signal(6)
		local grid = newGrid(core, { items = items, gap = gap })
		expect(grid.dump().gap).toBe(6)
		gap:set(10)
		expect(grid.dump().gap).toBe(10)
		grid.dispose()
	end)

	it("a name that resolves NOWHERE is refused, and names itself", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local ok, err = pcall(function()
			newList(core, { rows = rows, rowGap = "6" })
		end)
		expect(ok).toBe(false)
		-- the message has to carry the value, or the author is hunting a field
		expect(string.find(tostring(err), '"6"', 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "rowGap", 1, true) ~= nil).toBe(true)
		-- ...and the same refusal on the grid's two fields
		local items = core:signal(makeRows(9))
		expect(pcall(function()
			newGrid(core, { items = items, rowGap = "nope" })
		end)).toBe(false)
		expect(pcall(function()
			newGrid(core, { items = items, gap = "nope" })
		end)).toBe(false)
	end)

	it("a negative number is still refused — widening the type widened nothing else", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		expect(pcall(function()
			newList(core, { rows = rows, rowGap = -1 })
		end)).toBe(false)
		local items = core:signal(makeRows(9))
		expect(pcall(function()
			newGrid(core, { items = items, gap = -2 })
		end)).toBe(false)
	end)

	it("the gutter is LIVE: a theme swap moves it with no rebuild", function()
		--[[ THE WHOLE REASON A NAME BEATS A NUMBER. The list is built once, against
			an environment whose `themeMetrics` then changes underneath it — exactly
			what a runtime package swap does — and both the reported gutter and the
			content extent it feeds move without the control being reconstructed. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		local wide = themeSnapshot.neutral()
		local narrow = themeSnapshot.neutral()
		-- a package that spends a different space step is the realistic swap; the
		-- table is rebuilt rather than mutated so the two snapshots stay distinct
		narrow = table.clone(narrow)
		narrow.space = table.clone(narrow.space)
		narrow.space.xs = XS * 2
		env:set("themeMetrics", wide)
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, rowGap = "xs", env = env })
		local before = list.dump()
		expect(before.rowGap).toBe(XS)
		env:set("themeMetrics", narrow)
		local after = list.dump()
		expect(after.rowGap).toBe(XS * 2)
		expect(after.contentExtent - before.contentExtent).toBe(7 * XS)
		list.dispose()
	end)
end)
