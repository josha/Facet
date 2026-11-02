--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local motion = require("./motion")
local feedbackPaint = require("./feedback_paint")
export type Lift = {
	value: ComposeTypes.ReadOnlyValue<number>,
	visual: GuiObject,
	press: () -> (),
	release: () -> (),
	carry: () -> (),
}

return function(ctx: Types.Context, source: GuiObject, magnitude: Types.Input<number>): Lift
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local held = Compose.cell(false)
	local carried = Compose.cell(false)
	local readMagnitude = ctx.read<<number>>
	local value = runtime.tween(function(use: ComposeTypes.Use): number
		return if use(held) then readMagnitude(magnitude, use) else 1
	end, {
		seconds = function(use)
			return ctx.metric("motion.durations.pressLift", use)
		end,
		ease = ctx.motionEase("present"),
		reducedMotion = motion.reduced(ctx),
	})
	local scaler = Host.UIScale {
		Name = "PressLift",
		Scale = function(use: ComposeTypes.Use): number
			return if use(carried) then 1 else use(value)
		end,
	}
	local paint = feedbackPaint(ctx, source, scaler, {})
	return {
		value = value,
		visual = paint,
		press = function()
			carried:set(false)
			held:set(true)
		end,
		release = function()
			held:set(false)
		end,
		carry = function()
			carried:set(true)
		end,
	}
end
