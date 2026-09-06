--[[ D1: THE PLAN VERDICT LIVES ON THE NODE LITERAL (Facet Plan D, 2026-09-06 —
	FacetBench §D1/§D2).

	THE DEFECT, MEASURED. `measure_facts.memoPlan` decides, per node, whether its
	measured size can read the offered HEIGHT (`PLAN_HEIGHT_FREE`), must be keyed on
	it (`PLAN_KEYED`), or is two literals and needs no memo at all (`PLAN_SKIP`). It
	was memoised in `ctx.memoPlans` — PER SOLVE — and for a `vstack` whose children
	are all height-free the verdict recurses into every child. So on every incremental
	solve of the arena's 5,127-node `battle_hud` it re-derived all 5,127 verdicts and
	allocated a 5,127-entry map: **0.768 ms and 303 KB of a 0.949 ms one-leaf class**,
	and invisible to every wrap-based profile because the solver binds the function at
	module load (FacetBench `tools/profile/lib_attr` now shims it BEFORE the solver is
	required; the column is `mf.memoPlan`).

	THE MECHANISM. The verdict is a pure function of `width`/`height`/`kind`/
	`textFit`/`shrinkWeight` and the CHILDREN's verdicts; nothing in `src/` writes any
	of those after `render/layout_node` constructs the literal; and `layout_node.build`
	rebuilds a FRESH literal for every node in the ANCESTOR-CLOSED dirty set. So the
	verdict is cached on the literal (`node.mPlan`) for the literal's life, and a node
	whose subtree changed is never the same table. `ctx.planVisits` counts the verdicts
	a solve had to COMPUTE, published as `stats().lastPlanVisits`.

	THE THREE CASES THIS FILE OWES:
	  1. the counter: a one-leaf text write on `deep_stack_scene` computes verdicts for
	     the dirty chain alone (read off the run), with `lastMeasured` UNMOVED beside
	     it and `solves=1` — the safety pair;
	  2. the exactness witness on the PRODUCTION path: a child's height flips
	     `fixed` → `fill` through a SIGNAL, and the root's verdict flips with it,
	     because the rebuild replaced every literal on the chain;
	  3. the NEGATIVE CONTROL: the one write the cache cannot see — a dim rewritten IN
	     PLACE on a built literal with no rebuild — leaves the root's verdict stale.
	     Recorded, not fixed: no production path makes that write, and a case that
	     stays green when the cache is removed would be a pin on nothing. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/deep_stack_scene")
local solver = require("../src/layout/solver")
local measure_facts = require("../src/layout/measure_facts")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local customFactory = require("../src/core/custom")

local ROWS = 1000

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

-- one drive, one string: the counter pair AND `solves`, in the idiom every counter
-- spec in this repo uses (a drive that solves zero times re-asserts the previous
-- solve's numbers, so `solves` is part of the pin rather than a side condition)
local function plansOf(s: any, drive: () -> ()): string
	local before = s.stats().solves
	drive()
	local st = s.stats()
	return `solves={st.solves - before} plans={st.lastPlanVisits} measured={st.lastMeasured} builds={st.lastNodeBuilds}`
end

describe("D1: the plan verdict is cached on the node literal", function()
	it("a text write on ONE leaf computes verdicts for the dirty chain alone (case 1)", function()
		local s = scene.new({ rows = ROWS })
		-- the first refresh after `initialRender` rebuilds nothing it can serve from;
		-- discarded, exactly as `measure_serve.spec` discards it
		s.text(500, "warm")
		--[[ READ OFF THE RUN. The build constructs four literals for a leaf text write
			— the screen root, the list, the dirty row and the dirty text — and those are
			the four verdicts computed: `plans == builds`, which is the whole claim. Every
			other node answers from its own `mPlan`. With the cache read disabled (the
			red arm, kept in the ledger) this reads `plans=3011`: the whole tree, every
			solve. `measured=5` is `measure_serve.spec`'s own pin for the same drive and
			MUST NOT MOVE. ]]
		expect(plansOf(s, function()
			s.text(500, "x")
		end)).toBe("solves=1 plans=4 measured=5 builds=4")
		-- a WIDTH write on the row: the row and its two ancestors are rebuilt; the
		-- row's two children are clean and keep their literals — and their verdicts.
		-- `measured=6` is the drive's own truth: the row, its two children at the
		-- new offer, and the chain above (`measure_serve.spec`'s width case)
		expect(plansOf(s, function()
			s.width(500, 40)
		end)).toBe("solves=1 plans=3 measured=6 builds=3")
		s.dispose()
	end)

	it("...and a NOOP refresh computes none", function()
		local s = scene.new({ rows = ROWS })
		s.text(500, "warm")
		s.text(500, "x")
		local st = s.stats()
		expect(`plans={st.lastPlanVisits}`).toBe("plans=4")
		s.controller.refresh()
		-- nothing dirty: the solve is skipped outright and the counter is the last
		-- solve's, which is the documented meaning of every `last*` field
		expect(`plans={s.stats().lastPlanVisits}`).toBe("plans=4")
		s.dispose()
	end)
end)

--[[ THE FLIP FIXTURE: `Screen > VStack(List) > 20 x HStack{ Text, Box(height = signal) }`.
	A `vstack` is `PLAN_HEIGHT_FREE` only while NO child on its vertical main axis
	declares a `fill` and every child's own verdict is height-free — so one Box whose
	height goes `fixed` → `fill` through a signal flips the row to `PLAN_KEYED` and the
	list with it. The verdicts are read by calling `memoPlan` on the layout root the
	solver was handed, captured off `solver.solve`. ]]
local function flipWorld()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
	local boxHeight = core:signal(px(10))
	local rows: { any } = {}
	for i = 1, 20 do
		-- an explicit content height: a stack child's default height is `fill`, which
		-- would make the list `keyed` before any flip and the witness a witness to nothing
		rows[i] = UI.HStack({
			id = `R{i}`,
			gap = 2,
			height = { type = "content" },
			children = {
				UI.Text({ id = "T", textSize = 12, text = `row {i}` }),
				UI.Box({ id = "Bx", width = px(20), height = if i == 5 then boxHeight else px(10) }),
			},
		})
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.VStack({ id = "List", gap = 1, width = fill(), height = { type = "content" }, children = rows }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
		translateHosts = true,
	})
	return { core = core, controller = controller, boxHeight = boxHeight }
end

-- by path suffix, not by kind: the screen root is itself a stack whose dims read the
-- viewport, so "the first vstack" would be the root and its verdict `keyed` on sight
local function findId(node: any, suffix: string): any
	if type(node.id) == "string" and string.sub(node.id, -#suffix) == suffix then
		return node
	end
	for _, c in node.children or {} do
		local hit = findId(c, suffix)
		if hit ~= nil then
			return hit
		end
	end
	return nil
end

local function verdictName(plan: number): string
	if plan == measure_facts.PLAN_HEIGHT_FREE then
		return "height-free"
	elseif plan == measure_facts.PLAN_SKIP then
		return "skip"
	end
	return "keyed"
end

-- the verdict of the LIST node in the layout root the last solve was handed, via a
-- fresh ctx so the count says how many verdicts that read had to compute
local function listVerdict(root: any): string
	local ctx = { planVisits = 0 }
	local list = findId(root, "/List")
	return `{verdictName(measure_facts.memoPlan(ctx, list))} computed={ctx.planVisits}`
end

describe("D1: the cache is exact on the production path, and the negative control says why", function()
	local captured: { root: any } = { root = nil }
	local function capturing(fn: () -> ())
		local real = solver.solve
		solver.solve = function(...)
			captured.root = (select(1, ...))
			return real(...)
		end
		local ok, err = pcall(fn)
		solver.solve = real
		if not ok then
			error(err, 0)
		end
	end

	it("a child height flipping fixed -> fill through a SIGNAL flips the list's verdict (case 2)", function()
		capturing(function()
			local w = flipWorld()
			w.controller.initialRender()
			--[[ A COLD SOLVE NEVER ASKS `memoPlan` (`measure` takes the uncached return
				when there is no store), so the first INCREMENTAL solve is the one that
				fills every literal on the tree — one warm write, discarded. ]]
			w.boxHeight:set(px(11))
			w.controller.refresh()
			local before = captured.root
			-- every verdict on the list's subtree is already on its literal: the read
			-- computes nothing, and the list is height-free
			expect(listVerdict(before)).toBe("height-free computed=0")
			w.boxHeight:set(fill())
			w.controller.refresh()
			local after = captured.root
			--[[ THE REBUILD IS THE MECHANISM. The Box, its row and the list are fresh
				literals (the dirty set is ancestor-closed), so the list's cached verdict
				went with the old table and the new one was computed on the solve — and
				it is `keyed`, because row 5 now declares a `fill` on the vertical axis. ]]
			expect(after ~= before).toBe(true)
			expect(listVerdict(after)).toBe("keyed computed=0")
			-- ...and the OLD literal still says what it said: a stale verdict on a
			-- table nobody solves against any more
			expect(listVerdict(before)).toBe("height-free computed=0")
			w.controller.dispose()
		end)
	end)

	it(
		"NEGATIVE CONTROL: a dim rewritten IN PLACE with no rebuild is the one write the cache cannot see (case 3)",
		function()
			capturing(function()
				local w = flipWorld()
				w.controller.initialRender()
				w.boxHeight:set(px(11))
				w.controller.refresh()
				local root = captured.root
				expect(listVerdict(root)).toBe("height-free computed=0")
				--[[ The write no production path makes: `layout_node.build` never mutates a
				literal it already handed out, it constructs a new one. Made here by hand
				on the built tree, the verdict cached on the list is STALE — which is the
				whole reason `mPlan` lives on the literal and not on the mounted node. ]]
				local list = findId(root, "/List")
				local row5 = list.children[5]
				local box = row5.children[2]
				box.height = fill()
				expect(listVerdict(root)).toBe("height-free computed=0")
				-- ...and clearing the cache along the chain is what recomputes it: the
				-- function itself is still pure, the cache is what was stale
				box.mPlan, row5.mPlan, list.mPlan = nil, nil, nil
				expect(listVerdict(root)).toBe("keyed computed=3")
				w.controller.dispose()
			end)
		end
	)
end)
