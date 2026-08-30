--!strict
--[[ THE OUTPOST'S POWER RULES — pure, and deliberately the only place any of this
	is written down (design: artifacts/example-games-and-standalones/design/
	outpost-power-terminal.md §2, §6).

	NO SIGNAL, NO PRESENTER, NO ENGINE. Everything here is a value in and a value
	out, which is what lets the SAME module answer for both halves of an authority
	boundary: the client terminal shows a refusal before it spends a round trip,
	and the server refuses with the identical sentence when the client's answer is
	a lie or is stale. Two hosts, one vocabulary — a rule the client and the server
	stated differently would be two rules.

	THE GAME, in one paragraph. The outpost generator makes six whole units. Three
	consumers want them: a blast door, a landing beacon and a workshop. Each has a
	number it NEEDS before it does anything at all, and a CAPACITY past which more
	power buys nothing. The player's goal is to get all three running at once —
	2 + 1 + 2 = 5 does it with a unit spare, so there is a right answer, more than
	one route to it, and a real trade-off (a fully-lit workshop at 4 leaves the
	door short).

	WHY `needs`/`capacity` AND NOT `min`/`max`. They are domain words: `needs` is
	the threshold a consumer starts working at, `capacity` is the largest number
	worth giving it. `min`/`max` would read as a UI dimension — which is also what
	`tools/lune/check_example_drift`'s R1 rule would take them for.
]]

local rules = {}

-- the generator's whole output, and the reason the three ranges do not simply add
rules.TOTAL = 6

