--!strict

local Cli = require("./lib/cli")

local commands: { Cli.Command } = {
	require("@self/version"),
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
}

return table.freeze(commands)
