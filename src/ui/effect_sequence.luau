--!strict
local Shared = require("./types")
local Types = require("./effect_types")
local reducedMotion = require("./motion").reduced

type Phase = {
	spec: Types.SequenceStep,
	start: number,
	finish: number,
	active: boolean,
	ended: boolean,
	ease: (number) -> number,
}
type Event = { time: number, order: number, phase: Phase, start: boolean }
return function(ctx: Shared.Context, UI: Types.Controls)
	local C, runtime = ctx.Compose, ctx.runtime
	function UI.countUp(value: Shared.Value<number>): Shared.Readable<number>
		local reduce = reducedMotion(ctx)
		return runtime.tween(function(use: Shared.Use): number
			local number = ctx.read(value, use)
			assert(number == number and math.abs(number) < math.huge, "Facet countUp requires a finite value")
			return number
		end, {
			seconds = ctx.metric("motion.durations.countUp"),
			ease = ctx.motionEase("countUp"),
			reducedMotion = reduce,
		})
	end
	function UI.sequence(spec: Types.SequenceSpec): Types.Sequence
		local reduce = reducedMotion(ctx)
		local owner = assert(C.currentOwner(), "Facet sequence requires a Compose owner")
		local phases: { Phase } = {}
		local events: { Event } = {}
		local function seconds(token: string?): number
			local value = if token then ctx.metric("motion.durations." .. token) else 0
			assert(value >= 0 and value < math.huge, "Facet sequence timing must be finite and nonnegative")
			return value
		end
		local function event(phase: Phase, time: number, start: boolean)
			table.insert(events, { phase = phase, time = time, start = start, order = #events + 1 })
		end
		local compile: (Types.SequenceStep, number) -> number
		compile = function(step: Types.SequenceStep, cursor: number): number
			local start = cursor + seconds(step.delay)
			local phase: Phase = {
				spec = step,
				start = start,
				finish = start + seconds(step.duration),
				active = false,
				ended = false,
				ease = ctx.motionEase(step.easing or "sequence"),
			}
			table.insert(phases, phase)
			event(phase, start, true)
			if step.parallel then
				for _, child in step.parallel do
					phase.finish = math.max(phase.finish, compile(child, start))
				end
			end
			event(phase, phase.finish, false)
			return phase.finish
		end
		local duration = 0
		for _, step in spec.steps do
			duration = compile(step, duration)
		end
		table.sort(events, function(a, b)
			return if a.time == b.time then a.order < b.order else a.time < b.time
		end)
		local clock = runtime.timeline {
			duration = if duration > 0 then duration else ctx.metric("motion.durations.sequence"),
			autoplay = false,
		}
		local running, completed = C.cell(false), C.cell(false)
		local cursor, generation = 1, 0
		local function invoke(callback: (() -> ())?)
			if callback then
				C.withOwner(owner, callback)
			end
		end
		local function sample(phase: Phase, value: number)
			if phase.spec.sample then
				C.withOwner(owner, function()
					assert(phase.spec.sample)(value)
				end)
			end
		end
		local function advance(elapsed: number)
			if not running:peek() or owner.isDisposed() then
				return
			end
			local run = generation
			while cursor <= #events and events[cursor].time <= elapsed do
				local next = events[cursor]
				cursor += 1
				local phase = next.phase
				if next.start then
					phase.active = true
					invoke(phase.spec.onStart)
				else
					sample(phase, 1)
					if run ~= generation then
						return
					end
					phase.active, phase.ended = false, true
					invoke(phase.spec.onEnd)
				end
				if run ~= generation then
					return
				end
			end
			for _, phase in phases do
				if phase.active and not phase.ended then
					local progress = if phase.finish == phase.start
						then 1
						else math.clamp((elapsed - phase.start) / (phase.finish - phase.start), 0, 1)
					sample(phase, phase.ease(progress))
					if run ~= generation then
						return
					end
				end
			end
			if cursor > #events then
				clock:pause()
				running:set(false)
				completed:set(true)
				invoke(spec.onCompleted)
			end
		end
		local function cancel()
			generation += 1
			clock:pause()
			running:set(false)
			completed:set(false)
		end
		local function play()
			if owner.isDisposed() then
				return
			end
			runtime.reactor:batch(function()
				cancel()
				cursor = 1
				for _, phase in phases do
					phase.active, phase.ended = false, false
				end
				clock:seek(0)
				running:set(true)
				if reduce() or duration == 0 then
					advance(duration)
				else
					clock:play()
					advance(0)
				end
			end)
		end
		C.watch(function(use: Shared.Use)
			local elapsed, active = use(clock.elapsed), use(running)
			local collapsed = reduce(use)
			if active then
				advance(if collapsed then duration else elapsed)
			end
		end)
		C.cleanup(cancel)
		return {
			play = play,
			cancel = cancel,
			finish = function()
				advance(duration)
			end,
			running = running,
			completed = completed,
		}
	end
end
