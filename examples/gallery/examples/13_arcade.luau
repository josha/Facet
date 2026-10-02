--!strict
local loadTabs = require :: (string) -> typeof(require("@repo/examples/gallery/scenarios/demo_tabs"))
return {
	title = "Arcade",
	build = function(ctx: any)
		local demoTabs = if ctx.load then ctx.load("fixture", "demo_tabs") else loadTabs("../scenarios/demo_tabs")
		local games: { any } = {
			{ id = "word", label = "Word Guess", scenario = require("./05_word_game") },
			{ id = "crossword", label = "Crossword", scenario = require("./06_tile_game") },
			{ id = "match3", label = "Match 3", scenario = require("./07_match3") },
			{ id = "outpost", label = "Outpost", scenario = require("./12_outpost") },
		}
		return demoTabs(ctx, "Arcade", games)
	end,
}
