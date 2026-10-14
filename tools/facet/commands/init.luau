--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
	require("@self/check"),
}

return table.freeze(commands)
