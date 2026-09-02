--!strict
--[[
	THE COPY-ON-WRITE RECT MAP (perf campaign P2) — the demonstrator and its oracle.

	WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, `battle_hud` at
	5 115 layout nodes, measured AFTER P1 landed). `arrange` could already SKIP a
	subtree nothing dirtied — and then it walked that subtree anyway, because the skip
	was implemented as `replaySubtree`: copy every descendant's entry forward into a
	fresh `out` map, plus four more per-node writes for the verdict channels and the
	skipped set. So the pass incremental layout exists to remove was still O(N), and it
	was the last superlinear term in the step. `tools/profile/probe` at L, reuse with
	nothing dirty: `arranged = 0`, `skipped = 5115`, **3.26 ms of `Facet/arrange` and
	1 140 kb allocated** to reproduce a map the solve was already holding.

	THE FIX is that the map is not fresh. A solve given `reuse` starts FROM the previous
	solve's own rect map, so a subtree it skips is already correct — same entries, same
	tables — and skipping costs a `return` instead of N inserts.

	THE DEMONSTRATOR (D-P2) is `work.rectInserts`, a counter on the one place the map
	is written (`arrange`'s `out[node.id] = {...}`). It is a COUNTER, not a clock. At
	pre-fix HEAD, with the counter added and nothing else changed, a one-leaf update on
	the fixture below reads **1 008** — the whole tree — and it now reads 5. (That run was
	against the 8-head fixture it was measured on; the P3 review added a `When` branch and
	an `ErrorBoundary` view to all three fixtures in this family, so the tree is 1 010
	today and the assertions below are bounds rather than that number.)

	WHY A COUNTER AND NOT MAP IDENTITY. Entry identity was ALREADY shared before the
	fix (`out[node.id] = entry` stored the previous solve's table), so "untouched
	entries are the same tables" is green on both builds and proves nothing about the
	bound. The number of INSERTIONS is what moved, and it is what the aliasing case
	below pairs with map identity to state completely.

	THE ORACLE, and it is why this file is longer than the fix. Sharing a map across
	solves adds two failure classes a single solve cannot see:

	  1. A STALE OR MISSING ENTRY. The map now carries whatever the last solve left, so
	     a subtree wrongly skipped is not a missing rect — it is last frame's rect,
	     silently. Every case here is therefore a DIFFERENTIAL against a forced FULL
	     solve, rect for rect, over the whole device matrix including 320x640.
	  2. A READER THAT MUTATES IT. The shared structure is read-only, because the next
	     solve hands the same tables back as "unchanged". THE TWO HALVES OF THAT ARE
	     ENFORCED DIFFERENTLY AND THE DIFFERENCE IS THE POINT (P2 review, IMPORTANT 1):

	     · the RECT is `table.freeze`d where `arrange` builds the entry, so corrupting
	       one is impossible rather than merely detected. O(walked), and it cost the
	       audit that licensed it: no writer of a solved rect exists in `src/`, the
	       tests, the examples or the game, and every rect reaching `arrange` is a
	       fresh table literal (so an unguarded freeze cannot double-freeze).
	     · the ENTRY cannot be frozen, and here is why rather than a shrug: `arrange`
	       itself writes `contentSize`, `padding`, `barInset`, `overflow` and
	       `composition` onto an entry AFTER building it, and a parent writes `hidden`
	       onto a CHILD's entry after that child's own `arrange` has returned. There is
	       no moment an entry is final except the end of the whole solve, and freezing
	       there is the O(N) pass this fix removed. So the entry half is held by two
	       instruments instead: the canary below holds the `textFacts` TABLES the
	       renderer republishes by reference (`renderer.luau:2046-2055` ->
	       `lastTextFacts` -> `controller.textAt()`, a shallow clone), and the scalar
	       fields reach the adapter through `visible`/`scrollRegions`, so a corrupted
	       one diverges from the full-solve arm in the oracle.

	     THREE MUTATIONS WERE RUN, 2026-09-01, and all three bite:
	       · drop the `table.freeze` -> the aliasing case's negative control goes red
	         (the write to a solved rect stops raising);
	       · make `rectKey` blind to `entry.hidden` -> the same case goes red, so the
	         detection really is that comparison and not something else;
	       · make a REAL reader mutate a shared entry field (`renderer.luau:2049`
	         flipping `entry.textFacts.truncated` as it harvests) -> the canary, the
	         oracle AND the P1 x P2 case all go red.

	AND THE ONE COMPOSITION THAT IS NOT EITHER HALF'S: P1's cross-solve measure store
	serves a subtree its cached size while P2's map serves the same subtree its cached
	rect. Both are keyed off `reuse.dirtyContains`, so a disagreement between them
	would show as geometry that is right in one arm and stale in the other. The last
	case drives a warm cache and a warm map together and asserts all three at once —
	the rects match a full solve, insertions stay bounded, and measures stay bounded.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local solver = require("../src/layout/solver")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

--[[ THE FIXTURE. 200 rows of 5 nodes plus a 10-node head is 1 010 layout nodes, and it
	carries the shapes the risk lives in rather than plain boxes (the lesson
	`incremental_layout.spec` states at length): a truncating `disclose` label and a
	`compactLabel` ladder, so the published verdicts are real; a ScrollView, so the
	container and the bar reserve are in play; a `containerRelative` box whose own
	wrapper never moves, which is the one dimension a rect cannot vouch for; a
	`ViewThatFits`, so a hidden losing candidate is in the map; and one malformed box
	that FILES A DIAGNOSTIC, because a skipped subtree's findings are replayed off the
	same bookkeeping this fix rewrote; and — added by the P3 review (M3) — a `When`
	branch and an `ErrorBoundary` view, so all three structural reconcilers are spliced
	into the flow this differential compares rather than only `ForEach`. ]]
type Arm = { core: any, env: any, controller: any, adapter: any, rows: any, items: any, wide: any, branch: any }

--[[ TEN, and the three that are NOT in it are the point: `UI.ForEach`, `UI.When` and
	`UI.ErrorBoundary` are structural regions that own MOUNTING, not layout, so
	`toLayoutNode` splices their children into the enclosing flow and emits no node for
	the region itself. Scroll, Wrap, Bar, Bad, Fits and its two candidates, Extra (the
	When's branch, mounted because it starts ON), Held (the ErrorBoundary's view), List. ]]
local HEAD_NODES = 10
local ROW_NODES = 5
-- Scroll > List > Row > V, the deepest live chain (`Rows` splices away)
local DEPTH = 4

local function world(incremental: boolean, cache: boolean, viewport: { w: number, h: number }, rowCount: number): Arm
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
	local items = {}
	for i = 1, rowCount do
		table.insert(items, { id = `r{i}`, n = core:signal(i) })
	end
	local rows = core:signal(items)
	local wide = core:signal(false)
	local branchOn = core:signal(true)
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
			--[[ THE OTHER TWO RECONCILERS (P3 review, M3). `ForEach` is the one the rows
				exercise; `When` and `ErrorBoundary` splice the same way and are the other
				two writers of `node.children` in the whole framework, so a differential
				that never mounted one was testing a third of the structural half of every
				invalidation axis in this family. The branch starts ON and the script
				toggles it OFF and back, so the node count at the end of the script is the
				count at the start — which is what lets the exact totals stay exact. The
				three fixtures in this family (`measure_reuse`, `rect_cow`, `node_reuse`)
				are kept identical on purpose: they are invalidated off the same events and
				a divergence between them would be a divergence in what "the same case"
				means. ]]
			UI.When({
				id = "Branch",
				condition = branchOn,
				thenView = function()
					return UI.Text({ id = "Extra", textSize = 12, text = "conditional row" })
				end,
			}),
			UI.ErrorBoundary({
				id = "Guard",
				view = function()
					return UI.Box({ id = "Held", width = px(30), height = px(10) })
				end,
				fallback = function()
					return UI.Box({ id = "Fallen", width = px(30), height = px(10) })
				end,
			}),
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
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		controller = controller,
		adapter = adapter,
		rows = rows,
		items = items,
		wide = wide,
		branch = branchOn,
	}
end

-- every live node's rect and every property it carries; the shape
-- `incremental_layout.spec` settled on, because an adapter-only comparison is blind to
-- most of what a solve publishes
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
-- that reaches it, so the count has never been a contract (see `measure_reuse.spec`)
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
	HISTORY rather than the same state — a shared map can only be wrong about a
	sequence. Each step names the axis it exercises. ]]
