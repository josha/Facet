--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local S = require("../../extended/hidden/support")
local cases: { Play.Case } = {
	{
		id = "track-vote-change-live",
		tier = "spec",
		screen = "track-vote",
		run = function(qa, context)
			S.state(qa, "ballot", { seconds = 90 })
			S.tap(qa, context, "Track Vote")
			Check.text(qa, context, "voting ends in", "countdown is visible")
			local countdown = qa:hasText("voting ends in")
			qa:sleep(1.2)
			Check.that(context, qa:hasText("voting ends in") ~= countdown, "countdown advances while open")
			for _, name in { "Harbor Loop", "Alpine Pass", "Desert Sprint" } do
				Check.visible(qa, context, { text = name, clipped = true }, "three tracks are available")
			end
			Check.tap(qa, context, { role = "button", text = "vote", near = "Harbor Loop" }, "vote Harbor")
			Check.that(context, Check.number(S.state(qa), "vote") == 1, "first vote is recorded")
			Check.visible(qa, context, { text = "your vote", near = "Harbor Loop" }, "own vote is marked")
			Check.tap(qa, context, { role = "button", text = "vote", near = "Alpine Pass" }, "change vote")
			local votes = Check.field(S.state(qa), "votes") :: { number }
			Check.that(context, votes[1] == 2 and votes[2] == 4, "old vote is removed before the new vote is added")
			Check.that(context, Check.number(S.state(qa), "vote") == 2, "vote changes")
			S.state(qa, "votes")
			Check.visible(qa, context, { text = "9 votes", near = "Desert Sprint" }, "live remote votes update")
			S.capture(qa, context, "track-vote")
		end,
	},
	{
		id = "track-vote-lock-winner",
		tier = "spec",
		screen = "track-winner",
		run = function(qa, context)
			S.state(qa, "finish")
			Check.text(qa, context, "winner: desert sprint", "winner follows highest count")
			local control = Check.visible(
				qa,
				context,
				{ role = "button", text = "vote", near = "Harbor Loop" },
				"closed card remains readable"
			)
			Check.that(context, not control.interactable, "closed ballot cannot accept a vote")
			S.capture(qa, context, "track-winner")
			S.back(qa, context, "Track Vote")
		end,
	},
}
return cases
