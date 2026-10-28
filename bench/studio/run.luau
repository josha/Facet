--!strict

local Types = require("../comparison/types")
local Workloads = require("../comparison")
local World = require("./world")

export type Lane = { median: number, samples: { number } }
export type Row = {
	id: string,
	iterations: number,
	status: string,
	facet: Lane?,
	plain: Lane?,
}

local WARMUP, SAMPLES = 2, 9

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	return sorted[(#sorted + 1) // 2]
end

local function sample(workload: Types.Workload, lane: Types.Lane, parent: Instance): (number, string)
	local world = World(parent)
	local scene = workload.prepare((world :: unknown) :: Types.World, lane)
	local started = os.clock()
	for index = 1, workload.iterations do
		scene.step(index)
	end
	local elapsed = os.clock() - started
	local snapshot = scene.snapshot()
	scene.stop()
	world.dispose()
	return elapsed * 1e6, snapshot
end

local function measure(workload: Types.Workload, parent: Instance): (Lane, Lane, boolean)
	for _ = 1, WARMUP do
		sample(workload, "plain", parent)
		sample(workload, "facet", parent)
	end
	local plain: { number }, facet: { number } = {}, {}
	local same = true
	for _ = 1, SAMPLES do
		local plainTime, plainSnapshot = sample(workload, "plain", parent)
		local facetTime, facetSnapshot = sample(workload, "facet", parent)
		table.insert(plain, plainTime)
		table.insert(facet, facetTime)
		same = same and plainSnapshot == facetSnapshot
	end
	return { median = median(plain), samples = plain }, { median = median(facet), samples = facet }, same
end

return function(parent: Instance, filter: string?): { Row }
	local rows: { Row } = {}
	for _, workload in Workloads do
		if filter ~= nil and string.find(workload.id, filter, 1, true) == nil then
			continue
		end
		local row: Row = { id = workload.id, iterations = workload.iterations, status = "measured" }
		local ok, problem = pcall(function()
			local plain, facet, same = measure(workload, parent)
			row.plain, row.facet = plain, facet
			if not same then
				row.status = "parity mismatch"
			end
		end)
		if not ok then
			row.status = "unsupported: " .. string.sub(tostring(problem), 1, 160)
		end
		table.insert(rows, row)
		task.wait()
	end
	return rows
end
