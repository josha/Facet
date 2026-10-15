--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local function state(qa: QA.QA): { coins: number, gems: number, owned: { [string]: boolean }, journal: { unknown } }
	local value = qa:admin("state")
	local owned: { [string]: boolean } = {}
	local rawOwned = Check.field(value, "state", "owned")
	if type(rawOwned) == "table" then
		for key, flag in rawOwned :: { [string]: unknown } do
			owned[key] = flag == true
		end
	end
	local journal = Check.field(value, "journal")
	return {
		coins = tonumber(Check.field(value, "state", "wallet", "Coins")) or -1,
		gems = tonumber(Check.field(value, "state", "wallet", "Gems")) or -1,
		owned = owned,
		journal = if type(journal) == "table" then journal :: { unknown } else {},
	}
end

local function buy(qa: QA.QA, context: Core.Context, name: string)
	Check.tap(qa, context, { role = "button", text = "buy", near = name }, "the Buy control for " .. name)
end

local function openShop(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, { role = "button", text = "shop" }, "the HUD shows a Shop button", 15)
	Check.tap(qa, context, { role = "button", text = "shop" }, "open the shop")
	Check.visible(qa, context, { text = "Starter Motor", clipped = true }, "the shop lists its items", 5)
end

local function ownedNear(qa: QA.QA, name: string): boolean
	return Check.closer(
		qa,
		{ pattern = "owned", near = name, clipped = true },
		{ role = "button", text = "buy", near = name, clipped = true }
	)
end

local behavior: { Case } = {
	{
		id = "hud-shop-button",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "shop" }, "the HUD shows a Shop button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "opens-shop",
		tier = "spec",
		screen = "shop",
		shot = "2-shop",
		run = function(qa, context)
			openShop(qa, context)
			Check.visible(qa, context, { text = "Sport Motor" }, "the shop shows the Sport Motor", 5)
			qa:capture("2-shop")
			qa:dump("shop")
		end,
	},
	{
		id = "shows-balances",
		tier = "spec",
		run = function(qa, context)
			Check.text(qa, context, Check.count("320"), "the shop shows the 320 Coins balance")
			Check.text(qa, context, Check.count("40"), "the shop shows the 40 Gems balance")
		end,
	},
	{
		id = "shows-prices-and-currency",
		tier = "spec",
		run = function(qa, context)
			Check.text(qa, context, Check.count("250"), "the Sport Motor price is visible")
			Check.text(qa, context, "coin", "prices name the Coins currency")
			Check.text(qa, context, "gem", "prices name the Gems currency")
		end,
	},
	{
		id = "marks-owned-items",
		tier = "spec",
		run = function(qa, context)
			Check.that(context, ownedNear(qa, "Starter Motor"), "the Starter Motor shows Owned instead of Buy")
		end,
	},
	{
		id = "buys-affordable-item",
		tier = "spec",
		run = function(qa, context)
			buy(qa, context, "Sport Motor")
			local bought = Check.eventually(5, function()
				return state(qa).owned.sport_motor == true
			end)
			Check.that(context, bought, "the server recorded the Sport Motor purchase")
			Check.that(context, state(qa).coins == 70, "the server charged 250 Coins")
			Check.text(qa, context, Check.count("70"), "the Coins balance shows 70 after the purchase")
			Check.that(
				context,
				Check.eventually(3, function()
					return ownedNear(qa, "Sport Motor")
				end),
				"the Sport Motor shows Owned after the purchase"
			)
		end,
	},
	{
		id = "refuses-insufficient-coins",
		tier = "spec",
		screen = "feedback",
		shot = "3-feedback",
		run = function(qa, context)
			buy(qa, context, "Rainbow Trail")
			Check.text(qa, context, "not enough coins", "the shop explains that the player needs more Coins", 4)
			qa:capture("3-feedback")
			qa:dump("feedback")
			local now = state(qa)
			Check.that(context, now.coins == 70, "the Coins balance did not change")
			Check.that(context, now.owned.rainbow_trail ~= true, "the Rainbow Trail is not owned")
		end,
	},
	{
		id = "buys-with-gems",
		tier = "spec",
		run = function(qa, context)
			buy(qa, context, "Amber Wheels")
			local bought = Check.eventually(5, function()
				return state(qa).owned.amber_wheels == true
			end)
			Check.that(context, bought, "the server recorded the Amber Wheels purchase")
			Check.that(context, state(qa).gems == 15, "the server charged 25 Gems")
			Check.text(qa, context, Check.count("15"), "the Gems balance shows 15")
		end,
	},
	{
		id = "refuses-insufficient-gems",
		tier = "spec",
		run = function(qa, context)
			buy(qa, context, "Gold Paint")
			Check.text(qa, context, "not enough gems", "the shop explains that the player needs more Gems", 4)
			Check.that(context, state(qa).owned.gold_paint ~= true, "the Gold Paint is not owned")
		end,
	},
	{
		id = "follows-server-balance",
		tier = "spec",
		run = function(qa, context)
			qa:admin("grant", { currency = "Coins", amount = 1000 })
			local shown = qa:waitText("1[,%.]?070", 4) or qa:waitText("1%.07k", 1)
			Check.that(context, shown ~= nil, "the Coins balance follows a server grant to 1070")
		end,
	},
	{
		id = "closes-shop",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "close" }, "close the shop")
			Check.gone(qa, context, { text = "Sport Motor" }, "the shop closes", 4)
		end,
	},
}

return behavior
