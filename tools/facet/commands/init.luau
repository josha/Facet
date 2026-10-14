--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
}

return table.freeze(commands)
