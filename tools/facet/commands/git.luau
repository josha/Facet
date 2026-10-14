--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "git",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet git",
	run = function(_invocation: Cli.Invocation): number
		print("facet git: not ported yet")
		return 1
	end,
}

return command
