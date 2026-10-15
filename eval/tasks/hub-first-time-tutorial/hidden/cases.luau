--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "tutorial-dock",
		tier = "spec",
		screen = "tutorial-dock",
		run = function(qa, context)
			S.tap(qa, context, "Tutorial")
			Check.text(qa, context, "step 1 of 3: dock", "tutorial starts at the dock")
			S.target(qa, context, "Next")
			S.target(qa, context, "Skip")
			S.capture(qa, context, "tutorial-dock")
			S.tap(qa, context, "Garage")
			Check.text(qa, context, "clear filters", "pointed dock control still works")
			S.tap(qa, context, "Close")
			S.tap(qa, context, "Next")
		end,
	},
	{
		id = "tutorial-shop-back",
		tier = "spec",
		screen = "tutorial-shop",
		run = function(qa, context)
			Check.text(qa, context, "step 2 of 3: shop", "second step points to Shop")
			S.tap(qa, context, "Back")
			Check.text(qa, context, "step 1 of 3", "Back returns one step")
			S.tap(qa, context, "Next")
			S.capture(qa, context, "tutorial-shop")
			S.tap(qa, context, "Shop")
			Check.text(qa, context, "starter motor", "pointed Shop works")
			S.tap(qa, context, "Close")
			S.tap(qa, context, "Next")
		end,
	},
	{
		id = "tutorial-queue-skip",
		tier = "spec",
		screen = "tutorial-queue",
		run = function(qa, context)
			Check.text(qa, context, "step 3 of 3: race queue", "third step points to race queue")
			S.capture(qa, context, "tutorial-queue")
			S.tap(qa, context, "Play")
			Check.text(qa, context, "solo", "pointed queue control works")
			S.tap(qa, context, "Close")
			S.tap(qa, context, "Skip")
			Check.absent(qa, context, "step 3 of 3", "Skip dismisses coach marks")
			Check.that(context, Check.field(S.state(qa), "tutorialDone") == true, "tutorial dismissal is recorded")
			S.tap(qa, context, "Tutorial")
			S.tap(qa, context, "Next")
			S.tap(qa, context, "Next")
			S.tap(qa, context, "Next")
			Check.absent(qa, context, "step 3 of 3", "last Next completes tutorial")
		end,
	},
}
return cases
