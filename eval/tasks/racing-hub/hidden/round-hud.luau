--!strict

local task = require("@std/task")
local fs = require("@std/fs")
local process = require("@std/process")
local Audit = require("../../../../tools/vendor/verify/src/roblox/ui-audit")
local Lute = require("../../../../tools/vendor/verify/src/lute")
local RaceSpace = require("./race-space")

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local BOTS: { [string]: boolean } = {
	Nova = true,
	Pip = true,
	Rook = true,
	Zed = true,
	Ivy = true,
	Bolt = true,
	Moss = true,
}

local function server(qa: QA.QA): (string, number, string)
	local value = qa:admin("state")
	local localName = "?"
	local fighters = Check.field(value, "state", "fighters")
	if type(fighters) == "table" then
		for _, fighter in fighters :: { unknown } do
			local name = tostring(Check.field(fighter, "name"))
			if not BOTS[name] then
				localName = name
			end
		end
	end
	return tostring(Check.field(value, "state", "phase")), Check.number(value, "remaining"), localName
end

local function shownTimer(qa: QA.QA, phase: string): number?
	local fallback: number? = nil
	for _, text in qa:texts() do
		local normal = string.lower(text)
		local minutes, seconds = string.match(normal, "(%d+):(%d%d)")
		if minutes ~= nil then
			local value = tonumber(minutes) :: number * 60 + tonumber(seconds) :: number
			if string.find(normal, string.lower(phase), 1, true) ~= nil then
				return value
			end
			fallback = fallback or value
		end
	end
	return fallback
end

local function timerMatches(qa: QA.QA, context: Core.Context, phase: string)
	Check.text(qa, context, string.lower(phase), ("the HUD shows the %s phase"):format(phase), 5)
	local shown = shownTimer(qa, phase)
	local _, remaining = server(qa)
	Check.that(
		context,
		shown ~= nil and math.abs((shown :: number) - remaining) <= 2.5,
		("the timer %s matches the %d seconds left on the server"):format(tostring(shown), math.floor(remaining))
	)
	task.wait(2.5)
	local later = shownTimer(qa, phase)
	Check.that(
		context,
		shown ~= nil and later ~= nil and (later :: number) < (shown :: number),
		"the timer counts down every second"
	)
end

local function nearer(qa: QA.QA, wanted: QA.Query, other: QA.Query): boolean
	local hit = qa:first(wanted)
	if hit == nil then
		return false
	end
	local rival = qa:first(other)
	return rival == nil or (hit.score or math.huge) < (rival.score or math.huge)
end

local function eliminate(qa: QA.QA, victim: string, by: string)
	qa:admin("eliminate", { victim = victim, by = by })
end

local function feed(qa: QA.QA, context: Core.Context, _by: string, victim: string)
	Check.text(
		qa,
		context,
		string.lower(victim) .. "%s+knocked out:%s+last on lap 1",
		("the feed shows %s knocked out: last on lap 1"):format(victim),
		4
	)
end

local function startRound(qa: QA.QA, context: Core.Context)
	qa:admin("phase", { phase = "Round", seconds = 180 })
	Check.text(qa, context, "round", "the HUD shows the Round phase", 5)
end

local function drivingDump(qa: QA.QA): Audit.Dump
	qa:dump("driving-safety")
	for index, word in process.args do
		if word == "--outputs" then
			return Audit.decode(
				Lute.parse(
					fs.readFileToString(process.args[index + 1] .. "/dumps/" .. qa.device.id .. "/driving-safety.json")
				)
			)
		end
	end
	error("--outputs is required")
end

