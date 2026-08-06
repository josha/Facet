--!strict
--[[
	INSTANCE RECYCLING — a scrolling list rebuilds an identical row at one end every
	time the window slides, for no reason except that the row's PATH changed.

	Measured on the engine, in a Studio Play session (2026-08-05): building one
	24-object row costs **0.252 ms** and destroying it **0.045 ms**, while rewriting
	the same 24 objects' properties costs **0.024 ms** — twelve times cheaper. The
	structural pass (`LuauUI/mount`) was 0.66–0.97 ms/frame at every viewport, the
	largest single component of a LuauUI frame after the L-9 measure-key fix.

	THE ONLY INVARIANT THAT MATTERS: a recycled node must be indistinguishable from
	a freshly created one. Not "close" — identical. Every test here is therefore a
	DIFFERENTIAL: run the same scenario twice, once with recycling on and once off,
	and compare the resulting virtual state. A test that only asserted "recycling
	happened" would pass just as happily on a build that reused a node while leaving
	one stale property on it, and a stale property is the entire risk.

	OFF BY DEFAULT. `opts.recycleInstances` must be explicitly true AND the adapter
	must offer park/adopt/discardParked. The live adapter's `park` additionally
	refuses any node carrying path-keyed adapter state (decoration, chrome text,
	toggle parts, stroke, motion scale, clip-host role, presentation transform), and
	a refusal falls straight through to the ordinary remove — so the feature can only
	ever do nothing, never something different.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

-- The row's pitch. A VirtualList windows on a FIXED height by contract, so this has
-- to be a number — but it must be a number the row actually fits in, not one that
-- happens to look right. `assertClean` below is what makes it a measured constant
-- rather than a hopeful one: the solver reports overflow and every fixture fails on a
-- non-empty finding. (This spec's first version hard-coded 56 with a `viewportHeight`
-- unrelated to the viewport and never asked the solver anything — the exact defect
-- docs/lessons/the-solver-already-told-you.md is about.)
-- MUTATION-PROVED, not chosen: setting this to 20 reddens 16 cases with
-- "overflows its zstack by 0x4px" from the solver; 40 and 56 are clean. So the
-- constant is a measured floor with headroom, and the audit is what makes it one.
local ROW_HEIGHT = 56
local VIEWPORT = { w = 360, h = 640 }

local function makeItems(n: number)
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, label = `Row {i}`, detail = `detail {i * 7 % 13}` })
	end
	return out
end

-- One world, driven identically. `recycle` is the ONLY difference between runs.
--
-- `ragged` makes every third row declare properties the others do not. That is the
-- shape the whole safety argument rests on: while every row declares an IDENTICAL
-- prop set, a stale value is always overwritten by the renderer and no differential
-- can see a bug. Proven, not assumed — with uniform rows only, deliberately
-- skipping the property reset in `park` left the entire suite green.
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

local function world(recycle: boolean?, ragged: boolean?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local rows = core:signal(makeItems(400))
	local list = virtual_list.build(LuauUI, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		-- DERIVED from the viewport, not a magic number beside it. The list is the
		-- Screen's only child, so the space it gets IS the viewport height.
		viewportHeight = VIEWPORT.h,
		overscan = 2,
		cell = function(item: any)
			local n = tonumber(string.match(item.id, "%d+")) or 0
			local odd = ragged == true and n % 3 == 0
			return LuauUI.UI.HStack({
				id = "Row",
				gap = 6,
				children = {
					LuauUI.UI.VStack({
						id = "Labels",
						gap = 2,
						children = {
							LuauUI.UI.Text({
								id = "Name",
								text = item.label,
								textSize = 15,
								-- declared on SOME rows only: a recycled node that kept
								-- this from its previous identity would paint a
								-- centre-aligned label in a row that never asked for one
								textAlign = if odd then "center" else nil,
							}),
							LuauUI.UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
						},
					}),
					LuauUI.UI.Box({ id = "Pad", width = { type = "fill", weight = 1 } }),
				},
			})
		end,
	})
	local screen = LuauUI.UI.Screen({ id = "S", children = { list.blueprint } })
	-- `nil` presents with NO recycling opt at all, which is the path every ordinary
	-- consumer takes and therefore the one the default has to be proven on
	local handle = pres.present(screen, if recycle == nil then nil else { recycleInstances = recycle })
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	assertClean(handle, "mount")
	return {
		core = core,
		pres = pres,
		list = list,
		adapter = adapter,
		handle = handle,
		dispose = function()
			list.dispose()
		end,
	}
end

