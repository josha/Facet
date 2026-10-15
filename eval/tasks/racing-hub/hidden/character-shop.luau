--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local HUD: QA.Query = { role = "button", text = "drivers" }

type Snapshot = { coins: number, owned: { [string]: boolean }, rentLeft: { [string]: number }, equipped: string? }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local now = Check.number(value, "now")
	local owned: { [string]: boolean } = {}
	local rawOwned = Check.field(value, "state", "owned")
	if type(rawOwned) == "table" then
		for id, flag in rawOwned :: { [string]: unknown } do
			owned[id] = flag == true
		end
	end
	local rentLeft: { [string]: number } = {}
	local rawRented = Check.field(value, "state", "rented")
	if type(rawRented) == "table" then
		for id, expires in rawRented :: { [string]: unknown } do
			rentLeft[id] = (tonumber(expires) or 0) - now
		end
	end
	local equipped = Check.field(value, "state", "equipped")
	return {
		coins = Check.number(value, "state", "coins"),
		owned = owned,
		rentLeft = rentLeft,
		equipped = if type(equipped) == "string" then equipped else nil,
	}
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, HUD, "the HUD shows a Drivers button", 20)
	Check.tap(qa, context, HUD, "open the driver shop")
	Check.visible(qa, context, { text = "Kira", clipped = true }, "the shop lists the Circuit drivers", 5)
end

local function choose(qa: QA.QA, context: Core.Context, name: string)
	qa:reveal({ text = name })
	Check.tap(qa, context, { role = "button", text = name }, "choose " .. name)
	Check.text(qa, context, "^strength", "the details show Strength", 4)
end

local function shownRent(qa: QA.QA): number?
	local text = qa:hasText("rented:%s*%d+:%d%d%s*left")
	if text == nil then
		return nil
	end
	local minutes, seconds = string.match(string.lower(text), "(%d+):(%d%d)")
	if minutes == nil then
		return nil
	end
	return tonumber(minutes) :: number * 60 + tonumber(seconds) :: number
end

local behavior: { Case } = {
	{
		id = "hud-drivers-button",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, HUD, "the HUD shows a Drivers button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "lists-drivers",
		tier = "spec",
		screen = "list",
		shot = "2-list",
		run = function(qa, context)
			open(qa, context)
			Check.text(qa, context, Check.count("700") .. "%s*coins", "the shop shows the 700 Coins balance", 3)
			for _, name in { "Ren", "Aiko", "Tomo", "Haru" } do
				Check.that(context, qa:first({ text = name, clipped = true }) ~= nil, "the Circuit list shows " .. name)
			end
			Check.that(
				context,
				qa:first({ pattern = "900%s*coins", near = "Kira", clipped = true }) ~= nil,
				"Kira shows the 900 Coins price"
			)
			Check.that(
				context,
				qa:first({ pattern = "equipped", near = "Haru", clipped = true }) ~= nil,
				"Haru shows Equipped"
			)
			qa:capture("2-list")
			qa:dump("list")
			Check.tap(qa, context, { role = "button", exact = "rally" }, "switch to the Rally drivers")
			Check.that(
				context,
				Check.eventually(3, function()
					return qa:first({ text = "Blaze", clipped = true }) ~= nil
						and qa:first({ text = "Kira", clipped = true }) == nil
				end),
				"the Rally list shows Blaze and hides Kira"
			)
			Check.tap(qa, context, { role = "button", exact = "circuit" }, "switch back to Circuit")
			Check.visible(qa, context, { text = "Kira", clipped = true }, "the Circuit list comes back", 3)
		end,
	},
	{
		id = "shows-details",
		tier = "spec",
		screen = "details",
		shot = "3-details",
		run = function(qa, context)
			choose(qa, context, "Kira")
			for _, value in { "92", "80", "70" } do
				Check.text(qa, context, Check.count(value), "the details show the stat " .. value, 2)
			end
			Check.visible(qa, context, { role = "button", text = "buy" }, "the details show Buy", 2)
			Check.visible(qa, context, { role = "button", text = "rent" }, "the details show Rent", 2)
			qa:capture("3-details")
			qa:dump("details")
		end,
	},
	{
		id = "refuses-without-coins",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "buy" }, "press Buy for Kira")
			Check.text(qa, context, "not enough coins", "the shop says that the player needs more Coins", 4)
			Check.that(context, qa:hasText("buy kira for") == nil, "no confirmation shows")
			Check.that(context, state(qa).coins == 700, "the server charged nothing")
		end,
	},
	{
		id = "confirms-the-rent",
		tier = "spec",
		screen = "confirm",
		shot = "4-confirm",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "rent" }, "press Rent for Kira")
			Check.text(qa, context, "rent kira for 10 minutes for 90 coins", "the confirmation names the rent", 4)
			qa:capture("4-confirm")
			qa:dump("confirm")
			Check.tap(qa, context, { role = "button", exact = "cancel" }, "cancel the rent")
			Check.that(context, state(qa).coins == 700, "Cancel spends nothing")
		end,
	},
	{
		id = "rents-after-confirming",
		tier = "spec",
		screen = "rented",
		shot = "5-rented",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "rent" }, "press Rent again")
			Check.tap(qa, context, { role = "button", exact = "confirm" }, "confirm the rent")
			Check.that(
				context,
				Check.eventually(5, function()
					return state(qa).rentLeft.kira ~= nil
				end),
				"the server rented Kira"
			)
			Check.that(context, state(qa).coins == 610, "the server charged 90 Coins")
			Check.that(
				context,
				Check.eventually(4, function()
					local shown = shownRent(qa)
					local left = state(qa).rentLeft.kira
					return shown ~= nil and left ~= nil and math.abs((shown :: number) - left) <= 3
				end),
				"the details show Rented: M:SS left that matches the server"
			)
			qa:capture("5-rented")
			qa:dump("rented")
		end,
	},
	{
		id = "equips-the-rented-driver",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", exact = "equip" }, "equip Kira")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).equipped == "kira"
				end),
				"the server equipped Kira"
			)
			Check.text(qa, context, "equipped", "the details show Equipped", 3)
		end,
	},
	{
		id = "buys-after-confirming",
		tier = "spec",
		run = function(qa, context)
			choose(qa, context, "Aiko")
			Check.tap(qa, context, { role = "button", text = "buy" }, "press Buy for Aiko")
			Check.text(qa, context, "buy aiko for 350 coins", "the confirmation names the price", 4)
			Check.tap(qa, context, { role = "button", exact = "confirm" }, "confirm the purchase")
			Check.that(
				context,
				Check.eventually(5, function()
					return state(qa).owned.aiko == true
				end),
				"the server sold Aiko"
			)
			Check.that(context, state(qa).coins == 260, "the server charged 350 Coins")
			Check.tap(qa, context, { role = "button", exact = "equip" }, "equip Aiko")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).equipped == "aiko"
				end),
				"the server equipped Aiko"
			)
		end,
	},
	{
		id = "closes-shop",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", exact = "close" }, "close the shop")
			Check.gone(qa, context, { text = "Kira" }, "the shop closes", 4)
		end,
	},
}

return behavior
