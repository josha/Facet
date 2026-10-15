--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type DemoTabs = typeof(require("@repo/examples/gallery/scenarios/demo_tabs"))
type DemoTab = typeof(require("@repo/examples/types").DemoTab)
local loadTabs: (ModuleScript | string) -> DemoTabs = require
return {
	title = "Arcade",
	build = function(ctx: ExampleContext)
		local demoTabs = loadTabs(if ctx.find then ctx.find("fixture", "demo_tabs") else "../scenarios/demo_tabs")
		local games: { DemoTab } = {
			{ id = "word", label = "Word Guess", scenario = require("./05_word_game") },
			{ id = "crossword", label = "Crossword", scenario = require("./06_tile_game") },
			{ id = "match3", label = "Match 3", scenario = require("./07_match3") },
			{ id = "outpost", label = "Outpost", scenario = require("./12_outpost") },
		}
		return demoTabs(ctx, "Arcade", games)
	end,
}
