--!strict

local task = require("@std/task")

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local PLAY: QA.Query = { role = "button", exact = "play" }
local LEAVE: QA.Query = { role = "button", text = "leave queue" }

type Snapshot = { phase: string, players: number, needed: number, countdown: number? }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local countdown = Check.field(value, "countdown")
	return {
		phase = tostring(Check.field(value, "state", "phase")),
		players = Check.number(value, "state", "players"),
		needed = Check.number(value, "state", "needed"),
		countdown = if type(countdown) == "number" then countdown else nil,
	}
end

local function shownCountdown(qa: QA.QA): number?
	local text = qa:hasText("match starts in%s*%d+")
	if text == nil then
		return nil
	end
	return tonumber(string.match(string.lower(text), "match starts in%s*(%d+)"))
end

local function join(qa: QA.QA, context: Core.Context, mode: string)
	Check.visible(qa, context, PLAY, "the lobby shows a Play button", 20)
	Check.tap(qa, context, PLAY, "press Play")
	Check.visible(qa, context, { role = "button", text = mode }, "the mode choice shows " .. mode, 4)
	Check.tap(qa, context, { role = "button", text = mode }, "choose " .. mode)
	Check.that(
		context,
		Check.eventually(4, function()
			return state(qa).phase == "Queue"
		end),
		"the server put the player in the queue"
	)
end

local behavior: { Case } = {
	{
		id = "shows-play",
		tier = "spec",
		run = function(qa, context)
			qa:admin("manual")
			Check.visible(qa, context, PLAY, "the lobby shows a Play button", 20)
			qa:capture("1-lobby")
		end,
	},
	{
		id = "shows-modes",
		tier = "spec",
		screen = "modes",
		shot = "2-modes",
		run = function(qa, context)
			Check.tap(qa, context, PLAY, "press Play")
			Check.visible(qa, context, { role = "button", text = "solo" }, "the mode choice shows Solo", 4)
			Check.text(qa, context, Check.count("4") .. "%s*players", "Solo shows 4 players", 2)
			Check.text(qa, context, Check.count("6") .. "%s*players", "Duo shows 6 players", 2)
			qa:capture("2-modes")
			qa:dump("modes")
			Check.tap(qa, context, { role = "button", exact = "back" }, "go back")
			Check.visible(qa, context, PLAY, "Back shows the Play button again", 4)
		end,
	},
	{
		id = "joins-the-queue",
		tier = "spec",
		screen = "queue",
		shot = "3-queue",
		run = function(qa, context)
			join(qa, context, "Solo")
			Check.text(qa, context, "1%s*/%s*4", "the queue shows 1/4", 4)
			Check.text(qa, context, "need 3 more players", "the queue shows Need 3 more players", 3)
			qa:capture("3-queue")
			qa:dump("queue")
		end,
	},
	{
		id = "follows-the-server-count",
		tier = "spec",
		run = function(qa, context)
			qa:admin("addPlayers", { count = 2 })
			Check.text(qa, context, "3%s*/%s*4", "the queue shows 3/4", 4)
			Check.text(qa, context, "need 1 more player", "the queue shows Need 1 more player", 3)
		end,
	},
	{
		id = "leaves-the-queue",
		tier = "spec",
		run = function(qa, context)
			Check.tap(qa, context, LEAVE, "press Leave Queue")
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).phase == "Lobby"
				end),
				"the server removed the player from the queue"
			)
			Check.visible(qa, context, PLAY, "the Play button comes back", 4)
			Check.that(context, qa:first(LEAVE) == nil, "the queue panel hides")
		end,
	},
	{
		id = "counts-down-when-full",
		tier = "spec",
		screen = "countdown",
		shot = "4-countdown",
		run = function(qa, context)
			join(qa, context, "Duo")
			qa:admin("addPlayers", { count = 5 })
			Check.that(
				context,
				Check.eventually(4, function()
					return state(qa).phase == "Countdown"
				end),
				"the server started the countdown"
			)
			Check.text(qa, context, "6%s*/%s*6", "the queue shows 6/6", 4)
			local shown = nil :: number?
			Check.that(
				context,
				Check.eventually(4, function()
					shown = shownCountdown(qa)
					local left = state(qa).countdown
					return shown ~= nil and left ~= nil and math.abs((shown :: number) - left) <= 1.6
				end),
				"Match starts in N matches the server countdown"
			)
			task.wait(2)
			local later = shownCountdown(qa)
			Check.that(
				context,
				shown ~= nil and later ~= nil and (later :: number) < (shown :: number),
				"the countdown goes down"
			)
			qa:capture("4-countdown")
			qa:dump("countdown")
		end,
	},
	{
		id = "stops-when-a-player-leaves",
		tier = "spec",
		run = function(qa, context)
			qa:admin("removePlayers", { count = 1 })
			Check.text(qa, context, "need 1 more player", "the queue needs a player again", 4)
			Check.absent(qa, context, "match starts in", "the countdown stops", 3)
		end,
	},
	{
		id = "starts-the-match",
		tier = "spec",
		run = function(qa, context)
			qa:admin("addPlayers", { count = 1 })
			Check.text(qa, context, "match starts in", "the countdown starts again", 4)
			qa:admin("finishCountdown")
			Check.text(qa, context, "starting match", "the lobby shows Starting match", 5)
			Check.that(context, qa:first(LEAVE) == nil, "Leave Queue hides while the match starts")
			qa:capture("5-starting")
			Check.text(qa, context, "round", "the queue starts the race", 15)
		end,
	},
}

return behavior
