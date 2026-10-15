--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

type Snapshot = { coins: number, gems: number, redeemed: { string }, items: { [string]: number } }

local FIELD: QA.Query = { role = "input" }
local REDEEM: QA.Query = { role = "button", text = "redeem" }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local redeemed: { string } = {}
	local raw = Check.field(value, "state", "redeemed")
	if type(raw) == "table" then
		for _, code in raw :: { unknown } do
			table.insert(redeemed, tostring(code))
		end
	end
	local items: { [string]: number } = {}
	local rawItems = Check.field(value, "state", "items")
	if type(rawItems) == "table" then
		for name, amount in rawItems :: { [string]: unknown } do
			items[name] = tonumber(amount) or 0
		end
	end
	return {
		coins = Check.number(value, "state", "wallet", "Coins"),
		gems = Check.number(value, "state", "wallet", "Gems"),
		redeemed = redeemed,
		items = items,
	}
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, { role = "button", text = "codes" }, "the HUD shows a Codes button", 20)
	Check.tap(qa, context, { role = "button", text = "codes" }, "open the Codes panel")
	Check.visible(qa, context, FIELD, "the panel shows a text field for the code", 5)
end

local function enter(qa: QA.QA, context: Core.Context, code: string)
	local typed, detail = qa:typeText(FIELD, code)
	Check.that(context, typed, ("type %q into the code field: %s"):format(code, detail))
	Check.tap(qa, context, REDEEM, "press Redeem")
end

local function continueIfShown(qa: QA.QA)
	if qa:first({ role = "button", text = "continue" }) ~= nil then
		qa:tap({ role = "button", text = "continue" })
		qa:waitGone({ role = "button", text = "continue" }, 3)
	end
end

local behavior: { Case } = {
	{
		id = "hud-codes-button",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "codes" }, "the HUD shows a Codes button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "opens-codes",
		screen = "codes",
		shot = "2-codes",
		run = function(qa, context)
			open(qa, context)
			Check.text(qa, context, Check.count("120") .. "%s*coins", "the panel shows the 120 Coins balance")
			Check.text(qa, context, Check.count("5") .. "%s*gems", "the panel shows the 5 Gems balance")
			qa:capture("2-codes")
			qa:dump("codes")
		end,
	},
	{
		id = "refuses-empty-code",
		run = function(qa, context)
			Check.tap(qa, context, REDEEM, "press Redeem with an empty field")
			Check.text(qa, context, "type a code first", "the panel asks for a code", 4)
		end,
	},
	{
		id = "refuses-unknown-code",
		run = function(qa, context)
			enter(qa, context, "nope")
			Check.text(qa, context, "does not exist", "the panel says that the code does not exist", 4)
			Check.that(context, state(qa).coins == 120, "the Coins balance did not change")
		end,
	},
	{
		id = "refuses-expired-code",
		screen = "feedback",
		shot = "3-feedback",
		run = function(qa, context)
			enter(qa, context, "summer24")
			Check.text(qa, context, "has expired", "the panel says that the code has expired", 4)
			qa:capture("3-feedback")
			qa:dump("feedback")
		end,
	},
	{
		id = "redeems-valid-code",
		screen = "rewards",
		shot = "4-rewards",
		run = function(qa, context)
			enter(qa, context, "  welcome ")
			Check.that(
				context,
				Check.eventually(5, function()
					return table.find(state(qa).redeemed, "WELCOME") ~= nil
				end),
				"the server recorded the WELCOME code"
			)
			local now = state(qa)
			Check.that(context, now.coins == 620 and now.gems == 15, "the server paid 500 Coins and 10 Gems")
			Check.text(qa, context, "500%s*coins", "the reward view shows 500 Coins", 4)
			Check.text(qa, context, "10%s*gems", "the reward view shows 10 Gems", 2)
			qa:capture("4-rewards")
			qa:dump("rewards")
		end,
	},
	{
		id = "continues-to-balance",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "continue" }, "press Continue")
			Check.gone(qa, context, { role = "button", text = "continue" }, "the reward view closes", 4)
			Check.text(qa, context, Check.count("620") .. "%s*coins", "the balance shows 620 Coins", 4)
			Check.text(qa, context, "welcome", "the redeemed list shows WELCOME", 2)
		end,
	},
	{
		id = "refuses-repeated-code",
		run = function(qa, context)
			enter(qa, context, "WELCOME")
			Check.text(qa, context, "already used", "the panel says that the code was already used", 4)
			Check.that(context, state(qa).coins == 620, "the server did not pay twice")
		end,
	},
	{
		id = "limits-retries",
		timeoutSeconds = 300,
		run = function(qa, context)
			for _, code in { "bad1", "bad2", "bad3" } do
				enter(qa, context, code)
				Check.text(qa, context, "does not exist", ("the panel refuses %s"):format(code), 4)
			end
			enter(qa, context, "lucky7")
			Check.text(qa, context, "try again in %d+ seconds", "the panel shows the wait time", 4)
			Check.that(context, state(qa).items["Lucky Charm"] == nil, "the server refused the code while limited")
		end,
	},
	{
		id = "closes-codes",
		run = function(qa, context)
			continueIfShown(qa)
			Check.tap(qa, context, { role = "button", text = "close" }, "close the panel")
			Check.gone(qa, context, FIELD, "the panel closes", 4)
		end,
	},
}

return behavior
