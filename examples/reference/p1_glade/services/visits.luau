--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T

local seedData = require("../content/seed")

local visits = {}

export type Opts = {
	Compose: ComposeModule,
	rooted: <T>(() -> T) -> T,
	now: ReadOnlyValue<number>,
	charmTier: ReadOnlyValue<string>,
}
export type Current = { id: string, wisp: string, glade: string, start: number }
export type Recent = { id: string, wisp: string, glade: string, finish: number }
export type Live = { id: string, wisp: string, glade: string }
export type Seen = { at: number, glade: string }
export type Dump = { current: { { glade: string, wisp: string, visit: string } }, presented: { string } }
type Visit = seedData.Visit

function visits.new(opts: Opts)
	local Compose: ComposeModule = opts.Compose

	local rooted = opts.rooted
	local now = opts.now
	local charmTier = opts.charmTier

	local presented: { [string]: boolean } = {}

	local service = {}

	local function startOf(visit: Visit, tier: string): number
		if visit.earlyStart ~= nil and tier == "lumen" then
			return visit.earlyStart
		end
		return visit.start
	end

	local currentByGlade: { [string]: ReadOnlyValue<Current?> } = {}
	local recentByGlade: { [string]: ReadOnlyValue<{ Recent }> } = {}

	function service.current(gladeId: string): ReadOnlyValue<Current?>
		local memo = currentByGlade[gladeId]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use: Use): Current?
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

	function service.recent(gladeId: string): ReadOnlyValue<{ Recent }>
		local memo = recentByGlade[gladeId]
		if memo == nil then
			memo = rooted(function()
				return Compose.formula(function(use: Use): { Recent }
					local at = use(now)
					local tier = use(charmTier)
					local out: { Recent } = {}
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
					table.sort(out, function(a: Recent, b: Recent)
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

	local currentAll = Compose.formula(function(use: Use): { Live }
		local at = use(now)
		local tier = use(charmTier)
		local out: { Live } = {}
		for _, visit in seedData.VISITS do
			local from = startOf(visit, tier)
			if at >= from and at < visit.finish then
				table.insert(out, { id = visit.id, wisp = visit.wisp, glade = visit.glade })
			end
		end
		return out
	end)

	function service.currentAll(): ReadOnlyValue<{ Live }>
		return currentAll
	end

	function service.lastSeen(wispId: string): Seen?
		local at = now:peek()
		local tier = charmTier:peek()
		local best: Seen? = nil
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

	function service.needsPresent(gladeId: string): Current?
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

	function service.dump(): Dump
		local live: { { glade: string, wisp: string, visit: string } } = {}
		for _, entry in currentAll:peek() do
			table.insert(live, { glade = entry.glade, wisp = entry.wisp, visit = entry.id })
		end
		table.sort(live, function(a, b)
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
