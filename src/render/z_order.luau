--!strict
--[[ THE EXPLICIT PAINT-ORDER WALK, lifted out of `render/renderer.luau` on
	2026-09-04 (Plan C, ruling T5-2) because that file stood 40 characters from the
	campaign's 197,500 STOP line with T8 and T9 still to spend room there.

	WHY THIS BLOCK. It is the largest run in the renderer that is ONE subject — "who
	paints above whom" — and it reaches for nothing the renderer owns except two
	records it already hands to five other modules by reference. The alternative
	candidate, the parked-props pair, is 2,226 characters against this one's 3,185
	and would have left the file above the line it had to clear.

	WHAT IT IS FOR. Flat sibling rendering paints in z-order, and instance creation
	order is NOT deterministic across a structural sync (live-found defect
	2026-07-19), so z is assigned explicitly from a tree walk. `lastZ` itself stays
	declared in the renderer beside `rectOf`, because the drag registry reads it as
	the paint-order tie-break for overlapping drop targets.

	AUTHORED PAINT ORDER, WITHIN THE PARENT'S STACKING SCOPE. Siblings are visited in
	`(zIndex or 0, declaration order)` order, so a lifted node — a drag ghost, a
	toast — paints above the siblings it was declared before, and its whole SUBTREE
	travels with it because the walk is depth-first over one counter. Nothing crosses
	a scope: a child's counter is always higher than its parent's, whatever its
	zIndex, which is why lifting across surfaces stays structural (the presenter's
	display order).

	The declaration index is part of the key rather than trusted to `table.sort`:
	Luau's sort is NOT stable, so ties between two zero-index siblings would
	otherwise be free to swap between solves — and z-order churn is exactly the
	non-determinism the explicit z walk exists to remove.

	ONE-WAY, BY THE LEDGER'S OWN TEST. It reads `handles` and `lastZ` — two maps the
	renderer declares once, clears in place and never rebinds — plus `root`, the
	mount handle, which is likewise never reassigned; the adapter; the lift; and one
	function for the metrics snapshot. NO reassigned upvalue of the host crosses this
	boundary, it names no renderer symbol, and its two requires (`./authority`,
	`./layout_node`) are leaves the renderer requires as well.
	`tests/z_order_seam.spec.luau` is that property mechanised. ]]
local authority = require("./authority")
local layoutNode = require("./layout_node")

local effectiveHitFloor = layoutNode.effectiveHitFloor

local z_order = {}

