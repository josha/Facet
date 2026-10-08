--!strict
local Shared = require("./types")

export type Options = {
	initial: { number },
	carrier: GuiObject?,
	target: () -> { number },
	sample: ({ number }) -> (),
	complete: (() -> ())?,
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
}
type Entry = { tick: (number) -> (), active: boolean }
type Service = { entries: { Entry }, carriers: { [GuiObject]: Entry }, disconnect: (() -> ())? }
local services = setmetatable({} :: { [Shared.Runtime]: Service }, { __mode = "k" })

return function(ctx: Shared.Context, options: Options): Handle
	local service = services[ctx.runtime]
	if not service then
		service = { entries = {}, carriers = {} }
		services[ctx.runtime] = service
	end
	local shared = service
	local state = ctx.Compose.createSpringState(options.initial, #options.initial)
	local reference = table.clone(options.initial)
	local elapsed = 0
	local entry: Entry = { active = true, tick = function() end }
	local function finish(target: { number })
		for index, value in target do
			state.position[index], state.velocity[index] = value, 0
		end
		entry.active = false
		options.sample(state.position)
		if options.complete then
			options.complete()
		end
	end
	entry.tick = function(delta: number)
		if not entry.active then
			return
		end
		local target = options.target()
		if options.reduced() then
			finish(target)
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
	local stopped = false
	local function stop()
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
	ctx.Compose.cleanup(stop)
	return {
		rebase = function(values: { number })
			for index, value in values do
				state.position[index] = value
			end
		end,
		snap = function(values: { number })
			for index, value in values do
				state.position[index], state.velocity[index] = value, 0
			end
			reference = table.clone(values)
			entry.active = false
			options.sample(state.position)
		end,
		retarget = function()
			reference = table.clone(state.position)
			elapsed, entry.active = 0, true
			if options.reduced() or (options.motion == "ease" and options.duration <= 0) then
				finish(options.target())
			end
		end,
		stop = stop,
		velocity = function()
			return table.clone(state.velocity)
		end,
	}
end
