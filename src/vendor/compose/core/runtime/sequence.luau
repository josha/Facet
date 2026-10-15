--!strict

local Active = require "../ownership/active"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Cell = require "../reactive/cell"
local Timeline = require "../animation/timeline"
local Easing = require "../animation/easing"
local Motion = require "../animation/motion"
local Support = require "../structure/support"
local Watch = require "../reactive/watch"

export type Step = {
	wait: number?,
	run: (() -> ())?,
	onComplete: (() -> ())?,
	tween: { seconds: number, ease: Easing.Easing? }?,
	timeline: Timeline.Options?,
	sample: ((number) -> ())?,
	parallel: { Step }?,
	steps: { Step }?,
}
export type Options = { steps: { Step }, reducedMotion: Motion.ReducedMotion?, autoplay: boolean? }
export type Sequence = {
	completed: Types.Readable<boolean>,
	running: Types.Readable<boolean>,
	play: () -> (),
	cancel: () -> (),
	finish: () -> (),
}
type Phase = { start: number, finish: number, step: Step, clock: Timeline.Timeline?, ended: boolean, started: boolean }
type Event = { at: number, order: number, phase: Phase, start: boolean }

return function(timeline: (Timeline.Options?) -> Timeline.Timeline, ownerOf: (string) -> Owner.Owner)
	return function(options: Options): Sequence
		local parent = ownerOf "sequence"
		local scope = parent.createChild()
		local function build(): Sequence
			local phases: { Phase } = {}
			local events: { Event } = {}
			local function event(phase: Phase, at: number, start: boolean)
				table.insert(events, { at = at, order = #events + 1, phase = phase, start = start })
			end
			local compile: (Step, number) -> number
			compile = function(step: Step, start: number): number
				local seconds = step.wait or 0
				local clock: Timeline.Timeline? = nil
				if step.tween and step.tween.seconds == 0 then
					seconds = 0
				elseif step.timeline or step.tween then
					local settings: Timeline.Options = if step.timeline
						then table.clone(step.timeline)
						else { duration = assert(step.tween).seconds }
					settings.autoplay = false
					clock = timeline(settings)
					seconds = ((settings.delay or 0) + (settings.duration or 1) * (settings.repeats or 1))
						/ (settings.scale or 1)
				end
				assert(seconds >= 0 and seconds < math.huge, "Compose sequence steps need finite nonnegative timing")
				local phase: Phase = {
					start = start,
					finish = start + seconds,
					step = step,
					clock = clock,
					ended = false,
					started = false,
				}
				table.insert(phases, phase)
				event(phase, start, true)
				for _, child in (step.steps or {}) :: { Step } do
					phase.finish = compile(child, phase.finish)
				end
				local children: { Step } = step.parallel or {}
				for _, child in children do
					phase.finish = math.max(phase.finish, compile(child, start))
				end
				event(phase, phase.finish, false)
				return phase.finish
			end
			local duration = 0
			for _, step in options.steps do
				duration = compile(step, duration)
			end
			table.sort(events, function(a: Event, b: Event): boolean
				return if a.at == b.at then a.order < b.order else a.at < b.at
			end)
			local clock = timeline { duration = math.max(duration, 1e-9), autoplay = false }
			local running, completed = Cell.cell(false), Cell.cell(false)
			local generation = 0
			local cursor = 1
			local function cancel()
				generation += 1
				clock:pause()
				running:set(false)
				completed:set(false)
			end
			scope.own(cancel)
			local policy = if options.reducedMotion
				then Support.sourceOf(options.reducedMotion, "sequence", "reducedMotion")
				else nil
			local function invoke(body: () -> ())
				local ok, failure: unknown = pcall(function(): nil
					Active.withOwner(scope, body)
					return nil
				end)
				if not ok then
					cancel()
					error(failure, 0)
				end
			end
			local function sample(phase: Phase, elapsed: number)
				local body = phase.step.sample
				if body == nil or (phase.clock == nil and phase.step.tween == nil) then
					return
				end
				local progress = 1
				if phase.clock then
					local settings = phase.step.timeline
					phase.clock:seek(
						math.max(
							0,
							(elapsed - phase.start) * (settings and settings.scale or 1)
								- (settings and settings.delay or 0)
						)
					)
					progress = phase.clock.progress:peek()
				end
				local tween = phase.step.tween
				invoke(function()
					body(if phase.clock and tween and tween.ease then tween.ease(progress) else progress)
				end)
			end
			local function advance(elapsed: number)
				if not running:peek() or scope.isDisposed() then
					return
				end
				local mine = generation
				while cursor <= #events and events[cursor].at <= elapsed do
					local nextEvent = events[cursor]
					cursor += 1
					local phase = nextEvent.phase
					if nextEvent.start then
						phase.started = true
						if phase.step.run then
							invoke(phase.step.run)
						end
					else
						sample(phase, phase.finish)
						if mine ~= generation or scope.isDisposed() then
							return
						end
						phase.ended = true
						if phase.step.onComplete then
							invoke(phase.step.onComplete)
						end
					end
					if mine ~= generation or scope.isDisposed() then
						return
					end
				end
				for _, phase in phases do
					if phase.started and not phase.ended then
						sample(phase, elapsed)
						if mine ~= generation or scope.isDisposed() then
							return
						end
					end
				end
				if elapsed >= duration then
					clock:pause()
					running:set(false)
					completed:set(true)
				end
			end
			local function finish()
				advance(duration)
			end
			scope.watch(function(use)
				local elapsed = use(clock.elapsed)
				local reduced = policy ~= nil and policy(use) == true
				advance(if reduced then duration else elapsed)
			end)
			local function play()
				if scope.isDisposed() then
					return
				end
				scope.reactor:batch(function()
					cancel()
					cursor = 1
					for _, phase in phases do
						phase.ended, phase.started = false, false
					end
					clock:seek(0)
					running:set(true)
					local reduced = policy ~= nil
						and Watch.sample(function(): unknown
								return assert(policy)(function<T>(value: Types.Readable<T>): T
									return value:peek()
								end)
							end)
							== true
					advance(if reduced then duration else 0)
					if running:peek() then
						clock:play()
					end
				end)
			end
			if options.autoplay ~= false then
				play()
			end
			return { running = running, completed = completed, play = play, cancel = cancel, finish = finish }
		end
		local ok, result = pcall(Active.withOwner, scope, build)
		if not ok then
			scope.dispose()
			error(result, 0)
		end
		return result
	end
end
