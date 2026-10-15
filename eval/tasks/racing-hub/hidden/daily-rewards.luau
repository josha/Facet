--!strict

local task = require("@std/task")

local Check = require("../../../../tools/play/host/check")
local Core = require("../../../../tools/vendor/verify/src/core")
local Play = require("../../../../tools/play/host/play")
local QA = require("../../../../tools/play/host/qa")

type Case = Play.Case

local HUD: QA.Query = { role = "button", text = "rewards" }
local CLAIM: QA.Query = { role = "button", exact = "claim" }
local STATES = { "claimed", "today", "locked" }

type Snapshot = { day: number, claimedToday: boolean, gems: number, coins: number, remaining: number }

local function state(qa: QA.QA): Snapshot
	local value = qa:admin("state")
	local nextClaimAt = Check.number(value, "state", "nextClaimAt")
	local now = Check.number(value, "now")
	return {
		day = Check.number(value, "state", "day"),
		claimedToday = Check.field(value, "state", "claimedToday") == true,
		gems = Check.number(value, "state", "wallet", "Gems"),
		coins = Check.number(value, "state", "wallet", "Coins"),
		remaining = if nextClaimAt > 0 then nextClaimAt - now else 0,
	}
end

local function ready(qa: QA.QA): boolean
	local button = qa:first(HUD)
	if button ~= nil and string.find(string.lower(button.label), "ready", 1, true) ~= nil then
		return true
	end
	local badge = qa:first({ pattern = "^ready$", near = "rewards" })
	return badge ~= nil and (badge.score or math.huge) <= 3
end

local function dayState(qa: QA.QA, day: number): string?
	local best: string? = nil
	local bestScore = math.huge
	for _, word in STATES do
		local found = qa:first({ pattern = "^" .. word .. "$", near = "day " .. day, clipped = true })
		if found ~= nil and (found.score or math.huge) < bestScore then
			best = word
			bestScore = found.score or math.huge
		end
	end
	return best
end

local function countdown(qa: QA.QA): number?
	local text = qa:hasText("next reward in %d+:%d%d:%d%d")
	if text == nil then
		return nil
	end
	local hours, minutes, seconds = string.match(text, "(%d+):(%d%d):(%d%d)")
	if hours == nil then
		return nil
	end
	return tonumber(hours) :: number * 3600 + tonumber(minutes) :: number * 60 + tonumber(seconds) :: number
end

local function open(qa: QA.QA, context: Core.Context)
	Check.visible(qa, context, HUD, "the HUD shows a Rewards button", 20)
	Check.tap(qa, context, HUD, "open the daily rewards")
	Check.visible(qa, context, { text = "Day 7", clipped = true }, "the panel lists the seven days", 5)
end

local function close(qa: QA.QA, context: Core.Context)
	Check.tap(qa, context, { role = "button", text = "close" }, "close the panel")
	Check.gone(qa, context, { text = "Day 7" }, "the panel closes", 4)
end

local function claimToday(qa: QA.QA, context: Core.Context, gemsBefore: number)
	Check.tap(qa, context, CLAIM, "claim today's reward")
	Check.that(
		context,
		Check.eventually(5, function()
			return state(qa).claimedToday
		end),
		"the server recorded the claim"
	)
	Check.that(context, state(qa).gems == gemsBefore + 5, "the server paid the 5 Gems of Day 3")
	Check.text(qa, context, "you got.*5%s*gems", "the panel shows You got 5 Gems", 4)
end

local behavior: { Case } = {
	{
		id = "hud-shows-ready",
		run = function(qa, context)
			Check.visible(qa, context, HUD, "the HUD shows a Rewards button", 20)
			Check.that(
				context,
				Check.eventually(4, function()
					return ready(qa)
				end),
				"the Rewards button shows Ready"
			)
			qa:capture("1-hud")
		end,
	},
	{
		id = "shows-the-track",
		screen = "track",
		shot = "2-track",
		run = function(qa, context)
			open(qa, context)
			for day = 1, 7 do
				Check.that(
					context,
					qa:first({ text = "Day " .. day, clipped = true }) ~= nil,
					("the panel shows Day %d"):format(day)
				)
			end
			Check.that(context, qa:first({ pattern = "5%s*gems", clipped = true }) ~= nil, "Day 3 shows 5 Gems")
			Check.that(
				context,
				qa:first({ pattern = "legendary crate", clipped = true }) ~= nil,
				"Day 7 shows the Legendary Crate"
			)
			qa:capture("2-track")
			qa:dump("track")
		end,
	},
	{
		id = "marks-day-states",
		run = function(qa, context)
			Check.that(context, dayState(qa, 1) == "claimed", "Day 1 shows Claimed")
			Check.that(context, dayState(qa, 2) == "claimed", "Day 2 shows Claimed")
			Check.that(context, dayState(qa, 3) == "today", "Day 3 shows Today")
			Check.that(context, dayState(qa, 5) == "locked", "Day 5 shows Locked")
			Check.visible(qa, context, CLAIM, "today's reward has a Claim button", 3)
		end,
	},
	{
		id = "claims-today",
		screen = "claimed",
		shot = "3-claimed",
		run = function(qa, context)
			claimToday(qa, context, 12)
			Check.that(
				context,
				Check.eventually(4, function()
					return dayState(qa, 3) == "claimed"
				end),
				"Day 3 shows Claimed after the claim"
			)
			Check.gone(qa, context, CLAIM, "no reward can be claimed twice", 3)
			qa:capture("3-claimed")
			qa:dump("claimed")
		end,
	},
	{
		id = "counts-down",
		run = function(qa, context)
			local first = countdown(qa)
			Check.that(context, first ~= nil, "the panel shows Next reward in H:MM:SS")
			local remaining = state(qa).remaining
			Check.that(
				context,
				first ~= nil and math.abs((first :: number) - remaining) <= 5,
				("the countdown %s matches the server wait of %d seconds"):format(
					tostring(first),
					math.floor(remaining)
				)
			)
			task.wait(3)
			local second = countdown(qa)
			Check.that(
				context,
				first ~= nil and second ~= nil and (second :: number) < (first :: number),
				"the countdown goes down every second"
			)
		end,
	},
	{
		id = "hides-ready",
		run = function(qa, context)
			close(qa, context)
			Check.visible(qa, context, HUD, "the HUD shows the Rewards button again", 4)
			Check.that(context, not ready(qa), "the Rewards button no longer shows Ready")
			open(qa, context)
		end,
	},
	{
		id = "follows-a-new-day",
		run = function(qa, context)
			qa:admin("advance")
			Check.visible(qa, context, CLAIM, "the next day can be claimed without reopening the panel", 5)
			Check.that(
				context,
				Check.eventually(4, function()
					return dayState(qa, 4) == "today"
				end),
				"Day 4 shows Today"
			)
			close(qa, context)
			Check.that(
				context,
				Check.eventually(4, function()
					return ready(qa)
				end),
				"the Rewards button shows Ready again"
			)
			open(qa, context)
		end,
	},
	{
		id = "explains-a-missed-day",
		run = function(qa, context)
			qa:admin("miss")
			Check.text(qa, context, "missed a day", "the panel says that the streak started again", 5)
			Check.that(
				context,
				Check.eventually(4, function()
					return dayState(qa, 1) == "today"
				end),
				"Day 1 shows Today after the restart"
			)
			qa:capture("4-missed")
		end,
	},
	{
		id = "closes-rewards",
		run = function(qa, context)
			close(qa, context)
		end,
	},
}

return behavior
