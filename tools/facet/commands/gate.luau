--!strict

local Cli = require("../lib/cli")
local Gate = require("../lib/gate")

local command: Cli.Command = {
	name = "gate",
	summary = "Run the Verify gate: the producers of a tier, or named specs.",
	usage = Gate.USAGE,
	run = function(invocation: Cli.Invocation): number
		return Gate.main(invocation.arguments)
	end,
}

return command
