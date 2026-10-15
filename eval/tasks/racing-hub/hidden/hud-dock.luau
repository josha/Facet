--!strict

local task = require("@std/task")

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

type Snapshot = {
	coins: number,
	gems: number,
	boostLeft: number?,
	offerLeft: number,
	bought: boolean,
	claimed: { [string]: boolean },
}

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local now = Check.number(value, "now")
	local boost = Check.field(value, "state", "boostEndsAt")
	local claimed: { [string]: boolean } = {}
	local quests = Check.field(value, "state", "quests")
	if type(quests) == "table" then
		for _, quest in quests :: { unknown } do
			claimed[tostring(Check.field(quest, "id"))] = Check.field(quest, "claimed") == true
		end
	end
	return {
		coins = Check.number(value, "state", "coins"),
		gems = Check.number(value, "state", "gems"),
		boostLeft = if type(boost) == "number" then boost - now else nil,
		offerLeft = Check.number(value, "state", "offer", "endsAt") - now,
		bought = Check.field(value, "state", "offer", "bought") == true,
		claimed = claimed,
	}
end

local function forms(amount: number): { string }
	if amount < 1000 then
		return { tostring(math.floor(amount)) }
	end
	local found: { string } = {}
	local sizes = { 1e9, 1e6, 1e3 }
	local suffixes = { "b", "m", "k" }
	for index, size in sizes do
		if amount >= size then
			for _, value in { math.floor(amount / size * 100) / 100, math.floor(amount / size * 100 + 0.5) / 100 } do
				local text = string.format("%.2f", value)
				text = string.gsub(text, "%.?0+$", "")
				local escaped = string.gsub(text, "%.", "%%.")
				table.insert(found, escaped .. suffixes[index])
			end
			break
		end
	end
	return found
end

local function showsAmount(qa: QA.QA, amount: number, word: string): boolean
	for _, form in forms(amount) do
		if qa:hasText("%f[%w.]" .. form .. "%s*" .. word) ~= nil then
			return true
		end
	end
	return false
end

local function clock(text: string?): number?
	if text == nil then
		return nil
	end
	local minutes, seconds = string.match(text :: string, "(%d+):(%d%d)")
	if minutes == nil then
		return nil
	end
	return tonumber(minutes) :: number * 60 + tonumber(seconds) :: number
end

local function openPanel(qa: QA.QA, context: Core.Context, name: string, marker: string)
	Check.tap(qa, context, { role = "button", text = string.lower(name) }, "open the " .. name .. " panel")
	Check.text(qa, context, marker, "the " .. name .. " panel opens", 4)
end

local function closePanel(qa: QA.QA, context: Core.Context, marker: string)
	Check.tap(qa, context, { role = "button", exact = "close" }, "close the panel")
	Check.absent(qa, context, marker, "the panel closes", 4)
end

local behavior: { Case } = {
	{
		id = "shows-counters",
		screen = "hud",
		shot = "1-hud",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "boosts" }, "the dock shows Boosts", 20)
			qa:admin("pause")
			task.wait(1.5)
			local now = state(qa)
			Check.that(
				context,
				Check.eventually(4, function()
					return showsAmount(qa, now.coins, "coins")
				end),
				("the HUD shows %d Coins in the short form"):format(now.coins)
			)
			Check.that(context, showsAmount(qa, now.gems, "gems"), "the HUD shows the Gems")
			Check.text(qa, context, "%+%s*5%s*/%s*s", "the HUD shows the income +5/s", 2)
			Check.text(qa, context, "zone 2", "the HUD shows Zone 2", 2)
			Check.text(qa, context, "/%s*5k", "the zone progress shows the 5K goal", 2)
			qa:capture("1-hud")
			qa:dump("hud")
		end,
	},
	{
		id = "follows-the-income",
		run = function(qa, context)
			qa:admin("resume")
			task.wait(3.2)
			qa:admin("pause")
			task.wait(1.2)
			local now = state(qa)
			Check.that(
				context,
				Check.eventually(3, function()
					return showsAmount(qa, now.coins, "coins")
				end),
				("the HUD follows the income to %d Coins"):format(now.coins)
			)
			qa:admin("grant", { coins = 1234567 })
			local after = state(qa)
			Check.that(
				context,
				Check.eventually(3, function()
					return showsAmount(qa, after.coins, "coins")
				end),
				"the HUD shows millions with M"
			)
		end,
	},
	{
		id = "buys-a-boost",
		screen = "boosts",
		shot = "2-boosts",
		run = function(qa, context)
			local before = state(qa).gems
			openPanel(qa, context, "Boosts", "2x coins for 30 seconds")
			Check.tap(qa, context, { role = "button", text = "buy for 10 gems" }, "buy the boost")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).boostLeft ~= nil
				end),
				"the server started the boost"
			)
			Check.that(context, state(qa).gems == before - 10, "the server charged 10 Gems")
			Check.that(
				context,
				Check.eventually(4, function()
					local shown = clock(qa:hasText("2x coins:%s*%d+:%d%d%s*left"))
					local left = state(qa).boostLeft
					return shown ~= nil and left ~= nil and math.abs((shown :: number) - left) <= 2
				end),
				"the panel shows 2x Coins: M:SS left that matches the server"
			)
			Check.text(qa, context, "%+%s*10%s*/%s*s", "the HUD shows the doubled income", 3)
			qa:capture("2-boosts")
			qa:dump("boosts")
			closePanel(qa, context, "2x coins for 30 seconds")
		end,
	},
	{
		id = "claims-quests",
		screen = "quests",
		shot = "3-quests",
		run = function(qa, context)
			openPanel(qa, context, "Quests", "earn 1,?200 coins")
			Check.tap(
				qa,
				context,
				{ role = "button", exact = "claim", near = "Earn 1,200 Coins" },
				"claim the first quest"
			)
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).claimed.earn_small == true
				end),
				"the server marked the quest claimed"
			)
			Check.that(
				context,
				Check.eventually(3, function()
					return qa:first({ pattern = "^claimed$", near = "Earn 1,200 Coins" }) ~= nil
				end),
				"the quest shows Claimed"
			)
			Check.tap(qa, context, { role = "button", exact = "claim", near = "boost" }, "claim the boost quest")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).claimed.boost == true
				end),
				"the server marked the boost quest claimed"
			)
			qa:capture("3-quests")
			qa:dump("quests")
			closePanel(qa, context, "earn 1,?200 coins")
		end,
	},
	{
		id = "buys-the-offer",
		screen = "offer",
		shot = "4-offer",
		run = function(qa, context)
			local dock = qa:first({ role = "button", text = "offer" })
			Check.that(context, dock ~= nil and clock(dock.label) ~= nil, "the Offer button shows the time left")
			openPanel(qa, context, "Offer", "starter offer")
			Check.that(
				context,
				Check.eventually(3, function()
					local shown = clock(qa:hasText("ends in%s*%d+:%d%d"))
					return shown ~= nil and math.abs((shown :: number) - state(qa).offerLeft) <= 2
				end),
				"Ends in MM:SS matches the server"
			)
			Check.text(qa, context, "99%s*gems", "the offer shows the 99 Gems price", 2)
			local coins = state(qa).coins
			Check.tap(qa, context, { role = "button", exact = "buy" }, "buy the offer")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).bought
				end),
				"the server sold the offer"
			)
			Check.that(context, state(qa).coins >= coins + 5000, "the server paid 5K Coins")
			Check.text(qa, context, "bought", "the panel shows Bought", 3)
			qa:capture("4-offer")
			qa:dump("offer")
			closePanel(qa, context, "starter offer")
		end,
	},
}

return behavior
