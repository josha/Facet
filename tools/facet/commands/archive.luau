--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "archive",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet archive",
	run = function(_invocation: Cli.Invocation): number
		print("facet archive: not ported yet")
		return 1
	end,
}

return command
