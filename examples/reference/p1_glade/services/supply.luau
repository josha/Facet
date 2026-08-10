--!strict
-- SupplyService — refill stamps, drain constants, derived levels (responsibility
-- ledger, P1 row 1). Production would be server-authoritative time plus a
-- DataStore per player; here it is a pure function of the seeded stamps and the
-- INJECTED `now` Readable, so a headless test and a Studio session see the same
-- arithmetic and a reset reproduces the world exactly.
--
-- No `os.*`, no `math.random`, no network. The only time in this module is the
-- Readable the caller hands in.

local seedData = require("../content/seed")

local supply = {}

export type Opts = {
	core: any,
	now: any, -- Readable<number>: injected world seconds
	scope: any,
}

local KINDS = { "nectar", "dew" }
supply.KINDS = KINDS

function supply.new(opts: Opts): any
	local core = opts.core
	local now = opts.now
	local scope = opts.scope

	-- semantic state: the refill stamp per glade per supply, and which nectar is
	-- assigned to each glade. Both survive re-solve; both reset from the seed.
	local stamps: { [string]: any } = {}
	local assigned: { [string]: any } = {}
	for _, glade in seedData.GLADES do
		stamps[glade.id] = {
			nectar = scope:own(core:signal(-glade.nectarAge)),
			dew = scope:own(core:signal(-glade.dewAge)),
		}
		assigned[glade.id] = scope:own(core:signal(glade.nectar))
	end

	local service = {}

	-- memo caches, keyed "<glade>/<kind>": one memo per supply, built on demand
	-- and owned by the service scope. Rebuilding them per read would make every
	-- card's ring its own dependency graph.
	local levels: { [string]: any } = {}
	local remainings: { [string]: any } = {}
	local states: { [string]: any } = {}

	local function elapsedOf(gladeId: string, kind: string, at: number): number
		local stamp = stamps[gladeId][kind]
		return at - stamp:get()
	end

	function service.remaining(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = remainings[key]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				local at = use(now)
				local stamp = use(stamps[gladeId][kind])
				local left = seedData.DRAIN[kind].empty - (at - stamp)
				return if left < 0 then 0 else left
			end))
			remainings[key] = memo
		end
		return memo
	end

	function service.level(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = levels[key]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				local left = use(service.remaining(gladeId, kind))
				return left / seedData.DRAIN[kind].empty
			end))
			levels[key] = memo
		end
		return memo
	end

	-- "full" | "low" | "empty" — the three states §6's table names. State is
	-- carried by FORM downstream (a chip, an empty arc, a strengthened caption),
	-- never by a second hue.
	function service.state(gladeId: string, kind: string): any
		local key = gladeId .. "/" .. kind
		local memo = states[key]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				local at = use(now)
				local stamp = use(stamps[gladeId][kind])
				local elapsed = at - stamp
				local drain = seedData.DRAIN[kind]
				if elapsed >= drain.empty then
					return "empty"
				elseif elapsed >= drain.low then
					return "low"
				end
				return "full"
			end))
			states[key] = memo
		end
		return memo
	end

	function service.nectarOf(gladeId: string): any
		return assigned[gladeId]
	end

	-- the two mutations. Both stamp `now`, which is what makes a refill visible
	-- as a ring returning to full and then draining again.
	function service.refill(gladeId: string, kind: string)
		stamps[gladeId][kind]:set(now:get())
	end

	-- assigning a nectar also refills it: a fresh jar IS a full supply, and the
	-- reference's "choose" is one act, not two.
	function service.assign(gladeId: string, nectarId: string)
		assigned[gladeId]:set(nectarId)
		service.refill(gladeId, "nectar")
	end

	function service.reset()
		for _, glade in seedData.GLADES do
			stamps[glade.id].nectar:set(-glade.nectarAge)
			stamps[glade.id].dew:set(-glade.dewAge)
			assigned[glade.id]:set(glade.nectar)
		end
	end

	-- deterministic, JSON-safe state for the proof's report/dump
	function service.dump(): any
		local out: { any } = {}
		for _, glade in seedData.GLADES do
			local at = now:get()
			table.insert(out, {
				glade = glade.id,
				nectar = assigned[glade.id]:get(),
				nectarElapsed = elapsedOf(glade.id, "nectar", at),
				dewElapsed = elapsedOf(glade.id, "dew", at),
				nectarState = service.state(glade.id, "nectar"):get(),
				dewState = service.state(glade.id, "dew"):get(),
			})
		end
		return out
	end

	return service
end

return supply
