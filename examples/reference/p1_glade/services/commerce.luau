--!strict
-- CommerceService — satchel ledger, charm tier, catalog, and the purchase
-- COMMAND (responsibility ledger, P1 row 2). Production maps to
-- MarketplaceService developer products (consumables) and PromptSubscription-
-- Purchase for the tiers, with receipts processed server-side; the prompt sheet
-- itself is a host surface and the in-experience UI ends at the prompt call.
--
-- Every command runs `idle → pending → confirmed | rejected`. Pending NEVER
-- implies success: the caller shows a disabled, labelled "Confirming…" control
-- and nothing else moves until the command resolves. Resolution happens on the
-- injected clock (`update(now)`), so the same drive produces the same verdicts
-- headlessly and in Studio.
--
-- Rejections come from the seed's OUTCOMES fixtures by attempt ordinal, plus one
-- DERIVED rule the fixtures cannot override: buying a charm tier you already
-- hold is always `owned`.

local seedData = require("../content/seed")
local strings = require("../content/strings")

local commerce = {}

export type Opts = {
	core: any,
	now: any, -- Readable<number>
	scope: any,
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
	local core = opts.core
	local now = opts.now
	local scope = opts.scope

	-- ---- ledger -------------------------------------------------------------
	local satchel: { [string]: any } = {}
	for _, nectar in seedData.NECTARS do
		if nectar.premium then
			satchel[nectar.id] = scope:own(core:signal(seedData.SATCHEL[nectar.id] or 0))
		end
	end
	local charmTier = scope:own(core:signal("none"))

	-- ---- commands -----------------------------------------------------------
	-- One record per command id (a pack id, a charm tier id, or "restore"). The
	-- record is created on first use and reused, so a card can bind its button's
	-- label and enabled state before anything has ever been bought.
	local records: { [string]: any } = {}
	-- attempt counters per FAMILY, which is what the fixtures are indexed by
	local attempts: { [string]: number } = { pack = 0, charm = 0, restore = 0 }
	-- commands waiting on the clock: { id, dueAt, family, outcome }
	local inFlight: { any } = {}

	local function recordFor(id: string): any
		local record = records[id]
		if record == nil then
			record = {
				status = scope:own(core:signal("idle")),
				reason = scope:own(core:signal(nil :: string?)),
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
		return seedData.CHARM_RANK[charmTier:get()] or 0
	end

	-- prices are SERVICE-PUBLISHED STRINGS (spec §1). The UI never composes a
	-- price out of a number and a glyph — that is exactly the copy a real
	-- storefront localizes and the proof must not invent per screen.
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

	-- the scripted verdict for the next attempt in a family
	local function nextOutcome(family: string): string
		local fixtures = seedData.OUTCOMES[family]
		attempts[family] += 1
		local index = (attempts[family] - 1) % #fixtures + 1
		return fixtures[index]
	end

	local function start(id: string, family: string, outcome: string, apply: (() -> ())?): boolean
		local record = recordFor(id)
		if record.status:get() == "pending" then
			return false -- one flight per command; the control is disabled anyway
		end
		record.reason:set(nil)
		record.status:set("pending")
		table.insert(inFlight, {
			id = id,
			family = family,
			outcome = outcome,
			apply = apply,
			dueAt = now:get() + seedData.COMMAND_SECONDS,
		})
		return true
	end

	-- ---- the three purchase-shaped verbs -----------------------------------

	function service.buyPack(packId: string): boolean
		local pack = seedData.PACK_BY_ID[packId]
		if pack == nil then
			return false
		end
		local outcome = nextOutcome("pack")
		return start(packId, "pack", outcome, function()
			satchel[pack.nectar]:set(satchel[pack.nectar]:get() + pack.quantity)
		end)
	end

	function service.buyCharm(tierId: string): boolean
		local tier = seedData.CHARM_BY_ID[tierId]
		if tier == nil then
			return false
		end
		-- the derived rule wins over the fixture: a tier you already hold can
		-- never be sold to you again, whatever the script says next.
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

	-- the S7 "Restore provisions" command: a FAKE ledger re-sync, stated plainly
	-- (there is no host restore surface in a Roblox experience).
	function service.restore(): boolean
		return start("restore", "restore", nextOutcome("restore"), nil)
	end

	-- ---- resolution ---------------------------------------------------------
	-- Called from the proof's one clock advance. Deterministic: a command started
	-- at t resolves at t + COMMAND_SECONDS, in start order.
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

	-- the caller clears a settled command when the player moves on (a notice
	-- clears on the next attempt or on modal dismiss, spec §9)
	function service.clear(id: string)
		local record = records[id]
		if record == nil then
			return
		end
		if record.status:get() ~= "pending" then
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
				table.insert(held, { nectar = nectar.id, count = satchel[nectar.id]:get() })
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
			if record.status:get() ~= "idle" then
				table.insert(commands, { id = id, status = record.status:get(), reason = record.reason:get() })
			end
		end
		return {
			satchel = held,
			charm = charmTier:get(),
			commands = commands,
			attempts = { pack = attempts.pack, charm = attempts.charm, restore = attempts.restore },
			inFlight = #inFlight,
		}
	end

	return service
end

return commerce
