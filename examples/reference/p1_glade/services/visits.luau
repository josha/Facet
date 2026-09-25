--!strict

local seedData = require("../content/seed")

local visits = {}

export type Opts = {
	Compose: any,
	rooted: (() -> any) -> any,
	now: any,
	charmTier: any,
}

function visits.new(opts: Opts): any
	local Compose = opts.Compose

	local rooted = opts.rooted
	local now = opts.now
	local charmTier = opts.charmTier

	local presented: { [string]: boolean } = {}

	local service = {}

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
			memo = rooted(function()
				return Compose.formula(function(use)
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
				end)
			end)
			currentByGlade[gladeId] = memo
		end
		return memo
	end

	function service.recent(gladeId: string): any
		local memo = recentByGlade[gladeId]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use)
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
				end)
			end)
			recentByGlade[gladeId] = memo
		end
		return memo
	end

	local currentAll = Compose.formula(function(use)
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
	end)

	function service.currentAll(): any
		return currentAll
	end

	function service.lastSeen(wispId: string): any?
		local at = now:peek()
		local tier = charmTier:peek()
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

	function service.needsPresent(gladeId: string): any?
		local live = service.current(gladeId):peek()
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
		for _, entry in currentAll:peek() do
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
