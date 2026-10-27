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
	require("@self/facetbench"),
	require("@self/gate"),
	require("@self/info"),
	require("@self/docs"),
	require("@self/context-ledger"),
	require("@self/author-replay"),
	require("@self/project"),
	require("@self/lint"),
	require("@self/preview"),
	require("@self/audit"),
	require("@self/critique"),
	require("@self/verify"),
	require("@self/studio"),
	require("@self/kit"),
	require("@self/design"),
}

return table.freeze(commands)
