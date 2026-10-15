--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
local demoTabs = require("./demo_tabs")

type Entry = typeof(require("@repo/examples/types").DemoTab)
local motionTabs: { Entry } = {
	{ id = "automatic", label = "Automatic", scenario = require("./component_motion") },
	{ id = "animation", label = "Explicit actions", scenario = require("./with_animation") },
	{ id = "curves", label = "Timing", scenario = require("./time_curves") },
	{ id = "opacity", label = "Transparency", scenario = require("./preferred_transparency") },
	{ id = "compositing", label = "Group fade", scenario = require("./canvas_group") },
}
local layoutTabs: { Entry } = {
	{ id = "wrap", label = "Wrapping", scenario = require("./flow_wrap") },
	{ id = "grid", label = "Grid", scenario = require("./container_grid") },
	{ id = "containers", label = "Containers", scenario = require("./containers") },
	{ id = "labels", label = "Labels", scenario = require("./text_degrade") },
	{ id = "inheritance", label = "Inheritance", scenario = require("./inherited_subtree") },
	{ id = "markers", label = "World markers", scenario = require("./world_markers") },
}
local groups: { Entry } = {
	{
		id = "motion",
		label = "Motion",
		tabs = motionTabs,
	},
	{
		id = "layout",
		label = "Layout",
		tabs = layoutTabs,
	},
}

return {
	title = "Motion and layout",
	ledgerRows = {},
	groups = groups,
	build = function(ctx: ExampleContext)
		return demoTabs(ctx, "MotionLayout", groups)
	end,
}
