--!strict
--[[ BOUNDARY-ROOTED PARTIAL SOLVES FOR STRUCTURAL CHANGES (perf campaign P5) —
	the demonstrator and its oracle.

	WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, at the HEAD that
	shipped P1-P4). P1 gave `measure` a cross-solve slate, P2 made the arrange skip
	O(touched), P3 stopped rebuilding the `solver.Node` tree and P4 stopped re-walking
	the commit — and all four are armed by ONE thing, the `reuse` set the renderer
	hands the solver. `refresh` refused to build one the moment any dirty entry was
	`structure`, so an add, a remove or a reorder paid the pre-campaign price in full:
	on `killfeed_nameplates` L (904 mounted nodes) an `addItem` step cost **8.05 ms —
	`measure` 2.06 ms for 2,209 measures, `arrange` 3.54 ms, commit 1.83 ms** — while
	the same tree's UPDATE steps had already fallen to 0.345 ms. `war_room_inventory`
	L (7,500 nodes) paid an 85 ms p95 on its reorder steps.

	THE FIX is not a second solver. `render/structural_scope.luau` carries the whole
	argument — why re-rooting IS the reuse set in Stage 2 v2, what the boundary
	qualifies, and the invalidation each of the four other mechanisms is owed.

	THE DEMONSTRATOR (D-P5) is `work.measured + work.arranged` after an `addItem` on a
	600-row list that sits beside a 600-node sibling the change cannot reach. It is a
	pair of COUNTERS, not a clock, and the claim is that the work is bounded by the
	LIST REGION rather than by the tree. RED at pre-fix HEAD and the run is in the task
	report; the `structuralReuse = false` arm below is that build, kept, and is what
	the bound is asserted against rather than against a remembered number.

	AND THE HONEST FLOOR IS ASSERTED BESIDE IT. An insert at the FRONT of a vertical
	list moves every row after it, so O(shifted) is irreducible and the bound is the
	REGION, not O(1). The case that inserts at the front asserts both halves: the work
	is at least the rows that moved, and it is still bounded by the region rather than
	by the tree. A reorder is the same shape at full width — every row moves — and its
	win is the MEASURE half alone, which is exactly what the numbers say.

	THE ORACLE, and it is why this file is longer than the fix. A partial solve that
	skips a subtree it should have walked leaves LAST FRAME'S geometry, which an arm
	compared only against itself agrees with. So the differential is the whole painted
	surface plus the adapter's ORDERED operation log, compared position for position
	against the same surface with `structuralReuse = false`, after every step of a
	script, at every viewport in the device matrix including 320x640 — plus a second
	differential against an arm that reuses NOTHING, which is the only arm that cannot
	be stale about anything.

	THE FIXTURE IS `measure_reuse.spec`'s, `rect_cow.spec`'s, `node_reuse.spec`'s and
	`commit_scope.spec`'s, deliberately: the five stores are invalidated off the same
	events and a divergence between the files' fixtures would be a divergence in what
	"the same case" means. THE SCRIPT IS THAT FAMILY'S PLUS FOUR, and the four are
	P5's own axes rather than a preference:

	  · a REORDER (no key enters or leaves; every rect moves) — the war_room shape;
	  · an insert in the MIDDLE (the shifted set is a suffix, not the tree);
	  · a `When` toggled OFF and ON with no refresh between, which re-creates a
	    subtree AT A PATH THAT NEVER LEFT — the one case a removal sweep cannot see
	    and the reason `structural_scope.widen` exists;
	  · a `ForEach` key removed and re-added the same way, with a TRANSITION declared
	    so the row is retiring when it comes back (`mount.luau`'s RE-ENTRY MID-EXIT
	    branch, which hands back the SAME mounted row — same table, same scope, same
	    instances — and is therefore the case where P3's table key legitimately HITS
	    and the slate legitimately survives).

	MUTATIONS RUN, 2026-09-02: twelve, of which ELEVEN bite —

	  | mutation                                              | result   |
	  | `widen` is a no-op                                    | 1 red    |
	  | the build collects no ids for `widen` to spend        | 1 red    |
	  | `rect_pass` records a node it has no handle for       | 1 red    |
	  | the ancestor closure is dropped (`widen` alone)       | 1 red    |
	  | the boundary walk stops at the first ancestor         | 3 red    |
	  | `commonAncestor` compares characters, not segments    | 1 red    |
	  | the departed path's rect entry is not swept           | 1 red    |
	  | the departed node's findings are not swept            | 1 red    |
	  | the skip count is not repaired from the tree          | 1 red    |
	  | a served subtree's size is not counted                | 3 red    |
	  | a pathless structural entry does not refuse           | 1 red    |
	  | the root qualification ignores a moved stamp          | DOES NOT |

	AND THREE OF THEM ONLY BITE BECAUSE THE CASE WAS CORRECTED. The re-created-subtree
	case first gave its branch a FREE outer box, so the new build measured to a
	different size, the parent placed it at a different rect and the arrange skip
	refused itself — the case passed with the fix removed. The pathless-entry refusal
	was first driven with a list holding ONLY that entry, which refuses for a second
	reason. And the departed-finding case first used a finding the PARENT files about
	the child, which a walked parent corrects by re-filing.

	THE ROOT QUALIFICATION IS A RECORDED NULL RESULT and is kept. `plan.atRoot` plus a
	moved measure stamp is the one pairing no route through the public API produces
	today: every geometry and theme write solves inside its own settle phase, so the
	stamp is already current by the time a structural `refresh` runs. The predicate is
	driven directly instead (THE REFUSALS, below), and the renderer's half stays
	because the day an env fact reaches a solve WITHOUT its own settle — a text-metrics
	epoch flip is the standing candidate — a re-solve rooted at the solve root would be
	rooted at an offer that had moved under it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local large_text = require("./lib/large_text")
-- the module under test, driven directly for the two refusals no surface can reach
local structural_scope = require("../src/render/structural_scope")

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

--[[ THE FIXTURE. 200 rows of 5 nodes plus a 10-node head is 1 010 layout nodes, and
	it is the one `measure_reuse.spec`, `rect_cow.spec` and `node_reuse.spec` carry —
	see the header. It holds the shapes the risk lives in rather than plain boxes: a
	truncating `disclose` label and a `compactLabel` ladder (published verdicts), a
	ScrollView (a canvas and a bar reserve), a `containerRelative` box whose wrapper
	never moves, a `ViewThatFits` (a hidden losing candidate, which is what the
	harvest's own set is about), one malformed box that FILES A DIAGNOSTIC, and a
	`When` branch and an `ErrorBoundary` view so all three structural reconcilers are
	spliced into the flow — and a spliced region is exactly the node shape that has no
	rect entry of its own. ]]
type Arm = { core: any, env: any, controller: any, adapter: any, rows: any, items: any, wide: any, branch: any }

--[[ THE FAMILY'S OWN NODE ACCOUNTING, carried verbatim. TEN, and the three that are
	NOT in it are the point: `UI.ForEach`, `UI.When` and
	`UI.ErrorBoundary` are structural regions that own MOUNTING, not layout, so
	`toLayoutNode` splices their children into the enclosing flow and emits no node for
	the region itself. Scroll, Wrap, Bar, Bad, Fits and its two candidates, Extra (the
	When's branch, mounted because it starts ON), Held (the ErrorBoundary's view), List. ]]
local HEAD_NODES = 10
local ROW_NODES = 5
-- Scroll > List > Row > V, the deepest live chain (`Rows` splices away). Carried
-- with the fixture rather than pruned: this family's four files keep one block, and
-- a constant that differs between them is a fixture that differs between them.
local DEPTH = 4

local function world(
	structural: boolean,
	incremental: boolean,
	cache: boolean,
	viewport: { w: number, h: number },
	rowCount: number
): Arm
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
		layoutNodeReuse = cache,
		structuralReuse = structural,
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

--[[ EVERY LIVE NODE'S RECT AND EVERY PROPERTY IT CARRIES, plus the three per-path
	fields the walks own that are not props — visibility, the hit expander and the
	scroll canvas. `rect_cow.spec` settled the first half; the second half is added
	here because those three are exactly what the pruned walks stop writing if the
	prune is wrong, and none of them is a prop. ]]
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
		local hit = node.hitRect
		local region = node.scrollRegion
		table.insert(
			out,
			`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
				.. `|vis={tostring(node.visible)}`
				.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
				.. `|canvas={if region
					then `{region.axis},{region.contentW},{region.contentH},{region.hostW},{region.hostH},{region.indicators}`
					else "-"}`
		)
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

-- ...and the OTHER two solve outputs `harvest` now maintains in place rather than
-- rebuilding: the hidden set the focus map filters on and the composition
-- resolutions. Both were rebuilt from the whole rect map before P4.
local function published(controller: any): string
	local out = {}
	for path in controller.hiddenRoots() do
		table.insert(out, `hidden {path}`)
	end
	for path, c in controller.compositionAt() do
		table.insert(out, `comp {path}={tostring(type(c) == "table" and c.id or c)}`)
	end
	table.sort(out)
	return `{table.concat(out, "\n")}\nepoch-moved={tostring(controller.structureEpoch() > 0)}`
end

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
	return `{painted(arm.adapter)}\n--facts--\n{facts(arm.controller)}\n--pub--\n{published(arm.controller)}\n--diag--\n{findings(
		arm.controller
	)}`
end

--[[ THE ADAPTER'S ORDERED OPERATION LOG, which is the half a state comparison cannot
	give. A minimal-write walk that skips a node it should have written leaves the
	state it already had, so two arms can agree on every field and still have made
	different journeys — and one of those journeys is a frame the player saw wrong.
	The log is compared position for position. ]]
local function opsSince(arm: Arm, from: number): { string }
	local all = arm.adapter.ops()
	local out: { string } = {}
	for i = from + 1, #all do
		--[[ A TABLE-VALUED PROP LOGS ITS ADDRESS, and two arms never share one. The
			fake target writes `prop <path>.<name>=<tostring(value)>`, so `textFont` —
			the one prop on this surface whose value is a table — makes every arm's log
			differ at every text node for a reason that is not a behaviour difference.
			Canonicalised here rather than compared: what the two arms MUST agree on is
			WHICH property of WHICH node was written and IN WHAT ORDER, and the table's
			own contents are compared field by field by `painted` above. ]]
		table.insert(out, (string.gsub(all[i], "table: 0x%x+", "<table>")))
	end
	return out
end

--[[ THE SCRIPT, applied identically to every arm so the comparison is over the same
	HISTORY rather than the same state. The first thirteen steps are the family's,
	step for step; the last two are P4's own axes (see the header). ]]
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
	--[[ P4'S OWN TWO. The theme swap is AXIS 3 — the solve-wide stamp: no node is
		dirtied and no rect entry records it, so a prune that only watched those two
		would serve the old font and the old type role to every text node on the
		surface (measured: `node_reuse.spec`'s theme case reported exactly that when
		this walk's arming was read one commit late). ]]
	{
		name = "theme: a swap APPLIED mid-run moves the solve-wide stamp",
		run = function(arm: Arm)
			arm.env:set("themeMetrics", large_text.THEMES[2].metrics)
		end,
	},
	{
		name = "one leaf under the new theme",
		run = function(arm: Arm)
			arm.items[4].n:set(808)
		end,
	},
}

--[[ P5'S OWN FOUR, appended to the family's fifteen. Each is a shape the other four
	mechanisms never had to answer for, because a structural change used to take a full
	solve and a full commit. ]]
table.insert(SCRIPT, {
	name = "structure: the rows are REORDERED — every rect moves, no key enters or leaves",
	run = function(arm: Arm)
		local next_ = {}
		for i = #arm.items, 1, -1 do
			table.insert(next_, arm.items[i])
		end
		arm.rows:set(next_)
	end,
})
table.insert(SCRIPT, {
	name = "structure: a row is inserted in the MIDDLE — the shifted set is a suffix",
	run = function(arm: Arm)
		local next_ = table.clone(arm.rows:get())
		local fresh = { id = "rMid", n = arm.core:signal(31) }
		table.insert(next_, math.max(1, #next_ // 2), fresh)
		table.insert(arm.items, fresh)
		arm.rows:set(next_)
	end,
})
table.insert(SCRIPT, {
	name = "structure: the When branch leaves and returns with NO refresh between",
	run = function(arm: Arm)
		--[[ THE CASE A REMOVAL SWEEP CANNOT SEE, and the reason
			`structural_scope.widen` exists. Two writes, one refresh: the branch is
			disposed and re-mounted, so the path `/Scroll/Branch/then/Extra` is alive at
			the sync with a DIFFERENT mounted node under it. Nothing departed, so nothing
			is swept — and a path-keyed slate, a forwarded rect entry and a recorded
			commit entry would all answer for content that no longer exists. ]]
		arm.branch:set(false)
		arm.branch:set(true)
	end,
})
table.insert(SCRIPT, {
	name = "structure: a ForEach key leaves and returns with NO refresh between",
	run = function(arm: Arm)
		local without = {}
		for _, item in arm.items do
			if item.id ~= "r2" then
				table.insert(without, item)
			end
		end
		arm.rows:set(without)
		arm.rows:set(table.clone(arm.items))
	end,
})

local function drive(arm: Arm, step: number)
	SCRIPT[step].run(arm)
	arm.controller.refresh()
end

--[[ ── D-P5's OWN FIXTURE ─────────────────────────────────────────────────────
	The family fixture above is the ORACLE's, because the five stores must be
	compared on one tree. The demonstrator needs a different shape and says why: a
	bound has to be able to distinguish "the region" from "the tree", so the tree must
	hold something the change provably cannot reach. HEADER (600 nodes) sits ABOVE the
	list, so an append moves nothing in it; LIST is the region; FOOT is the one node
	below that an append does move. ]]
local HEAD_ROWS = 300
local LIST_ROWS = 600
-- the list's own layout nodes plus the chain above it that must be walked to reach
-- them. The `ForEach` region splices away and owns none.
local REGION = LIST_ROWS + 4

type Bench = { core: any, controller: any, adapter: any, rows: any, items: { any }, tick: any }

local function bench(structural: boolean, rowCount: number): Bench
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
	local head = {}
	for i = 1, HEAD_ROWS do
		table.insert(
			head,
			UI.HStack({
				id = `H{i}`,
				padding = 0,
				gap = 0,
				children = { UI.Box({ id = "Dot", width = px(6), height = px(6) }) },
			})
		)
	end
	local items = {}
	for i = 1, rowCount do
		table.insert(items, { id = `r{i}`, n = core:signal(i) })
	end
	local rows = core:signal(table.clone(items))
	local tick = core:signal(1)
	local bp = UI.VStack({
		id = "Root",
		padding = 0,
		gap = 0,
		children = {
			UI.VStack({ id = "Header", padding = 0, gap = 0, children = head }),
			UI.VStack({
				id = "List",
				padding = 0,
				gap = 0,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.Text({
								id = "V",
								textSize = 12,
								text = core:memo(function(use: any)
									return tostring(use(item.n))
								end),
							})
						end,
					}),
				},
			}),
			UI.Text({
				id = "Foot",
				textSize = 12,
				text = core:memo(function(use: any)
					return tostring(use(tick))
				end),
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		structuralReuse = structural,
	})
	controller.initialRender()
	-- two warm frames, so every cross-solve store is full and the bound is about the
	-- steady state rather than about a first fill
	for i = 2, 3 do
		tick:set(i)
		controller.refresh()
	end
	return { core = core, controller = controller, adapter = adapter, rows = rows, items = items, tick = tick }
end

local function append(b: Bench)
	local next_ = table.clone(b.rows:get())
	local fresh = { id = `x{#next_}`, n = b.core:signal(0) }
	table.insert(next_, fresh)
	table.insert(b.items, fresh)
	b.rows:set(next_)
	b.controller.refresh()
end

local function prepend(b: Bench)
	local next_ = table.clone(b.rows:get())
	local fresh = { id = `y{#next_}`, n = b.core:signal(0) }
	table.insert(next_, 1, fresh)
	table.insert(b.items, fresh)
	b.rows:set(next_)
	b.controller.refresh()
end

local function work(b: Bench): number
	local s = b.controller.stats()
	return s.lastMeasured + s.lastArranged
end

describe("boundary-rooted structural solves (P5)", function()
	it("DEMONSTRATOR D-P5: an addItem at N=600 is bounded by the LIST REGION, not the tree", function()
		--[[ THE BOUND, PINNED FROM THE FIXTURE'S SHAPE RATHER THAN FITTED. An append at
			the end of the list moves the list's own box and the one node below it; the
			600 rows already placed keep their rects and the 600-node header cannot be
			reached at all. The honest ceiling is therefore the region — the rows the
			enclosing stack has to scan plus the chain down to them — and `2 * REGION`
			leaves an ordinary layout edit room to move the constant.

			MEASURED on this fixture: **4,517 at the `structuralReuse = false` arm
			(3,311 measured + 1,206 arranged) against 9 with the fix (5 + 4)**, and the
			run at pre-fix HEAD is in the task report. ]]
		local b = bench(true, LIST_ROWS)
		append(b)
		append(b)
		expect(work(b) > 0).toBe(true)
		expect(work(b) <= 2 * REGION).toBe(true)
		-- ...and the solve underneath it really was a partial one, rooted somewhere
		local s = b.controller.stats()
		expect(s.structuralPartialSolves > 0).toBe(true)
		expect(s.lastStructuralBoundary).toBe("/Root")
		expect(s.lastSkipped > LIST_ROWS).toBe(true)
	end)

	it("...and the same append with P5 OFF costs the whole tree, twice over — the control", function()
		--[[ THE NEGATIVE CONTROL THE DEMONSTRATOR IS MEANINGLESS WITHOUT, and it is the
			pre-fix build rather than a model of it: `structuralReuse = false` leaves P1,
			P2, P3 and P4 exactly as they are and takes only the structural set away. The
			measure half is where the factor lives — the ancestor closure reaches the
			root on every solve, so distributing the root stack measures every subtree a
			second time, which is the 2.4 N this campaign opened on. ]]
		local off = bench(false, LIST_ROWS)
		append(off)
		append(off)
		local s = off.controller.stats()
		expect(s.structuralPartialSolves).toBe(0)
		expect(s.lastStructuralBoundary).toBeNil()
		expect(work(off) > 4 * REGION).toBe(true)

		local on = bench(true, LIST_ROWS)
		append(on)
		append(on)
		-- two orders of magnitude on the same edit
		expect(work(on) * 50 < work(off)).toBe(true)
	end)

	it("THE HONEST FLOOR: an insert at the FRONT is O(shifted), and shifted IS the region", function()
		--[[ THE HALF A BOUND ALONE WOULD HIDE. A vertical stack has no way to move one
			row without moving every row after it, so an insert at the front re-arranges
			the whole list and no mechanism in this campaign can make that smaller. What
			P5 changes is the OTHER half: the rows keep their measured sizes, so the
			measure pass stays flat while the arrange pass pays the shift.

			BOTH DIRECTIONS ARE ASSERTED, because a bound with no floor beside it is a
			claim that could be met by doing nothing at all. MEASURED: **605 arranged
			and 5 measured, against 601 skipped** — the list moved and the header did
			not, and the measure pass paid nothing for either. ]]
		local b = bench(true, LIST_ROWS)
		prepend(b)
		prepend(b)
		local s = b.controller.stats()
		-- the floor: the rows really did move, and the arrange pass really did pay
		expect(s.lastArranged > LIST_ROWS // 2).toBe(true)
		-- ...and it is still the REGION, not the tree: the 300-row header is untouched
		expect(s.lastArranged <= 2 * REGION).toBe(true)
		expect(s.lastSkipped >= HEAD_ROWS).toBe(true)
		-- ...and the measure half is flat, which is the part P5 actually bought here
		expect(s.lastMeasured <= 2 * REGION).toBe(true)
		local off = bench(false, LIST_ROWS)
		prepend(off)
		prepend(off)
		expect(off.controller.stats().lastMeasured > 2 * work(b)).toBe(true)
	end)
end)

describe("P5's oracle: the surface is identical, step for step, arm for arm", function()
	it("ORACLE: the whole painted surface and the ORDERED op log equal the full-solve arm's", function()
		--[[ THE DIFFERENTIAL THAT CAN CATCH A WRONGLY SKIPPED SUBTREE. A skipped solve
			is not a missing rect — it is LAST FRAME'S rect, which an arm compared only
			against itself agrees with. `b` is the same surface with `structuralReuse =
			false` and everything else identical, so a divergence names THE STRUCTURAL
			SET and not the four mechanisms it arms. Both the ordered log and the whole
			surface are compared after every step, at every viewport in the matrix
			including the 320x640-class rows.

			THIS IS THE CASE THAT FOUND THE ROUND'S TWO REAL DEFECTS, and neither was
			visible to a counter: the ancestor closure skipped a subtree a `When` had
			re-created under a path that never left, and `rect_pass` recorded a node it
			had no handle for. Seventeen suite cases went red on the first and six on
			the second. ]]
		for _, view in device_views.VIEWS do
			local vp = { w = view.w, h = view.h }
			local a = world(true, true, true, vp, 12)
			local b = world(false, true, true, vp, 12)
			expect(snapshot(a)).toBe(snapshot(b))
			expect(opsSince(a, 0)).toEqual(opsSince(b, 0))
			local marka, markb = #a.adapter.ops(), #b.adapter.ops()
			local engaged = 0
			for step = 1, #SCRIPT do
				drive(a, step)
				drive(b, step)
				expect(`{SCRIPT[step].name}: {snapshot(a)}`).toBe(`{SCRIPT[step].name}: {snapshot(b)}`)
				expect(opsSince(a, marka)).toEqual(opsSince(b, markb))
				marka, markb = #a.adapter.ops(), #b.adapter.ops()
				if a.controller.stats().structuralPartialSolves > engaged then
					engaged = a.controller.stats().structuralPartialSolves
				end
			end
			--[[ THE GUARD EVERY DIFFERENTIAL NEEDS. Nine of the nineteen steps are
				structural and every one of them must have taken the partial road, or
				this case is comparing a build against itself. MEASURED at nine on every
				view in the matrix. ]]
			expect(engaged >= 8).toBe(true)
			expect(b.controller.stats().structuralPartialSolves).toBe(0)
		end
	end)

	it("ORACLE: and it equals a surface with every cross-solve mechanism OFF", function()
		--[[ The other end of the ladder. The case above isolates P5; this one asserts
			all five together against a build that reuses NOTHING — a full solve, a full
			tree build, no measure store and no structural set — which is the only arm
			that cannot be stale about anything. Ops are NOT compared here and that is
			deliberate: a full-solve arm re-inserts every entry, so `rect_pass`'s value
			diff writes the same numbers back and its log is legitimately a different
			length. State is the comparable thing. ]]
		local vp = { w = 400, h = 800 }
		local a = world(true, true, true, vp, 12)
		local c = world(false, false, false, vp, 12)
		expect(snapshot(a)).toBe(snapshot(c))
		for step = 1, #SCRIPT do
			drive(a, step)
			drive(c, step)
			expect(`{SCRIPT[step].name}: {snapshot(a)}`).toBe(`{SCRIPT[step].name}: {snapshot(c)}`)
		end
	end)

	it("P1 x P2 x P3 x P4 x P5: all five warm, one addItem, every counter bounded", function()
		--[[ THE COMPOSITION CASE. Each mechanism has its own counter and each bound is
			pinned from the fixture rather than fitted; the point of running them
			together is that the four earlier ones are armed BY the fifth on this frame,
			so a regression in any of the five shows up here as a number rather than as
			a rendering nobody looks at. The snapshot is compared against the
			reuse-nothing arm, so "bounded" and "correct" are asserted in one case. ]]
		local a = world(true, true, true, { w = 400, h = 800 }, 200)
		local c = world(false, false, false, { w = 400, h = 800 }, 200)
		for _, arm in { a, c } :: { Arm } do
			-- warm, then the structural step itself
			arm.items[3].n:set(11)
			arm.controller.refresh()
			local next_ = table.clone(arm.items)
			local fresh = { id = "rP5", n = arm.core:signal(5150) }
			table.insert(next_, fresh)
			arm.items[#arm.items + 1] = fresh
			arm.rows:set(next_)
			arm.controller.refresh()
		end
		local s = a.controller.stats()
		expect(s.structuralPartialSolves).toBe(1)
		expect(s.lastStructuralBoundary).toBe("/Scroll")
		-- P1 (measure slates), P2 (rect inserts), P3 (node builds), P4 (commit visits)
		expect(s.lastMeasured <= 64).toBe(true)
		expect(s.lastRectInserts <= 64).toBe(true)
		expect(s.lastNodeBuilds <= 8 * DEPTH).toBe(true)
		expect(s.lastCommitVisits <= 256).toBe(true)
		-- ...and the identity the repair restores, on the frame that moved the count
		expect(s.lastRectInserts + s.lastSkipped).toBe(HEAD_NODES + ROW_NODES * 201)
		expect(snapshot(a)).toBe(snapshot(c))
	end)

	it("THE BOUNDARY QUALIFIES A REAL NODE: a fixed-size viewport absorbs, an auto-sized ancestor does not", function()
		--[[ THE BRIEF'S TWO CASES, BOTH DRIVEN. A node that is `fixed` on both axes
			cannot change size when its content does, so the re-solve is rooted THERE;
			with only auto-sized ancestors the walk runs out and the boundary is the
			SOLVE ROOT, whose offer is the content rect. Both are partial solves — the
			set is the same either way, which is the correction
			`render/structural_scope`'s header makes — and the boundary is what says
			WHERE the claim is anchored.

			MEASURED on the FacetBench workload shapes, and it is worth recording
			because it is the answer to "can this ever engage": NONE of the three
			benchmark surfaces has a fixed-size box above its lists, so all three root
			at the solve root. The fixed case below is the one this repository can
			build, and it is the one a real scrolling list viewport produces. ]]
		local function listed(fixed: boolean): any
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
			local items = { { id = "a" }, { id = "b" } }
			local rows = core:signal(items)
			local region = UI.ForEach({
				id = "Rows",
				items = rows,
				key = function(item: any)
					return item.id
				end,
				row = function(item: any)
					return UI.Box({ id = "R", width = px(40), height = px(10) })
				end,
			})
			local host = if fixed
				then UI.VStack({
					id = "Viewport",
					padding = 0,
					gap = 0,
					width = px(200),
					height = px(300),
					children = { region },
				})
				else UI.VStack({ id = "Viewport", padding = 0, gap = 0, children = { region } })
			local bp = UI.VStack({ id = "Root", padding = 0, gap = 0, children = { host } })
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			return {
				controller = controller,
				add = function()
					local next_ = table.clone(rows:get())
					table.insert(next_, { id = `k{#next_}` })
					rows:set(next_)
					controller.refresh()
				end,
			}
		end
		local fixed = listed(true)
		fixed.add()
		expect(fixed.controller.stats().lastStructuralBoundary).toBe("/Root/Viewport")
		local auto = listed(false)
		auto.add()
		expect(auto.controller.stats().lastStructuralBoundary).toBe("/Root")
		-- both are partial, which is the half the boundary does NOT decide
		expect(fixed.controller.stats().structuralPartialSolves).toBe(1)
		expect(auto.controller.stats().structuralPartialSolves).toBe(1)
	end)

	it("THE REFUSALS, driven against the module itself — the two no surface can reach", function()
		--[[ `structural_scope.plan` is pure, so the arms a live surface cannot produce
			are asserted here rather than left as prose. Both refusals are the
			conservative direction: `nil` is the pre-P5 full solve, exactly.

			THE ROOT'S QUALIFICATION IS THE RENDERER'S HALF and is asserted where it is
			spent — a plan whose boundary IS the solve root is refused on a solve whose
			stamp moved. No path through the public API can produce that pairing today
			(a geometry write solves inside its own settle, so the stamp is already
			current by the time a structural refresh runs), which is exactly why the
			predicate is driven directly instead. ]]
		local function parentOf(path: string): any
			if path == "/Root/List" then
				return { path = "/Root" }
			end
			return nil
		end
		local function noLayout(): any
			return nil
		end
		local dirty = { { path = "/Root/List", class = "structure" } }
		local plan = structural_scope.plan(dirty, "/Root", parentOf, noLayout)
		expect(plan ~= nil).toBe(true)
		expect((plan :: any).boundary).toBe("/Root")
		expect((plan :: any).atRoot).toBe(true)
		expect((plan :: any).contains["/Root/List"]).toBe(true)
		expect((plan :: any).contains["/Root"]).toBe(true)
		-- an absorbing ancestor takes the boundary off the root
		local absorbing = structural_scope.plan(dirty, "/Root", parentOf, function(): any
			return { width = { type = "fixed", px = 100 }, height = { type = "fixed", px = 100 } }
		end)
		expect((absorbing :: any).boundary).toBe("/Root")
		expect((absorbing :: any).atRoot).toBe(true)
		--[[ REFUSAL 1: a structural entry with no path names no subtree, so nothing can
			be proved about what it did not touch. MIXED with a real entry deliberately:
			a list holding ONLY the pathless one refuses for a second reason (no
			structural path was seen at all), so it would stay green with the guard
			deleted — the mutation is what said so. ]]
		expect(
			structural_scope.plan(
				{ { path = "/Root/List", class = "structure" }, { path = nil, class = "structure" } },
				"/Root",
				parentOf,
				noLayout
			)
		).toBeNil()
		-- REFUSAL 2: a structural path the parent map can no longer reach
		expect(structural_scope.plan({ { path = "/Gone/List", class = "structure" } }, "/Root", parentOf, noLayout)).toBeNil()
		-- ...and a refresh with no structural entry at all is not this branch's business
		expect(structural_scope.plan({ { path = "/Root/List", class = "measure" } }, "/Root", parentOf, noLayout)).toBeNil()
		-- the segment-boundary rule, which a character-wise prefix gets wrong
		expect(structural_scope.commonAncestor("/L/[k1]", "/L/[k10]")).toBe("/L")
		expect(structural_scope.commonAncestor("/L/[k1]/A", "/L/[k1]/B")).toBe("/L/[k1]")
		expect(structural_scope.commonAncestor("/L", "/L/[k1]")).toBe("/L")
		-- the offer-free absorbing predicate, both verdicts
		expect(structural_scope.absorbs({ type = "fixed", px = 10 })).toBe(true)
		expect(structural_scope.absorbs({ type = "containerRelative", fraction = 0.5 })).toBe(true)
		expect(structural_scope.absorbs({ type = "fill", weight = 1 })).toBe(false)
		expect(structural_scope.absorbs(nil)).toBe(false)
	end)

	it("RETIRE AND RE-ENTRY MID-EXIT: the row that comes back is the SAME row, and it is served", function()
		--[[ `mount.luau`'s re-entry branch hands back the SAME mounted row — same
			table, same scope, same instances — when a key returns while its exit
			transition is still playing. That is the one structural case where P3's
			table key legitimately HITS, so the row is not in `builtIds`, its slate
			survives and `arrange` may skip it; what DID change is where it sits in the
			parent's flow, and the region's own `structure` dirty is what marks that.

			The claim is that P5 changes NOTHING here, so the assertion is the
			differential: the same script on a `structuralReuse = false` arm paints the
			same surface. The counters are read too, because "unchanged" would also be
			true of a mechanism that never engaged. ]]
		local function retiring(structural: boolean): any
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
			local items = { { id = "a" }, { id = "b" }, { id = "c" } }
			local rows = core:signal(items)
			local bp = UI.VStack({
				id = "Root",
				padding = 0,
				gap = 0,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						transition = { enter = "fade" },
						row = function(item: any)
							return UI.Text({ id = "T", textSize = 12, text = item.id })
						end,
					}),
				},
			})
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				structuralReuse = structural,
			})
			controller.initialRender()
			return { core = core, adapter = adapter, controller = controller, rows = rows, items = items }
		end
		local function shape(w: any): string
			local out = {}
			for path, node in w.adapter.liveNodes() do
				local r = node.rect
				table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|vis={tostring(node.visible)}`)
			end
			table.sort(out)
			return table.concat(out, "\n")
		end
		local a, b = retiring(true), retiring(false)
		for _, w in { a, b } do
			-- 'b' leaves and its exit begins; the row stays mounted, in place
			w.rows:set({ w.items[1], w.items[3] })
			w.controller.refresh()
			-- ...and comes back MID-EXIT, before the transition finished
			w.rows:set({ w.items[1], w.items[2], w.items[3] })
			w.controller.refresh()
		end
		expect(shape(a)).toBe(shape(b))
		expect(a.adapter.node("/Root/Rows/[b]/T") ~= nil).toBe(true)
		expect(a.controller.stats().structuralPartialSolves > 0).toBe(true)
		expect(b.controller.stats().structuralPartialSolves).toBe(0)
	end)

	it("THE BOUNDARY ANALYSIS still reports the tree, not the partial solve it followed", function()
		--[[ `controller.analyzeBoundaries` re-solves through a CLONE of the live
			`solveOpts`, and P1's review round had to null `reuse` and `measures` out of
			it for exactly this reason: a solve served from slates records almost nothing
			in `ctx.boundary` and every unrecorded node reads as "does not absorb". P5
			gives that clone a `reuse` on a structural frame too, so the null-out is now
			load-bearing on one more road. Driven after a real structural partial solve,
			which is the arm that did not exist when the null-out was written. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local items = { { id = "a" }, { id = "b" } }
		local rows = core:signal(items)
		local bp = UI.VStack({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.VStack({
					id = "Fixed",
					padding = 0,
					gap = 0,
					width = px(40),
					height = px(20),
					children = { UI.Box({ id = "In", width = px(10), height = px(10) }) },
				}),
				UI.ForEach({
					id = "Rows",
					items = rows,
					key = function(item: any)
						return item.id
					end,
					row = function()
						return UI.Box({ id = "R", width = px(30), height = px(10) })
					end,
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local before = controller.analyzeBoundaries().absorbingNodes
		expect(before > 0).toBe(true)
		for i = 1, 3 do
			local next_ = table.clone(rows:get())
			table.insert(next_, { id = `k{i}` })
			rows:set(next_)
			controller.refresh()
			expect(controller.stats().structuralPartialSolves).toBe(i)
			-- one more absorbing box per added row, and the fixed pair is still counted
			expect(controller.analyzeBoundaries().absorbingNodes).toBe(before + i)
		end
		-- ...and the analysis disturbed neither the surface nor the store it reads
		expect(controller.analyzeBoundaries().absorbingNodes).toBe(before + 3)
		expect(core:lastError()).toBeNil()
	end)
end)

--[[ ── THE THREE CASES THAT NEED THEIR OWN FIXTURE ────────────────────────────
	The family fixture cannot drive these and the reason is worth stating rather than
	working around: its `When` branch shows a CONSTANT, so re-creating it produces the
	same content and the same box — a divergence the differential cannot see because
	there is nothing to diverge. Each case below is the smallest surface that makes one
	of P5's three invalidation claims falsifiable. ]]

describe("P5: the three invalidation claims, each on the smallest surface that can break it", function()
	local function recreating(structural: boolean): any
		--[[ A `When` whose branch is BUILT FRESH EACH TIME, and whose OUTER BOX IS
			FIXED while its CONTENT changes. Both halves are load-bearing and the second
			one is the correction a mutation forced: with the outer box free, the new
			build measured to a different size, the parent placed it at a different rect
			and the arrange skip refused itself — so the case passed with the fix
			removed. A fixed outer box takes that away: the subtree lands on exactly the
			rect it already had, which is the one shape where "this cannot have changed"
			is decided by the SET and by nothing else.

			The path never changes and never leaves the tree — the two writes land in one
			refresh — so nothing departs, nothing is swept, and every per-path record the
			framework keeps is still pointing at the old subtree. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		local on = core:signal(true)
		local builds = 0
		local bp = UI.VStack({
			id = "Root",
			padding = 0,
			gap = 0,
			children = {
				UI.When({
					id = "Gate",
					condition = on,
					thenView = function()
						builds += 1
						return UI.VStack({
							id = "Body",
							padding = 0,
							gap = 0,
							width = px(120),
							height = px(60),
							children = {
								UI.Box({ id = "Say", width = px(10 + builds * 20), height = px(10 + builds * 10) }),
							},
						})
					end,
				}),
				UI.Box({ id = "Below", width = px(30), height = px(10) }),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			structuralReuse = structural,
		})
		controller.initialRender()
		return { core = core, adapter = adapter, controller = controller, on = on }
	end

	local function shape(w: any): string
		local out = {}
		for path, node in w.adapter.liveNodes() do
			local r = node.rect
			local text = if node.props ~= nil then tostring(node.props.text) else "-"
			table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{text}`)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end

	it("A SUBTREE RE-CREATED UNDER A PATH THAT NEVER LEFT is re-solved, not replayed", function()
		--[[ THE ROUND'S FIRST DEFECT, as a case. The ancestor closure marks the region
			and everything ABOVE it; the subtree the region re-created is a DESCENDANT,
			so the closure says nothing about it, its path is unchanged and its old rect
			is still in the map. `arrange` skipped it and handed the old entry forward.
			`structural_scope.widen` is what fixes it, and a no-op `widen` leaves this
			case painting the FIRST build's box under the SECOND build's text. ]]
		local a, b = recreating(true), recreating(false)
		for _, w in { a, b } do
			-- off and on with NO refresh between: one structural sync sees both
			w.on:set(false)
			w.on:set(true)
			w.controller.refresh()
		end
		expect(shape(a)).toBe(shape(b))
		--[[ THE NEGATIVE CONTROLS THIS CASE IS VACUOUS WITHOUT. The outer box is the
			same rect it always was — that is the point — so the evidence is INSIDE it:
			the second build's child is 30x30 where the first build's was 30x20, and a
			replayed subtree paints the first one. ]]
		local body = a.adapter.node("/Root/Gate/then/Body")
		expect(body ~= nil).toBe(true)
		expect(body.rect.w).toBe(120)
		local say = a.adapter.node("/Root/Gate/then/Body/Say")
		expect(say ~= nil).toBe(true)
		expect(`{say.rect.w}x{say.rect.h}`).toBe("50x30")
		expect(a.controller.stats().structuralPartialSolves > 0).toBe(true)
	end)

	it("A NODE THE COMMIT HAD NO HANDLE FOR is not recorded as committed", function()
		--[[ THE ROUND'S SECOND DEFECT, as a case, and it is the one that needed a
			SETTLE-PHASE SOLVE to reach. `structuralSync` runs inside `refresh`; the
			geometry settle does not run it at all. So a write that mounts a node and a
			geometry write in the SAME flush leave the settle solve arranging a node that
			has no handle yet — every write in the commit span is guarded on that handle,
			so nothing is spent, and recording it anyway says "committed with this entry"
			about an entry nothing was written for.

			Before P5 the structural refresh that followed rebuilt the map, so the entry
			was a new table, the record did not match and the rect landed. P5 hands the
			entry forward, `skip` matches, and the node keeps NO rect at all. MEASURED
			on the real surface: the Table's collapsed-column chip, `chip.rect` nil,
			six cases red across two files. ]]
		local function settled(structural: boolean): any
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
			local items: { any } = { { id = "a" } }
			local rows = core:signal(items)
			local bp = UI.VStack({
				id = "Root",
				padding = 0,
				gap = 0,
				children = {
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any)
							return item.id
						end,
						row = function(item: any)
							return UI.Box({ id = "R", width = px(30), height = px(10) })
						end,
					}),
				},
			})
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				structuralReuse = structural,
			})
			controller.initialRender()
			return {
				core = core,
				env = env,
				adapter = adapter,
				controller = controller,
				rows = rows,
				items = items,
			}
		end
		local a, b = settled(true), settled(false)
		for _, w in { a, b } do
			--[[ ONE TRANSACTION, TWO WRITES. The row mounts and the viewport moves in
				the same flush, so the geometry settle solves a tree that already holds
				the new row and a handle map that does not. The refresh after it is the
				structural one. ]]
			w.core:transaction(function()
				local next_ = table.clone(w.items)
				table.insert(next_, { id = "b" })
				w.rows:set(next_)
				w.env:set("viewportRect", { x = 0, y = 0, w = 380, h = 780 })
			end)
			w.controller.refresh()
		end
		local newRow = a.adapter.node("/Root/Rows/[b]/R")
		expect(newRow ~= nil).toBe(true)
		expect(newRow.rect ~= nil).toBe(true)
		expect(shape(a)).toBe(shape(b))
	end)

	it("A DEPARTED NODE'S FINDING IS NOT REPLAYED FOREVER", function()
		--[[ `solve` replays the previous solve's diagnostics for every node THIS solve
			did not walk, which is what keeps `controller.diagnostics()` honest about the
			parts of the screen that did not change. It was self-cleaning while a
			structural change rebuilt the map: a node that left simply had no entry any
			more. Now the map is written in place, so the removal sweep deletes the
			departed path's entry and `structural_scope.sweepDiagnostics` drops the
			findings whose FILER went with it. Without either, a box that is no longer
			mounted keeps reporting its overflow on every frame, forever. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		local items: { any } = { { id = "a" }, { id = "bad" } }
		local rows = core:signal(items)
		local bp = UI.VStack({
			id = "Root",
			padding = 0,
			gap = 0,
			width = px(100),
			children = {
				UI.ForEach({
					id = "Rows",
					items = rows,
					key = function(item: any)
						return item.id
					end,
					row = function(item: any)
						--[[ THE MALFORMED ONE FILES A FINDING IT IS ITSELF THE FILER OF,
							and that is the property this case needs rather than a
							preference: `inertPlacement` is filed by the PARENT about the
							child, and a parent that stays is walked on the frame the child
							leaves, so its finding is corrected by being re-filed. The
							aspect-on-both-axes finding is filed in `measureUncached` under
							the node's OWN id, so nothing else can correct it — the replay
							is the only thing keeping it alive. ]]
						if item.id == "bad" then
							return UI.Box({
								id = "R",
								width = { type = "aspect", ratio = 2 },
								height = { type = "aspect", ratio = 2 },
							})
						end
						return UI.Box({ id = "R", width = px(20), height = px(10) })
					end,
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local function names(): string
			local out = {}
			for _, d in controller.diagnostics() do
				table.insert(out, tostring(d.node))
			end
			table.sort(out)
			return table.concat(out, " ")
		end
		-- the finding is real, and it names the row that is about to leave
		expect(string.find(names(), "[bad]", 1, true) ~= nil).toBe(true)
		rows:set({ items[1] })
		controller.refresh()
		expect(controller.stats().structuralPartialSolves > 0).toBe(true)
		expect(string.find(names(), "[bad]", 1, true)).toBeNil()
		-- ...and a solve after it does not resurrect the finding either
		rows:set({ items[1] })
		controller.refresh()
		expect(string.find(names(), "[bad]", 1, true)).toBeNil()
	end)
end)
