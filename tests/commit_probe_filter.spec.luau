--!strict
--[[ THE COMMIT ASKS `entryVerdict` ONLY WHERE IT CANNOT ANSWER FOR ITSELF
	(Plan C, C14).

	WHAT THE PROFILE FOUND, at `48f010cd` with `attr <wl> L 3`. C4 took the sibling
	scan from eight passes to one; what is left is that ONE pass, and it is still
	`cw.harvest` **0.098 ms of a 1.053 ms `battle_hud L updateItem-hp` — 9.3 %**
	(`war_room_inventory L setState` 0.160 of 1.918, `killfeed_nameplates L
	updateItem-hp` 0.031 of 0.293). T13/T14/T15 did not reduce it — it was 0.089 ms
	before them — they reduced the DENOMINATOR, which is why the gate was restated on
	the absolute value. `lastCommitScans` reads 1,137 against `lastCommitVisits` 48:
	the commit visits the dirty chain and asks about a thousand siblings on the way.

	WHAT THE ANSWER ACTUALLY COSTS, which is the finding this file exists to record.
	`entryVerdict(child)` is `probeEntry` plus a `lastCommitEntry` lookup plus an
	`==`, and `probeEntry`'s FIRST LINE is `commitRects[node.path]`. So for a child
	that OWNS its own entry — nearly every child of nearly every visited node — the
	verdict is two hash lookups and a compare wrapped in two closure calls, and the
	calls are the only part that can be removed. `buildDescend` now does the two
	lookups in the loop body and keeps the call for the two populations that need it:
	an entry-LESS child (a spliced `UI.When`/`UI.ForEach`/`UI.ErrorBoundary` region,
	or a single-child pass-through, where `probeEntry` walks a chain) and a child
	whose entry this solve REPLACED, where `moved` still has to be computed.

	IT IS `entryVerdict` ITSELF, NOT AN APPROXIMATION OF IT — C4's own invariant one
	level down. `settled` IS `lastCommitEntry[p] == probeEntry(child)`, and for
	`own ~= nil` that is exactly `lastCommitEntry[p] == own`; `settled` short-circuits
	`moved` in all three consumers. No verdict can differ, which is why
	`lastCommitScans`, `lastCommitVisits`, `lastCommitVisitsByWalk`, `rectWrites`,
	`propWrites` and `engineWrites` are pinned IDENTICAL beside every probe count here.

	WHAT THE PLAN ASKED FOR INSTEAD, BUILT, MEASURED AND REFUSED. C14 was written as a
	set-membership filter: the solver publishes `work.walkedIds` (plus
	`translatedPaths`, plus — a correction this task had to make — `translatedRoots`,
	because a successful translate root returns ABOVE the `walkedIds` write while its
	fresh entry was written above THAT), the renderer forwards the record, and a child
	outside the union skips the probe. Built end to end and measured against this
	branch at the same SHA, it produced **the identical probe count on every class of
	every workload**, because the union filter needs two more terms to be sound and
	both of them are the lookups this branch already does:

	  * `commitRects[p] ~= nil` (review round 3's MUST-FIX) — `walked` is
	    ancestor-closed over LAYOUT nodes and a spliced region has none, so pruning one
	    takes its whole subtree with it. Driven: a `ForEach` under a container whose
	    padding moves leaves every item painting its old position.
	  * `lastCommitEntry[p] ~= nil` — found by `tests/structural_scope.spec.luau`'s "A
	    NODE THE COMMIT HAD NO HANDLE FOR is not recorded as committed", which the union
	    filter turned red: an entry the commit could not record is deliberately left
	    UNNOTED so the next commit descends to it, and membership in `walked` says
	    nothing about that.

	With both terms in, the membership test is a THIRD lookup deciding nothing the
	first two had not decided: `cw.harvest` 0.098 -> 0.078 ms with it against
	**0.074 ms without**, and +11 %/+14 % against HEAD on the two structural classes it
	cannot help. It also cost a `solver.luau` export and a `renderer.luau` argument on a
	file 149 characters from this campaign's STOP line. So `render/commit_walks` needs
	no fact from the solve to answer this question, and does not take one.

	AND IT DOES NOT `continue`. The fork points in `buildDescend` copy a PREFIX of
	`kids` BY INDEX, so skipping the rest of the loop body would let the first fork
	after a fast-pathed child copy that child back in. The three flags are set
	directly. `lastCommitScans` therefore MUST NOT MOVE and is this file's safety pin;
	`lastCommitProbes` is its acceptance number.

	WHICH CASES ARE REDS AND WHICH ARE GUARDS, said once here and again at each site
	(review fix round 1, Minor 1). **RED AT BASE** — they fail with the fast path
	neutered: the two scan/probe pairs, the `fill`-child acceptance case, "costs no
	call", "A DIRTY CHILD WITH A SETTLED ENTRY", "A NEVER-COMMITTED ENTRY", "A MOVE-ONLY
	ENTRY", and "A BOTH-DIRTY CHILD READS NO ENTRY AT ALL" (which is red against the
	FIRST shipped form, not against C4 — see its own header). **GREEN AT BASE** — they
	are forward guards, and saying so is the honest label: the viewport/unpruned case,
	the structural-churn case (green BY DESIGN — it is the "degrades to today's count"
	arm), "the filtered arm agrees with a full-walk arm", the `ForEach` region case, "AN
	ENTRY-LESS CHILD is never fast-pathed", the `commitDirty ⊆ nodeDirty` source pin, and
	both differential oracles.

	AND THE ORACLES ARE C4's ARM SWITCH, NOT C14's (Minor 7). Both compare
	`commitScope = true` against `commitScope = false`, which is the prune as a whole;
	there is no attach opt for this branch and inventing one would be a public surface
	for a code path. They are excellent guards — mutation 2 reddens both — but C14's own
	A/B evidence is the five hand-built cases plus the mutation battery. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local deep = require("./lib/deep_stack_scene")
local device_views = require("./lib/device_views")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local function byWalk(st: any): string
	local keys = {}
	for k in st.lastCommitVisitsByWalk do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `{k}={st.lastCommitVisitsByWalk[k]}`)
	end
	return table.concat(parts, " ")
end

--[[ A ROW WHOSE WIDTH IS A SIGNAL AND WHOSE ONLY CHILD FILLS IT — the same shape
	`commit_descend_cache.spec` built for C4, re-declared here rather than shared so
	the two files' pins cannot drift together. `commitScope` is the arm switch, so one
	builder produces the filtered build and the pre-P4 control the oracle compares
	against. ]]
local function fillScene(commitScope: boolean)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	local width = core:signal(300)
	local rows: { any } = {}
	for i = 1, 20 do
		rows[i] = UI.HStack({
			id = `R{i}`,
			padding = 0,
			gap = 0,
			width = if i == 5
				then core:memo(function(use: any)
					return { type = "fixed", px = use(width) :: number }
				end)
				else { type = "fixed", px = 300 },
			height = { type = "fixed", px = 18 },
			children = {
				UI.Box({ id = "Fill", width = { type = "fill", weight = 1 }, height = { type = "fixed", px = 10 } }),
			},
		})
	end
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "List",
					padding = 0,
					gap = 2,
					width = { type = "fill", weight = 1 },
					height = { type = "content" },
					children = rows,
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = commitScope,
		translateHosts = true,
	})
	controller.initialRender()
	return {
		controller = controller,
		adapter = adapter,
		setWidth = function(px: number)
			width:set(px)
			controller.refresh()
		end,
		rectOf = function(path: string): string
			local r = controller.rectOf(path)
			return if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("C14: the probe is asked only where the solve could have replaced an entry", function()
	it("one leaf's text on a 1,000-row list SCANS the same and PROBES almost nothing", function()
		--[[ RED AT BASE. THE PAIR IS THE POINT. `scans` is C4's number and must not move by one:
			the filter sets three flags where the probe used to run and lets every child
			reach the fork logic with the same `i`. `probes` is C14's, read off the run
			with `solves=1` on the class. The first drive is a warm-up — the fixture's
			first refresh after `initialRender` is structural and cannot prune. ]]
		local s = deep.new({})
		s.text(500, "warm")
		s.text(500, "Row 500 changed")
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans}`).toBe("scans=1011")
		expect(`probes={st.lastCommitProbes} visits={st.lastCommitVisits}`).toBe("probes=1 visits=34")
		-- ...AND NOT ONE VISIT OR WRITE MOVED, which is the whole safety claim. These
		-- are `commit_descend_cache.spec`'s own numbers, re-asserted here because a
		-- filter that changed one of them would be pruning a node, not a question.
		expect(byWalk(st)).toBe(
			"harvest=4 hitRects=5 padding=4 rectPass=5 scrollRegions=4 textScale=4 textVerdicts=4 visible=4"
		)
		expect(`rects={st.rectWrites} props={st.propWrites} engine={st.engineWrites}`).toBe(
			"rects=3006 props=7004 engine=6008"
		)
		--[[ ...and the REST of the brief's must-not-move list, named here rather than
			left to transitive coverage (review fix round 1, Minor 3). `lastCommitListCells`
			is C4's allocation counter and is the one a change to this loop could plausibly
			move; the pool and lifecycle four are here because "nothing else moved" is a
			claim about the whole commit, not about the walks. ]]
		expect(
			`cells={st.lastCommitListCells} elided={st.elided} creates={st.creates} `
				.. `removes={st.removes} parked={st.parked} recycled={st.recycled}`
		).toBe("cells=3 elided=1001 creates=3002 removes=0 parked=0 recycled=0")
		s.dispose()
	end)

	it("...and a width write on the ROW itself is the same shape", function()
		-- RED AT BASE: the probe count is this branch's own number.
		local s = deep.new({})
		s.width(500, 280)
		s.width(500, 260)
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans} probes={st.lastCommitProbes} visits={st.lastCommitVisits}`).toBe(
			"scans=1011 probes=0 visits=24"
		)
		s.dispose()
	end)

	it("a viewport change filters nothing — the unpruned arm never reaches the filter", function()
		--[[ GREEN AT BASE — a forward guard. `descendOf` returns `node.children` before `buildDescend` is ever called
			when `pruning` is false, and a viewport change is a full solve with no reuse
			table at all. So the filter is not "off" here; it is unreachable, and both
			counters say so. ]]
		local s = deep.new({})
		s.text(500, "warm")
		s.viewport(1000, 700)
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans} probes={st.lastCommitProbes} visits={st.lastCommitVisits}`).toBe(
			"scans=6 probes=0 visits=21014"
		)
		s.dispose()
	end)

	it("a structural churn degrades to today's probe count", function()
		--[[ GREEN AT BASE, BY DESIGN — that is what "degrades to today's count" MEANS, and
			the number is here so a later reader cannot mistake a small probe count elsewhere
			for a universal one. THE ARM THE FILTER CANNOT HELP, priced rather than hoped for. An insert
			into the `ForEach` region dirties the region and re-arranges the list, so
			most children are either dirty or walked and the probe is asked of them
			anyway. `probes` close to `scans` is the correct answer here, and having it
			written down is what stops a later reader reading a small number as a
			universal one. ]]
		local s = deep.new({ rows = 60, foreach = true })
		s.text(3, "warm")
		s.insertItem("x1")
		local st = s.stats() :: any
		expect(`scans={st.lastCommitScans} probes={st.lastCommitProbes}`).toBe("scans=193 probes=183")
		s.dispose()
	end)
end)

describe("C14: A CLEAN CHILD OF A DIRTY PARENT is still descended", function()
	it("a `fill` child commits its new rect when its row's width moves", function()
		--[[ THE ACCEPTANCE TEST, and it is C4's own refutation asked of the mechanism
			that replaced it. The signal is bound to `/S/List/R5`'s `width`, so
			`markDirtyIn` marks `/S/List/R5`, `/S/List` and `/S` and nothing below — the
			`fill` child is in NO dirty set. A `dirtyChildren` index prunes it and the
			box paints 300 px for the life of the surface. `walked` is not a dirty set:
			the solve RE-ARRANGED that child, so `arrangeBody` ran for it and it is in
			`walkedIds`, and the probe is asked exactly as before.

			The two rect assertions are green at base by construction — this is a
			forward guard, not a red for this commit. Mutation 2 (`nodeDirty` as the
			filter) is what makes them bite. ]]
		local s = fillScene(true)
		expect(s.rectOf("/S/List/R5/Fill")).toBe("0,80,300,10")
		s.setWidth(220)
		expect(s.rectOf("/S/List/R5/Fill")).toBe("0,80,220,10")
		-- and the ADAPTER has it, not just the solver: a rect nobody wrote is the
		-- exact defect the index would have shipped
		local live = s.adapter.liveNodes()["/S/List/R5/Fill"]
		local stored = (live :: any).storedRect
		expect(`w={stored.w}`).toBe("w=220")
		local st = s.controller.stats() :: any
		expect(`scans={st.lastCommitScans} probes={st.lastCommitProbes} solves={st.solves}`).toBe(
			"scans=30 probes=1 solves=2"
		)
		s.dispose()
	end)

	it("...and the filtered arm agrees with a full-walk arm rect for rect", function()
		-- GREEN AT BASE: a differential guard on the prune, not this branch's red.
		local a = fillScene(true)
		local b = fillScene(false)
		for _, px in { 220, 300, 180, 180, 420 } do
			a.setWidth(px)
			b.setWidth(px)
			for i = 1, 20 do
				expect(`{px} R{i} {a.rectOf(`/S/List/R{i}`)}`).toBe(`{px} R{i} {b.rectOf(`/S/List/R{i}`)}`)
				expect(`{px} R{i}/Fill {a.rectOf(`/S/List/R{i}/Fill`)}`).toBe(
					`{px} R{i}/Fill {b.rectOf(`/S/List/R{i}/Fill`)}`
				)
			end
		end
		a.dispose()
		b.dispose()
	end)
end)

describe("C14: a `ForEach` REGION is never filtered", function()
	it("a padding write on the list still reaches every item inside the region", function()
		--[[ GREEN AT BASE — a forward guard, and the reason `own ~= nil` is a term at all.
			REVIEW ROUND 3'S MUST-FIX, DRIVEN. The region is `List`'s first mount
			child and has no layout node — `layout_node`'s `appendChild` splices its
			children into `List`'s flow — so it is in no dirty set, in none of the three
			published sets, and it owns no rect entry. Its ITEMS are re-placed (`List`'s
			padding moved) and are therefore walked; but the commit reaches them only
			THROUGH the region. Without `commitRects[p] ~= nil` the region is pruned and
			its whole subtree goes with it.

			The assertion is the ADAPTER's stored rect, not the solver's: the solver is
			correct either way and the defect is a write that never happened. ]]
		local s = deep.new({ rows = 8, foreach = true, listPad = true })
		s.text(3, "warm")
		--[[ the item paths, discovered rather than spelled: a `ForEach` row's path is
			the reconciler's business and a hard-coded one would be a pin on it. ]]
		local paths: { string } = {}
		for path in s.adapter.liveNodes() do
			if string.find(path, "/List/F/", 1, true) ~= nil then
				table.insert(paths, path)
			end
		end
		table.sort(paths)
		expect(`items={#paths}`).never().toBe("items=0")
		local function stored(): string
			local live = s.adapter.liveNodes()
			local out = {}
			for _, path in paths do
				local r = (live[path] :: any).storedRect
				table.insert(out, `{path}={if r == nil then "-" else tostring(r.y)}`)
			end
			return table.concat(out, " ")
		end
		local function solved(): string
			local out = {}
			for _, path in paths do
				local r = s.controller.rectOf(path)
				table.insert(out, `{path}={if r == nil then "-" else tostring(r.y)}`)
			end
			return table.concat(out, " ")
		end
		local before = stored()
		s.listPad(24)
		-- THE WITNESS: the adapter's own rect moved, and it agrees with the solver's.
		-- Pruning the region leaves the first line equal and the second unequal.
		expect(`before={before}`).never().toBe(`before={stored()}`)
		expect(`adapter {stored()}`).toBe(`adapter {solved()}`)
		s.dispose()
	end)
