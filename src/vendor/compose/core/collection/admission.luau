--!strict

export type Result = {
	order: { number }?,
	admitted: number,
	pending: number,
}

local function select(count: number, limit: number?, before: (a: number, b: number) -> boolean): Result
	if limit == nil or count <= limit then
		return { order = nil, admitted = count, pending = 0 }
	end
	local order: { number } = table.create(count)
	for index = 1, count do
		order[index] = index
	end
	table.sort(order, before)
	return { order = order, admitted = limit, pending = count - limit }
end

return select
