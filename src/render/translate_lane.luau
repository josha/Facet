--!strict
--[[ THE TRANSLATE LANE — a refresh whose only layout-class dirt is a placement
	prop on coordinate-space hosts solves NOTHING.

	Per qualifying host the lane re-places it with `placement.anchorPlace` — the
	solver's own function, not a second copy of the arithmetic — writes the
	solver's existing entry IN PLACE, and calls `setRect` once. Anything that
	would need a solve is handed BACK to the solve as the remainder. MEASURED on
	the campaign's own fixture: a frame that moves 250 nameplates and resizes 50
	cast bars lanes ALL 250 and solves only the 50 bars — the lane keys on the
	ENTRY, and a caster's extra dirt is a MEASURE write on a different path.

	TWO PASSES, AND THE SPLIT IS THE SAFETY PROPERTY. VALIDATE every candidate
	against the gates before a single write, then APPLY. A candidate that fails
	stays in the remainder and the solve handles it; the others still lane. No
	half-applied frame exists, because nothing is written until every gate on
	every candidate has answered.

	WHAT A SKIPPED FUNCTION PUBLISHED IS A LIST, NOT A HOPE. For a consumed host
	this lane skips `layout_node.build`, `solver.solve`, the eight commit walks,
	`presentation_channel.installAnimationRecords`, `premeasure_round.request`,
	`fullSolveSeq` and the whole `stats.last*` family; it SERVES `hit_lift.refresh`,
	`dragBridge.refreshTargets` and the solved listeners by calling them. The full
	table — one row per channel, with the verdict and the pin — is in the campaign
	ledger's "Task 5 — the owed list" and `tests/translate_lane.spec.luau` drives
	every row of it. The gates below are that table, in code. ]]
local placementLib = require("../layout/placement")
local measureFacts = require("../layout/measure_facts")
local layoutNodeLib = require("./layout_node")
local authority = require("./authority")

local translate_lane = {}

export type Deps = {
	handles: { [string]: any },
	lastRects: { [string]: any },
	lastHitRects: { [string]: any },
	-- the last solve's composition resolutions, by node path, BY REFERENCE
	lastCompositions: { [string]: any },
	stats: any,
	adapter: any,
	metrics: () -> any,
	-- `render/rect_reads`: `spaceHosts`, `spaceHostHasPath`, `invalidateOrigins`,
	-- `hostOriginOf`
	geometry: any,
	parentNodeOf: { [string]: any }, -- by reference
	inputSinks: { [string]: boolean }, -- by reference, for the `hit_lift` serve
	layoutNodeOf: (mountNode: any) -> any,
	--[[ parent path -> its children BY PATH, the renderer's own per-parent index, BY
		REFERENCE. This is how the lane reaches a mounted node, and the alternative is
		why: `renderer.findNode` is a depth-first walk of the whole tree per call, and
		one call per candidate made a 250-plate tick O(plates x nodes) — measured LIVE
		at +5.4 ms a frame on FacetBench's `nameplates L`, 3.9 -> 9.3, where every Lune
		instrument in the suite was blind to it because they count work, not time. ]]
	childNodesOf: { [string]: { [string]: any } },
	lastResultRects: () -> any?, -- the solver's live entry map
	solverHidden: { [string]: boolean },
	channelArmed: () -> boolean,
	rectsEqual: (a: any, b: any) -> boolean,
	hitLiftRefresh: (any, any, any, any, any, (string) -> (number, number)) -> boolean,
	syncZOrder: () -> (),
}

-- the three props a coordinate-space host's own rect is a function of. The other
-- six placement props (`alignH`, `alignV`, `lineAlign`, `gridSpan`,
-- `layoutPriority`, `shrinkWeight`) are read by a STACK or a GRID parent, never by
-- the anchor branch this lane reproduces, so a write to one of them is not a
-- candidate and reaches the solve untouched.
local PLACEMENT: { [string]: boolean } = { offsetX = true, offsetY = true, anchor = true }

--[[ THE MOUNT PARENT IS NOT ALWAYS THE LAYOUT PARENT. `When`, `ForEach` and
	`ErrorBoundary` own MOUNTING, not layout: `layout_node`'s `appendChild` splices
	their children straight into the enclosing flow, so a `ForEach` row's real
	layout parent — the container whose inner box places it — is the node ABOVE the
	region, and the region itself has no layout node and no rect at all.

	NAMED CLASSES, NOT "climb while the layout node is nil". A missing layout node
	also means "this node was never built", and climbing past a real parent would
	place the host against some grandparent's box — a wrong answer that looks like a
	working one. This is the same three-class list `appendChild` splices on. ]]