local behavior: { Case } = {
	{
		id = "shows-intermission",
		tier = "spec",
		screen = "intermission",
		shot = "1-intermission",
		run = function(qa, context)
			qa:admin("manual")
			qa:admin("phase", { phase = "Intermission", seconds = 30 })
			timerMatches(qa, context, "Intermission")
			qa:capture("1-intermission")
			qa:dump("intermission")
		end,
	},
	{
		id = "shows-the-round",
		tier = "spec",
		run = function(qa, context)
			startRound(qa, context)
			timerMatches(qa, context, "Round")
			for name in BOTS do
				Check.visible(qa, context, { text = name, clipped = true }, "the teams list " .. name, 3)
			end
			local _, _, localName = server(qa)
			Check.that(context, qa:first({ text = "you" }) ~= nil, "the HUD marks the local player as You")
			Check.that(
				context,
				qa:first({ text = localName, clipped = true }) ~= nil,
				"the Red team lists the local player " .. localName
			)
			Check.that(
				context,
				qa:first({ pattern = "4%s*alive", near = "blue" }) ~= nil,
				"the Blue team shows 4 alive"
			)
		end,
	},
	{
		id = "driving-keeps-selection-free",
		tier = "spec",
		run = function(qa, context)
			for _ = 1, 3 do
				Check.that(context, qa:selected() == nil, "driving has no selected UI until the player opens a panel")
				task.wait(0.2)
			end
		end,
	},
	{
		id = "driving-keeps-thumbstick-free",
		tier = "spec",
		run = function(qa, context)
			local dump = drivingDump(qa)
			if table.find(qa.device.input, "touch") then
				Check.that(
					context,
					RaceSpace.thumbstickClear(dump),
					"interactive UI leaves the lower-left touch thumbstick region clear"
				)
			end
		end,
	},
	{
		id = "driving-keeps-road-clear",
		tier = "spec",
		run = function(qa, context)
			Check.that(
				context,
				RaceSpace.centerClear(drivingDump(qa)),
				"the race HUD leaves the central road corridor clear"
			)
		end,
	},
	{
		id = "marks-an-elimination",
		tier = "spec",
		screen = "round",
		shot = "2-round",
		run = function(qa, context)
			eliminate(qa, "Zed", "Nova")
			feed(qa, context, "Nova", "Zed")
			Check.that(
				context,
				Check.eventually(3, function()
					return nearer(qa, { pattern = "^out$", near = "Zed" }, { pattern = "^out$", near = "Ivy" })
				end),
				"Zed shows OUT and Ivy does not"
			)
			Check.that(
				context,
				nearer(qa, { pattern = "3%s*alive", near = "blue" }, { pattern = "3%s*alive", near = "red" }),
				"the Blue team shows 3 alive"
			)
			qa:capture("2-round")
			qa:dump("round")
		end,
	},
	{
		id = "keeps-four-feed-lines",
		tier = "spec",
		run = function(qa, context)
			eliminate(qa, "Ivy", "Rook")
			eliminate(qa, "Bolt", "Pip")
			eliminate(qa, "Pip", "Moss")
			feed(qa, context, "Moss", "Pip")
			feed(qa, context, "Nova", "Zed")
			eliminate(qa, "Rook", "Moss")
			feed(qa, context, "Moss", "Rook")
			Check.absent(qa, context, "zed%s+knocked out", "the oldest line leaves the feed", 3)
		end,
	},
	{
		id = "tells-the-player-they-are-out",
		tier = "spec",
		screen = "out",
		shot = "3-out",
		run = function(qa, context)
			local _, _, localName = server(qa)
			eliminate(qa, localName, "Moss")
			Check.text(qa, context, "you are out", "the HUD says You are out", 4)
			qa:capture("3-out")
			qa:dump("out")
		end,
	},
	{
		id = "shows-results",
		tier = "spec",
		screen = "results",
		shot = "4-results",
		run = function(qa, context)
			qa:admin("phase", { phase = "Results", seconds = 20, winner = "Blue" })
			Check.text(qa, context, "blue wins", "the results show Blue wins", 4)
			Check.text(qa, context, "earned%s*20%s*coins", "the results show You earned 20 Coins", 3)
			qa:capture("4-results")
			qa:dump("results")
		end,
	},
	{
		id = "resets-for-the-next-round",
		tier = "spec",
		run = function(qa, context)
			qa:admin("phase", { phase = "Intermission", seconds = 20 })
			Check.absent(qa, context, "blue wins", "the results hide in the intermission", 4)
			startRound(qa, context)
			Check.absent(qa, context, "knocked out", "the feed clears for the new round", 4)
			Check.absent(qa, context, "you are out", "You are out hides in the new round", 3)
		end,
	},
}

return behavior
