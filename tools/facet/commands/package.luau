--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "package",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet package",
	run = function(_invocation: Cli.Invocation): number
		print("facet package: not ported yet")
		return 1
	end,
}

return command