local SCRIPT: { { name: string, run: (Arm) -> () } } = {
	{
		name = "one leaf: a single row's bound value",
		run = function(arm: Arm)
			arm.items[3].n:set(4242)
		end,
	},
	{
		name = "a second, different leaf",
		run = function(arm: Arm)
			arm.items[1].n:set(7)
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
			arm.items[2].n:set(99)
		end,
	},
	{
		name = "structure: a row is appended (no reuse set at all)",
		run = function(arm: Arm)
			local next_ = table.clone(arm.items)
			table.insert(next_, { id = "rNew", n = arm.core:signal(1234) })
			arm.items[#arm.items + 1] = next_[#next_]
			arm.rows:set(next_)
		end,
	},
	{
		name = "one leaf after the structural change",
		run = function(arm: Arm)
			arm.items[#arm.items].n:set(5150)
		end,
	},
	{
		name = "structure: the first row is removed",
		run = function(arm: Arm)
			local next_ = table.clone(arm.items)
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
			arm.items[2].n:set(31337)
		end,
	},
	{
		name = "nothing at all: a refresh with an empty dirty set",
		run = function() end,
	},
	--[[ THE OTHER TWO RECONCILERS (P3 review, M3). `When` off drops a spliced child out
		of the scroller's flow and back in; `ErrorBoundary` participates on every step by
		being in the tree at all, its view spliced into the same flow, so a stale splice
		would move every sibling below it. The branch ends ON, so the node count at the
		end of this script is the count at the start. ]]
	{
		name = "structure: the When branch is dropped",
		run = function(arm: Arm)
			arm.branch:set(false)
		end,
	},
	{
		name = "structure: the When branch comes back",
		run = function(arm: Arm)
			arm.branch:set(true)
		end,
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

-- a hand-built tree for the cases that need the MAP itself, which no controller
-- exposes. `solver.solve`'s `reuse` opt is exactly what the renderer passes.
local function tree(groups: number, perGroup: number): any
	local children = {}
	for g = 1, groups do
		local kids = {}
		for i = 1, perGroup do
			table.insert(kids, {
				kind = "box",
				id = `/root/g{g}/l{i}`,
				width = px(10 + (i % 7)),
				height = px(8),
				children = {},
			})
		end
		table.insert(children, { kind = "vstack", id = `/root/g{g}`, gap = 2, children = kids })
	end
	return { kind = "vstack", id = "/root", gap = 4, children = children }
end

--[[ EVERY FIELD A READER CONSUMES, not only the geometry. The rect is frozen, so the
	fields below are the ones a rogue reader could still move — and this is the
	comparison the negative control mutates to prove the instrument bites. ]]
local function rectKey(rects: any): string
	local out = {}
	for id, entry in rects do
		local r = entry.rect
		local facts = if type(entry.textFacts) == "table" then entry.textFacts else nil
		table.insert(
			out,
			`{id}|{r.x},{r.y},{r.w},{r.h}|h={tostring(entry.hidden)}|o={tostring(entry.overflow)}`
				.. `|k={tostring(entry.kind)}|c={tostring(entry.compact)}|t={tostring(facts and facts.truncated)}`
				.. `|cs={tostring(entry.contentSize and entry.contentSize.w)}`
		)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

describe("the copy-on-write rect map (P2)", function()
	it("DEMONSTRATOR D-P2: a one-leaf update at N=1010 inserts O(touched), not O(N)", function()
		--[[ THE BOUND, PINNED FROM THE FIXTURE'S OWN BRANCHING RATHER THAN FITTED. The
			honest touched set of a one-value update is the scroller, the list, the dirty
			row, the text and the one sibling the text's new width moves — MEASURED at 5,
			because the row's other siblings each land on the rect they already had and
			the skip catches them one by one on the way past. `8 * DEPTH` is 32: six
			times that, so an ordinary layout edit can move the constant without
			reddening this, and it is two orders of magnitude below the 1 008 the pre-fix
			build inserted (run recorded in the task report). ]]
		local arm = world(true, true, { w = 400, h = 800 }, 200)
		local total = HEAD_NODES + ROW_NODES * 200
		arm.items[100].n:set(4242)
		arm.controller.refresh()
		arm.items[100].n:set(4243)
		arm.controller.refresh()
		local s = arm.controller.stats()
		expect(s.lastRectInserts > 0).toBe(true)
		expect(s.lastRectInserts <= 8 * DEPTH).toBe(true)
		--[[ ...AND THIS IS THE NUMBER THAT USED TO BE INSERTED WITH IT: before the fix
			every skipped node was a separate `out[id] = entry` write plus four more on
			`ctx`, so 5 + 1 003 is what this same re-solve cost.

			IT IS NOT AN ENGAGEMENT GUARD, and saying so is the correction (P2 review,
			minor 4). `skipped` is now computed BY SUBTRACTION — the previous solve's
			node count minus `arranged` — so these three numbers are one identity read
			three ways and cannot disagree with each other. What keeps this case from
			going vacuous is elsewhere and is real: the ORACLE asserts
			`partialSolves > 0` at every viewport and compares the whole surface
			against a forced full solve after every step, so a skip that stopped
			engaging shows up there as work, and a skip that engaged WRONGLY shows up
			there as a divergence. ]]
		expect(s.lastSkipped >= total - 8 * DEPTH).toBe(true)
		expect(s.lastRectInserts + s.lastSkipped).toBe(total)
		-- the identity the fix creates: the map costs exactly what the walk costs
		expect(s.lastRectInserts).toBe(s.lastArranged)
	end)

	it("...and a forced full solve of the same tree inserts all 1010 — the control", function()
		-- the negative control the demonstrator is meaningless without, and the number
		-- the pre-fix build reported for the INCREMENTAL arm above
		local arm = world(false, true, { w = 400, h = 800 }, 200)
		arm.items[100].n:set(4242)
		arm.controller.refresh()
		local s = arm.controller.stats()
		expect(s.lastRectInserts).toBe(HEAD_NODES + ROW_NODES * 200)
		expect(s.lastSkipped).toBe(0)
	end)

	it("ALIASING: two solves with nothing changed share the map, and equal a full solve", function()
		local root = tree(40, 10)
		local vp = { w = 400, h = 800 }
		local first = solver.solve(root, vp, {})
		local before = rectKey(first.rects)
		local sampled = first.rects["/root/g7/l3"]
		--[[ THE CANARY, planted in the map the next solve is handed. A shared structure
			is read-only by convention; this is the assertion that the SOLVER itself
			honours it — it may overwrite the entry of a node it walks and nothing else,
			so a key it never walks must come back byte-identical and table-identical. ]]
		first.rects["__canary__"] = { rect = { x = 1, y = 2, w = 3, h = 4 }, kind = "canary" }
		local canary = first.rects["__canary__"]

		local second = solver.solve(root, vp, { reuse = { previous = first, dirtyContains = {} } })
		-- the map is the SAME table, and every untouched entry the same entry
		expect(second.rects).toBe(first.rects)
		expect(second.rects["/root/g7/l3"]).toBe(sampled)
		expect(second.rects["__canary__"]).toBe(canary)
		expect(canary.rect.x).toBe(1)
		expect(canary.rect.w).toBe(3)
		expect(second.work.rectInserts).toBe(0)
		expect(second.work.skipped).toBe(first.work.arranged)

		-- ...AND IT IS STILL THE RIGHT ANSWER. Identity without a differential is a
		-- cache that agrees with itself; this is the forced full solve it must equal.
		second.rects["__canary__"] = nil
		local full = solver.solve(root, vp, {})
		expect(rectKey(second.rects)).toBe(before)
		expect(rectKey(second.rects)).toBe(rectKey(full.rects))

		--[[ NEGATIVE CONTROL, BOTH HALVES (P2 review, IMPORTANT 1). A canary nobody has
			seen fail is decoration, so the corruption is planted here rather than
			hoped for.

			THE RECT half is `table.freeze`, so the failure mode is not "detected", it
			is "refused": writing to a solved rect RAISES. That is the whole point of
			paying for the freeze instead of trusting a grep.

			THE ENTRY half cannot be frozen (see the header), so it is detected: moving
			one field on ONE untouched entry must change `rectKey`, which is the
			comparison every differential in this file is built out of. Restored
			afterwards so this case leaves no corpse for the next. ]]
		local victim = second.rects["/root/g30/l4"]
		expect(pcall(function()
			victim.rect.x = 999
		end)).toBe(false)
		local clean = rectKey(second.rects)
		local wasHidden = victim.hidden
		victim.hidden = true
		expect(rectKey(second.rects) ~= clean).toBe(true)
		victim.hidden = wasHidden
		expect(rectKey(second.rects)).toBe(clean)
	end)

	it("ALIASING: a dirty leaf replaces its own entry and leaves every other alone", function()
		local root = tree(40, 10)
		local vp = { w = 400, h = 800 }
		local first = solver.solve(root, vp, {})
		local untouched = first.rects["/root/g30/l4"]
		local touched = first.rects["/root/g7/l3"]
		-- the ancestor closure the renderer computes, spelled out: the leaf and its
		-- ancestors are the only ids `arrange` is allowed to walk
		local dirty = { ["/root"] = true, ["/root/g7"] = true, ["/root/g7/l3"] = true }
		local second = solver.solve(root, vp, { reuse = { previous = first, dirtyContains = dirty } })
		expect(second.rects).toBe(first.rects)
		expect(second.rects["/root/g30/l4"]).toBe(untouched)
		expect(second.rects["/root/g7/l3"]).never().toBe(touched)
		--[[ THREE, and the number is the point: `/root` and `/root/g7` are walked because
			the closure names them, and inside `g7` only `l3` is — its NINE SIBLINGS are
			each individually clean and land on the rect they already had, so the skip
			catches them one by one on the way past. A subtree is not the unit; a node
			is. ]]
		expect(second.work.rectInserts).toBe(3)
		expect(second.work.rectInserts + second.work.skipped).toBe(first.work.arranged)
		local full = solver.solve(root, vp, {})
		expect(rectKey(second.rects)).toBe(rectKey(full.rects))
	end)

	it("ORACLE: every step of the script equals a forced full solve, at every viewport", function()
		--[[ THE DIFFERENTIAL, and it is the only thing that can catch a wrongly shared
			subtree: a stale entry is not a missing rect, it is LAST FRAME'S rect, which
			an arm compared only against itself will happily agree with. `c` re-solves
			the whole tree every refresh and is ground truth; 320x640 is in the set
			because the narrowest supported box is where a reserve arms and a container
			narrows, which is the one thing a matching rect cannot vouch for. ]]
		for _, view in device_views.VIEWS do
			local vp = { w = view.w, h = view.h }
			local a = world(true, true, vp, 12)
			local c = world(false, false, vp, 12)
			expect(snapshot(a)).toBe(snapshot(c))
			for step = 1, #SCRIPT do
				drive(a, step)
				drive(c, step)
				expect(snapshot(a)).toBe(snapshot(c))
			end
			-- the guard every differential needs: the mechanism actually engaged
			expect(a.controller.stats().partialSolves > 0).toBe(true)
		end
	end)

	it("CANARY: no reader mutates a shared rect or entry, over a long run of refreshes", function()
		--[[ The renderer hands `entry.rect` straight to the adapter (`rect_pass.applyOne`
			-> `adapter.setRect`), and the fake target keeps the reference — so holding
			the tables it was given IS holding the solver's own. Every reader in the
			commit walk sees the same structures: the hidden/composition/textFacts
			harvest, `commit_walks.textScale`/`textVerdicts`/`visible`/`hitRects`/
			`scrollRegions`, `hit_lift.refresh`, the animation record install and the
			rect pass. If any of them wrote into an entry or into the rect inside it, the
			next solve would hand that corruption back as "unchanged" and this case is
			where it surfaces. ]]
		local arm = world(true, true, { w = 400, h = 800 }, 60)
		local held: { [string]: any } = {}
		local values: { [string]: string } = {}
		for path, node in arm.adapter.liveNodes() do
			if node.rect ~= nil then
				held[path] = node.rect
				values[path] = `{node.rect.x},{node.rect.y},{node.rect.w},{node.rect.h}`
			end
		end
		expect(next(held) ~= nil).toBe(true)
		--[[ ...AND AN ENTRY FIELD, through the same real chain. `renderer.luau:2046-2055`
			harvests `entry.textFacts` into `nextTextFacts` BY REFERENCE, that becomes
			`lastTextFacts`, and `controller.textAt()` shallow-clones the outer map — so
			the tables below ARE the solver's own entry fields, held from outside. A
			reader writing into one is caught here; a reader writing a SCALAR entry
			field reaches the adapter through `visible`/`scrollRegions` and is caught by
			the oracle's full-solve differential instead. ]]
		local facts: { [string]: any } = {}
		local factValues: { [string]: string } = {}
		local function factKey(f: any): string
			local parts = {}
			for k, v in f do
				table.insert(parts, `{tostring(k)}={tostring(v)}`)
			end
			table.sort(parts)
			return table.concat(parts, ",")
		end
		for path, f in arm.controller.textAt() do
			facts[path] = f
			factValues[path] = factKey(f)
		end
		expect(next(facts) ~= nil).toBe(true)
		-- refreshes that change ONE row: every other row's rect is shared forward, so
		-- every other held table must still be that row's live rect, unchanged
		for i = 1, 12 do
			arm.items[1].n:set(1000 + i)
			arm.controller.refresh()
			for path, node in arm.adapter.liveNodes() do
				local kept = held[path]
				if kept ~= nil and node.rect == kept then
					expect(`{kept.x},{kept.y},{kept.w},{kept.h}`).toBe(values[path])
				end
			end
			for path, f in arm.controller.textAt() do
				if facts[path] == f then
					expect(factKey(f)).toBe(factValues[path])
				end
			end
		end
		-- the entry half of the canary is not vacuous: some `textFacts` tables really
		-- were shared forward rather than rebuilt, which is what makes holding them
		-- a test of the readers instead of a test of the allocator
		local shared = 0
		for path, f in arm.controller.textAt() do
			if facts[path] == f then
				shared += 1
			end
		end
		expect(shared > 0).toBe(true)
		-- ...and the run really did share rather than re-solve
		expect(arm.controller.stats().lastSkipped > 100).toBe(true)
	end)

	it("P1 x P2: a warm measure store and a warm rect map compose", function()
		--[[ The one interaction neither half owns. P1 serves a clean subtree its cached
			SIZE without recursing; P2 serves the same subtree its cached RECT without
			walking. Both are keyed off `reuse.dirtyContains`, so a disagreement shows up
			as geometry that is right in one arm and stale in the other — which is
			exactly what the full-solve arm below would catch. Three claims at once:
			the answer is a full solve's, insertions stay bounded, measures stay
			bounded. ]]
		local vp = { w = 400, h = 800 }
		local a = world(true, true, vp, 200)
		local c = world(false, false, vp, 200)
		-- the first incremental solve fills both the store and the map; the second is
		-- the steady state, which is every frame of a live surface
		for round = 1, 4 do
			local v = 4200 + round
			a.items[100].n:set(v)
			a.controller.refresh()
			c.items[100].n:set(v)
			c.controller.refresh()
			expect(snapshot(a)).toBe(snapshot(c))
		end
		local warm = a.controller.stats()
		expect(warm.lastRectInserts <= 8 * DEPTH).toBe(true)
		expect(warm.lastMeasured <= 8 * DEPTH).toBe(true)
		expect(warm.lastSkipped > 900).toBe(true)
		-- and the full-solve arm is what those two numbers are bounded AGAINST
		local cold = c.controller.stats()
		expect(cold.lastRectInserts).toBe(HEAD_NODES + ROW_NODES * 200)
		expect(cold.lastMeasured > 500).toBe(true)
	end)

	it("THE FINDINGS LIST IS FLAT over 100 refreshes with a malformed subtree in the SKIP", function()
		--[[ THE REPLAY THAT COPIED ITSELF FORWARD (RED-TEAM 2026-09-02, HIGH 2). `solve`
			replays the previous solve's findings for every filer this solve did not
			WALK — an arrange fact — while the four measure-time filers are inside the
			skipped subtree and are measured every solve anyway, freshly or from the
			cross-solve slate. So each frame filed the finding AND replayed last frame's
			copy of it: 605 findings at frame 600 against a full solve's 3, an unbounded
			list copied forward by every solve, with `controller.diagnostics()` cloning
			it for every caller.

			IT WAS INVISIBLE TO THE SPECS THAT WATCH THIS CHANNEL because `findings`
			above compares the SET (see its own comment: multiplicity has never been a
			contract, and it still is not). The COUNT is what grew, so the count is what
			this case reads — as a bound, not as a number: the arms legitimately differ
			in how many times a solve measures the malformed box. ]]
		local vp = { w = 400, h = 800 }
		local arms: { { name: string, arm: Arm } } = {
			{ name = "incremental + cache", arm = world(true, true, vp, 40) },
			{ name = "incremental, no cache", arm = world(true, false, vp, 40) },
			{ name = "full solve (oracle)", arm = world(false, false, vp, 40) },
		}
		for _, entry in arms do
			local arm = entry.arm
			-- THREE refreshes to reach the steady state, and the number is measured
			-- rather than chosen: the first one after `initialRender` still fills the
			-- map and the store, and measures the malformed box one more time than a
			-- settled frame does (2 findings, then 1). Then a hundred more that dirty
			-- ONE leaf far from the malformed box.
			for warm = 1, 3 do
				arm.items[10].n:set(-warm)
				arm.controller.refresh()
			end
			local settled = #arm.controller.diagnostics()
			local settledSet = findings(arm.controller)
			expect(`{entry.name}: {settled > 0}`).toBe(`{entry.name}: true`)
			for i = 1, 100 do
				arm.items[10].n:set(i)
				arm.controller.refresh()
			end
			-- FLAT. Not "bounded by something generous": the list a hundred frames later
			-- is the list one frame in, and the findings themselves are unchanged.
			expect(`{entry.name}: {#arm.controller.diagnostics()}`).toBe(`{entry.name}: {settled}`)
			expect(`{entry.name}: {findings(arm.controller)}`).toBe(`{entry.name}: {settledSet}`)
		end
		-- ...and the SET the two incremental arms report is the full solve's, which is
		-- the half a count can never say
		expect(findings(arms[1].arm.controller)).toBe(findings(arms[3].arm.controller))
		expect(findings(arms[2].arm.controller)).toBe(findings(arms[3].arm.controller))
	end)
end)
