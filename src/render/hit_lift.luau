--!strict
--[[ THE HIT-EXPANDER OVERHANG LIFT — the paint order a touch floor needs to be
	DELIVERABLE.

	A control under the touch floor gets an invisible hit expander from
	`setHitRect`, and the adapter derives `expander.ZIndex = hostZ - 1`. The `- 1`
	is load-bearing: hover is wired as `MouseEnter`/`MouseLeave` on the HOST
	(`src/client/screen_pointer.luau`), so an expander above its own host swallows
	hover and the cursor hint over the host's own rect.

	The defect that follows: the engine delivers input to the TOPMOST interactive
	object only (a `GuiButton` SINKS it), and paint order is one depth-first
	counter, so a sibling walked LATER always outranks the expander. Where the
	expander overhangs INTO that sibling it advertises a band it cannot deliver.
	Measured on `table_columns`: a 44px divider band delivered 26px, and the outer
	18px belonged to the next column's header — a drag there did nothing and a tap
	there sorted a column the player never touched
	(artifacts/hit-expander-overhang/corpus-measurement.md).

	Raising the expander alone is UNSATISFIABLE: it needs `expanderZ < hostZ`
	(hover, above) and `expanderZ > neighbourZ`, while `neighbourZ > hostZ`
	always. No integer is both. So the HOST is lifted, with its expander, past the
	siblings that expander reaches into — the satisfiable form of the same rule,
	and the reason this is a paint-order module rather than an adapter change.

	THE QUALIFIER, AND IT IS NOT OPTIONAL: outrank NON-EXPANDER siblings only;
	expander-vs-expander is left to the existing host z order. Two neighbouring
	sub-floor controls each carry a floor and those floors overlap EACH OTHER
	(measured: `hud`, host `R1`, two 44x44 expanders overlapping by 5%) — under an
	unqualified rule each would want to outrank the other in that sliver, which is
	circular for exactly the population the rule governs. Only a real, painted,
	input-sinking rect creates a lift; another expander's invisible rect never
	does. The caller supplies that census (`sinks`).

	...AND IT STOPS AT THE HOST. A target the host's own PAINTED rect already
	overlaps is not something the expander reaches out to — it is something the
	host is drawn on top of, and the paint order between them stays the authored
	one. `table_columns` is the case: the 8px divider paints INSIDE its header
	cell, whose own 28px-tall floor overhangs it, and lifting the cell over the
	divider by that overlap would bury the divider under the button it exists to
	drag.

	WHY THE PAINT REORDER IS SAFE — measured, not argued: across 48 of 53
	scenarios mounted on a real engine, 86 hit expanders and 82 overhang relations,
	the painted-rect overlaps among them number ZERO. No host this lifts has a
	painted rect intersecting the sibling it is lifted over, so the reorder is
	invisible by construction — which is also what the clause above guarantees
	going forward. The rule therefore ships unqualified across all four
	`minHitSize` classes: no `Grip` special case.

	DETERMINISM. Every constraint points from an EARLIER sibling to a LATER one in
	the base (zIndex, declaration) order, so the graph is a DAG by construction and
	the stable topological pass always terminates. It is computed against the BASE
	order and never against the applied one — feeding the result back in would let
	a tiled list (every row sub-floor, each floor reaching into its neighbour) flip
	its order on every solve.

	Public interface (one lift per attached surface; the renderer owns it):
	  hit_lift.new() -> Lift
	  lift.refresh(rects, hitRects, sinks, parentNodeOf, hidden) -> changed: boolean
	  lift.order(children) -> children, reordered where the rule asks
	  lift.touches(children) -> boolean   (is any of these constrained at all)
	  lift.clear()

	Depends on nothing: every input is an argument and every value is data, so it
	is testable without an engine (`tests/hit_expander_overhang.spec.luau`).
]]

local hit_lift = {}

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

export type Lift = {
	any: boolean,
	after: { [string]: { [string]: boolean } },
	refresh: (rects: any, hitRects: any, sinks: any, parentNodeOf: any, hidden: any) -> boolean,
	order: (children: { any }) -> { any },
	touches: (children: { any }) -> boolean,
	clear: () -> (),
}

