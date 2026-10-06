--!strict

export type Scheduler = {
	clock: () -> number,
	tag: (thread: thread, value: any) -> (),
	onFailure: (handler: (string) -> ()) -> (),
	context: () -> any,
	spawn: (callback: any, ...any) -> thread,
	spawnTagged: (tag: any, callback: any, ...any) -> thread,
	defer: (callback: any, ...any) -> thread,
	delay: (seconds: number, callback: any, ...any) -> thread,
	wait: (seconds: number?) -> number,
	block: (resume: (thread) -> ()) -> ...any,
	drain: (budget: number) -> (),
	advance: (seconds: number) -> (),
	resume: (thread: thread, ...any) -> (),
	cancel: (thread: thread) -> (),
	failures: { string },
	pending: () -> number,
}

local function create(): Scheduler
	local now = 0
	local ready: { { thread: thread, arguments: any } } = {}
	local timers: { { at: number, thread: thread } } = {}
	local failures: { string } = {}
	local tags: { [thread]: any } = {}
	local owners: { [thread]: thread } = {}
	local active: any = nil
	local scheduler: any = {}
	local onFailure: (string) -> () = function() end

	local function withTag(thread: thread, ...: any): ...any
		local previous = active
		active = tags[thread]
		local results = table.pack(coroutine.resume(thread, ...))
		active = previous
		return table.unpack(results, 1, results.n)
	end

	local function describe(thread: thread, message: any): string
		local ok, trace = pcall(function(): any
			return (debug :: any).traceback(thread)
		end)
		if ok and type(trace) == "string" then
			return tostring(message) .. "\n" .. trace
		end
		return tostring(message)
	end

	local function push(thread: thread, ...: any)
		ready[#ready + 1] = { thread = thread, arguments = table.pack(...) }
	end

	local function step()
		local batch = ready
		ready = {}
		for _, entry in batch do
			if coroutine.status(entry.thread) == "dead" then
				continue
			end
			local results = table.pack(withTag(entry.thread, table.unpack(entry.arguments, 1, entry.arguments.n)))
			if not results[1] then
				local message = describe(entry.thread, results[2])
				failures[#failures + 1] = message
				onFailure(message)
			end
		end
	end

	function scheduler.clock(): number
		return now
	end

	function scheduler.resume(thread: thread, ...: any)
		push(thread, ...)
	end

	function scheduler.spawn(callback: any, ...: any): thread
		local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
		if tags[thread] == nil then
			tags[thread] = active
		end
		local results = table.pack(withTag(thread, ...))
		if not results[1] then
			local message = describe(thread, results[2])
			failures[#failures + 1] = message
			onFailure(message)
		end
		return thread
	end

	function scheduler.spawnTagged(tag: any, callback: any, ...: any): thread
		local thread = coroutine.create(callback)
		tags[thread] = tag
		local results = table.pack(withTag(thread, ...))
		if not results[1] then
			local message = describe(thread, results[2])
			failures[#failures + 1] = message
			onFailure(message)
		end
		return thread
	end

	function scheduler.defer(callback: any, ...: any): thread
		local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
		if tags[thread] == nil then
			tags[thread] = active
		end
		push(thread, ...)
		return thread
	end

	function scheduler.delay(seconds: number, callback: any, ...: any): thread
		local thread = if type(callback) == "thread" then callback else coroutine.create(callback)
		local arguments = table.pack(...)
		if tags[thread] == nil then
			tags[thread] = active
		end
		local waiter = coroutine.create(function()
			withTag(thread, table.unpack(arguments, 1, arguments.n))
		end)
		tags[waiter] = active
		owners[waiter] = thread
		timers[#timers + 1] = { at = now + math.max(seconds, 0), thread = waiter }
		return thread
	end

	function scheduler.onFailure(handler: (string) -> ())
		onFailure = handler
	end

	function scheduler.tag(thread: thread, value: any)
		tags[thread] = value
	end

	function scheduler.context(): any
		return active
	end

	function scheduler.wait(seconds: number?): number
		local thread = coroutine.running()
		timers[#timers + 1] = { at = now + math.max(seconds or 0, 0), thread = thread }
		coroutine.yield()
		return seconds or 0
	end

	function scheduler.block(register: (thread) -> ()): ...any
		register(coroutine.running())
		return coroutine.yield()
	end

	function scheduler.advance(seconds: number)
		now += seconds
		local due: { { at: number, thread: thread, order: number } } = {}
		local keep: { { at: number, thread: thread } } = {}
		for order, timer in timers do
			if timer.at <= now then
				due[#due + 1] = { at = timer.at, thread = timer.thread, order = order }
			else
				keep[#keep + 1] = timer
			end
		end
		timers = keep
		table.sort(due, function(left, right): boolean
			if left.at ~= right.at then
				return left.at < right.at
			end
			return left.order < right.order
		end)
		for _, entry in due do
			push(entry.thread)
		end
	end

	function scheduler.drain(budget: number)
		local rounds = 0
		while #ready > 0 and rounds < budget do
			step()
			rounds += 1
		end
	end

	function scheduler.cancel(thread: thread)
		local keptReady: { { thread: thread, arguments: any } } = {}
		for _, entry in ready do
			if entry.thread ~= thread then
				table.insert(keptReady, entry)
			end
		end
		ready = keptReady
		local keptTimers: { { at: number, thread: thread } } = {}
		for _, timer in timers do
			if timer.thread ~= thread and owners[timer.thread] ~= thread then
				table.insert(keptTimers, timer)
			end
		end
		timers = keptTimers
		if coroutine.status(thread) == "suspended" then
			coroutine.close(thread)
		end
	end

	function scheduler.pending(): number
		return #ready + #timers
	end

	scheduler.failures = failures
	return scheduler :: Scheduler
end

return { create = create }
