--!strict
-- VisitScheduler — seeded past / current / future visit windows, with
-- `currentVisitor` and `needsPresent` derived (responsibility ledger, P1 row 3).
-- Production would be a server sim plus a DataStore, with tier-gated content
-- driven by an entitlement fact — which is exactly the shape the Lumen early
-- arrival takes here: the window's start is READ from the charm tier, so the
-- gate is data, never a branch in the view.

local seedData = require("../content/seed")

local visits = {}

export type Opts = {
	core: any,
	now: any, -- Readable<number>
	charmTier: any, -- Readable<string>
	scope: any,
}

function visits.new(opts: Opts): any
	local core = opts.core
	local now = opts.now
	local charmTier = opts.charmTier
	local scope = opts.scope

	-- which visits have already had their arrival ceremony played. Presentation
	-- state, not world state: it never replicates and it resets with the world.
	local presented: { [string]: boolean } = {}

	local service = {}

	-- the effective start of a window. A Lumen keeper sees `earlyStart`; anyone
	-- else waits for `start`.
	local function startOf(visit: any, tier: string): number
		if visit.earlyStart ~= nil and tier == "lumen" then
			return visit.earlyStart
		end
		return visit.start
	end

	local currentByGlade: { [string]: any } = {}
	local recentByGlade: { [string]: any } = {}

	function service.current(gladeId: string): any
		local memo = currentByGlade[gladeId]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				local at = use(now)
				local tier = use(charmTier)
				for _, visit in seedData.VISITS do
					if visit.glade == gladeId then
						local from = startOf(visit, tier)
						if at >= from and at < visit.finish then
							return { id = visit.id, wisp = visit.wisp, glade = visit.glade, start = from }
						end
					end
				end
				return nil
			end))
			currentByGlade[gladeId] = memo
		end
		return memo
	end

	-- past visits, most recent first — the S2 "Recent visitors" list
	function service.recent(gladeId: string): any
		local memo = recentByGlade[gladeId]
		if memo == nil then
			memo = scope:own(core:memo(function(use)
				local at = use(now)
				local tier = use(charmTier)
				local out: { any } = {}
				for _, visit in seedData.VISITS do
					if visit.glade == gladeId and visit.finish <= at then
						table.insert(
							out,
							{ id = visit.id, wisp = visit.wisp, glade = visit.glade, finish = visit.finish }
						)
					end
				end
				-- a current visit counts as seen, at its start
				local live = use(service.current(gladeId))
				if live ~= nil then
					table.insert(out, { id = live.id, wisp = live.wisp, glade = live.glade, finish = live.start })
				end
				table.sort(out, function(a: any, b: any)
					if a.finish == b.finish then
						return a.id > b.id
					end
					return a.finish > b.finish
				end)
				local _ = tier
				return out
			end))
			recentByGlade[gladeId] = memo
		end
		return memo
	end

	-- every glade with a visitor right now — the search suggestions' source
	local currentAll = scope:own(core:memo(function(use)
		local at = use(now)
		local tier = use(charmTier)
		local out: { any } = {}
		for _, visit in seedData.VISITS do
			local from = startOf(visit, tier)
			if at >= from and at < visit.finish then
				table.insert(out, { id = visit.id, wisp = visit.wisp, glade = visit.glade })
			end
		end
		return out
	end))

	function service.currentAll(): any
		return currentAll
	end

	-- when was this wisp last seen, and where (S6's "Last seen {when} in {glade}")
	function service.lastSeen(wispId: string): any?
		local at = now:get()
		local tier = charmTier:get()
		local best: any = nil
		for _, visit in seedData.VISITS do
			if visit.wisp == wispId then
				local from = startOf(visit, tier)
				local seenAt = if visit.finish <= at then visit.finish elseif at >= from then from else nil
				if seenAt ~= nil and (best == nil or seenAt > best.at) then
					best = { at = seenAt, glade = visit.glade }
				end
			end
		end
		return best
	end

	-- the arrival ceremony's gate: a current visit whose fly-in has not run yet.
	function service.needsPresent(gladeId: string): any?
		local live = service.current(gladeId):get()
		if live == nil or presented[live.id] then
			return nil
		end
		return live
	end

	function service.markPresented(visitId: string)
		presented[visitId] = true
	end

	function service.reset()
		presented = {}
	end

	function service.dump(): any
		local live: { any } = {}
		for _, entry in currentAll:get() do
			table.insert(live, { glade = entry.glade, wisp = entry.wisp, visit = entry.id })
		end
		table.sort(live, function(a: any, b: any)
			return a.visit < b.visit
		end)
		local shown: { string } = {}
		for id in presented do
			table.insert(shown, id)
		end
		table.sort(shown)
		return { current = live, presented = shown }
	end

	return service
end

return visits
