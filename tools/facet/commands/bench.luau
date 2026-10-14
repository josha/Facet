--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "bench",
	summary = "Run the headless microbenchmarks against bench/baseline.json.",
	usage = "usage: lute run tools/facet bench\n\nExit 0 passes, 1 fails and 2 reports a host timing comparison failure.",
	run = function(_invocation: Cli.Invocation): number
		return require("../lib/bench_run")()
	end,
}

return command
