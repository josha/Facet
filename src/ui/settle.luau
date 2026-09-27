--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local reducedMotion = require("./motion")

export type Settle = {
	value: ComposeTypes.Readable<number?>,
	launch: (from: number, velocity: number) -> (),
	halt: () -> (),
}

return function(ctx: Types.Context, target: () -> number, spring: { period: number, damping: number }): Settle
	local Compose = ctx.Compose
	local frames = ctx.runtime.host.frames
	local reduce = reducedMotion(ctx)
	local value: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
	local stop: (() -> ())? = nil
	local disposed = false
	local function halt()
		local current = stop
		stop = nil
		if current then
			current()
		end
		value:set(nil)
	end
	local function launch(from: number, velocity: number)
		halt()
		if disposed or frames == nil or reduce() then
			return
		end
		local state = Compose.createSpringState({ from }, 1)
		state.velocity[1] = velocity
		value:set(from)
		stop = frames.onFrame(function(delta: number)
			local goal = target()
			local before = state.position[1]
			Compose.stepSpring(state, { goal }, delta, spring.period, spring.damping)
			local now = state.position[1]
			if
				(now - goal) * (before - goal) <= 0 or (math.abs(now - goal) < 0.5 and math.abs(state.velocity[1]) < 5)
			then
				halt()
				return
			end
			value:set(now)
		end)
	end
	Compose.cleanup(function()
		disposed = true
		halt()
	end)
	return { value = value, launch = launch, halt = halt }
end
