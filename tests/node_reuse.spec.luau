--!strict
--[[
	THE CROSS-SOLVE LAYOUT-NODE STORE (perf campaign P3) — the demonstrator and its
	oracle.

	WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, `battle_hud`).
	`renderer.solveAndApply` called `toLayoutNode(root.node, …)` on EVERY solve and
	rebuilt the whole mounted-tree -> `solver.Node` translation from scratch: one table
	and one `textOf` closure per node, and every theme token re-resolved through
	`themeSnapshot.resolveDim`/`resolveSides`/`resolveNumber`/`resolveSize`/
	`effectiveTypeRole`. `tools/profile/probe` variant D, the build alone:
	**0.51 ms / 666 kb at S (525 nodes), 2.66 / 2,609 at M, 6.22 / 6,507 at L** — paid
	whether one leaf moved or nothing did, and 1.28 kb per node of the step's
	allocation. `tools/profile/residual` attributes 3.6 ms/step of the L figure to the
	theme-token resolution inside it.

	THE FIX is a per-mounted-node slate that outlives the solve, so a subtree nothing
	dirtied is RETURNED rather than rebuilt. `render/layout_node.luau` carries the four
	axes; the two that are this file's subject are **axis 2** (the renderer's dirty set,
	closed over ancestors, of EVERY class) and **axis 3** (the applied theme snapshot,
	the typography scale and the preferred-text offset, folded into one stamp).

	THE DEMONSTRATOR (D-P3) is `controller.stats().lastNodeBuilds`, a counter on the
	one place a `solver.Node` is constructed. It is a COUNTER, not a clock. On the
	1,008-node fixture below a one-leaf update reads **5**; with the store off — which
	is what every build in this framework did before this round — the same re-solve
	reads **1,008**, and a re-solve with nothing dirty at all reads **0** where it also
	read 1,008.

	THE ORACLE, and it is the reason this file is longer than the fix. A cross-solve
	tree adds three failure classes a single solve cannot see:

	  1. A STALE NODE. The tree now carries whatever the last build left, so a subtree
	     wrongly reused is not a missing box — it is last frame's box, silently. Every
	     case here is a DIFFERENTIAL against an arm that rebuilds the whole tree every
	     solve, over the whole device matrix including 320x640.
	  2. A THEME SWAP SERVED FROM THE OLD SNAPSHOT. This is the one the standing lesson
	     names: **emission is not application**. A package EMITS tokens; the key here is
	     what the surface has APPLIED — the `themeMetrics` value `renderer.currentMetrics()`
	     resolves against at the build. The theme case below swaps a real second package
	     mid-run and asserts the rects AND the resolved per-node tokens equal a
	     fresh-built arm, with a negative control proving a token actually moved.
	  3. A NODE REUSED IN A PLACE IT WAS NOT BUILT FOR. `parentAxis` and `insideClipper`
	     ride the recursion and can change with no prop and no child changing. They are
	     stored per entry and checked at the lookup; the axis-4 case drives that
	     directly, because no blueprint can re-parent a live mounted node.

	THREE ARMS, driven over one script, compared channel-for-channel at every step:

	  A  node store ON,  measure store ON,  incremental ON   — the shipped default
	  B  node store OFF, measure store ON,  incremental ON   — isolates THIS store
	  C  everything OFF                                       — a forced full solve

	`renderer.attach`'s `layoutNodeReuse` opt exists for arm B alone. A vs C proves the
	answer; A vs B proves which mechanism moved it.

	AND ONE AXIS THAT IS DELIBERATELY NOT ONE. `text_metrics.calibrate` moves every
	estimated word width and is the boot-window font-flip class that P1's store must
	invalidate on — and it cannot reach this store at all, because the only
	`text_metrics` call on this seam is `reservedSize`, which is
	`authoredSize * measureScale + offset` and reads no font data. The script drives a
	calibration anyway, and the oracle proves the claim rather than the comment doing it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local layout_node = require("../src/render/layout_node")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local large_text = require("./lib/large_text")
local text_metrics = require("../src/layout/text_metrics")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

