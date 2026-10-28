--!strict

local Cli = require("../lib/cli")

local USAGE =
	"usage: lute run tools/facet bench [--shard K/N] [--cases a,b]\n       lute run tools/facet bench compare [--verify] [--filter text] [--out dir]\n\n--shard runs every Nth microbenchmark and --cases runs only the named ones; both always run the CPU yardstick.\ncompare checks Facet/plain parity before timing and writes JSON and Markdown; --verify checks parity only.\nExit 0 passes, 1 fails and 2 reports a host timing comparison failure or usage error."

local command: Cli.Command = {
	name = "bench",
	summary = "Run the headless microbenchmarks against bench/baseline.json.",
	usage = USAGE,
	values = { "shard", "cases", "filter", "out" },
	run = function(invocation: Cli.Invocation): number
		if invocation.positional[1] == "compare" then
			return require("./bench_compare")(invocation)
		end
		if #invocation.positional > 0 then
			print(USAGE)
			return 2
		end
		local listed = Cli.flag(invocation, "cases")
		local cases = if listed ~= nil then string.split(listed, ",") else nil
		local value = Cli.flag(invocation, "shard")
		if value == nil then
			return require("../lib/bench_run")(nil, cases)
		end
		local position, total = string.match(value, "^(%d+)/(%d+)$")
		local index, count = tonumber(position), tonumber(total)
		if index == nil or count == nil or index < 1 or index > count then
			print(USAGE)
			return 2
		end
		return require("../lib/bench_run")({ index = index, count = count }, cases)
	end,
}

return command
