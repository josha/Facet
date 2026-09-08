--!strict
-- Per-surface coordination, owned by the lifetime of the existing lastZ table.
-- A drag registry needs globally comparable numbers even across real row hosts.
local scope = {}
function scope.of(lastZ: any): any
	local state = getmetatable(lastZ)
	if state == nil then
		state = { global = false }
		setmetatable(lastZ, state)
	end
	return state
end
function scope.requireGlobal(lastZ: any)
	local state = scope.of(lastZ)
	if not state.global then
		state.global = true
		if state.restore ~= nil then
			local ok, err = pcall(state.restore)
			if not ok then
				state.global = false
				error(err, 0)
			end
		end
	end
end
return scope
