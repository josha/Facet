--!strict
--[[ HOW A SOLVE'S RECTS REACH THE ADAPTER, AND IN WHAT ORDER.

	The order is the whole content of this module, and it is load-bearing rather
	than tidy.

	WHAT IT REPLACED. The renderer applied a solve's rects by iterating
	`result.rects` as a HASH — its own comment called it "the unordered rect hash".
	On a flat tree that is fine: every node's engine Position is absolute, so no
	node's answer depends on another's having landed first. Under a nested tree it
	stops being fine, because a descendant's Position is relative to its HOST. A
	descendant reached before its host re-bases against an origin that has not
	moved yet, writes a wrong value, and has to be corrected afterwards.

	MEASURED IN STUDIO, 2026-08-17, on a 120-node list inside a `ScrollView` whose
	container grew 40px: **240 engine `Position` changes across 120 descendants**,
	two each. `GetPropertyChangedSignal` fires only on a real VALUE change, so
	these were not redundant writes a minimal-write contract could catch — they
	were two different values:

	    1. cell  -> y = 60    WRONG: the new window rect against the host's OLD origin
	    2. list  -> y = 60    the host finally moves, and its origin updates
	    3. cell  -> y = 20    corrected, when the host re-bases its own children

	The net change is zero, which is exactly what "a Position is parent-relative"
	predicts. The path paid 2N writes to arrive there, and for the moment between
	1 and 3 every descendant of a moved container is drawn in the wrong place — a
	frame landing in that window shows the whole subtree jump.

	THE FIX IS TWO HALVES AND NEEDS BOTH. Ordering alone does not do it: apply the
	host first and its inline child re-base then runs against the children's own
	stale rects, which is the same defect mirrored. Deferring alone does not do it
	either: the child's first write still sees a stale origin. Together — document
	order here, and the adapter's re-base moved to `settleRects` after every rect
	has landed — a child whose parent-relative position did not change writes
	nothing at all.

	DOCUMENT ORDER IS ANCESTORS-FIRST BY CONSTRUCTION, so this needs no sort and no
	host bookkeeping: one walk of the live tree the renderer already knows how to
	do. **Do not put the hash back.** The sweep afterwards keeps the old behaviour
	for any solved path the walk cannot reach, which should be none.

	WHY IT IS A MODULE. Partly cohesion — "the rect pass" is a nameable thing with
	one rule — and partly the 200,000-character `Script.Source` WRITE cap, which
	`renderer.luau` is perpetually against: over it a module silently stops
	live-syncing into an open Studio session, so a live check tests the built place
	rather than the edits on disk. Everything it takes is read-only to it or a
	by-reference table declared once and never rebound (`handles`, `lastRects`,
	`lastBarInsets`, `stats`), which is the same seam test every other extraction
	from this file passed.
]]

local authority = require("./authority")

local rect_pass = {}

