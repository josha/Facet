--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
local Lute = require("../../../../tools/vendor/verify/src/lute")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local Check = require("../../../../tools/play/host/check")
local QA = require("../../../../tools/play/host/qa")
local Space = require("./race-space")
local Catalog = require("../starter/src/shared/Hub/Catalog")
local Outcomes = require("./outcomes")

local turns = {
	"hub-shop-categories",
	"hub-garage-sort",
	"hub-settings-reset",
	"hub-race-scoreboard",
	"hub-livery-editor",
	"hub-track-vote",
	"hub-quick-chat",
	"hub-upgrades",
	"hub-party-invite",
	"hub-first-time-tutorial",
}
local panels = {
	"Shop",
	"Garage",
	"Inventory",
	"Drivers",
	"Crates",
	"Daily Rewards",
	"Codes",
	"Settings",
	"Boosts",
	"Quests",
	"Offer",
	"Play",
}
local added = { "", "", "", "", "Livery", "Track Vote", "Quick Chat", "Upgrades", "Party", "Tutorial" }

local function query(words: string): QA.Query
	return { role = "button", text = string.lower(words) }
end

local function press(qa: QA.QA, context: Core.Context, words: string)
	qa:reveal(query(words))
	Check.tap(qa, context, query(words), "use " .. words)
end

local function back(qa: QA.QA, context: Core.Context)
	local found: QA.Query? = nil
	for _, word in { "Close", "Back", "Cancel", "Skip", "Return" } do
		local candidate: QA.Query = { role = "button", text = string.lower(word) }
		if qa:first(candidate) ~= nil then
			found = candidate
			break
		end
	end
	Check.that(context, found ~= nil, "the screen has a clear way back")
	if qa.device.mode == "gamepad" then
		local ok, detail = qa:press("Backspace")
		Check.that(context, ok, detail)
	else
		Check.tap(qa, context, found :: QA.Query, "return one level")
	end
end

local function observe(qa: QA.QA, context: Core.Context, screen: string): Audit.Dump
	qa:dump(screen)
	qa:capture(screen)
	local output: string? = nil
	for index, word in process.args do
		if word == "--outputs" then
			output = process.args[index + 1]
		end
	end
	assert(output, "universal geometry needs an output directory")
	local dump =
		Audit.decode(Lute.parse(fs.readFileToString(output .. "/dumps/" .. qa.device.id .. "/" .. screen .. ".json")))
	local report = Audit.analyze(dump, { touch = qa.device.mode == "touch", gamepad = qa.device.mode == "gamepad" })
	for _, rule in
		{
			"text-truncated",
			"text-clipped",
			"contrast-low",
			"offscreen",
			"outside-safe-area",
			"touch-target-small",
			"interactive-overlap",
			"focus-hidden",
		}
	do
		Check.that(context, report.rules[rule].count == 0, screen .. ": " .. rule)
	end
	Check.that(context, Space.textClear(dump), "text does not overlap")
	Check.that(context, Space.safeContent(dump), "content clears core UI and cutouts")
	Check.that(context, Space.visibleScrimsCover(dump), "visible scrims cover the screen")
	for _, element in dump.elements do
		if element.visible and element.text ~= nil and element.text.content ~= "" then
			Check.that(context, element.text.size >= 14, "visible text has a readable size")
		end
	end
	Check.that(context, Space.selectionValid(dump), "selection is valid")
	if qa.device.mode == "touch" then
		local controls = qa:call("touchControls")
		Check.that(context, Check.field(controls, "available") == true, "runtime touch controls are observable")
		local regions: { Space.TouchRect } = {}
		local raw = Check.field(controls, "rectangles")
		assert(type(raw) == "table", "runtime touch rectangles are required")
		for _, item in raw :: { unknown } do
			local path = Check.field(item, "path")
			table.insert(regions, {
				path = if type(path) == "string" then path else nil,
				x = Check.number(item, "rect", "x"),
				y = Check.number(item, "rect", "y"),
				width = Check.number(item, "rect", "width"),
				height = Check.number(item, "rect", "height"),
			})
		end
		context:attach(screen .. "-touch-controls", "application/json", Lute.encode(controls))
		Check.that(
			context,
			Space.touchControlsClear(dump, regions),
			"UI and HUD text clear the actual thumbstick, jump and CAS buttons"
		)
	end
	return dump
