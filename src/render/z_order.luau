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
}

function z_order.new(deps: Deps)
	local adapter, root = deps.adapter, deps.root
	local handles, lastZ, hitLift = deps.handles, deps.lastZ, deps.hitLift

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

	local function sync()
		if adapter.setZOrder == nil then
			return
		end
		local z = 0
		local zMetrics = deps.metrics()
		local function walkZ(node: any)
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
			for _, child in orderedChildren(node) do
				walkZ(child)
			end
		end
		walkZ(root.node)
	end

	return { orderedChildren = orderedChildren, sync = sync }
end

return z_order
