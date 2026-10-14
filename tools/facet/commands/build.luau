--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "build",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet build",
	run = function(_invocation: Cli.Invocation): number
		print("facet build: not ported yet")
		return 1
	end,
}

return command