function hit_lift.new(): Lift
	local self: any = { any = false, after = {} }
	local key = ""
	-- the host's ancestor chain, keyed by parent path, so the target's own walk up
	-- recognises the first shared parent. One reused table: `branchPair` runs once
	-- per overhang relation and there are single digits of those per surface.
	local chain: { [string]: string } = {}

	-- the two children of the nearest common parent that carry these two paths —
	-- (host's branch, target's branch, that parent). All nil when one is an
	-- ancestor of the other, which is one branch and so nothing to lift.
	local function branchPair(parentNodeOf: any, hostPath: string, targetPath: string): (string?, string?, any)
		table.clear(chain)
		local cur = hostPath
		while true do
			local parent = parentNodeOf[cur]
			if parent == nil then
				break
			end
			chain[parent.path] = cur
			cur = parent.path
		end
		cur = targetPath
		while true do
			local parent = parentNodeOf[cur]
			if parent == nil then
				return nil, nil, nil
			end
			local mine = chain[parent.path]
			if mine ~= nil then
				if mine == cur then
					return nil, nil, nil
				end
				return mine, cur, parent
			end
			cur = parent.path
		end
	end

	--[[ ONE PASS over the hit expanders this solve asked for, against the paths
		that can SINK a press:

		  · a target the expander overlaps PAST its host, and that is walked LATER,
		    is a sibling the expander cannot reach past — so the branch carrying the
		    HOST is marked to be walked after the branch carrying the TARGET;
		  · the two branches are the children of their nearest COMMON parent, so the
		    lift moves whole subtrees and a `zIndex` scope stays intact;
		  · a target inside the host's own branch is not a competitor (it rides the
		    same lift), and neither is another expander (the qualifier).

		Returns whether the constraint set CHANGED, which is what makes this cheap:
		the caller's z walk re-runs only on a real change, never per solve. ]]
	function self.refresh(rects: any, hitRects: any, sinks: any, parentNodeOf: any, hidden: any): boolean
		local next: { [string]: { [string]: boolean } } = {}
		local keys: { string } = {}
		for hostPath, hit in hitRects do
			local hostEntry = rects[hostPath]
			for targetPath in sinks do
				local entry = if targetPath == hostPath or hostEntry == nil then nil else rects[targetPath]
				if
					entry ~= nil
					and hidden[targetPath] ~= true
					and overlaps(hit, entry.rect)
					and not overlaps(hostEntry.rect, entry.rect)
				then
					local mine, theirs, parent = branchPair(parentNodeOf, hostPath, targetPath)
					if mine ~= nil and theirs ~= nil then
						-- WHO IS WALKED LATER, in the base (zIndex, declaration) order —
						-- the only order this reads (see the determinism note above). A
						-- target already walked EARLIER is one the expander outranks
						-- today, so it constrains nothing.
						local mineZ, mineIndex, theirsZ, theirsIndex = 0, 0, 0, 0
						for index, child in parent.children do
							if child.path == mine or child.path == theirs then
								local z = if child.props ~= nil and type(child.props.zIndex) == "number"
									then child.props.zIndex
									else 0
								if child.path == mine then
									mineZ, mineIndex = z, index
								else
									theirsZ, theirsIndex = z, index
								end
							end
						end
						if if mineZ ~= theirsZ then mineZ < theirsZ else mineIndex < theirsIndex then
							local set = next[mine]
							if set == nil then
								set = {}
								next[mine] = set
							end
							if set[theirs] == nil then
								set[theirs] = true
								table.insert(keys, `{mine}>{theirs}`)
							end
						end
					end
				end
			end
		end
		table.sort(keys)
		local nextKey = table.concat(keys, "|")
		if nextKey == key then
			return false
		end
		key = nextKey
		self.after = next
		self.any = #keys > 0
		return true
	end

	function self.touches(children: { any }): boolean
		if not self.any then
			return false
		end
		for _, child in children do
			if self.after[child.path] ~= nil then
				return true
			end
		end
		return false
	end

	-- A STABLE TOPOLOGICAL PASS rather than a sort key: the constraint is pairwise,
	-- and a chain of them — every row of a tiled list reaching into the next — has
	-- no total key. It terminates because every edge points from an earlier sibling
	-- to a later one (see the determinism note above).
	function self.order(children: { any }): { any }
		local n = #children
		local out: { any } = table.create(n)
		local taken: { boolean } = table.create(n, false)
		local emitted: { [string]: boolean } = {}
		for _ = 1, n do
			local pick: number? = nil
			for i = 1, n do
				if not taken[i] then
					local after = self.after[children[i].path]
					local ready = true
					if after ~= nil then
						for target in after do
							if not emitted[target] then
								ready = false
								break
							end
						end
					end
					if ready then
						pick = i
						break
					end
				end
			end
			if pick == nil then
				-- unreachable on an acyclic set; emitting the first one left is what
				-- keeps a future edge that IS cyclic a wrong paint order rather than a
				-- hung render
				for i = 1, n do
					if not taken[i] then
						pick = i
						break
					end
				end
			end
			local at = pick :: number
			taken[at] = true
			emitted[children[at].path] = true
			table.insert(out, children[at])
		end
		return out
	end

	function self.clear()
		table.clear(self.after)
		self.any = false
		key = ""
	end

	return self :: Lift
end

return hit_lift
