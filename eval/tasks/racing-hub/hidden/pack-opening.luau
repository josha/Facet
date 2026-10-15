--!strict

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local NAMES: { [string]: string } = {
	pebble_golem = "Pebble Golem",
	moss_sprite = "Moss Sprite",
	dune_beetle = "Dune Beetle",
	river_otter = "River Otter",
	frost_fox = "Frost Fox",
	ember_hawk = "Ember Hawk",
	tide_serpent = "Tide Serpent",
	storm_lion = "Storm Lion",
	crystal_stag = "Crystal Stag",
	sun_dragon = "Sun Dragon",
	moon_whale = "Moon Whale",
}

type Snapshot = { gems: number, collection: { [string]: number }, opened: { { string } } }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local collection: { [string]: number } = {}
	local raw = Check.field(value, "state", "collection")
	if type(raw) == "table" then
		for id, count in raw :: { [string]: unknown } do
			collection[id] = tonumber(count) or 0
		end
	end
	local opened: { { string } } = {}
	local entries = Check.field(value, "journal")
	if type(entries) == "table" then
		for _, entry in entries :: { unknown } do
			if Check.field(entry, "ok") == true then
				local cards: { string } = {}
				local list = Check.field(entry, "cards")
				if type(list) == "table" then
					for _, id in list :: { unknown } do
						table.insert(cards, tostring(id))
					end
				end
				table.insert(opened, cards)
			end
		end
	end
	return { gems = Check.number(value, "state", "gems"), collection = collection, opened = opened }
end

local function openStore(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, { role = "button", text = "crates" }, "the HUD shows a Crates button", 20)
	Check.tap(qa, context, { role = "button", text = "crates" }, "open the crate store")
	Check.visible(qa, context, { text = "Starter Crate", clipped = true }, "the store lists the Starter Crate", 5)
end

local function askToOpen(qa: QA.QA, context: Core.Context, crate: string)
	qa:reveal({ text = crate })
	Check.tap(qa, context, { role = "button", exact = "open", near = crate }, "press Open on the " .. crate)
end

local function confirm(qa: QA.QA, context: Core.Context, before: number)
	Check.text(qa, context, "open starter crate for 50 gems", "the confirmation names the crate and the price", 4)
	Check.tap(qa, context, { role = "button", exact = "open", near = "for 50 gems" }, "confirm the purchase")
	Check.that(
		context,
		Check.eventually(6, function()
			return #state(qa).opened == before + 1
		end),
		"the server opened one Starter Crate"
	)
end

