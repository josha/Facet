--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Bench = require("../lib/facetbench")

return {
	name = "facetbench",
	summary = "Derive the extended hub contract and validation sources.",
	usage = "usage: lute run tools/facet facetbench prepare",
	run = function(invocation: Cli.Invocation): number
		assert(invocation.positional[1] == "prepare", "expected prepare")
		Bench.prepare(Files.cwd())
		print("facetbench: prepared extended contract, fixture tasks, follow-ups and type project")
		return 0
	end,
} :: Cli.Command
