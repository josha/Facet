--!strict
-- Step-5 carry-over reproduction probe (Step 5.5 cleanup, one-shot evidence).
-- Runs the four reactive-runtime residuals' own reproductions verbatim against
-- the CURRENT source and prints what actually happens, so each is dispositioned
-- from a measurement rather than from reading the code.
-- Usage: lune run tools/lune/_probe_carryovers

local LuauUI = require("../../src") :: any
local customFactory = require("../../src/core/custom")
local adaptive = require("../../src/layout/adaptive")
local environment = require("../../src/env/environment")

local out: { string } = {}
local function say(line: string)
	table.insert(out, line)
	print(line)
end

-- ===== RR-5-R1: false double-dispose when a cleanup FUNCTION disposes a child
do
	local core = customFactory.new()
	local parent = core:scope("p")
	local child: any = nil
	parent:own(function()
		child:dispose()
	end)
	child = parent:child("c")
	parent:dispose()
	say(`RR-5-R1 lastError = {tostring(core:lastError())}`)
	say(`RR-5-R1 counters.scopes = {tostring((core:counters() :: any).scopes)}`)
end

-- ===== RR-1-R2: stats invariant "transactions must equal steps"
do
	local core = customFactory.new()
	local clock = LuauUI.motion.newClock(core, {
		now = function()
			return 0
		end,
	})
	local a = clock:spring(0, "object")
	local reads = 0
	a:setTarget(function()
		reads += 1
		if reads >= 2 then
			error("boom in a live target")
		end
		return 10
	end)
	for _ = 1, 30 do
		clock:step(1 / 60)
	end
	local stats = clock:stats()
	say(`RR-1-R2 steps={stats.steps} transactions={stats.transactions} writes={stats.writes}`)
	say(`RR-1-R2 lastError = {tostring(clock:lastError())}`)
	clock:dispose()
end

-- ===== RR-1-R1: blast radius of a PERSISTENTLY throwing live target
do
	local core = customFactory.new()
	local clock = LuauUI.motion.newClock(core, {
		now = function()
			return 0
		end,
	})
	local a = clock:spring(0, "object")
	local b = clock:spring(0, "object")
	b:setTarget(100)
	local reads = 0
	a:setTarget(function()
		reads += 1
		if reads >= 2 then
			error("boom")
		end
		return 10
	end)
	for _ = 1, 600 do
		clock:step(1 / 60)
	end
	say(`RR-1-R1 a={a:get()} b={b:get()} active={clock:activeCount()} (b target 100)`)
	clock:dispose()
end

-- ===== RR-5-R1 control: the SAME cleanup shape WITHOUT parent ownership
do
	local core = customFactory.new()
	local parent = core:scope("p")
	local standalone = core:scope("standalone") -- NOT a child of `parent`
	parent:own(function()
		standalone:dispose()
	end)
	parent:dispose()
	say(`RR-5-R1(control, non-aliased) lastError = {tostring(core:lastError())}`)
end

-- ===== RR-8 family: does a scope-less adaptive.conditions leak in a SHORT-lived core?
do
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
	local baseline = core:counters()
	for _ = 1, 50 do
		local _ = adaptive.conditions(core, env)
	end
	local after = core:counters()
	local drift = {}
	for k, v in baseline :: any do
		if (after :: any)[k] ~= v then
			table.insert(drift, `{k}: {v} -> {(after :: any)[k]}`)
		end
	end
	say(`RR-8 scope-less x50 on ONE core, counter drift = {if #drift == 0 then "none" else table.concat(drift, ", ")}`)
end

print("\n----- probe complete -----")
