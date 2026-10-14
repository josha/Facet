--!strict

local Cli = require("../lib/cli")

local command: Cli.Command = {
	name = "release",
	summary = "Not ported yet.",
	usage = "usage: lute run tools/facet release",
	run = function(_invocation: Cli.Invocation): number
		print("facet release: not ported yet")
		return 1
	end,
}

return command