--[[ ctx:
	  adapter         the render target
	  handles         path -> adapter handle, by reference
	  lastRects       path -> the rect last written, by reference (the minimal-write
	                  contract's own record; a rect equal to it is not re-sent)
	  lastBarInsets   path -> the scroll bar gutter this solve spent, by reference
	  stats           the renderer's counters, by reference
	  rectsEqual      the pure rect comparison
	  scope           the commit's prune (P4), from `render/commit_walks`:
	                  `skip(node)` -> may this subtree be left alone, `note(node)` ->
	                  record what it was committed with, `armed()` -> is the prune on
	                  for this commit at all, `publishVisits(name, n)` -> this walk's
	                  share of `stats.lastCommitVisits` / `lastCommitVisitsByWalk`
	                  (wicked-fast T2) — the eighth walk of the commit, so it
	                  publishes through the same table `commit_walks`'s own seven
	                  share rather than keeping a second one
]]
function rect_pass.new(ctx: any)
	local adapter = ctx.adapter
	local handles = ctx.handles
	local lastRects = ctx.lastRects
	local lastBarInsets = ctx.lastBarInsets
	local stats = ctx.stats
	local rectsEqual = ctx.rectsEqual
	local scope = ctx.scope

	local function applyOne(path: string, entry: any)
		local handle = handles[path]
		-- the bar gutter a scroll host spent this solve, carried on the same walk
		-- the rects are (solver: `out[id].barInset`). Nil on every node that is not
		-- an overflowing scroll host, which is nearly all of them, so this is one
		-- nil assignment per node rather than a second walk.
		lastBarInsets[path] = entry.barInset
		if handle ~= nil and not rectsEqual(lastRects[path], entry.rect) then
			authority.assertWrite("common", "size", "layout")
			adapter.setRect(handle, entry.rect)
			lastRects[path] = entry.rect
			stats.rectWrites += 1
		end
	end

	-- `rects` is the solve's `path -> entry` map; `rootNode` is the live tree it
	-- was solved from; `work` is the solve's work record, whose `translatedRoots` /
	-- `translatedPaths` / `translatedEntries` this walk short-circuits through
	-- (wicked-fast N1). `work` nil — `initialRender`, or any caller that does not
	-- have one — falls back to the plain walk exactly as before.
	local function apply(rootNode: any, rects: { [string]: any }, work: any?)
		--[[ THE LAST WALK OF THE COMMIT, so this is the one that spends the prune AND
			records what every walk in the span compared against (P4). `note` is called
			for each node this walk visits — the same set the six before it visited —
			so the next commit's comparison is against the state this one actually
			committed. A commit that could not PRUNE still RECORDS (it walked everything
			anyway, so the next one can prune); a commit with the feature OFF records
			nothing, which is what keeps the differential oracle's off arm a genuine
			pre-P4 build. ]]
		local pruning = scope.armed()
		local recording = scope.records()
		local applied: { [string]: boolean }? = if pruning then nil else {}
		--[[ THE RUNS THE SOLVER RECORDED (wicked-fast N1), and they are read only on a
			PRUNED commit — deliberately, and for the reason this module's neighbour
			already gives about `recording`: a `commitScope = false` arm has to stay an
			honest pre-P4 build, and an arm that still takes the fast route is not the
			control for the fast route. A commit that cannot prune is the rare, whole-tree
			one anyway; the run is worth its bookkeeping only on the steady path. ]]
		local runs = if pruning and work ~= nil then work.translatedRoots else nil
		local runPaths = if runs ~= nil then work.translatedPaths else nil
		local runEntries = if runs ~= nil then work.translatedEntries else nil
		local visits = 0
		local function walk(node: any)
			if pruning and scope.skip(node) then
				return
			end
			visits += 1
			local entry = rects[node.path]
			if entry ~= nil then
				if applied ~= nil then
					applied[node.path] = true
				end
				applyOne(node.path, entry)
			end
			--[[ ...AND ONLY FOR A NODE THIS COMMIT COULD ACTUALLY COMMIT (P5). Every
				write in the span — this one, the six walks' — is guarded on
				`handles[path]`, so a node with no handle yet is one the commit made NO
				write for. Recording it anyway says "committed with this entry" about an
				entry nothing was spent on, and the next commit then prunes it forever.

				REACHABLE, AND P5 IS WHAT MADE IT SO. A settle-phase solve and the
				feedback re-solve both run WITHOUT a structural sync, so a node mounted
				this frame is already in the tree the solver walks and not yet in
				`handles`. Before P5 the structural refresh that followed did a FULL
				solve into a FRESH map, so every entry was a new table, nothing matched
				and the rect landed. P5 hands the entry forward instead, `skip` finds
				`lastCommitEntry == entry`, and the node keeps last frame's rect for as
				long as its geometry does not move again. MEASURED: the Table's
				collapsed-column chip (`tests/table_input.spec`) mounted with NO RECT
				AT ALL — `chip.rect` nil — and six cases across two files went red. ]]
			if recording and handles[node.path] ~= nil then
				scope.note(node)
			end
			--[[ ...AND THE RUN STOPS THE WALK HERE (wicked-fast N1). This node's subtree
				only MOVED, and the solver already wrote every descendant's re-based entry
				into a flat, document-ordered run when it did it
				(`layout/solver.luau`'s `translateDescendants`). Walking the live tree to
				find them again — a hash lookup, a `rectsEqual` and a recursive call per
				node — is the part of this walk that is not the adapter calls.

				THE COMPARE IS DEAD, NOT SKIPPED ON FAITH. The arm fires only when the
				root's origin moved, every descendant is re-based by that same non-zero
				delta, and `lastRects[path]` — where a handle exists at all — is by
				construction value-equal to the entry the move started from (a write is
				skipped only when it equals `lastRects`, so the two never diverge). So no
				run rect can equal what was last written. `rectWrites` is pinned per tick
				by `tests/commit_translate.spec` and `tests/nameplates_baseline.spec`,
				which is what would say so if that argument were ever wrong.

				THE HANDLE GUARD ON `noteEntry` IS THE WALK'S OWN (P5): recording a path
				the commit made no write for prunes it forever once it gains a handle. And
				an EMPTY span (`from > to`, a childless root) is a real case — the loop
				runs zero times and the root's own entry is applied above, by the literal.

				THE ONE HONEST COST: a structural WRAPPER path inside a translated subtree
				(a `ForEach` region, a `When` region — a mounted node that owns no rect) is
				not re-noted here, because the run holds layout ids and a wrapper is not
				one. Its `lastCommitEntry` then lags a tick and the six pruned walks visit
				it once more than strictly needed. In the nameplates tree the wrappers sit
				ABOVE the translate roots so the count is zero; the bound is one extra
				visit per wrapper inside a translated subtree, and it is not a correctness
				question — nothing is written from a wrapper. ]]
			local run = if runs ~= nil then runs[node.path] else nil
			if run ~= nil then
				for i = run.from, run.to do
					local path = (runPaths :: any)[i]
					local entryAt = (runEntries :: any)[i]
					lastBarInsets[path] = entryAt.barInset
					local handle = handles[path]
					if handle ~= nil then
						authority.assertWrite("common", "size", "layout")
						adapter.setRect(handle, entryAt.rect)
						lastRects[path] = entryAt.rect
						stats.rectWrites += 1
						if recording then
							scope.noteEntry(path, entryAt)
						end
					end
					if applied ~= nil then
						applied[path] = true
					end
				end
				return
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
		--[[ any solved path the walk could not reach — a node that left the tree
			between the solve and the apply. Order cannot matter for one of these: it
			has no live ancestor to be relative to.

			SKIPPED ENTIRELY ON A PRUNED COMMIT, and the reason is a PREMISE ABOUT THE
			MAP rather than an optimisation: every key in it belongs to a live path.
			That used to be free — the renderer armed the prune only for a REUSE solve
			and gave one only when the tree's shape had not moved. **P5 gives one for an
			add/remove/reorder too, and pays for the premise where it is now spendable:
			`renderer`'s removal sweep deletes a departed path's rect entry beside the
			nine other per-path records it owns.** Running the sweep anyway would
			re-apply every subtree the walk had just proved it could leave alone —
			O(N), which is the term this fix exists to remove. ]]
		if applied ~= nil then
			for path, entry in rects do
				if not applied[path] then
					applyOne(path, entry)
				end
			end
		end
		-- ...and the DEFERRED RE-BASE. A host that moved may carry children this
		-- solve did not re-emit — an incremental re-solve of the host alone — and
		-- placing those is the adapter's business, not this walk's. It runs after
		-- every rect has landed, so a child it touches is re-based against two
		-- current numbers instead of one; with the adapter's write skip in front of
		-- it, a child already in the right place costs nothing. Feature-detected,
		-- like every other optional adapter capability.
		if adapter.settleRects ~= nil then
			adapter.settleRects()
		end
		-- the eighth walk's share (wicked-fast T2): the sweep above and the
		-- deferred re-base both write through `applyOne`/the adapter directly and
		-- visit no tree node, so `visits` is already final by here.
		scope.publishVisits("rectPass", visits)
	end

	return { apply = apply }
end

return rect_pass
