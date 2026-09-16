--!strict
local demoTabs = require("./demo_tabs")

local groups = {
	{
		id = "inputs",
		label = "Inputs",
		tabs = {
			{ id = "basics", label = "Basics", scenario = require("./adaptive_controls") },
			{ id = "writing", label = "Writing", scenario = require("./text_controls") },
			{ id = "choices", label = "Choices", scenario = require("./selection_controls") },
		},
	},
	{
		id = "actions",
		label = "Actions",
		tabs = {
			{ id = "buttons", label = "Buttons", scenario = require("./action_controls") },
			{ id = "menus", label = "Menus", scenario = require("./menu") },
			{ id = "alerts", label = "Alerts", scenario = require("./alert") },
			{ id = "sheets", label = "Sheets", scenario = require("./sheet") },
			{ id = "help", label = "Help", scenario = require("./callout") },
		},
	},
	{
		id = "indicators",
		label = "Indicators",
		tabs = {
			{ id = "progress", label = "Progress", scenario = require("./progress_ring") },
			{ id = "levels", label = "Levels", scenario = require("./level_picker") },
			{ id = "feedback", label = "Feedback", scenario = require("./sensory_feedback") },
		},
	},
	{
		id = "navigation",
		label = "Navigation",
		tabs = {
			{ id = "journey", label = "Journey", scenario = require("./navigation_stack") },
			{ id = "pages", label = "Pages", scenario = require("./page_view") },
			{ id = "disclosure", label = "Disclosure", scenario = require("./collapsible_view") },
		},
	},
}

return {
	title = "All controls",
	ledgerRows = {},
	groups = groups,
	build = function(ctx)
		return demoTabs(ctx, "AllControls", groups)
	end,
}
