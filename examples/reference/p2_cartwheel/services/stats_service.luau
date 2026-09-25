--!strict

local data = require("../content/data")
local rng = require("./rng")

local stats_service = {}

local TIMEFRAMES = table.freeze({ "today", "week", "month", "year" })
local POINTS = table.freeze({ twoWeeks = 14, month = 30, year = 12 })

function stats_service.new(opts: any): any
	local Compose = opts.Compose
	local seed: number = opts.seed or 1

	local self: any = {}
	local version = Compose.cell(0)
	self.version = version

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

	function self.recordCompletion(brew: any)
		for _, item in brew.items do
			collected[item.potion] = (collected[item.potion] or 0) + item.bottles
		end
		version:set(version:peek() + 1)
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

	function self.dispose() end

	return self
end

return table.freeze(stats_service)
