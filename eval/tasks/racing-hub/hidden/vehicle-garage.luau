--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local HUD: QA.Query = { role = "button", exact = "garage" }

local function state(qa: QA.QA): { spawned: string?, favorites: { [string]: boolean } }
	local value = qa:admin("state")
	local spawned = Check.field(value, "state", "spawned")
	local favorites: { [string]: boolean } = {}
	local raw = Check.field(value, "state", "favorites")
	if type(raw) == "table" then
		for id, flag in raw :: { [string]: unknown } do
			favorites[id] = flag == true
		end
	end
	return { spawned = if type(spawned) == "string" then spawned else nil, favorites = favorites }
end

local function listed(qa: QA.QA, name: string): boolean
	return qa:first({ text = name, clipped = true }) ~= nil
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, HUD, "the HUD shows a Garage button", 20)
	Check.tap(qa, context, HUD, "open the garage")
	Check.visible(qa, context, { role = "button", exact = "sprint" }, "the garage shows the Air tab", 5)
end

local function tab(qa: QA.QA, context: Core.Context, name: string)
	Check.tap(qa, context, { role = "button", exact = string.lower(name) }, "choose the " .. name .. " tab")
end

local function filter(qa: QA.QA, context: Core.Context, rarity: string)
	Check.tap(qa, context, { role = "button", exact = "filters" }, "open the filters")
	Check.visible(qa, context, { role = "button", exact = "apply" }, "the filters show Apply", 4)
	Check.tap(qa, context, { role = "button", exact = string.lower(rarity) }, "choose " .. rarity)
end

local behavior: { Case } = {
	{
		id = "hud-garage-button",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, HUD, "the HUD shows a Garage button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "filters-by-category",
		tier = "spec",
		screen = "garage",
		shot = "2-garage",
		run = function(qa, context)
			open(qa, context)
			Check.that(
				context,
				listed(qa, "Rookie Kart") and listed(qa, "Aero Kart"),
				"All lists vehicles of every category"
			)
			tab(qa, context, "Sprint")
			Check.that(
				context,
				Check.eventually(3, function()
					return listed(qa, "Aero Kart") and not listed(qa, "Rookie Kart") and not listed(qa, "Coast Kart")
				end),
				"the Air tab lists only air vehicles"
			)
			Check.text(qa, context, "lv%s*8", "the cards show the level as Lv 8", 2)
			qa:capture("2-garage")
			qa:dump("garage")
		end,
	},
	{
		id = "filters-by-rarity",
		tier = "spec",
		screen = "filters",
		shot = "3-filters",
		run = function(qa, context)
			filter(qa, context, "Legendary")
			qa:capture("3-filters")
			qa:dump("filters")
			Check.tap(qa, context, { role = "button", exact = "apply" }, "apply the filters")
			Check.that(
				context,
				Check.eventually(3, function()
					return listed(qa, "Summit Kart") and not listed(qa, "Aero Kart")
				end),
				"Air with Legendary lists only the Summit Kart"
			)
		end,
	},
	{
		id = "cancels-filters",
		tier = "spec",
		run = function(qa, context)
			filter(qa, context, "Common")
			Check.tap(qa, context, { role = "button", exact = "cancel" }, "cancel the filters")
			Check.that(context, listed(qa, "Summit Kart") and not listed(qa, "Sprint Kart"), "Cancel changes nothing")
			Check.tap(qa, context, { role = "button", text = "clear filters" }, "clear the filters")
			Check.that(
				context,
				Check.eventually(3, function()
					return listed(qa, "Aero Kart") and listed(qa, "Sprint Kart")
				end),
				"Clear Filters lists every air vehicle again"
			)
		end,
	},
	{
		id = "shows-details",
		tier = "spec",
		screen = "details",
		shot = "4-details",
		run = function(qa, context)
			qa:reveal({ text = "Aero Kart" })
			Check.tap(qa, context, { role = "button", text = "Aero Kart" }, "choose the Aero Kart")
			Check.visible(qa, context, { role = "button", exact = "spawn" }, "the details show Spawn", 4)
			Check.that(
				context,
				qa:first({ pattern = "^speed", near = "spawn", clipped = true }) ~= nil,
				"the details show Speed"
			)
			for _, value in { "85", "35", "45" } do
				Check.text(qa, context, Check.count(value), "the details show the stat " .. value, 2)
			end
			qa:capture("4-details")
			qa:dump("details")
		end,
	},
	{
		id = "marks-a-favorite",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "favorite" }, "make the Aero Kart a favorite")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).favorites.aero_kart == true
				end),
				"the server saved the favorite"
			)
		end,
	},
	{
		id = "spawns-the-vehicle",
		tier = "spec",
		screen = "vehicle",
		shot = "5-vehicle",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", exact = "spawn" }, "spawn the Aero Kart")
			Check.that(
				context,
				Check.eventually(5, function()
					return state(qa).spawned == "aero_kart"
				end),
				"the server spawned the Aero Kart"
			)
			Check.gone(qa, context, { role = "button", exact = "filters" }, "the garage closes", 4)
			Check.text(qa, context, "drive: w a s d", "the vehicle HUD shows the controls", 4)
			Check.visible(qa, context, { role = "button", text = "leave vehicle" }, "the HUD shows Leave Vehicle", 3)
			local garage = qa:first(HUD)
			if garage ~= nil then
				qa:tap(HUD)
				Check.that(
					context,
					qa:first({ role = "button", exact = "filters" }) == nil,
					"the garage does not open while a vehicle is out"
				)
			end
			qa:capture("5-vehicle")
			qa:dump("vehicle")
		end,
	},
	{
		id = "leaves-the-vehicle",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "leave vehicle" }, "leave the vehicle")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).spawned == nil
				end),
				"the server removed the vehicle"
			)
			Check.gone(qa, context, { role = "button", text = "leave vehicle" }, "the vehicle HUD hides", 4)
		end,
	},
	{
		id = "explains-an-empty-filter",
		tier = "spec",
		run = function(qa, context)
			open(qa, context)
			tab(qa, context, "Coast")
			filter(qa, context, "Legendary")
			Check.tap(qa, context, { role = "button", exact = "apply" }, "apply the filters")
			Check.text(qa, context, "no vehicles match", "the garage says that no vehicle matches", 4)
			Check.tap(qa, context, { role = "button", text = "clear filters" }, "clear the filters")
			Check.visible(qa, context, { text = "Stream Kart", clipped = true }, "the sea vehicles come back", 4)
			Check.tap(qa, context, { role = "button", exact = "close" }, "close the garage")
			Check.gone(qa, context, { role = "button", exact = "filters" }, "the garage closes", 4)
		end,
	},
}

return behavior
