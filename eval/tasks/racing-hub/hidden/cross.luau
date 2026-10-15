--!strict

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")
local Core = require("../../../../tools/vendor/verify/src/core")
local Coherence = require("./coherence")

local function tap(qa: QA.QA, context: Core.Context, words: string)
	Check.tap(qa, context, { role = "button", exact = string.lower(words) }, words)
end

local function value(qa: QA.QA, ...: string): unknown
	return Check.field(qa:admin("state"), ...)
end

local function returned(qa: QA.QA, context: Core.Context, words: string)
	if qa.device.id == "console" then
		local selected = qa:selected()
		Check.that(
			context,
			selected ~= nil and string.lower(selected.label) == string.lower(words),
			"selection returns to " .. words
		)
	end
end

local cases: { Play.Case } = {
	{
		id = "race-results-return",
		tier = "spec",
		run = function(qa, context)
			qa:admin("phase", { phase = "Round", seconds = 120 })
			qa:admin("phase", { phase = "Results", seconds = 120 })
			Check.text(qa, context, "finish order", "the race ends with results")
			tap(qa, context, "Back to hub")
			Check.that(
				context,
				Check.eventually(4, function()
					return value(qa, "systems", "round-hud", "state", "phase") == "Intermission"
				end),
				"Back returns to the hub without a server reset"
			)
		end,
	},
	{
		id = "overlay-stack-and-focus",
		tier = "spec",
		screen = "overlay-stack",
		run = function(qa, context)
			tap(qa, context, "Shop")
			Check.text(qa, context, "sport motor", "the Shop opens over the HUD")
			tap(qa, context, "Codes")
			Check.visible(qa, context, { role = "button", text = "redeem" }, "Codes opens over the Shop")
			qa:dump("overlay-stack")
			Coherence.observe(qa.device.id, "overlay-stack")
			qa:capture("overlay-stack")
			tap(qa, context, "Close")
			Check.visible(qa, context, { text = "Sport Motor", clipped = true }, "Close returns one level to the Shop")
			returned(qa, context, "Codes")
			if qa.device.id == "console" then
				local ok = qa:press("Backspace")
				Check.that(context, ok, "the console Back action is delivered")
			else
				tap(qa, context, "Close")
			end
			Check.gone(qa, context, { text = "Sport Motor" }, "the second Close or Back returns to the hub")
			returned(qa, context, "Shop")
		end,
	},
	{
		id = "purchase-flows-to-hud-and-garage",
		tier = "spec",
		screen = "shared-wallet",
		run = function(qa, context)
			qa:admin("wallet", { coins = 500, gems = 200 })
			tap(qa, context, "Shop")
			Check.tap(qa, context, { role = "button", exact = "buy", near = "Road Wheels" }, "buy Road Wheels")
			Check.that(
				context,
				Check.eventually(5, function()
					return value(qa, "systems", "shop", "state", "owned", "road_wheels") == true
				end),
				"the server records ownership"
			)
			Check.that(context, value(qa, "state", "wallet", "Coins") == 350, "the shared wallet pays once")
			Check.text(qa, context, "350%s*coins", "the Shop refreshes its balance")
			tap(qa, context, "Close")
			Check.text(qa, context, "350%s*coins", "the HUD refreshes its balance")
			tap(qa, context, "Garage")
			tap(qa, context, "Inventory")
			Check.tap(qa, context, { role = "button", text = "Road Wheels" }, "inspect the purchased part")
			Check.tap(qa, context, { role = "button", exact = "equip" }, "equip the purchased part")
			Check.that(
				context,
				Check.eventually(4, function()
					return value(qa, "systems", "inventory", "state", "equipped", "Wheels") == "road_wheels"
				end),
				"the garage equips the purchased part in its slot"
			)
			qa:dump("shared-wallet")
			Coherence.observe(qa.device.id, "shared-wallet")
			qa:capture("shared-wallet")
			tap(qa, context, "Close")
			tap(qa, context, "Close")
		end,
	},
	{
		id = "quest-crate-connects-to-collection",
		tier = "spec",
		run = function(qa, context)
			local crates = tonumber(value(qa, "state", "crates")) or 0
			Check.that(context, crates == 1, "the mechanic rewarded one crate")
			local gems = value(qa, "state", "wallet", "Gems")
			tap(qa, context, "Crates")
			Check.tap(qa, context, { role = "button", exact = "open", near = "Starter Crate" }, "open the earned crate")
			tap(qa, context, "Open")
			Check.visible(qa, context, { role = "button", exact = "reveal all" }, "the earned crate has a reveal")
			tap(qa, context, "Reveal All")
			tap(qa, context, "Done")
			Check.that(
				context,
				value(qa, "state", "crates") == 0 and value(qa, "state", "wallet", "Gems") == gems,
				"the earned crate is consumed without a second charge"
			)
			tap(qa, context, "Close")
		end,
	},
	{
		id = "queue-loadout-race-rewards",
		tier = "spec",
		screen = "race-loadout",
		run = function(qa, context)
			tap(qa, context, "Garage")
			tap(qa, context, "All")
			Check.tap(qa, context, { role = "button", text = "Aero Kart" }, "pick the Aero Kart")
			tap(qa, context, "Spawn")
			tap(qa, context, "Leave Vehicle")
			local before = qa:admin("state")
			tap(qa, context, "Play")
			Check.tap(qa, context, { role = "button", text = "solo" }, "queue for Solo")
			qa:admin("system", { system = "lobby-queue", command = "addPlayers", args = { count = 3 } })
			Check.text(qa, context, "match starts in", "the full queue counts down")
			qa:admin("system", { system = "lobby-queue", command = "finishCountdown" })
			Check.that(
				context,
				Check.eventually(5, function()
					return value(qa, "systems", "round-hud", "state", "phase") == "Round"
				end),
				"the queue starts the race"
			)
			Check.text(qa, context, "aero kart", "the chosen kart is in the race")
			Check.text(qa, context, "aiko", "the chosen driver is in the race")
			qa:admin("positions", { names = { "Nova", "You", "Pip" } })
			Check.text(qa, context, "position%s*2", "the server position reaches the HUD")
			qa:dump("race-loadout")
			Coherence.observe(qa.device.id, "race-loadout")
			qa:capture("race-loadout")
			qa:admin("phase", { phase = "Round", seconds = 120 })
			qa:admin("phase", { phase = "Results", seconds = 120 })
			Check.text(qa, context, "earned%s*50%s*coins", "results name the currency reward")
			Check.text(qa, context, "120%s*xp", "results name the XP reward")
			Check.that(
				context,
				value(qa, "state", "wallet", "Coins") == Check.number(before, "state", "wallet", "Coins") + 50,
				"race rewards pay Coins once"
			)
			Check.that(
				context,
				value(qa, "state", "wallet", "Gems") == Check.number(before, "state", "wallet", "Gems") + 5,
				"race rewards pay Gems"
			)
			Check.that(
				context,
				value(qa, "state", "xp") == Check.number(before, "state", "xp") + 120,
				"race rewards pay XP"
			)
			Check.that(
				context,
				value(qa, "state", "races") == Check.number(before, "state", "races") + 1,
				"race results advance daily race progress"
			)
			tap(qa, context, "Back to hub")
			for _, panel in { "Shop", "Crates", "Drivers", "Daily Rewards" } do
				Check.tap(
					qa,
					context,
					{ role = "button", text = string.lower(panel) },
					"open " .. panel .. " after rewards"
				)
				local state = qa:admin("state")
				local currency = if panel == "Crates" then "Gems" else "Coins"
				local balance = Check.number(state, "state", "wallet", currency)
				Check.text(
					qa,
					context,
					Check.count(tostring(balance)) .. "%s*" .. string.lower(currency),
					"the visible counter matches the shared wallet"
				)
				tap(qa, context, "Close")
			end
		end,
	},
}

for _, panel in
	{
		"Shop",
		"Inventory",
		"Settings",
		"Codes",
		"Daily Rewards",
		"Garage",
		"Drivers",
		"Crates",
		"Boosts",
		"Quests",
		"Offer",
	}
do
	local case: Play.Case = {
		id = "navigation/" .. string.gsub(string.lower(panel), " ", "-"),
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, { role = "button", text = string.lower(panel) }, "open " .. panel)
			Coherence.returnControl(qa, context)
			if qa.device.id == "console" then
				local ok = qa:press("Backspace")
				Check.that(context, ok, "Back closes one level")
			else
				tap(qa, context, "Close")
			end
			Check.visible(qa, context, { role = "button", exact = "shop" }, "the hub is reachable without a reset")
			returned(qa, context, panel)
			Check.gone(qa, context, { role = "button", exact = "back" }, "the root hub has no Back command")
		end,
	}
	table.insert(cases, case)
end

return cases
