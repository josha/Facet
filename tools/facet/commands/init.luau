--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
	require("@self/art"),
	require("@self/icons"),
}

return table.freeze(commands)
