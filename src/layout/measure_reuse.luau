--!strict
--[[ THE CROSS-SOLVE MEASURE STORE (perf campaign P1, 2026-09-01).

	`solver.measure` has always been memoised PER SOLVE, and the memo dies with the
	`ctx` that owns it. Incremental layout (Stage 2 v2) then taught `arrange` to SKIP
	a subtree nothing dirtied — but `measure` never learned the same trick, so a
	refresh with NOTHING dirty still measured every node in the tree exactly once,
	and a refresh with ONE dirty leaf measured every node TWICE (the ancestor closure
	always reaches the root, and distributing the root stack re-measures every child
	subtree). Measured headless on `battle_hud` L, 5115 layout nodes, 2026-09-01:
	16.1 ms and `measured = 1.00 N` with zero dirt; 24.7 ms and `measured = 2.00 N`
	for a real one-leaf closure. That is 44 % of the step.

	This module is the per-SURFACE half of the fix: a slate per node id that outlives
	the solve, so the per-solve memo can be handed the answers the LAST solve already
	produced instead of a fresh empty table. `solver.measure` is otherwise unchanged —
	same key, same entries, same replay of the published verdicts — which matters more
	than it sounds: that key was proved correct by a differential fuzz over 800 seeded
	trees (see `tests/measure_memo.spec.luau`) and it already carries every input a
	measure reads that is not in its argument list (`hiddenDepth`, the nearest
	container and `fitProbe` all ride `ctx.scopeKey`). Making it cross-solve therefore
	only has to answer the axes a SOLVE BOUNDARY adds, and there are exactly three.

	AXIS 1 — THE NODE. The slate is keyed by `node.id`, the mounted path, which is the
	same identity `dirtyContains` and `previous.rects` are keyed by — never by the node
	TABLE, which is what the per-solve memo keys on. **That was written when the layout
	tree was rebuilt from the mounted tree on every solve, so the table was a different
	object each time; since P3 (`render/layout_node.build`) a clean subtree's tables are
	REUSED across solves.** The choice is unchanged and so is its reason: `node.id` is
	the identity the three stores share, and a table key would go stale on exactly the
	solves P3 rebuilds. What moved is only that the per-solve memo now starts each solve
	holding keys it can hit — warmer, never wrong, since its `ctx` is fresh either way.

	AXIS 2 — WHAT CHANGED INSIDE THE NODE. A slate may only be adopted when this
	solve can prove nothing under that node moved, and that proof already exists:
	`reuse.dirtyContains` is the dirty set closed over ancestors, i.e. exactly the set
	`arrange` refuses to skip. A node absent from it has no layout dirt on itself or
	on any descendant. A node present in it — and every ancestor of every dirty node
	is — gets a FRESH slate, which is also what drops its stale entries. A solve with
	no reuse set at all (a feedback re-solve, the first solve, a REFUSED structural
	one) adopts nothing and the renderer clears the whole store for it.

	**A STRUCTURAL CHANGE IS NO LONGER ONE OF THOSE (perf campaign P5), and the reason
	this paragraph used to name it is the reason `forget` below exists.** A structural
	change can move different content under the SAME path — a `When` toggled off and
	on inside one flush, a `ForEach` key removed and re-added by two writes of it — and
	that path never leaves the tree, so no removal sweep sees it. A structural solve
	now gets a reuse set (`render/structural_scope.luau`) and pays for it by dropping
	the slate of every id `layout_node.build` CONSTRUCTED, which is exactly the set
	whose identity or props may have moved; with the node store off there is no smaller
	set to name and the whole store still goes.

	AXIS 3 — WHAT CHANGED AROUND IT. Everything a measure reads that is neither the
	node nor the offer is solve-WIDE: the viewport, the safe insets, the root policy,
	the scrollbar reserve, the platform band, the theme snapshot, the text measure and
	paint scales, and the exact-text-width store. None of them dirty a node, so none of
	them can be caught by axis 2. They are folded into one `stamp` string by the
	renderer and compared once per solve; any change wipes the store. That is blunt on
	purpose — these move on a resize, a theme swap or a text-metrics correction, never
	on the per-frame path this exists to make cheap.

	THE ONE AXIS THAT IS NEITHER, and it is the trap this design walked into once. A
	`containerRelative` dimension resolves against the nearest scroll VIEWPORT rather
	than against the parent's offer, and the container joins `ctx.scopeKey` only once
	one has actually been MEASURED (see `rebuildScopeKey`: arming late is what keeps
	the memo alive at all). So every ancestor of the first such dimension is keyed
	WITHOUT the container while its answer depends on one — safe inside a solve
	(a pre-arm key can never be produced again once armed), and stale across solves the
	moment that container moves. `node.containerRelativeInside` is stamped at tree
	build time for exactly this question and is what the arrange skip already asks; a
	slate for such a node records the container it answered against and is adopted only
	if it still matches.

	KEYS ARE CAPPED PER NODE. A slate is written to on every genuine measure and only
	ever grows; a node whose offers DRIFT (a clean subtree inside an animating box)
	would accumulate one entry per frame forever. Past `KEY_CAP` distinct offers the
	slate is wiped and starts again — a miss, never a wrong answer.
]]

