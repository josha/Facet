--!strict
local demoTabs = require("./demo_tabs")

local groups = {
	{
		id = "rows",
		label = "Rows",
		tabs = {
			{ id = "swipe", label = "Swipe actions", scenario = require("./row_actions") },
			{ id = "permissions", label = "Permissions", scenario = require("./row_capabilities") },
			{ id = "measured", label = "Measured heights", scenario = require("./measured_extents") },
			{ id = "declared", label = "Declared heights", scenario = require("./variable_extents") },
		},
	},
	{
		id = "grids",
		label = "Grids",
		tabs = {
			{ id = "vertical", label = "Grid", scenario = require("./virtual_grid") },
			{ id = "horizontal", label = "Sideways grid", scenario = require("./virtual_hgrid") },
			{ id = "cards", label = "Card rail", scenario = require("./card_rail") },
			{ id = "games", label = "Cards", scenario = require("./cards") },
			{ id = "table", label = "Large table", scenario = require("./table_virtualized") },
		},
	},
}

return {
	title = "Collections",
	ledgerRows = {},
	groups = groups,
	build = function(ctx)
		return demoTabs(ctx, "Collections", groups)
	end,
}
