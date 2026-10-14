--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "types",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet types",
	run = function(_invocation: Cli.Invocation): number
		print("facet types: not ported yet")
		return 1
	end,
}

return command