end)

describe("C14: the fast path is the verdict, and the two nils that refuse it", function()
	--[[ A HAND-BUILT COMMIT, because the three claims below are about `buildDescend`'s
		own branch and a mounted fixture cannot put a node into these states on demand.
		`commit_walks.new` takes a ctx once per attach; `harvest` arms the commit. ]]
	local commit_walks = require("../src/render/commit_walks")
	local function newWalks(): (any, any)
		local function tbl(): any
			return {}
		end
		local ctx: any = {
			adapter = {},
			handles = tbl(),
			stats = {
				lastCommitVisits = 0,
				lastCommitVisitsByWalk = {},
				lastCommitScans = 0,
				lastCommitProbes = 0,
				propWrites = 0,
				rectWrites = 0,
			},
			rectsEqual = function(x: any, y: any): boolean
				return x == y
			end,
			paintedRectIn = function(): any
				return nil
			end,
			pathEscapesClip = function(): boolean
				return false
			end,
			reculPathClips = function() end,
			lastTextSize = tbl(),
			lastTextFont = tbl(),
			lastPadding = tbl(),
			lastCompact = tbl(),
			lastWrapped = tbl(),
			lastVisible = tbl(),
			lastHitRects = tbl(),
			lastScrollRegions = tbl(),
			scrollAutoscroll = tbl(),
			pathClipObservers = tbl(),
			solverHidden = tbl(),
			paintHeld = tbl(),
			pathNodes = tbl(),
			inputSinks = tbl(),
			noteWorn = function() end,
			lastCommitEntry = tbl(),
			hiddenRoots = tbl(),
			lastCompositions = tbl(),
			lastTextFacts = tbl(),
			authoredHidden = tbl(),
		}
		return commit_walks.new(ctx), ctx
	end
	-- a root with two clean leaves, both owning an entry, neither dirty: the shape the
	-- fast path exists for, small enough that the probe count IS the assertion
	local function tree(): (any, any, any)
		local a = { path = "/S/A", class = "Box", props = {}, children = {} }
		local b = { path = "/S/B", class = "Box", props = {}, children = {} }
		local root = { path = "/S", class = "Screen", props = {}, children = { a, b } }
		local rects: any = {
			["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } },
			["/S/A"] = { rect = { x = 0, y = 0, w = 10, h = 10 } },
			["/S/B"] = { rect = { x = 0, y = 10, w = 10, h = 10 } },
		}
		return root, rects, { a = a, b = b }
	end

	it("a child whose committed entry IS this solve's entry costs no call", function()
		-- RED AT BASE: this is the fast path, counted.
		local walks, ctx = newWalks()
		local root, rects = tree()
		local metrics = {}
		local dirty: any = { ["/S"] = true }
		-- NOTHING NOTED YET: both leaves must be probed, because an entry no commit
		-- ever wrote is exactly what `lastCommitEntry[p] == own` refuses
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		expect(`unnoted-probes={ctx.stats.lastCommitProbes} scans={ctx.stats.lastCommitScans}`).toBe(
			"unnoted-probes=2 scans=3"
		)
		-- ...and once ONE of them is committed, only the other one costs a call. The
		-- scan count does not move between the two readings.
		ctx.lastCommitEntry["/S/A"] = rects["/S/A"]
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`noted-probes={ctx.stats.lastCommitProbes} scans={ctx.stats.lastCommitScans}`).toBe(
			"noted-probes=1 scans=3"
		)
	end)

	it("A DIRTY CHILD WITH A SETTLED ENTRY is dirty for the base and move shapes", function()
		--[[ RED AT BASE. THE ONE STATE IN WHICH `dirtyAll` MATTERS ON THIS PATH. `commitDirty` is a
			SUBSET of `nodeDirty` (T5b drops the seven props that move a node and change
			nothing a walk reads), so `dirtyCommit` implies `dirtyAll` and the branch
			above catches every child in both sets. What reaches the fast path with
			`dirtyAll` true is the MIXED child: in the all-classes set, out of the
			commit-side one, and holding the entry the last commit wrote — a node the
			solve did not re-arrange, dirtied by something the arrange-blind walks are
			entitled to ignore and the other two are not.

			`dirtyCommit` is the mirror image and is unreachable here: false on every
			child that gets this far, by the subset relation. `skipC = not dirtyCommit`
			is written for symmetry with the slow path below it, and a mutation to
			`skipC = true` is EQUIVALENT rather than wrong. ]]
		local walks, ctx = newWalks()
		local root, rects, kids = tree()
		local metrics = {}
		local dirty: any = { ["/S"] = true, ["/S/A"] = true }
		local commitDirty: any = { ["/S"] = true }
		ctx.lastCommitEntry["/S/A"] = rects["/S/A"]
		ctx.lastCommitEntry["/S/B"] = rects["/S/B"]
		walks.harvest(root, rects, true, dirty, 1, metrics, 0, commitDirty)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0, commitDirty)
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		--[[ ...READ THROUGH `descendOf`, NOT `skip`. `skip` computes its own answer
			from the same inputs and would pass whatever `buildDescend` decided — it is
			the walks' ROOT guard, and every other node is answered by the list its
			parent built. The three lists ARE the assertion. ]]
		local function list(moveBlind: boolean?, arrangeBlind: boolean?): string
			local out = {}
			for _, child in walks.scope.descendOf(root, moveBlind, arrangeBlind) do
				table.insert(out, child.path)
			end
			table.sort(out)
			return table.concat(out, " ")
		end
		-- the two shapes that read `nodeDirty` must descend the dirty child; the
		-- arrange-blind shape, answered against the narrower set, may drop it. `/S/B`
		-- is clean and settled and is out of all three, which is what says these
		-- answers are about the dirty set and not about the fast path declining.
		expect(`base={list()}`).toBe("base=/S/A")
		expect(`move={list(true)}`).toBe("move=/S/A")
		expect(`commit={list(true, true)}`).toBe("commit=")
		-- neither child cost a call: both entries are the ones the last commit wrote
		expect(`probes={ctx.stats.lastCommitProbes} scans={ctx.stats.lastCommitScans}`).toBe("probes=0 scans=3")
	end)

	it("A NEVER-COMMITTED ENTRY still reaches the probe, and is still descended", function()
		--[[ RED AT BASE. THE RED THE UNION FILTER PRODUCED, kept as a case in its own right.
			`rect_pass` deliberately does NOT record a node the commit had no handle for,
			so `lastCommitEntry[p]` is nil while `commitRects[p]` is a perfectly good
			entry — and the next commit MUST descend to it. `nil == own` is false, so the
			fast path declines and `entryVerdict` answers `settled = false`. A predicate
			that tested only "does this child own an entry" would prune it. ]]
		local walks, ctx = newWalks()
		local root, rects, kids = tree()
		local metrics = {}
		local dirty: any = { ["/S"] = true }
		ctx.lastCommitEntry["/S/A"] = rects["/S/A"]
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`noted={walks.scope.skip(kids.a, true)}`).toBe("noted=true")
		expect(`never-noted={walks.scope.skip(kids.b, true)}`).toBe("never-noted=false")
		expect(`probes={ctx.stats.lastCommitProbes}`).toBe("probes=1")
	end)

	it("AN ENTRY-LESS CHILD is never fast-pathed, whatever `lastCommitEntry` holds", function()
		--[[ GREEN AT BASE — a forward guard on a term, not a red. THE `nil == nil` TRAP, which this file's ancestor already paid for once:
			C4's header records that a predicate comparing `rects[path]` directly read
			`nil == nil` on every spliced region and pruned the whole subtree. `own ~= nil`
			is the term that refuses it, and a region whose own `note` wrote nil is the
			state where the two nils meet. ]]
		local walks, ctx = newWalks()
		local leaf = { path = "/S/R/L", class = "Box", props = {}, children = {} }
		local other = { path = "/S/R/M", class = "Box", props = {}, children = {} }
		-- a REGION: two children, so `probeEntry` answers nil for it and it owns no
		-- entry of its own, exactly as `UI.ForEach` mounts
		local region = { path = "/S/R", class = "ForEach", props = {}, children = { leaf, other } }
		local root = { path = "/S", class = "Screen", props = {}, children = { region } }
		local rects: any = {
			["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } },
			["/S/R/L"] = { rect = { x = 0, y = 0, w = 10, h = 10 } },
			["/S/R/M"] = { rect = { x = 0, y = 10, w = 10, h = 10 } },
		}
		local metrics = {}
		local dirty: any = { ["/S"] = true }
		-- what `note(region)` writes: `probeEntry` of a two-child region is nil
		ctx.lastCommitEntry["/S/R"] = nil
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`region-skipped={walks.scope.skip(region, true)}`).toBe("region-skipped=false")
		-- the region cost a call and its children were reached
		expect(`probes={ctx.stats.lastCommitProbes} scans={ctx.stats.lastCommitScans}`).toBe("probes=3 scans=4")
	end)

	it("A BOTH-DIRTY CHILD READS NO ENTRY AT ALL — the dirty test comes first", function()
		--[[ RED AT BASE (fix round 1, review Important 1). The first shipped form read
			`commitRects[p]` ABOVE the `dirtyAll and dirtyCommit` short-circuit, so every
			child in both sets paid a hash lookup HEAD never took — once per child, on
			exactly the commits that have the most children. Fifty lines above the branch,
			`commit_walks` records the same lesson from C4 fix round 1: "AND THE DIRTY
			TEST COMES FIRST, EXACTLY AS `skip` ORDERS IT … Losing that short-circuit is
			what the reorder regression actually was." Measured, the hoist WAS the whole
			booked regression: `war_room_inventory reorder` `cw.harvest` 0.374 -> 0.429 ms,
			+14.7 %.

			THE INSTRUMENT IS A COUNTING PROXY, not a counter in the source. A hash lookup
			cannot be counted in production without paying more than it costs, so the map
			`harvest` is handed is an EMPTY table whose `__index` forwards to the real one
			and tallies. `commitRects` is a plain upvalue read with a computed key, so
			every read in the file goes through it and none of them can tell.

			AND THE CLASSIFIED SUBTREE IS DETACHED FROM THE HARVESTED ONE, which is the
			difference between measuring this branch and measuring C4's cache: `harvest`
			walks its own tree and fills `descendKids` on the way, so a `descendOf` of a
			node it already visited reads the CACHE and would report zero however this
			branch is written. `/X` is never harvested, so its classification is fresh. ]]
		local walks, ctx = newWalks()
		local rects: any = { ["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } } }
		local dirty: any = { ["/S"] = true, ["/X"] = true }
		local kids: { any } = {}
		for i = 1, 8 do
			local path = `/X/D{i}`
			kids[i] = { path = path, class = "Box", props = {}, children = {} }
			rects[path] = { rect = { x = 0, y = i, w = 10, h = 10 } }
			-- EVERY child in BOTH sets: the reorder shape, where the fast path can never
			-- fire and a read above the branch is therefore pure loss
			dirty[path] = true
		end
		local harvested = { path = "/S", class = "Screen", props = {}, children = {} }
		local detached = { path = "/X", class = "VStack", props = {}, children = kids }
		local reads = 0
		local counting = setmetatable({}, {
			__index = function(_, key: any): any
				reads += 1
				return rects[key]
			end,
		})
		local metrics = {}
		walks.harvest(harvested, counting :: any, true, dirty, 1, metrics, 0, dirty)
		walks.harvest(harvested, counting :: any, true, dirty, 1, metrics, 0, dirty)
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		reads = 0
		local list = walks.scope.descendOf(detached)
		--[[ ZERO. Not "fewer" — the eight children are answered by two reads of the DIRTY
			maps and the entry map is never consulted at all. `#list` is 8 beside it,
			because a both-dirty child is descended by every shape: this branch removed a
			LOOKUP and not a child, which is `lastCommitScans`' own claim one level up.
			(The stats record is written by a WALK's `publishVisits`, so a bare
			`descendOf` does not move it; the counter pins live in the mounted cases.) ]]
		expect(`reads={reads} kept={#list}`).toBe("reads=0 kept=8")

		--[[ ...AND THE CONTROL, which is what makes the zero above mean something. The
			same eight children CLEAN read the entry map exactly ONCE EACH — once is what
			`entryVerdict` reads anyway, so the fast path costs nothing extra. A form that
			called `probeEntry` from the loop while already holding `own`, or that let
			`entryVerdict` re-read `lastCommitEntry`, would say more than 8 here. ]]
		local walks2, ctx2 = newWalks()
		for _, child in kids do
			ctx2.lastCommitEntry[child.path] = rects[child.path]
		end
		local clean: any = { ["/S"] = true, ["/X"] = true }
		local metrics2 = {}
		walks2.harvest(harvested, counting :: any, true, clean, 1, metrics2, 0, clean)
		walks2.harvest(harvested, counting :: any, true, clean, 1, metrics2, 0, clean)
		reads = 0
		local cleanList = walks2.scope.descendOf(detached)
		expect(`clean-reads={reads} kept={#cleanList}`).toBe("clean-reads=8 kept=0")
	end)

	it("A MOVE-ONLY ENTRY still reaches the probe, so `moved` is computed", function()
		--[[ RED AT BASE. The translate arm's entry is a FRESH table with `prev` pointing at the one
			the last commit wrote, so `lastCommitEntry[p] == own` is false and the fast
			path declines — which is required, because the three shapes disagree here:
			the move-blind walks may skip it and `hitRects`/`rect_pass`, which read a
			POSITION, may not. This is also the shape a walked-set filter got wrong: a
			successful translate ROOT is in neither `walkedIds` nor `translatedPaths`. ]]
		local walks, ctx = newWalks()
		local root, rects, kids = tree()
		local metrics = {}
		local dirty: any = { ["/S"] = true }
		local prev = rects["/S/B"]
		ctx.lastCommitEntry["/S/A"] = rects["/S/A"]
		ctx.lastCommitEntry["/S/B"] = prev
		rects["/S/B"] = { rect = { x = 4, y = 10, w = 10, h = 10 }, moveOnly = true, prev = prev }
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`move-blind={walks.scope.skip(kids.b, true)}`).toBe("move-blind=true")
		expect(`reads-position={walks.scope.skip(kids.b)}`).toBe("reads-position=false")
		expect(`probes={ctx.stats.lastCommitProbes}`).toBe("probes=1")
	end)
end)

