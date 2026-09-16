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
	allowRemoval: boolean?,
	allowInsert: boolean?,
	allowUnrecorded: boolean?
): any
	local inserted = allowInsert == true and n ~= nil and n < #children
	if
		ids == nil
		or dirty == nil
		or n == nil
		or (n ~= #children and not (allowRemoval and n > #children) and not inserted)
	then
		return nil
	end
	local index, order = if cachedIndex ~= nil then table.clone(cachedIndex) else {}, {}
	local recorded = n
	if cachedIndex == nil then
		recorded = 0
		for i = 1, n :: number do
			local id = ids[i]
			if id == nil and allowUnrecorded then
				continue
			end
			if id == nil or index[id] ~= nil then
				return nil
			end
			index[id] = i
			recorded += 1
		end
	end
	local removed = n > #children
	local moved = removed or inserted
	local survivors, last = 0, 0
	for i, child in children do
		local old = index[child.id]
		if old == nil then
			-- Zero means measure a new row normally; survivors must keep their order.
			if not inserted then
				return nil
			end
			old = 0
		else
			survivors += 1
			if old == 0 or dirty[child.id] == true or (inserted and old <= last) then
				return nil
			end
		end
		last = if old > 0 then old else last
		-- Keep a consumed marker so duplicate ids cannot masquerade as new rows.
		index[child.id] = 0
		order[i] = old
		moved = moved or old ~= i
	end
	if inserted and survivors ~= recorded then
		return nil
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
