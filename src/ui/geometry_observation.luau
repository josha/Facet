--!strict
local ComposeTypes = require("../vendor/compose/core")

type Update = { read: () -> (), publish: () -> () }

type Queue = {
	pending: { [Update]: boolean },
	thread: thread?,
	users: number,
}
local queues: { [ComposeTypes.Runtime]: Queue } = {}

return function(
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	node: Instance,
	property: string
): ComposeTypes.Cell<unknown>
	local observation = assert(runtime.host.observation)
	local initial: unknown = if task
			and task.defer
			and property ~= "CanvasPosition"
		then (if property == "TextFits" then false else Vector2.zero)
		else observation.readProperty(node, property)
	local value = Compose.cell(initial)
	local queue = queues[runtime]
	if queue == nil then
		queue = { pending = {}, users = 0 }
		queues[runtime] = queue
	end
	local held = queue :: Queue
	held.users += 1
	local alive = true
	local snapshot: unknown = initial
	local update: Update = {
		read = function()
			if alive then
				snapshot = observation.readProperty(node, property)
			end
		end,
		publish = function()
			if alive then
				value:set(snapshot)
			end
		end,
	}
	local function flush()
		held.thread = nil
		local pending = held.pending
		held.pending = {}
		for entry in pending do
			entry.read()
		end
		runtime.reactor:batch(function()
			for entry in pending do
				entry.publish()
			end
		end)
	end
	local function refresh()
		if not alive then
			return
		end
		if task and task.defer then
			held.pending[update] = true
			if held.thread == nil then
				held.thread = task.defer(flush)
			end
		else
			update.read()
			update.publish()
		end
	end
	local stop = observation.observeProperty(node, property, refresh)
	if task and task.defer then
		refresh()
	end
	Compose.cleanup(function()
		alive = false
		stop()
		held.pending[update] = nil
		held.users -= 1
		if next(held.pending) == nil and held.thread then
			task.cancel(held.thread)
			held.thread = nil
		end
		if held.users == 0 then
			queues[runtime] = nil
		end
	end)
	return value
end
