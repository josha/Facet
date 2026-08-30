--!strict
--[[ THE OUTPOST POWER TERMINAL — the pure half, all of it (design
	artifacts/example-games-and-standalones/design/outpost-power-terminal.md).

	WHAT THIS FILE CAN AND CANNOT REACH, stated first because it decided the
	shape of everything below. `surface_target.new` calls
	`Instance.new("SurfaceGui")`, so the terminal's ENGINE half — the console
	part, the walk-up prompt, the second host, the responder handoff — is Studio
	evidence and is driven from `examples/gallery/scenarios/outpost_terminal.luau`.
	Everything else is a value in and a value out, and this file proves it
	exhaustively.

	THAT IS NOT A CONSOLATION PRIZE. The boundary was drawn so that it would be
	true: the RULES are pure (`examples/gallery/examples/outpost_terminal/rules`),
	the SERVER'S JUDGEMENT is pure (`rules.authorize`, with the engine reading the
	five values and this deciding on them), and the TERMINAL'S STATE MACHINE is a
	blueprint over signals with a `send` function it is handed. So the three
	things a reviewer actually wants proved — every refusal says the right
	sentence, every server check refuses what it should, and the screen's engage →
	adjust → apply → success → reset → exit really is a machine — are all provable
	here, with no engine at all.

	THE EXHAUSTIVE PASSES ARE REALLY EXHAUSTIVE. `4 x 3 x 5 = 60` is the entire
	product of legal per-consumer values, so "every range" and "what running
	means" are walked rather than sampled. A rule with sixty cases and three
	spot-checks is a rule with fifty-seven untested cases.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local world = require("./lib/world")
local terminal = require("../examples/gallery/examples/outpost_terminal") :: any
local rules = require("../examples/gallery/examples/outpost_terminal/rules") :: any

local CANVAS = terminal.CANVAS
local VIEWPORT = { x = 0, y = 0, w = CANVAS.w, h = CANVAS.h }

-- every legal allocation, which is the whole product and not a sample
local function everyAllocation(): { { [string]: number } }
	local out: { { [string]: number } } = {}
	for door = 0, rules.consumer("door").capacity do
		for beacon = 0, rules.consumer("beacon").capacity do
			for workshop = 0, rules.consumer("workshop").capacity do
				table.insert(out, { door = door, beacon = beacon, workshop = workshop })
			end
		end
	end
	return out
end

-- ═══ THE RULES ══════════════════════════════════════════════════════════════

describe("outpost rules: the ranges, walked rather than sampled", function()
	it("every value inside 0..capacity is legal, and capacity+1 and -1 are not", function()
		local problems: { string } = {}
		for _, consumer in rules.CONSUMERS do
			for value = 0, consumer.capacity do
				local allocation = { door = 0, beacon = 0, workshop = 0 }
				allocation[consumer.id] = value
				local verdict = rules.validate(allocation)
				if not verdict.ok then
					table.insert(problems, `{consumer.id} = {value} was refused: {verdict.message}`)
				end
			end
			for _, bad in { -1, consumer.capacity + 1 } do
				local allocation = { door = 0, beacon = 0, workshop = 0 }
				allocation[consumer.id] = bad
				local verdict = rules.validate(allocation)
				if verdict.code ~= "range" then
					table.insert(problems, `{consumer.id} = {bad} should be out of range, got {tostring(verdict.code)}`)
				end
				local expected = `{consumer.label} takes 0 to {consumer.capacity} units. {bad} is outside that.`
				if verdict.message ~= expected then
					table.insert(problems, `{consumer.id} = {bad} said "{verdict.message}", wanted "{expected}"`)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the three declared ranges are the design's, and the goal is reachable inside them", function()
		expect(rules.TOTAL).toBe(6)
		expect(#rules.CONSUMERS).toBe(3)
		expect(rules.consumer("door").needs).toBe(2)
		expect(rules.consumer("door").capacity).toBe(3)
		expect(rules.consumer("beacon").needs).toBe(1)
		expect(rules.consumer("beacon").capacity).toBe(2)
		expect(rules.consumer("workshop").needs).toBe(2)
		expect(rules.consumer("workshop").capacity).toBe(4)
		-- 2 + 1 + 2 = 5: a right answer, with a unit spare
		local answer = { door = 2, beacon = 1, workshop = 2 }
		expect(rules.validate(answer).ok).toBe(true)
		expect(rules.allRunning(answer)).toBe(true)
		expect(rules.remaining(answer)).toBe(1)
	end)

	it("THE TRADE-OFF IS REAL: a fully-lit workshop can never leave all three running", function()
		--[[ The design's claim, checked rather than asserted: "a fully-lit workshop
			at 4 leaves the door short". If some allocation with workshop = 4 ran all
			three, the terminal would have no decision in it at all. ]]
		local counterexamples = 0
		local winners = 0
		for _, allocation in everyAllocation() do
			if rules.validate(allocation).ok and rules.allRunning(allocation) then
				winners += 1
				if allocation.workshop == 4 then
					counterexamples += 1
				end
			end
		end
		expect(counterexamples).toBe(0)
		-- ...and there is more than one way to reach it, which is the other half
		expect(winners).toBeGreaterThan(1)
	end)

	it("the total bound is exactly six, over the whole product", function()
		local problems: { string } = {}
		for _, allocation in everyAllocation() do
			local sum = allocation.door + allocation.beacon + allocation.workshop
			local verdict = rules.validate(allocation)
			local wanted = sum <= rules.TOTAL
			if verdict.ok ~= wanted then
				table.insert(problems, `sum {sum} -> ok={tostring(verdict.ok)}, wanted {tostring(wanted)}`)
			end
			if not wanted then
				if verdict.code ~= "budget" then
					table.insert(problems, `sum {sum} refused as '{tostring(verdict.code)}', wanted 'budget'`)
				end
				local expected = `The generator makes 6 units and that allocation asks for {sum}.`
				if verdict.message ~= expected then
					table.insert(problems, `sum {sum} said "{verdict.message}"`)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("WHAT RUNNING MEANS is `at least what it needs`, over the whole product", function()
		local problems: { string } = {}
		for _, allocation in everyAllocation() do
			local running = 0
			for _, consumer in rules.CONSUMERS do
				local wanted = allocation[consumer.id] >= consumer.needs
				if rules.isRunning(allocation, consumer.id) ~= wanted then
					table.insert(problems, `{consumer.id} at {allocation[consumer.id]} ~= {tostring(wanted)}`)
				end
				if wanted then
					running += 1
				end
				local line = rules.stateLine(allocation, consumer.id)
				local wantedLine = if wanted then consumer.running else consumer.idle
				if line ~= wantedLine then
					table.insert(problems, `{consumer.id} line "{line}" ~= "{wantedLine}"`)
				end
			end
			if rules.runningCount(allocation) ~= running then
				table.insert(problems, `runningCount disagreed at {allocation.door}/{allocation.beacon}`)
			end
			if rules.allRunning(allocation) ~= (running == 3) then
				table.insert(problems, `allRunning disagreed at {allocation.door}/{allocation.beacon}`)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the starting allocation is legal, and is a problem with an obvious first move", function()
		expect(rules.validate(rules.START).ok).toBe(true)
		expect(rules.runningCount(rules.START)).toBe(1)
		expect(rules.isRunning(rules.START, "door")).toBe(true)
		-- the door is on THREE, one more than it needs: the first thing to try is
		-- also the right thing to do
		expect(rules.START.door).toBe(3)
		expect(rules.START.door).toBeGreaterThan(rules.consumer("door").needs)
	end)
end)

describe("outpost rules: every refusal, and the exact sentence it uses", function()
	it("a fraction is refused as `whole`, naming the consumer and the value", function()
		local verdict = rules.validate({ door = 1.5, beacon = 1, workshop = 2 })
		expect(verdict.code).toBe("whole")
		expect(verdict.message).toBe("Power moves in whole units — blast door cannot take 1.5.")
	end)

	it("a missing consumer is refused as `missing`, and an extra one as `unknown`", function()
		local missing = rules.validate({ door = 2, workshop = 2 })
		expect(missing.code).toBe("missing")
		expect(missing.message).toBe("Landing beacon has no number in that allocation.")
		local unknown = rules.validate({ door = 2, beacon = 1, workshop = 2, reactor = 1 })
		expect(unknown.code).toBe("unknown")
		expect(unknown.message).toBe("The outpost has no consumer called 'reactor'.")
	end)

	it("THE ORDER IS PART OF THE CONTRACT: a fraction that is also over budget says `whole`", function()
		--[[ A player who typed a number the terminal cannot even produce should be
			told about the number, not about a budget that was never going to be
			reached. Deterministic, because the consumers are asked in declaration
			order. ]]
		local verdict = rules.validate({ door = 3.5, beacon = 2, workshop = 4 })
		expect(verdict.code).toBe("whole")
	end)

	it("every declared refusal code has a sentence, and an undeclared one is loud", function()
		local infos: { [string]: any } = {
			whole = { label = "Blast door", value = "1.5" },
			range = { label = "Blast door", capacity = 3, value = 4 },
			budget = { total = 9 },
			missing = { label = "Workshop" },
			unknown = { id = "reactor" },
			session = {},
			holder = {},
			rate = {},
			distance = { distance = 18, range = 10 },
		}
		local problems: { string } = {}
		for _, code in rules.REFUSAL_CODES do
			local ok, message = pcall(rules.refusal, code, infos[code])
			if not ok or type(message) ~= "string" or #message < 10 then
				table.insert(problems, `{code}: {tostring(message)}`)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
		expect(#rules.REFUSAL_CODES).toBe(9)
		expect(pcall(rules.refusal, "no-such-code", {})).toBe(false)
	end)

	it("the three server-only sentences are the ones the design specifies", function()
		expect(rules.refusal("session")).toBe("This console session has ended. Use the terminal again to take control.")
		expect(rules.refusal("holder")).toBe("Another engineer is at this console.")
		expect(rules.refusal("rate")).toBe("The terminal takes one command at a time. Wait a moment and try again.")
		expect(rules.refusal("distance", { distance = 18, range = 10 })).toBe(
			"You are 18 studs from the console. Step within 10 to use it."
		)
	end)
end)

describe("outpost rules: what changed, which is what the terminal reports", function()
	it("only a CROSSING is news; a number that moved without crossing is not", function()
		local before = { door = 3, beacon = 0, workshop = 0 }
		expect(#rules.changes(before, { door = 2, beacon = 0, workshop = 0 })).toBe(0)
		local crossed = rules.changes(before, { door = 2, beacon = 1, workshop = 2 })
		expect(#crossed).toBe(2)
		expect(crossed[1]).toBe("The landing beacon is lit.")
		expect(crossed[2]).toBe("The workshop lamps are on.")
		-- ...and going the other way reports the idle sentence
		local lost = rules.changes({ door = 2, beacon = 1, workshop = 2 }, { door = 0, beacon = 1, workshop = 2 })
		expect(lost[1]).toBe("The blast door is sealed.")
	end)

	it("the outcome sentence has three cases and picks the player's one first", function()
		local start = { door = 3, beacon = 0, workshop = 0 }
		expect(rules.outcomeLine(start, { door = 2, beacon = 1, workshop = 2 })).toBe(
			"All three are running, with 1 unit to spare."
		)
		expect(rules.outcomeLine(start, { door = 3, beacon = 1, workshop = 2 })).toBe(
			"All three are running, on every unit the generator makes."
		)
		expect(rules.outcomeLine(start, { door = 2, beacon = 1, workshop = 0 })).toBe("The landing beacon is lit.")
		expect(rules.outcomeLine(start, { door = 2, beacon = 0, workshop = 0 })).toBe(
			"Allocation set. 1 of 3 consumers are running."
		)
	end)
end)

-- ═══ THE SERVER'S JUDGEMENT ═════════════════════════════════════════════════

local function request(overrides: any): any
	local base: any = {
		holderId = "player-1",
		senderId = "player-1",
		holderToken = "s1",
		token = "s1",
		sinceLast = nil,
		distance = 4,
		allocation = { door = 2, beacon = 1, workshop = 2 },
	}
	for key, value in overrides do
		base[key] = if value == "\0nil" then nil else value
	end
	return base
end

describe("outpost authority: every refusal the server can make", function()
	it("the happy path: the holder, a fresh token, in range, with a legal allocation", function()
		local verdict = rules.authorize(request({}))
		expect(verdict.ok).toBe(true)
		expect(verdict.total).toBe(5)
	end)

	it("REFUSAL 1 — nobody holds the console, or somebody else does", function()
		expect(rules.authorize(request({ holderId = "\0nil" })).code).toBe("holder")
		expect(rules.authorize(request({ holderId = "player-2" })).code).toBe("holder")
		expect(rules.authorize(request({ senderId = "player-2" })).code).toBe("holder")
		expect(rules.authorize(request({ holderId = "player-2" })).message).toBe("Another engineer is at this console.")
	end)

	it("REFUSAL 2 — a stale session token, or no token at all", function()
		expect(rules.authorize(request({ token = "s0" })).code).toBe("session")
		expect(rules.authorize(request({ token = "\0nil" })).code).toBe("session")
		expect(rules.authorize(request({ token = 7 })).code).toBe("session")
		expect(rules.authorize(request({ holderToken = "\0nil" })).code).toBe("session")
	end)

	it("REFUSAL 3 — faster than a hand can press", function()
		expect(rules.authorize(request({ sinceLast = 0.05 })).code).toBe("rate")
		expect(rules.authorize(request({ sinceLast = rules.MIN_COMMAND_INTERVAL - 0.001 })).code).toBe("rate")
		-- the boundary is inclusive on the legal side: exactly the interval passes
		expect(rules.authorize(request({ sinceLast = rules.MIN_COMMAND_INTERVAL })).ok).toBe(true)
		expect(rules.authorize(request({ sinceLast = 5 })).ok).toBe(true)
	end)

	it("REFUSAL 4 — too far, MEASURED, and an unmeasurable distance is not a pass", function()
		local far = rules.authorize(request({ distance = 18 }))
		expect(far.code).toBe("distance")
		expect(far.message).toBe("You are 18 studs from the console. Step within 10 to use it.")
		-- exactly at the range is still at the console
		expect(rules.authorize(request({ distance = rules.RANGE })).ok).toBe(true)
		expect(rules.authorize(request({ distance = rules.RANGE + 0.01 })).code).toBe("distance")
		--[[ NO CHARACTER, NO CONSOLE, NO MEASUREMENT — and that is a refusal, not a
			shrug. A check that passes when it could not run is not a check. ]]
		local blind = rules.authorize(request({ distance = "\0nil" }))
		expect(blind.code).toBe("distance")
		expect(blind.message).toBe("You are an unknown number of studs from the console. Step within 10 to use it.")
	end)

	it("REFUSAL 5 — the allocation itself, through the same rules the terminal ran", function()
		expect(rules.authorize(request({ allocation = { door = 9, beacon = 0, workshop = 0 } })).code).toBe("range")
		expect(rules.authorize(request({ allocation = { door = 3, beacon = 2, workshop = 4 } })).code).toBe("budget")
		expect(rules.authorize(request({ allocation = { door = 1.5, beacon = 1, workshop = 2 } })).code).toBe("whole")
		expect(rules.authorize(request({ allocation = "six units please" })).code).toBe("missing")
	end)

	it("THE ORDER IS PART OF THE CONTRACT: who you are beats how far, beats what you asked", function()
		--[[ A player who walked away should be told THAT, not told about the
			arithmetic of an allocation that was never going to be applied — and a
			player who does not hold the console should not be told the distance to a
			console that is not theirs. ]]
		local everythingWrong = request({
			holderId = "player-2",
			token = "stale",
			sinceLast = 0.01,
			distance = 99,
			allocation = { door = 9, beacon = 9, workshop = 9 },
		})
		expect(rules.authorize(everythingWrong).code).toBe("holder")
		everythingWrong.holderId = "player-1"
		expect(rules.authorize(everythingWrong).code).toBe("session")
		everythingWrong.token = "s1"
		expect(rules.authorize(everythingWrong).code).toBe("rate")
		everythingWrong.sinceLast = 1
		expect(rules.authorize(everythingWrong).code).toBe("distance")
		everythingWrong.distance = 3
		expect(rules.authorize(everythingWrong).code).toBe("range")
	end)
end)

-- ═══ THE TERMINAL'S STATE MACHINE ═══════════════════════════════════════════

local function lab(opts: any?): any
	local o: any = opts or {}
	local w = world.new({
		viewport = VIEWPORT,
		env = { presentationSpace = "world", preferredTextSize = o.preferredTextSize },
	})
	local sent: { any } = {}
	local exits: { boolean } = {}
	local built = terminal.build(Facet, w.core, {
		send = if o.noTransport
			then nil
			else function(envelope: any)
				table.insert(sent, envelope)
			end,
		onExit = function()
			table.insert(exits, true)
		end,
		onState = o.onState,
	})
	w.present(built.screen, built.present)
	w.settle(4)
	return { w = w, built = built, sent = sent, exits = exits, steps = built.steps }
end

--[[ THE SERVER, AS A FUNCTION. It runs the SAME `rules.authorize` the real one
	does, over the same five values, so a spec that drives the terminal against it
	is driving the terminal against the shipped judgement rather than a mock of
	it. Only the reading of the five values is faked, which is exactly the half
	that needs an engine. ]]
local function answer(fixture: any, situation: any?): any
	local envelope = fixture.sent[#fixture.sent]
	assert(envelope ~= nil, "nothing was sent")
	local s: any = situation or {}
	local verdict = rules.authorize({
		holderId = s.holderId or "me",
		senderId = "me",
		holderToken = s.holderToken or "s1",
		token = s.token or "s1",
		sinceLast = s.sinceLast,
		distance = if s.distance ~= nil then s.distance else 4,
		allocation = envelope.payload.allocation,
	})
	if verdict.ok then
		return fixture.steps.confirm(envelope.requestId, {
			revision = 99,
			allocation = envelope.payload.allocation,
		})
	end
	return fixture.steps.reject(envelope.requestId, { code = verdict.code, message = verdict.message })
end

describe("outpost terminal: engage -> adjust -> apply -> success -> reset -> exit", function()
	it("a terminal nobody is standing at is idle, and says the objective", function()
		local f = lab()
		local state = f.steps.snapshot()
		expect(state.phase).toBe("idle")
		expect(state.message).toBe(rules.OBJECTIVE)
		expect(state.canApply).toBe(false)
		f.built.dispose()
	end)

	it("ENGAGE seeds the draft from what the outpost is actually running", function()
		local f = lab()
		f.steps.engage({ door = 1, beacon = 2, workshop = 0 })
		local state = f.steps.snapshot()
		expect(state.phase).toBe("engaged")
		expect(state.draft.door).toBe(1)
		expect(state.draft.beacon).toBe(2)
		expect(state.outpost.door).toBe(1)
		expect(state.budget).toBe("3 of 6 units allocated — 3 spare")
		f.built.dispose()
	end)

	it("ADJUST moves the draft, and the budget line and the live verdict follow it", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		f.steps.adjust("beacon", 1)
		f.steps.adjust("workshop", 2)
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.draft.door).toBe(2)
		expect(state.draft.beacon).toBe(1)
		expect(state.draft.workshop).toBe(2)
		expect(state.budget).toBe("5 of 6 units allocated — 1 spare")
		expect(state.canApply).toBe(true)
		-- a stepper cannot leave its own range even when asked to
		f.steps.setValue("beacon", 99)
		expect(f.steps.snapshot().draft.beacon).toBe(rules.consumer("beacon").capacity)
		f.steps.setValue("beacon", -4)
		expect(f.steps.snapshot().draft.beacon).toBe(0)
		f.built.dispose()
	end)

	it("AN ILLEGAL DRAFT IS REFUSED HERE and never reaches the wire", function()
		--[[ Not a substitute for the server's check — the same `rules.validate`
			runs there — but a terminal that spends a round trip to be told what it
			already knew is a terminal that feels broken. ]]
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 3)
		f.steps.setValue("beacon", 2)
		f.steps.setValue("workshop", 4)
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.canApply).toBe(false)
		expect(state.message).toBe("The generator makes 6 units and that allocation asks for 9.")
		local result = f.steps.apply()
		expect(result.sent).toBe(false)
		expect(result.reason).toBe("budget")
		expect(#f.sent).toBe(0)
		expect(f.steps.snapshot().counters.refusedLocally).toBe(1)
		f.built.dispose()
	end)

	it("APPLY sends ONE intent carrying the draft, and `pending` is not success", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		f.steps.setValue("beacon", 1)
		f.steps.setValue("workshop", 2)
		local result = f.steps.apply()
		expect(result.sent).toBe(true)
		expect(#f.sent).toBe(1)
		expect(f.sent[1].payload.kind).toBe("set")
		expect(f.sent[1].payload.allocation.door).toBe(2)
		local state = f.steps.snapshot()
		expect(state.status).toBe("pending")
		expect(state.message).toBe("Sending to the outpost…")
		-- the outpost has NOT moved: nothing is optimistic here
		expect(state.outpost.door).toBe(3)
		expect(state.complete).toBe(false)
		f.built.dispose()
	end)

	it("a SECOND apply while one is in flight is refused instead of throwing", function()
		--[[ `Facet.replication.mutation.send` ERRORS on a second in-flight request,
			by contract. A terminal that lets it throw is a terminal whose Apply
			button stops working for reasons the player cannot see. ]]
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		expect(f.steps.apply().sent).toBe(true)
		local second = f.steps.apply()
		expect(second.sent).toBe(false)
		expect(second.reason).toBe("pending")
		expect(#f.sent).toBe(1)
		f.built.dispose()
	end)

	it("SUCCESS: the verdict lands, the outpost moves, and the terminal says what changed", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		f.steps.setValue("beacon", 1)
		f.steps.setValue("workshop", 2)
		f.steps.apply()
		answer(f)
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.status).toBe("confirmed")
		expect(state.outpost.beacon).toBe(1)
		expect(state.revision).toBe(99)
		expect(state.complete).toBe(true)
		expect(state.message).toBe("All three are running, with 1 unit to spare.")
		expect(state.counters.applied).toBe(1)
		f.built.dispose()
	end)

	it("A REFUSAL IS SHOWN, NOT SWALLOWED — and the draft survives it", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		f.steps.setValue("beacon", 1)
		f.steps.setValue("workshop", 2)
		f.steps.apply()
		-- the player walked away between pressing and arriving
		answer(f, { distance = 22 })
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.status).toBe("rejected")
		expect(state.message).toBe("You are 22 studs from the console. Step within 10 to use it.")
		-- the outpost did NOT move, and the draft is still there to retry with
		expect(state.outpost.door).toBe(3)
		expect(state.draft.door).toBe(2)
		f.built.dispose()
	end)

	it("every server refusal reaches the screen as its own sentence", function()
		local cases = {
			{ situation = { holderId = "someone-else" }, message = rules.refusal("holder") },
			{ situation = { token = "stale" }, message = rules.refusal("session") },
			{ situation = { sinceLast = 0.01 }, message = rules.refusal("rate") },
			{ situation = { distance = 40 }, message = rules.refusal("distance", { distance = 40, range = 10 }) },
		}
		local problems: { string } = {}
		for _, case in cases do
			local f = lab()
			f.steps.engage(rules.START)
			f.steps.setValue("door", 2)
			f.steps.apply()
			answer(f, case.situation)
			f.w.settle(2)
			local got = f.steps.snapshot().message
			if got ~= case.message then
				table.insert(problems, `got "{got}", wanted "{case.message}"`)
			end
			f.built.dispose()
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("RESET IS A SERVER INTENT, not a local undo", function()
		--[[ "Reset puts the outpost back to its starting allocation" is a change to
			shared world state, so it takes the same road, the same validation and the
			same refusals as any other. ]]
		local f = lab()
		f.steps.engage({ door = 2, beacon = 1, workshop = 2 })
		local result = f.steps.reset()
		expect(result.sent).toBe(true)
		expect(#f.sent).toBe(1)
		expect(f.sent[1].payload.allocation.door).toBe(rules.START.door)
		expect(f.sent[1].payload.allocation.beacon).toBe(0)
		expect(f.steps.snapshot().draft.door).toBe(rules.START.door)
		answer(f)
		expect(f.steps.snapshot().outpost.workshop).toBe(0)
		f.built.dispose()
	end)

	it("AN EDIT RETIRES THE LAST OUTCOME, so the line never stands over state it contradicts", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		f.steps.setValue("beacon", 1)
		f.steps.setValue("workshop", 2)
		f.steps.apply()
		answer(f)
		f.w.settle(2)
		expect(f.steps.snapshot().message).toBe("All three are running, with 1 unit to spare.")
		f.steps.setValue("workshop", 4)
		f.w.settle(2)
		expect(f.steps.snapshot().message).toBe("The generator makes 6 units and that allocation asks for 7.")
		f.built.dispose()
	end)

	it("an allocation ANOTHER player applied lands without touching this draft", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.setValue("workshop", 3)
		f.steps.ingest(12, { door = 2, beacon = 1, workshop = 2 })
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.outpost.workshop).toBe(2)
		expect(state.draft.workshop).toBe(3)
		-- ...and a stale revision does not win
		expect(f.steps.ingest(3, { door = 0, beacon = 0, workshop = 0 }).verdict).toBe("stale")
		expect(f.steps.snapshot().outpost.door).toBe(2)
		f.built.dispose()
	end)
end)

describe("outpost terminal: every exit lands in the same place", function()
	--[[ EIGHT WAYS OUT, ONE DOOR. Cancel, the Exit control, walking out of range,
		losing line of sight, a removed character, a streamed-out adornee, a
		scenario switch and teardown all call `exit(reason)`. What each one does to
		the ENGINE — resign the responder, cancel armed input, dispose the host — is
		the runner's `ctx.surface.release`, and is Studio evidence. What each does
		to the TERMINAL is here, and it is identical for all eight, which is the
		property worth proving. ]]
	local REASONS = {
		"cancel",
		"exit-control",
		"out-of-range",
		"line-of-sight",
		"character-removed",
		"adornee-lost",
		"scenario-switch",
		"teardown",
	}

	it("all eight reasons produce the same terminal state, and each is recorded by name", function()
		local problems: { string } = {}
		for _, reason in REASONS do
			local f = lab()
			f.steps.engage(rules.START)
			f.steps.setValue("door", 2)
			f.steps.apply()
			expect(f.steps.snapshot().status).toBe("pending")
			local result = f.steps.exit(reason)
			local state = f.steps.snapshot()
			if state.phase ~= "exited" then
				table.insert(problems, `{reason}: phase {state.phase}`)
			end
			if state.exitReason ~= reason then
				table.insert(problems, `{reason}: recorded {tostring(state.exitReason)}`)
			end
			--[[ IN-FLIGHT INPUT IS CANCELLED. Without this the next engage would meet
				a mutation still marked pending, and Apply would silently refuse for the
				rest of the session. ]]
			if state.status ~= "idle" then
				table.insert(problems, `{reason}: left the request {state.status}`)
			end
			if result.reason ~= reason or #f.exits ~= 1 then
				table.insert(problems, `{reason}: onExit fired {#f.exits} time(s)`)
			end
			f.built.dispose()
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("EXIT IS IDEMPOTENT, because the two directions have to be one door", function()
		--[[ The Exit control calls the screen's `exit`, which asks the host to
			resign; every other exit starts on the HOST and has to reach the screen,
			so the host's release calls the screen's `exit` too. Without the guard
			those two are a cycle. ]]
		local f = lab()
		f.steps.engage(rules.START)
		local first = f.steps.exit("exit-control")
		local second = f.steps.exit("teardown")
		expect(first.already).toBeNil()
		expect(second.already).toBe(true)
		-- the FIRST reason is the one recorded, and `onExit` fired exactly once
		expect(f.steps.snapshot().exitReason).toBe("exit-control")
		expect(#f.exits).toBe(1)
		f.built.dispose()
	end)

	it("an exited terminal sends nothing, and re-engaging is safe", function()
		local f = lab()
		f.steps.engage(rules.START)
		f.steps.exit("cancel")
		expect(f.steps.apply().reason).toBe("exited")
		expect(#f.sent).toBe(0)
		-- REPEATED TRIGGER-THEN-CANCEL: the surface stays mounted across every cycle
		for i = 1, 20 do
			f.steps.engage({ door = 2, beacon = 1, workshop = 2 })
			if i % 2 == 0 then
				f.steps.setValue("door", 3)
			end
			f.steps.exit("cancel")
		end
		f.steps.engage(rules.START)
		f.w.settle(2)
		local state = f.steps.snapshot()
		expect(state.phase).toBe("engaged")
		expect(state.draft.door).toBe(rules.START.door)
		expect(state.status).toBe("idle")
		expect(f.steps.apply().sent).toBe(true)
		f.built.dispose()
	end)

	it("NO TRANSPORT IS A STATE, NOT A CRASH", function()
		--[[ What a headless mount and a place with no server both look like. The
			terminal says so in the same line it says everything else. ]]
		local f = lab({ noTransport = true })
		f.steps.engage(rules.START)
		f.steps.setValue("door", 2)
		local result = f.steps.apply()
		expect(result.sent).toBe(false)
		expect(result.reason).toBe("no-transport")
		f.w.settle(2)
		expect(f.steps.snapshot().message).toBe(rules.refusal("session"))
		expect(f.steps.snapshot().status).toBe("rejected")
		f.built.dispose()
	end)
end)

describe("outpost terminal: the screen itself", function()
	it("it holds its own canvas at every text preference the player can choose", function()
		--[[ THE MEASURED OFFSETS, not a guess: {0,4,10,14} is the ladder
			`GuiService.PreferredTextSize` actually produces. This is the whole reason
			the canvas is 640x480 rather than the spike's 400x250 — a terminal that
			only fits at the default preference is a terminal half the players cannot
			read. The world's containment guard runs on every settle. ]]
		for _, offset in { 0, 4, 10, 14 } do
			local f = lab({ preferredTextSize = offset })
			f.steps.engage(rules.START)
			f.w.settle(6)
			-- the busiest state: an over-budget draft, whose message is the longest
			f.steps.setValue("door", 3)
			f.steps.setValue("beacon", 2)
			f.steps.setValue("workshop", 4)
			f.w.settle(6)
			f.built.dispose()
		end
		expect(true).toBe(true)
	end)

	it("it declares the walk-up contract rather than leaving each host to derive it", function()
		local f = lab()
		--[[ `responder = "passive"` mounts the surface INERT and makes
			`handle.engage()` the one thing that turns it into the surface receiving
			Navigate/Activate/Cancel — which is what "the prompt engages exactly ONE
			responder and focus scope" means mechanically. ]]
		expect(f.built.present.responder).toBe("passive")
		expect(f.built.present.keyboardNavigation).toBe(true)
		expect(f.built.present.initialFocus).toBe("first")
		--[[ AND CANCEL IS LEFT AT ITS DEFAULT ON PURPOSE: on a passive surface the
			presenter RESIGNS rather than dismisses, which is exactly the exit this
			terminal wants — the mounted surface survives so the player can walk back
			up to it. A `cancelPolicy` here would break that. ]]
		expect(f.built.present.cancelPolicy).toBeNil()
		f.built.dispose()
	end)

	it("its canvas is declared once and the aspect is a real console's", function()
		expect(CANVAS.w).toBe(640)
		expect(CANVAS.h).toBe(480)
		-- 4:3, which the fixture's 8 x 6 stud console matches: `surface_target`'s
		-- canvas is invariant to the part, so a mismatched part shows this squashed
		expect(CANVAS.w / CANVAS.h).toBeCloseTo(8 / 6, 0.001)
	end)

	it("EVERY CONTROL NEEDS ONLY ACTIVATION — there is not a drag on the terminal", function()
		--[[ Not a style rule: `surface_target` DELETES `setPointerHandlers` and
			`setTouchGestureHandlers` because a capture's coordinates on a
			`SurfaceGui` are unmeasured. A Slider on this screen would be a control
			whose coordinate space nobody has measured. ]]
		local fs = require("@lune/fs")
		local source = fs.readFile("examples/gallery/examples/outpost_terminal/init.luau")
		expect(string.find(source, "Controls.Slider", 1, true)).toBeNil()
		expect(string.find(source, "newSlider", 1, true)).toBeNil()
		expect(string.find(source, "Controls.Stepper", 1, true)).toBeTruthy()
	end)

	it("THE CONTENT MODULE IS ENGINE-FREE, which is what lets two hosts share it", function()
		--[[ The claim that makes one module servable to two hosts: the terminal
			creates no Instance, reaches no service, and knows nothing about a console
			part, a `ProximityPrompt` or a `RemoteEvent`. Asserted on the SYMBOLS
			rather than on the words — the headers of these files discuss all three at
			length, which is the point of them.

			THE SCENARIO IS HELD TO THE SAME RULE WITH ONE NAMED EXCEPTION: the
			guarded engine route that resolves the content module out of
			`ReplicatedStorage.FacetExamples`, which is the sanctioned idiom
			`tools/lune/check_scenario_requires` exists to keep honest. Anything else
			reaching the engine belongs in the runner's seam. ]]
		local fs = require("@lune/fs")
		local BANNED = { "Instance%.new", "GetService", "FireServer", "OnClientEvent", "%f[%w]workspace%f[%W]" }
		local problems: { string } = {}
		for _, file in
			{
				"examples/gallery/examples/outpost_terminal/init.luau",
				"examples/gallery/examples/outpost_terminal/rules.luau",
			}
		do
			local source = fs.readFile(file)
			for _, banned in BANNED do
				if string.find(source, banned) ~= nil then
					table.insert(problems, `{file} reaches the engine: {banned}`)
				end
			end
		end
		local scenario = fs.readFile("examples/gallery/scenarios/outpost_terminal.luau")
		local getServices = select(2, string.gsub(scenario, "GetService", ""))
		if getServices ~= 1 then
			table.insert(problems, `the scenario names GetService {getServices} times, and exactly one is sanctioned`)
		end
		for _, banned in { "Instance%.new", "FireServer", "OnClientEvent", "%f[%w]workspace%f[%W]" } do
			if string.find(scenario, banned) ~= nil then
				table.insert(problems, `the scenario reaches the engine: {banned}`)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)
