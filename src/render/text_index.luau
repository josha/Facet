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
	-- the arrange-and-measure closure and the measure half, exactly as
	-- `dirty_closure.of` builds them for a refresh
	contains: { [string]: boolean },
	measures: { [string]: boolean },
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
	take: (narrow: boolean) -> Plan?,
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

	function index.take(narrow: boolean): Plan?
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
		if #entries == 0 then
			return nil
		end
		local contains, measures = dirty_closure.of(entries)
		return { contains = contains, measures = measures, n = #entries }
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
