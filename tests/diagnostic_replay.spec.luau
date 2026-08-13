--!strict
--[[
	THE PLACEMENT AUDIT UNDER INCREMENTAL LAYOUT — RED-TEAM Milestone 1, HIGH 2.

	`solve` replays the previous solve's diagnostics for any finding whose
	`d.node` sits in `ctx.skippedIds`. Every diagnostic in the solver is filed
	under the node that FILES it — except one. An `inertPlacement` finding is
	filed by the PARENT (`arrange` walks the parent and reads
	`node.inertPlacement`) and NAMED after the offending CHILD.

	So when the parent is walked (something dirty is inside it) and the audited
	child's own subtree is skipped (clean, same rect), the finding is filed
	FRESH by the walked parent AND replayed for the skipped child. Measured on an
	HStack with one inert `alignH` child and a reactive-width sibling, at the
	shipped default:

	    initial 1 -> 2 -> 3 -> 4 ...

	one more copy per layout-dirty frame, forever, with each solve copying the
	whole list forward: O(n^2) work, a real table leak on any long-lived surface
	carrying one inert placement prop, and every count-based assertion on
	`controller.diagnostics()` made frame-dependent.

	THE FIX: gate the replay on the FILING node being skipped, not the named one.
	`inertPlacement` findings are stamped with their filing parent's id at build
	time (`solver.auditPlacement` already receives it), and the replay reads
	`d.filedBy or d.node`. Both halves are tested here — the duplicate must stop,
	and a finding whose FILING parent really is skipped must still be replayed.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function px(n: number)
	return { type = "fixed", px = n }
end

-- every `inertPlacement` finding in the channel, as "<node>|<prop>" strings.
-- Counted, never deduplicated — duplication is the whole subject.
local function placementFindings(controller: any): { string }
	local out: { string } = {}
	for _, d in controller.diagnostics() do
		local prop = string.match(d.issue, "^`([%a]+)` is a placement prop")
		if prop ~= nil then
			table.insert(out, `{d.node}|{prop}`)
		end
	end
	table.sort(out)
	return out
end

-- THE FIXTURE, built to reach BOTH sides of the gate from one tree:
--
--   VStack S
--     HStack Row
--       Inert     — carries `alignH`, which an hstack's arrange never reads.
--                   The audited child. Its rect never changes.
--       Reactive  — width bound to `wide`. Dirtying it forces `Row` to be
--                   WALKED while `Inert` is skipped  -> the duplication path.
--     Tail        — height bound to `tall`, and it sits BELOW `Row`, so
--                   dirtying it never moves `Row`'s rect: the whole `Row`
--                   subtree is skipped  -> the replay path.
local function world(incremental: boolean)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local wide = core:signal(false)
	local tall = core:signal(false)
	local reactiveWidth = core:memo(function(use: any)
		return px(if use(wide) then 120 else 60)
	end)
	local tailHeight = core:memo(function(use: any)
		return px(if use(tall) then 90 else 30)
	end)
	local bp = UI.VStack({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.HStack({
				id = "Row",
				padding = 0,
				gap = 0,
				children = {
					UI.Box({ id = "Inert", width = px(80), height = px(40), alignH = "end" }),
					UI.Box({ id = "Reactive", width = reactiveWidth, height = px(40) }),
				},
			}),
			UI.Box({ id = "Tail", width = px(100), height = tailHeight }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
	})
	controller.initialRender()
	return { core = core, controller = controller, wide = wide, tall = tall, adapter = adapter }
end

describe("the placement audit does not duplicate under incremental layout (HIGH 2)", function()
	it("stays at exactly one finding across many layout-dirty frames", function()
		local w = world(true)
		expect(#placementFindings(w.controller)).toBe(1)

		w.wide:set(true)
		w.controller.refresh()
		-- THE REUSE PATH MUST ACTUALLY BE ENGAGING or this case proves nothing:
		-- some subtree was skipped this solve. Asserted, not assumed.
		expect(w.controller.stats().lastSkipped > 0).toBe(true)
		expect(#placementFindings(w.controller)).toBe(1)

		w.wide:set(false)
		w.controller.refresh()
		expect(#placementFindings(w.controller)).toBe(1)

		-- ten more flips. Pre-fix this read 12: one more copy every frame.
		for i = 1, 10 do
			w.wide:set(i % 2 == 1)
			w.controller.refresh()
		end
		expect(#placementFindings(w.controller)).toBe(1)
		-- ...and it is still the RIGHT finding, named after the offending CHILD
		expect(placementFindings(w.controller)[1]).toBe("/S/Row/Inert|alignH")
	end)

	it("a finding whose FILING parent is skipped is still replayed", function()
		-- the other half of the gate, and the half a careless fix breaks: dirty
		-- `Tail`, which is outside `Row` and below it. `Row`'s whole subtree is
		-- clean and lands on the rect it already had, so `Row` is skipped and files
		-- nothing this solve. Dropping the replay here would silence
		-- `controller.diagnostics()` for exactly the parts of the screen that did
		-- not change.
		local w = world(true)
		expect(#placementFindings(w.controller)).toBe(1)
		local rowBefore = w.adapter.node("/S/Row").rect
		w.tall:set(true)
		w.controller.refresh()
		local rowAfter = w.adapter.node("/S/Row").rect
		-- the precondition: `Row` really did land on the same rect
		expect(rowAfter.x).toBe(rowBefore.x)
		expect(rowAfter.y).toBe(rowBefore.y)
		expect(rowAfter.w).toBe(rowBefore.w)
		expect(rowAfter.h).toBe(rowBefore.h)
		expect(w.controller.stats().lastSkipped > 0).toBe(true)
		expect(placementFindings(w.controller)).toEqual({ "/S/Row/Inert|alignH" })
	end)

	it("the incremental answer is identical to the full-solve oracle, finding for finding", function()
		-- the differential, over BOTH dirtying routes interleaved. A fix that
		-- simply deleted the replay passes the first case and fails here; a fix
		-- that keeps duplicating fails here too. Only a solver that skips nothing
		-- can tell those apart.
		local inc = world(true)
		local full = world(false)
		local steps: { { wide: boolean, tall: boolean } } = {
			{ wide = true, tall = false },
			{ wide = true, tall = true },
			{ wide = false, tall = true },
			{ wide = false, tall = false },
			{ wide = true, tall = true },
			{ wide = false, tall = true },
		}
		expect(placementFindings(inc.controller)).toEqual(placementFindings(full.controller))
		for _, step in steps do
			for _, w in { inc, full } do
				w.wide:set(step.wide)
				w.tall:set(step.tall)
				w.controller.refresh()
			end
			expect(placementFindings(inc.controller)).toEqual(placementFindings(full.controller))
			expect(#placementFindings(inc.controller)).toBe(1)
		end
	end)
end)
