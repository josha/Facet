--!strict
-- THE TOAST SCHEDULER (ADR-0022 Decision 4; ui-designer spec §3.2; acceptance row
-- SF-T2). A pure model: no blueprint, no adapter, no engine, no wall clock — the
-- presenter is a thin driver over it, so every rule below is provable headlessly
-- under an injected `now()` and stays provable when the presentation changes.
--
-- The rules, and the reason each one exists:
--
--   * MAX VISIBLE 3 / QUEUE CAP 8 (defaults, both options — disposition F1). A
--     burst must not stack unbounded, and a queue that grows forever is a queue
--     nobody will ever read.
--   * THE READ FLOOR IS NEVER TRUNCATED BY PRIORITY (disposition F2). Priority
--     orders the QUEUE. A showing toast is immune to replacement until its floor
--     has elapsed — an urgent message that erases the sentence a player is
--     mid-way through has cost more information than it delivered.
--   * A CAPACITY DROP IS AN EVENT (disposition F3). At the cap the LOWEST-priority
--     QUEUED entry is dropped (never a showing one) and it emits
--     `dismiss(reason = "capacity")` — nothing may vanish untraceably.
--   * SAME-KEY SUPERSEDE replaces its predecessor: immediately while it is
--     queued, and the moment the read floor is met while it is showing.
--   * PREEMPTION waits. When the queue holds something more urgent than the
--     lowest-priority showing toast, it replaces it — but only once that toast's
--     floor has elapsed (the same rule as above, seen from the other side).
--
-- Time only ever enters through `now()`, and nothing here reads a clock of its
-- own. Every mutating call resolves the schedule synchronously, so an `onDismiss`
-- fires on the frame its cause resolved (the causal-frame rule, SF-F1).
--
--   local schedule = toast_schedule.new({ now = fn, onDismiss = fn, ... })
--   schedule.push({ key?, priority?, duration?, readFloor?, data }) -> id
--   schedule.update()          -- retire what is due, promote what fits
--   schedule.visible()         -- showing entries, newest LAST (stack order)
--   schedule.dismiss(id, reason?)
--   schedule.counts()          -- { visible, queued, sequence }

local toast_schedule = {}

-- ui-designer spec §3.2, all designer-set framework defaults (disposition F1)
local DEFAULT_MAX_VISIBLE = 3
local DEFAULT_QUEUE_CAP = 8
local DEFAULT_DURATION = 4
-- 1.5 → 2.5 at the SFH-3 human gate (the row that ratified the number invited
-- retuning it): at race-glance speed the detail line was gone before it was read
local DEFAULT_READ_FLOOR = 2.5

export type Entry = {
	id: number,
	key: string?,
	priority: number,
	duration: number,
	readFloor: number,
	data: any,
	-- set when it becomes visible; nil while queued
	shownAt: number?,
	-- FIFO tie-break within a priority
	sequence: number,
}

export type Opts = {
	maxVisible: number?,
	queueCap: number?,
	duration: number?,
	readFloor: number?,
	now: (() -> number)?,
	-- (entry, reason) — "timeout" | "supersede" | "capacity" | "preempt" | "manual"
	onDismiss: ((entry: Entry, reason: string) -> ())?,
	onChange: (() -> ())?,
}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function positive(value: any, fallback: number): number
	return if isFinite(value) and (value :: number) >= 0 then value :: number else fallback
end