local SPLICED: { [string]: boolean } = { When = true, ForEach = true, ErrorBoundary = true }

-- an offset the lane may resolve itself: a plain number, or the `{ scale, offset }`
-- fraction-of-the-parent form. A METRIC NAME is refused — the theme resolves those,
-- and `layout_node.resolveOffset` is the only thing that knows the snapshot.
local function offsetOk(v: any): boolean
	if v == nil or type(v) == "number" then
		return true
	end
	return type(v) == "table"
		and (v.scale == nil or type(v.scale) == "number")
		and (v.offset == nil or type(v.offset) == "number")
end

function translate_lane.new(deps: Deps)
	local handles, lastRects, lastHitRects = deps.handles, deps.lastRects, deps.lastHitRects
	local lastCompositions = deps.lastCompositions
	local stats, adapter, geometry = deps.stats, deps.adapter, deps.geometry
	local parentNodeOf, layoutNodeOf, childNodesOf = deps.parentNodeOf, deps.layoutNodeOf, deps.childNodesOf
	local solverHidden, channelArmed, rectsEqual = deps.solverHidden, deps.channelArmed, deps.rectsEqual
	local spaceHosts, spaceHostHasPath = geometry.spaceHosts, geometry.spaceHostHasPath

	-- one candidate per host path, however many placement entries it wrote this
	-- frame. `props`/`metrics` are held in the record because `apply` hands them to
	-- `layout_node.applyPlacement`, and this module is `--!strict`.
	local candidates: {
		[string]: { node: any, entry: any, x: number, y: number, props: any, metrics: any },
	} = {}
	local order: { string } = {}

	--[[ the parent's inner (content) box, in the space the HOST's rect is STORED in.
		A space host's children are stored relative to it, so such a parent's own box
		sits at the origin however far the parent itself has moved. ]]
	--[[ THE COMPOSITION PATHS OF THE LAST SOLVE, collected ONCE per refresh rather
		than iterated per candidate. `run` refills this list only when the map is
		non-empty, which on every surface this lane was built for is never — one
		`next()` and no allocation — and a surface that DOES hold compositions pays one
		pass over a handful of paths instead of `candidates x compositions`, which on a
		250-plate frame was the difference between a few string compares and thousands.
		The old form also interpolated a fresh `path .. "/"` per candidate; the prefix
		test below allocates nothing. ]]
	local compositionPaths: { string } = {}

	--[[ IS THIS HOST A COMPOSITION, OR ABOVE ONE? `string.sub` on the COMPOSITION's
		path rather than a built prefix on the host's: same answer, no string built. A
		composition beneath a moving host re-resolves — its exclusions are window-space
		by contract and are converted into its own box — and only `arrange` can do that
		(the solver's `spaceCompositions`/`noSkipDepth`), so the lane refuses the host. ]]
	local function underAComposition(path: string): boolean
		local n = #path
		for _, compPath in compositionPaths do
			if compPath == path or (#compPath > n and string.sub(compPath, 1, n + 1) == path .. "/") then
				return true
			end
		end
		return false
	end

	local function innerBoxOf(parentPath: string, parentNode: any): any?
		local own = lastRects[parentPath]
		if own == nil then
			return nil
		end
		local pr = if spaceHosts[parentPath] then { x = 0, y = 0, w = own.w, h = own.h } else own
		local pt, prr, pb, pl = measureFacts.sides(parentNode.padding)
		-- THE SOLVER'S OWN DERIVATION, NOT A COPY: `placement.innerBox` is the four
		-- lines `arrange` runs, clamp included.
		local ix, iy, iw, ih = placementLib.innerBox(pr.x, pr.y, pr.w, pr.h, pt, prr, pb, pl)
		return { x = ix, y = iy, w = iw, h = ih }
	end

	local function validate(path: string): boolean
		if candidates[path] ~= nil then
			return true
		end
		if not spaceHosts[path] or handles[path] == nil or solverHidden[path] == true then
			return false
		end
		--[[ THE HOST'S OWN HIT EXPANDER, and a `UI.Path` anywhere beneath it.

			The expander's `want` is centred on the host's own rect and only the
			`hitRects` commit walk recomputes it, so a host that carries one is refused.
			A DESCENDANT's expander is host-relative and did not move in its own space,
			so it needs nothing — and an expander elsewhere on the surface that now
			overhangs INTO the moved host is served by the `hit_lift` call in `run`.

			A Path under the host is the `visible` walk's clip test (`pathEscapesClip`),
			which compares a stroked path against its clip host's box in WINDOW space —
			the one visibility answer a move can change. `spaceHostHasPath` is a COUNT
			whose key `rect_reads.noteUnder`/`noteFromHost` DELETE at zero, so this plain
			truthiness test is exact: a host that once held a Path and no longer does has
			no key and lanes again. TWO things make that true, and both live outside this
			file. (1) Every ±1 rides a latch the live-path walk already keeps, so
			re-walking an unchanged Path cannot ratchet the count. (2) The removal sweep
			visits DEEPEST FIRST (T4b), which is what keeps the decrement's climb whole:
			it runs from `pathHostOf[Path]` up through `hostSpaceOf`, and
			`geometry.dropPath` clears the very link it climbs — so a nested space host
			torn down before the Path beneath it would stop the climb one host short and
			leave every surviving ancestor gated for the life of the surface.
			`tests/translate_lane.spec.luau`'s nested-host case drives exactly that, on
			BOTH sweep arms, and deleting the sort is what reddens it. ]]
		if lastHitRects[path] ~= nil or spaceHostHasPath[path] ~= nil then
			return false
		end
		--[[ A COMPOSITION UNDER A MOVING HOST IS THE ONE THING A MOVE RE-ARRANGES BELOW
			ITSELF. T3 measured it: the origin carry is exact only where a composition is
			RE-ENTERED, and under a coordinate space a host's move re-bases nothing, so
			both the translate arm and the ordinary arrange skip it — 7 px wrong after one
			slide. The solver answers with `Ctx.spaceCompositions`/`noSkipDepth`, which
			suspend the skip for such a host's body; a lane tick has no arrange to suspend,
			so it refuses the host instead.

			COSTS ONE `next` ON A SURFACE WITH NO COMPOSITIONS, which is nearly all of
			them and is every surface this lane was built for. `lastCompositions` is the
			renderer's own map of the last solve's resolutions, keyed by node path; the
			host itself counts, because a Composition that is its own coordinate space
			re-resolves its body on arrange too. ]]
		if #compositionPaths > 0 and underAComposition(path) then
			return false
		end
		local rects = deps.lastResultRects()
		local entry = if rects ~= nil then rects[path] else nil
		-- THE MOUNTED NODE IN O(1), through the renderer's own per-parent index (see
		-- `Deps.childNodesOf`), never through a tree walk
		local mountParent = parentNodeOf[path]
		local siblings = if mountParent ~= nil then childNodesOf[mountParent.path] else nil
		local mount = if siblings ~= nil then siblings[path] else nil
		-- see `SPLICED`: step over the structural regions between this host and the
		-- container that actually placed it
		local parentMount = mountParent
		while parentMount ~= nil and SPLICED[parentMount.class] do
			parentMount = parentNodeOf[parentMount.path]
		end
		if entry == nil or entry.rect == nil or mount == nil or parentMount == nil then
			return false
		end
		--[[ THE SIZE COMES FROM THE SOLVER'S ENTRY, AND FROM NOWHERE ELSE. `apply` builds
			the new rect from `entry.rect`, so validation has to place against the same
			table or the two can disagree: `lastRects[path]` is the rect the COMMIT last
			wrote, and the two are the same table on every ordinary frame but need not be
			(a solve that produced a fresh entry a torn commit never applied leaves
			`lastRects` one frame behind). Placing against one and writing the other would
			put the host at a position derived from a size it does not have. ]]
		local sized = entry.rect
		local node, parent = layoutNodeOf(mount), layoutNodeOf(parentMount)
		if node == nil or parent == nil then
			return false
		end
		-- ONLY THE ANCHOR BRANCH. This lane reproduces `solver.arrange`'s corner-anchor
		-- placement and nothing else: a `scroll` parent reads `offsetX`/`offsetY` for
		-- its own axis, and every stack and grid places its children by flow.
		if parent.kind ~= "anchor" then
			return false
		end
		-- `offsetFill` gives a `fill` child back the room its own offset costs it, so
		-- on a fill axis the offset changes the host's SIZE and not only its position
		if measureFacts.dim(node, "w").type == "fill" or measureFacts.dim(node, "h").type == "fill" then
			return false
		end
		local props = mount.props
		if props == nil then
			return false
		end
		if not offsetOk(props.offsetX) or not offsetOk(props.offsetY) then
			return false
		end
		--[[ THE NIL-FLIP GATE. `layout_node.build` derives `placementProps` — a
			nine-prop PRESENCE flag — and the PARENT's `inertPlacement` audit from these
			props, and both move only when a prop appears or disappears. The lane serves
			values, not presence, so a write whose old or new value is `nil` stays in the
			remainder and the solve does the whole job. `node` here is the layout node as
			the last build left it, so its field is the OLD value and `props` carries the
			new one. ]]
		if
			(props.offsetX == nil) ~= (node.offsetX == nil)
			or (props.offsetY == nil) ~= (node.offsetY == nil)
			or (props.anchor == nil) ~= (node.anchor == nil)
		then
			return false
		end
		-- an anchor name the solver does not know files a diagnostic, which is a
		-- channel a lane tick has no way to publish
		if placementLib.ANCHOR_FACTORS[props.anchor or "topLeft"] == nil then
			return false
		end
		local inner = innerBoxOf(parentMount.path, parent)
		if inner == nil then
			return false
		end
		local metrics = deps.metrics()
		local ox = layoutNodeLib.resolveOffset(metrics, props.offsetX)
		local oy = layoutNodeLib.resolveOffset(metrics, props.offsetY)
		local x, y = placementLib.anchorPlace(
			inner.x,
			inner.y,
			inner.w,
			inner.h,
			sized.w,
			sized.h,
			false,
			false,
			props.anchor,
			ox,
			oy
		)
		--[[ THERE IS NO CONTAINMENT GATE HERE, AND THAT IS A MEASUREMENT RATHER THAN AN
			OVERSIGHT. The plan called for one — refuse unless the old and the new rect
			are both inside the parent's inner box, so the lane never has to file the
			containment finding a solve would have filed. Under an ANCHOR parent there is
			no such finding to file: `arrange_reports.containment` has exactly ONE caller,
			`stack.arrange`, and the anchor branch never reports about where it put a
			child (its own doc says anchors "place children outside their box by design").
			Driven directly on the 250-plate fixture: a plate moved to x = -500, wholly
			outside the anchor, changes `controller.diagnostics()` from 0 findings to 0
			findings.

			The rest of the position channel is gated above or is position-blind by
			construction: the `visible` walk's only geometry test is `pathEscapesClip`
			(the `spaceHostHasPath` gate), and `arrange_reports.box` — the report a host's
			OWN arrange makes — reads `rect.w`/`rect.h` and never x or y, which under a
			coordinate space is doubly true because such a host's body runs at the origin.

			WHAT WOULD MAKE THIS WRONG is the anchor branch gaining a containment report,
			or this lane accepting a parent kind that has one. Both are pinned in
			`tests/translate_lane.spec.luau` — the single call site by a source scan, the
			parent kind by the gate above — so the day either moves, this comment does not
			quietly become false.

			The cost of the gate the plan asked for was not theoretical: 21 of the 250
			plates in the campaign's own demonstrator sit partly past the 1280 px anchor,
			so it would have refused 8 % of them and left every "pure" tick solving. ]]
		candidates[path] = { node = node, entry = entry, x = x, y = y, props = props, metrics = metrics }
		table.insert(order, path)
		return true
	end

	-- returns TRUE when it wrote a rect, which is what `stats.lastLaneTranslates`
	-- counts: see the note at the bottom of `run`
	local function apply(path: string): boolean
		local c = candidates[path]
		local node, entry = c.node, c.entry
		--[[ WHAT `layout_node.build` WOULD HAVE WRITTEN, WRITTEN BY THE BUILD'S OWN
			CODE. The lane consumes these dirty entries, so the classifier never marks
			this path in `nodeDirty` and the next build takes the warm-store hit — which
			returns this very node table, unchanged. `applyPlacement` is the same
			function the node literal calls, so there is exactly one copy of "what a
			placement prop means on a layout node" and no enumeration here to fall out of
			date. (`placementProps` and the parent's `inertPlacement` cannot move: a
			presence flip was refused at validation.) ]]
		layoutNodeLib.applyPlacement(node, c.props, c.metrics)
		local old = entry.rect
		local newRect = table.freeze({ x = c.x, y = c.y, w = old.w, h = old.h })
		if rectsEqual(old, newRect) then
			-- the same pixel: nothing moved, so nothing is written AND nothing is
			-- counted. The layout node was still re-placed above, which is what makes
			-- the warm-store hit correct on the next build; the COUNTER is about
			-- writes, not about candidates.
			return false
		end
		--[[ THE ENTRY IS MUTATED IN PLACE, DELIBERATELY. `commit_walks.skip` prunes on
			entry IDENTITY — it holds the last-committed entry TABLE — and this host's
			subtree is exactly what the next commit must prune. The RECT is a fresh
			frozen table and is never mutated, which is the Global Constraint every
			identity-comparing reader downstream depends on. ]]
		entry.rect = newRect
		lastRects[path] = newRect
		geometry.invalidateOrigins()
		authority.assertWrite("common", "size", "layout")
		adapter.setRect(handles[path], newRect)
		stats.rectWrites += 1
		return true
	end

	--[[ returns the entries the solve must still see — the SAME array when nothing
		was consumed, so a frame with no coordinate-space hosts allocates nothing —
		and how many hosts were re-placed. ]]
	local function run(dirty: { any }): ({ any }, number)
		stats.lastLaneTranslates = 0
		-- an armed `withAnimation` commit records every root that moved, and that
		-- record walk runs inside the solve
		if channelArmed() or next(spaceHosts) == nil then
			return dirty, 0
		end
		table.clear(candidates)
		table.clear(order)
		-- ...and the composition list, refilled once per refresh (see `compositionPaths`).
		-- `next` first, so the surfaces that hold none — which is nearly all of them, and
		-- every one this lane was built for — pay one hash probe and no allocation.
		table.clear(compositionPaths)
		if next(lastCompositions) ~= nil then
			for compPath in lastCompositions do
				table.insert(compositionPaths, compPath)
			end
		end
		local consumed: { [number]: boolean }? = nil
		for i, entry in dirty do
			if entry.class == "arrange" and entry.prop ~= nil and PLACEMENT[entry.prop] and entry.path ~= nil then
				if validate(entry.path) then
					consumed = consumed or {}
					consumed[i] = true
				end
			end
		end
		if consumed == nil then
			return dirty, 0
		end
		local applied = 0
		for _, path in order do
			if apply(path) then
				applied += 1
			end
		end
		--[[ SERVE `hit_lift`. An expander OUTSIDE a moved host can now overhang INTO
			it, and no counter can decide that cheaply — so call the same function the
			commit calls, with the commit's own feature guard beside it: on an adapter
			with no `setHitRect` there is no expander seam at all. It reads
			`lastHitRects`, not the tree, so it costs one pass over the expander set on a
			frame that HAS expanders and nothing on a frame that does not.

			`geometry.hostOriginOf`, not the commit path's fresh-map origin: a lane frame
			runs no solve, and `apply` has already written `lastRects` and bumped the
			origin epoch, so last frame's map IS this frame's. ]]
		if #order > 0 and adapter.setHitRect ~= nil and next(lastHitRects) ~= nil then
			if
				deps.hitLiftRefresh(
					deps.lastResultRects(),
					lastHitRects,
					deps.inputSinks,
					parentNodeOf,
					solverHidden,
					geometry.hostOriginOf
				)
			then
				deps.syncZOrder()
			end
		end
		local remaining = {}
		for i, entry in dirty do
			if not consumed[i] then
				table.insert(remaining, entry)
			end
		end
		--[[ THE COUNTER IS HOSTS THE LANE MOVED, not candidates it validated. `apply`
			returns early on a zero-delta re-place — a placement prop written back to the
			value it already had — and counting those would have made
			`stats.lastLaneTranslates` a number no engine write corresponds to, which is
			the one thing a per-refresh counter must never be. `render/render_stats`'
			field doc says the same in the same words. The REMAINDER is still keyed on
			validation: a candidate the lane consumed does not reach the solve whether or
			not its rect moved, because its layout node was re-placed either way. ]]
		stats.laneTranslates += applied
		stats.lastLaneTranslates = applied
		return remaining, applied
	end

	return { run = run }
end

return translate_lane