end

local function cases(id: string): { Play.Case }
	local result: { Play.Case } = {}
	local function add(name: string, screen: string?, run: Play.CaseBody)
		table.insert(result, { id = "universal/" .. name, tier = "universal", screen = screen, run = run })
	end
	add("hub", "universal-hub", function(qa, context)
		qa:admin("manual")
		qa:admin("phase", { phase = "Intermission", seconds = 600 })
		Check.visible(qa, context, query("Shop"), "hub actions are available", 20)
		Check.that(context, qa:first({ role = "button", exact = "back" }) == nil, "root has no Back action")
		observe(qa, context, "universal-hub")
	end)
	local routes: { string } = if id == "racing-hub-slice"
		then { "Shop", "Boosts", "Quests", "Offer" }
		else table.clone(panels)
	local index = table.find(turns, id) or 0
	for earlier = 1, index do
		if added[earlier] ~= "" then
			table.insert(routes, added[earlier])
		end
	end
	for _, name in routes do
		local screen = "universal-" .. string.gsub(string.lower(name), " ", "-")
		add("route-" .. screen, screen, function(qa, context)
			press(qa, context, name)
			qa:sleep(0.5)
			observe(qa, context, screen)
			if name == "Tutorial" then
				local first = qa:hasText("step")
				press(qa, context, "Next")
				Check.that(context, qa:hasText("step") ~= first, "Next advances help")
				press(qa, context, "Back")
				Check.that(context, qa:hasText("step") == first, "Back restores the previous help step")
				press(qa, context, "Skip")
			else
				back(qa, context)
			end
			for _, words in { "close", "back", "cancel", "skip" } do
				Check.that(
					context,
					qa:first({ role = "button", exact = words }) == nil,
					"the route is no longer stuck on a child screen"
				)
			end
			Check.visible(qa, context, query(name), "return to the opener")
			if qa.device.mode == "gamepad" then
				local selected = qa:selected()
				Check.that(
					context,
					selected ~= nil and string.find(string.lower(selected.label), string.lower(name), 1, true) ~= nil,
					"selection returns to the opener"
				)
			end
		end)
	end
	for _, case in Outcomes.cases(index, { press = press, back = back }) do
		table.insert(result, case)
	end
	add("server-wallet-and-errors", nil, function(qa, context)
		qa:admin("wallet", { coins = 0, gems = 0 })
		press(qa, context, "Shop")
		local snapshot = qa:admin("system", { system = "shop", command = "state" })
		local item: Catalog.Item? = nil
		for _, candidate in Catalog.items do
			if Check.field(snapshot, "state", "owned", candidate.id) ~= true then
				item = candidate
				break
			end
		end
		if item == nil then
			for _, candidate in Catalog.items do
				qa:reveal({ text = candidate.name })
				Check.visible(
					qa,
					context,
					{ pattern = "owned", near = candidate.name, clipped = true },
					"already purchased items show ownership"
				)
			end
			back(qa, context)
			return
		end
		local chosen = item
		local action: QA.Query = { role = "button", text = "buy", near = chosen.name }
		qa:reveal(action)
		local button = Check.visible(qa, context, action, "an unowned item can be inspected")
		if button.interactable then
			Check.tap(qa, context, action, "try without funds")
		end
		Check.that(
			context,
			Check.eventually(3, function()
				for _, text in qa:texts() do
					if
						string.find(string.lower(text), "enough")
						or string.find(string.lower(text), "insufficient")
						or string.find(string.lower(text), "need")
					then
						return true
					end
				end
				return false
			end),
			"a failed purchase explains missing funds"
		)
		local refused = qa:admin("system", { system = "shop", command = "state" })
		Check.that(
			context,
			Check.field(refused, "state", "owned", chosen.id) ~= true,
			"a refused purchase grants nothing"
		)
		qa:admin("wallet", { coins = chosen.price + 37, gems = chosen.price + 37 })
		qa:sleep(0.5)
		Check.tap(qa, context, action, "buy with enough funds")
		for _, words in { "Confirm", "Confirm purchase" } do
			if qa:first(query(words)) ~= nil then
				press(qa, context, words)
				break
			end
		end
		Check.that(
			context,
			Check.eventually(5, function()
				return Check.field(
					qa:admin("system", { system = "shop", command = "state" }),
					"state",
					"owned",
					chosen.id
				) == true
			end),
			"a successful purchase reaches the server"
		)
		local bought = qa:admin("system", { system = "shop", command = "state" })
		Check.that(
			context,
			Check.number(bought, "state", "wallet", chosen.currency) == 37,
			"the server charges the displayed catalog price once"
		)
		Check.that(
			context,
			Check.eventually(3, function()
				return qa:first({ pattern = "owned", near = chosen.name, clipped = true }) ~= nil
			end),
			"ownership follows server success"
		)
		Check.text(qa, context, Check.count("37"), "the visible balance follows the server")
		back(qa, context)
	end)
	if id ~= "racing-hub-slice" then
		add("mechanic", "universal-mechanic", function(qa, context)
			qa:admin("system", { system = "npc-dialogue", command = "approach" })
			press(qa, context, "Talk to Mechanic")
			observe(qa, context, "universal-mechanic")
			if qa:first(query("Leave")) ~= nil then
				press(qa, context, "Leave")
			end
			if qa:first(query("Close")) ~= nil then
				back(qa, context)
			end
			Check.visible(qa, context, query("Shop"), "dialogue has a route back")
		end)
		add("queue-cancel", "universal-queue", function(qa, context)
			qa:admin("system", { system = "lobby-queue", command = "manual" })
			press(qa, context, "Play")
			press(qa, context, "Solo")
			Check.that(
				context,
				Check.eventually(4, function()
					return Check.field(
						qa:admin("system", { system = "lobby-queue", command = "state" }),
						"state",
						"phase"
					) == "Queue"
				end),
				"joining reaches the server"
			)
			observe(qa, context, "universal-queue")
			press(qa, context, "Leave Queue")
			Check.that(
				context,
				Check.eventually(4, function()
					return Check.field(
						qa:admin("system", { system = "lobby-queue", command = "state" }),
						"state",
						"phase"
					) == "Lobby"
				end),
				"leaving cancels the server queue"
			)
			Check.visible(qa, context, query("Play"), "queue cannot trap the player")
		end)
		add("race-driving", "universal-race", function(qa, context)
			qa:admin("phase", { phase = "Round", seconds = 120 })
			qa:sleep(2)
			local race = observe(qa, context, "universal-race")
			Check.that(context, Space.centerClear(race), "the road remains visible while driving")
			Check.that(context, qa:selected() == nil, "passive HUD releases gamepad selection")
			if index >= 4 then
				press(qa, context, "Scoreboard")
				observe(qa, context, "universal-scoreboard")
				back(qa, context)
			end
			qa:admin("phase", { phase = "Results", seconds = 120 })
			qa:sleep(1)
			observe(qa, context, "universal-results")
			press(qa, context, "hub")
			Check.visible(qa, context, query("Shop"), "results return to the hub")
		end)
	end
	return result
end

local function scenario(id: string): Play.Scenario
	for _, word in process.args do
		if word == "--systems" then
			id = "racing-hub-slice"
		end
	end
	local result: Play.Scenario = { sessions = {} }
	for _, device in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
		table.insert(result.sessions, { device = device, cases = cases(id) })
	end
	return result
end

return { scenario = scenario, observe = observe, back = back, press = press, turns = turns }
