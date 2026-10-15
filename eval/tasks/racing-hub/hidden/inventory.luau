--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local OWNED = {
	"Starter Motor",
	"Frost Motor",
	"Ember Motor",
	"Light Body",
	"Steel Body",
	"City Wheels",
	"Snow Wheels",
	"Spark Trail",
	"Galaxy Trail",
}

local function equipped(qa: QA.QA, slot: string): string?
	local value = Check.field(qa:admin("state"), "state", "equipped", slot)
	return if type(value) == "string" then value else nil
end

local function owns(qa: QA.QA, item: string): boolean
	local list = Check.field(qa:admin("state"), "state", "owned")
	if type(list) ~= "table" then
		return false
	end
	return table.find(list :: { unknown }, item) ~= nil
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, { role = "button", text = "inventory" }, "the HUD shows an Inventory button", 20)
	Check.tap(qa, context, { role = "button", text = "inventory" }, "open the inventory")
	Check.visible(qa, context, { text = "Frost Motor", clipped = true }, "the inventory lists the owned items", 5)
end

local function inspect(qa: QA.QA, context: Core.Context, name: string, description: string)
	Check.tap(qa, context, { role = "button", text = name }, "open the details of " .. name)
	Check.text(qa, context, description, "the details show the description of " .. name, 4)
end

local behavior: { Case } = {
	{
		id = "hud-inventory-button",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "inventory" }, "the HUD shows an Inventory button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "lists-owned-items",
		screen = "grid",
		shot = "2-grid",
		run = function(qa, context)
			open(qa, context)
			for _, name in OWNED do
				Check.that(
					context,
					qa:first({ text = name, clipped = true }) ~= nil,
					"the inventory lists the owned item " .. name
				)
			end
			Check.that(
				context,
				qa:first({ text = "Night Motor", clipped = true }) == nil,
				"the inventory does not list the Night Motor, which the player does not own"
			)
			qa:capture("2-grid")
			qa:dump("grid")
		end,
	},
	{
		id = "shows-item-details",
		screen = "details",
		shot = "3-details",
		run = function(qa, context)
			inspect(qa, context, "Frost Motor", "stable motor")
			Check.text(qa, context, "rare", "the details show the rarity")
			Check.text(qa, context, "motor", "the details show the slot")
			Check.text(qa, context, Check.count("42"), "the details show the power")
			qa:capture("3-details")
			qa:dump("details")
		end,
	},
	{
		id = "equips-item",
		run = function(qa, context)
			Check.tap(
				qa,
				context,
				{ role = "button", pattern = "^equip$", near = "stable motor" },
				"equip the Frost Motor"
			)
			Check.that(
				context,
				Check.eventually(5, function()
					return equipped(qa, "Motor") == "frost_motor"
				end),
				"the server equipped the Frost Motor"
			)
			Check.text(qa, context, "equipped", "the screen shows that the Frost Motor is equipped", 3)
		end,
	},
	{
		id = "replaces-slot",
		run = function(qa, context)
			inspect(qa, context, "Starter Motor", "reliable motor")
			Check.visible(
				qa,
				context,
				{ role = "button", pattern = "^equip$" },
				"the Starter Motor can be equipped again because the Frost Motor replaced it",
				3
			)
		end,
	},
	{
		id = "unequips-item",
		run = function(qa, context)
			inspect(qa, context, "City Wheels", "daily hub runs")
			Check.tap(qa, context, { role = "button", text = "unequip" }, "unequip the City Wheels")
			Check.that(
				context,
				Check.eventually(5, function()
					return equipped(qa, "Wheels") == nil
				end),
				"the server emptied the Wheels slot"
			)
			Check.text(qa, context, "empty", "the Wheels slot shows Empty", 3)
		end,
	},
	{
		id = "shows-new-item-from-server",
		run = function(qa, context)
			qa:admin("give", { item = "flame_wheels" })
			Check.that(context, owns(qa, "flame_wheels"), "the server gave the Flame Wheels")
			Check.visible(
				qa,
				context,
				{ text = "Flame Wheels", clipped = true },
				"the new Flame Wheels appears in the inventory",
				4
			)
		end,
	},
	{
		id = "closes-inventory",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "close" }, "close the inventory")
			Check.gone(qa, context, { text = "Frost Motor" }, "the inventory closes", 4)
		end,
	},
}

return behavior