export type Consumer = {
	id: string,
	label: string,
	-- the number below which this consumer does nothing at all
	needs: number,
	-- the largest number worth giving it (its stepper's ceiling)
	capacity: number,
	-- what the outpost looks like on each side of `needs`
	running: string,
	idle: string,
}

export type Allocation = { [string]: number }

--[[ ORDERED, because the terminal reads them top to bottom and a focus ring walks
	them in this order. The blast door is first because it is the one the outpost
	starts with — see `rules.START`. ]]
local CONSUMERS: { Consumer } = {
	{
		id = "door",
		label = "Blast door",
		needs = 2,
		capacity = 3,
		running = "The blast door is open.",
		idle = "The blast door is sealed.",
	},
	{
		id = "beacon",
		label = "Landing beacon",
		needs = 1,
		capacity = 2,
		running = "The landing beacon is lit.",
		idle = "The landing beacon is dark.",
	},
	{
		id = "workshop",
		label = "Workshop",
		needs = 2,
		capacity = 4,
		running = "The workshop lamps are on.",
		idle = "The workshop is dark.",
	},
}
rules.CONSUMERS = CONSUMERS

--[[ THE STARTING ALLOCATION IS A PROBLEM WITH AN OBVIOUS FIRST MOVE. The door is
	open on three units and nothing else works, so the player arrives at a lit
	screen that is already wrong, and the first thing to try — take one off the
	door — is also correct. ]]
local START: Allocation = { door = 3, beacon = 0, workshop = 0 }
rules.START = START

-- the goal, stated on screen rather than left to be inferred
rules.OBJECTIVE = "Get all three running at once."

local byId: { [string]: Consumer } = {}
for _, consumer in CONSUMERS do
	byId[consumer.id] = consumer
end

function rules.consumer(id: string): Consumer?
	return byId[id]
end

--[[ ── THE REFUSALS ──────────────────────────────────────────────────────────

	EVERY SENTENCE THE OUTPOST EVER SAYS NO WITH LIVES HERE, in one table, keyed by
	a stable code. Three of the eight are things the terminal itself can see (a
	fraction, a value past a capacity, a total past six); the other five are things
	only the server knows, and the server reads them out of this same table so a
	player never meets two vocabularies for one outpost.

	They are FUNCTIONS, not strings, because a refusal that does not name the
	number it refused is a refusal the player has to guess at. ]]
local REFUSALS: { [string]: (any) -> string } = {
	-- the client can see this one: a value that is not a whole number
	whole = function(info: any): string
		return `Power moves in whole units — {string.lower(info.label)} cannot take {info.value}.`
	end,
	-- ...and this one: a value outside 0..capacity
	range = function(info: any): string
		return `{info.label} takes 0 to {info.capacity} units. {info.value} is outside that.`
	end,
	-- ...and this one: the sum past the generator's output
	budget = function(info: any): string
		return `The generator makes {rules.TOTAL} units and that allocation asks for {info.total}.`
	end,
	-- a consumer the allocation forgot
	missing = function(info: any): string
		return `{info.label} has no number in that allocation.`
	end,
	-- ...and one the outpost does not have
	unknown = function(info: any): string
		return `The outpost has no consumer called '{info.id}'.`
	end,
	--[[ SERVER-ONLY FROM HERE DOWN. The client cannot establish any of these:
		a session it believes in may have ended, a hand it believes is at the
		console may have walked away, and both claims arrive over a wire. ]]
	session = function(): string
		return "This console session has ended. Use the terminal again to take control."
	end,
	holder = function(): string
		return "Another engineer is at this console."
	end,
	rate = function(): string
		return "The terminal takes one command at a time. Wait a moment and try again."
	end,
	distance = function(info: any): string
		return `You are {info.distance} studs from the console. Step within {info.range} to use it.`
	end,
}

-- the codes, in the order a reader should meet them; a test walks this list so a
-- new refusal cannot be added without a sentence and a case
rules.REFUSAL_CODES = { "whole", "range", "budget", "missing", "unknown", "session", "holder", "rate", "distance" }

--[[ `rules.refusal(code, info)` — the ONE way any host phrases a no. An unknown
	code is an authoring mistake and fails loudly here rather than reaching a
	player as an empty line. ]]
function rules.refusal(code: string, info: any?): string
	local phrase = REFUSALS[code]
	assert(phrase ~= nil, `outpost rules: no refusal called '{code}'`)
	return phrase(info or {})
end

export type Verdict = {
	ok: boolean,
	code: string?,
	message: string?,
	consumer: string?,
	total: number,
}

--[[ ── VALIDATION ────────────────────────────────────────────────────────────

	ONE PASS, IN ONE ORDER, and the order is part of the contract: a player who
	types a fraction into a field the terminal cannot produce should be told about
	the fraction, not about the budget it happens to also break. Per-consumer
	problems (shape, then range) are reported before the whole-allocation one, and
	the consumers are asked in declaration order so the same bad allocation always
	produces the same sentence.

	It also refuses what it does not recognise: an extra key is an allocation for
	an outpost this is not. ]]
function rules.validate(allocation: Allocation): Verdict
	local total = 0
	for id in allocation do
		if byId[id] == nil then
			return { ok = false, code = "unknown", message = rules.refusal("unknown", { id = id }), total = 0 }
		end
	end
	for _, consumer in CONSUMERS do
		local value = allocation[consumer.id]
		if value == nil then
			return {
				ok = false,
				code = "missing",
				message = rules.refusal("missing", { label = consumer.label }),
				consumer = consumer.id,
				total = 0,
			}
		end
		if type(value) ~= "number" or value ~= math.floor(value) or value ~= value then
			return {
				ok = false,
				code = "whole",
				message = rules.refusal("whole", { label = consumer.label, value = tostring(value) }),
				consumer = consumer.id,
				total = 0,
			}
		end
		if value < 0 or value > consumer.capacity then
			return {
				ok = false,
				code = "range",
				message = rules.refusal(
					"range",
					{ label = consumer.label, capacity = consumer.capacity, value = value }
				),
				consumer = consumer.id,
				total = 0,
			}
		end
		total += value
	end
	if total > rules.TOTAL then
		return { ok = false, code = "budget", message = rules.refusal("budget", { total = total }), total = total }
	end
	return { ok = true, total = total }
end

--[[ ── AUTHORITY, AS A PURE FUNCTION ─────────────────────────────────────────

	THE SERVER MEASURES; THIS DECIDES. Everything the outpost's authority checks
	is a judgement over five plain values — who holds the console, which session
	token came with the command, how long since this sender's last one, how far
	away the sender's character actually is, and the allocation itself — and not
	one of those judgements needs an engine. So the engine half of the server is
	the four lines that READ those values off `Player`, `os.clock` and a
	`BasePart.Position`, and the whole of the decision lives here, where a
	headless spec can drive every refusal exhaustively.

	That split is the reason this file is worth having twice over: the client
	shows the player a refusal before spending a round trip, and the server
	refuses with the identical sentence when the client's answer was a guess, a
	lie, or simply out of date.

	THE ORDER IS PART OF THE CONTRACT. A player who is no longer at the console
	should be told THAT, not told about the arithmetic of an allocation that was
	never going to be applied.
]]

-- the prompt's activation distance AND the distance the server re-measures — one
-- number, so the affordance and the check cannot disagree
rules.RANGE = 10
--[[ A person pressing Apply, reading what happened and pressing it again cannot
	do it in a fifth of a second; a script can do it a thousand times. Not
	anti-cheat — the cheapest possible statement that the server does not take a
	client's word for its own cadence. ]]
rules.MIN_COMMAND_INTERVAL = 0.2

export type Request = {
	-- an opaque identity for whoever the server believes holds the console, and
	-- for whoever sent this command. Never a `Player`: this module has no engine.
	holderId: string?,
	senderId: string,
	-- the token the server issued when the console was engaged, and the one that
	-- actually arrived
	holderToken: string?,
	token: any,
	-- seconds since this sender's previous command; nil means "never sent one"
	sinceLast: number?,
	-- studs, MEASURED BY THE SERVER; nil means it could not measure at all (no
	-- character, no console), which is refused exactly like being too far
	distance: number?,
	allocation: any,
}

function rules.authorize(request: Request): Verdict
	-- 1. IDENTITY. Is this the player who engaged this console?
	if request.holderId == nil or request.holderId ~= request.senderId then
		return { ok = false, code = "holder", message = rules.refusal("holder"), total = 0 }
	end
	-- 2. STALENESS. Is this the session they engaged, or an older one?
	if type(request.token) ~= "string" or request.holderToken == nil or request.token ~= request.holderToken then
		return { ok = false, code = "session", message = rules.refusal("session"), total = 0 }
	end
	-- 3. RATE. Faster than a hand can press is not a hand.
	local since = request.sinceLast
	if since ~= nil and since < rules.MIN_COMMAND_INTERVAL then
		return { ok = false, code = "rate", message = rules.refusal("rate"), total = 0 }
	end
	-- 4. DISTANCE, as the server measured it. A client-side proximity claim is a
	-- suggestion; an unmeasurable one is not a pass.
	local distance = request.distance
	if distance == nil or distance > rules.RANGE then
		return {
			ok = false,
			code = "distance",
			message = rules.refusal("distance", {
				distance = if distance == nil then "an unknown number of" else math.floor(distance + 0.5),
				range = rules.RANGE,
			}),
			total = 0,
		}
	end
	-- 5. THE ALLOCATION ITSELF, through the same `validate` the terminal ran.
	if type(request.allocation) ~= "table" then
		return { ok = false, code = "missing", message = rules.refusal("missing", { label = "The outpost" }), total = 0 }
	end
	return rules.validate(request.allocation)
end

-- ── reading an allocation ───────────────────────────────────────────────────

function rules.spent(allocation: Allocation): number
	local total = 0
	for _, consumer in CONSUMERS do
		total += allocation[consumer.id] or 0
	end
	return total
end

function rules.remaining(allocation: Allocation): number
	return rules.TOTAL - rules.spent(allocation)
end

--[[ WHAT "RUNNING" MEANS, and it is the whole of what it means: a consumer runs
	when it holds at least what it needs. Above `capacity` is not a second state —
	the terminal simply never offers it, and `validate` refuses it if something
	else does. ]]
function rules.isRunning(allocation: Allocation, id: string): boolean
	local consumer = byId[id]
	if consumer == nil then
		return false
	end
	return (allocation[id] or 0) >= consumer.needs
end

function rules.runningCount(allocation: Allocation): number
	local count = 0
	for _, consumer in CONSUMERS do
		if rules.isRunning(allocation, consumer.id) then
			count += 1
		end
	end
	return count
end

-- the win condition, and the one sentence that says so
function rules.allRunning(allocation: Allocation): boolean
	return rules.runningCount(allocation) == #CONSUMERS
end

function rules.stateLine(allocation: Allocation, id: string): string
	local consumer = byId[id]
	if consumer == nil then
		return rules.refusal("unknown", { id = id })
	end
	return if rules.isRunning(allocation, id) then consumer.running else consumer.idle
end

--[[ WHAT CHANGED, which is what the terminal reports after an Apply. A consumer
	whose NUMBER moved without crossing its threshold has not changed anything the
	player can see out of the window, so it is not news: this reports crossings
	only, in declaration order. ]]
function rules.changes(before: Allocation, after: Allocation): { string }
	local lines: { string } = {}
	for _, consumer in CONSUMERS do
		local was = rules.isRunning(before, consumer.id)
		local now = rules.isRunning(after, consumer.id)
		if was ~= now then
			table.insert(lines, if now then consumer.running else consumer.idle)
		end
	end
	return lines
end

--[[ THE OUTCOME SENTENCE. Three cases, in the order they matter to a player:
	the outpost is fully lit (the goal), something crossed a threshold (progress),
	or the allocation was legal and changed nothing anyone can see. ]]
function rules.outcomeLine(before: Allocation, after: Allocation): string
	if rules.allRunning(after) then
		local spare = rules.remaining(after)
		if spare > 0 then
			return `All three are running, with {spare} unit{if spare == 1 then "" else "s"} to spare.`
		end
		return "All three are running, on every unit the generator makes."
	end
	local changed = rules.changes(before, after)
	if #changed > 0 then
		return table.concat(changed, " ")
	end
	return `Allocation set. {rules.runningCount(after)} of {#CONSUMERS} consumers are running.`
end

-- a defensive copy, so a caller can hand an allocation across a boundary without
-- handing over the table it is still editing
function rules.copy(allocation: Allocation): Allocation
	local out: Allocation = {}
	for _, consumer in CONSUMERS do
		out[consumer.id] = allocation[consumer.id] or 0
	end
	return out
end

function rules.equal(a: Allocation, b: Allocation): boolean
	for _, consumer in CONSUMERS do
		if (a[consumer.id] or 0) ~= (b[consumer.id] or 0) then
			return false
		end
	end
	return true
end

return rules