describe("C14: `commitDirty` is a SUBSET of `nodeDirty`, and one line makes it so", function()
	it("`markDirtyIn(commitDirty, …)` has exactly one producer, inside the `nodeDirty` mark", function()
		--[[ GREEN AT BASE — a forward guard on an invariant this file ARGUES from (review
			fix round 1, Minor 5). Mutation 5 of this task's battery (`skipC = true` in
			place of `not dirtyCommit`) is recorded as a PROVEN-EQUIVALENT null, and the
			proof is exactly this: `commitDirty ⊆ nodeDirty`, so `dirtyCommit` implies
			`dirtyAll` and every both-dirty child is caught by the branch above the fast
			path. An argued invariant with no pin is how a null turns into a hole.

			(The SHIPPED line does not depend on it — when `dirtyCommit` is true,
			`not dirtyCommit` is false and so is HEAD's `not dirtyCommit and (settled or
			moved)`. The unconditional form is deliberate; this pin protects the
			null's VERDICT, not the code.)

			IT IS A SOURCE PIN BECAUSE THE PRODUCER IS THE RENDERER'S, one file over and
			behind an attach. `renderer.luau`'s dirty-scan loop marks `nodeDirty` for every
			entry and `commitDirty` for the subset that is not a `PURE_ARRANGE_PROPS`
			write, in the SAME iteration — so the subset is a property of that one block,
			and the thing that can break it is a second, unguarded `markDirtyIn(commitDirty,
			…)` appearing somewhere else. That is what this counts. ]]
		local fs = require("@lune/fs")
		local source = fs.readFile("src/render/renderer.luau")
		local producers = 0
		for _ in string.gmatch(source, "markDirtyIn%(commitDirty") do
			producers += 1
		end
		local all = 0
		for _ in string.gmatch(source, "markDirtyIn%(nodeDirty") do
			all += 1
		end
		expect(`commitDirty-producers={producers} nodeDirty-producers={all}`).toBe(
			"commitDirty-producers=1 nodeDirty-producers=1"
		)
		--[[ ...AND THE ONE PRODUCER IS INSIDE THE OTHER'S BLOCK, which is the half a
			count cannot say: the `commitDirty` mark must appear AFTER the `nodeDirty`
			mark with no intervening `end` at the loop's own depth. Read as text, the
			guard between them is the only thing that removes a path. ]]
		local between = string.match(source, "markDirtyIn%(nodeDirty[^\n]*\n(.-)markDirtyIn%(commitDirty")
		expect(`gap-found={between ~= nil}`).toBe("gap-found=true")
		expect(`guard={string.find(between :: string, "PURE_ARRANGE_PROPS", 1, true) ~= nil}`).toBe("guard=true")
		-- NEGATIVE CONTROL: the scan really does see a second producer
		local fake = "markDirtyIn(commitDirty, a)\nmarkDirtyIn(commitDirty, b)"
		local n = 0
		for _ in string.gmatch(fake, "markDirtyIn%(commitDirty") do
			n += 1
		end
		expect(`control={n}`).toBe("control=2")
	end)
end)

describe("C14: the differential oracle", function()
	it("every drive leaves the filtered arm and the full-walk arm byte-identical", function()
		--[[ GREEN AT BASE — C4's arm switch, kept as a guard (see the file header, Minor 7).
			THE SAME QUESTION C4's oracle asks, asked of the filter, on the fixtures
			whose sibling scan it cuts: a leaf's text, a row's own width, a coupled
			row's HEIGHT (which moves a CLEAN child's offer without dirtying it — the
			shape a dirty index would break), a viewport change (a full solve, no reuse
			table) and a list-padding write on the `foreach` arm, which moves every item
			inside a region that owns no entry. ]]
		for _, arm in { "plain", "coupled", "foreach" } do
			local a = deep.new({
				rows = 40,
				listPad = true,
				coupled = arm == "coupled",
				foreach = arm == "foreach",
			})
			local b = deep.new({
				rows = 40,
				listPad = true,
				coupled = arm == "coupled",
				foreach = arm == "foreach",
				commitScope = false,
			})
			local step = 0
			local function agree()
				step += 1
				expect(`{arm} step {step}\n{a.snapshot()}`).toBe(`{arm} step {step}\n{b.snapshot()}`)
			end
			for _, drive in
				{
					function(s: any)
						s.text(deep.GATE_ROW, "changed")
					end,
					function(s: any)
						s.width(deep.GATE_ROW, 240)
					end,
					function(s: any)
						s.height(deep.GATE_ROW, 40)
					end,
					function(s: any)
						s.listPad(18)
					end,
					function(s: any)
						s.viewport(900, 620)
					end,
					function(s: any)
						s.width(7, 200)
					end,
				}
			do
				drive(a)
				drive(b)
				agree()
			end
			a.dispose()
			b.dispose()
		end
	end)

	it("...at every view in the device matrix, on both adapters", function()
		--[[ GREEN AT BASE — C4's arm switch again. THE ADAPTER-FREE ARM is the price C4's review named: `solver.solve` driven
			directly over the same layout tree, so the comparison is the SOLVER's own
			answer and not a second reading of the adapter the first arm already read.
			Nine views, both arms, the whole rect map per view. ]]
		for _, view in device_views.VIEWS do
			local a = deep.new({
				rows = 20,
				foreach = true,
				listPad = true,
				viewport = { x = 0, y = 0, w = view.w, h = view.h },
			})
			local b = deep.new({
				rows = 20,
				foreach = true,
				listPad = true,
				commitScope = false,
				viewport = { x = 0, y = 0, w = view.w, h = view.h },
			})
			a.text(deep.GATE_ROW, "changed")
			b.text(deep.GATE_ROW, "changed")
			a.listPad(12)
			b.listPad(12)
			expect(`{view.name}\n{a.snapshot()}`).toBe(`{view.name}\n{b.snapshot()}`)
			a.dispose()
			b.dispose()
		end
	end)
end)