export type Deps = {
	adapter: any,
	-- the mount handle, BY REFERENCE: `root.node` is re-read per walk because a
	-- structural sync replaces the tree under it
	root: any,
	handles: { [string]: any },
	lastZ: { [string]: number },
	-- `render/hit_lift`: `touches` and `order`, the overhang lift's own ordering
	hitLift: any,
	-- the active ThemeSnapshot, asked once per walk rather than once per node
	metrics: () -> any,
	--[[ `render/render_stats`, for `zPasses`/`zVisits` — the SEVENTH field, and the
		one this record's own seam spec warns about, so it carries its reason: two z
		walks can run in one frame (this one, and the commit's hit-lift re-run), and a
		LAST capture cannot tell a caller which one it is holding. A cumulative pair
		read as a delta can, and the module is the only thing that knows the count. ]]
	stats: any,
}

function z_order.new(deps: Deps)
	local adapter, root = deps.adapter, deps.root
	local handles, lastZ, hitLift = deps.handles, deps.lastZ, deps.hitLift
	local stats = deps.stats

	-- ...and the SECOND KEY, only when something asked for it: a branch whose hit
	-- expander overhangs into a later sibling is walked AFTER that sibling
	-- (`src/render/hit_lift.luau` owns the rule and the ordering).
	local function orderedChildren(node: any): { any }
		local children = node.children
		if children == nil or #children < 2 then
			return children or {}
		end
		local lifted = hitLift.touches(children)
		local anyLift = false
		for _, child in children do
			if child.props ~= nil and type(child.props.zIndex) == "number" and child.props.zIndex ~= 0 then
				anyLift = true
				break
			end
		end
		if not anyLift then
			-- the overwhelmingly common case allocates nothing
			return if lifted then hitLift.order(children) else children
		end
		local indexed: { { node: any, index: number, z: number } } = table.create(#children)
		for index, child in children do
			local z = if child.props ~= nil and type(child.props.zIndex) == "number" then child.props.zIndex else 0
			table.insert(indexed, { node = child, index = index, z = z })
		end
		table.sort(indexed, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.index < b.index
		end)
		local out: { any } = table.create(#children)
		for _, entry in indexed do
			table.insert(out, entry.node)
		end
		return if lifted then hitLift.order(out) else out
	end

	--[[ WHAT THE WALK REMEMBERS, so a bounded structural sync can SKIP a subtree
		instead of renumbering it (Plan C, C5). Per path: the counter on ENTERING the
		node the last time its subtree was assigned, and the number of increments that
		subtree consumed. Both are cleared by `forget`, which the renderer calls from
		its removal sweep beside `lastZ[path] = nil`.

		THE INVARIANT THE ENGINE ACTUALLY CONSUMES, and it is not the integers.
		`ZIndexBehavior.Sibling` orders SIBLINGS within a parent and lets the hierarchy
		carry the rest, so only each parent's children's relative order is observable;
		and the drag registry reads `lastZ` as a paint-order TIE-BREAK between
		overlapping drop targets (`render/drag_bridge`), a comparison, never a value.
		Nothing in the framework reads an absolute z. So the walk owes exactly:

		  (Z1)  z STRICTLY INCREASES over the walk's own visit order, and
		  (Z2)  every number it hands out is distinct, so an expander's reserved
		        `z - 1` (below) is nobody else's z.

		GAPS ARE FREE. A skip keeps a subtree's existing numbers and jumps the counter
		to the last of them, so the kept run stays above everything assigned before it
		and below everything assigned after — (Z1) is MAINTAINED by the skip, not
		merely tolerated. It holds for a REORDER too: `[A,B,C]` -> `[C,A,B]` meets C
		first with `z <= zIn[C]`, keeps C's old (largest) numbers, jumps past them, and
		renumbers A and B ABOVE C, which is the new document order. A removal is the
		pure case: everything after the hole keeps its numbers and NOT ONE WRITE IS
		OWED. This is why `tests/zorder_bounded.spec` pins the two arms' RANKING rather
		than their values — a value diff would also pass a walk that assigned the right
		numbers in the wrong order.

		WHEN A SUBTREE MAY BE SKIPPED: when no dirty root lies at or below it. A
		subtree's assignment is a function of the set and order of the paths in it and
		of each node's `zIndex` and the hit-lift order. The first can only change
		through `mount` replacing a `children` array, which pushes a `structure` entry
		at that parent — so that parent is one of `roots`, or an ancestor entry covers
		it, or `render/structural_scope.roots` refuses and hands this walk `nil`.
		`zIndex` is `reactive = false` in the schema, so it can only arrive on a new
		node under a replaced `children` array — the same case; and a hit-lift change
		re-runs this walk WHOLE-TREE on the frame it moves. Handle creation and
		departure need no separate term: a path can only appear or leave that way.

		THE COMPACTION LATCH, AND WHY IT IS RELATIVE. Gaps are never reclaimed, so a
		surface that only ever takes bounded syncs drifts the counter upward for as
		long as it churns — one add/remove pair on a 250-row list moves the high-water
		mark by a row's worth and gives none of it back — and `ZIndex` is an int32. So
		the walk remembers where the last WHOLE-TREE walk ended, which is a true node
		count, and a bounded walk that ends past twice it makes the NEXT one whole-tree.
		That is the pre-C5 cost, amortised over the hundreds of churn steps it takes to
		earn, and it keeps the numbers within a small factor of the tree rather than
		merely under an int32 ceiling — which is also what makes the guard DRIVABLE by a
		test instead of a comment nobody can reach (`tests/zorder_bounded.spec`). ]]
	local zIn: { [string]: number } = {}
	local zSpan: { [string]: number } = {}
	local compactNext = false
	-- where the last whole-tree walk's counter ended, and the slack a bounded one may
	-- add before it has to be paid back. The constant is a FLOOR for a small tree,
	-- where twice a handful of nodes would compact on the first churn.
	local zHigh = 0
	local Z_COMPACT_SLACK = 64

	local function forget(path: string)
		zIn[path] = nil
		zSpan[path] = nil
	end

	-- every path from `path` up to the mount root, which is the set the walk has to
	-- DESCEND through to reach a root; everything else it may skip
	local function markToRoot(forced: { [string]: boolean }, path: string)
		forced[path] = true
		local cut = string.find(path, "/[^/]*$")
		while cut ~= nil and cut > 1 do
			path = string.sub(path, 1, cut - 1)
			if forced[path] then
				return
			end
			forced[path] = true
			cut = string.find(path, "/[^/]*$")
		end
	end

	-- `roots` is the bounded structural sync's root list, or nil for the whole tree
	-- (the hit-lift re-run, the initial render, a sync no delta could bound). Publishes
	-- the NODES IT TOUCHED, skips included, into `zVisits`, and counts itself.
	local function sync(roots: { { path: string, node: any } }?)
		if adapter.setZOrder == nil then
			return
		end
		local forced: { [string]: boolean }? = nil
		if roots ~= nil and not compactNext then
			forced = {}
			for _, r in roots do
				markToRoot(forced :: { [string]: boolean }, r.path)
			end
		end
		compactNext = false
		local z = 0
		local visited = 0
		local zMetrics = deps.metrics()
		local function walkZ(node: any)
			visited += 1
			if forced ~= nil and not forced[node.path] then
				local was, span = zIn[node.path], zSpan[node.path]
				if was ~= nil and span ~= nil and z <= was then
					z = was + span
					return
				end
			end
			local entered = z
			-- A HOST WITH A HIT EXPANDER OWNS THE COUNTER BELOW IT TOO. The adapter
			-- paints the expander at `hostZ - 1`, and without this reservation that
			-- number belongs to whatever node happened to be walked immediately
			-- before — a TIE, which the engine breaks by insertion order, i.e. by
			-- exactly the non-determinism this explicit walk exists to remove. It is
			-- also what makes the overhang lift land: a host lifted one position past
			-- a leaf sibling would otherwise put its expander level with it, and
			-- level is not above (measured on `keyboard_navigation`, whose rows are
			-- leaves: Row1 at z 37 over Row2 at z 36 left the expander at 36).
			-- THE CLASS, NOT THE CURRENT STATE (NM-H4a, live 2026-08-17): reading
			-- `lastHitRects` made this band a function of HISTORY. See
			-- tests/hit_expander_z_band.spec.
			if effectiveHitFloor(node.class, zMetrics) ~= nil then
				z += 1
			end
			z += 1
			if handles[node.path] ~= nil and lastZ[node.path] ~= z then
				authority.assertWrite("common", "zIndex", "layout")
				adapter.setZOrder(handles[node.path], z)
				lastZ[node.path] = z
			end
			local kids = orderedChildren(node)
			for _, child in kids do
				walkZ(child)
			end
			--[[ ...AND THE MEMO, FOR A PARENT ONLY. Skipping a childless node saves
				nothing — the probe costs what the visit costs — so a leaf earns no entry,
				and on `battle_hud` that is most of the surface. MEASURED, and it is not a
				micro-optimisation: with an entry per node the two maps hold ~10,200 live
				entries against 5,127 layout nodes, and `battle_hud setState` — which
				allocates 1.13 MB a step and therefore collects the most — ran +16 % on an
				arm where every counter was byte-identical and no z walk ran at all. A
				control arm carrying the whole C5 change EXCEPT these two maps sat on the
				base, which is what named them.

				WRITTEN ONLY WHEN IT MOVED, the same guard the z write above uses and for
				the same reason: a blind hash write per visited node was a real charge on
				the commit's own walks (C4, fix round 1). ]]
			if #kids > 0 then
				if zIn[node.path] ~= entered then
					zIn[node.path] = entered
				end
				if zSpan[node.path] ~= z - entered then
					zSpan[node.path] = z - entered
				end
			end
		end
		walkZ(root.node)
		if forced == nil then
			zHigh = z
		end
		compactNext = z > zHigh * 2 + Z_COMPACT_SLACK
		stats.zPasses += 1
		stats.zVisits += visited
	end

	return { orderedChildren = orderedChildren, sync = sync, forget = forget }
end

return z_order
