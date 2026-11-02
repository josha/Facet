--!strict
local toast_schedule = {}

type Reason = "timeout" | "supersede" | "preempt" | "capacity" | "manual"

export type Entry<T = unknown> = {
	id: number,
	key: string?,
	priority: number,
	duration: number,
	readFloor: number,
	data: T,
	shownAt: number?,
	held: boolean,
	asked: { [string]: boolean },
}
export type Options<T = unknown, R = string> = {
	maxVisible: number?,
	queueCap: number?,
	duration: number?,
	readFloor: number?,
	now: (() -> number)?,
	onDismiss: ((Entry<T>, Reason | R) -> ())?,
	onChange: (() -> ())?,
	onPropose: ((Entry<T>, Reason | R) -> ())?,
}
export type Push<T = unknown> = {
	key: string?,
	priority: number?,
	duration: number?,
	readFloor: number?,
	data: T,
	held: boolean?,
}
export type Schedule<T = unknown, R = string> = {
	push: (Push<T>) -> number,
	update: () -> (),
	dismiss: (number, R?) -> boolean,
	visible: () -> { Entry<T> },
	queued: () -> { Entry<T> },
	counts: () -> { visible: number, queued: number },
	isEmpty: () -> boolean,
}

toast_schedule.DEFAULTS = table.freeze({ maxVisible = 3, queueCap = 8, duration = 4, readFloor = 2.5 })

local function positive(value: unknown, fallback: number): number
	return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else fallback
end

function toast_schedule.new<T, R>(options: Options<T, R>?): Schedule<T, R>
	local settings: Options<T, R> = options or {}
	local defaults = toast_schedule.DEFAULTS
	local maxVisible = math.max(1, math.floor(positive(settings.maxVisible, defaults.maxVisible)))
	local queueCap = math.max(1, math.floor(positive(settings.queueCap, defaults.queueCap)))
	local duration = positive(settings.duration, defaults.duration)
	local readFloor = positive(settings.readFloor, defaults.readFloor)
	local now = settings.now or os.clock
	local visible: { Entry<T> } = {}
	local queue: { Entry<T> } = {}
	local sequence = 0
	local changed = false
	local proposals: { { entry: Entry<T>, reason: Reason } } = {}
	local depth = 0
	local pending: { () -> () } = {}
	local function guarded<T, A...>(body: (A...) -> T, ...: A...): T
		depth += 1
		local ok: boolean, result: T = pcall(body, ...)
		local failure: unknown = if ok then nil else result
		if ok and depth == 1 then
			while failure == nil and #pending > 0 do
				local callback = assert(table.remove(pending, 1))
				local done, problem = pcall(callback)
				failure = if done then nil else problem
			end
		end
		depth -= 1
		if failure ~= nil then
			table.clear(pending)
			error(failure, 0)
		end
		return result
	end

	local function outranks(a: Entry<T>, b: Entry<T>): boolean
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.id < b.id
	end
	local function retire(entry: Entry<T>, reason: Reason | R)
		changed = true
		local onDismiss = settings.onDismiss
		if onDismiss then
			table.insert(pending, function()
				onDismiss(entry, reason)
			end)
		end
	end
	local function floorMet(entry: Entry<T>, at: number): boolean
		return entry.shownAt ~= nil and at - entry.shownAt >= entry.readFloor
	end
	local function showing(key: string?): number?
		if key == nil then
			return nil
		end
		for index, entry in visible do
			if entry.key == key then
				return index
			end
		end
		return nil
	end
	local function eligible(): number?
		for index, waiting in queue do
			if showing(waiting.key) == nil then
				return index
			end
		end
		return nil
	end
	local function ask(entry: Entry<T>, reason: Reason)
		if not entry.asked[reason] then
			entry.asked[reason] = true
			table.insert(proposals, { entry = entry, reason = reason })
		end
	end
	local function show(index: number, at: number)
		local entry = assert(table.remove(queue, index))
		entry.shownAt = at
		table.insert(visible, entry)
		changed = true
	end

	local function resolve(): nil
		local at = now()
		for _, entry in table.clone(visible) do
			if at - assert(entry.shownAt) >= entry.duration then
				if entry.held then
					ask(entry, "timeout")
					continue
				end
				table.remove(visible, assert(table.find(visible, entry)))
				retire(entry, "timeout")
			end
		end
		for _, waiting in queue do
			local index = showing(waiting.key)
			if index and floorMet(visible[index], at) then
				if visible[index].held then
					ask(visible[index], "supersede")
					continue
				end
				retire(assert(table.remove(visible, index)), "supersede")
			end
		end
		while #visible < maxVisible do
			local index = eligible()
			if index == nil then
				break
			end
			show(index, at)
		end
		while #visible >= maxVisible do
			local index = eligible()
			if index == nil then
				break
			end
			local worst = 1
			for at, entry in visible do
				if outranks(visible[worst], entry) then
					worst = at
				end
			end
			if not outranks(queue[index], visible[worst]) or not floorMet(visible[worst], at) then
				break
			end
			if visible[worst].held then
				ask(visible[worst], "preempt")
				break
			end
			retire(assert(table.remove(visible, worst)), "preempt")
			show(index, at)
		end
		if changed then
			changed = false
			if settings.onChange then
				table.insert(pending, settings.onChange)
			end
		end
		local onPropose = settings.onPropose
		for _, proposal in proposals do
			if onPropose then
				table.insert(pending, function()
					onPropose(proposal.entry, proposal.reason)
				end)
			end
		end
		table.clear(proposals)
		return nil
	end

	local schedule = {}
	local function enqueue(spec: Push<T>): number
		sequence += 1
		local entry: Entry<T> = {
			id = sequence,
			key = if type(spec.key) == "string" then spec.key else nil,
			priority = if type(spec.priority) == "number" and math.abs(spec.priority) < math.huge
				then spec.priority
				else 0,
			duration = if spec.duration == math.huge then math.huge else positive(spec.duration, duration),
			readFloor = positive(spec.readFloor, readFloor),
			data = spec.data,
			shownAt = nil,
			held = spec.held == true,
			asked = {},
		}
		if entry.key then
			for index = #queue, 1, -1 do
				if queue[index].key == entry.key then
					retire(assert(table.remove(queue, index)), "supersede")
				end
			end
		end
		table.insert(queue, entry)
		changed = true
		table.sort(queue, outranks)
		while #queue > queueCap do
			retire(assert(table.remove(queue)), "capacity")
		end
		resolve()
		return entry.id
	end
	function schedule.push(spec: Push<T>): number
		return guarded(enqueue, spec)
	end
	function schedule.update()
		guarded(resolve)
	end
	function schedule.dismiss(id: number, reason: R?): boolean
		return guarded(function()
			for _, list in { visible, queue } do
				for index, entry in list do
					if entry.id == id then
						table.remove(list, index)
						retire(entry, reason or "manual")
						resolve()
						return true
					end
				end
			end
			return false
		end)
	end
	function schedule.visible(): { Entry<T> }
		return table.clone(visible)
	end
	function schedule.queued(): { Entry<T> }
		return table.clone(queue)
	end
	function schedule.counts(): { visible: number, queued: number }
		return { visible = #visible, queued = #queue }
	end
	function schedule.isEmpty(): boolean
		return #visible == 0 and #queue == 0
	end
	return schedule
end

return toast_schedule