local measure_reuse = {}

-- Distinct offers one node may keep before its slate is wiped. Twelve is well past
-- what a settled tree produces (a node is measured at 1-2 offers per solve and they
-- repeat) and small enough that a drifting node cannot hold a frame's worth of keys.
local KEY_CAP = 12

export type Store = {
	-- the solve-wide inputs the entries below were measured under (axis 3)
	stamp: string,
	byId: { [string]: { [string]: any } },
	-- the container a `containerRelativeInside` node answered against, `"{w}|{h}"`.
	-- Absent for every other node, which is nearly all of them.
	ctr: { [string]: string },
	-- distinct offers stored per node, for `KEY_CAP`
	n: { [string]: number },
}

function measure_reuse.new(): Store
	-- the initial stamp is deliberately not `""`: a surface whose real stamp somehow
	-- computed empty would otherwise adopt an empty store rather than be re-stamped
	return { stamp = "\0", byId = {}, ctr = {}, n = {} }
end

function measure_reuse.clear(store: Store)
	table.clear(store.byId)
	table.clear(store.ctr)
	table.clear(store.n)
end

--[[ ONE PATH'S SLATE, DROPPED (perf campaign P5). Two callers, and they are the two
	halves of the invalidation boundary a structural partial solve needs — see
	`render/structural_scope.luau`, which owns the argument:

	  * the renderer's REMOVAL SWEEP, beside the nine other per-path records it
	    already owns. A path that leaves takes its slate with it, or a `ForEach` that
	    mints fresh keys grows this store for the life of the surface;
	  * every id `layout_node.build` CONSTRUCTED on a structural build — the nodes
	    whose identity or props may have moved, which is the set axis 1's warning
	    ("a structural change can move different content under the same path") is
	    actually about.

	Axis 1 is unchanged and so is its reason: a solve with NO reuse set still adopts
	nothing and still clears the whole store. This is the narrower answer for the
	solve that now HAS one. ]]
function measure_reuse.forget(store: Store, id: string)
	store.byId[id] = nil
	store.ctr[id] = nil
	store.n[id] = nil
end

-- Re-stamp the store with this solve's solve-wide inputs; clears it (and returns
-- true) when any of them moved.
function measure_reuse.restamp(store: Store, stamp: string): boolean
	if store.stamp == stamp then
		return false
	end
	store.stamp = stamp
	measure_reuse.clear(store)
	return true
end

--[[ The slate `solver.measure` writes this node's entries into, and whether it came
	back from a previous solve. `reusable` is the caller's proof for axis 2; the
	container check is axis 4. A fresh slate REPLACES the stored one, so a dirty node's
	stale entries are dropped by the same call that gives it somewhere to write. ]]
function measure_reuse.adopt(
	store: Store,
	node: any,
	reusable: boolean,
	containerW: number,
	containerH: number
): ({ [string]: any }, boolean)
	local id = node.id
	local scoped = node.containerRelativeInside == true
	if reusable then
		local prev = store.byId[id]
		if prev ~= nil and (not scoped or store.ctr[id] == `{containerW}|{containerH}`) then
			return prev, true
		end
	end
	local fresh: { [string]: any } = {}
	store.byId[id] = fresh
	store.n[id] = 0
	if scoped then
		store.ctr[id] = `{containerW}|{containerH}`
	end
	return fresh, false
end

-- One more distinct offer for this node. Called by `solver.measure` immediately
-- BEFORE it writes a key the slate does not already hold, so the wipe cannot throw
-- away the entry it is about to make.
function measure_reuse.note(store: Store, id: string, slate: { [string]: any })
	local n = (store.n[id] or 0) + 1
	if n > KEY_CAP then
		table.clear(slate)
		n = 1
	end
	store.n[id] = n
end

measure_reuse.KEY_CAP = KEY_CAP

return measure_reuse
