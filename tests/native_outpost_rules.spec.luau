--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local rules = require("../examples/gallery/examples/outpost_terminal/rules")

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

		local answer = { door = 2, beacon = 1, workshop = 2 }
		expect(rules.validate(answer).ok).toBe(true)
		expect(rules.allRunning(answer)).toBe(true)
		expect(rules.remaining(answer)).toBe(1)
	end)

	it("THE TRADE-OFF IS REAL: a fully-lit workshop can never leave all three running", function()
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

		expect(rules.authorize(request({ sinceLast = rules.MIN_COMMAND_INTERVAL })).ok).toBe(true)
		expect(rules.authorize(request({ sinceLast = 5 })).ok).toBe(true)
	end)

	it("REFUSAL 4 — too far, MEASURED, and an unmeasurable distance is not a pass", function()
		local far = rules.authorize(request({ distance = 18 }))
		expect(far.code).toBe("distance")
		expect(far.message).toBe("You are 18 studs from the console. Step within 10 to use it.")

		expect(rules.authorize(request({ distance = rules.RANGE })).ok).toBe(true)
		expect(rules.authorize(request({ distance = rules.RANGE + 0.01 })).code).toBe("distance")

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
