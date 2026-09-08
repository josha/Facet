--!strict
-- Matches a pure permutation against a prior measurement index before any writes.
-- The caller owns offer/stamp/scope validation. Dirty rows and unsupported prior
-- answers refuse the entire permutation, so mixed frames use the ordinary solver.
local permutation = {}
local ENABLED = true -- experiment arm: false retains validation but serves no answer

function permutation.order(children: any, ids: any, n: number?, dirty: any): any
	if ids == nil or dirty == nil or n ~= #children then
		return nil
	end
	local index, order = {}, {}
	for i = 1, n :: number do
		local id = ids[i]
		if id == nil or index[id] ~= nil then
			return nil
		end
		index[id] = i
	end
	local moved = false
	for i, child in children do
		local old = index[child.id]
		if old == nil or dirty[child.id] == true then
			return nil
		end
		index[child.id] = nil
		order[i] = old
		moved = moved or old ~= i
	end
	return if ENABLED and moved then order else nil
end

function permutation.remap(values: any, order: any): any
	local out = {}
	for i, old in order do
		out[i] = values[old]
	end
	return out
end

return permutation
