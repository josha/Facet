--!strict
-- Matches a pure permutation against a prior measurement index before any writes.
-- The caller owns offer/stamp/scope validation. Dirty rows and unsupported prior
-- answers refuse the entire permutation, so mixed frames use the ordinary solver.
local permutation = {}
local REMOVAL = true -- C validates the subset but declines removal reuse
local ENABLED = true -- experiment arm: false retains validation but serves no answer

function permutation.order(
	children: any,
	ids: any,
	n: number?,
	dirty: any,
	cachedIndex: any?,
	allowRemoval: boolean?
): any
	if ids == nil or dirty == nil or n == nil or (n ~= #children and not (allowRemoval and n > #children)) then
		return nil
	end
	local index, order = if cachedIndex ~= nil then table.clone(cachedIndex) else {}, {}
	if cachedIndex == nil then
		for i = 1, n :: number do
			local id = ids[i]
			if id == nil or index[id] ~= nil then
				return nil
			end
			index[id] = i
		end
	end
	local removed = n ~= #children
	local moved = removed
	for i, child in children do
		local old = index[child.id]
		if old == nil or dirty[child.id] == true then
			return nil
		end
		index[child.id] = nil
		order[i] = old
		moved = moved or old ~= i
	end
	return if ENABLED and moved and (not removed or REMOVAL) then order else nil
end

function permutation.remap(values: any, order: any): any
	local out = {}
	for i, old in order do
		out[i] = values[old]
	end
	return out
end

return permutation
