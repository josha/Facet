--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "perf",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet perf",
	run = function(_invocation: Cli.Invocation): number
		print("facet perf: not ported yet")
		return 1
	end,
}

return command
