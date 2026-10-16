--!strict
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local DocsQuery = require("../lib/docs_query")

local USAGE = [[usage: lute run tools/facet docs [path] [--outline] [--search TEXT] [--list]

Start with the map. Open one task recipe, then one card or option node for a
missing detail. Do not read a node that is already in context.
Each response has a 4096-byte limit. --full uses the same limit.
Multiple paths return query names only. --search returns paths and summaries.

Examples:
  lute run tools/facet docs Tasks.hud
  lute run tools/facet docs Sheet.card
  lute run tools/facet docs Sheet --outline
  lute run tools/facet docs --search detent]]

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "search", "list", "outline", "full" })
	if unknown ~= nil then
		print("facet docs: unknown flags " .. unknown)
		print(USAGE)
		return 2
	end
	print(DocsQuery.response(DocsIndex.load("."), invocation))
	return 0
end

return {
	name = "docs",
	summary = "Open one small documentation node, or search paths and summaries.",
	usage = USAGE,
	values = { "search" },
	run = run,
} :: Cli.Command
