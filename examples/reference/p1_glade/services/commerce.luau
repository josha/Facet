--!strict

local seedData = require("../content/seed")
local strings = require("../content/strings")

local commerce = {}

export type Opts = {
	Compose: any,
	now: any,
}

local REASONS = { "declined", "offline", "owned", "fallback" }
commerce.REASONS = REASONS

local function isKnownReason(reason: string): boolean
	for _, known in REASONS do
		if known == reason then
			return true
		end
	end
	return false
end

function commerce.new(opts: Opts): any
	local Compose = opts.Compose
	local now = opts.now

	local satchel: { [string]: any } = {}
	for _, nectar in seedData.NECTARS do
		if nectar.premium then
			satchel[nectar.id] = Compose.cell(seedData.SATCHEL[nectar.id] or 0)
		end
	end
	local charmTier = Compose.cell("none")

	local records: { [string]: any } = {}

	local attempts: { [string]: number } = { pack = 0, charm = 0, restore = 0 }

	local inFlight: { any } = {}

	local function recordFor(id: string): any
		local record = records[id]
		if record == nil then
			record = {
				status = Compose.cell("idle"),
				reason = Compose.cell(nil :: string?),
			}
			records[id] = record
		end
		return record
	end

	local service = {}

	function service.command(id: string): any
		return recordFor(id)
	end

	function service.status(id: string): any
		return recordFor(id).status
	end

	function service.reason(id: string): any
		return recordFor(id).reason
	end

	function service.satchelOf(nectarId: string): any
		return satchel[nectarId]
	end

	function service.charmTier(): any
		return charmTier
	end

	function service.charmRank(): number
		return seedData.CHARM_RANK[charmTier:peek()] or 0
	end

	function service.priceOf(packId: string): string
		local pack = seedData.PACK_BY_ID[packId]
		if pack == nil then
			return ""
		end
		return `{strings.PRICE_MARK} {pack.price}`
	end

	function service.charmPriceOf(tierId: string): string
		local tier = seedData.CHARM_BY_ID[tierId]
		if tier == nil then
			return ""
		end
		return `{strings.PRICE_MARK} {tier.price}`
	end

	local function nextOutcome(family: string): string
		local fixtures = seedData.OUTCOMES[family]
		attempts[family] += 1
		local index = (attempts[family] - 1) % #fixtures + 1
		return fixtures[index]
	end

	local function start(id: string, family: string, outcome: string, apply: (() -> ())?): boolean
		local record = recordFor(id)
		if record.status:peek() == "pending" then
			return false
		end
		record.reason:set(nil)
		record.status:set("pending")
		table.insert(inFlight, {
			id = id,
			family = family,
			outcome = outcome,
			apply = apply,
			dueAt = now:peek() + seedData.COMMAND_SECONDS,
		})
		return true
	end

	function service.buyPack(packId: string): boolean
		local pack = seedData.PACK_BY_ID[packId]
		if pack == nil then
			return false
		end
		local outcome = nextOutcome("pack")
		return start(packId, "pack", outcome, function()
			satchel[pack.nectar]:set(satchel[pack.nectar]:peek() + pack.quantity)
		end)
	end

	function service.buyCharm(tierId: string): boolean
		local tier = seedData.CHARM_BY_ID[tierId]
		if tier == nil then
			return false
		end

		local outcome
		if tier.rank <= service.charmRank() then
			outcome = "owned"
		else
			outcome = nextOutcome("charm")
		end
		return start(tierId, "charm", outcome, function()
			charmTier:set(tierId)
		end)
	end

	function service.restore(): boolean
		return start("restore", "restore", nextOutcome("restore"), nil)
	end

	function service.update(at: number)
		if #inFlight == 0 then
			return
		end
		local due: { any } = {}
		local rest: { any } = {}
		for _, flight in inFlight do
			if at >= flight.dueAt then
				table.insert(due, flight)
			else
				table.insert(rest, flight)
			end
		end
		if #due == 0 then
			return
		end
		inFlight = rest
		for _, flight in due do
			local record = recordFor(flight.id)
			if flight.outcome == "confirmed" then
				if flight.apply ~= nil then
					flight.apply()
				end
				record.reason:set(nil)
				record.status:set("confirmed")
			else
				local reason = if isKnownReason(flight.outcome) then flight.outcome else "fallback"
				record.reason:set(reason)
				record.status:set("rejected")
			end
		end
	end

	function service.clear(id: string)
		local record = records[id]
		if record == nil then
			return
		end
		if record.status:peek() ~= "pending" then
			record.status:set("idle")
			record.reason:set(nil)
		end
	end

	function service.clearAll()
		for id in records do
			service.clear(id)
		end
	end

	function service.pendingCount(): number
		return #inFlight
	end

	function service.reset()
		inFlight = {}
		for _, nectar in seedData.NECTARS do
			if nectar.premium then
				satchel[nectar.id]:set(seedData.SATCHEL[nectar.id] or 0)
			end
		end
		charmTier:set("none")
		for _, record in records do
			record.status:set("idle")
			record.reason:set(nil)
		end
		attempts = { pack = 0, charm = 0, restore = 0 }
	end

	function service.dump(): any
		local held: { any } = {}
		for _, nectar in seedData.NECTARS do
			if nectar.premium then
				table.insert(held, { nectar = nectar.id, count = satchel[nectar.id]:peek() })
			end
		end
		local commands: { any } = {}
		local ids: { string } = {}
		for id in records do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local record = records[id]
			if record.status:peek() ~= "idle" then
				table.insert(commands, { id = id, status = record.status:peek(), reason = record.reason:peek() })
			end
		end
		return {
			satchel = held,
			charm = charmTier:peek(),
			commands = commands,
			attempts = { pack = attempts.pack, charm = attempts.charm, restore = attempts.restore },
			inFlight = #inFlight,
		}
	end

	return service
end

return commerce
