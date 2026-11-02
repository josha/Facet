--!strict

local task = require("@std/task")

local Parallel = {}

function Parallel.map<T, R>(items: { T }, limit: number, work: (T) -> R): { R }
	local results: { R } = {}
	local problems: { [number]: unknown } = {}
	local upcoming = 1
	local running = math.min(limit, #items)
	local stopped = false
	for _ = 1, running do
		task.spawn(function()
			while not stopped and upcoming <= #items do
				local index = upcoming
				upcoming += 1
				local ok, value = pcall(work, items[index])
				if ok then
					results[index] = value :: R
				else
					problems[index] = value
					stopped = true
				end
			end
			running -= 1
		end)
	end
	while running > 0 do
		task.wait(0.01)
	end
	for index = 1, #items do
		if problems[index] ~= nil then
			error(problems[index], 0)
		end
	end
	return results
end

return Parallel
