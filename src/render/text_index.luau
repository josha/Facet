--!strict
--[[ ── WHICH NODES A LEARNED WORD ACTUALLY MOVES ────────────────────────────────

	Plan C, T18-A (ruling L-10, L-11, L-12; T17's second finding; FacetBench §C16).

	THE DEFECT THIS FILE EXISTS FOR, measured rather than reasoned. A SETTLED session
	— the state a shipped game is in from ~0.66 s onward — paid a fully COLD
	whole-tree re-solve for every new word it learned. Live (T17, arm C, Studio Play
	with the production adapter): `battle_hud L setState` **39.676 ms** and
	`addItem-damage` **76.971 ms** against 3.733 / 3.994 with the headless target in
	the same VM, with `lastMeasured == lastMeasureCalls == 14,2xx` on 5,109 nodes.
	`lastMeasured == lastMeasureCalls` is the signature: every measure was a MISS.
	Reproduced HEADLESS at 14,215 on the same workload, so the pin needs no Studio.

	THERE WERE TWO CAUSES AND THE OBVIOUS ONE WAS THE SMALLER, which is why this file
	is a dirty-set producer and not an epoch:

	  1. `text_metrics`' generation was ONE process-global counter folded into
	     `measureStamp`, so one learned word dropped the measure memo of every node of
	     every attached surface. That is the cause the investigation named.
	  2. AND THE SETTLE RE-SOLVE HAD NO DIRTY SET AT ALL. `premeasure_round.luau`'s
	     `solveAndApply` and the `textMeasureEpoch` geometry fact's settle callback
	     (`renderer.luau:2704-2719`) both call the renderer's solve BARE, and
	     `dirtyContains`/`measureContains` are set only inside `refresh`. So
	     `solveOpts.reuse == nil`, and with no reuse set the cross-solve store is
	     CLEARED, the leaf serve is dead at its first term (`solver.luau:1609-1611`)
	     and the container memo is dead at its second (`stack_measure.luau:131-133`).
	     The renderer says so in its own words: "a feedback re-solve is not the
	     refresh that built them and takes a full solve, exactly as the re-entrant
	     text-measurement solve does".

	Removing (1) alone is worth NOTHING — no memo is consulted on a path where the
	store was just cleared. Measured, arm B of T18-A's step-0 differential. The lever
	is (2), and (1) is its necessary companion: with the word generation still in the
	stamp, `measure_reuse.restamp` clears the store and `node.mStamp ==
	ctx.measureStamp` fails for every node whatever the dirty set says.

	THE FOUR LINKS, ALL OR NOTHING.
	  (i)   a per-surface `(font,size) -> mounted text paths` index, populated at
	        MEASURE time and cleared at unmount — this file;
	  (ii)  on a learned word, each indexed path pushed as `class == "measure"` dirt.
	        The class is load-bearing: `dirty_closure.of` builds its measure half from
	        `entry.class == "measure"` ALONE (`render/dirty_closure.luau`), and an
	        `arrange`-class push would produce an EMPTY measure closure and serve
	        stale everywhere;
	  (iii) the re-solve routed through a path that COMPUTES and PASSES the two
	        closures — `renderer.luau`'s `solveAndApply` takes the plan from here;
	  (iv)  the word generation out of `measureStamp` (`render/measure_stamp`).

	WHY AT MEASURE TIME AND NOT AT MOUNT. The `(font,size)` a node measures under is
	not known at mount: it is resolved inside `solver`'s text branch from the theme
	snapshot, the typography role, `measureScale`, `prefOffset` and — for
	`textSize = "fit"` — the box itself. `render/layout_node`'s `textOf` cannot answer
	it either, and a node SERVED from the node store never re-runs `textOf` at all, so
	an index rebuilt per build would lose every entry under a served subtree. The
	entries here persist across served solves and are refreshed only when a node is
	actually re-measured under a different key, which is exactly right: a served node
	measured under the key it is still filed under.

	WHY PER SURFACE. Paths are per-surface — two attached surfaces have identical
	`/Root/...` strings — and the dirty push has to reach THAT controller's tree. So
	each `renderer.attach` owns one index and they are held in a module-level registry
	that `learned()` broadcasts to. That registry is what preserves the cross-surface
	reach the process-global epoch used to give for free: a busy screen teaching the
	measurer a width a quiet one draws still corrects the quiet one, because the quiet
	one's own index names its own paths. Once the word generation leaves the stamp,
	the `textMeasureEpoch` env fact alone no longer suffices — that surface's solve
	would legitimately serve — so this broadcast is not an optimisation, it is the
	correctness half.

	A STALE ENTRY IS COST; A MISSING ONE IS STALENESS. An entry for a path that has
	been unmounted pushes dirt for a node the tree no longer has, which is inert. A
	MISSING entry means a live node is never re-measured and keeps the estimator's
	box. The failure direction is therefore safe, and `forget` is still called from
	the renderer's one per-path removal sweep so a `ForEach` churning rows does not
	retain paths for the session.

	WHAT THE RENDERER DOES WITH `take`, since the argument does not fit in that file.
	The plan is spent in `renderer.attach`'s solve, ABOVE the layout build, and it does
	three things there:

	  * it fills `dirtyContains`/`measureContains`, which is the reuse set the solver
	    reads — link (iii);
	  * it does NOT touch `nodeDirty`. That was tried and MEASURED, and it is the one
	    place where the conservative direction was the wrong one: marking the push into
	    the layout-node store's dirty set forces a REBUILD of every pushed node and
	    every ancestor, and on the wide key (`battle_hud`'s 1,000 facing labels at size
	    10) that is ~2,000 rebuilds the parent SHA's cold solve never paid — its
	    `nodeDirty` was empty and every node was served. Live, arm C: the
	    `updateItem-facing` settle class read **62.986 ms** with the marks against
	    39.7 ms for the whole-tree cold solve they were meant to be cheaper than. What
	    the marks were protecting is `commit_walks`' prune, and that prune does not read
	    the dirty set alone — it asks `entryVerdict(child)` (settled / moved), so a node
	    whose rect moved is descended whether or not anything marked it. The residue is
	    a published VERDICT that changes without moving a rect; no fixture in the suite
	    produces one, deleting the marks reddened nothing, and the measurement is what
	    decided it.
	  * it CLEARS the pair afterwards. `refresh` and `resolveForFeedback` each clear it
	    in their own tails; a settle solve has no tail, so a push left standing would be
	    spent again by the next bare solve as a stale set. Two `textMeasureEpoch` writes
	    in a row is what found that.

	THE REFUSALS, and every one of them is a SUPERSET of the push rather than a
	weakening of it. `take(false)` DROPS the mark, because the solve that follows covers
	everything the push could have named:

	  * a MOVED STAMP — a viewport, inset, scale, theme or calibration change — has
	    already dropped the whole store, and nothing narrower than everything is honest
	    there. The push only ever names TEXT nodes, so spending it would leave every
	    other node at the rect the old viewport gave it.
	  * no `lastResult`, or incremental layout off, means there is nothing to reuse.
	  * ...and the push that names more than `cap` paths is NOT one of these: it comes
	    back as `full`, and the caller drops whatever closure it was holding. See THE
	    BUDGET at `take` for the route where returning `nil` there was a wrong box.

	A CLOSURE ALREADY SET IS A UNION, NOT A REFUSAL, and this is the one the live drive
	corrected. On the SHIPPED route the engine's settled branch answers INLINE, from
	inside the solve that asked, so `premeasure_round`'s `done` runs while `refresh`'s
	own closure is still standing and the re-solve is the re-entrant one. Refusing there
	looked safe — the refresh's dirt contains the node whose text just changed — but the
	(font,size)'s OTHER users are not in it, and they are exactly the nodes still
	showing the estimator's box. The push is therefore unioned into the caller's two
	sets: strictly wider than what the caller asked for, never narrower, and the caller
	still owns the tables (they are cleared by its own tail, not by this one).

	AN EMPTY PUSH IS A PLAN, NOT A REFUSAL, and the distinction is worth 39.9 ms. A
	width learned at a key no mounted node measured under names nobody; returning `nil`
	there would send the caller down the bare route and buy the full cold solve this
	file exists to remove. Measured while it did exactly that on `battle_hud L`: 39.865
	ms and 14,215 measures, the parent SHA's number to the digit, on the one case that
	should be free. With an empty closure it is **0.046 ms and 0 measures**.

	`textSize = "fit"` IS FILED CONSERVATIVELY, and this is the one place the key is
	not enough. A fit node's ladder measures its string at SEVERAL sizes inside the
	band (`layout/text_fit`) before choosing one, so a width learned at a size it
	merely PROBED can change which rung it lands on — while the key recorded here is
	the size it chose. Those nodes go into `always`, which joins every push. They are
	rare (an opt-in prop), and being wrong about them would be a wrong box on screen.
]]

local dirty_closure = require("./dirty_closure")
local text_metrics = require("../layout/text_metrics")

local text_index = {}

export type Plan = {
	--[[ TRUE when the push was over budget and the caller must take the WHOLE-TREE
		solve instead. `contains`/`measures` are nil there, and the caller has to DROP
		any closure it was already holding — see THE BUDGET at `take` for why a
		refusal that merely returns `nil` is not a superset on every route. ]]
	full: boolean,
	-- the arrange-and-measure closure and the measure half, exactly as
	-- `dirty_closure.of` builds them for a refresh. Nil when `full`.
	contains: { [string]: boolean }?,
	measures: { [string]: boolean }?,
	-- how many PATHS were pushed (not the closure size): the counter
	-- `stats.lastTextDirtyPaths` publishes, and the number this whole task is about
	n: number,
}

export type Index = {
	-- file `path` under the (font,size) it was just measured with. Called from the
	-- solver's text branch, on every measure of a text node, so the unchanged case
	-- is two hash reads and two comparisons and nothing else
	record: (path: string, font: string, size: number, always: boolean) -> (),
	-- a path left the tree (the renderer's per-path removal sweep)
	forget: (path: string) -> (),
	-- take the pending push, or drop it. `narrow` false means the caller is about to
	-- take a FULL solve anyway, which covers everything a push would have named
	take: (narrow: boolean, cap: number) -> Plan?,
	--[[ ...AND SPEND IT ON THE CALLER'S TWO CLOSURES, which is `take` plus the whole
		own/union/full decision in one call. Returns `(contains, measures, owns, pushed)`:
		the two sets the solve should use, whether THIS call created them (so the caller
		knows to clear them — a settle solve has no tail of its own, and a caller's
		closure belongs to the caller), and how many paths were pushed.

		IT LIVES HERE RATHER THAN AT THE CALL SITE for a reason this repository states
		in its own ledger: `render/renderer.luau` is the capped file, 56 characters under
		the campaign's STOP when this round opened, and an argument this long cannot be
		paid for there. The decision is three lines of code and a page of why. ]]
	apply: (
		contains: { [string]: boolean }?,
		measures: { [string]: boolean }?,
		narrow: boolean,
		cap: number
	) -> ({ [string]: boolean }?, { [string]: boolean }?, boolean, number),
	-- INTERNAL, and named in the type only so the registry broadcast above can call
	-- it without an `any` cast: mark one `metricKey` as changed. Nothing outside this
	-- module calls it — `text_index.learned` is the seam.
	mark: (key: string) -> (),
	-- is anything waiting? (read before a solve decides how to spend it)
	pending: () -> boolean,
	-- leave the registry: a surface that detaches must stop receiving broadcasts
	dispose: () -> (),
}

-- every attached surface's index. A LIST rather than a set so the broadcast order is
-- the attach order, which makes a two-surface spec deterministic.
local live: { Index } = {}

--[[ A word's exact width MOVED at this (font,size). Every live surface marks its own
	paths — see WHY PER SURFACE above.

	SUBSCRIBED AT THE SEAM, NOT AT THE CALLER. `text_metrics.setMeasured` is the one
	function that can change an exact width, and until this round every writer of it
	invalidated every surface's geometry for free through the process-global epoch.
	Registering here keeps that property for every writer — the premeasurement round,
	a Studio tool reloading a design system, a spec driving the store — rather than
	narrowing it to the one caller that happened to be in the Files list.

	IT RUNS BEFORE THE `textMeasureEpoch` WRITE that makes those surfaces solve
	(`render/premeasure_round`'s `learned` branch calls `setMeasured` first, then
	publishes), so the mark is already standing when their solves ask for it. ]]
text_metrics.onWordChanged(function(font: string, size: number)
	if #live == 0 then
		return
	end
	local key = text_metrics.metricKey(font, size)
	for _, index in live do
		index.mark(key)
	end
end)

-- how many surfaces are registered. The leak instrument: `attach`/`dispose` pairs
-- have to balance, and a spec that presents and dismisses a hundred screens can say
-- so in one number.
function text_index.liveCount(): number
	return #live
end

function text_index.new(): Index
	-- `path -> the (font,size) it is currently filed under`, split into two maps so
	-- the unchanged case allocates nothing and builds no key string
	local pathFont: { [string]: string } = {}
	local pathSize: { [string]: number } = {}
	-- `metricKey -> { path: true }`
	local byKey: { [string]: { [string]: boolean } } = {}
	-- the conservative set: `textSize = "fit"` nodes, which join every push
	local always: { [string]: boolean } = {}
	-- keys marked since the last `take`. Keys, not paths: a delivery that learns
	-- forty damage numbers at one size costs one entry here, and the paths are
	-- expanded once, at the solve that spends them.
	local marked: { [string]: boolean } = {}
	local anyMarked = false

	local index: any = {}

	local function detach(path: string)
		local font = pathFont[path]
		if font == nil then
			return
		end
		local bucket = byKey[text_metrics.metricKey(font, pathSize[path])]
		if bucket ~= nil then
			bucket[path] = nil
		end
	end

	function index.record(path: string, font: string, size: number, alwaysDirty: boolean)
		if pathFont[path] == font and pathSize[path] == size and always[path] == (alwaysDirty or nil) then
			return
		end
		detach(path)
		pathFont[path] = font
		pathSize[path] = size
		always[path] = if alwaysDirty then true else nil
		local key = text_metrics.metricKey(font, size)
		local bucket = byKey[key]
		if bucket == nil then
			bucket = {}
			byKey[key] = bucket
		end
		bucket[path] = true
	end

	function index.forget(path: string)
		detach(path)
		pathFont[path] = nil
		pathSize[path] = nil
		always[path] = nil
	end

	function index.mark(key: string)
		marked[key] = true
		anyMarked = true
	end

	function index.pending(): boolean
		return anyMarked
	end

	function index.take(narrow: boolean, cap: number): Plan?
		if not anyMarked then
			return nil
		end
		--[[ DROPPED, NOT KEPT, when the caller is not narrowing. Every route into this
			function is a solve that is about to happen: if it is a FULL one it
			re-measures everything a push could have named, and holding the mark would
			buy a second solve for work already done; if it is an incremental one the
			caller refused to narrow because something WIDER is already in play (a
			moved stamp drops the whole store; a refresh's own closure is the dirt this
			frame, and the settle write that produced this mark is inside it). Both are
			supersets on the measure axis, which is the only axis this push carries. ]]
		local keys = marked
		marked = {}
		anyMarked = false
		if not narrow then
			return nil
		end
		--[[ ONE ENTRY PER PATH, `class = "measure"`. The class is the whole contract
			with `dirty_closure.of`: it fills the measure half from measure entries
			ALONE, and an `arrange` push here would hand the solver an empty measure
			closure — every container above the corrected label serving its stale
			slate while the arrange pass dutifully re-placed it at the old size. ]]
		local entries: { { path: string, class: string } } = {}
		local pushed: { [string]: boolean } = {}
		local function push(path: string)
			if not pushed[path] then
				pushed[path] = true
				table.insert(entries, { path = path, class = "measure" })
			end
		end
		for key in keys do
			local bucket = byKey[key]
			if bucket ~= nil then
				for path in bucket do
					push(path)
				end
			end
		end
		-- ...AND THE CONSERVATIVE SET, on every push: a `textSize = "fit"` node
		-- measured its string at sizes it merely PROBED (see the header)
		for path in always do
			push(path)
		end
		--[[ AN EMPTY PUSH IS A PLAN, NOT A REFUSAL, and this is the difference between
			"the narrowing works" and "the narrowing works when it has something to
			say". A width learned at a (font,size) NO MOUNTED NODE MEASURED UNDER names
			nobody — and returning `nil` here would send the caller down the bare route,
			where `dirtyContains == nil` buys the full cold solve this whole task exists
			to remove. Measured on `battle_hud L` while this returned `nil`: a word at
			an unused key still cost 39.9 ms and 14,215 measures, the parent SHA's
			number exactly, on the one case that should be free.

			An EMPTY closure is the honest answer: nothing is dirty, so the solve
			replays every subtree and re-publishes every channel from the previous
			result. The env fact still bumps, so a consumer memo that read
			`Facet.text.measure` still re-derives. ]]
		--[[ ...AND A BUDGET, MEASURED RATHER THAN ASSUMED. A push that names a large
			FRACTION of the tree is not a narrowing: its ancestor closure reaches the
			root, every container on the way down refuses its memo, and the solve ends
			up doing the whole tree's work PLUS the closure's. Live, arm C,
			`battle_hud L`'s `updateItem-facing` — 1,000 labels sharing one
			(font,size) — read **55.709 ms** with the push against **~39.7 ms** for the
			whole-tree cold solve it replaced, at 14,174 measure CALLS against the cold
			solve's 14,215.

			THE CUTOFF IS NOW SWEPT RATHER THAN BRACKETED (fix round 1, FacetBench §C16).
			A scene that holds the tree still — 3,002 nodes, always — and moves only how
			many text nodes share the changed key, push arm against forced-full arm, two
			runs of 5 and 7 reps:

			    users   % of tree   PUSH ms        FULL ms        verdict
			       50        1.7    7.9 /  8.2    21.0 / 22.6    push wins ~2.7x
			      200        6.7   10.6 / 14.6    20.8 / 20.9    push wins 1.4-2.0x
			      400       13.3   13.5 / 17.5    17.2 / 21.7    a coin flip
			      638       21.3   19.0 / 23.3    18.5 / 20.5    full wins
			    1,000       33.3   30.1 / 31.9    16.9 / 17.2    full wins ~1.9x

			The crossover is a BAND between roughly 7 % and 13 % of the tree, not a
			point, and `lastLayoutNodes // 8` is 12.5 % — the top of that band, where a
			refusal costs at worst a wash and never the 1.9x the far end costs. That is
			why the cap stayed where it was: the sweep vindicated the fraction rather
			than replacing it. `battle_hud`'s own wide key cannot answer this question at
			all — its 1,000 labels are always ~20 % of its 5,106 nodes, so scaling the
			workload scales both together and the ratio never moves.

			IT READS THE PREVIOUS SOLVE'S `lastLayoutNodes`, which is 0 on a first solve
			and therefore the `max(64, ...)` floor. Benign by construction: a surface
			with no previous solve has `lastResult == nil`, so `narrow` is false and no
			push is built for the cap to judge.

			▲ AND OVER THE CAP THE ANSWER IS `full`, NOT `nil`, WHICH IS A CORRECTION.
			This returned `nil` and both this file and T18-A's report claimed the
			fallback was "the full solve the parent SHA took". That is true on the BARE
			route, where `dirtyContains` is already nil. It was FALSE on the INLINE
			route — the one that ships, where a caller closure is standing — and there
			the mark was consumed, the push discarded, and the solve stayed NARROW:
			measured `cap=76 pushed=0 measured=4 arranged=5 nodes=614`, with the key's
			other users left on the estimator's box and nothing to repair them later.
			A word is a TOKEN, not a label — `text_metrics.measure` sums per word — so
			two labels sharing no string still share words, and a correction to one of
			them moves every node that draws it while only the written node is in the
			refresh's dirt. `full` makes the caller drop its closure, which is what the
			claim always said. `tests/text_settle_closure.spec.luau`'s over-budget
			inline case is the witness, and it reddens on both halves.

			The classes this task exists for are nowhere near the cap: 4 paths of 5,106
			nodes on `setState` and 45 on `addItem-damage`, against a cap of 638. ]]
		if #entries > cap then
			return { full = true, contains = nil, measures = nil, n = 0 }
		end
		local contains, measures = dirty_closure.of(entries)
		return { full = false, contains = contains, measures = measures, n = #entries }
	end

	--[[ THE THREE OUTCOMES, and every one of them is a SUPERSET of the push rather than
		a weakening of it.

		  * NO CLOSURE STANDING (a bare settle solve — `premeasure_round`'s own
		    `solveAndApply`, or the `textMeasureEpoch` geometry fact's settle callback):
		    the push IS the closure, and the caller is told it owns it.
		  * A CLOSURE STANDING (a `refresh` whose INLINE delivery produced the mark —
		    the route that ships): the push is UNIONED in. The delivery's users are not
		    all inside the dirt that produced them; a word is a TOKEN, not a label, so
		    two rows sharing no string still share words.
		  * OVER BUDGET: the caller's closure is DROPPED and the solve is the whole-tree
		    one. See THE BUDGET at `take` for the wrong box that came of returning `nil`
		    here instead. ]]
	function index.apply(
		contains: { [string]: boolean }?,
		measures: { [string]: boolean }?,
		narrow: boolean,
		cap: number
	): ({ [string]: boolean }?, { [string]: boolean }?, boolean, number)
		local plan = index.take(narrow, cap)
		if plan == nil then
			return contains, measures, false, 0
		end
		if plan.full then
			return nil, nil, false, 0
		end
		local pushC = plan.contains :: { [string]: boolean }
		local pushM = plan.measures :: { [string]: boolean }
		if contains == nil then
			return pushC, pushM, true, plan.n
		end
		local intoM = (measures or contains) :: { [string]: boolean }
		for path in pushM do
			intoM[path] = true
		end
		for path in pushC do
			(contains :: { [string]: boolean })[path] = true
		end
		return contains, measures, false, plan.n
	end

	table.insert(live, index)

	function index.dispose()
		for i, other in live do
			if other == index then
				table.remove(live, i)
				break
			end
		end
		table.clear(byKey)
		table.clear(pathFont)
		table.clear(pathSize)
		table.clear(always)
		marked = {}
		anyMarked = false
	end

	return index :: Index
end

return text_index
