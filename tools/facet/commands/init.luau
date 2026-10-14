--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
	require("@self/design"),
	require("@self/tool"),
	require("@self/mcp"),
	require("@self/schema"),
}

return table.freeze(commands)
