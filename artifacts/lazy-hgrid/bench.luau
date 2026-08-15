--!strict
-- HEADLESS LUNE BENCH — evidence class: REGRESSION SIGNAL ONLY (UI-PERF-002).
-- Lune is not the engine; nothing here is a device claim or a Studio number.
-- Order-swapped ABBA rounds, and the A/A control band is reported BEFORE any delta.
--
-- THE HORIZONTAL TWIN of `artifacts/lazy-grid/bench.luau`, arm for arm, so the two
-- axes are comparable rather than merely each plausible. ARM A is the lazy grid on
-- `axis = "x"`; ARM B is what a consumer builds today without it — a sideways
-- ScrollView over a plain `UI.Grid { flow = "column" }` holding every cell.
local LuauUI = require("../../src") :: any
local virtual_grid = require("../../src/controls/virtual_grid")
local fake_target = require("../../tests/lib/fake_target")
local UI = LuauUI.UI

local function items(n: number)
	local out = table.create(n)
	for i = 1, n do
		out[i] = { id = `i{i}`, label = `Item {i}` }
	end
	return out
end

local function cellBp(item: any)
	return UI.Text({ id = "L", text = item.label, textSize = 14 })
end

-- ARM A: the lazy grid. ARM B: a plain UI.Grid of every cell inside a ScrollView
-- (what a consumer builds today, and what the parity doc calls the eager half).
local function mountLazy(n: number)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local grid = virtual_grid.build(LuauUI, core, {
		id = "VG",
		items = core:signal(items(n)),
		key = function(it: any)
			return it.id
		end,
		axis = "x",
		columns = 4,
		itemExtent = 40,
		viewportExtent = 400,
		cell = cellBp,
	})
	-- the cross axis of a horizontal grid is its HEIGHT and it fills, so the strip
	-- is wrapped in a box of the height under test (the control refuses `width`)
	local handle = pres.present(UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.VStack({
				id = "Wrap",
				padding = 0,
				gap = 0,
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = 320 },
				children = { grid.blueprint },
			}),
		},
	}))
	pres.refresh()
	grid.bindNativeScroll(handle.controller)
	return { pres = pres, grid = grid, adapter = adapter }
end

local function mountEager(n: number)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local children = {}
	for _, it in items(n) do
		table.insert(
			children,
			UI.ZStack({
				id = `C{it.id}`,
				width = { type = "fixed", px = 40 },
				height = { type = "fill", weight = 1 },
				children = { cellBp(it) },
			})
		)
	end
	local bp = UI.ScrollView({
		id = "EG",
		axis = "x",
		padding = 0,
		gap = 0,
		clipChildren = true,
		width = { type = "fixed", px = 400 },
		height = { type = "fixed", px = 320 },
		children = {
			UI.Grid({
				id = "Band",
				flow = "column",
				columns = 4,
				height = { type = "fill", weight = 1 },
				children = children,
			}),
		},
	})
	local handle = pres.present(UI.Screen({ id = "S", padding = 0, gap = 0, children = { bp } }))
	pres.refresh()
	return { pres = pres, adapter = adapter, handle = handle }
end

local function timeIt(fn: () -> ()): number
	local t0 = os.clock()
	fn()
	return (os.clock() - t0) * 1000
end

local function stats(xs: { number })
	table.sort(xs)
	local sum = 0
	for _, x in xs do
		sum += x
	end
	return { median = xs[math.ceil(#xs / 2)], mean = sum / #xs, min = xs[1], max = xs[#xs] }
end

local function spread(a: number, b: number): number
	return math.abs(a - b) / math.max(a, b) * 100
end

print("evidence class: HEADLESS LUNE (regression signal). Not Studio, not a device.\n")

-- ── the A/A control band, stated FIRST ────────────────────────────────────
local REPS = 9
for _, n in { 1000, 10000 } do
	local a1, a2 = {}, {}
	for r = 1, REPS do
		-- ABBA: A1 A2 A2 A1 within each rep, so drift cancels
		table.insert(
			a1,
			timeIt(function()
				mountLazy(n)
			end)
		)
		table.insert(
			a2,
			timeIt(function()
				mountLazy(n)
			end)
		)
		table.insert(
			a2,
			timeIt(function()
				mountLazy(n)
			end)
		)
		table.insert(
			a1,
			timeIt(function()
				mountLazy(n)
			end)
		)
	end
	local s1, s2 = stats(a1), stats(a2)
	print(
		string.format(
			"A/A CONTROL  mount lazy hgrid N=%d   arm1 median %.2f ms, arm2 median %.2f ms  ->  control spread %.2f%%",
			n,
			s1.median,
			s2.median,
			spread(s1.median, s2.median)
		)
	)
end
print("")

-- ── the delta ─────────────────────────────────────────────────────────────
for _, n in { 1000, 10000 } do
	local lazy, eager = {}, {}
	for r = 1, REPS do
		table.insert(
			lazy,
			timeIt(function()
				mountLazy(n)
			end)
		)
		table.insert(
			eager,
			timeIt(function()
				mountEager(n)
			end)
		)
		table.insert(
			eager,
			timeIt(function()
				mountEager(n)
			end)
		)
		table.insert(
			lazy,
			timeIt(function()
				mountLazy(n)
			end)
		)
	end
	local sl, se = stats(lazy), stats(eager)
	print(
		string.format(
			"MOUNT  N=%-6d  lazy %.2f ms   eager %.2f ms   -> %.1fx",
			n,
			sl.median,
			se.median,
			se.median / sl.median
		)
	)
end
print("")

-- ── the laziness claim itself: a scroll frame is FLAT in N ────────────────
for _, n in { 1000, 10000, 40000 } do
	local w = mountLazy(n)
	local frames = {}
	for r = 1, 40 do
		local x = (r % 20) * 40
		table.insert(
			frames,
			timeIt(function()
				w.adapter.driveScroll("/S/Wrap/VG", { x = x, y = 0 })
				w.pres.refresh()
			end)
		)
	end
	local s = stats(frames)
	print(string.format("SCROLL FRAME  N=%-6d  median %.3f ms  (mean %.3f, max %.3f)", n, s.median, s.mean, s.max))
end
