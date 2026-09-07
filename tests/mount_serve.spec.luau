--!strict
--[[ D5 — A COLD SOLVE SERVES A NODE'S SECOND QUESTION FROM ITS FIRST ANSWER.

	THE NUMBER THIS EXISTS FOR. A `battle_hud L` mount measured 14,215 times on 5,106
	layout nodes — 2.78 measures per node — and `lastMeasured == lastMeasureCalls`
	exactly, which is the signature of a solve where nothing was cached at all
	(FacetBench §D1.4). The cause was one line: `record` refused to write its two slots
	when `ctx.reuse == nil`, so a mount recorded nothing and the arrange pass
	re-measured every node the measure pass had already answered at the same offer.
	The per-solve memo could not cover it either — `measure`'s early return takes every
	call when there is no store, no scroll node and no deep nesting, so `lastPlanVisits`
	is 0 on the cold mount of all five arena workloads.

	THE GATE IS NOW THE STAMP, AND THE PURITY CONTRACT IS UNCHANGED WHERE IT IS
	EXERCISED. `ctx.measureStamp` is threaded by exactly one caller — `render/renderer`
	takes it unconditionally on every solve it drives — and by nobody else:
	`dump.fromSolve`, the layout fuzzer and every hand-built spec tree pass none, so
	`record` still returns before its first write for all of them and
	`tests/layout.spec.luau`'s `table.freeze`d purity case still solves. That census is
	a case below rather than a claim.

	AND THE DIRT GATE GROWS A SECOND ARM RATHER THAN LOSING ITS FIRST. `measure`'s serve
	asks "has anything MEASURE-classed inside this node moved since the slot was
	written?". Across solves the answer is `reuse.measureContains`, the ancestor-closed
	dirty set. WITHIN one solve it is free — the tree is immutable for the solve's life
	— and `node.mSolve == ctx.solveToken` says exactly that. The two arms are disjoint
	by construction: `record` writes `mSolve` only when `ctx.reuse == nil`, i.e. only on
	the solves where the first arm is unavailable.

	WHY `mSolve` IS NOT WRITTEN ON AN INCREMENTAL SOLVE, which is the review question
	this design answers rather than dodges. It is ONE flag over TWO slots. On an
	incremental solve a node can arrive carrying a slot the PREVIOUS solve wrote at
	another offer under the same stamp; if `mSolve` were set on first record, a
	MEASURE-DIRTY node would pass the gate and its second ask at that other offer would
	be answered from last frame's number. The same hazard exists on a full solve, where
	`layoutNodeReuse` keeps the literal — and there `record` closes it by dropping BOTH
	slots on the node's first record of the solve, which costs nothing because a full
	solve had no cross-solve serve to lose.

	=====================================================================
	THE PUBLISH LIST FOR THE SERVED SECOND MEASURE — written before the code
	=====================================================================

	`tests/measure_serve.spec.luau`'s header enumerates the eleven channels `measure`
	publishes and what a served call does with each. Nothing in that table changes: the
	serve's body is the same body, and this task only widens WHEN the gate above it can
	open. What is owed is the delta — what a second measure on a COLD solve would have
	published that the first did not:

	  1  `ctx.offers[wKey]`/`[hKey]`   SERVED, from the offer in hand, exactly as on the
	                                   cross-solve path
	  2  the three text verdicts       SERVED for `text`/`composition`, from the slot
	     (`textStates`/`compact`/       — and the first measure of the same solve is what
	     `textFacts`)                   put them there
	  3  `ctx.fitCuts`                 SERVED as the slot's cut delta
	  4  `ctx.compositions` / `hasScroll` / the container arm / `ctx.boundary` /
	     the diagnostics replay        GATED, by the same five terms as before
	                                   (`subtreeHasComposition`, `subtreeHasScroll`,
	                                   `containerRelativeInside`, `ctx.analyze`,
	                                   `ctx.measureQuiet`) — untouched by this task
	  5  `measureReuse.note`           NOT SERVED, and unreachable: the store is nil on a
	                                   cold solve, so there is no hit counter to move
	  6  `ctx.measureCache[node]`      NOT SERVED — a per-solve convenience, and on a
	                                   cold solve the early return above it means the
	                                   cache is never even allocated
	  7  `ctx.mdepth` / `deepNesting`  BALANCED BY CONSTRUCTION: the serve returns before
	                                   `measureUncached`, which is the only frame that
	                                   pushes. ▲ CONSEQUENCE, STATED: a served second ask
	                                   no longer arms `deepNesting`, which is why
	                                   `lastPlanVisits` moves 0 -> one per node on a cold
	                                   solve rather than staying 0 — `record` asks
	                                   `memoPlan` for the offer-height key, and that
	                                   verdict is cached on the literal since D1
	  8  `node.mTextW`                 NOT SERVED, and right: the uncached text branch
	                                   writes it, so the FIRST measure of this solve did
	  9  `render/text_index`'s filing  NOT SERVED, and unchanged: the index is populated
	                                   at measure time and persists across served solves
	                                   by design (its own header), and the first measure
	                                   of a cold solve files every node
	 10  the DIAGNOSTICS a second      NOT REFILED, and that is the one channel where
	     measure would file again      HEAD produced a DUPLICATE: a malformed node
	                                   measured twice on a cold solve filed its finding
	                                   twice. Nothing in the suite reads a duplicate, the
	                                   `(node, issue)` pair is what the replay already
	                                   treats as identity, and the differential over the
	                                   nine views below compares `diagnostics` as a
	                                   channel — see the oracle
	 11  `ctx.measured` / `Served`     MOVE BY DESIGN; every pin re-recorded in this
	                                   commit, Facet and Rascal Rally
	 12  ▲ `text_metrics`' COLLECTOR   THE CHANNEL THE ELEVEN-ROW TABLE NEVER NAMED, and
	     QUEUE                          the run is what found it. A text node's measure
	                                    files its unknown words as REQUESTS; a served one
	                                    does not. Within a solve that is free (the first
	                                    measure filed them), but the mount's own
	                                    truncation is not: with a vocabulary over the
	                                    1,024-word budget the surplus was DROPPED, and
	                                    the only thing that ever brought it back was the
	                                    next solve re-measuring the tree for want of
	                                    anything to serve from. D5 removes that accident,
	                                    so the surplus is now HELD instead of dropped
	                                    (`text_metrics`' `overflow`, and the case below).
	                                    `tests/text_collect_inflight.spec.luau` is where
	                                    the surface-level drain is driven

	── THE MUTATIONS, run and recorded in `d5-mutations.txt`
	  M1  drop `or node.mSolve == ctx.solveToken` from the gate -> BITES: the headline
	      returns to HEAD's `measured=5003`, and `measure_serve`/`container_memo` with it
	  M4  gate `record` on `ctx.reuse` again -> BITES: every count in this file, in
	      `measure_serve` and in `container_memo` returns to HEAD
	  M5  drop the collector's overflow queue -> BITES: the tail case below, and
	      `text_collect_inflight`'s red arm
	  M2  write `mSolve` on EVERY solve (delete `record`'s `ctx.reuse == nil` guard)
	      -> BITES ON THE COUNTS, 9 cases in `measure_serve` and 10 in `container_memo`:
	      the within-solve arm then fires on incremental solves too and every steady-state
	      `served`/`measured` pin moves. It does NOT bite on any rect, and that is the
	      finding recorded below
	  M3  drop the both-slots invalidation on a full solve's first record -> **KEPT NULL**
	      on all four specs, and the reason is a design fact rather than a missing case.
	      `render/layout_node` rebuilds a FRESH literal for every node in the dirty set,
	      which is ANCESTOR-CLOSED and strictly wider than `measureContains` — so a node
	      whose measured answer can have moved is never the table that carries the old
	      slots, and the stale slot the guard protects against cannot exist. Two attempts
	      to reach it are in this file and both stay green under the mutation: the
	      `incremental = false` list (where the edit that invalidates an answer also moves
	      the list's resolved offer, so a stale slot is MISSED rather than served) and the
	      `ViewThatFits` candidate (one offer, two scopes, and nothing inside able to move
	      either — the candidate is rebuilt anyway). Both are KEPT: the invalidation and
	      the `ctx.reuse == nil` guard together make this serve's correctness local to
	      `record`, where without them the gate is only as sound as another module's
	      rebuild invariant — which `tests/plan_cache.spec.luau`'s own NEGATIVE CONTROL
	      exists to say is an invariant and not a law of nature. The two cases stay too:
	      neither reddens this mutation, but both are byte-level differentials over the
	      FULL-solve path, which nothing else in the suite drives against an incremental
	      control
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local scene = require("./lib/deep_stack_scene")
local device_views = require("./lib/device_views")
local solver = require("../src/layout/solver")
local text_metrics = require("../src/layout/text_metrics")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local customFactory = require("../src/core/custom")

local ROWS = 1000

describe("D5: the cold solve measures every node ONCE", function()
	it("a mount of 3,002 layout nodes measures 3,002 times, and serves the rest", function()
		--[[ THE HEADLINE, AND THE RED. At HEAD this reads `measured=5003 calls=5003
			served=0` — 1.67 measures per node on this fixture, 2.78 on `battle_hud L` —
			because a cold solve had nothing recorded to answer from. `measured` is now
			EXACTLY the layout-node count, which is the floor: a solve cannot arrange a
			node it never measured.

			`calls` MOVES TOO, AND THE BRIEF EXPECTED IT NOT TO. 5,003 -> 4,003, and the
			1,000 that disappear are not served — they are never made. A container the
			arrange pass re-asks is answered from its slot and RETURNS, so the recursion
			into its children never happens and their second calls are not made either.
			1,001 served + 1,000 unasked = the 2,001 second measures HEAD paid for. ]]
		local s = scene.new({ rows = ROWS })
		local st = s.stats() :: any
		expect(
			`measured={st.lastMeasured} calls={st.lastMeasureCalls} served={st.lastMeasureServed}`
				.. ` nodes={st.lastLayoutNodes} solves={st.solves}`
		).toBe("measured=3002 calls=4003 served=1001 nodes=3002 solves=1")
		--[[ ...AND THE PLAN VERDICT IS COMPUTED ONCE PER NODE, which is row 7 of the
			publish list above said as a number. It is 0 at HEAD — a cold solve never
			reached `memoPlan` at all, because `measure`'s early return fires when there
			is no store, no scroll node and no deep nesting — and it is one per node now
			because `record` asks for the offer-height key. D1 cached that verdict on the
			literal, so it is one visit and not a walk. ]]
		expect(`plans={st.lastPlanVisits} of {st.lastLayoutNodes}`).toBe(`plans=3002 of 3002`)
		s.dispose()
	end)

	it("the `measureReuse = false` mount lands the same tree, byte for byte", function()
		--[[ AND IT SHARES THE PATH, WHICH IS SAID HERE RATHER THAN LEFT TO BE ASSUMED.
			`measureReuse = false` turns off the cross-solve STORE; the stamp is taken
			unconditionally either way, so this arm records and serves exactly as the
			other one does. It is a compatibility check, not an oracle — the oracle is
			the next case, whose slow arm is the pre-D5 code path itself. ]]
		local a = scene.new({ rows = 40 })
		local b = scene.new({ rows = 40, measureReuse = false })
		expect(a.snapshot() == b.snapshot()).toBe(true)
		a.text(7, "x")
		b.text(7, "x")
		expect(a.snapshot() == b.snapshot()).toBe(true)
		a.dispose()
		b.dispose()
	end)
end)

--[[ ── THE SWITCH-INDEPENDENT ORACLE ────────────────────────────────────────────
	The slow arm is not a flag: it is a solve with NO `measureStamp`, which is the
	code HEAD ran on every solve and which `record` still returns from before its
	first write. So the comparison is "the solver as it was" against "the solver as
	it is", over the SAME production layout tree — the one the renderer built and
	handed to `solver.solve` — at all nine device viewports.

	THE THIRD ARM IS THE ORDER CONTROL. A solve with a stamp WRITES to the node
	tables, so the slow arm is run again AFTER it: if the fast arm left a node in a
	state that changes what a later solve answers, the third arm disagrees with the
	first. `tests/lessons`' own rule — a divergence that moves with arm ORDER is
	shared state, not the arm. ]]
describe("D5 oracle: a stamped solve and an unstamped one agree, every view", function()
	local function serialize(result: any): string
		local ids: { string } = {}
		for id in result.rects do
			table.insert(ids, id)
		end
		table.sort(ids)
		local function ser(v: any, depth: number): string
			if type(v) ~= "table" then
				return tostring(v)
			end
			if depth <= 0 then
				return "…"
			end
			local inner: { string } = {}
			for k, item in v do
				table.insert(inner, `{tostring(k)}={ser(item, depth - 1)}`)
			end
			table.sort(inner)
			return `\{{table.concat(inner, ",")}\}`
		end
		local parts: { string } = {}
		for _, id in ids do
			table.insert(parts, `{id}|{ser(result.rects[id], 5)}`)
		end
		local diags: { string } = {}
		for _, d in result.diagnostics do
			table.insert(diags, `{d.node}:{d.issue}`)
		end
		table.sort(diags)
		table.insert(parts, `diagnostics={#result.diagnostics}|{table.concat(diags, ";")}`)
		return table.concat(parts, "\n")
	end

	--[[ THE TREE IS THE RENDERER'S OWN. `solver.solve` is wrapped for one mount so the
		layout root, the viewport and the opts it was handed are captured verbatim; a
		hand-built tree would be a different tree and a differently-built one would be a
		different measurement. ]]
	local function capturedSolve(build: () -> any): (any, any, any, () -> ())
		local root, viewport, opts
		local real = solver.solve
		solver.solve = function(...)
			root, viewport, opts = (select(1, ...)), (select(2, ...)), (select(3, ...))
			return real(...)
		end
		local ok, disposer = pcall(build)
		solver.solve = real
		if not ok then
			error(disposer, 0)
		end
		return root, viewport, opts, disposer :: any
	end

	local FIXTURES: { { name: string, opts: any } } = {
		{ name = "plain", opts = { rows = 24 } },
		{ name = "hug", opts = { rows = 24, hug = true } },
		{ name = "scroll", opts = { rows = 24, scroll = true } },
		{ name = "coupled", opts = { rows = 24, coupled = true } },
		{ name = "label", opts = { rows = 24, label = true, nested = true } },
	}

	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, the published entry and the diagnostics all agree`, function()
			for _, view in device_views.VIEWS do
				local o = table.clone(fixture.opts)
				o.viewport = { x = 0, y = 0, w = view.w, h = view.h }
				local root, viewport, opts, dispose = capturedSolve(function()
					local s = scene.new(o)
					return function()
						s.dispose()
					end
				end)
				local slowOpts = table.clone(opts)
				slowOpts.measureStamp = nil
				slowOpts.reuse = nil
				local fastOpts = table.clone(slowOpts)
				fastOpts.measureStamp = "d5-oracle"
				local before = serialize(solver.solve(root, viewport, slowOpts))
				local fast = serialize(solver.solve(root, viewport, fastOpts))
				local after = serialize(solver.solve(root, viewport, slowOpts))
				local label = `{fixture.name}/{view.id}`
				if before ~= fast then
					error(`{label}: the STAMPED solve diverged from the unstamped one`, 0)
				end
				if before ~= after then
					error(`{label}: the unstamped solve changed after a stamped one ran — shared state`, 0)
				end
				dispose()
			end
		end)
	end
end)

describe("D5: the slot a FULL solve inherits is the one it must not serve", function()
	it("a surface that FULL-solves every tick agrees with one that never does", function()
		--[[ THE NEGATIVE CONTROL FOR THE INVALIDATION IN `record`, and the hazard is
			exact. `layoutNodeReuse` keeps a node literal across solves, so a full solve
			meets slots the PREVIOUS solve wrote under the same stamp. `mSolve` is ONE
			flag over TWO slots: claim one with this solve's answer and the other still
			holds last frame's, and the within-solve gate cannot tell them apart — so the
			arrange pass's ask at the other offer is answered from a number this solve
			never produced. `record` closes it by dropping both slots on the node's first
			record of a full solve, which costs a full solve nothing (it had no
			cross-solve serve to lose) and is what this case reddens without.

			`incremental = false` is the arm that makes every refresh a full solve, and
			`hug` is what makes a row asked at TWO offers — the list's measure pass hands
			it the screen's width and its arrange pass the list's resolved one. A `fill`
			list has one offer and cannot witness this at all. The control is the same
			fixture on the ordinary incremental path, whose gate this task does not
			touch. ]]
		local full = scene.new({ rows = 24, hug = true, incremental = false })
		local ref = scene.new({ rows = 24, hug = true })
		local function agree(step: string)
			if full.snapshot() ~= ref.snapshot() then
				error(`{step}: the FULL-solving surface diverged from the incremental one`, 0)
			end
		end
		agree("mount")
		for step = 1, 4 do
			local label = string.rep("wide", step * 3)
			full.text(step + 2, label)
			ref.text(step + 2, label)
			agree(`text {step}`)
			full.width(step + 2, 40 + step * 31)
			ref.width(step + 2, 40 + step * 31)
			agree(`width {step}`)
			full.text(step + 2, "s")
			ref.text(step + 2, "s")
			agree(`shrink {step}`)
		end
		full.dispose()
		ref.dispose()
	end)

	it("...and the shape that actually reaches it is a ViewThatFits candidate", function()
		--[[ THE CASE ABOVE IS THE PRODUCTION SHAPE AND IT DOES NOT BITE, WHICH IS A
			FINDING RATHER THAN A GAP. A stale slot can only be SERVED if its key still
			matches, and on a `hug` list the very edit that makes last frame's answer
			wrong also moves the list's resolved width — so the second offer moves with
			it and the stale slot is missed rather than served. The list arm is kept for
			the rects it does prove; this one is the arm where both offers stand still.

			ONE OFFER, TWO SCOPES. `ViewThatFits` measures the SAME candidate at the SAME
			`(maxW, maxH)` twice — once with the shrink pass suppressed (`0|fit`) and once
			without — so the two slots differ by SCOPE alone, and the `Fits` box is fixed,
			so nothing inside the candidate can move either offer. Change the candidate,
			full-solve, and the probe refreshes the slot it matches while the real
			measure's slot still holds last frame's answer: without the invalidation the
			real measure is answered from it. Driven against the incremental arm, whose
			gate this task does not touch, on the rects the arranger paints. ]]
		local function world(incremental: boolean): (any, any, any)
			local core = customFactory.new()
			local env = environment.new(core)
			env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 400 })
			local innerW = core:signal(900)
			local root = mountLib.mount(
				core,
				UI.Screen({
					id = "S",
					children = {
						UI.ViewThatFits({
							id = "Fits",
							width = { type = "fixed", px = 400 },
							height = { type = "fixed", px = 60 },
							children = {
								UI.VStack({
									id = "Rich",
									width = { type = "fixed", px = 400 },
									height = { type = "content" },
									padding = 0,
									gap = 0,
									children = {
										UI.HStack({
											id = "Inner",
											width = { type = "hug" },
											height = { type = "fixed", px = 40 },
											padding = 0,
											gap = 0,
											children = {
												UI.Box({
													id = "Big",
													width = core:memo(function(use: any)
														return { type = "fixed", px = use(innerW) :: number }
													end),
													height = { type = "fixed", px = 40 },
												}),
											},
										}),
									},
								}),
								UI.Box({
									id = "Plain",
									width = { type = "fixed", px = 50 },
									height = { type = "fixed", px = 20 },
								}),
							},
						}),
					},
				})
			)
			local adapter = fake_target.new()
			local controller = rendererLib.attach(core, root, env, adapter, {
				rootPolicy = "edgeToEdge",
				incrementalLayout = incremental,
				measureReuse = true,
				layoutNodeReuse = true,
				commitScope = true,
			})
			controller.initialRender()
			return controller, innerW, function()
				controller.dispose()
				root.dispose()
			end
		end
		local fullC, fullSig, fullDispose = world(false)
		local refC, refSig, refDispose = world(true)
		local function line(c: any): string
			local out: { string } = {}
			for _, path in { "/S/Fits", "/S/Fits/Rich", "/S/Fits/Rich/Inner", "/S/Fits/Rich/Inner/Big" } do
				local r = c.rectOf(path)
				table.insert(out, `{path}={if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`}`)
			end
			return table.concat(out, " ")
		end
		local function agree(step: string)
			if line(fullC) ~= line(refC) then
				error(`{step}: FULL {line(fullC)} vs INCREMENTAL {line(refC)}`, 0)
			end
		end
		agree("mount")
		for _, w in { 120, 700, 90, 1400, 300 } do
			fullSig:set(w)
			fullC.refresh()
			refSig:set(w)
			refC.refresh()
			agree(`inner={w}`)
		end
		fullDispose()
		refDispose()
	end)
end)

describe("D5: the purity contract, and the census that makes the swap exact", function()
	it("`measureStamp` reaches a solve from ONE caller in `src/`, and it is the renderer", function()
		--[[ THE WHOLE OF THE PURITY ARGUMENT, MECHANISED. `record`'s refusal moved from
			"this solve has no reuse set" to "this solve has no stamp", and that swap is
			exact only while the stamp is the renderer's alone: a second producer would
			hand the recorder a frozen tree and turn `tests/layout.spec.luau`'s purity
			case into a hard error. The scan is over the SOLVE-OPTS assignment
			(`measureStamp = ` on the left of a table field), not over the identifier,
			because `solver`, `stack`, `stack_measure` and `solve_ctx` all READ it. ]]
		local producers: { string } = {}
		local function scan(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(entry, -5) == ".luau" then
					local source = fs.readFile(path)
					local stripped = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
					stripped = string.gsub(stripped, "\n[ \t]*%-%-[^\n]*", "\n")
					if string.find(stripped, "measureStamp = ", 1, true) ~= nil then
						table.insert(producers, path)
					end
				end
			end
		end
		scan("src")
		table.sort(producers)
		--[[ TWO, AND ONLY ONE OF THEM IS A CALLER. `renderer.luau` writes it into
			`solveOpts`; `solve_ctx.luau` writes it into the CONTEXT off those opts, which
			is the reader's side of the same one channel. Nothing in `src/layout/` builds
			a solve. ]]
		expect(producers).toEqual({ "src/layout/solve_ctx.luau", "src/render/renderer.luau" })
		local renderer = fs.readFile("src/render/renderer.luau")
		expect(string.find(renderer, "measureStamp = measureStamp,", 1, true) ~= nil).toBe(true)
		local ctx = fs.readFile("src/layout/solve_ctx.luau")
		expect(
			string.find(ctx, "measureStamp = if opts ~= nil then (opts :: any).measureStamp else nil", 1, true) ~= nil
		).toBe(true)
		--[[ ...AND NO SPEC, TOOL OR BENCH HANDS ONE TO `solver.solve` EITHER, which is
			the other half: the fuzzer and `dump.fromSolve` are the direct callers the
			contract is about, and this file's own oracle above is the one exception —
			it passes a stamp deliberately, to a tree the RENDERER built and never froze. ]]
		local others: { string } = {}
		for _, dir in { "tests", "tools", "bench" } do
			local function walk(d: string)
				for _, entry in fs.readDir(d) do
					local path = `{d}/{entry}`
					if fs.isDir(path) then
						walk(path)
					elseif string.sub(entry, -5) == ".luau" then
						local source = fs.readFile(path)
						local stripped = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
						stripped = string.gsub(stripped, "\n[ \t]*%-%-[^\n]*", "\n")
						if string.find(stripped, "measureStamp = ", 1, true) ~= nil then
							table.insert(others, path)
						end
					end
				end
			end
			walk(dir)
		end
		table.sort(others)
		--[[ TWO, AND ONE OF THEM IS THIS SAME RULE PINNED ELSEWHERE. `measure_reuse.spec`
			holds the renderer's own line as a SOURCE PIN (`"measureStamp = measureStamp,"`
			inside a `string.find`); it calls no solver. This file is the only one that
			hands a stamp to a solve, and it does so deliberately in the oracle above, to
			a tree the renderer built and never froze. Every other direct caller —
			`dump.fromSolve`, `tests/lib/fuzzers/layout`, the hand-built trees in
			`layout.spec` and `measure_memo.spec` — passes none, which is what keeps
			`record` from ever writing into a frozen table. ]]
		expect(others).toEqual({ "tests/measure_reuse.spec.luau", "tests/mount_serve.spec.luau" })
	end)

	it("a FROZEN tree solved WITH a stamp raises, and that is the boundary being drawn", function()
		--[[ READ OFF THE RUN, and it is the honest statement of what the new gate costs:
			a caller that both freezes its tree AND threads a stamp gets a hard error,
			where the old gate would have refused to write. No such caller exists — the
			case above is the census that says so — and the renderer never freezes a
			layout node. Pinned here so that a future caller that wants both finds the
			decision rather than the crash: the cheap fix would be `not
			table.isfrozen(node)` in `record`, one C call per measure return, and it was
			not spent on a caller nobody has. ]]
		local function deepFreeze(node: any): any
			for _, child in node.children or {} do
				deepFreeze(child)
			end
			return table.freeze(node)
		end
		local function tree(): any
			return deepFreeze({
				kind = "vstack",
				id = "root",
				gap = 4,
				children = {
					{ kind = "text", id = "t", text = "hello", textSize = 16 },
					{
						kind = "box",
						id = "b",
						width = { type = "fixed", px = 40 },
						height = { type = "fixed", px = 20 },
					},
				},
			})
		end
		local bare = pcall(function()
			return solver.solve(tree(), { w = 300, h = 200 }, { rootPolicy = "edgeToEdge" })
		end)
		local stamped = pcall(function()
			return solver.solve(tree(), { w = 300, h = 200 }, { rootPolicy = "edgeToEdge", measureStamp = "s" })
		end)
		expect(`unstamped={bare} stamped={stamped}`).toBe("unstamped=true stamped=false")
	end)
end)

describe("D5: the collector channel the publish table never named", function()
	it("a truncated collect HOLDS its surplus and the next collector takes it", function()
		--[[ ROW 12, DRIVEN ON `text_metrics` DIRECTLY. The budget is 1,024 words per
			collector; a solve that wants more used to DROP the surplus, and the only
			thing that ever asked about it again was the next solve re-measuring the tree
			— which a cold solve did for want of anything to serve from, and which D5
			stops doing. Held instead of dropped, the tail rides the next batch and the
			surface never needs a cold re-solve to find it. ]]
		--[[ ONE WORD PER `measure` CALL, AND A SIZE NOTHING ELSE IN THE SUITE USES. A
			multi-word string also asks for the SPACE, and an in-flight word rides the
			budget FREE (D3a) — so a space another spec left outstanding would put a
			1,025th entry in the first batch and make this pin a function of suite order.
			`resetMeasured` clears the store; it does not and must not clear the flight
			refcount, which is per-surface and process-wide. ]]
		text_metrics.resetMeasured()
		local SIZE = 41
		text_metrics.beginCollect()
		for i = 1, 1200 do
			text_metrics.measure(`d5w{i}`, "BuilderSans", SIZE, math.huge)
		end
		local first = text_metrics.endCollect()
		expect(`first={#first}`).toBe("first=1024")
		-- the surplus is held, not dropped: a collector that measures NOTHING drains it
		text_metrics.beginCollect()
		local tail = text_metrics.endCollect()
		expect(`tail={#tail}`).toBe("tail=176")
		-- ...and the two batches are the whole vocabulary, once each
		local seen: { [string]: boolean } = {}
		local dupes = 0
		for _, batch in { first, tail } do
			for _, request in batch do
				if seen[request.word] then
					dupes += 1
				end
				seen[request.word] = true
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		expect(`distinct={n} dupes={dupes}`).toBe("distinct=1200 dupes=0")
		text_metrics.resetMeasured()
	end)
end)
