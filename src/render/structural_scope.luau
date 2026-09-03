--!strict
--[[ ── BOUNDARY-ROOTED PARTIAL SOLVES FOR STRUCTURAL CHANGES (perf campaign P5) ──

	P1 gave `measure` a cross-solve slate, P2 made the arrange skip O(touched), P3
	stopped rebuilding the `solver.Node` tree and P4 stopped re-walking the commit.
	Every one of those four is armed by ONE thing: the renderer handing the solver a
	`reuse` set. And `refresh` refused to build one the moment ANY dirty entry was
	`structure`:

		if needsStructure then
			dirtyContains = nil     -- a full solve, a full tree build, a full commit

	So an add, a remove or a reorder paid the pre-campaign price in full. MEASURED
	(FacetBench, headless Lune, 2026-09-01, `killfeed_nameplates` L, 904 mounted
	nodes, at the HEAD that shipped P1-P4): an `addItem` step cost **8.05 ms** —
	`measure` 2.06 ms for **2 209 measures**, `arrange` 3.54 ms, commit 1.83 ms — while
	the same tree's UPDATE steps had already fallen to 0.3 ms. On `war_room_inventory`
	L (7 500 nodes) a `reorder` step's p95 was 85 ms.

	THE FIX IS NOT A SECOND SOLVER. Stage 2 v1 re-solved a boundary subtree as its own
	ROOT and could not be made correct (`renderer.luau`'s own note: a sub-solve gets a
	fresh `ctx`, a zeroed inset stack and a screen-root policy applied to a node that
	is not a screen). Stage 2 v2 replaced it with ONE solve from the root that SKIPS
	what it can prove has not moved, and that is the machinery a structural change
	re-roots into: **the re-root is expressed as the reuse set.** A set closed over the
	ancestors of every structural path makes the solver walk exactly the chain from the
	root down to the changed region, and skip every sibling subtree whose rect it lands
	on again. Nothing is re-based, re-parented or given a second context.

	THAT IS WHY THE BOUNDARY IS A QUALIFICATION AND NOT A SET-SHAPING DEVICE, and it
	is the one honest correction this module owes its brief. Whatever enclosing
	boundary you re-root at, the set the solver needs is the SAME set — the ancestor
	closure — because the arrange skip only descends through nodes that are IN it.
	Rooting "at" a boundary and rooting at the solve root produce identical work.
	What the boundary decides is whether a partial solve is ALLOWED AT ALL:

	  * a node that ABSORBS (`fixed` or `containerRelative` on both axes — the
	    offer-free half of the solver's `axisAbsorbs`, so it is true whatever it is
	    offered) cannot change size when its content changes, so a structural change
	    under it is CONTAINED by construction;
	  * with no absorbing ancestor the boundary is THE SOLVE ROOT, whose offer is the
	    content rect.

	AND EITHER WAY THE SOLVE-WIDE INPUTS STILL HAVE TO HOLD — the refusal on a moved
	measure stamp is UNCONDITIONAL, and it was `atRoot`-only until the review corrected
	it. Absorbing proves a node's own SIZE cannot change; it proves nothing about the
	theme snapshot, the text scale or the preferred-text offset, and those are what the
	entries a partial solve hands forward were computed under. A moved stamp under a
	non-root boundary would have let every skipped sibling keep `textFacts`, `compact`
	and `composition` verdicts measured under the OLD ones — the class the measure
	memo's own axis 3 exists to refuse. `plan.atRoot` remains on the record because it
	is what the boundary walk decided and what `lastStructuralBoundary` reports; it no
	longer gates the refusal.

	AND THE ROUTE THAT PAIRS THEM HAS SINCE BEEN FOUND, so the refusal is no longer
	free and no longer theoretical (RED-TEAM 2026-09-02). What this paragraph used to
	say is that no route through the public API pairs a moved stamp with a structural
	refresh, because every geometry and theme write solves inside its own settle
	phase. `text_metrics.calibrate` is the exception it could not construct: a live
	client seam that moves every glyph width with NO env write, no dirty node and no
	solve of its own, so the very next structural `refresh` solves against an offer
	that moved under it. `tests/structural_scope.spec.luau` drives it.

	AND THE STAMP HAS TO BE TAKEN WHETHER OR NOT THE MEASURE CACHE IS ON, which is
	where the campaign's own defect was (same review, HIGH 1). `measure_reuse.restamp`
	both ANSWERS "did the solve-wide inputs move" and re-stamps the store, and the call
	sat inside `if measureReuseEnabled` — so with `measureReuse = false` the answer was
	a constant `false` and this refusal could not fire at all. That flag is the CONTROL
	ARM of five differential cases: the switch that exists to make a divergence
	attributable was manufacturing one, and the calibration route above is what made it
	visible (a sibling label outside the boundary kept its pre-calibration 437x39
	against the full-solve oracle's 363x20). The call is unconditional now; only
	`solveOpts.measures` is gated, which is the switch itself. With the cache off the
	re-stamp clears a store nobody reads.

	THE PLAN IS REFRESH-SCOPED, AND BOTH HALVES OF IT ARE. `refresh` sets the set and
	the plan together and clears them together at its tail, because a solve that is not
	that refresh — a feedback re-solve, a re-entrant text-measurement solve — must take
	a FULL one. Clearing only `dirtyContains` left the plan live, and a solve reading a
	plan built for another one stamped `lastStructuralBoundary` on a solve that was not
	partial at all (the diagnostic this round's own engagement evidence reads) and paid
	an O(N) `builtIds` collect and an O(N) `widen` on exactly the frames P5 exists to
	make cheap. `renderer.resolveForFeedback` is the site.

	...AND THE TAIL THAT CLEARS THEM RUNS EVEN WHEN THE SOLVE THROWS (RED-TEAM
	2026-09-02). An adapter that raises mid-commit used to leave both live, and the
	solve that spends them is not exotic: `refresh`'s NON-structural arm computes a
	fresh `dirtyContains` and never touches `structuralPlan`, so the next one-leaf
	frame took a boundary-rooted solve claiming a boundary nothing had dirtied
	(measured pre-fix: `partial=2 boundary=/Scroll` on a frame whose only dirt was one
	row's bound value). What masked it is worth recording because it is a coincidence
	rather than a guarantee: every `GEOMETRY_KEYS` fact also moves the measure stamp —
	the viewport, the three inset facts, the display size through
	`typographyPaintScale`, both text scales and the theme snapshot — so a geometry
	write refuses the stale plan for its own reasons, and only a plain refresh gets
	through. The renderer pcalls, clears the pair and re-raises, which is the shape
	`resolveForFeedback` already had.

	THE COUNTER IS WRITTEN FROM THE SOLVE, NOT FROM THE COMMIT (same review, finding
	10). `stats.structuralPartialSolves` used to be incremented before `solver.solve`
	was called — alone among the stats of that block, every one of which is read off
	the result — so a solve that threw was counted as one that happened. It is counted
	beside `partialSolves` now. A commit that throws AFTER the solve still counts, and
	that is deliberate: the solve happened and the work was done, and what a torn
	commit owes the surface is the clean re-solve above rather than a rewritten count.

	CONSERVATIVE IN THE ONLY DIRECTION THAT MATTERS: every refusal costs time and
	nothing else, and the fallback is the pre-P5 full solve, unchanged.

	── WHAT A STRUCTURAL REUSE SET MUST INVALIDATE, AND WHY THE OTHER THREE STORES
	   ALREADY DO ─────────────────────────────────────────────────────────────────

	P2 (the arrange skip) is safe by construction. A node is skipped only when it is
	absent from the set AND lands on the rect it already had, and the closure puts
	every ancestor of every structural path IN the set — so a subtree whose SHAPE
	moved is never a skip candidate. Paths are `/a/b/c` and layout ids ARE mounted
	paths, so the closure is a string-prefix closure and a nested region's row is
	covered by its own list's prefix.

	P3 (the node store) is safe by construction and for a stronger reason: it is keyed
	by the mounted node TABLE. A `ForEach` row that died and came back is a fresh
	`mountNode`, a fresh table and a miss; a row that never left is the same table and
	a hit — and a hit serves the whole subtree, so a served node's descendants are
	unchanged too. That is measured rather than argued: `toLayoutNode` already cost
	0.04 ms on the 8 ms structural step above, because P3 patches on structure dirt.

	P4 (the commit prune) inherits ONE premise from this module and it is stated at
	`rect_pass.apply`: its whole-map sweep is skipped on a pruned commit because
	"every key in the map belongs to a live path". That was free while a structural
	change forced a full solve into a FRESH map. It is not free now — P2 writes into
	the previous solve's map in place — so **the renderer deletes a departed path's
	rect entry in the removal sweep**, beside the eight other per-path records that
	sweep already owns. The premise is restored where it is spent, not weakened.

	P1 (the measure slate) is the one that needs a new answer, and this is the
	invalidation boundary the round had to define precisely. The slate is keyed by
	`node.id` — the mounted PATH — and `measure_reuse`'s own axis 1 says why a
	structural change used to wipe it: *a structural change can move different content
	under the same path*. That is real and it survives the removal sweep, because the
	path stays ALIVE across the refresh: a `When` toggled off and on inside one flush,
	an `ErrorBoundary` that trips and re-mounts its fallback with a different error, a
	`ForEach` key removed and re-added by two writes of the same flush. The sweep never
	sees those, so a path-keyed slate would answer the new content with the old size.

	THE PRECISE ANSWER IS P3'S OWN OUTPUT. A layout node is served from the node store
	only when the mounted table is unchanged AND the path is absent from `nodeDirty`
	(the ancestor-closed, EVERY-class dirty set). So the nodes the build CONSTRUCTED
	are exactly the nodes whose measure inputs may have moved — identity, props or
	both — and every other node's subtree is provably the tree it was. `layout_node`
	collects those ids on a structural build and `widen` below puts them in the set,
	which is what makes `adopt` hand each of them a fresh slate. Bounded by the region,
	not by the store: a 600-row list that gained one row invalidates the list's own
	chain, not the 900 nodes beside it.

	AND IF P3 IS OFF, THE ANSWER DEGRADES TO THE pre-P5 ONE. A count-only node store
	constructs every node, so there is no smaller set to name: the list is the whole
	tree, the set is everything, nothing is skipped and every slate is dropped — which
	is exactly what a structural change did before this round. Slower, never wrong, and
	it keeps the differential oracle's arms independent in the direction that matters
	(P5 on with P3 off is still correct).

	WHAT `work.skipped` MEANS NOW, because P5 moved the ground under it. `solve`
	derives it BY SUBTRACTION — `previous.arranged + previous.skipped - arranged` — and
	that previous total is the node count of the tree the last solve walked. It was
	sound because a full solve reset the chain every time the count could move, and a
	structural change was always a full solve. It is not sound any more: left alone,
	the total would be pinned to the last FULL solve's forever and drift by every row a
	list had gained or lost since. So `layout_node.build` counts the live tree on the
	way past (`store.nodes` — constructed nodes one at a time, served subtrees by the
	size their entry recorded, which is O(1) per served node rather than a walk) and the
	renderer restores `arranged + skipped == N` from the TREE instead of from induction.

	ONE THING IS DELIBERATELY NOT REPAIRED, and the honest statement of it is stronger
	than "off by a delta" (review, I-6). The solver's diagnostic-replay gate reads
	`ctx.skipped` INSIDE the solve, before the renderer can correct it, and that gate is
	all-or-nothing: `if ctx.skipped > 0`. So on a structural frame whose NODE DELTA is
	greater than or equal to the number of nodes it genuinely skipped, the subtraction
	floors at zero and the frame replays NO findings at all — not some of them, all of
	them. What that costs is bounded on three sides and is worth each one: it is
	DIAGNOSTICS ONLY (no geometry, no paint, no verdict a node publishes); it lasts ONE
	FRAME, because the next solve's own walk re-files whatever is still true and the
	renderer's repair re-bases the chain either way; and it cannot accumulate. The
	shape that reaches it is a frame that adds a lot and skips a little — which is a
	frame that had almost nothing to replay in the first place.

	DIAGNOSTICS ARE PER-PATH TOO. `solve` replays the previous solve's findings for
	every node this solve did not walk, so a departed node's finding would be replayed
	forever once the map stops being rebuilt. `sweepDiagnostics` drops the findings
	whose FILER has left, using the same rect map the sweep has just corrected — the
	filer, not the named node, because `inertPlacement` is filed by the parent about
	the child (the solver's own replay gate makes the same distinction).

	AND THE FILER IS THE RIGHT KEY EVEN WHEN THE NAMED NODE IS THE ONE THAT LEFT. An
	`inertPlacement` finding names a departed child and is filed by a parent that
	stays — so this sweep keeps it, and it is corrected one line later by the solver
	instead: the parent is IN the set (it is an ancestor of the structural path), so
	it is walked, so its findings are filed fresh without the child that left. What
	only this sweep can correct is a finding whose filer is the departed node itself
	(`aspect on both axes` is the one `measureUncached` files that way), because
	nothing walks that node ever again. `tests/structural_scope.spec` drives the
	second, and the first attempt used the first — which proved nothing, and said so.
]]

local paths = require("../paths")
local isPrefix = paths.isPrefix

local structural_scope = {}

--[[ THE OFFER-FREE HALF OF `axisAbsorbs` (`layout/measure_facts.luau`). That
	function's `fixed` and `containerRelative` branches return true unconditionally —
	neither reads the content and neither reads the offer — while `percent`, `fill`,
	`minMax` and `aspect` all answer against a limit this module does not have and
	cannot get without the solve it is deciding about. Taking only the two
	unconditional branches is therefore not an approximation of the solver's predicate:
	it is the subset of it that is decidable here, and a node the solver would have
	called absorbing that this refuses simply gets a boundary further up. ]]
local function absorbs(d: any): boolean
	if d == nil then
		return false
	end
	local t = d.type
	return t == "fixed" or t == "containerRelative"
end

structural_scope.absorbs = absorbs

-- `/a/b/c` -> `/a/b`; `""` (and a root-level segment) -> nil
local function parentPath(path: string): string?
	local cut = string.match(path, "^(.*)/[^/]*$")
	if cut == nil or cut == "" then
		return nil
	end
	return cut
end

--[[ The deepest path that is an ancestor-or-self of both, on SEGMENT boundaries.
	Character-wise prefixing is not enough and the framework already has the scar:
	`/List/[k1]` is not inside `/List/[k10]` and the sweep that once thought so
	retired live rows (verifier P2-2). ]]
local function commonAncestor(a: string, b: string): string
	if a == b then
		return a
	end
	local out = ""
	local i = 1
	while true do
		local nextA = string.find(a, "/", i + 1, true)
		local nextB = string.find(b, "/", i + 1, true)
		local endA = nextA or (#a + 1)
		local endB = nextB or (#b + 1)
		if endA ~= endB or string.sub(a, i, endA - 1) ~= string.sub(b, i, endB - 1) then
			return out
		end
		out = string.sub(a, 1, endA - 1)
		if nextA == nil or nextB == nil then
			return out
		end
		i = endA
	end
end

structural_scope.commonAncestor = commonAncestor

export type Plan = {
	-- the node the re-solve is rooted at: the nearest enclosing absorbing ancestor
	-- of every structural path, or the solve root when none absorbs
	boundary: string,
	-- true when `boundary` IS the solve root — reported, not a gate. The caller's
	-- stamp refusal is unconditional (see the header); this says which of the two
	-- shapes the walk found, which is the claim `lastStructuralBoundary` publishes.
	atRoot: boolean,
	-- the ancestor-closed set the solver skips the complement of
	contains: { [string]: boolean },
}

--[[ Build the reuse set for a refresh that carries structural dirt, and name the
	boundary it is rooted at. `nil` means REFUSE — take the full solve.

	`dirty` is the drained queue; `rootPath` the mounted root's path; `parentOf` maps
	a path to its parent mounted NODE (the renderer's `parentNodeOf`, rebuilt by the
	same structural sync that produced this dirt); `layoutOf` maps a mounted node to
	the `solver.Node` the last build made for it, or nil when it has none — which is
	the honest answer for `ForEach`/`When`/`ErrorBoundary`, since those splice away and
	own no box to absorb anything.

	THE CLOSURE IS OVER `measure`, `arrange` AND `structure` — the same three classes
	the non-structural branch uses, plus the one it was missing. **It is HALF the set,
	and `widen` below is the other half.** ]]
function structural_scope.plan(
	dirty: { any },
	rootPath: string,
	parentOf: (string) -> any,
	layoutOf: (any) -> any
): Plan?
	local contains: { [string]: boolean } = {}
	local lca: string? = nil
	local sawStructure = false
	for _, entry in dirty do
		local class = entry.class
		if class ~= "measure" and class ~= "arrange" and class ~= "structure" then
			continue
		end
		local path = entry.path
		if path == nil then
			-- a dirty entry with no path names no subtree, so nothing can be proved
			-- about what it did not touch
			return nil
		end
		if class == "structure" then
			sawStructure = true
			lca = if lca == nil then path else commonAncestor(lca, path)
		end
		if not contains[path] then
			contains[path] = true
			local at = path
			while true do
				local cut = parentPath(at)
				if cut == nil or contains[cut] then
					break
				end
				contains[cut] = true
				at = cut
			end
		end
	end
	if not sawStructure or lca == nil then
		return nil
	end
	--[[ THE BOUNDARY WALK, over STRICT ancestors of the common ancestor, and it is
		O(depth): `parentOf` is a map, not a search, and nothing here reaches a sibling.

		STRICT, not inclusive, and that is a conservatism rather than a difference of
		opinion with `solver.boundaryReport` (which walks the same chain inclusively,
		because a fixed-size node absorbs its own content's change). The common
		ancestor of a structural change is almost always the REGION itself — a
		`ForEach`, a `When` — which owns no box and absorbs nothing, and the renderer's
		one O(1) route to a node is its parent link. Testing the node itself would cost
		a scan of its parent's children, over a list whose length is the very number
		this round exists to stop paying. A boundary one hop further up costs nothing:
		the reuse set is identical either way (see the header). ]]
	local at: string? = lca :: string
	local boundary: string? = nil
	while at ~= nil and at ~= rootPath do
		local node = parentOf(at :: string)
		if node == nil then
			-- a structural path with no parent link: the region was itself unmounted
			-- by this same flush, so `parentNodeOf` no longer reaches it and nothing
			-- above it is provable. Refuse.
			return nil
		end
		local layout = layoutOf(node)
		if layout ~= nil and absorbs(layout.width) and absorbs(layout.height) then
			boundary = node.path
			break
		end
		at = node.path
	end
	-- the walk ran out of absorbing ancestors: the boundary is the solve root, whose
	-- offer is the content rect. The caller refuses on a moved stamp either way.
	boundary = boundary or rootPath
	return { boundary = boundary :: string, atRoot = boundary == rootPath, contains = contains }
end

--[[ ── THE OTHER HALF OF THE SET, AND THE ROUND'S ONE REAL CORRECTION ─────────

	THE ANCESTOR CLOSURE IS NOT ENOUGH, and the differential oracle is what said so.
	A structural change is reported at the REGION's path — a `ForEach`, a `When`, an
	`ErrorBoundary` — so the closure marks the region and everything above it. What it
	does NOT mark is the subtree the region RE-CREATED, because that subtree is a
	DESCENDANT of the dirty path and not an ancestor of it. And its root's path did not
	change: `{when}/then` is `{when}/then` whether the branch left and came back or
	never moved. So `arrange` found a path absent from the set, holding the rect it
	already had, and skipped it — handing the OLD subtree's entries forward, verdicts
	and all, over content that no longer exists.

	MEASURED, not reasoned into: the first draft shipped the closure alone and the
	suite went 7,993 -> 7,976. Seventeen cases across five files, and the clearest was
	`tab_view_scenario`'s — a tab left and re-entered kept reporting the PREVIOUS
	tab-scope's counter, because `controller.textAt()` reads the facts a skipped
	subtree never re-published. `overflow_sweep` found the geometry half at a viewport
	no hand-written case swept: a row painting 29 px outside its own box.

	THE ANSWER IS P3'S OWN OUTPUT, and it makes the skip's precondition one sentence:
	**a node may be skipped only if its layout node was SERVED from the node store —
	the same mounted TABLE, absent from `nodeDirty`, same axis and clip — and its rect
	is unchanged.** Served is exactly the claim the skip needs, and it is stronger than
	the closure in both directions:

	  * a served node's whole layout SUBTREE is the same tree object, so nothing under
	    it changed identity, props or shape;
	  * `nodeDirty` is closed over ancestors and covers EVERY dirty class, so a node
	    whose measure moved for a PAINT-classed reason (`label`, `icon`,
	    `compactLabel` — the three the measure seam sizes boxes with) is never served,
	    which the three-class closure alone could not promise.

	ONE LIST, SPENT ONCE, AND THAT IS THE SIMPLIFICATION THE MUTATIONS FORCED. The
	first draft also handed `builtIds` to the measure store as a second, explicit
	invalidation — and no mutation could make dropping it fail, for a reason worth
	writing down rather than working around: `measure_reuse.adopt` takes its
	`reusable` argument from THIS SET (`dirtyContains[id] ~= true`), so a node the set
	names is handed a FRESH slate by the same call that gives it somewhere to write.
	Widening the set invalidates the slate. A second call could only ever repeat it.

	AND WITH THE NODE STORE OFF IT DEGRADES RATHER THAN BREAKING. A count-only store
	constructs every node, so `builtIds` is the whole tree, the set is everything,
	nothing is skipped and every slate is dropped — which is precisely the pre-P5
	full solve, reached through the same code. P5 needs P3 to WIN, never to be right. ]]
function structural_scope.widen(contains: { [string]: boolean }, builtIds: { string }?)
	if builtIds == nil then
		return
	end
	for _, id in builtIds do
		contains[id] = true
	end
end

--[[ Drop the findings whose FILER has left the tree, so the solver's replay cannot
	carry a departed node's diagnostic forever. Called from the removal sweep's tail,
	after the departed paths' rect entries are gone, so the map answers "is this filer
	still here?" in one membership test rather than a second walk.

	WHAT `rects` ACTUALLY IS, stated literally because the sentence this replaces said
	"exactly the live set" and that is stronger than the truth (RED-TEAM 2026-09-02).
	It is the last solve's map MINUS the paths this sweep just retired, and the sweep
	walks `handles` — so a path the commit never gave a handle to (an elided node, a
	node a settle-phase solve wrote before its instance existed) keeps its entry
	whether or not it is still mounted, until a solve with no `reuse` set rebuilds the
	map from scratch.

	IT IS A SUPERSET, AND THAT IS THE SAFE DIRECTION: an over-inclusive map keeps a
	finding one solve longer than it deserves, which is a stale diagnostic that heals
	itself. The failure this exists to prevent is the other one — a finding whose node
	is gone for good, replayed on every frame for the life of the surface. ]]
--[[ ── THE ROOTS OF A STRUCTURAL SYNC (wicked-fast O6) ──────────────────────

	The other half of "a structural change is not a whole-tree event". Everything
	above answers *how small a SOLVE a structural change needs*; these two answer
	*how small a SYNC it needs* — which subtrees `renderer.luau` has to re-walk to
	rebuild the five per-path maps `livePaths` owns, and which paths those subtrees
	held before the walk.

	WHY THE DELTA IS ENOUGH. `mount.luau` pushes every `structure` entry against the
	path of the container whose `node.children` it just mutated — never against the
	child that moved — so a structure entry names exactly the subtree that changed,
	and everything outside those subtrees is unchanged BY CONSTRUCTION. And the maps
	are all inherited-from-the-parent or per-node facts (`scrollHostOf`, `clipHostOf`,
	`parentNodeOf`, `pathNodes`, `inputSinks`), so a subtree re-derives from its
	root's own recorded pair plus the nodes themselves.

	WHY THIS LIVES HERE RATHER THAN IN THE RENDERER. It is the same question this
	module already answers, asked of a different phase — and `renderer.luau` is the
	file with the least Source-write headroom in `src/`. Both functions are PURE
	functions of their arguments: they read no state of their caller, hold none of
	their own, and reach for nothing in `render/`, which is what keeps this one-way. ]]

--[[ The mounted roots this sync has to re-walk, resolved against the CURRENT tree,
	plus the number of nodes the resolution itself looked at.

	`nil` means REFUSE — take the whole tree, which is what `renderer.attach`'s
	`initialRender` does unconditionally and what any delta this cannot bound falls
	back to. ONE THING MAKES A DELTA UNBOUNDABLE, stated rather than implied: an entry
	whose path is not both MOUNTED (something was walked there, so there is a recorded
	seed and a recorded membership) and RESOLVABLE in the current tree — unless another
	entry strictly covers it, which is the ordinary case described below.

	AN ANCESTOR DOES NOT SWALLOW A DESCENDANT, which the first draft of this function
	had backwards. The caller's walk SKIPS a child whose node object and inherited
	pair are both unchanged, so an ancestor's walk may never reach a descendant root
	at all — a nested `ForEach` keeps its node object while `mount.luau` replaces its
	`children` in place. Collapsing the descendant away would have made exactly that
	change invisible. Two roots on one chain cost a second walk of a subtree, which is
	work; dropping one costs correctness.

	AND A SECOND CLASS OF ENTRY IS A ROOT: one whose PROP is a fact the caller's walk
	reads off a node rather than off the tree. There is exactly one — `active`, the
	input-sinking flag — because the other two the walk reads (`clipChildren`,
	`expandTarget`) are `reactive = false` in the schema and cannot move after
	construction. Without it, a backdrop that stops sinking keeps its entry through
	every later sync, since `active` is `semantics`-classed and schedules no sync of
	its own.

	THE DESCENT IS THE POINT OF THE SIGNATURE. `renderer.luau`'s `findNode` is a
	whole-tree DFS — one of the very walks this bound exists to stop paying — so a
	root is resolved by following the one child per level whose path is a prefix of
	the target. Every node it looks at is RETURNED in the count, so a descent through
	a wide level shows up in `stats.lastSsVisited` instead of hiding underneath it. ]]
-- the one prop the caller's live-path walk reads off a node and that can still move
-- (see the note above): `clipChildren` and `expandTarget` are `reactive = false`
local NODE_FACT_PROPS: { [string]: boolean } = { active = true }

function structural_scope.roots(
	dirty: { any },
	rootNode: any,
	mounted: { [string]: any }
): ({ { path: string, node: any } }?, number)
	local paths: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, entry in dirty do
		if entry.class ~= "structure" and not NODE_FACT_PROPS[entry.prop] then
			continue
		end
		local path = entry.path
		if type(path) ~= "string" then
			return nil, 0
		end
		if not seen[path] then
			seen[path] = true
			table.insert(paths, path)
		end
	end
	if #paths == 0 then
		return nil, 0
	end
	local visited = 0
	local out: { { path: string, node: any } } = {}
	for _, path in paths do
		local node: any = if mounted[path] ~= nil then rootNode else nil
		while node ~= nil and node.path ~= path do
			local found: any = nil
			for _, child in node.children do
				visited += 1
				if isPrefix(child.path, path) then
					found = child
					break
				end
			end
			node = found
		end
		if node == nil then
			--[[ NOT A ROOT, AND USUALLY NOT A PROBLEM. Two ordinary things put a path
				here: a container that MOUNTED this frame (a `ForEach` fills its children on
				its first run and pushes for itself, before anything has a handle) and one
				that LEFT (a region inside a removed subtree fires on its way out). Either
				way the change is inside some other entry's subtree, so it is skipped when
				another entry STRICTLY covers it — and only then. The topmost entry can
				never be covered, so an unresolvable one there still takes the whole tree. ]]
			local covered = false
			for _, other in paths do
				if other ~= path and isPrefix(other, path) then
					covered = true
					break
				end
			end
			if not covered then
				return nil, visited
			end
			continue
		end
		table.insert(out, { path = path, node = node })
	end
	if #out == 0 then
		return nil, visited
	end
	return out, visited
end

--[[ `path` and everything that was under it at the last walk, appended to `out`,
	read out of the renderer's per-parent index. This is how a DEPARTED subtree gets
	named: by the time the sweep runs those nodes are gone from the tree, so the index
	is the only thing that still knows what they were. ]]
function structural_scope.subtreeOf(childNodesOf: { [string]: { [string]: any } }, path: string, out: { string })
	table.insert(out, path)
	local kids = childNodesOf[path]
	if kids == nil then
		return
	end
	for child in kids do
		structural_scope.subtreeOf(childNodesOf, child, out)
	end
end

function structural_scope.sweepDiagnostics(result: any)
	local list = result.diagnostics
	if list == nil or #list == 0 then
		return
	end
	local rects = result.rects
	local kept: { any } = {}
	for _, d in list do
		local filer = d.filedBy or d.node
		if filer == nil or rects[filer] ~= nil then
			table.insert(kept, d)
		end
	end
	result.diagnostics = kept
end

return structural_scope
