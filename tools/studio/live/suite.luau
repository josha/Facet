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

local function interactive(cases: { Case })
	local function interactive(
		id: string,
		contracts: { string },
		setup: (any) -> any,
		steps: { [string]: (any, any) -> () }
	)
		table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
	end
	return interactive
end

local function planned(cases: { Case })
	local function interactive(
		id: string,
		contracts: { string },
		plan: string,
		setup: (any) -> any,
		steps: { [string]: (any, any) -> () }
	)
		table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
	end
	return interactive
end

return { new = new, planned = planned, interactive = interactive }
