--!strict

local rules = {}

rules.TOTAL = 6

export type Consumer = {
	id: string,
	label: string,

	needs: number,

	capacity: number,

	running: string,
	idle: string,
}

export type Allocation = { [string]: number }

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

local START: Allocation = { door = 3, beacon = 0, workshop = 0 }
rules.START = START

rules.OBJECTIVE = "Get all three running at once."

local byId: { [string]: Consumer } = {}
for _, consumer in CONSUMERS do
	byId[consumer.id] = consumer
end

function rules.consumer(id: string): Consumer?
	return byId[id]
end

local REFUSALS: { [string]: (any) -> string } = {

	whole = function(info: any): string
		return `Power moves in whole units — {string.lower(info.label)} cannot take {info.value}.`
	end,

	range = function(info: any): string
		return `{info.label} takes 0 to {info.capacity} units. {info.value} is outside that.`
	end,

	budget = function(info: any): string
		return `The generator makes {rules.TOTAL} units and that allocation asks for {info.total}.`
	end,

	missing = function(info: any): string
		return `{info.label} has no number in that allocation.`
	end,

	unknown = function(info: any): string
		return `The outpost has no consumer called '{info.id}'.`
	end,

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

rules.REFUSAL_CODES = { "whole", "range", "budget", "missing", "unknown", "session", "holder", "rate", "distance" }

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

rules.RANGE = 10

rules.MIN_COMMAND_INTERVAL = 0.2

export type Request = {

	holderId: string?,
	senderId: string,

	holderToken: string?,
	token: any,

	sinceLast: number?,

	distance: number?,
	allocation: any,
}

function rules.authorize(request: Request): Verdict
	if request.holderId == nil or request.holderId ~= request.senderId then
		return { ok = false, code = "holder", message = rules.refusal("holder"), total = 0 }
	end

	if type(request.token) ~= "string" or request.holderToken == nil or request.token ~= request.holderToken then
		return { ok = false, code = "session", message = rules.refusal("session"), total = 0 }
	end

	local since = request.sinceLast
	if since ~= nil and since < rules.MIN_COMMAND_INTERVAL then
		return { ok = false, code = "rate", message = rules.refusal("rate"), total = 0 }
	end

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

	if type(request.allocation) ~= "table" then
		return { ok = false, code = "missing", message = rules.refusal("missing", { label = "The outpost" }), total = 0 }
	end
	return rules.validate(request.allocation)
end

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
