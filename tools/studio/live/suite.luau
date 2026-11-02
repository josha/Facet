--!strict

export type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local function new(): ({ Case }, (string, { string }, (any) -> ()) -> ())
	local cases: { Case } = {}
	local function add(id: string, contracts: { string }, run: (any) -> ())
		table.insert(cases, { id = id, contracts = contracts, run = run })
	end
	return cases, add
end

return { new = new }
