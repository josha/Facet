--!strict

local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")
local Check = require("../../../../tools/play/host/check")

type Actions = {
	press: (QA.QA, Core.Context, string) -> (),
	back: (QA.QA, Core.Context) -> (),
}

local function extended(qa: QA.QA, command: string?, args: unknown?): unknown
	return qa:admin("extended", { command = command or "state", args = args })
end

local function cases(index: number, actions: Actions): { Play.Case }
	local press, back = actions.press, actions.back
	local bodies: { Play.CaseBody } = {
		function(qa, context)
			press(qa, context, "Shop")
			for _, category in { "Motors", "Boosts", "Wheels", "Cosmetics", "All" } do
				press(qa, context, category)
				Check.that(context, #qa:texts() > 0, "category browsing has readable content")
			end
			back(qa, context)
		end,
		function(qa, context)
			press(qa, context, "Garage")
			local typed, detail = qa:typeText({ role = "input" }, "zzzz-unmatched")
			Check.that(context, typed, detail)
			Check.gone(qa, context, { text = "Rookie Kart", clipped = true }, "an unmatched search hides the kart")
			Check.that(context, #qa:texts() > 0, "an empty search keeps readable navigation")
			press(qa, context, "Clear")
			Check.visible(qa, context, { text = "Rookie Kart", clipped = true }, "Clear restores the collection")
			for _, order in { "Speed", "Rarity", "Name" } do
				press(qa, context, order)
			end
			back(qa, context)
		end,
		function(qa, context)
			press(qa, context, "Settings")
			local before = qa:admin("system", { system = "settings", command = "state" })
			press(qa, context, "Reset")
			press(qa, context, "Cancel")
			local after = qa:admin("system", { system = "settings", command = "state" })
			for _, key in { "musicVolume", "effectsVolume", "showDamageNumbers", "cameraShake", "graphics" } do
				Check.that(
					context,
					Check.field(before, "values", key) == Check.field(after, "values", key),
					"Cancel preserves " .. key
				)
			end
			back(qa, context)
		end,
		function(_qa, _context) end,
		function(qa, context)
			extended(qa, "reset")
			press(qa, context, "Livery")
			press(qa, context, "Flames")
			press(qa, context, "Save")
			Check.that(
				context,
				Check.eventually(4, function()
					return Check.field(extended(qa), "livery", "decal") == "Flames"
				end),
				"Save keeps the chosen decal on the server"
			)
			press(qa, context, "Stars")
			press(qa, context, "Revert")
			press(qa, context, "Cancel")
			Check.that(
				context,
				Check.field(extended(qa), "livery", "decal") == "Flames",
				"Cancel does not overwrite the saved design"
			)
			press(qa, context, "Revert")
			press(qa, context, "Discard")
			back(qa, context)
		end,
		function(qa, context)
			extended(qa, "reset")
			extended(qa, "ballot", { seconds = 30 })
			press(qa, context, "Track Vote")
			qa:reveal({ role = "button", text = "vote", near = "Harbor Loop" })
			Check.tap(qa, context, { role = "button", text = "vote", near = "Harbor Loop" }, "vote for the first track")
			Check.that(
				context,
				Check.eventually(4, function()
					return Check.number(extended(qa), "vote") == 1
				end),
				"the server records the player's vote"
			)
			extended(qa, "finish")
			local final = extended(qa)
			local winner = Check.field(final, "winner")
			Check.that(context, type(winner) == "string" and winner ~= "", "the server finished the ballot")
			Check.visible(qa, context, { text = tostring(winner) }, "the server winner is visible", 4)
			back(qa, context)
		end,
		function(qa, context)
			extended(qa, "reset")
			local before = Check.number(extended(qa), "chatCount")
			press(qa, context, "Quick Chat")
			back(qa, context)
			Check.that(
				context,
				Check.number(extended(qa), "chatCount") == before,
				"opening and canceling sends nothing"
			)
			press(qa, context, "Quick Chat")
			press(qa, context, "Hello!")
			Check.that(
				context,
				Check.eventually(4, function()
					return Check.number(extended(qa), "chatCount") == before + 1
				end),
				"one activation sends one message"
			)
			Check.visible(qa, context, { text = "Hello!" }, "the sent message is visible")
		end,
		function(qa, context)
			extended(qa, "reset")
			qa:admin("wallet", { coins = 1000, gems = 50 })
			press(qa, context, "Upgrades")
			local before = extended(qa)
			press(qa, context, "Upgrade Speed")
			press(qa, context, "Cancel")
			for _, currency in { "Coins", "Gems" } do
				Check.that(
					context,
					Check.field(extended(qa), "wallet", currency) == Check.field(before, "wallet", currency),
					"Cancel spends no " .. currency
				)
			end
			press(qa, context, "Upgrade Speed")
			press(qa, context, "Confirm")
			Check.that(
				context,
				Check.eventually(4, function()
					local after = extended(qa)
					return Check.number(after, "wallet", "Coins") < Check.number(before, "wallet", "Coins")
						and Check.number(after, "wallet", "Gems") < Check.number(before, "wallet", "Gems")
				end),
				"an accepted upgrade charges both server balances"
			)
			back(qa, context)
		end,
		function(qa, context)
			extended(qa, "reset")
			press(qa, context, "Party")
			local typed, detail = qa:typeText({ role = "input" }, "zzzz-unmatched")
			Check.that(context, typed, detail)
			Check.gone(qa, context, { text = "Mira", clipped = true }, "search filters friends")
			press(qa, context, "Clear")
			Check.visible(qa, context, { text = "Mira", clipped = true }, "Clear restores friends")
			back(qa, context)
		end,
	}
	local result: { Play.Case } = {}
	for turn = 1, math.min(index, #bodies) do
		if turn == 4 then
			continue
		end
		table.insert(result, { id = "universal/change-" .. tostring(turn), tier = "universal", run = bodies[turn] })
	end
	return result
end

return { cases = cases }
