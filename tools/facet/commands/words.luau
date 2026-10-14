--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "words",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet words",
	run = function(_invocation: Cli.Invocation): number
		print("facet words: not ported yet")
		return 1
	end,
}

return command
