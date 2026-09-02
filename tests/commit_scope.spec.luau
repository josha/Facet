--!strict
--[[ THE COMMIT'S OWN SKIP (perf campaign P4) — the demonstrator and its oracle.

	WHAT THE PROFILE FOUND (FacetBench, headless Lune, 2026-09-01, `battle_hud` at
	5 109 nodes, measured AFTER P1, P2 and P3 had landed). A one-leaf update arranged
	FIVE nodes and then spent **3.99 ms of `Facet/commit`** — 62 % of the whole step —
	to make about four writes. The commit walked the live tree SEVEN times: the six
	`commit_walks` loops (2.23 ms), `rect_pass.apply` (1.29 ms), and a loop over every
	entry in the rect map to re-harvest the hidden set, the compositions and the text
	facts. Every one of those walks is minimal-write, so the writes were right; the
	TRAVERSAL was the cost, and it was the last O(N) term in an update.

	THE FIX is the arrange skip's mirror, and it borrows both of its inputs rather
	than inventing one: a subtree is left alone when it is absent from `nodeDirty`
	(P3's ancestor-closed mounted-node dirt) and its rect ENTRY is the same TABLE the
	last commit saw (P2 made that identity meaningful — a reuse solve hands a skipped
	subtree's entries forward table for table). `src/render/commit_walks.luau` carries
	the predicate, the borrowed answer an entry-less region node needs, and the two
	walks that cannot use it at all.

	THE DEMONSTRATOR (D-P4) is `stats.lastCommitVisits`, a counter on every node the
	commit's eight walks visit. It is a COUNTER, not a clock. At pre-fix HEAD, with
	the counter added and nothing else changed, a one-leaf update on the fixture below
	reads **7,091** — every mounted node, once per walk — and it now reads **48**.
	(Measured a second way, on the real pre-fix tree with only the counter added: 7,021
	against 40 on a 1,002-node list.) The `commitScope = false` arm below is that build,
	kept, and it is what the bound is asserted AGAINST rather than against a
	remembered number.

	WHY A COUNTER AND NOT A CLOCK, and why VISITS and not skip-TESTS. A pruned walk
	still asks each child of every node it visits whether it may stop there, so the
	honest claim is about the nodes it does WORK for. Under a dirty `ForEach` the
	sibling scan is one comparison per row — inherent, because `markNodeDirty` closes
	over mounted-path prefixes and therefore always marks the list a dirty row is in —
	while the pre-fix build ran the whole walk for every one of them.

	THE ORACLE, and it is why this file is longer than the fix. Not writing is
	indistinguishable from writing the same value, which is precisely the failure a
	minimal-write contract makes invisible: a prune that skips a node that SHOULD have
	been written leaves last frame's paint on the screen and no counter moves. So the
	differential is the ADAPTER'S ORDERED OPERATION LOG, compared position for
	position against the same surface with the prune off, after every step of a
	script — plus every per-path field the walks own, the solve outputs the harvest
	republishes, and the diagnostics. Order matters and is asserted: `rect_pass`'s
	ancestors-first rule is the reason the hash loop it replaced was removed
	(2026-08-17, 240 engine Position writes across 120 descendants), and a prune is
	only allowed to make the op log a SUBSEQUENCE — which, for a correct one, means
	identical.

	THE FIXTURE IS `measure_reuse.spec`'s, `rect_cow.spec`'s and `node_reuse.spec`'s,
	deliberately: the four stores are invalidated off the same events and a divergence
	between the files' fixtures would be a divergence in what "the same case" means.
	THE SCRIPT IS THAT FAMILY'S PLUS TWO STEPS, and the two are P4's own axes rather
	than a preference: a THEME swap moves the solve-wide stamp (`metrics`), which no
	node dirties and no rect entry records, and the SCROLL CANVAS is published by a
	walk whose verdict is a function of a descendant's content rather than of the
	host's own rect. Neither is in the other three files because neither invalidates
	their stores.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local solver = require("../src/layout/solver")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
-- the second theme package the large-text matrix ships, used here for the one
-- invalidation axis that is neither a node nor a rect: the applied snapshot
local large_text = require("./lib/large_text")
-- the deterministic ring math the stroked-path gate's case needs a real `UI.Path` for
local path_shapes = require("../src/controls/path_shapes")

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

--[[ TEN, and the three that are NOT in it are the point: `UI.ForEach`, `UI.When` and
	`UI.ErrorBoundary` are structural regions that own MOUNTING, not layout, so
	`toLayoutNode` splices their children into the enclosing flow and emits no node for
	the region itself. Scroll, Wrap, Bar, Bad, Fits and its two candidates, Extra (the
	When's branch, mounted because it starts ON), Held (the ErrorBoundary's view), List. ]]
local HEAD_NODES = 10
local ROW_NODES = 5
-- Scroll > List > Row > V, the deepest live chain (`Rows` splices away)
local DEPTH = 4
-- the commit's eight walks: harvest, the six `commit_walks` loops, and `rect_pass`
local WALKS = 8

local function world(
	scope: boolean,
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
		commitScope = scope,
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

local function drive(arm: Arm, step: number)
	SCRIPT[step].run(arm)
	arm.controller.refresh()
end

describe("the commit's own skip (P4)", function()
	it("DEMONSTRATOR D-P4: a one-leaf update at N=1010 visits O(touched), not O(N)", function()
		--[[ THE BOUND, PINNED FROM THE FIXTURE'S BRANCHING RATHER THAN FITTED. The
			honest touched set of a one-value update is the scroller, the list, the
			`ForEach` region (which has no entry of its own and is therefore always
			walked when anything inside it is dirty), the row, the text and the one
			sibling the text's new width moves — each seen once per walk, and there are
			eight walks. `16 * WALKS` is 128: about twice the measured number, so an
			ordinary layout edit can move the constant without reddening this, and it is
			two orders of magnitude below the 7,091 the `commitScope = false` arm visits
			for the same update — 48 against 7,091, and the pre-fix HEAD run that says
			the same thing is recorded in the task report. ]]
		local arm = world(true, true, true, { w = 400, h = 800 }, 200)
		arm.items[100].n:set(4242)
		arm.controller.refresh()
		arm.items[100].n:set(4243)
		arm.controller.refresh()
		local s = arm.controller.stats()
		expect(s.lastCommitVisits > 0).toBe(true)
		expect(s.lastCommitVisits <= 16 * WALKS).toBe(true)
		-- ...and the solve underneath it really was the small one this bound is about
		expect(s.lastRectInserts <= 8 * DEPTH).toBe(true)
	end)

	it("...and the same update with the prune OFF visits every node, once per walk — the control", function()
		--[[ THE NEGATIVE CONTROL THE DEMONSTRATOR IS MEANINGLESS WITHOUT, and it is the
			pre-fix build rather than a model of it: `commitScope = false` leaves P1, P2
			and P3 exactly as they are and takes only the prune away, so the number below
			is what this commit cost before the fix. It is ABOVE seven times the node
			count rather than exactly eight times it, because two of the eight walks
			return early on an adapter capability and the harvest walks the mounted tree
			(1,010 layout nodes, more mounted ones — the regions splice away in the
			solver and do not in the commit). ]]
		local arm = world(false, true, true, { w = 400, h = 800 }, 200)
		arm.items[100].n:set(4242)
		arm.controller.refresh()
		arm.items[100].n:set(4243)
		arm.controller.refresh()
		local s = arm.controller.stats()
		expect(s.lastCommitVisits > 6 * (HEAD_NODES + ROW_NODES * 200)).toBe(true)
		-- ...and the two arms disagree by two orders of magnitude on the SAME update
		local pruned = world(true, true, true, { w = 400, h = 800 }, 200)
		pruned.items[100].n:set(4242)
		pruned.controller.refresh()
		pruned.items[100].n:set(4243)
		pruned.controller.refresh()
		expect(s.lastCommitVisits > 50 * pruned.controller.stats().lastCommitVisits).toBe(true)
	end)

	it("ORACLE: the adapter's ORDERED op log equals the full-walk arm's, step for step", function()
		--[[ THE DIFFERENTIAL THAT CAN CATCH A WRONGLY PRUNED SUBTREE. A skipped write is
			not a missing value — it is LAST FRAME'S value, which an arm compared only
			against itself agrees with. `b` is the same surface with `commitScope = false`
			and everything else identical, so a divergence names THE PRUNE and not the
			three stores under it. Both the ordered log and the whole surface are
			compared after every step. ]]
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
				expect(snapshot(a)).toBe(snapshot(b))
				expect(opsSince(a, marka)).toEqual(opsSince(b, markb))
				marka, markb = #a.adapter.ops(), #b.adapter.ops()
				if a.controller.stats().lastCommitVisits < b.controller.stats().lastCommitVisits then
					engaged += 1
				end
			end
			--[[ THE GUARD EVERY DIFFERENTIAL NEEDS, and it is asserted over the RUN
				rather than at its end, because most of this script legitimately cannot
				prune: nine of the fifteen steps are structural edits, offer changes,
				viewport resizes and a theme swap, and the prune's whole precondition is
				a reuse solve whose stamp did not move. MEASURED at nine of fifteen on
				every view in the matrix — and it was THREE before the recording half was
				split from the pruning half, because a full commit that declined to
				record made the frame after every one of those steps full as well. ]]
			expect(engaged >= 8).toBe(true)
			-- ...and the steady state the bound is really about: two more leaf updates
			-- with nothing else moving
			for _, arm in { a, b } :: { Arm } do
				arm.items[2].n:set(555)
				arm.controller.refresh()
				arm.items[2].n:set(556)
				arm.controller.refresh()
			end
			expect(snapshot(a)).toBe(snapshot(b))
			-- 48 against 511 on every view in the matrix; the factor is stated at 5 so an
			-- ordinary layout edit can move the constant without reddening this
			expect(a.controller.stats().lastCommitVisits * 5 < b.controller.stats().lastCommitVisits).toBe(true)
		end
	end)

	it("ORACLE: and it equals a surface with every cross-solve store OFF", function()
		--[[ The other end of the ladder. The case above isolates the prune; this one
			asserts the four together against a build that reuses NOTHING — a full solve,
			a full tree build, no measure store and no prune — which is the only arm that
			cannot be stale about anything. Ops are NOT compared here and that is
			deliberate rather than an omission: a full-solve arm re-inserts every rect
			entry, so `rect_pass`'s value diff writes the same numbers back and its log is
			legitimately different in length. State is the comparable thing. ]]
		local vp = { w = 400, h = 800 }
		local a = world(true, true, true, vp, 12)
		local c = world(false, false, false, vp, 12)
		expect(snapshot(a)).toBe(snapshot(c))
		for step = 1, #SCRIPT do
			drive(a, step)
			drive(c, step)
			expect(snapshot(a)).toBe(snapshot(c))
		end
	end)

	it("THE SCROLL CANVAS is republished when a descendant's content moves, not when the host does", function()
		--[[ P4'S SECOND AXIS. `commit_walks.scrollRegions` publishes a canvas from the
			host's SOLVED content extent, so its verdict is a function of what is inside
			the host rather than of the host's own rect — and the host's rect is what the
			prune compares. It is sound because a content change re-arranges the host too
			(the extent is its own measure), and this is the case that proves it rather
			than asserting it: appending rows must move the canvas on the pruned arm
			exactly as it does on the full one. ]]
		local vp = { w = 400, h = 800 }
		local a = world(true, true, true, vp, 12)
		local b = world(false, true, true, vp, 12)
		local before = a.adapter.scrollRegionOf("/Scroll")
		expect(before ~= nil).toBe(true)
		for _, arm in { a, b } :: { Arm } do
			local next_ = table.clone(arm.items)
			for i = 1, 8 do
				table.insert(next_, { id = `x{i}`, n = arm.core:signal(i) })
			end
			arm.rows:set(next_)
			arm.controller.refresh()
			-- ...and a leaf update after it, which is the frame the prune is armed on
			arm.items[2].n:set(2026)
			arm.controller.refresh()
		end
		local after = a.adapter.scrollRegionOf("/Scroll")
		expect(after.contentH ~= before.contentH).toBe(true)
		expect(after.contentH).toBe(b.adapter.scrollRegionOf("/Scroll").contentH)
	end)

	it("A HIDE FLIPS THROUGH A CLEAN SUBTREE — the one verdict the prune inherits", function()
		--[[ THE CASE THAT NEEDS ITS OWN FIXTURE, and the mutation is why. Hiddenness is
			carried DOWN the visibility and hit walks (the solver marks a candidate ROOT
			only), so a flip at an ancestor has to reach descendants that are themselves
			untouched — which is the one place entry identity is not the whole answer.

			IT CANNOT BE DRIVEN THROUGH `ViewThatFits`, and that is worth stating because
			the first version of this case tried: when a candidate loses, its subtree
			solves to zero, so every descendant gets a NEW entry and the prune visits
			them for that reason instead. An AUTHORED hide is the shape that isolates the
			inheritance — `props.hidden` is merged into the set by the renderer, not by
			the solver, so it moves NO rect at all and every descendant stays clean.
			MEASURED: dropping the flip's forced descent leaves `A`, `Inner` and `B`
			painting inside a hidden panel while the panel itself goes invisible. ]]
		local function panel(scope: boolean)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
			local hide = core:signal(false)
			local n = core:signal(1)
			local bp = UI.VStack({
				id = "Root",
				padding = 0,
				gap = 0,
				children = {
					-- the co-driver: something dirty on every frame, so the commit is
					-- armed rather than skipped outright
					UI.Text({
						id = "Driver",
						textSize = 14,
						text = core:memo(function(use: any)
							return tostring(use(n))
						end),
					}),
					UI.VStack({
						id = "Panel",
						padding = 0,
						gap = 0,
						hidden = hide,
						width = px(100),
						children = {
							UI.Box({ id = "A", width = px(30), height = px(10) }),
							UI.VStack({
								id = "Inner",
								padding = 0,
								gap = 0,
								children = { UI.Box({ id = "B", width = px(20), height = px(10) }) },
							}),
						},
					}),
				},
			})
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, { commitScope = scope })
			controller.initialRender()
			return { core = core, adapter = adapter, controller = controller, hide = hide, n = n }
		end
		local function visibility(arm: any): string
			local out = {}
			for path, node in arm.adapter.liveNodes() do
				table.insert(out, `{path}={tostring(node.visible)}`)
			end
			table.sort(out)
			return table.concat(out, " ")
		end
		local a, b = panel(true), panel(false)
		for _, arm in { a, b } do
			-- two warm frames so the prune is armed and the store is full, THEN the hide
			arm.n:set(2)
			arm.controller.refresh()
			arm.n:set(3)
			arm.controller.refresh()
			arm.hide:set(true)
			arm.controller.refresh()
		end
		expect(visibility(a)).toBe(visibility(b))
		-- the negative control this case is vacuous without: the hide really reached
		-- the descendants rather than only the panel
		expect(string.find(visibility(a), "/Root/Panel/Inner/B=false", 1, true) ~= nil).toBe(true)
		-- ...and back again, because a flip has two directions and only one of them
		-- is "write false to everything"
		for _, arm in { a, b } do
			arm.hide:set(false)
			arm.controller.refresh()
		end
		expect(visibility(a)).toBe(visibility(b))
		expect(string.find(visibility(a), "/Root/Panel/Inner/B=true", 1, true) ~= nil).toBe(true)
	end)

	it("A STROKED PATH IS CULLED BY A CLIP HOST THAT SHRANK — the gate `visible` cannot prune past", function()
		--[[ THE FIRST OF THE TWO GATES, DRIVEN (P4 review, I1). This report originally
			said the repository could not produce a case for it; the review built one,
			and it is neither exotic nor hard to reach.

			THE SHAPE IS "A SIBLING GREW". A clip host laid out as `fill` shrinks when
			the box below it grows — and NOTHING INSIDE THE HOST MOVES: the path keeps
			the rect it had, so `arrange` skips it and hands its entry forward table for
			table, and `dirtyContains` never reaches it either because the dirty prop is
			the sibling's height. Both halves of `skip` therefore say "leave it alone" at
			exactly the node whose cull verdict just changed. `pathEscapesClip` asks the
			HOST's box, not the path's, which is why entry identity cannot answer for it
			and why `visible` refuses to prune at all on a surface that draws one.

			MUTATION: `prunable = true` at the gate leaves the ring painting outside the
			host that is supposed to crop it. ]]
		local function surface()
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
			env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			local grow = core:signal(80)
			local tick = core:signal(1)
			local bp = UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Root",
						padding = 0,
						gap = 0,
						width = fill(),
						height = fill(),
						children = {
							UI.VStack({
								id = "Clip",
								clipChildren = true,
								padding = 0,
								gap = 0,
								width = px(200),
								height = fill(),
								children = {
									UI.Path({
										id = "Ring",
										points = path_shapes.ring(),
										thickness = 4,
										role = "accent",
										width = px(120),
										height = px(120),
									}),
								},
							}),
							UI.Box({
								id = "Grower",
								width = px(200),
								height = core:memo(function(use: any)
									return px(use(grow))
								end),
							}),
							-- a co-driver, so the frames below are armed commits rather
							-- than solves that never happen
							UI.Text({
								id = "Tick",
								textSize = 12,
								text = core:memo(function(use: any)
									return tostring(use(tick))
								end),
							}),
						},
					}),
				},
			})
			local root = mountLib.mount(core, bp)
			local adapter = fake_target.new()
			local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
			controller.initialRender()
			return { core = core, adapter = adapter, controller = controller, grow = grow, tick = tick }
		end
		local a = surface()
		-- two warm frames, so the prune is armed and its store is full
		a.tick:set(2)
		a.controller.refresh()
		a.tick:set(3)
		a.controller.refresh()
		expect(a.adapter.node("/S/Root/Clip/Ring").visible).toBe(true)
		expect(a.adapter.node("/S/Root/Clip").rect.h > 120).toBe(true)

		a.grow:set(340)
		a.controller.refresh()
		--[[ THE HOST SHRANK AND THE RING DID NOT MOVE — which is the whole premise, so
			it is asserted rather than assumed: an assertion on visibility alone would
			pass on a fixture where the ring's own rect had changed and the prune had
			nothing to get wrong. ]]
		expect(a.adapter.node("/S/Root/Clip").rect.h < 120).toBe(true)
		local ring = a.adapter.node("/S/Root/Clip/Ring").rect
		expect(`{ring.x},{ring.y},{ring.w},{ring.h}`).toBe("0,0,120,120")
		expect(a.adapter.node("/S/Root/Clip/Ring").visible).toBe(false)

		-- ...and back: a gate that only ever hid things would pass the case above by
		-- accident
		a.grow:set(80)
		a.controller.refresh()
		expect(a.adapter.node("/S/Root/Clip/Ring").visible).toBe(true)
	end)

	it(
		"A CHROME FLOOR IS RE-GROWN WHEN AN AUTHOR CONTROL MOVES UNDER IT — the gate `hitRects` cannot prune past",
		function()
			--[[ THE SECOND GATE, DRIVEN (P4 review, I1), and the failure it prevents is the
			one ruling R23 exists for: two actionable targets for one gesture, with the
			framework's own invisible expander on top.

			THE SHAPE IS "AN AUTHOR CONTROL WIDENED". A `cover` under the 44px floor asks
			for a floor that grows only until it meets something the AUTHOR declared
			pressable (`growWithin`). The cover itself does not move when the author's
			button widens toward it — same rect, entry carried forward, not dirty — so
			`skip` says leave it alone at exactly the node whose floor just changed.

			THE NUMBERS ARE THE ASSERTION. At width 100 the author is clear of the
			cover's ask and the expander is the full 44x44 at x=156. At 170 it overlaps
			on both axes, and the floor is clipped to 40x32 at x=160. MUTATION: dropping
			`not sawChrome` leaves the 44x44 standing over the author's own button. ]]
			local function surface(authorW: number)
				local core = customFactory.new()
				local env = environment.new(core)
				env:set("viewportRect", { x = 0, y = 0, w = 300, h = 200 })
				env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
				local w = core:signal(authorW)
				local tick = core:signal(1)
				local bp = UI.Screen({
					id = "S",
					children = {
						UI.VStack({
							id = "Root",
							padding = 0,
							gap = 0,
							width = fill(),
							height = fill(),
							children = {
								UI.Anchor({
									id = "Plate",
									width = px(200),
									height = px(60),
									children = {
										UI.Button({
											id = "Author",
											label = "Go",
											anchor = "topLeft",
											offsetX = 0,
											offsetY = 0,
											width = core:memo(function(use: any)
												return px(use(w))
											end),
											height = px(44),
										}),
										--[[ AUTHORS NEVER WRITE THIS — `UI.Region{ expand = … }`
										and the dismissible-plate close both synthesize it, and
										the schema's own doc says so. It is authored directly
										here because the framework's two producers of it are a
										whole Region and a whole plate, and this case is about
										one prop's consequence rather than about either. ]]
										UI.Button({
											id = "Cover",
											label = "",
											expandTarget = { role = "cover" },
											anchor = "topLeft",
											offsetX = 160,
											offsetY = 0,
											width = px(36),
											height = px(20),
										}),
									},
								}),
								UI.Text({
									id = "Tick",
									textSize = 12,
									text = core:memo(function(use: any)
										return tostring(use(tick))
									end),
								}),
							},
						}),
					},
				})
				local root = mountLib.mount(core, bp)
				local adapter = fake_target.new()
				local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
				controller.initialRender()
				return { core = core, adapter = adapter, controller = controller, w = w, tick = tick }
			end
			local function hitOf(a: any, path: string): string
				local h = a.adapter.node(path).hitRect
				return if h == nil then "-" else `{h.x},{h.y},{h.w},{h.h}`
			end
			local a = surface(100)
			a.tick:set(2)
			a.controller.refresh()
			a.tick:set(3)
			a.controller.refresh()
			expect(hitOf(a, "/S/Root/Plate/Cover")).toBe("156,-12,44,44")

			a.w:set(170)
			a.controller.refresh()
			-- the premise, asserted: the cover did not move, so entry identity would have
			-- pruned it and only the gate stops that
			local cover = a.adapter.node("/S/Root/Plate/Cover").rect
			expect(`{cover.x},{cover.y},{cover.w},{cover.h}`).toBe("160,0,36,20")
			expect(hitOf(a, "/S/Root/Plate/Cover")).toBe("160,-12,40,32")
			-- ...and it equals a surface built COLD at the same final width, which is what
			-- makes "40x32" the right answer rather than merely a different one
			expect(hitOf(a, "/S/Root/Plate/Cover")).toBe(hitOf(surface(170), "/S/Root/Plate/Cover"))

			-- ...and the author narrowing again gives the floor back
			a.w:set(100)
			a.controller.refresh()
			expect(hitOf(a, "/S/Root/Plate/Cover")).toBe("156,-12,44,44")
		end
	)

	it(
		"EVERY PROP THE WALKS READ — DIRECTLY OR THROUGH A HELPER — resolves to one a stale prune cannot miss",
		function()
			--[[ THE CENSUS THAT LICENSES THE PREDICATE, mechanised the way P1's review
			required for `layout_node` (`tests/layout_prop_dirt.spec.luau`), because the
			same table is load-bearing here for the opposite reason.

			`skip` refuses to prune a node in `nodeDirty` — P3's ancestor-closed set over
			EVERY dirty class. Entry identity alone would already catch every prop these
			walks read today, and this case is the proof of that rather than a hope: each
			one either declares a LAYOUT dirty class (so a change puts it in
			`dirtyContains`, the solver walks it, and `arrange` writes a fresh entry) or
			is `reactive = false` (so it can only change by REMOUNT, which is structural,
			which takes the full commit).

			THE FIRST VERSION OF THIS CASE PROVED NEITHER, and the correction is the
			point (P4 review, I3). It looped over `schema.propDirty()` and skipped any
			name that table did not carry — and `propDirty` carries only REACTIVE props,
			so `autoscroll`, `expandTarget` and `indicators` never entered the loop at
			all and the `reactive == false` clause never executed once. Three of the six
			names were exonerated by absence, which is the exact shape of "a check that
			proves nothing". The loop now runs over `schema.all()` — every DECLARATION,
			reactive or not — and a name that resolves to no declaration anywhere FAILS
			rather than passing quietly.

			AND THE SCAN NOW FOLLOWS THE HELPERS. `textVerdicts` hands `node.props` to
			`layout_node.compactForm` and `layout_node.drawnButtonText`, and `padding`
			hands it to `themeSnapshot.buttonPadding` — so `label`, `compactLabel`,
			`icon` and `shape` are props these walks read with no `props.` of their own
			in this file. That is the same blind spot P3's review found in
			`layout_node`'s audit ("the audit is TWO enumerations"), arriving here.

			IT STAYS ANYWAY, and the census is why the conservatism is principled instead
			of superstitious: the day a reactive PAINT-class prop is read by one of these
			walks, entry identity stops covering it and the failure is a write that never
			happens — invisible to every state comparison, because not writing looks
			exactly like writing the same value. This case goes red on that day. ]]
			local schema = require("../src/blueprint_schema")
			local fs = require("@lune/fs")
			local LAYOUT = { measure = true, arrange = true, structure = true }
			local WALKS_PATH = "src/render/commit_walks.luau"

			--[[ COMMENTS ARE NOT CODE, and the line-at-a-time stripper this case first
				shipped with could not say so: it latched `inBlock` on a block-comment OPEN
				and never looked for the CLOSE on that same line, so one single-line block
				comment swallowed the rest of the file and every scan below it read almost
				nothing. Block comments come out first, whole, then line comments, which is
				the shape the seam specs in this repository already use. ]]
			local function stripLuauComments(text: string): string
				local out = string.gsub("\n" .. text, "%-%-%[%[.-%]%]", " ")
				out = string.gsub(out, "%-%-[^\n]*", "")
				return out
			end
			local function propReads(code: string): { [string]: boolean }
				local out: { [string]: boolean } = {}
				for name in string.gmatch(code, "props%.([%a_][%w_]*)") do
					out[name] = true
				end
				return out
			end

			local walks = stripLuauComments(fs.readFile(WALKS_PATH))

			--[[ THE MODULE MAP, DERIVED FROM THIS FILE'S OWN REQUIRES rather than written
			out, so a helper that moves file cannot leave the scan pointing at nothing. ]]
			local modules: { [string]: string } = {}
			for name, spec in string.gmatch(walks, 'local ([%a_][%w_]*) = require%("([^"]+)"%)') do
				local rest = string.match(spec, "^%./(.+)$")
				if rest ~= nil then
					modules[name] = `src/render/{rest}.luau`
				else
					local up = string.match(spec, "^%.%./(.+)$")
					if up ~= nil then
						modules[name] = `src/{up}.luau`
					end
				end
			end
			expect(modules.layout_node).toBe("src/render/layout_node.luau")
			expect(modules.themeSnapshot).toBe("src/themes/snapshot.luau")

			--[[ ENUMERATION TWO: every call in these walks that hands `props` to somebody
			else. A whole-props helper is invisible to a `props.<name>` scan of this
			file, which is precisely how `label`, `compactLabel`, `icon` and `shape`
			went uncounted. ]]
			local handoffs: { { mod: string, fn: string, index: number } } = {}
			local fieldOnly: { string } = {}
			local seenCall: { [string]: boolean } = {}
			local seenField: { [string]: boolean } = {}
			for mod, fn, args in string.gmatch(walks, "([%a_][%w_]*)%.([%a_][%w_]*)%(([^()]*)%)") do
				if modules[mod] == nil or string.find(args, "props", 1, true) == nil then
					continue
				end
				--[[ WHOLE PROPS, NOT A FIELD OF IT, and the difference decides whether the
					callee can read a prop this file never names. An argument that is exactly
					`node.props` hands the table over; `node.props.padding` and
					`node.props and node.props.textSize` hand over one value this file has
					already named, so following them would add nothing and pinning them as
					handoffs would claim a coverage the body scan does not have. Both sets are
					pinned below, because "excluded" is a claim too. ]]
				local index: number? = nil
				local at = 0
				for _, piece in string.split(args, ",") do
					at += 1
					local arg = string.match(piece, "^%s*(.-)%s*$")
					if arg == "props" or arg == "node.props" then
						index = at
					end
				end
				local key = `{mod}.{fn}`
				if index == nil then
					if not seenField[key] then
						seenField[key] = true
						table.insert(fieldOnly, key)
					end
					continue
				end
				if not seenCall[key] then
					seenCall[key] = true
					table.insert(handoffs, { mod = mod, fn = fn, index = index :: number })
				end
			end
			table.sort(fieldOnly)
			table.sort(handoffs, function(a, b)
				return `{a.mod}.{a.fn}` < `{b.mod}.{b.fn}`
			end)
			local handoffNames: { string } = {}
			for _, h in handoffs do
				table.insert(handoffNames, `{h.mod}.{h.fn}`)
			end
			--[[ PINNED, so a FOURTH whole-props helper fails this case instead of slipping
			the scan — the property P3's review asked `node_reuse.spec` for and got. ]]
			expect(handoffNames).toEqual({
				"layout_node.compactForm",
				"layout_node.drawnButtonText",
				"themeSnapshot.buttonPadding",
			})
			-- ...and the calls that carry a FIELD rather than the table, which the scan
			-- sees and deliberately does not follow
			expect(fieldOnly).toEqual({ "themeSnapshot.effectiveTypeRole", "themeSnapshot.resolveSides" })

			local names = propReads(walks)
			-- the parser pins for enumeration one: an audit that silently matched nothing
			-- would pass forever
			expect(names.textSize).toBe(true)
			expect(names.padding).toBe(true)
			expect(names.autoscroll).toBe(true)

			-- ...and enumeration two, followed into the helper's own body
			--[[ AND THE BODY SCAN RESOLVES THE CALLEE'S OWN PARAMETER NAME rather than
				assuming it is spelled `props`. A helper that called its parameter `p` would
				otherwise contribute nothing and contribute it SILENTLY, which is the same
				exonerate-by-absence failure this whole case was rewritten for. ]]
			local transitive: { [string]: boolean } = {}
			for _, h in handoffs do
				local source = stripLuauComments(fs.readFile(modules[h.mod]))
				local params, body = string.match(source, `\nlocal function {h.fn}%(([^)]*)%)[^\n]*\n(.-)\nend\n`)
				if params == nil then
					params, body = string.match(source, `\nfunction [%a_][%w_]*%.{h.fn}%(([^)]*)%)[^\n]*\n(.-)\nend\n`)
				end
				assert(params ~= nil and body ~= nil, `no body found for {h.mod}.{h.fn}`)
				local raw = string.split(params :: string, ",")[h.index]
				assert(raw ~= nil, `{h.mod}.{h.fn} has no parameter {h.index}`)
				local param = string.match(raw, "([%a_][%w_]*)")
				assert(param ~= nil, `{h.mod}.{h.fn} parameter {h.index} has no name`)
				for name in string.gmatch(body :: string, `{param}%.([%a_][%w_]*)`) do
					transitive[name] = true
					names[name] = true
				end
			end
			-- the pins for enumeration two, by name: these four are read by NO `props.` in
			-- `commit_walks.luau` and are what the first version of this case never saw
			expect(transitive.label).toBe(true)
			expect(transitive.compactLabel).toBe(true)
			expect(transitive.icon).toBe(true)
			expect(transitive.shape).toBe(true)

			local dirty = schema.propDirty()
			local specs = schema.all()
			local offenders: { string } = {}
			local unresolved: { string } = {}
			local checked = 0
			local reactiveFalseSeen = 0
			for name in names do
				local declaredSomewhere = false
				for className, spec in specs do
					local prop = if spec.props ~= nil then (spec.props :: any)[name] else nil
					if prop == nil then
						continue
					end
					declaredSomewhere = true
					checked += 1
					--[[ ARM ONE: a LAYOUT dirty class. A change puts the node in
					`dirtyContains`, `arrange` walks it, and the entry it writes is a new
					table — so entry identity alone already refuses the prune. ]]
					local classes = (dirty[className] or {})[name]
					local layout = false
					for _, c in classes or {} do
						if LAYOUT[c] then
							layout = true
						end
					end
					if layout then
						continue
					end
					--[[ ARM TWO: not reactive at all, so the only way it changes is a
					REMOUNT — structural, which gives no reuse set, which takes the full
					commit. Asserted EXPLICITLY here rather than reached by absence. ]]
					if prop.reactive == false then
						reactiveFalseSeen += 1
						continue
					end
					table.insert(
						offenders,
						`{className}.{name} = {if classes then table.concat(classes, "+") else "no dirty classes"} and reactive`
					)
				end
				if not declaredSomewhere then
					--[[ THE HOLE THE REVIEW FOUND, CLOSED FROM THE OTHER SIDE: a name the
					scan matched that resolves to no prop declaration anywhere is a scan
					that is reading something other than props, and it must say so
					instead of being skipped. ]]
					table.insert(unresolved, name)
				end
			end
			table.sort(offenders)
			table.sort(unresolved)
			expect(table.concat(unresolved, "; ")).toBe("")
			expect(table.concat(offenders, "; ")).toBe("")
			--[[ AND THE TWO ARMS BOTH RAN. Set comparisons and `continue`-driven loops are
			the two shapes that pass by doing nothing, and this case has been both. ]]
			expect(checked > 25).toBe(true)
			expect(reactiveFalseSeen >= 4).toBe(true)
		end
	)

	it("NEGATIVE CONTROL: the census's two enumerations and both of its arms report", function()
		--[[ Each scan is a pure function of a string, so each is fed a broken input
			here. A check that cannot fail is decoration — and the version of the case
			above that shipped without this could not fail on three of its six names. ]]
		--[[ COMMENTS ARE NOT CODE, and the line-at-a-time stripper this case first
			shipped with could not say so: it latched `inBlock` on a block-comment OPEN
			and never looked for the CLOSE on that same line, so one single-line block
			comment swallowed the rest of the file and every scan below it read almost
			nothing. Block comments come out first, whole, then line comments, which is
			the shape the seam specs in this repository already use. ]]
		local function stripLuauComments(text: string): string
			local out = string.gsub("\n" .. text, "%-%-%[%[.-%]%]", " ")
			out = string.gsub(out, "%-%-[^\n]*", "")
			return out
		end
		local function propReads(code: string): { [string]: boolean }
			local out: { [string]: boolean } = {}
			for name in string.gmatch(code, "props%.([%a_][%w_]*)") do
				out[name] = true
			end
			return out
		end
		-- a prop named in a comment is prose, not a read
		local sample = "--[[ props.ghost ]]\nlocal a = props.real\n\t-- props.phantom\n"
		local read = propReads(stripLuauComments(sample))
		expect(read.real).toBe(true)
		expect(read.ghost).toBe(nil)
		expect(read.phantom).toBe(nil)
		-- the handoff scan sees a call that carries props and ignores one that does not
		local calls = stripLuauComments("local x = helper.take(metrics, node.props)\nlocal y = helper.other(metrics)\n")
		local seen: { [string]: boolean } = {}
		for mod, fn, args in string.gmatch(calls, "([%a_][%w_]*)%.([%a_][%w_]*)%(([^()]*)%)") do
			if string.find(args, "props", 1, true) ~= nil then
				seen[`{mod}.{fn}`] = true
			end
		end
		expect(seen["helper.take"]).toBe(true)
		expect(seen["helper.other"]).toBe(nil)
		--[[ ...AND THE ARM ORDER. A declaration with a paint-only dirty class AND
			`reactive` is the offender the case exists for; the same prop declared
			`reactive = false` is not. This is the pair the broken version could never
			evaluate, because such a prop never appeared in `propDirty` at all. ]]
		local LAYOUT = { measure = true, arrange = true, structure = true }
		local function verdict(classes: { string }?, reactive: boolean?): string
			for _, c in classes or {} do
				if LAYOUT[c] then
					return "safe:layout"
				end
			end
			if reactive == false then
				return "safe:remount-only"
			end
			return "OFFENDER"
		end
		expect(verdict({ "measure" }, nil)).toBe("safe:layout")
		expect(verdict({ "paint" }, false)).toBe("safe:remount-only")
		expect(verdict({ "paint" }, nil)).toBe("OFFENDER")
		expect(verdict(nil, nil)).toBe("OFFENDER")
	end)

	it("A CARRIED-FORWARD ENTRY IS NEVER MUTATED IN PLACE — the precondition identity-capture rests on", function()
		--[[ THE PRECONDITION THE PRUNE INHERITED FROM P2 AND MADE LOAD-BEARING (P4
			review, I4). `skip` compares ENTRY IDENTITY, so it is blind by construction
			to a field written into an entry the solve handed forward. P2 could tolerate
			that — its own consumer re-read the map — and P4 cannot: an entry whose
			`hidden` flipped without its table changing is a hide that never reaches
			paint, and no counter moves.

			IT IS NOT HYPOTHETICAL AS A SHAPE. `layout/solver.luau` writes fields onto an
			entry AFTER the `arrange` that built it, at nine sites, and four of them
			write onto a CHILD'S entry (`out[child.id].hidden = true`) after an `arrange`
			that may legally have skip-served that child. `solver.luau` is frozen at 110
			characters to the write cap, so this is pinned from the spec side, both ways.

			WHY NO REACHABLE CASE EXISTS TODAY, which is the thing the pins have to keep
			true rather than the thing they assert: all four writes follow an `arrange`
			to a rect of `w = 0, h = 0`, and `arrange` skips only a node landing on the
			rect it ALREADY had. So a child that gets the hidden mark on a carried entry
			was already at a zero rect, which means it was already marked — the write is
			idempotent. A fifth write of a different shape, or one of these four losing
			its zero rect, breaks that and is what the source pin below refuses. ]]
		local fs = require("@lune/fs")
		local SOLVER_PATH = "src/layout/solver.luau"
		local source = fs.readFile(SOLVER_PATH)
		local lines = string.split(source, "\n")
		local ownWrites, childWrites, unguarded = 0, 0, {}
		for i, raw in lines do
			local target, field = string.match(raw, "out%[([%w_%.]+)%]%.([%a_][%w_]*) = ")
			if target == nil then
				continue
			end
			if target == "node.id" then
				--[[ THE NODE'S OWN ENTRY, written by the `arrange` that is building it.
					It cannot be a carried entry: reaching these lines means the skip
					above did not fire. ]]
				ownWrites += 1
				continue
			end
			childWrites += 1
			--[[ A CHILD'S ENTRY, which the child's own `arrange` may have skip-served.
				Safe only while the rect that `arrange` was handed is ZERO — see the
				header. Looked for in the three lines above the write, which is the
				shape all four have. ]]
			local guarded = false
			for back = math.max(1, i - 3), i - 1 do
				local prior = lines[back]
				if
					string.find(prior, "arrange(", 1, true) ~= nil
					and string.find(prior, "w = 0, h = 0", 1, true) ~= nil
				then
					guarded = true
				end
			end
			if not guarded then
				table.insert(unguarded, `{SOLVER_PATH}:{i} {string.match(raw, "^%s*(.-)%s*$")}`)
			end
		end
		--[[ THE COUNTS ARE PINNED, not merely the guard: a fifth child-side write is a
			new way for this precondition to be broken, and it should fail HERE with the
			reason rather than somewhere downstream with a stale pixel. ]]
		expect(childWrites).toBe(4)
		expect(ownWrites).toBe(5)
		expect(table.concat(unguarded, "\n")).toBe("")
		-- the scan really looked (a regex that matched nothing would pass forever)
		expect(string.find(source, "out[child.id].hidden = true", 1, true) ~= nil).toBe(true)

		--[[ AND THE PROPERTY ITSELF, DRIVEN, because a source pin is a claim about the
			code and this is a claim about the RUN. Two solves over a `fits` tree whose
			winner changes: every entry the second solve handed forward by IDENTITY must
			also be unchanged by VALUE on every field the commit reads off it. An
			in-place write to a carried entry is exactly the pair "same table, different
			field", and this is the only comparison that names it. ]]
		local function entryKey(e: any): string
			local r = e.rect
			local facts = if type(e.textFacts) == "table" then e.textFacts else nil
			return `{r.x},{r.y},{r.w},{r.h}|h={tostring(e.hidden)}|o={tostring(e.overflow)}|k={tostring(e.kind)}`
				.. `|c={tostring(e.compact)}|t={tostring(facts and facts.truncated)}|b={tostring(e.barInset)}`
				.. `|cs={tostring(e.contentSize and e.contentSize.w)}|p={tostring(e.padding)}`
		end
		local function fitsTree(wide: boolean): any
			local kids = {}
			for i = 1, 12 do
				table.insert(kids, {
					kind = "box",
					id = `/root/pad{i}`,
					width = px(10),
					height = px(8),
					children = {},
				})
			end
			return {
				kind = "vstack",
				id = "/root",
				gap = 2,
				children = {
					{
						kind = "fits",
						id = "/root/fits",
						width = px(if wide then 200 else 40),
						height = px(24),
						children = {
							{ kind = "box", id = "/root/fits/long", width = px(120), height = px(20), children = {} },
							{ kind = "box", id = "/root/fits/short", width = px(30), height = px(20), children = {} },
						},
					},
					{ kind = "vstack", id = "/root/rest", gap = 2, children = kids },
				},
			}
		end
		local vp = { w = 400, h = 800 }
		local first = solver.solve(fitsTree(true), vp, {})
		local held: { [string]: any } = {}
		local values: { [string]: string } = {}
		for id, entry in first.rects do
			held[id] = entry
			values[id] = entryKey(entry)
		end
		expect(next(held) ~= nil).toBe(true)
		--[[ A REUSE SOLVE OF THE NARROWED TREE. `dirtyContains` names the `fits` node
			and its ancestors, exactly as the renderer's closure would, so the candidate
			verdict really does move — and everything else is eligible to be handed
			forward. ]]
		local dirty = { ["/root"] = true, ["/root/fits"] = true }
		local second = solver.solve(fitsTree(false), vp, { reuse = { previous = first, dirtyContains = dirty } })
		local carried, mutated = 0, {}
		for id, entry in second.rects do
			if held[id] ~= entry then
				continue
			end
			carried += 1
			if entryKey(entry) ~= values[id] then
				table.insert(mutated, `{id}: {values[id]} -> {entryKey(entry)}`)
			end
		end
		table.sort(mutated)
		expect(table.concat(mutated, "\n")).toBe("")
		-- ...and the case is not vacuous: entries really were carried, and the verdict
		-- really did move
		expect(carried > 10).toBe(true)
		expect(second.rects["/root/fits/long"].hidden).toBe(true)
		expect(first.rects["/root/fits/long"] == nil or values["/root/fits/long"] ~= nil).toBe(true)
	end)

	it("P1 x P2 x P3 x P4: all four warm, one leaf, every counter bounded and the paint identical", function()
		--[[ THE COMPOSITION CASE. Each of the four is keyed off a different thing —
			the measure store off `dirtyContains`, the rect map off the same skip, the
			node store off `nodeDirty`, the commit off `nodeDirty` AND entry identity —
			so a disagreement between them is geometry that is right in one arm and stale
			in another. Four claims at once: the answer is the reuse-nothing arm's, and
			all four counters are O(touched). ]]
		local vp = { w = 400, h = 800 }
		local a = world(true, true, true, vp, 200)
		local c = world(false, false, false, vp, 200)
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
		expect(warm.lastNodeBuilds <= ROW_NODES + 2 * DEPTH).toBe(true)
		expect(warm.lastCommitVisits <= 16 * WALKS).toBe(true)
		expect(warm.lastSkipped > 900).toBe(true)
		-- and the arm those four numbers are bounded AGAINST
		local cold = c.controller.stats()
		expect(cold.lastRectInserts).toBe(HEAD_NODES + ROW_NODES * 200)
		expect(cold.lastCommitVisits > 6 * (HEAD_NODES + ROW_NODES * 200)).toBe(true)
	end)
end)
