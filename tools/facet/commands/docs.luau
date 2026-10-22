--!strict
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local DocsQuery = require("../lib/docs_query")
local Props = require("../lib/docs_props")

local USAGE = [[usage: lute run tools/facet docs [path] [--outline] [--search TEXT] [--list]

Start with the map and Design.guide. Read the design guide before UI work.
Read a recipe for the main structure and reuse it across similar pages.
Open another recipe, card or option node for a missing detail. Do not reread a node in context.
Each response has a 4096-byte limit. --full uses the same limit.
Multiple paths return query names only. --search returns paths and summaries.

Examples:
  lute run tools/facet docs Tasks.hud
  lute run tools/facet docs Sheet.card
  lute run tools/facet docs Picker.props
  lute run tools/facet docs Sheet --outline
  lute run tools/facet docs --search detent]]

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "search", "list", "outline", "full" })
	if unknown ~= nil then
		print("facet docs: unknown flags " .. unknown)
		print(USAGE)
		return 2
	end
	local nodes = DocsIndex.load(".")
	for name, options in Props.load(".") do
		local aliases = { name .. ".options" }
		if name == "Stack" then
			table.insert(aliases, name)
		end
		for _, option in options do
			table.insert(aliases, name .. "." .. option.name)
		end
		table.insert(nodes, {
			path = name .. ".props",
			file = "",
			kind = "detail",
			summary = "Typed options and defaults for " .. name .. ".",
			aliases = aliases,
			children = {},
			body = Props.render(name, options),
		})
	end
	table.insert(nodes, {
		path = "Icons.names",
		file = "",
		kind = "detail",
		summary = "Every icon name for the icon option of a control.",
		aliases = { "Icons", "icon names", "icon" },
		children = {},
		body = Props.icons("."),
	})
	print(DocsQuery.response(nodes, invocation))
	return 0
end

return {
	name = "docs",
	summary = "Open one small documentation node, or search paths and summaries.",
	usage = USAGE,
	values = { "search" },
	run = run,
} :: Cli.Command
