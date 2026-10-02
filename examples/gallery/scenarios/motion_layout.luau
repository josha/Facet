--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
local demoTabs = require("./demo_tabs")

type Scenario = { build: (ExampleContext) -> { screen: () -> Instance } }
type Entry = { id: string, label: string, tabs: { Entry }?, scenario: Scenario? }
local groups: { Entry } = {
	{
		id = "motion",
		label = "Motion",
		tabs = {
			{ id = "automatic", label = "Automatic", scenario = require("./component_motion") } :: Entry,
			{ id = "animation", label = "Explicit actions", scenario = require("./with_animation") } :: Entry,
			{ id = "curves", label = "Timing", scenario = require("./time_curves") } :: Entry,
			{ id = "opacity", label = "Transparency", scenario = require("./preferred_transparency") } :: Entry,
			{ id = "compositing", label = "Group fade", scenario = require("./canvas_group") } :: Entry,
		},
	},
	{
		id = "layout",
		label = "Layout",
		tabs = {
			{ id = "wrap", label = "Wrapping", scenario = require("./flow_wrap") } :: Entry,
			{ id = "grid", label = "Grid", scenario = require("./container_grid") } :: Entry,
			{ id = "containers", label = "Containers", scenario = require("./containers") } :: Entry,
			{ id = "labels", label = "Labels", scenario = require("./text_degrade") } :: Entry,
			{ id = "inheritance", label = "Inheritance", scenario = require("./inherited_subtree") } :: Entry,
			{ id = "markers", label = "World markers", scenario = require("./world_markers") } :: Entry,
		},
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
