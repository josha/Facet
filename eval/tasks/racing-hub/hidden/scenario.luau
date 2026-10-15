--!strict

local process = require("@std/process")

local Check = require("../../../../tools/play/host/check")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")
local Coherence = require("./coherence")
local Cross = require("./cross")

type System = { id: string, coins: number?, gems: number?, cases: { Play.Case }, screens: { [string]: string }? }
local systems: { System } = {
	{ id = "shop", coins = 320, gems = 40, cases = require("./shop") },
	{ id = "inventory", cases = require("./inventory") },
	{ id = "settings", cases = require("./settings") },
	{ id = "codes", coins = 120, gems = 5, cases = require("./codes"), screens = { feedback = "code-feedback" } },
	{ id = "daily-rewards", coins = 250, gems = 12, cases = require("./daily-rewards") },
	{ id = "pack-opening", gems = 200, cases = require("./pack-opening") },
	{ id = "vehicle-garage", cases = require("./vehicle-garage"), screens = { details = "kart-details" } },
	{
		id = "character-shop",
		coins = 700,
		cases = require("./character-shop"),
		screens = { details = "driver-details", confirm = "driver-confirm" },
	},
	{ id = "npc-dialogue", coins = 0, cases = require("./npc-dialogue") },
	{ id = "hud-dock", coins = 1180, gems = 120, cases = require("./hud-dock") },
	{ id = "lobby-queue", cases = require("./lobby-queue") },
	{ id = "round-hud", cases = require("./round-hud") },
}

local function selected(): { [string]: boolean }?
	for index, word in process.args do
		if word == "--systems" and process.args[index + 1] ~= nil then
			local chosen: { [string]: boolean } = {}
			for id in string.gmatch(process.args[index + 1], "[^,]+") do
				chosen[id] = true
			end
			return chosen
		end
	end
	return nil
end

local only = selected()

local function cases(): { Play.Case }
	local result: { Play.Case } = {}
	table.insert(result, {
		id = "idle-hub-needs-player-input",
		run = function(qa, context)
			local before = qa:call("racingState")
			qa:sleep(3)
			local after = qa:call("racingState")
			Check.that(context, Check.field(after, "racing") == false, "the player stays out of a race without input")
			Check.that(
				context,
				math.abs(Check.number(after, "x") - Check.number(before, "x")) < 2
					and math.abs(Check.number(after, "z") - Check.number(before, "z")) < 2,
				"the game does not move the idle player"
			)
			local value = qa:admin("state")
			Check.that(
				context,
				Check.field(value, "systems", "lobby-queue", "state", "phase") == "Lobby",
				"the queue stays idle without input"
			)
			Check.that(
				context,
				qa:first({ role = "button", exact = "close" }) == nil,
				"no dialog opens without player input"
			)
		end,
	})
	for _, system in systems do
		if only ~= nil and not only[system.id] then
			continue
		end
		local function screen(name: string): string
			return if system.screens ~= nil then system.screens[name] or name else name
		end
		table.insert(result, {
			id = system.id .. "/prepare",
			run = function(qa: QA.QA)
				qa:admin("manual")
				qa:admin("system", { system = "hud-dock", command = "pause" })
				qa:admin("wallet", { coins = system.coins, gems = system.gems })
				qa:admin("phase", { phase = "Intermission", seconds = 600 })
			end,
		})
		for _, case in system.cases do
			table.insert(result, {
				id = system.id .. "/" .. case.id,
				screen = if case.screen ~= nil then screen(case.screen) else nil,
				shot = if case.shot ~= nil then system.id .. "-" .. case.shot else nil,
				run = function(qa, context)
					local scoped = table.clone(qa)
					scoped.admin = function(_self: QA.QA, command: string, args: unknown?): unknown
						return qa:admin("system", { system = system.id, command = command, args = args })
					end
					scoped.capture = function(_self: QA.QA, name: string)
						qa:capture(system.id .. "-" .. name)
					end
					scoped.dump = function(_self: QA.QA, name: string)
						qa:dump(screen(name))
						Coherence.observe(qa.device.id, screen(name))
					end
					case.run(scoped, context)
				end,
			})
		end
	end
	if only == nil then
		for _, case in Cross do
			table.insert(result, case)
		end
	end
	table.insert(result, {
		id = "modal-scrims-cover-viewport",
		run = function(qa, context)
			Check.that(
				context,
				Coherence.insets(qa.device.id).scrims,
				"every open modal or sheet dims the full viewport within one pixel"
			)
		end,
	})
	table.insert(result, {
		id = "hud-and-controls-respect-insets",
		run = function(qa, context)
			Check.that(
				context,
				Coherence.insets(qa.device.id).content,
				"visible text and controls clear core UI and device unsafe areas"
			)
		end,
	})
	table.insert(result, {
		id = "selection-stays-valid",
		run = function(qa, context)
			Check.that(
				context,
				Check.number(qa:call("racingState"), "invalidSelections") == 0,
				"no invalid selection warning occurs during navigation or transitions"
			)
			Check.that(
				context,
				Coherence.insets(qa.device.id).selection,
				"selection targets a visible live selectable control"
			)
		end,
	})
	table.insert(result, {
		id = "coherence",
		run = function(qa, context)
			Coherence.check(qa.device.id, context)
		end,
	})
	table.insert(result, {
		id = "hub-reachable",
		run = function(qa, context)
			Check.visible(qa, context, { role = "button", exact = "shop" }, "the player can return to the hub")
		end,
	})
	return result
end

local scenario: Play.Scenario = { sessions = {} }
for _, device in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
	table.insert(scenario.sessions, { device = device, cases = cases() })
end
return scenario
