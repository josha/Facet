--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Types = require("./effect_types")
local Motion = require("./motion")
local reducedMotion = Motion.reduced

return function(ctx: Shared.Context, UI: Types.Controls)
	local runtime = ctx.runtime
	function UI.countUp(value: Shared.Input<number>): Shared.ReadOnlyValue<number>
		return runtime.tween(function(use: Shared.Use): number
			local number = ctx.read<<number>>(value, use)
			assert(number == number and math.abs(number) < math.huge, "Facet countUp requires a finite value")
			return number
		end, {
			seconds = ctx.metric("motion.durations.countUp"),
			ease = ctx.motionEase("countUp"),
			reducedMotion = reducedMotion(ctx),
		})
	end
	function UI.follow<T>(value: Shared.ReadOnlyValue<T> | (Shared.Use) -> T, role: string): Shared.ReadOnlyValue<T>
		local spring = ctx.motionSpring(role)
		local initial = ctx.read<<T>>(value)
		return Motion.forValue(ctx, initial).spring(function(use: Shared.Use): T
			return ctx.read<<T>>(value, use)
		end, {
			period = spring.period,
			damping = spring.damping,
			reducedMotion = reducedMotion(ctx),
		})
	end
	function UI.toward(value: Shared.Value<number>, target: number): (number) -> ()
		assert(target == target and math.abs(target) < math.huge, "Facet toward requires a finite target")
		local from: number? = nil
		return function(progress: number)
			local start = if progress <= 0 then nil else from
			local origin = start or value:peek()
			from = if progress >= 1 then nil else origin
			value:set(origin + (target - origin) * progress)
		end
	end
	function UI.sequence(spec: Types.SequenceSpec): Types.Sequence
		local function seconds(token: string?): number
			local value = if token then ctx.metric("motion.durations." .. token) else 0
			assert(value >= 0 and value < math.huge, "Facet sequence timing must be finite and nonnegative")
			return value
		end
		local compile: (Types.SequenceStep) -> (ComposeTypes.SequenceStep, number)
		compile = function(step: Types.SequenceStep): (ComposeTypes.SequenceStep, number)
			local duration = seconds(step.duration)
			local parallel: { ComposeTypes.SequenceStep } = {}
			local children: { Types.SequenceStep } = step.parallel or {}
			for _, child in children do
				local compiled, length = compile(child)
				table.insert(parallel, compiled)
				duration = math.max(duration, length)
			end
			local delay = seconds(step.delay)
			local serial: { ComposeTypes.SequenceStep } = {
				{ wait = delay },
				{
					run = step.onStart,
					onComplete = step.onEnd,
					tween = { seconds = duration, ease = ctx.motionEase(step.easing or "sequence") },
					sample = step.sample,
					parallel = parallel,
				},
			}
			return { steps = serial }, delay + duration
		end
		local steps: { ComposeTypes.SequenceStep } = {}
		for _, step in spec.steps do
			local compiled = compile(step)
			table.insert(steps, compiled)
		end
		local sequence = runtime.sequence { steps = steps, reducedMotion = reducedMotion(ctx), autoplay = false }
		if spec.onCompleted then
			local completed = ctx.Compose.bindOwner(spec.onCompleted)
			ctx.Compose.watch(function(use: Shared.Use)
				if use(sequence.completed) then
					completed()
				end
			end)
		end
		return sequence
	end
end
