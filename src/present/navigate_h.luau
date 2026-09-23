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

-- ONE OWNER OF THESE KEYS. A focused value control that takes the arrows
-- (`adjustAxis`, or a flat-screen legacy Adjust target) SUSPENDS them here
-- instead of removing binding objects this module tracks: a stale handle
-- removed twice, or a rebinding nobody tracks, left the arrows bound on a flat
-- screen after the chrome went away (and doubly bound when it came back).
-- The Thumbstick1 axis is never suspended — no Adjust binds it.

-- (the action, the focus graph, the surface scope, grouped now?)
--   -> (upgrade, bound?, suspend(on))
function navigate_h.attach(
	action: any,
	graph: any,
	scope: any,
	grouped: boolean
): (() -> (), () -> boolean, (boolean) -> ())
	local keys: { any } = {}
	local stick: any = nil
	local suspended = false
	local function sync()
		local want = grouped or (graph.chromeLive ~= nil and graph.chromeLive:peek() == true)
		if want and stick == nil then
			-- Thumbstick1 horizontal (matrix §D.5): the x component drives the
			-- horizontal axis, same latch as the vertical
			stick = action.bindAxis({ axis = "Thumbstick1", component = "x" })
		elseif not want and stick ~= nil then
			stick.remove()
			stick = nil
		end
		local wantKeys = want and not suspended
		if wantKeys and #keys == 0 then
			table.insert(keys, action.bind({ keyCode = "Left", direction = -1 }))
			table.insert(keys, action.bind({ keyCode = "Right", direction = 1 }))
			table.insert(keys, action.bind({ keyCode = "DPadLeft", direction = -1 }))
			table.insert(keys, action.bind({ keyCode = "DPadRight", direction = 1 }))
		elseif not wantKeys and #keys > 0 then
			for _, binding in keys do
				binding.remove()
			end
			table.clear(keys)
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
		return stick ~= nil
	end, function(on: boolean)
		suspended = on
		sync()
	end
end

return navigate_h
