--!strict
local harness = require("./lib/harness")
--[[
	THE SETTLE PASS IS PART OF THE FLUSH, NOT PART OF A WATCH BODY.

	`tests/measure_publish_settle.spec.luau` pins what the pass BUYS — a
	measure→publish round trip converging inside one flush. This file pins the
	three things about the pass that an audit found nobody was looking at:

	(1) WHEN IT RUNS. Compose's single-consumer entry — the shipped shape of a
	    bound prop — is `__enqueueSettleConsumer`, and it does two different
	    things: with nothing draining it runs the consumer and drains, but
	    MID-DRAIN it appends to the queue the caller is walking and returns at
	    once. `src/render/settle_pass.luau` decorated the entry and ran the whole
	    pass either way, so a watch fanning one plain write out to twenty
	    single-sink cells swept the pass twenty-one times — and every one of
	    those sweeps landed INSIDE the writing watch's body, before it had
	    finished and before any sibling watch had run. The pass carries the
	    renderer's geometry re-solve, so that is the surface re-solving against a
	    half-written frame. The same write inside `runtime:batch` cost one sweep;
	    one is the number both shapes must cost.

	(2) WHAT IT IS BUILT ON. Three of the four hooks it decorates or reads are
	    PRIVATE to the vendored Compose reactor. The old code guarded the most
	    important one with `if inline ~= nil`, so an upstream rename would have
	    removed the containment silently. It is now asserted at install, with a
	    message that names the pin.

	(3) THAT A CONTAINED FAILURE STAYS AUDIBLE. `services.report` warned only
	    when the message differed from the last one and never cleared it, so the
	    SECOND occurrence of any failure — a minute later, a session later — was
	    suppressed forever. Announcements are now rate-limited per message, which
	    keeps a per-frame failure from spamming without making a recurrence mute.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Compose = require("../src/vendor/compose/core")
local services = require("../src/core/services")
local settle_pass = require("../src/render/settle_pass")

local FAN = 20

--[[ The scene: one trigger, FAN cells that each carry exactly ONE terminal
	consumer (so every write takes Compose's single-consumer entry), and a watch
	that fans the trigger out across all of them in one body. ]]
local function fanOut(core: any)
	local trigger = Compose.cell(0)
	local cells = {}
	for index = 1, FAN do
		local cell = Compose.cell(0)
		cells[index] = cell
		core.owner.watchStatic(cell, function() end)
	end
	local inBody = false
	local sweeps = 0
	local sweptMidBody = false
	core.settlePass.register(function()
		sweeps += 1
		if inBody then
			sweptMidBody = true
		end
	end, "settle-probe")
	core.owner.watch(function(use)
		local value = use(trigger)
		inBody = true
		for index, cell in cells do
			cell:set(value * 100 + index)
		end
		inBody = false
	end)
	return {
		trigger = trigger,
		reset = function()
			sweeps = 0
			sweptMidBody = false
		end,
		sweeps = function(): number
			return sweeps
		end,
		sweptMidBody = function(): boolean
			return sweptMidBody
		end,
	}
end

describe("the settle pass runs once per flush, never inside a watch body", function()
	it("a plain write that fans out to twenty single-sink cells sweeps the pass ONCE", function()
		local core = harness.newCore()
		local scene = fanOut(core)
		scene.reset()
		scene.trigger:set(1)
		-- Before the fix: 21 — one sweep per fanned write, plus the outer one.
		expect(scene.sweeps()).toBe(1)
	end)

	it("the pass never runs before the writing watch has finished", function()
		local core = harness.newCore()
		local scene = fanOut(core)
		scene.reset()
		scene.trigger:set(1)
		expect(scene.sweptMidBody()).toBe(false)
	end)

	it("a plain write costs exactly what the same write inside a batch costs", function()
		local core = harness.newCore()
		local scene = fanOut(core)
		scene.reset()
		core.reactor:batch(function()
			scene.trigger:set(1)
		end)
		local batched = scene.sweeps()
		scene.reset()
		scene.trigger:set(2)
		expect(scene.sweeps()).toBe(batched)
		expect(batched).toBe(1)
	end)

	it("still converges a settle callback's own publication inside the flush", function()
		--[[ The containment must not cost the pass its purpose: a callback that
			publishes is still drained and the pass still restarts, so a measure →
			publish cycle reaches its fixed point before the write returns. ]]
		local core = harness.newCore()
		local source = Compose.cell(1)
		local published = Compose.cell(0)
		local seen = {}
		core.owner.watchStatic(source, function() end)
		core.owner.watchStatic(published, function(value)
			table.insert(seen, value)
		end)
		core.settlePass.register(function()
			local want = source:peek() * 2
			if published:peek() ~= want then
				published:set(want)
			end
		end, "publisher")
		source:set(5)
		expect(published:peek()).toBe(10)
		expect(seen[#seen]).toBe(10)
	end)
end)

describe("the settle pass asserts the vendored hooks it is built on", function()
	local function stub(over: { [string]: any }): any
		local reactor: any = {
			settle = function() end,
			batch = function(_self: any, body: any)
				return body()
			end,
			__enqueueSettleConsumer = function() end,
		}
		for key, value in over do
			reactor[key] = if value == "absent" then nil else value
		end
		return reactor
	end

	it("installs cleanly on a reactor that has all of them", function()
		local pass = settle_pass.install(stub({}), function() end)
		expect(pass.count()).toBe(0)
	end)

	for _, hook in { "__enqueueSettleConsumer", "settle", "batch" } do
		it(`refuses a reactor missing '{hook}' and names the pin`, function()
			local ok, err = pcall(function()
				settle_pass.install(stub({ [hook] = "absent" }), function() end)
			end)
			expect(ok).toBe(false)
			local message = tostring(err)
			expect(string.find(message, hook, 1, true) ~= nil).toBe(true)
			expect(string.find(message, "UPSTREAM.lock", 1, true) ~= nil).toBe(true)
		end)
	end

	it("refuses a SECOND reactor missing a hook, because `attach` is an install too", function()
		local pass = settle_pass.install(stub({}), function() end)
		local ok, err = pcall(function()
			pass.attach(stub({ __enqueueSettleConsumer = "absent" }))
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "__enqueueSettleConsumer", 1, true) ~= nil).toBe(true)
	end)
end)

describe("a contained failure stays audible", function()
	local function recordingCore()
		local warnings: { string } = {}
		local now = 0
		local core = services.new({
			warn = function(message: string)
				table.insert(warnings, message)
			end,
			now = function(): number
				return now
			end,
		})
		return core, warnings, function(seconds: number)
			now += seconds
		end
	end

	it("does not spam a failure that repeats every frame", function()
		local core, warnings = recordingCore()
		for _ = 1, 60 do
			core.report("the same failure")
		end
		expect(#warnings).toBe(1)
	end)

	it("reports the SAME failure again when it recurs later", function()
		local core, warnings, advance = recordingCore()
		core.report("the same failure")
		expect(#warnings).toBe(1)
		advance(1)
		core.report("the same failure")
		expect(#warnings).toBe(1)
		advance(services.REPORT_REPEAT_WINDOW_S)
		core.report("the same failure")
		-- Before the fix this was suppressed for the rest of the core's life.
		expect(#warnings).toBe(2)
	end)

	it("says how many it swallowed when it re-announces", function()
		local core, warnings, advance = recordingCore()
		for _ = 1, 10 do
			core.report("the same failure")
		end
		advance(services.REPORT_REPEAT_WINDOW_S)
		core.report("the same failure")
		expect(#warnings).toBe(2)
		expect(string.find(warnings[2], "9 more", 1, true) ~= nil).toBe(true)
	end)

	it("never suppresses a DIFFERENT failure", function()
		local core, warnings = recordingCore()
		core.report("first")
		core.report("second")
		core.report("first")
		expect(#warnings).toBe(3)
	end)

	it("still records the last failure for `core.lastError()`", function()
		local core = recordingCore()
		core.report("boom")
		core.report("boom")
		expect(core.lastError()).toBe("boom")
	end)
end)
