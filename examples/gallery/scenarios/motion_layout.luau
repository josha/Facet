--!strict
local demoTabs = require("./demo_tabs")

local groups = {
	{
		id = "motion",
		label = "Motion",
		tabs = {
			{ id = "animation", label = "Animation", scenario = require("./with_animation") },
			{ id = "curves", label = "Timing", scenario = require("./time_curves") },
			{ id = "opacity", label = "Transparency", scenario = require("./preferred_transparency") },
			{ id = "compositing", label = "Group fade", scenario = require("./canvas_group") },
		},
	},
	{
		id = "layout",
		label = "Layout",
		tabs = {
			{ id = "wrap", label = "Wrapping", scenario = require("./flow_wrap") },
			{ id = "labels", label = "Labels", scenario = require("./text_degrade") },
			{ id = "inheritance", label = "Inheritance", scenario = require("./inherited_subtree") },
			{ id = "markers", label = "World markers", scenario = require("./world_markers") },
		},
	},
}

return {
	title = "Motion and layout",
	ledgerRows = {},
	groups = groups,
	build = function(ctx)
		return demoTabs(ctx, "MotionLayout", groups)
	end,
}
