--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local reducedMotion = require("./motion").reduced

export type Spring = { period: number, damping: number }
export type Settle = {
	value: ComposeTypes.Readable<number?>,
	launch: (from: number, velocity: number, spring: Spring?) -> boolean,
	halt: () -> (),
}

return function(ctx: Types.Context, target: () -> number, spring: Spring, reduced: (() -> boolean)?): Settle
	local Compose = ctx.Compose
	local frames = ctx.runtime.host.frames
	local fallback = reducedMotion(ctx)
	local reduce: () -> boolean = reduced or function(): boolean
		return fallback()
	end
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
	local function launch(from: number, velocity: number, override: Spring?): boolean
		halt()
		local chosen = override or spring
		local crossing = chosen.damping >= 1
		if disposed or frames == nil or reduce() then
			return false
		end
		local limit = ctx.metric("motion.fling.maxSpeed")
		local state = Compose.createSpringState({ from }, 1)
		state.velocity[1] = math.clamp(velocity, -limit, limit)
		value:set(from)
		local mine: (() -> ())? = nil
		mine = frames.onFrame(function(delta: number)
			if stop ~= mine then
				return
			end
			local goal = target()
			local before = state.position[1]
			Compose.stepSpring(state, { goal }, delta, chosen.period, chosen.damping)
			local now = state.position[1]
			if
				now ~= now
				or math.abs(now) == math.huge
				or (crossing and (now - goal) * (before - goal) < 0)
				or (math.abs(now - goal) < 0.5 and math.abs(state.velocity[1]) < 5)
			then
				halt()
				return
			end
			value:set(now)
		end)
		stop = mine
		return true
	end
	Compose.cleanup(function()
		disposed = true
		halt()
	end)
	return { value = value, launch = launch, halt = halt }
end