function toast_schedule.new(opts: Opts?)
	local options: Opts = opts or {}
	local maxVisible = math.max(1, math.floor(positive(options.maxVisible, DEFAULT_MAX_VISIBLE)))
	local queueCap = math.max(0, math.floor(positive(options.queueCap, DEFAULT_QUEUE_CAP)))
	local defaultDuration = positive(options.duration, DEFAULT_DURATION)
	local defaultReadFloor = positive(options.readFloor, DEFAULT_READ_FLOOR)
	local now = options.now or os.clock
	local onDismiss = options.onDismiss
	local onChange = options.onChange

	local visible: { Entry } = {} -- showing, oldest first (the stack order)
	local queue: { Entry } = {} -- waiting, priority-ordered, FIFO within a priority
	local nextId = 0
	local sequence = 0
	local changed = false

	local schedule = {}

	local function retired(entry: Entry, reason: string)
		if onDismiss ~= nil then
			onDismiss(entry, reason)
		end
	end

	local function markChanged()
		changed = true
	end

	-- priority DESC, then FIFO. One comparator, so "higher wins" cannot mean two
	-- different things in two places.
	local function outranks(a: Entry, b: Entry): boolean
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.sequence < b.sequence
	end

	local function sortQueue()
		table.sort(queue, outranks)
	end

	local function floorMet(entry: Entry, t: number): boolean
		return entry.shownAt ~= nil and (t - (entry.shownAt :: number)) >= entry.readFloor
	end

	-- the showing toast a newcomer would replace: lowest priority, oldest first
	local function weakestVisible(): (Entry?, number?)
		local worst: Entry? = nil
		local worstIndex: number? = nil
		for i, entry in visible do
			if worst == nil or outranks(worst, entry) then
				worst, worstIndex = entry, i
			end
		end
		return worst, worstIndex
	end

	local function show(entry: Entry, t: number)
		entry.shownAt = t
		table.insert(visible, entry)
		markChanged()
	end

	local function removeVisible(index: number, reason: string)
		local entry = table.remove(visible, index) :: Entry
		markChanged()
		retired(entry, reason)
	end

	-- enforce the queue cap by dropping the LOWEST-priority queued entry (which may
	-- be the newcomer itself — that is the honest outcome of "you are the least
	-- urgent thing here"), emitting the capacity dismissal (F3)
	local function enforceCap()
		while #queue > queueCap do
			local dropped = table.remove(queue) :: Entry
			markChanged()
			retired(dropped, "capacity")
		end
	end

	local function resolve()
		local t = now()
		-- 1. retire what has run its duration
		local i = 1
		while i <= #visible do
			local entry = visible[i]
			if entry.shownAt ~= nil and (t - (entry.shownAt :: number)) >= entry.duration then
				removeVisible(i, "timeout")
			else
				i += 1
			end
		end
		-- 2. a queued same-key entry replaces a showing one the moment its floor is
		-- met (a queued predecessor was already replaced at push time)
		local q = 1
		while q <= #queue do
			local waiting = queue[q]
			local replaced = false
			if waiting.key ~= nil then
				for v, entry in visible do
					if entry.key == waiting.key then
						if floorMet(entry, t) then
							removeVisible(v, "supersede")
							replaced = true
						end
						break
					end
				end
			end
			if replaced then
				q = 1 -- the visible set moved; re-examine from the top
			else
				q += 1
			end
		end
		-- 3. promote whatever fits — SKIPPING a queued toast whose subject is
		-- already showing. It is not a second message, it is the next value of the
		-- one being read, so it takes that toast's place at its floor (step 2) and
		-- never appears beside it.
		local function firstEligible(): number?
			for i, waiting in queue do
				local blocked = false
				if waiting.key ~= nil then
					for _, entry in visible do
						if entry.key == waiting.key then
							blocked = true
							break
						end
					end
				end
				if not blocked then
					return i
				end
			end
			return nil
		end
		while #visible < maxVisible do
			local index = firstEligible()
			if index == nil then
				break
			end
			show(table.remove(queue, index) :: Entry, t)
		end
		-- 4. preemption: the queue holds something more urgent than the weakest
		-- showing toast — it takes its place, but only once that toast has been
		-- readable for its floor (F2: priority never truncates a read floor)
		while #visible >= maxVisible do
			local index = firstEligible()
			if index == nil then
				break
			end
			local waiting = queue[index]
			local worst, worstIndex = weakestVisible()
			if worst == nil or worstIndex == nil or not outranks(waiting, worst) then
				break
			end
			if not floorMet(worst, t) then
				break -- it will be preempted the moment it has been read
			end
			removeVisible(worstIndex, "preempt")
			show(table.remove(queue, index) :: Entry, t)
		end
		if changed then
			changed = false
			if onChange ~= nil then
				onChange()
			end
		end
	end

	-- push a toast. Returns its id; `dismiss(id)` retires it early.
	function schedule.push(spec: any): number
		if type(spec) ~= "table" then
			error(`LuauUI toast: presentToast takes an options table, got {typeof(spec)}`, 0)
		end
		nextId += 1
		sequence += 1
		local entry: Entry = {
			id = nextId,
			key = if type(spec.key) == "string" then spec.key else nil,
			priority = if isFinite(spec.priority) then spec.priority else 0,
			duration = positive(spec.duration, defaultDuration),
			readFloor = positive(spec.readFloor, defaultReadFloor),
			data = spec.data,
			shownAt = nil,
			sequence = sequence,
		}
		-- SAME-KEY SUPERSEDE: a queued predecessor goes now (nothing has been read
		-- yet); a SHOWING one is left alone here and replaced in `resolve` the moment
		-- its read floor is met
		if entry.key ~= nil then
			for i = #queue, 1, -1 do
				if queue[i].key == entry.key then
					local replaced = table.remove(queue, i) :: Entry
					markChanged()
					retired(replaced, "supersede")
				end
			end
		end
		table.insert(queue, entry)
		sortQueue()
		enforceCap()
		resolve()
		return entry.id
	end

	function schedule.dismiss(id: number, reason: string?)
		local why = reason or "manual"
		for i, entry in visible do
			if entry.id == id then
				removeVisible(i, why)
				resolve()
				return true
			end
		end
		for i, entry in queue do
			if entry.id == id then
				table.remove(queue, i)
				markChanged()
				retired(entry, why)
				resolve()
				return true
			end
		end
		return false
	end

	-- advance: retire what is due and promote what fits. Idempotent; call it once
	-- per frame from the same loop that steps the motion clock.
	function schedule.update()
		resolve()
	end

	function schedule.visible(): { Entry }
		return table.clone(visible)
	end

	function schedule.queued(): { Entry }
		return table.clone(queue)
	end

	function schedule.counts()
		return { visible = #visible, queued = #queue, sequence = sequence }
	end

	function schedule.isEmpty(): boolean
		return #visible == 0 and #queue == 0
	end

	-- retire everything (a surface tearing down): every entry still reports why
	function schedule.clear(reason: string?)
		local why = reason or "manual"
		for i = #visible, 1, -1 do
			removeVisible(i, why)
		end
		for i = #queue, 1, -1 do
			local entry = table.remove(queue, i) :: Entry
			markChanged()
			retired(entry, why)
		end
		changed = false
	end

	return schedule
end

toast_schedule.DEFAULTS = table.freeze({
	maxVisible = DEFAULT_MAX_VISIBLE,
	queueCap = DEFAULT_QUEUE_CAP,
	duration = DEFAULT_DURATION,
	readFloor = DEFAULT_READ_FLOOR,
})

return toast_schedule
