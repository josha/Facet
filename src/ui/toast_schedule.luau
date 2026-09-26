--!strict
local toast_schedule = {}

export type Entry = {
	id: number,
	key: string?,
	priority: number,
	duration: number,
	readFloor: number,
	data: unknown,
	shownAt: number?,
	sequence: number,
	held: boolean,
	asked: { [string]: boolean },
}
export type Options = {
	maxVisible: number?,
	queueCap: number?,
	duration: number?,
	readFloor: number?,
	now: (() -> number)?,
	onDismiss: ((Entry, string) -> ())?,
	onChange: (() -> ())?,
	onPropose: ((Entry, string) -> ())?,
}
export type Push = {
	key: string?,
	priority: number?,
	duration: number?,
	readFloor: number?,
	data: unknown,
	held: boolean?,
}
export type Schedule = {
	push: (Push) -> number,
	update: () -> (),
	dismiss: (number, string?) -> boolean,
	visible: () -> { Entry },
	queued: () -> { Entry },
	counts: () -> { visible: number, queued: number },
	isEmpty: () -> boolean,
}

toast_schedule.DEFAULTS = table.freeze({ maxVisible = 3, queueCap = 8, duration = 4, readFloor = 2.5 })

local function positive(value: unknown, fallback: number): number
	return if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else fallback
end

function toast_schedule.new(options: Options?): Schedule
	local settings: Options = options or {}
	local defaults = toast_schedule.DEFAULTS
	local maxVisible = math.max(1, math.floor(positive(settings.maxVisible, defaults.maxVisible)))
	local queueCap = math.floor(positive(settings.queueCap, defaults.queueCap))
	local duration = positive(settings.duration, defaults.duration)
	local readFloor = positive(settings.readFloor, defaults.readFloor)
	local now = settings.now or os.clock
	local visible: { Entry } = {}
	local queue: { Entry } = {}
	local sequence = 0
	local changed = false
	local proposals: { { entry: Entry, reason: string } } = {}

	local function outranks(a: Entry, b: Entry): boolean
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.sequence < b.sequence
	end
	local function retire(entry: Entry, reason: string)
		changed = true
		if settings.onDismiss then
			settings.onDismiss(entry, reason)
		end
	end
	local function floorMet(entry: Entry, at: number): boolean
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
	local function weakest(): number?
		local worst: number? = nil
		for index, entry in visible do
			if worst == nil or outranks(visible[worst], entry) then
				worst = index
			end
		end
		return worst
	end
	local function ask(entry: Entry, reason: string)
		if not entry.asked[reason] then
			entry.asked[reason] = true
			table.insert(proposals, { entry = entry, reason = reason })
		end
	end
	local function show(index: number, at: number)
		local entry = table.remove(queue, index) :: Entry
		entry.shownAt = at
		table.insert(visible, entry)
		changed = true
	end

	local function resolve()
		local at = now()
		for _, entry in table.clone(visible) do
			if at - (entry.shownAt :: number) >= entry.duration then
				if entry.held then
					ask(entry, "timeout")
					continue
				end
				table.remove(visible, table.find(visible, entry) :: number)
				retire(entry, "timeout")
			end
		end
		for _, waiting in table.clone(queue) do
			local index = showing(waiting.key)
			if index and floorMet(visible[index], at) then
				if visible[index].held then
					ask(visible[index], "supersede")
					continue
				end
				retire(table.remove(visible, index) :: Entry, "supersede")
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
			local index, worst = eligible(), weakest()
			if index == nil or worst == nil then
				break
			end
			if not outranks(queue[index], visible[worst]) or not floorMet(visible[worst], at) then
				break
			end
			if visible[worst].held then
				ask(visible[worst], "preempt")
				break
			end
			retire(table.remove(visible, worst) :: Entry, "preempt")
			show(index, at)
		end
		if changed then
			changed = false
			if settings.onChange then
				settings.onChange()
			end
		end
		local asked = proposals
		proposals = {}
		for _, proposal in asked do
			if settings.onPropose then
				settings.onPropose(proposal.entry, proposal.reason)
			end
		end
	end

	local schedule = {}
	function schedule.push(spec: Push): number
		sequence += 1
		local entry: Entry = {
			id = sequence,
			key = if type(spec.key) == "string" then spec.key else nil,
			priority = if type(spec.priority) == "number" and math.abs(spec.priority) < math.huge
				then spec.priority
				else 0,
			duration = if spec.duration == math.huge then math.huge else positive(spec.duration, duration),
			readFloor = positive(spec.readFloor, readFloor),
			data = spec.data,
			shownAt = nil,
			sequence = sequence,
			held = spec.held == true,
			asked = {},
		}
		if entry.key then
			for index = #queue, 1, -1 do
				if queue[index].key == entry.key then
					retire(table.remove(queue, index) :: Entry, "supersede")
				end
			end
		end
		table.insert(queue, entry)
		table.sort(queue, outranks)
		while #queue > queueCap do
			retire(table.remove(queue) :: Entry, "capacity")
		end
		resolve()
		return entry.id
	end
	function schedule.update()
		resolve()
	end
	function schedule.dismiss(id: number, reason: string?): boolean
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
	end
	function schedule.visible(): { Entry }
		return table.clone(visible)
	end
	function schedule.queued(): { Entry }
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
