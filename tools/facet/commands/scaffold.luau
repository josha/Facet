--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "scaffold",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet scaffold",
	run = function(_invocation: Cli.Invocation): number
		print("facet scaffold: not ported yet")
		return 1
	end,
}

return command
