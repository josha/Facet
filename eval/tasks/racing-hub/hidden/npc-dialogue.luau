--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local TALK: QA.Query = { role = "button", text = "talk to mechanic" }

type Snapshot = { node: string?, coins: number, accepted: boolean }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local node = Check.field(value, "state", "node", "id")
	return {
		node = if type(node) == "string" then node else nil,
		coins = Check.number(value, "state", "coins"),
		accepted = Check.field(value, "state", "questAccepted") == true,
	}
end

local function choose(qa: QA.QA, context: Core.Context, words: string, node: string)
	Check.tap(qa, context, { role = "button", text = words }, ("choose %q"):format(words))
	Check.that(
		context,
		Check.eventually(5, function()
			return state(qa).node == node
		end),
		("the server moved the talk to %s"):format(node)
	)
end

local function startTalk(qa: QA.QA, context: Core.Context)
	qa:admin("approach")
	Check.visible(qa, context, TALK, "a Talk to Mechanic button appears near Mechanic", 5)
	Check.tap(qa, context, TALK, "talk to Mechanic")
	Check.that(
		context,
		Check.eventually(5, function()
			return state(qa).node == "start"
		end),
		"the server started the talk"
	)
	Check.text(qa, context, "^mechanic:?$", "the box shows the speaker Mechanic", 4)
	Check.text(qa, context, "help me test the hub equipment", "the box shows the whole first line", 4)
end

local behavior: { Case } = {
	{
		id = "hides-talk-when-far",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, { pattern = "%f[%d]0%f[%D]%s*coins" }, "the HUD shows 0 Coins", 20)
			Check.that(context, qa:first(TALK) == nil, "no Talk button shows while the player is far from Mechanic")
			qa:capture("1-hud")
		end,
	},
	{
		id = "starts-talk",
		tier = "spec",
		screen = "talk",
		shot = "2-talk",
		run = function(qa, context)
			startTalk(qa, context)
			for _, words in { "I will help you.", "What needs a test?", "Not today." } do
				Check.visible(qa, context, { role = "button", text = words }, ("the box offers %q"):format(words), 3)
			end
			qa:capture("2-talk")
			qa:dump("talk")
		end,
	},
	{
		id = "follows-a-question",
		tier = "spec",
		run = function(qa, context)
			choose(qa, context, "What needs a test?", "well")
			Check.text(qa, context, "kart motor needs a test", "the box shows Mechanic's answer", 4)
			Check.that(
				context,
				qa:first({ role = "button", text = "What needs a test?" }) == nil,
				"the old choices are gone"
			)
		end,
	},
	{
		id = "accepts-the-quest",
		tier = "spec",
		screen = "reward",
		shot = "3-reward",
		run = function(qa, context)
			choose(qa, context, "I will help you.", "thanks")
			local now = state(qa)
			Check.that(context, now.accepted and now.coins == 50, "the server paid 50 Coins for the quest")
			Check.text(qa, context, "take 50 coins", "the box shows the thank-you line", 4)
			Check.text(qa, context, "%f[%d]50%f[%D]%s*coins", "the HUD shows 50 Coins", 4)
			qa:capture("3-reward")
			qa:dump("reward")
		end,
	},
	{
		id = "ends-the-talk",
		tier = "spec",
		run = function(qa, context)
			choose(qa, context, "Goodbye.", "farewell")
			Check.text(qa, context, "safe racing", "the box shows the last line", 4)
			Check.tap(qa, context, { role = "button", exact = "close" }, "close the talk")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).node == nil
				end),
				"the server ended the talk"
			)
			Check.absent(qa, context, "safe racing", "the box closes", 4)
			Check.text(qa, context, "%f[%d]50%f[%D]%s*coins", "the HUD still shows 50 Coins", 2)
		end,
	},
	{
		id = "leaves-early",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, TALK, "talk to Mechanic again")
			Check.text(qa, context, "help me test", "the talk starts again", 4)
			Check.tap(qa, context, { role = "button", exact = "leave" }, "leave the talk")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).node == nil
				end),
				"the server ended the talk"
			)
			Check.absent(qa, context, "help me test", "the box closes", 4)
			Check.that(context, state(qa).coins == 50, "the quest paid only once")
		end,
	},
	{
		id = "closes-when-the-player-walks-away",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, TALK, "talk to Mechanic a third time")
			Check.text(qa, context, "help me test", "the talk starts again", 4)
			qa:admin("walkAway")
			Check.absent(qa, context, "help me test", "the box closes when the server ends the talk", 4)
			Check.gone(qa, context, TALK, "the Talk button goes away", 4)
		end,
	},
}

return behavior
