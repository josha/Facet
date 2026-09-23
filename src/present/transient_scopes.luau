--!strict
--[[ TRANSIENT-POPUP FOCUS TRAP/RESTORE (matrix §B PopupButton; `transientScope`),
	moved out of presenter.luau's makeHandle.

	While a contribution's `transientScope.active` is true, focus is TRAPPED within
	`rootPath`'s subtree (default: the contribution's own mounted path, so the
	trigger stays the scope's entry) through the focus graph's own trap/restore
	machinery; on deactivation focus RESTORES to the pre-activation path. `sync`
	runs from refresh after the base focus map, so the pushed order always reflects
	the CURRENT mounted popup.

	A PUSHED TRAP BELONGS TO ITS CONTRIBUTION'S IDENTITY, NOT ITS PATH (phase6 P6a
	item 13). The contribution list is replaced before `sync` visits it, so a trap
	whose contribution left the tree (a recycled grid cell, a closed region) was
	never visited again and stranded focus in a scope with no members; a new control
	mounted at the same path is a different owner of a different trap. `prune`
	therefore runs right after the contributions are re-discovered and BEFORE the
	base focus map is rebuilt, removing every trap whose recorded bundle is no longer
	mounted at its path — so the path the trap restores is repaired against the live
	tree by the same refresh. ]]
local focusMap = require("./focus_map")

local transientScopes = {}

function transientScopes.bind(handle: any, graph: any, contributions: { any }, rootNode: () -> any)
	local pushed: { [string]: any } = {} -- path -> the bundle that pushed its trap
	local stack: { string } = {} -- push order: released top first, so no trap restores into a dead one
	local function name(path: string): string
		return `__transient__{path}`
	end
	local function release(path: string)
		graph.removeScope(name(path)) -- a top trap restores focus to its trigger
		pushed[path] = nil
		table.remove(stack, table.find(stack, path) :: number)
	end

	function handle.pruneTransientScopes()
		if next(pushed) == nil then
			return
		end
		local live: { [string]: any } = {}
		for _, c in contributions do
			live[c.path] = c.bundle
		end
		for i = #stack, 1, -1 do
			local path = stack[i]
			if live[path] ~= pushed[path] then
				release(path)
			end
		end
	end

	function handle.syncTransientScopes()
		for _, c in contributions do
			local ts = c.bundle.transientScope
			if ts ~= nil and ts.active ~= nil then
				local wantActive = ts.active:peek() == true
				if wantActive then
					local sub = focusMap.nodeAt(rootNode(), ts.rootPath or c.path)
					local order: { string } = {}
					if sub ~= nil then
						focusMap.focusOrder(sub, order)
					end
					-- ranked against the popup's own subtree, the tree its order was
					-- walked from (the traversal-order ledger)
					local rank = if sub ~= nil then focusMap.traversalRank(sub, order, nil) else nil
					if pushed[c.path] == nil then
						-- pushScope records the current focus for restore and enters at
						-- order[1]
						graph.pushScope({ name = name(c.path), trap = true, order = order, traversalRank = rank })
						pushed[c.path] = c.bundle
						table.insert(stack, c.path)
					else
						-- rows may churn while open: keep the trap order current
						graph.setOrder(name(c.path), order, rank)
					end
				elseif pushed[c.path] ~= nil then
					release(c.path)
				end
			end
		end
	end

	-- dismissing a screen with an OPEN popup must not orphan its trap scope
	function handle.clearTransientScopes()
		for i = #stack, 1, -1 do
			release(stack[i])
		end
	end
end

return transientScopes
