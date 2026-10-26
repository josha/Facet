--!strict

local Cli = require("../lib/cli")

local USAGE =
	"usage: lute run tools/facet bench [--shard K/N]\n\n--shard runs every Nth microbenchmark and always the CPU yardstick.\nExit 0 passes, 1 fails and 2 reports a host timing comparison failure."

local command: Cli.Command = {
	name = "bench",
	summary = "Run the headless microbenchmarks against bench/baseline.json.",
	usage = USAGE,
	values = { "shard" },
	run = function(invocation: Cli.Invocation): number
		local value = Cli.flag(invocation, "shard")
		if value == nil then
			return require("../lib/bench_run")()
		end
		local position, total = string.match(value, "^(%d+)/(%d+)$")
		local index, count = tonumber(position), tonumber(total)
		if index == nil or count == nil or index < 1 or index > count then
			print(USAGE)
			return 2
		end
		return require("../lib/bench_run")({ index = index, count = count })
	end,
}

return command
