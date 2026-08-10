--!strict
-- OrderService — the brews (spec §3).
--
-- Seeded backlog of 24 (#101-#109 New, #110-#124 Ready with synthetic
-- done-times), 20 scripted arrivals at seeded 3-8 s intervals, status commands,
-- and THE 60 s COUNTDOWN FACT PER BREW. That last one is the whole reason the
-- service owns time rather than the detail screen: a countdown that lives in the
-- view dies with the view, and the loop this proof exists to demonstrate is
-- "start a brew, walk away, come back and it is still counting".
--
-- Production mapping (responsibility ledger): MemoryStore queue / server sim,
-- with the countdown a server-time fact replicated to the client.
local data = require("../content/data")
local rng = require("./rng")

local order_service = {}

local BACKLOG_FIRST = 101
local BACKLOG_LAST = 124
local FIRST_READY = 110
local ARRIVAL_COUNT = 20
local BREW_SECONDS = 60

-- newest brew's placement, minutes since midnight (16:02)
local NEWEST_PLACED = 16 * 60 + 2

function order_service.new(opts: any): any
	local core = opts.core
	local clock = opts.clock
	local seed: number = opts.seed or 1
	local random = rng.new(seed)

	local self: any = {}
	local completedListeners: { (any) -> () } = {}
	local arrivalListeners: { (any) -> () } = {}
	local arrivalLog: { number } = {}

	-- ---- the seeded catalogue of a brew's contents --------------------------
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

	-- ---- the seeded backlog, newest first -----------------------------------
	local backlog: { any } = {}
	local placed = NEWEST_PLACED
	for id = BACKLOG_LAST, BACKLOG_FIRST, -1 do
		local status = if id >= FIRST_READY then "ready" else "new"
		table.insert(backlog, makeBrew(id, status, placed))
		placed -= random.int(7, 19)
	end
	local brews = core:signal(backlog)
	self.brews = brews

	-- ---- reads ---------------------------------------------------------------

	function self.byId(id: number): any?
		for _, brew in brews:get() :: any do
			if brew.id == id then
				return brew
			end
		end
		return nil
	end

	function self.count(): number
		return #(brews:get() :: any)
	end

	-- everything a search must match: the brew number, its potions and their
	-- ingredients (the reference searched the id alone — spec §6 completes it)
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

	-- the 60 s fact, read live off the domain clock. `nil` when this brew is not
	-- counting; the caller reads it inside a memo, so one advance moves every
	-- countdown on screen with one flush.
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

	-- ---- mutation ------------------------------------------------------------
	-- Records are replaced, never edited in place: the array is a signal, so a
	-- fresh record for the changed brew is what makes a memo over it re-run while
	-- every other row keeps its identity.

	local function replace(id: number, mutate: (any) -> ())
		local current = brews:get() :: any
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

	-- the AUTHORITY: may this brew be started / finished from `from`?
	function self.canStart(from: string?): (boolean, string?)
		if from == "new" then
			return true
		end
		if from == "done" then
			return false, "reject.collected"
		end
		return false, "reject.fallback"
	end

	-- COLLECTABLE FROM ANY LIVE STATE. The detail screen walks New -> Brewing ->
	-- Done, but the row menu and bulk complete both offer "Collect" on anything
	-- that is not already Done, so the authority has to allow it from New too —
	-- otherwise the list's own affordance would reject every New brew it offered.
	function self.canFinish(from: string?): (boolean, string?)
		if from == "new" or from == "brewing" or from == "ready" then
			return true
		end
		if from == "done" then
			return false, "reject.collected"
		end
		return false, "reject.fallback"
	end

	-- start: status -> brewing, and the countdown fact begins
	function self.applyStart(id: number)
		local now = clock.now()
		replace(id, function(brew)
			brew.status = "brewing"
			brew.startedAt = now
			brew.endsAt = now + BREW_SECONDS
		end)
	end

	-- finish: status -> done, the countdown fact ends
	function self.applyFinish(id: number)
		local minutes = NEWEST_PLACED + math.floor(clock.now() / 60)
		replace(id, function(brew)
			brew.status = "done"
			brew.endsAt = nil
			brew.doneAt = minutes
		end)
	end

	-- the undo half of an optimistic command
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

	-- ---- scripted arrivals ---------------------------------------------------
	-- Twenty New brews at seeded 3-8 s intervals, then the cart goes quiet. Each
	-- arrival lands at the FRONT (newest first) and tells its listeners, which is
	-- what drives the dashboard's slide-in and its numeric pulse.

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
		local current = brews:get() :: any
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

	-- ---- diagnostics ---------------------------------------------------------

	function self.dump(): any
		local counts = { new = 0, brewing = 0, ready = 0, done = 0 }
		local ids: { number } = {}
		for _, brew in brews:get() :: any do
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

	function self.dispose()
		brews:dispose()
	end

	return self
end

return table.freeze(order_service)
