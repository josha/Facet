--!strict
local demoTabs = require("./demo_tabs")

local groups = {
	{
		id = "inputs",
		label = "Inputs",
		tabs = {
			{ id = "basics", label = "Basics", scenario = require("./adaptive_controls") },
			{ id = "writing", label = "Writing", scenario = require("./text_controls") },
			{ id = "leaves", label = "Leaves", scenario = require("./leaf_capabilities") },
			{ id = "choices", label = "Choices", scenario = require("./selection_controls") },
			{ id = "pickers", label = "Pickers", scenario = require("./pickers") },
		},
	},
	{
		id = "actions",
		label = "Actions",
		tabs = {
			{ id = "buttons", label = "Buttons", scenario = require("./action_controls") },
			{ id = "shortcuts", label = "Shortcuts", scenario = require("./shortcut_hint") },
			{ id = "recipes", label = "Recipes", scenario = require("./recipes_common") },
			{ id = "menus", label = "Menus", scenario = require("./menu") },
			{ id = "alerts", label = "Alerts", scenario = require("./alert") },
			{ id = "sheets", label = "Sheets", scenario = require("./sheet") },
			{ id = "overlays", label = "Overlays", scenario = require("./overlays") },
			{ id = "help", label = "Help", scenario = require("./callout") },
		},
	},
	{
		id = "indicators",
		label = "Status",
		tabs = {
			{ id = "progress", label = "Progress", scenario = require("./progress_ring") },
			{ id = "identity", label = "Identity", scenario = require("./identity") },
			{ id = "status", label = "Status", scenario = require("./status_family") },
			{ id = "toasts", label = "Toasts", scenario = require("./sponsor_toast") },
			{ id = "levels", label = "Levels", scenario = require("./level_picker") },
			{ id = "feedback", label = "Feedback", scenario = require("./sensory_feedback") },
		},
	},
	{
		id = "navigation",
		label = "Menus",
		tabs = {
			{ id = "journey", label = "Journey", scenario = require("./navigation_stack") },
			{ id = "pages", label = "Pages", scenario = require("./page_view") },
			{ id = "paging", label = "Paging", scenario = require("./paging") },
			{ id = "steps", label = "Steps", scenario = require("./steps") },
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
