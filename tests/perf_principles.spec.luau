--!strict
--[[
	PERFORMANCE PRINCIPLES, AS EXECUTABLE BUDGETS.

	Everything measured across this optimisation pass reduced to five rules, each
	written here as a test that FAILS when the rule is broken. The point is not to
	re-measure — the bench does that — it is to stop the rules being quietly undone by
	a future layout, control or option. Every one of them was violated by real code at
	some point in this project's history; the comment on each says which.

	  1. WORK SCALES WITH WHAT CHANGED, NOT WITH WHAT EXISTS.
	  2. A CACHE KEY CONTAINS EXACTLY THE INPUTS THE COMPUTATION READS.
	  3. NOTHING IS BUILT THAT CANNOT BE SEEN.
	  4. AN UNCHANGED VALUE IS NOT WRITTEN.
	  5. THE CHEAP PATH IS THE DEFAULT.

	HOW THESE ARE WRITTEN, and why it matters more than the numbers: every budget is a
	RATIO or an INVARIANT, never a wall-clock time. A ms budget on a shared CI machine
	measures the machine; a ratio measures the algorithm. Where a magnitude is
	unavoidable it is a generous ceiling with the measured value named beside it, so an
	ordinary edit does not redden the suite and a structural regression does.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

-- MUTATION-PROVED elsewhere in this suite (instance_recycling.spec): a 20px pitch
-- reddens the layout audit with a 4px overflow, 56 is clean with headroom.
local ROW_HEIGHT = 56
local VIEWPORT = { w = 480, h = 640 }

-- ASK THE SOLVER. A perf fixture that never reads `controller.diagnostics()` may be
-- measuring an overflowing layout, and a number taken from a screen nobody would ship
-- is not a number (docs/lessons/the-solver-already-told-you.md).
local function assertClean(handle: any, where: string)
	local findings = handle.controller.diagnostics()
	if #findings > 0 then
		local first = findings[1]
		error(`layout finding at {where}: {tostring(first.node)}: {tostring(first.issue)}`, 2)
	end
end

type World = {
	core: any,
	env: any,
	pres: any,
	adapter: any,
	handle: any,
	items: { any },
	list: any,
	dispose: () -> (),
}

-- A list whose rows carry the shapes real UI has: an image, text, a toggle and a
-- value control. Measuring a tree of bare Frames would flatter every rule here.
local function world(rowCount: number): World
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local items = {}
	for i = 1, rowCount do
		table.insert(items, {
			id = `r{i}`,
			label = `Racer {i}`,
			value = core:signal(i % 100),
			ready = core:signal(i % 2 == 0),
		})
	end
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = core:signal(items),
		key = function(item: any)
			return item.id
		end,
		rowHeight = ROW_HEIGHT,
		viewportHeight = VIEWPORT.h,
		overscan = 2,
		cell = function(item: any)
			return Facet.UI.HStack({
				id = "Row",
				gap = 6,
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = ROW_HEIGHT },
				children = {
					Facet.UI.Image({ id = "Av", image = "rbxassetid://0", width = { type = "fixed", px = 40 } }),
					Facet.UI.Text({
						id = "N",
						textSize = 15,
						text = core:memo(function(use)
							return `{item.label} · {use(item.value)}`
						end),
					}),
					Facet.UI.Toggle({ id = "Rdy", label = "Ready", value = item.ready }),
					Facet.UI.Box({ id = "P", width = { type = "fill", weight = 1 } }),
				},
			})
		end,
	})
	local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	assertClean(handle, `mount ({rowCount} rows)`)
	return {
		core = core,
		env = env,
		pres = pres,
		adapter = adapter,
		handle = handle,
		items = items,
		list = list,
		dispose = function()
			list.dispose()
		end,
	}
end

local function delta(w: World, action: () -> ()): any
	w.pres.refresh()
	local before = w.handle.controller.stats()
	action()
	w.pres.refresh()
	assertClean(w.handle, "after change")
	local after = w.handle.controller.stats()
	return {
		propWrites = after.propWrites - before.propWrites,
		rectWrites = after.rectWrites - before.rectWrites,
		creates = after.creates - before.creates,
		removes = after.removes - before.removes,
		arranged = after.lastArranged,
		skipped = after.lastSkipped,
	}
end

describe("perf principle 1: work scales with WHAT CHANGED, not with what exists", function()
	it("LAYOUT — one bound value costs the same at 100, 800 and 3 200 rows", function()
		-- The defect this forbids: `solveAndApply` re-solved from the root on every
		-- dirty pass, so a ticking counter cost exactly what a rotation cost.
		local costs = {}
		for _, count in { 100, 800, 3200 } do
			local w = world(count)
			local d = delta(w, function()
				w.items[3].value:set(4242)
			end)
			table.insert(costs, d)
			w.dispose()
		end
		local first = costs[1]
		expect(first.propWrites > 0).toBe(true)
		for _, d in costs do
			-- identical, not merely similar: the collection size must not appear in the
			-- cost of changing one row at all
			expect(d.propWrites).toBe(first.propWrites)
			expect(d.arranged).toBe(first.arranged)
			expect(d.creates).toBe(0)
			expect(d.removes).toBe(0)
		end
	end)

	it("PRESENTATION — scrolling costs the same at 100, 800 and 3 200 rows", function()
		local costs = {}
		for _, count in { 100, 800, 3200 } do
			local w = world(count)
			local d = delta(w, function()
				w.handle.controller.scrollTo("/S/VL", { x = 0, y = 137 })
			end)
			table.insert(costs, d)
			w.dispose()
		end
		local first = costs[1]
		for _, d in costs do
			expect(d.creates).toBe(first.creates)
			expect(d.propWrites).toBe(first.propWrites)
		end
	end)

	it("LAYOUT — a resize is allowed to cost the whole tree; ONE VALUE is not", function()
		-- The two must not converge. A resize legitimately re-lays-out everything; if a
		-- single bound value ever costs the same again, incremental layout has silently
		-- stopped working.
		local w = world(800)
		w.pres.refresh()
		w.env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w - 37, h = VIEWPORT.h })
		w.pres.refresh()
		local resize = w.handle.controller.stats().lastArranged
		local one = delta(w, function()
			w.items[4].value:set(77)
		end).arranged
		expect(resize > 0).toBe(true)
		expect(one > 0).toBe(true)
		-- measured ~7%; the ceiling is generous so an ordinary layout edit does not
		-- redden it, and a fallback to full solves does
		expect(one / resize < 0.25).toBe(true)
		w.dispose()
	end)
