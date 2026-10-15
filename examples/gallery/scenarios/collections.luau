--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
local demoTabs = require("./demo_tabs")

type Entry = typeof(require("@repo/examples/types").DemoTab)
local rows: { Entry } = {
	{ id = "swipe", label = "Swipe actions", scenario = require("./row_actions") },
	{ id = "permissions", label = "Permissions", scenario = require("./row_capabilities") },
	{ id = "measured", label = "Measured heights", scenario = require("./measured_extents") },
	{ id = "declared", label = "Declared heights", scenario = require("./variable_extents") },
}
local grids: { Entry } = {
	{ id = "vertical", label = "Grid", scenario = require("./virtual_grid") },
	{ id = "horizontal", label = "Sideways grid", scenario = require("./virtual_hgrid") },
	{ id = "cards", label = "Card rail", scenario = require("./card_rail") },
	{ id = "games", label = "Cards", scenario = require("./cards") },
	{ id = "table", label = "Large table", scenario = require("./table_virtualized") },
}
local groups: { Entry } = {
	{ id = "rows", label = "Rows", tabs = rows },
	{ id = "grids", label = "Grids", tabs = grids },
}

return {
	title = "Collections",
	ledgerRows = {},
	groups = groups,
	build = function(ctx: ExampleContext)
		return demoTabs(ctx, "Collections", groups)
	end,
}
