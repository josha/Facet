--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
local demoTabs = require("./demo_tabs")

type Scenario = { build: (ExampleContext) -> { screen: () -> Instance } }
type Entry = { id: string, label: string, tabs: { Entry }?, scenario: Scenario? }
local groups: { Entry } = {
	{
		id = "rows",
		label = "Rows",
		tabs = {
			{ id = "swipe", label = "Swipe actions", scenario = require("./row_actions") } :: Entry,
			{ id = "permissions", label = "Permissions", scenario = require("./row_capabilities") } :: Entry,
			{ id = "measured", label = "Measured heights", scenario = require("./measured_extents") } :: Entry,
			{ id = "declared", label = "Declared heights", scenario = require("./variable_extents") } :: Entry,
		},
	},
	{
		id = "grids",
		label = "Grids",
		tabs = {
			{ id = "vertical", label = "Grid", scenario = require("./virtual_grid") } :: Entry,
			{ id = "horizontal", label = "Sideways grid", scenario = require("./virtual_hgrid") } :: Entry,
			{ id = "cards", label = "Card rail", scenario = require("./card_rail") } :: Entry,
			{ id = "games", label = "Cards", scenario = require("./cards") } :: Entry,
			{ id = "table", label = "Large table", scenario = require("./table_virtualized") } :: Entry,
		},
	},
}

return {
	title = "Collections",
	ledgerRows = {},
	groups = groups,
	build = function(ctx: ExampleContext)
		return demoTabs(ctx, "Collections", groups)
	end,
}