local function lastCards(qa: QA.QA): { string }
	local opened = state(qa).opened
	local names: { string } = {}
	local last: { string } = opened[#opened] or {}
	for _, id in last do
		table.insert(names, NAMES[id] or id)
	end
	return names
end

local function revealAll(qa: QA.QA, context: Core.Context, names: { string })
	if qa:first({ role = "button", text = "reveal all" }) ~= nil then
		Check.tap(qa, context, { role = "button", text = "reveal all" }, "press Reveal All")
	else
		for _ = 1, #names do
			Check.tap(qa, context, { role = "button", exact = "reveal" }, "press Reveal")
		end
	end
	for _, name in names do
		Check.visible(qa, context, { text = name }, "the reveal shows " .. name, 4)
	end
end

local behavior: { Case } = {
	{
		id = "hud-crates-button",
		tier = "spec",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", text = "crates" }, "the HUD shows a Crates button", 20)
			qa:capture("1-hud")
		end,
	},
	{
		id = "shows-the-store",
		tier = "spec",
		screen = "store",
		shot = "2-store",
		run = function(qa, context)
			openStore(qa, context)
			for _, name in { "Veteran Crate", "Legend Crate" } do
				Check.that(context, qa:first({ text = name, clipped = true }) ~= nil, "the store lists the " .. name)
			end
			Check.text(qa, context, Check.count("200") .. "%s*gems", "the store shows the 200 Gems balance")
			Check.text(qa, context, Check.count("50") .. "%s*gems", "the store shows the 50 Gems price")
			Check.text(qa, context, Check.count("3") .. "%s*cards", "the store shows 3 cards for the Starter Crate")
			Check.text(qa, context, Check.count("70") .. "%s*%%", "the store shows the 70% Common odds")
			qa:capture("2-store")
			qa:dump("store")
		end,
	},
	{
		id = "cancels-before-paying",
		tier = "spec",
		screen = "confirm",
		shot = "3-confirm",
		run = function(qa, context)
			askToOpen(qa, context, "Starter Crate")
			Check.text(
				qa,
				context,
				"open starter crate for 50 gems",
				"the confirmation names the crate and the price",
				4
			)
			qa:capture("3-confirm")
			qa:dump("confirm")
			Check.tap(qa, context, { role = "button", exact = "cancel" }, "cancel the purchase")
			Check.absent(qa, context, "open starter crate for", "the confirmation closes", 4)
			local now = state(qa)
			Check.that(context, now.gems == 200 and #now.opened == 0, "Cancel spends nothing")
		end,
	},
	{
		id = "opens-after-confirming",
		tier = "spec",
		run = function(qa, context)
			askToOpen(qa, context, "Starter Crate")
			confirm(qa, context, 0)
			Check.that(context, state(qa).gems == 150, "the server charged 50 Gems")
		end,
	},
	{
		id = "reveals-in-order",
		tier = "spec",
		screen = "reveal",
		shot = "4-reveal",
		run = function(qa, context)
			local names = lastCards(qa)
			Check.that(context, #names == 3, "the server returned 3 cards")
			Check.tap(qa, context, { role = "button", exact = "reveal" }, "press Reveal")
			Check.visible(qa, context, { text = names[1] }, "the first reveal shows the first card " .. names[1], 4)
			Check.tap(qa, context, { role = "button", exact = "reveal" }, "press Reveal again")
			Check.visible(qa, context, { text = names[2] }, "the second reveal shows " .. names[2], 4)
			revealAll(qa, context, { names[3] })
			for _, name in names do
				Check.visible(qa, context, { text = name }, "the reveal shows " .. name, 2)
			end
			qa:capture("4-reveal")
			qa:dump("reveal")
			Check.tap(qa, context, { role = "button", exact = "done" }, "press Done")
			Check.visible(qa, context, { text = "Legend Crate", clipped = true }, "Done goes back to the store", 4)
		end,
	},
	{
		id = "shows-the-collection",
		tier = "spec",
		screen = "collection",
		shot = "5-collection",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = "collection" }, "open the collection")
			local now = state(qa)
			local owned = 0
			for id, count in now.collection do
				owned += 1
				local name = NAMES[id] or id
				Check.visible(qa, context, { text = name, clipped = true }, "the collection shows " .. name, 4)
				Check.that(
					context,
					qa:first({ pattern = "x%s*" .. count .. "$", near = name, clipped = true }) ~= nil,
					("the collection shows x%d for %s"):format(count, name)
				)
			end
			Check.text(qa, context, Check.count(tostring(owned)) .. "%s*/%s*11", "the collection shows the progress", 3)
			Check.that(context, qa:first({ text = "???", clipped = true }) ~= nil, "unknown cards show ???")
			qa:capture("5-collection")
			qa:dump("collection")
			Check.tap(qa, context, { role = "button", exact = "back" }, "go back to the store")
			Check.visible(qa, context, { text = "Starter Crate", clipped = true }, "Back goes to the store", 4)
		end,
	},
	{
		id = "refuses-without-gems",
		tier = "spec",
		run = function(qa, context)
			askToOpen(qa, context, "Legend Crate")
			Check.text(qa, context, "not enough gems", "the store says that the player needs more Gems", 4)
			Check.that(context, qa:hasText("open legend crate for") == nil, "no confirmation shows")
			Check.that(context, state(qa).gems == 150, "the server charged nothing")
		end,
	},
	{
		id = "closes-store",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", exact = "close" }, "close the store")
			Check.gone(qa, context, { text = "Starter Crate" }, "the store closes", 4)
		end,
	},
}

return behavior
