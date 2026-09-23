--!strict
--[[ THE HORIZONTAL ARROWS OF ONE SURFACE, bound only while something needs them.

	Grouped screens own the horizontal axis (verifier F2): Left/Right + d-pad
	become real directions instead of Adjust. So does a screen that ADOPTS a
	chrome strip (F1): the composed scope is grouped even when the surface's own
	derivation is one flat ring, so without this the pad could reach the strip
	and not walk it.

	THE ACTION ALWAYS EXISTS; ITS KEYS DO NOT. An unbound action costs nothing and
	fires nothing — the same deal `traverse` takes for Tab — so a flat surface
	that needs no horizontal direction shadows no arrow key.

	LIVE, BOTH WAYS. A grouped upgrade is permanent (`upgrade()`), but chrome
	participation follows the graph's `chromeLive`: an EMPTY chrome host (a
	notification strip with no rows) binds nothing, a row arriving binds the keys
	on every screen that adopts it — including one presented while the host was
	empty — and the last row leaving releases them again. ]]
local observeChange = require("../core/on_change")

local navigate_h = {}

-- (the action, the focus graph, the surface scope, grouped now?) -> (upgrade, bound?)
function navigate_h.attach(action: any, graph: any, scope: any, grouped: boolean): (() -> (), () -> boolean)
	local bindings: { any } = {}
	local function sync()
		local want = grouped or (graph.chromeLive ~= nil and graph.chromeLive:peek() == true)
		if want and #bindings == 0 then
			table.insert(bindings, action.bind({ keyCode = "Left", direction = -1 }))
			table.insert(bindings, action.bind({ keyCode = "Right", direction = 1 }))
			table.insert(bindings, action.bind({ keyCode = "DPadLeft", direction = -1 }))
			table.insert(bindings, action.bind({ keyCode = "DPadRight", direction = 1 }))
			-- Thumbstick1 horizontal (matrix §D.5): the x component drives the
			-- horizontal axis, same latch as the vertical
			table.insert(bindings, action.bindAxis({ axis = "Thumbstick1", component = "x" }))
		elseif not want and #bindings > 0 then
			for _, binding in bindings do
				binding.remove()
			end
			table.clear(bindings)
		end
	end
	sync()
	if graph.chromeLive ~= nil then
		observeChange(scope, graph.chromeLive, sync)
	end
	return function()
		grouped = true
		sync()
	end, function(): boolean
		return #bindings > 0
	end
end

return navigate_h
