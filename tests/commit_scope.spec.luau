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
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
-- the second theme package the large-text matrix ships, used here for the one
-- invalidation axis that is neither a node nor a rect: the applied snapshot
local large_text = require("./lib/large_text")

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

	it("EVERY PROP THE WALKS READ is one a dirty entry or a remount can only reach WITH a new rect", function()
		--[[ THE CENSUS THAT LICENSES THE PREDICATE, mechanised the way P1's review
			required for `layout_node` (`tests/layout_prop_dirt.spec.luau`), because the
			same table is load-bearing here for the opposite reason.

			`skip` refuses to prune a node in `nodeDirty` — P3's ancestor-closed set over
			EVERY dirty class. Entry identity alone would already catch every prop this
			file reads today, and this case is the proof of that rather than a hope: each
			one either declares a LAYOUT dirty class (so a change puts it in
			`dirtyContains`, the solver walks it, and `arrange` writes a fresh entry) or
			is `reactive = false` (so it can only change by REMOUNT, which is structural,
			which takes the full commit). No mutation of the `nodeDirty` clause reddens
			any case in this file, and that is stated rather than hidden.

			IT STAYS ANYWAY, and the census is why the conservatism is principled instead
			of superstitious: the day a reactive PAINT-class prop is read by one of these
			walks, entry identity stops covering it and the failure is a write that never
			happens — invisible to every state comparison, because not writing looks
			exactly like writing the same value. This case goes red on that day. ]]
		local schema = require("../src/blueprint_schema")
		local fs = require("@lune/fs")
		local LAYOUT = { measure = true, arrange = true, structure = true }
		local source = fs.readFile("src/render/commit_walks.luau")
		local names: { [string]: boolean } = {}
		local inBlock = false
		for _, raw in string.split(source, "\n") do
			if inBlock then
				if string.match(raw, "%]%]") then
					inBlock = false
				end
				continue
			end
			if string.match(raw, "%-%-%[%[") then
				inBlock = true
				continue
			end
			local code = string.gsub(raw, "%-%-.*", "")
			for name in string.gmatch(code, "props%.([%a_][%w_]*)") do
				names[name] = true
			end
		end
		-- the parser pin: an audit that silently matched nothing would pass forever
		expect(names.textSize).toBe(true)
		expect(names.padding).toBe(true)
		expect(names.autoscroll).toBe(true)
		local n = 0
		for _ in names do
			n += 1
		end
		expect(n >= 6).toBe(true)

		local dirty = schema.propDirty()
		local specs = schema.all()
		local offenders: { string } = {}
		for name in names do
			for className, byProp in dirty do
				local classes = byProp[name]
				if classes == nil then
					continue
				end
				local layout = false
				for _, c in classes do
					if LAYOUT[c] then
						layout = true
					end
				end
				if layout then
					continue
				end
				local spec = specs[className]
				local prop = if spec ~= nil and spec.props ~= nil then spec.props[name] else nil
				if prop ~= nil and prop.reactive == false then
					continue
				end
				table.insert(offenders, `{className}.{name} = {table.concat(classes, "+")} and reactive`)
			end
		end
		table.sort(offenders)
		expect(table.concat(offenders, "; ")).toBe("")
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