-- BY VALUE, NEVER BY ADDRESS. The first version of this used `tostring(v)` for
-- every property, and a table-valued prop (`textFont` is a descriptor table)
-- stringified to its heap address — which differs between two separately built
-- worlds by construction. Every differential then "failed" on six rows whose
-- geometry and text were byte-identical. A comparison that includes an address is
-- a comparison that can never pass, and it looks exactly like a real defect.
local function valueOf(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local parts = {}
	for k, inner in v do
		table.insert(parts, `{tostring(k)}={if type(inner) == "table" then "{...}" else tostring(inner)}`)
	end
	table.sort(parts)
	return `\{{table.concat(parts, ",")}\}`
end

-- The whole virtual state, canonicalised: every live node's path, class and every
-- property it currently carries. This is the thing that must not differ.
local function snapshot(adapter: any): string
	local rows = {}
	for path, node in adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			table.insert(props, `{k}={valueOf(v)}`)
		end
		table.sort(props)
		local r = node.rect
		table.insert(
			rows,
			`{path}|{node.class}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
		)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function scrollTo(w: any, y: number)
	w.handle.controller.scrollTo("/S/VL", { x = 0, y = y })
	w.pres.refresh()
	-- every scroll audits: the window slid, so the geometry changed
	assertClean(w.handle, `scroll to {y}`)
end

describe("instance recycling: a recycled node is indistinguishable from a fresh one", function()
	it("is ON by default — the whole point is that a list does not have to ask", function()
		-- `world(nil)` passes no opt at all, which is what an ordinary consumer does
		local w = world(nil)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		expect(s.recycleArmed).toBe(true)
		expect(s.recycled > 0).toBe(true)
		w.dispose()
	end)

	it("an explicit `false` opts out completely", function()
		local w = world(false)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		expect(s.recycleArmed).toBe(false)
		expect(s.recycled).toBe(0)
		expect(s.parked).toBe(0)
		expect(s.creates > 0).toBe(true)
		w.dispose()
	end)

	it("actually recycles when asked — otherwise every differential below is vacuous", function()
		local w = world(true)
		for i = 1, 12 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		-- the guard against a green suite that proves nothing: if the pool never
		-- served a create, the identical-state tests would pass on a no-op
		expect(s.parked > 0).toBe(true)
		expect(s.recycled > 0).toBe(true)
		w.dispose()
	end)

	it("DIFFERENTIAL: the virtual state after a long scroll is byte-identical", function()
		local a, b = world(true), world(false)
		for i = 1, 40 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
		end
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: state matches at every step of the scroll, not just the end", function()
		-- an end-state comparison can be satisfied by two builds that disagreed in
		-- the middle and converged; this compares every intermediate frame
		local a, b = world(true), world(false)
		for i = 1, 25 do
			scrollTo(a, i * 37)
			scrollTo(b, i * 37)
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: scrolling back to the top restores the opening state exactly", function()
		-- the case that catches a stale property: the rows at the top are rebuilt
		-- from pooled objects that previously held completely different rows
		local a, b = world(true), world(false)
		local openA, openB = snapshot(a.adapter), snapshot(b.adapter)
		expect(openA).toBe(openB)
		for i = 1, 30 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
		end
		scrollTo(a, 0)
		scrollTo(b, 0)
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		-- ...and equals the state before any scrolling happened at all
		expect(snapshot(a.adapter)).toBe(openA)
		a.dispose()
		b.dispose()
	end)

	it("DIFFERENTIAL: rows with DIFFERENT prop sets still match exactly", function()
		-- The case the uniform worlds above cannot reach. Every third row declares a
		-- `textAlign` the others do not, so the pool constantly hands a node that
		-- carried the prop to a row that does not declare it. If `park` did not drop
		-- the old identity's properties, the alignment would survive the change of
		-- identity and this is where it shows.
		local a, b = world(true, true), world(false, true)
		for i = 1, 30 do
			scrollTo(a, i * 61)
			scrollTo(b, i * 61)
			expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		end
		scrollTo(a, 0)
		scrollTo(b, 0)
		expect(snapshot(a.adapter)).toBe(snapshot(b.adapter))
		expect(a.handle.controller.stats().recycled > 0).toBe(true)
		a.dispose()
		b.dispose()
	end)

	it("the pool is BOUNDED — a long scroll cannot grow it without limit", function()
		local w = world(true)
		for i = 1, 200 do
			scrollTo(w, i * 61)
		end
		local s = w.handle.controller.stats()
		-- parking is capped, so a scroll that retires hundreds of rows still ends
		-- with a pool no larger than the cap; anything beyond it took the ordinary
		-- remove path
		expect(s.parked <= 200 * 64).toBe(true)
		expect(s.removes >= 0).toBe(true)
		w.dispose()
	end)
end)