--[[ THE FIXTURE is `measure_reuse.spec`'s and `rect_cow.spec`'s, deliberately: the
	three stores are invalidated off the same events and a divergence between the
	files' fixtures would be a divergence in what "the same case" means. 200 rows x 5
	nodes plus an 8-node head is 1,008 layout nodes, carrying the shapes the risk lives
	in — a truncating `disclose` label and a `compactLabel` ladder (published verdicts),
	a ScrollView (`insideClipper` is true below it, which is axis 4 in the shipped
	tree), a `containerRelative` box under a wrapper that never moves, a `ViewThatFits`
	with a hidden losing candidate, and one malformed box that files a diagnostic. ]]
type Arm = { core: any, env: any, controller: any, adapter: any, rows: any, value: any, wide: any }

--[[ 8, not 9: `UI.ForEach` owns MOUNTING, not layout, so `toLayoutNode` splices its
	children into the list's own flow and builds no node for `Rows` itself — which is
	also why a structural change rebuilds the LIST rather than a region wrapper. ]]
local HEAD_NODES = 8
local ROW_NODES = 5
-- Scroll > List > Row > V, the deepest live chain (`Rows` splices away)
local DEPTH = 4

local function world(
	nodeReuse: boolean,
	cache: boolean,
	incremental: boolean,
	viewport: { w: number, h: number },
	rowCount: number
): Arm
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
	local rows = core:signal({})
	local items = {}
	for i = 1, rowCount do
		table.insert(items, { id = `r{i}`, n = core:signal(i) })
	end
	rows:set(items)
	local wide = core:signal(false)
	local wrapWidth = core:memo(function(use: any)
		return px(if use(wide) then 300 else 220)
	end)
	local bp = UI.ScrollView({
		id = "Scroll",
		axis = "y",
		padding = 0,
		gap = 0,
		width = fill(),
		height = fill(),
		children = {
			UI.VStack({
				id = "Wrap",
				padding = 0,
				gap = 0,
				width = px(200),
				height = px(30),
				children = {
					UI.Box({
						id = "Bar",
						width = { type = "containerRelative", fraction = 0.5 },
						height = px(10),
					}),
				},
			}),
			UI.Box({ id = "Bad", width = px(40), height = { type = "percent", fraction = 0.5 } }),
			UI.ViewThatFits({
				id = "Fits",
				width = px(120),
				height = px(24),
				children = {
					UI.Text({ id = "Long", textSize = 12, text = "A rather long candidate label" }),
					UI.Text({ id = "Short", textSize = 12, text = "Short" }),
				},
			}),
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 2,
				width = wrapWidth,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.HStack({
								id = "Row",
								padding = 0,
								gap = 4,
								width = fill(),
								height = px(28),
								children = {
									UI.Text({
										id = "V",
										textSize = 14,
										text = core:memo(function(use: any)
											return tostring(use(item.n))
										end),
									}),
									UI.Text({
										id = "L",
										textSize = 12,
										disclose = true,
										width = px(40),
										text = core:memo(function(use: any)
											return `Extraordinarily Long Identity {use(item.n)}`
										end),
									}),
									UI.Button({
										id = "B",
										label = "Configure this row",
										compactLabel = "C",
										width = px(44),
									}),
									UI.Box({ id = "P", width = fill(), height = px(10) }),
								},
							})
						end,
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	adapter.scrollBarThickness = 8
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = cache,
		layoutNodeReuse = nodeReuse,
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		rows = rows,
		value = items,
		wide = wide,
	}
end

-- every live node's rect and every property it carries; an adapter-only comparison is
-- blind to most of what a solve publishes, so all three readers below are compared
local function painted(adapter: any): string
	local out = {}
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
		table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function facts(controller: any): string
	local out = {}
	for path, f in controller.textAt() do
		local parts = {}
		for k, v in f do
			table.insert(parts, `{tostring(k)}={tostring(v)}`)
		end
		table.sort(parts)
		table.insert(out, `{path}|{table.concat(parts, ",")}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

-- the SET, not its multiplicity: a measure-time finding is filed once per measure call
-- that reaches it, so the count has never been a contract
local function findings(controller: any): string
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, d in controller.diagnostics() do
		local key = `{tostring(d.node)}: {tostring(d.issue)}`
		if not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local function snapshot(arm: Arm): string
	return `{painted(arm.adapter)}\n--facts--\n{facts(arm.controller)}\n--diag--\n{findings(arm.controller)}`
end

--[[ THE SCRIPT, applied identically to every arm so the comparison is over the same
	HISTORY rather than the same state — a reused tree can only be wrong about a
	sequence. Each step names the axis it exercises. ]]
local SCRIPT: { { name: string, run: (Arm) -> () } } = {
	{
		name = "one leaf: a single row's bound values",
		run = function(arm: Arm)
			arm.value[3].n:set(4242)
		end,
	},
	{
		name = "a second, different leaf",
		run = function(arm: Arm)
			arm.value[1].n:set(7)
		end,
	},
	{
		name = "offer change: the wrapper re-offers every row",
		run = function(arm: Arm)
			arm.wide:set(true)
		end,
	},
	{
		name = "one leaf under the new offer",
		run = function(arm: Arm)
			arm.value[2].n:set(99)
		end,
	},
	{
		name = "structure: a row is appended",
		run = function(arm: Arm)
			local next_ = table.clone(arm.value)
			table.insert(next_, { id = "rNew", n = arm.core:signal(1234) })
			arm.value[#arm.value + 1] = next_[#next_]
			arm.rows:set(next_)
		end,
	},
	{
		name = "one leaf after the structural change",
		run = function(arm: Arm)
			arm.value[#arm.value].n:set(5150)
		end,
	},
	{
		name = "structure: the first row is removed",
		run = function(arm: Arm)
			local next_ = table.clone(arm.value)
			table.remove(next_, 1)
			arm.rows:set(next_)
		end,
	},
	{
		name = "viewport: a live resize with nothing else dirty",
		run = function(arm: Arm)
			arm.env:set("viewportRect", { x = 0, y = 0, w = 300, h = 500 })
		end,
	},
	{
		name = "one leaf at the new viewport",
		run = function(arm: Arm)
			arm.value[2].n:set(31337)
		end,
	},
	--[[ AXIS 3, THE ONE THIS STORE EXISTS TO GET RIGHT: a real second theme package
		APPLIED to the surface. Every resolved dim, side, gap, icon box and type role in
		the tree is a function of this table and of nothing the dirty set can see. ]]
	{
		name = "theme: a second real package swapped in",
		run = function(arm: Arm)
			arm.env:set("themeMetrics", large_text.THEMES[2].metrics)
		end,
	},
	{
		name = "one leaf under the new theme",
		run = function(arm: Arm)
			arm.value[2].n:set(8)
		end,
	},
	-- ...and the third of axis 3 a live surface can move (`typographyScale` is a
	-- derived env key and is driven directly in the unit cases at the bottom)
	{
		name = "text preference: the reservation offset moves with nothing dirty",
		run = function(arm: Arm)
			arm.env:set("preferredTextOffset", 10)
		end,
	},
	--[[ THE FONT FLIP, which is NOT an axis of this store and is driven to prove it.
		`calibrate` moves every estimated word width and dirties nothing; the only
		`text_metrics` call this seam makes is `reservedSize`, pure arithmetic over
		(size, scale, offset). If that claim is wrong the differential says so here. ]]
	{
		name = "text metrics: the font calibration flips",
		run = function(_arm: Arm)
			text_metrics.calibrate("BuilderSans", 0.34)
			text_metrics.calibrate("GothamSSm", 0.34)
			text_metrics.calibrate("SourceSans", 0.34)
		end,
	},
	{
		name = "one leaf after the font flip",
		run = function(arm: Arm)
			arm.value[2].n:set(1)
		end,
	},
	{
		name = "nothing at all: a refresh with an empty dirty set",
		run = function() end,
	},
	{
		name = "offer change back",
		run = function(arm: Arm)
			arm.wide:set(false)
		end,
	},
}

local function drive(arm: Arm, step: number)
	SCRIPT[step].run(arm)
	arm.controller.refresh()
end

describe("the cross-solve layout-node store (P3)", function()
	it("DEMONSTRATOR D-P3: a one-leaf update at N=1008 builds O(touched), not O(N)", function()
		--[[ THE BOUND, PINNED FROM THE FIXTURE'S OWN BRANCHING RATHER THAN FITTED. The
			row's bound value feeds TWO memos — `V`'s text and `L`'s disclosing label —
			so the honest touched set is those two leaves plus `Row`, `List` and
			`Scroll`: five, and `Rows` is not in it because a `ForEach` splices and emits
			no layout node. `2 * DEPTH` is 8, comfortably above it, so an ordinary layout
			edit can move the constant without reddening this — and two orders of
			magnitude below the 1,008 the pre-fix build constructed on this same
			re-solve (run recorded in the task report). ]]
		local arm = world(true, true, true, { w = 400, h = 800 }, 200)
		local total = HEAD_NODES + ROW_NODES * 200
		arm.value[100].n:set(4242)
		arm.controller.refresh()
		arm.value[100].n:set(4243)
		arm.controller.refresh()
		local s = arm.controller.stats()
		expect(s.lastNodeBuilds > 0).toBe(true)
		expect(s.lastNodeBuilds <= 2 * DEPTH).toBe(true)
		-- ...and the tree is still the whole tree: the solve that ran over it arranged
		-- and skipped every one of the 1,008 nodes the build did not construct
		expect(s.lastRectInserts + s.lastSkipped).toBe(total)
	end)

	it("...and a re-solve with NOTHING dirty builds zero — where it also built 1008", function()
		--[[ A LIVE RESIZE IS THE CLEANEST FORM OF THIS: it re-solves the whole surface
			and changes not one input this seam reads. Every dimension a viewport moves —
			`fill`, `containerRelative`, the scroller's own inner size — is resolved by
			the SOLVER from a descriptor this tree carries, never by the build. So the
			honest number is 0, and it was N. ]]
		local arm = world(true, true, true, { w = 400, h = 800 }, 200)
		local before = arm.controller.stats().solves
		arm.env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		local s = arm.controller.stats()
		expect(s.solves > before).toBe(true)
		expect(s.lastNodeBuilds).toBe(0)
		-- and it is the RIGHT answer, not merely a cheap one
		local full = world(false, false, false, { w = 400, h = 800 }, 200)
		full.env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		expect(snapshot(arm)).toBe(snapshot(full))
	end)

	it("...and the store OFF rebuilds all 1008 every solve — the control", function()
		-- the denominator, and the number every build in this framework produced before
		-- this round
		local arm = world(false, true, true, { w = 400, h = 800 }, 200)
		local total = HEAD_NODES + ROW_NODES * 200
		expect(arm.controller.stats().lastNodeBuilds).toBe(total)
		arm.value[100].n:set(4242)
		arm.controller.refresh()
		expect(arm.controller.stats().lastNodeBuilds).toBe(total)
		arm.env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		expect(arm.controller.stats().lastNodeBuilds).toBe(total)
	end)

	it("THEME: a swap APPLIED mid-run rebuilds every node, and equals a fresh build", function()
		--[[ EMISSION IS NOT APPLICATION, and this case is written against the
			application. What the build keys on is the value `renderer.currentMetrics()`
			returns — `env:get("themeMetrics"):get()`, read fresh at every use because
			"the swap transaction sets it and re-solves in the same invocation". So the
			swap below IS the application, and the assertion is that the store dropped
			everything the moment the applied snapshot changed. A key on a theme signal,
			a package id or a generation counter would be keyed on emission and would
			serve the old tree into the solve that had already been handed the new
			snapshot. ]]
		local vp = { w = 400, h = 800 }
		local warm = world(true, true, true, vp, 40)
		-- warm it thoroughly first: two one-leaf updates, so most of the tree is served
		warm.value[5].n:set(11)
		warm.controller.refresh()
		warm.value[6].n:set(12)
		warm.controller.refresh()
		expect(warm.controller.stats().lastNodeBuilds <= 2 * DEPTH).toBe(true)
		local beforeSnapshot = snapshot(warm)

		warm.env:set("themeMetrics", large_text.THEMES[2].metrics)
		-- EVERY node, because axis 3 is solve-wide and cannot be caught by a dirty set
		expect(warm.controller.stats().lastNodeBuilds).toBe(HEAD_NODES + ROW_NODES * 40)

		--[[ THE NEGATIVE CONTROL THIS CASE IS VACUOUS WITHOUT: the theme has to have
			MOVED something, or "equals a fresh build" is two identical trees agreeing. ]]
		expect(snapshot(warm) ~= beforeSnapshot).toBe(true)

		-- ...and it equals a surface that was BUILT under the new theme from cold, which
		-- is the only arm that can prove no token came from the old snapshot
		local fresh = world(false, false, false, vp, 40)
		-- the SAME history, because the comparison is over a surface's state and the two
		-- leaf updates above are part of it
		fresh.value[5].n:set(11)
		fresh.controller.refresh()
		fresh.value[6].n:set(12)
		fresh.controller.refresh()
		fresh.env:set("themeMetrics", large_text.THEMES[2].metrics)
		expect(snapshot(warm)).toBe(snapshot(fresh))
		-- the resolved TOKENS, not only the rects: `textAt()` carries the per-node type
		-- facts the swap moves, and it is compared above inside `snapshot`
		expect(facts(warm.controller)).toBe(facts(fresh.controller))

		-- and the store is warm again under the NEW theme rather than permanently cold
		warm.value[7].n:set(13)
		warm.controller.refresh()
		expect(warm.controller.stats().lastNodeBuilds <= 2 * DEPTH).toBe(true)
	end)

	it("STRUCTURE: a ForEach add/remove rebuilds the affected region and nothing else", function()
		--[[ The region is not the unit and neither is the tree. A `ForEach` splices, so
			the node that has to be rebuilt is the LIST whose flow the rows land in, plus
			the new row's own five nodes, plus `Scroll` above it. Removal is cheaper
			still: nothing new is built at all, and the removed row's slate goes with the
			node it was keyed on — the store is keyed by the mounted node TABLE, so a
			later row mounted at the same key can never be answered with the old row's
			tree. ]]
		local vp = { w = 400, h = 800 }
		local arm = world(true, true, true, vp, 40)
		arm.value[5].n:set(11)
		arm.controller.refresh()

		local next_ = table.clone(arm.value)
		table.insert(next_, { id = "rNew", n = arm.core:signal(1234) })
		arm.value[#arm.value + 1] = next_[#next_]
		arm.rows:set(next_)
		arm.controller.refresh()
		-- the new row (5) + List + Scroll = 7; the bound leaves room for a layout edit
		expect(arm.controller.stats().lastNodeBuilds <= ROW_NODES + 2 * DEPTH).toBe(true)
		expect(arm.controller.stats().lastNodeBuilds >= ROW_NODES).toBe(true)

		local shrunk = table.clone(arm.value)
		table.remove(shrunk, 1)
		arm.rows:set(shrunk)
		arm.controller.refresh()
		-- nothing NEW exists, so only the containers on the path are rebuilt
		expect(arm.controller.stats().lastNodeBuilds <= 2 * DEPTH).toBe(true)

		-- ...and the answer is a full rebuild's answer
		local full = world(false, false, false, vp, 40)
		full.value[5].n:set(11)
		full.controller.refresh()
		local nextFull = table.clone(full.value)
		table.insert(nextFull, { id = "rNew", n = full.core:signal(1234) })
		full.value[#full.value + 1] = nextFull[#nextFull]
		full.rows:set(nextFull)
		full.controller.refresh()
		local shrunkFull = table.clone(full.value)
		table.remove(shrunkFull, 1)
		full.rows:set(shrunkFull)
		full.controller.refresh()
		expect(snapshot(arm)).toBe(snapshot(full))
	end)

	it("A SOLVE THAT DID NOT DRAIN THE QUEUE takes the full arm, not the stale tree", function()
		--[[ THE HOLE THIS STORE HAD TO BE DESIGNED AROUND, and the one case in this file
			that no amount of `refresh` driving can reach. A settle-phase solve does NOT
			consume the dirty queue — deliberately, so the structural sync, the paint
			commit and the appear/disappear ordering stay byte-identical (THE STALE-
			LAYOUT-DIRT TEST, `renderer.luau`). So a prop can be WRITTEN onto the mounted
			tree, its dirty entry can still be sitting in the queue, and a geometry change
			can then solve the surface — with axis 2 holding the set from the LAST drain,
			which says nothing about that row.

			The fix is not a wider set, it is a refusal: `root.dirtySeq()` is monotonic and
			survives `takeDirty`, so "has anything dirtied this tree that this renderer has
			not classified" is one comparison, and any un-classified dirt takes the full
			rebuild. Below: a row's value is written with NO refresh, then a live resize
			solves the surface. The label must be the new one. ]]
		local vp = { w = 400, h = 800 }
		local arm = world(true, true, true, vp, 40)
		local full = world(false, false, false, vp, 40)
		-- the SAME surface with no pending write, so "the write moved the geometry"
		-- is a comparison rather than an assumption
		local quiet = world(true, true, true, vp, 40)
		-- warm the stores so the row below is genuinely being served from one
		for _, a2 in { arm, full, quiet } do
			a2.value[3].n:set(11)
			a2.controller.refresh()
		end
		expect(arm.controller.stats().lastNodeBuilds <= 2 * DEPTH).toBe(true)
		expect(painted(arm.adapter)).toBe(painted(quiet.adapter))

		-- the write lands on the tree; the dirty entry stays in the queue
		arm.value[3].n:set(424242)
		full.value[3].n:set(424242)
		-- ...and a geometry change solves all three surfaces without draining anything
		for _, a2 in { arm, full, quiet } do
			a2.env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		end
		--[[ THE DIFFERENTIAL IS THE ASSERTION, and the reason is worth stating: the
			paint COMMIT is driven by `refresh`, so the new string does not reach the
			adapter on this solve in EITHER arm. What does reach it is the geometry —
			`V` is auto-sized text, so "11" and "424242" are different widths and the
			whole row is laid out differently. A served tree would carry the old string's
			box; `full` rebuilds from the live props and is ground truth. ]]
		expect(snapshot(arm)).toBe(snapshot(full))
		-- ...and it is NOT vacuous: against the same surface WITHOUT the pending write,
		-- at the same viewport, the geometry differs — so a served tree would have been
		-- observably stale rather than merely unlucky
		expect(painted(arm.adapter) ~= painted(quiet.adapter)).toBe(true)
		-- the refusal really engaged: this solve rebuilt the whole tree
		expect(arm.controller.stats().lastNodeBuilds).toBe(HEAD_NODES + ROW_NODES * 40)

		-- ...and the store is warm again immediately after, not permanently cold
		arm.controller.refresh()
		expect(string.find(painted(arm.adapter), "424242", 1, true) ~= nil).toBe(true)
		arm.value[4].n:set(12)
		arm.controller.refresh()
		expect(arm.controller.stats().lastNodeBuilds <= 2 * DEPTH).toBe(true)
	end)

	it("ORACLE: every step of the script equals a forced full solve, at every viewport", function()
		--[[ THE DIFFERENTIAL, and it is the only thing that can catch a wrongly reused
			subtree: a stale node is not a missing box, it is LAST FRAME'S box, which an
			arm compared only against itself will happily agree with. `c` rebuilds the
			tree AND re-solves it whole on every refresh and is ground truth; `b` keeps
			P1 and P2 and drops only this store, so a divergence between A and B names
			THIS mechanism rather than the measure slate or the arrange skip. 320x640 is
			in the set because the narrowest supported box is where a reserve arms and a
			container narrows. ]]
		for _, view in device_views.VIEWS do
			local vp = { w = view.w, h = view.h }
			local a = world(true, true, true, vp, 12)
			local b = world(false, true, true, vp, 12)
			local c = world(false, false, false, vp, 12)
			expect(snapshot(a)).toBe(snapshot(c))
			expect(snapshot(a)).toBe(snapshot(b))
			for step = 1, #SCRIPT do
				drive(a, step)
				drive(b, step)
				drive(c, step)
				expect(snapshot(a)).toBe(snapshot(c))
				expect(snapshot(a)).toBe(snapshot(b))
			end
			-- the guard every differential needs: the mechanism actually engaged, and
			-- the arm it is compared against did not
			expect(a.controller.stats().lastNodeBuilds < HEAD_NODES + ROW_NODES * 12).toBe(true)
			expect(b.controller.stats().lastNodeBuilds).toBe(HEAD_NODES + ROW_NODES * 12)
			--[[ `text_metrics` calibration is PROCESS state, not surface state (see
				`tests/process_globals.spec`), and the font-flip step above moves it. Left
				set it changes what every later spec in the run measures — which is
				exactly the failure this line prevents, observed once on the way in. ]]
			text_metrics.resetCalibration()
		end
	end)

	it("P1 x P2 x P3: warm slates, a warm map and a warm tree compose", function()
		--[[ The three stores are keyed on the SAME identity and invalidated off the same
			dirty set: P1's slate by `node.id`, P2's map by `node.id`, and this one by the
			mounted node TABLE whose `path` IS that id (`layout_node.luau`: `id =
			node.path`). So a patched tree carries exactly the ids the other two key on,
			for exactly the same node set — which is what makes them composable rather
			than merely simultaneous. This is the case that would catch a disagreement:
			geometry right in one arm and stale in the other. ]]
		local vp = { w = 400, h = 800 }
		local warm = world(true, true, true, vp, 200)
		local cold = world(false, false, false, vp, 200)
		local total = HEAD_NODES + ROW_NODES * 200
		--[[ ONE WARMING UPDATE FIRST, and it is P1's requirement rather than this
			store's. The mount solve has no reuse set, so `measure_reuse` clears its
			slates on it; the FIRST update after a cold mount therefore measures the tree
			once to fill them. This store is already warm at that point — the numbers for
			that round are builds 5 / inserts 7 / measured 1,012 — so the bound below is
			about the composition of all three, which is what the case claims. ]]
		warm.value[10].n:set(999)
		warm.controller.refresh()
		cold.value[10].n:set(999)
		cold.controller.refresh()
		for round = 1, 4 do
			warm.value[10 + round].n:set(1000 + round)
			warm.controller.refresh()
			cold.value[10 + round].n:set(1000 + round)
			cold.controller.refresh()
			expect(snapshot(warm)).toBe(snapshot(cold))
			local s = warm.controller.stats()
			expect(s.lastNodeBuilds <= 2 * DEPTH).toBe(true)
			expect(s.lastRectInserts <= 8 * DEPTH).toBe(true)
			expect(s.lastMeasured <= 8 * DEPTH).toBe(true)
			expect(s.lastSkipped > 900).toBe(true)
		end
		local c = cold.controller.stats()
		expect(c.lastNodeBuilds).toBe(total)
		expect(c.lastRectInserts).toBe(total)
		expect(c.lastMeasured > 500).toBe(true)
	end)
end)

--[[ ── THE TWO CLAIMS NO BLUEPRINT CAN DRIVE ──────────────────────────────────
	A mounted node cannot be re-parented (the mount layer's whole identity model says
	so), and a garbage collection cannot be observed on demand. Both are properties of
	`layout_node.build` itself, so they are driven against it directly with the
	smallest mounted-node shape it accepts: `class`, `path`, `props`, `children` are
	the only four fields it reads. ]]
local function stub(class: string, path: string, props: any, children: { any }?): any
	return { class = class, path = path, props = props or {}, children = children or {} }
end

local NEUTRAL = (require("../src/themes/snapshot") :: any).neutral()

describe("the layout-node store: the axes a blueprint cannot reach", function()
	it("AXIS 4: an entry built under one parent axis is not served under another", function()
		--[[ `parentAxis` and `insideClipper` ride the recursion, so a node can need a
			different tree with no prop and no child having moved — the recursion is the
			only thing that knows where it is. They are recorded ON the entry and checked
			at the lookup rather than folded into the stamp, because a stamp is solve-wide
			and this is per node. ]]
		local leaf = stub("Box", "/r/leaf", { width = px(10), height = px(10) })
		local hstack = stub("HStack", "/r", {}, { leaf })
		local store = layout_node.newStore()
		layout_node.build(store, hstack, NEUTRAL, 1, 0, nil)
		expect(store.built).toBe(2)
		-- the same nodes, nothing dirty: served
		layout_node.build(store, hstack, NEUTRAL, 1, 0, {})
		expect(store.built).toBe(0)
		--[[ ...and now the SAME leaf table under a vertical parent. The mount layer
			cannot produce this, which is exactly why it is driven here: if the entry did
			not carry its axis, the leaf would be served a tree built for a row. ]]
		local vstack = stub("VStack", "/r", {}, { leaf })
		layout_node.build(store, vstack, NEUTRAL, 1, 0, {})
		expect(store.built).toBe(2)
	end)

	it("AXIS 4: an entry built outside a clipper is not served inside one", function()
		local leaf = stub("Box", "/r/leaf", { width = px(10), height = px(10) })
		local plain = stub("VStack", "/r", {}, { leaf })
		local store = layout_node.newStore()
		layout_node.build(store, plain, NEUTRAL, 1, 0, nil)
		layout_node.build(store, plain, NEUTRAL, 1, 0, {})
		expect(store.built).toBe(0)
		local scroller = stub("ScrollView", "/r", { axis = "y" }, { leaf })
		layout_node.build(store, scroller, NEUTRAL, 1, 0, {})
		-- both: the scroller's own kind changed, and the leaf is now inside a clipper
		expect(store.built).toBe(2)
	end)

	it("AXIS 3: the stamp is metrics IDENTITY, the typography scale and the offset", function()
		local leaf = stub("Box", "/r/leaf", { width = px(10), height = px(10) })
		local root = stub("VStack", "/r", {}, { leaf })
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		layout_node.build(store, root, NEUTRAL, 1, 0, {})
		expect(store.built).toBe(0)
		layout_node.build(store, root, NEUTRAL, 1.3, 0, {})
		expect(store.built).toBe(2)
		layout_node.build(store, root, NEUTRAL, 1.3, 0, {})
		expect(store.built).toBe(0)
		layout_node.build(store, root, NEUTRAL, 1.3, 4, {})
		expect(store.built).toBe(2)
		--[[ A DIFFERENT SNAPSHOT TABLE WITH THE SAME NUMBERS IS A DIFFERENT THEME as far
			as this store is concerned, and that is the conservative direction: the value
			`themeMetrics` holds is one table per applied theme, so identity is the cheap
			and correct question, and a package that recompiles to the same numbers costs
			one rebuild rather than risking a stale one. ]]
		local twin = table.clone(NEUTRAL)
		layout_node.build(store, root, NEUTRAL, 1.3, 4, {})
		expect(store.built).toBe(0)
		layout_node.build(store, root, twin, 1.3, 4, {})
		expect(store.built).toBe(2)
	end)

	it("AXIS 2: a dirty path rebuilds itself and leaves its clean siblings alone", function()
		local a = stub("Box", "/r/a", { width = px(10), height = px(10) })
		local b = stub("Box", "/r/b", { width = px(10), height = px(10) })
		local root = stub("VStack", "/r", {}, { a, b })
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(store.built).toBe(3)
		local cleanA = first.children[1]
		local cleanB = first.children[2]
		-- the ancestor closure the renderer computes, spelled out
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/a"] = true })
		expect(store.built).toBe(2)
		expect(second.children[1]).never().toBe(cleanA)
		expect(second.children[2]).toBe(cleanB)
	end)

	it("THE WEAK-KEY PREMISE: a built node holds no reference back to its mounted node", function()
		--[[ The store's keys are weak, which is what bounds it under a churning
			`ForEach` — and in Luau a weak table is NOT an ephemeron, so a VALUE that
			reaches its own KEY pins the pair alive forever and the bound silently
			disappears (measured on this project once already, in `surface_overlap`'s
			strong bucket). The premise is therefore a reachability property of the built
			tree, and it is walked rather than promised: `id` is `node.path`, a STRING;
			every other field is a resolved number, a carried name, or a child
			`solver.Node`. ]]
		local leaf = stub("Text", "/r/leaf", { text = "hello", textSize = 14 })
		local root = stub("VStack", "/r", { gap = 4 }, { leaf })
		local store = layout_node.newStore()
		local built = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local mounted = { [root] = "root", [leaf] = "leaf", [root.props] = "root.props" }
		mounted[leaf.props] = "leaf.props"
		mounted[root.children] = "root.children"
		local seen: { [any]: boolean } = {}
		local found: { string } = {}
		local function walk(v: any)
			if type(v) ~= "table" or seen[v] then
				return
			end
			seen[v] = true
			if mounted[v] ~= nil then
				table.insert(found, mounted[v])
				return
			end
			for k, inner in v do
				walk(k)
				walk(inner)
			end
		end
		walk(built)
		expect(table.concat(found, " ")).toBe("")
		-- ...and the walk really reached the tree it is about
		expect(seen[built]).toBe(true)
		expect(built.id).toBe("/r")
		expect(#built.children).toBe(1)
		-- NEGATIVE CONTROL: the same walk over a tree that DOES reach back reports it
		local planted = { id = "/r", children = { { id = "/r/leaf", back = leaf } } }
		seen = {}
		found = {}
		walk(planted)
		expect(table.concat(found, " ")).toBe("leaf")
	end)
end)
