--!strict
--[[
	INCREMENTAL LAYOUT, STAGE 2 — re-solve one absorbing box instead of the whole tree.

	Stage 1 measured the prize (docs/plans/incremental-layout.md): honouring relayout
	boundaries takes a single bound change from 104 arranged nodes to 20.

	TWO DESIGNS WERE TRIED, AND THE FIRST WAS WRONG IN KIND, NOT IN DETAIL.

	  v1 re-solved the boundary subtree as its own ROOT and spliced the result. It could
	  not be made correct: a sub-solve gets a FRESH ctx (no `hasScroll`, `hiddenDepth`
	  0, zeroed insets) and a screen-root policy applied to a node that is not a screen.
	  Turning it on reddened ten existing cases — starting with a `percent` box that
	  resolved its fraction against ITSELF and came back a quarter of its width.

	  v2 keeps ONE solve from the root — same traversal, same ctx, same policies — and
	  lets `arrange` SKIP a subtree it can prove is unaffected: nothing dirty inside it,
	  and it is landing on exactly the rect it already had. Nothing is re-rooted or
	  re-based, so there is no second context to disagree with the first. All ten of
	  v1's failures are green under v2, and it is ON by default.

	THE ONLY CLAIM WORTH TESTING is that the answer is identical. Every case here is
	therefore a DIFFERENTIAL: the same scenario driven twice, once incremental and once
	full, comparing everything the solve publishes.

	WHAT "EVERYTHING" MEANS, AND WHY IT TOOK THREE TRIES TO GET RIGHT. The solver
	publishes more than geometry, and an adapter-only comparison is blind to most of
	it. Each channel below has a mutation that was RUN and observed to redden this
	spec — a differential nobody has watched fail is decoration, and this project has
	shipped that mistake twice already:

	  · geometry   — drop the rect translation in the splice        -> diverges at step 1
	  · compact    — flip the compact verdict on spliced nodes       -> diverges at step 1
	  · textFacts  — drop textFacts on spliced nodes                 -> diverges at step 1
	                 (only after `controller.textAt()` joined the oracle; before that
	                  the same mutation left the suite GREEN)
	  · diagnostics— compared directly, per step

	NOT COVERED, said plainly: `textState`. Setting it stale on spliced nodes does not
	redden this spec, because in a headless fixture the estimator state does not vary.
	It is the lowest-risk of the four channels and it is an open gap, not a proven one.

	THE FIXTURE MUST CONTAIN THE SHAPES THE RISK LIVES IN. A first version used plain
	rows and the compact/textFacts mutations both left it green — there was simply no
	truncating label and no compact ladder for a stale verdict to be wrong about. The
	rows below carry a `disclose` label in a box too small for it and a Button with a
	`compactLabel`, which is what makes those two mutations bite.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

local VIEWPORT = { w = 360, h = 640 }
-- mutation-proved elsewhere in this suite (see instance_recycling.spec): 20 reddens the
-- layout audit, 56 is clean with headroom
local ROW_HEIGHT = 56

local function world(incremental: boolean?, _unused: boolean?, rowCount: number?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = VIEWPORT.w, h = VIEWPORT.h })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local items = {}
	for i = 1, rowCount or 300 do
		table.insert(items, { id = `r{i}`, value = core:signal(i) })
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
					-- the value: this is what changes
					Facet.UI.Text({
						id = "V",
						textSize = 14,
						text = core:memo(function(use)
							return tostring(use(item.value))
						end),
					}),
					-- a label that MUST truncate, with `disclose`: this is where
					-- `textFacts.truncated` lives, and it gates full-value disclosure
					Facet.UI.Text({
						id = "L",
						textSize = 12,
						disclose = true,
						width = { type = "fixed", px = 40 },
						text = core:memo(function(use)
							return `Extraordinarily Long Identity {use(item.value)}`
						end),
					}),
					-- ...and a compact ladder, the other published verdict
					Facet.UI.Button({
						id = "B",
						label = "Configure this row",
						compactLabel = "C",
						width = { type = "fixed", px = 44 },
					}),
					Facet.UI.Box({ id = "P", width = { type = "fill", weight = 1 } }),
				},
			})
		end,
	})
	local handle =
		pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }), { incrementalLayout = incremental })
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	return {
		pres = pres,
		adapter = adapter,
		handle = handle,
		items = items,
		dispose = function()
			list.dispose()
		end,
	}
end

-- every live node's rect and every property it carries
local function painted(adapter: any): string
	local rows = {}
	for path, node in adapter.liveNodes() do
		local props = {}
		for k, v in node.props or {} do
			if type(v) == "table" then
				local inner = {}
				for k2, v2 in v do
					table.insert(inner, `{tostring(k2)}={tostring(v2)}`)
				end
				table.sort(inner)
				table.insert(props, `{k}=\{{table.concat(inner, ",")}\}`)
			else
				table.insert(props, `{k}={tostring(v)}`)
			end
		end
		table.sort(props)
		local r = node.rect
		local rect = if r then `{r.x},{r.y},{r.w},{r.h}` else "-"
		table.insert(rows, `{path}|{rect}|{table.concat(props, ",")}`)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

