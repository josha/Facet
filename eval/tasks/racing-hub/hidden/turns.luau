--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")
local Core = require("../../../../tools/vendor/verify/src/core")
local Coherence = require("./coherence")

local function tap(qa: QA.QA, context: Core.Context, words: string)
	Check.tap(qa, context, { role = "button", exact = string.lower(words) }, words)
end
local function snapshot(qa: QA.QA, system: string): unknown
	return qa:admin("system", { system = system, command = "state" })
end
local function journalCount(value: unknown): number
	local journal = Check.field(value, "journal")
	return if type(journal) == "table" then #(journal :: { unknown }) else 0
end
local function capture(qa: QA.QA, name: string)
	qa:dump(name)
	qa:capture(name)
	Coherence.observe(qa.device.id, name)
end
local function ordered(qa: QA.QA, a: string, b: string): boolean
	local first = qa:first({ text = a, clipped = true })
	local second = qa:first({ text = b, clipped = true })
	return first ~= nil
		and second ~= nil
		and (
			first.rect.y < second.rect.y - 4
			or (math.abs(first.rect.y - second.rect.y) <= 4 and first.rect.x < second.rect.x)
		)
end

local function cases(kind: string): { Play.Case }
	if kind == "hub-shop-categories" then
		return {
			{
				id = "categories",
				screen = "shop-categories",
				run = function(qa, context)
					qa:admin("wallet", { coins = 2000, gems = 200 })
					tap(qa, context, "Shop")
					tap(qa, context, "All")
					Check.visible(qa, context, { text = "Crystal Motor", clipped = true }, "All lists motors")
					tap(qa, context, "Cosmetics")
					Check.gone(qa, context, { text = "Crystal Motor", clipped = true }, "categories filter the catalog")
					Check.visible(qa, context, { text = "Gold Paint", clipped = true }, "Cosmetics lists paint")
					capture(qa, "shop-categories")
				end,
			},
			{
				id = "big-purchase-confirm",
				screen = "shop-category-confirm",
				run = function(qa, context)
					local before = snapshot(qa, "shop")
					Check.tap(qa, context, { role = "button", exact = "buy", near = "Gold Paint" }, "buy Gold Paint")
					Check.text(qa, context, "buy gold paint for 120 gems", "the confirmation names the item and price")
					capture(qa, "shop-category-confirm")
					tap(qa, context, "Cancel")
					Check.that(
						context,
						Check.number(snapshot(qa, "shop"), "state", "wallet", "Gems")
							== Check.number(before, "state", "wallet", "Gems"),
						"Cancel spends nothing"
					)
					Check.that(
						context,
						journalCount(snapshot(qa, "shop")) == journalCount(before),
						"Cancel sends no purchase request"
					)
					Check.tap(qa, context, { role = "button", exact = "buy", near = "Gold Paint" }, "ask again")
					tap(qa, context, "Confirm")
					Check.that(
						context,
						Check.eventually(5, function()
							return Check.field(snapshot(qa, "shop"), "state", "owned", "gold_paint") == true
						end),
						"Confirm buys the item"
					)
					Check.that(
						context,
						Check.number(snapshot(qa, "shop"), "state", "wallet", "Gems") == 80,
						"Confirm charges once"
					)
					tap(qa, context, "Close")
				end,
			},
		}
	elseif kind == "hub-garage-sort" then
		return {
			{
				id = "garage-sort",
				screen = "garage-sort",
				run = function(qa, context)
					tap(qa, context, "Garage")
					tap(qa, context, "All")
					tap(qa, context, "Clear Filters")
					tap(qa, context, "Speed")
					Check.that(context, ordered(qa, "Summit Kart", "Aero Kart"), "Speed puts faster karts first")
					tap(qa, context, "Name")
					Check.that(context, ordered(qa, "Aero Kart", "Coast Kart"), "Name uses A to Z")
					tap(qa, context, "Rarity")
					Check.that(context, ordered(qa, "Summit Kart", "Heavy Kart"), "Legendary karts precede Epic karts")
					capture(qa, "garage-sort")
				end,
			},
			{
				id = "garage-search",
				screen = "garage-search",
				run = function(qa, context)
					local ok, detail = qa:typeText({ role = "input" }, "AERO")
					Check.that(context, ok, detail)
					Check.visible(qa, context, { text = "Aero Kart", clipped = true }, "search ignores case")
					Check.gone(qa, context, { text = "Summit Kart", clipped = true }, "search removes other karts")
					capture(qa, "garage-search")
					ok, detail = qa:typeText({ role = "input" }, "zzzz")
					Check.that(context, ok, detail)
					Check.text(qa, context, "no vehicles match", "an empty result has a message")
					tap(qa, context, "Clear")
					Check.visible(
						qa,
						context,
						{ text = "Summit Kart", clipped = true },
						"Clear restores the collection"
					)
					tap(qa, context, "Close")
				end,
			},
		}
	elseif kind == "hub-settings-reset" then
		return {
			{
				id = "settings-reset-cancel",
				screen = "settings-reset",
				run = function(qa, context)
					tap(qa, context, "Settings")
					local before = snapshot(qa, "settings")
					tap(qa, context, "Reset to Defaults")
					Check.text(qa, context, "reset all settings to their defaults", "reset asks for confirmation")
					capture(qa, "settings-reset")
					tap(qa, context, "Cancel")
					Check.that(
						context,
						Check.number(snapshot(qa, "settings"), "values", "musicVolume")
							== Check.number(before, "values", "musicVolume"),
						"Cancel keeps the saved values"
					)
					Check.that(
						context,
						journalCount(snapshot(qa, "settings")) == journalCount(before),
						"Cancel sends no save"
					)
					local previous = Check.field(snapshot(qa, "settings"), "values", "cameraShake")
					Check.tap(qa, context, { role = "button", near = "Camera Shake" }, "edit Camera Shake")
					Check.that(
						context,
						Check.eventually(5, function()
							return Check.field(snapshot(qa, "settings"), "values", "cameraShake") ~= previous
						end),
						"an ordinary edit saves"
					)
					Check.text(qa, context, "^saved$", "ordinary edits show Saved")
				end,
			},
			{
				id = "settings-reset-save",
				run = function(qa, context)
					tap(qa, context, "Reset to Defaults")
					tap(qa, context, "Reset")
					Check.that(
						context,
						Check.eventually(5, function()
							local now = snapshot(qa, "settings")
							return Check.number(now, "values", "musicVolume") == 70
								and Check.number(now, "values", "effectsVolume") == 70
								and Check.field(now, "values", "showDamageNumbers") == true
								and Check.field(now, "values", "cameraShake") == true
								and Check.field(now, "values", "graphics") == "High"
						end),
						"the server saves every default"
					)
					Check.text(qa, context, "^saved$", "the saved indicator confirms the save")
					tap(qa, context, "Close")
					tap(qa, context, "Settings")
					Check.text(qa, context, "70%%", "defaults persist after reopen")
					tap(qa, context, "Close")
				end,
			},
		}
	end
	return {
		{
			id = "race-scoreboard",
			screen = "scoreboard",
			run = function(qa, context)
				qa:admin("manual")
				qa:admin("phase", { phase = "Round", seconds = 120 })
				qa:admin("eliminate", { victim = "Zed", by = "Nova" })
				qa:admin("eliminate", { victim = "Ivy", by = "Nova" })
				qa:admin("eliminate", { victim = "Pip", by = "Moss" })
				tap(qa, context, "Scoreboard")
				Check.text(qa, context, "^eliminations$", "the scoreboard names its column")
				Check.text(qa, context, "^team$", "the scoreboard has a Team column")
				Check.text(qa, context, "^racer$", "the scoreboard has a Racer column")
				Check.that(context, ordered(qa, "Nova", "Moss"), "two eliminations rank above one")
				Check.visible(qa, context, { text = "you", clipped = true }, "the scoreboard marks the local player")
				Check.visible(
					qa,
					context,
					{ exact = "out", near = "Zed", clipped = true },
					"eliminated racers show OUT"
				)
				capture(qa, "scoreboard")
				qa:admin("eliminate", { victim = "Bolt", by = "Moss" })
				qa:admin("eliminate", { victim = "Rook", by = "Moss" })
				Check.that(
					context,
					Check.eventually(4, function()
						return ordered(qa, "Moss", "Nova")
					end),
					"the open scoreboard follows the server"
				)
				tap(qa, context, "Close")
				if qa.device.id == "desktop" then
					local ok = qa:press("Tab")
					Check.that(context, ok, "Tab reaches the game")
					Check.text(qa, context, "^eliminations$", "Tab opens the scoreboard")
					qa:press("Tab")
					Check.absent(qa, context, "^eliminations$", "Tab closes the scoreboard")
				end
				qa:admin("phase", { phase = "Results", seconds = 120 })
				tap(qa, context, "Back to hub")
			end,
		},
	}
end

return { cases = cases }
