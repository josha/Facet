--!strict

local data = require("../content/data")
local rng = require("./rng")

local order_service = {}

local BACKLOG_FIRST = 101
local BACKLOG_LAST = 124
local FIRST_READY = 110
local ARRIVAL_COUNT = 20
local BREW_SECONDS = 60

local NEWEST_PLACED = 16 * 60 + 2

function order_service.new(opts: any): any
	local Compose = opts.Compose
	local clock = opts.clock
	local seed: number = opts.seed or 1
	local random = rng.new(seed)

	local self: any = {}
	local completedListeners: { (any) -> () } = {}
	local arrivalListeners: { (any) -> () } = {}
	local arrivalLog: { number } = {}

	local function rollItems(): ({ any }, number)
		local count = random.int(1, 5)
		local taken: { [string]: boolean } = {}
		local items: { any } = {}
		local bottles = 0
		for _ = 1, count do
			local potion
			for _ = 1, 8 do
				potion = random.pick(data.potions :: any)
				if not taken[potion.id] then
					break
				end
			end
			if taken[potion.id] then
				continue
			end
			taken[potion.id] = true
			local n = random.int(1, 5)
			bottles += n
			table.insert(items, { potion = potion.id, bottles = n })
		end
		return items, bottles
	end

	local function makeBrew(id: number, status: string, placedAt: number): any
		local items, bottles = rollItems()
		return {
			id = id,
			status = status,
			placedAt = placedAt,
			items = items,
			bottles = bottles,
			doneAt = if status == "done" then placedAt + 12 else nil,
			endsAt = nil :: number?,
			startedAt = nil :: number?,
		}
	end

	local backlog: { any } = {}
	local placed = NEWEST_PLACED
	for id = BACKLOG_LAST, BACKLOG_FIRST, -1 do
		local status = if id >= FIRST_READY then "ready" else "new"
		table.insert(backlog, makeBrew(id, status, placed))
		placed -= random.int(7, 19)
	end
	local brews = Compose.cell(backlog)
	self.brews = brews

	function self.byId(id: number): any?
		for _, brew in brews:peek() :: any do
			if brew.id == id then
				return brew
			end
		end
		return nil
	end

	function self.count(): number
		return #(brews:peek() :: any)
	end

	function self.searchText(brew: any): string
		local parts = { "brew #" .. tostring(brew.id), tostring(brew.id) }
		for _, item in brew.items do
			local potion = data.potionById(item.potion)
			if potion == nil then
				continue
			end
			table.insert(parts, potion.name)
			for _, ingredientId in { potion.base, potion.essence, potion.garnish } do
				local ingredient = data.ingredientById(ingredientId)
				if ingredient ~= nil then
					table.insert(parts, ingredient.name)
				end
			end
		end
		return string.lower(table.concat(parts, " "))
	end

	function self.remaining(id: number): number?
		local brew = self.byId(id)
		if brew == nil or brew.endsAt == nil then
			return nil
		end
		return math.max(0, brew.endsAt - clock.now())
	end

	function self.brewSeconds(): number
		return BREW_SECONDS
	end

	local function replace(id: number, mutate: (any) -> ())
		local current = brews:peek() :: any
		local out = table.create(#current)
		for _, brew in current do
			if brew.id == id then
				local copy = table.clone(brew)
				copy.items = brew.items
				mutate(copy)
				table.insert(out, copy)
			else
				table.insert(out, brew)
			end
		end
		brews:set(out)
	end

	function self.statusOf(id: number): string?
		local brew = self.byId(id)
		return if brew == nil then nil else brew.status
	end

	function self.canStart(from: string?): (boolean, string?)
		if from == "new" then
			return true
		end
		if from == "done" then
			return false, "reject.collected"
		end
		return false, "reject.fallback"
	end

	function self.canFinish(from: string?): (boolean, string?)
		if from == "new" or from == "brewing" or from == "ready" then
			return true
		end
		if from == "done" then
			return false, "reject.collected"
		end
		return false, "reject.fallback"
	end

	function self.applyStart(id: number)
		local now = clock.now()
		replace(id, function(brew)
			brew.status = "brewing"
			brew.startedAt = now
			brew.endsAt = now + BREW_SECONDS
		end)
	end

	function self.applyFinish(id: number)
		local minutes = NEWEST_PLACED + math.floor(clock.now() / 60)
		replace(id, function(brew)
			brew.status = "done"
			brew.endsAt = nil
			brew.doneAt = minutes
		end)
	end

	function self.restore(id: number, status: string, endsAt: number?, startedAt: number?)
		replace(id, function(brew)
			brew.status = status
			brew.endsAt = endsAt
			brew.startedAt = startedAt
		end)
	end

	function self.snapshotOf(id: number): any
		local brew = self.byId(id)
		if brew == nil then
			return { status = "new" }
		end
		return { status = brew.status, endsAt = brew.endsAt, startedAt = brew.startedAt }
	end

	function self.onCompleted(fn: (any) -> ())
		table.insert(completedListeners, fn)
	end

	function self.notifyCompleted(id: number)
		local brew = self.byId(id)
		if brew == nil then
			return
		end
		for _, fn in completedListeners do
			fn(brew)
		end
	end

	local arrivalTimes: { number } = {}
	local at = 0
	for _ = 1, ARRIVAL_COUNT do
		at += random.int(3, 8)
		table.insert(arrivalTimes, at)
	end
	self.arrivalTimes = arrivalTimes

	local nextArrivalId = BACKLOG_LAST + 1
	local arrived = 0

	local function arrive()
		local id = nextArrivalId
		nextArrivalId += 1
		arrived += 1
		local minutes = NEWEST_PLACED + math.floor(clock.now() / 60) + arrived
		local brew = makeBrew(id, "new", minutes)
		local current = brews:peek() :: any
		local out = table.create(#current + 1)
		table.insert(out, brew)
		for _, existing in current do
			table.insert(out, existing)
		end
		brews:set(out)
		table.insert(arrivalLog, id)
		for _, fn in arrivalListeners do
			fn(brew)
		end
	end

	for _, when in arrivalTimes do
		clock.after(when, arrive)
	end

	function self.onArrival(fn: (any) -> ())
		table.insert(arrivalListeners, fn)
	end

	function self.arrivalLog(): { number }
		return table.clone(arrivalLog)
	end

	function self.arrivalsRemaining(): number
		return ARRIVAL_COUNT - arrived
	end

	function self.dump(): any
		local counts = { new = 0, brewing = 0, ready = 0, done = 0 }
		local ids: { number } = {}
		for _, brew in brews:peek() :: any do
			counts[brew.status] = (counts[brew.status] or 0) + 1
			table.insert(ids, brew.id)
		end
		return {
			count = #ids,
			first = ids[1],
			last = ids[#ids],
			counts = counts,
			arrivals = table.clone(arrivalLog),
			arrivalsRemaining = self.arrivalsRemaining(),
		}
	end

	function self.dispose() end

	return self
end

return table.freeze(order_service)
