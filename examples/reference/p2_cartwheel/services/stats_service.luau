--!strict
-- StatsService — per-plaza seeded series, and the union that closes the loop.
--
-- "Today" is the only timeframe that is not purely seeded: it is the seed PLUS
-- every brew collected this session, so finishing a brew moves Top Five and the
-- Ledger. That union is RA-P2's closing move — the charts reflecting the change
-- the player just made — and it is why this service listens to OrderService
-- rather than sampling it.
--
-- Production mapping: an analytics/telemetry aggregation service.
local data = require("../content/data")
local rng = require("./rng")

local stats_service = {}

local TIMEFRAMES = table.freeze({ "today", "week", "month", "year" })
local POINTS = table.freeze({ twoWeeks = 14, month = 30, year = 12 })

function stats_service.new(opts: any): any
	local core = opts.core
	local seed: number = opts.seed or 1

	local self: any = {}
	local version = core:signal(0)
	self.version = version

	-- ---- seeded popularity: potion -> timeframe -> bottles ------------------
	local popularity: { [string]: { [string]: number } } = {}
	for _, potion in data.potions :: any do
		local random = rng.new(seed * 31 + potion.index)
		local today = random.int(2, 40)
		popularity[potion.id] = {
			today = today,
			week = today * random.int(4, 8) + random.int(0, 20),
			month = today * random.int(18, 30) + random.int(0, 60),
			year = today * random.int(200, 340) + random.int(0, 400),
		}
	end

	-- the live half: bottles collected this session, per potion
	local collected: { [string]: number } = {}

	function self.bottlesFor(potionId: string, timeframe: string): number
		local row = popularity[potionId]
		if row == nil then
			return 0
		end
		local base = row[timeframe] or row.today
		if timeframe == "today" or timeframe == "day" then
			return base + (collected[potionId] or 0)
		end
		return base + (collected[potionId] or 0)
	end

	-- Top Five, descending; ties break on the catalogue index so two equal
	-- counts always answer in the same order (a dump has to be reproducible).
	function self.topFive(timeframe: string): { any }
		local rows: { any } = {}
		for _, potion in data.potions :: any do
			table.insert(rows, { potion = potion, bottles = self.bottlesFor(potion.id, timeframe) })
		end
		table.sort(rows, function(a, b)
			if a.bottles == b.bottles then
				return a.potion.index < b.potion.index
			end
			return a.bottles > b.bottles
		end)
		local out: { any } = {}
		for index = 1, math.min(5, #rows) do
			table.insert(out, rows[index])
		end
		return out
	end

	function self.totalBottles(timeframe: string): number
		local total = 0
		for _, potion in data.potions :: any do
			total += self.bottlesFor(potion.id, timeframe)
		end
		return total
	end

	-- ---- the Ledger's per-plaza series --------------------------------------
	-- normalized 0..1 samples, seeded per (plaza, timeframe). The Path takes
	-- normalized control points, so this is the shape it wants with no scaling
	-- arithmetic at the call site.
	local seriesCache: { [string]: { number } } = {}

	function self.series(plazaId: string, timeframe: string): { number }
		local key = plazaId .. ":" .. timeframe
		local cached = seriesCache[key]
		if cached ~= nil then
			return cached
		end
		local plaza = data.plazaById(plazaId)
		local count = if timeframe == "year"
			then POINTS.year
			elseif timeframe == "month" then POINTS.month
			else POINTS.twoWeeks
		local random = rng.new(seed * 97 + (if plaza == nil then 0 else plaza.seed) + #timeframe)
		local weight = if plaza == nil then 1 else plaza.weight
		local out: { number } = {}
		local level = 0.5
		for _ = 1, count do
			level = math.clamp(level + (random.next() - 0.5) * 0.35, 0.08, 0.98)
			table.insert(out, level * weight)
		end
		seriesCache[key] = out
		return out
	end

	-- ---- the union ----------------------------------------------------------

	function self.recordCompletion(brew: any)
		for _, item in brew.items do
			collected[item.potion] = (collected[item.potion] or 0) + item.bottles
		end
		version:set(version:get() + 1)
	end

	function self.collectedBottles(): number
		local total = 0
		for _, n in collected do
			total += n
		end
		return total
	end

	function self.timeframes(): { string }
		return TIMEFRAMES :: any
	end

	function self.dump(): any
		local top = {}
		for _, row in self.topFive("today") do
			table.insert(top, { id = row.potion.id, bottles = row.bottles })
		end
		return { top = top, collected = self.collectedBottles(), totalToday = self.totalBottles("today") }
	end

	function self.dispose()
		version:dispose()
	end

	return self
end

return table.freeze(stats_service)
