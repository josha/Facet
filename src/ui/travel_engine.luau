--!strict
local Shared = require("./types")

export type Options = {
	initial: { number },
	carrier: GuiObject?,
	target: () -> { number },
	sample: ({ number }) -> (),
	complete: (() -> ())?,
	start: (() -> ())?,
	delay: (() -> number)?,
	reduced: () -> boolean,
	motion: "ease" | "spring",
	duration: number,
	ease: (number) -> number,
	spring: { period: number, damping: number },
}
export type Handle = {
	retarget: () -> (),
	stop: () -> (),
	snap: ({ number }) -> (),
	rebase: ({ number }) -> (),
	velocity: () -> { number },
	depth: number,
}
type Entry = { tick: (number) -> (), active: boolean, depth: number }
type Service = { entries: { Entry }, carriers: { [GuiObject]: Entry }, disconnect: (() -> ())? }
local services = setmetatable({} :: { [Shared.Runtime]: Service }, { __mode = "k" })

return function(ctx: Shared.Context, options: Options): Handle
	local service = services[ctx.runtime]
	if not service then
		service = { entries = {}, carriers = {} }
		services[ctx.runtime] = service
	end
	local owner = assert(ctx.Compose.currentOwner())
	local shared = service
	local state = ctx.Compose.createSpringState(options.initial, #options.initial)
	local reference = table.clone(options.initial)
	local elapsed = 0
	local depth = 1
	while true do
		local occupied = false
		for _, leased in shared.entries do
			occupied = occupied or leased.depth == depth
		end
		if not occupied then
			break
		end
		depth += 1
	end
	local entry: Entry = { active = true, tick = function() end, depth = depth }
	local stopped = false
	local hadParent = options.carrier ~= nil and options.carrier.Parent ~= nil
	local stop: () -> ()
	local function alive(): boolean
		return not stopped
			and not owner.isDisposed()
			and not (hadParent and options.carrier and options.carrier.Parent == nil)
	end
	local waiting = 0
	local started = true
	local function start()
		if alive() and not started then
			started = true
			if options.start then
				options.start()
			end
		end
	end
	local function finish(target: { number })
		if not alive() then
			return
		end
		for index, value in target do
			state.position[index], state.velocity[index] = value, 0
		end
		entry.active = false
		options.sample(state.position)
		if alive() and options.complete then
			options.complete()
		end
	end
	entry.tick = function(delta: number)
		if options.carrier and options.carrier.Parent ~= nil then
			hadParent = true
		end
		if not alive() then
			stop()
			return
		end
		if not entry.active then
			return
		end
		local target = options.target()
		if not alive() then
			return
		end
		if options.reduced() then
			start()
			finish(target)
			return
		end
		if waiting > 0 then
			local consumed = math.min(waiting, delta)
			waiting -= consumed
			delta -= consumed
			if waiting > 0 then
				return
			end
		end
		start()
		if not alive() then
			return
		end
		if options.motion == "spring" then
			ctx.Compose.stepSpring(state, target, delta, options.spring.period, options.spring.damping)
			options.sample(state.position)
			if ctx.Compose.springAtRest(state, target, reference, 0.001) then
				finish(target)
			end
		else
			elapsed += delta
			local fraction = if options.duration <= 0 then 1 else math.min(1, elapsed / options.duration)
			local eased = options.ease(fraction)
			for index, value in target do
				state.position[index] = reference[index] + (value - reference[index]) * eased
			end
			options.sample(state.position)
			if fraction >= 1 then
				finish(target)
			end
		end
	end
	if options.carrier then
		assert(shared.carriers[options.carrier] == nil, "Facet travel carrier is already leased")
		shared.carriers[options.carrier] = entry
	end
	table.insert(shared.entries, entry)
	if not shared.disconnect then
		local frames = assert(ctx.runtime.host.frames, "Facet travel requires a Compose frame clock")
		shared.disconnect = frames.onFrame(function(delta: number)
			for _, current in table.clone(shared.entries) do
				current.tick(delta)
			end
		end)
	end
	stop = function()
		if stopped then
			return
		end
		stopped = true
		entry.active = false
		if options.carrier then
			shared.carriers[options.carrier] = nil
		end
		local index = table.find(shared.entries, entry)
		if index then
			table.remove(shared.entries, index)
		end
		if #shared.entries == 0 and shared.disconnect then
			shared.disconnect()
			shared.disconnect = nil
		end
	end
	if options.carrier then
		ctx.runtime.connect(options.carrier, "Destroying", stop)
	end
	ctx.Compose.cleanup(stop)
	return {
		depth = depth,
		rebase = function(values: { number })
			if not alive() then
				return
			end
			for index, value in values do
				state.position[index] = value
			end
		end,
		snap = function(values: { number })
			if not alive() then
				return
			end
			for index, value in values do
				state.position[index], state.velocity[index] = value, 0
			end
			reference = table.clone(values)
			entry.active = false
			options.sample(state.position)
			if options.carrier and options.carrier.Parent ~= nil then
				hadParent = true
			end
		end,
		retarget = function()
			if not alive() then
				return
			end
			local interrupted = entry.active and started
			reference = table.clone(state.position)
			waiting = if interrupted or options.delay == nil then 0 else options.delay()
			assert(waiting >= 0 and waiting < math.huge, "Facet travel delay must be finite and nonnegative")
			elapsed, entry.active, started = 0, true, false
			if waiting == 0 or options.reduced() then
				start()
			end
			if options.reduced() or (options.motion == "ease" and options.duration <= 0 and waiting == 0) then
				finish(options.target())
			end
		end,
		stop = stop,
		velocity = function()
			return table.clone(state.velocity)
		end,
	}
end
