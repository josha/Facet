--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
	require("@self/art"),
	require("@self/icons"),
	require("@self/check"),
	require("@self/sync"),
	require("@self/package"),
	require("@self/build"),
	require("@self/release"),
	require("@self/scaffold"),
	require("@self/types"),
	require("@self/perf"),
	require("@self/words"),
	require("@self/git"),
	require("@self/archive"),
	require("@self/bench"),
	require("@self/gate"),
	require("@self/design"),
	require("@self/tool"),
	require("@self/mcp"),
	require("@self/schema"),
}

return table.freeze(commands)
