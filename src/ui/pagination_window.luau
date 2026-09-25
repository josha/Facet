--!strict
export type Role = "boundary" | "neighbor" | "current"
export type Entry = { page: number, role: Role }

return function(current: number, count: number, sibling: number, boundary: number): { Entry }
	local roles: { [number]: Role } = {}
	local function add(page: number, role: Role)
		if page >= 1 and page <= count and roles[page] == nil then
			roles[page] = role
		end
	end
	for page = 1, math.min(boundary, count) do
		add(page, "boundary")
	end
	for page = math.max(count - boundary + 1, boundary + 1), count do
		add(page, "boundary")
	end
	local startRun = math.max(math.min(current - sibling, count - boundary - sibling * 2 - 1), boundary + 2)
	local endRun = math.min(math.max(current + sibling, boundary + sibling * 2 + 2), count - boundary - 1)
	for page = startRun, endRun do
		add(page, if page == current then "current" else "neighbor")
	end
	if startRun == boundary + 2 then
		add(boundary + 1, "boundary")
	end
	if endRun == count - boundary - 1 then
		add(count - boundary, "boundary")
	end
	roles[current] = "current"
	local out: { Entry } = {}
	for page, role in roles do
		local entry: Entry = { page = page, role = role :: Role }
		table.insert(out, entry)
	end
	table.sort(out, function(a: Entry, b: Entry): boolean
		return a.page < b.page
	end)
	return out
end