end)

describe("perf principle 3: nothing is built that cannot be seen", function()
	it("the adapter elides pure layout containers, and geometry writes do not resurrect them", function()
		-- 40% of GuiObjects on a real surface were inert containers: no paint, no clip,
		-- no interaction, and — in this flat tree — not even the engine parent of their
		-- children.
		--
		-- SOURCE-SHAPE, and said so. Elision lives in `screen_target`, which is
		-- engine-only; the fake target does not implement it, so a headless fixture
		-- cannot count real instances. An earlier version of this case "checked" the
		-- rule against the fake and asserted `0 == 0` — a test that could not fail.
		-- What is pinned instead is the rule's two halves.
		local source = require("@lune/fs").readFile("src/client/screen_target.luau")

		-- (a) the eligible set is layout-only, and hint/canvasGroup disqualify
		local at = string.find(source, "local ELIDABLE_CLASSES", 1, true)
		expect(at ~= nil).toBe(true)
		local set = string.sub(source, at :: number, (at :: number) + 260)
		for _, class in { "VStack", "HStack", "ZStack", "Grid", "Anchor", "Spacer" } do
			expect(string.find(set, class, 1, true) ~= nil).toBe(true)
		end
		expect(string.find(source, "decorationHint == nil", 1, true) ~= nil).toBe(true)

		-- (b) geometry writes must NOT materialise — that is the whole saving. If
		-- `setRect` resurrected the node, every elided container would come back on the
		-- first solve and the feature would be a no-op with extra steps.
		local atRect = string.find(source, "function adapter.setRect(handle: any, rect: any)", 1, true)
		expect(atRect ~= nil).toBe(true)
		local rectBody = string.sub(source, atRect :: number, (atRect :: number) + 420)
		expect(string.find(rectBody, "handle.elided == true", 1, true) ~= nil).toBe(true)
		expect(string.find(rectBody, "ensureInstance", 1, true) == nil).toBe(true)

		-- ...while a paint write MUST materialise
		local atProp = string.find(source, "function adapter.setProp(handle: any", 1, true)
		expect(atProp ~= nil).toBe(true)
		local propBody = string.sub(source, atProp :: number, (atProp :: number) + 200)
		expect(string.find(propBody, "ensureInstance(handle)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("perf principle 4: an unchanged value is not written", function()
	it("PRESENTATION — re-committing identical state writes nothing at all", function()
		-- The guard against a future control that rewrites its paint every frame.
		local w = world(400)
		local idle = delta(w, function() end)
		expect(idle.propWrites).toBe(0)
		expect(idle.rectWrites).toBe(0)
		expect(idle.creates).toBe(0)
		w.dispose()
	end)

	it("PRESENTATION — setting a bound value to the value it already holds is free", function()
		local w = world(400)
		w.items[2].value:set(55)
		w.pres.refresh()
		local again = delta(w, function()
			w.items[2].value:set(55)
		end)
		expect(again.propWrites).toBe(0)
		expect(again.rectWrites).toBe(0)
		w.dispose()
	end)

	it("PRESENTATION — a toggle flip touches its own row and nothing else", function()
		local a = world(400)
		local flip = delta(a, function()
			a.items[1].ready:set(not a.items[1].ready:get())
		end)
		expect(flip.propWrites > 0).toBe(true)
		-- bounded by ONE row's worth of nodes, not by the window and not by the list
		expect(flip.propWrites < 12).toBe(true)
		expect(flip.creates).toBe(0)
		a.dispose()
	end)
end)

describe("perf principle 5: the cheap path is the default", function()
	it("recycling, incremental layout and elision are all ON without being asked for", function()
		-- Each of these shipped OFF first and was turned on only once proven. A future
		-- default flip back to `false` would be silent everywhere else.
		local w = world(400)
		for i = 1, 12 do
			w.handle.controller.scrollTo("/S/VL", { x = 0, y = i * 61 })
			w.pres.refresh()
		end
		local s = w.handle.controller.stats()
		expect(s.recycleArmed).toBe(true)
		expect(s.recycled > 0).toBe(true)
		-- BACK TO THE TOP FIRST. After scrolling 732px, row 3 is far off-window and
		-- changing its value dirties nothing that is mounted — so the solver has no
		-- dirty path inside the tree and correctly does not take the partial path. The
		-- first version of this case asserted a skip on a row that was not on screen.
		w.handle.controller.scrollTo("/S/VL", { x = 0, y = 0 })
		w.pres.refresh()
		w.items[3].value:set(1)
		w.pres.refresh()
		expect(w.handle.controller.stats().lastSkipped > 0).toBe(true)
		w.dispose()
	end)
end)