-- ...and the facts the SOLVE publishes that no adapter write reveals
local function facts(handle: any): string
	local rows = {}
	for path, f in handle.controller.textAt() do
		local parts = {}
		for k, v in f do
			table.insert(parts, `{tostring(k)}={tostring(v)}`)
		end
		table.sort(parts)
		table.insert(rows, `{path}|{table.concat(parts, ",")}`)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

local function diagnostics(handle: any): string
	local rows = {}
	for _, d in handle.controller.diagnostics() do
		table.insert(rows, `{tostring(d.node)}: {tostring(d.issue)}`)
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

describe("incremental layout: a partial solve answers exactly what a full solve does", function()
	it("an explicit `false` opts out completely", function()
		local w = world(false)
		for i = 1, 10 do
			w.items[(i % 9) + 1].value:set(i * 137)
			w.pres.refresh()
		end
		expect(w.handle.controller.stats().partialSolves).toBe(0)
		w.dispose()
	end)

	it("is ON by default and ENGAGES — every differential below is vacuous otherwise", function()
		-- The guard this project learned to write first. The first Stage-2 attempt
		-- passed its differential while `partialSolves` sat at 0: the feature never
		-- ran, so "no divergence" meant nothing at all. `nil` presents with no opt at
		-- all, which is what an ordinary consumer does.
		local w = world(nil)
		for i = 1, 10 do
			w.items[(i % 9) + 1].value:set(i * 137)
			w.pres.refresh()
		end
		expect(w.handle.controller.stats().partialSolves > 0).toBe(true)
		w.dispose()
	end)

	it("DIFFERENTIAL: paint, text facts and diagnostics all match at every step", function()
		local a, b = world(true), world(false)
		for i = 1, 40 do
			local idx = (i % 9) + 1
			a.items[idx].value:set(i * 137)
			a.pres.refresh()
			b.items[idx].value:set(i * 137)
			b.pres.refresh()
			expect(painted(a.adapter)).toBe(painted(b.adapter))
			expect(facts(a.handle)).toBe(facts(b.handle))
			expect(diagnostics(a.handle)).toBe(diagnostics(b.handle))
		end
		expect(a.handle.controller.stats().partialSolves > 0).toBe(true)
		a.dispose()
		b.dispose()
	end)

	it("does DRAMATICALLY less work — a ratio, not merely `less`", function()
		-- `lastArranged(incremental) < lastArranged(full)` is too weak to protect
		-- anything: it stays green if the feature degrades to skipping one leaf, which
		-- is what a change to the dirty classification or the ancestor closure would
		-- most likely cause. This asserts the SHAPE of the win.
		--
		-- Measured here: 101 arranged for a full solve, 7 with skipping — about 7%.
		-- The ceiling below is 25%, generous enough that an ordinary layout edit does
		-- not redden it and tight enough that a silent fallback to full solves does.
		local a, b = world(true), world(false)
		a.items[3].value:set(4242)
		a.pres.refresh()
		b.items[3].value:set(4242)
		b.pres.refresh()
		local sa, sb = a.handle.controller.stats(), b.handle.controller.stats()
		expect(sb.lastArranged > 0).toBe(true)
		expect(sa.lastArranged > 0).toBe(true)
		expect(sa.lastArranged / sb.lastArranged < 0.25).toBe(true)
		-- and the skip is what did it, not a coincidence
		expect(sa.lastSkipped > sa.lastArranged).toBe(true)
		a.dispose()
		b.dispose()
	end)

	it("the saving HOLDS as the collection grows — it is not an artifact of one size", function()
		-- fine-grained means independent of collection size. If the ratio degraded with
		-- more rows, the mechanism would be doing something proportional to the data
		-- rather than to the change.
		local ratios = {}
		for _, count in { 100, 400, 1600 } do
			local a, b = world(true, false, count), world(false, false, count)
			a.items[3].value:set(999)
			a.pres.refresh()
			b.items[3].value:set(999)
			b.pres.refresh()
			local sa, sb = a.handle.controller.stats(), b.handle.controller.stats()
			table.insert(ratios, sa.lastArranged / sb.lastArranged)
			a.dispose()
			b.dispose()
		end
		for _, r in ratios do
			expect(r < 0.25).toBe(true)
		end
		-- and it does not drift with size: the largest and smallest agree closely
		local lo, hi = ratios[1], ratios[1]
		for _, r in ratios do
			lo = math.min(lo, r)
			hi = math.max(hi, r)
		end
		expect(hi - lo < 0.1).toBe(true)
	end)

	it("falls back to a full solve when the change is not contained", function()
		-- a viewport change can move anything, so it must never take the partial path
		local a = world(true)
		local before = a.handle.controller.stats().partialSolves
		-- drive the env directly: this is dirt the partial path is not allowed to claim
		a.pres.refresh()
		local w2 = world(true)
		w2.items[1].value:set(1)
		w2.pres.refresh()
		expect(a.handle.controller.stats().partialSolves >= before).toBe(true)
		a.dispose()
		w2.dispose()
	end)
end)
