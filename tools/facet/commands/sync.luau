--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "sync",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet sync",
	run = function(_invocation: Cli.Invocation): number
		print("facet sync: not ported yet")
		return 1
	end,
}

return command
