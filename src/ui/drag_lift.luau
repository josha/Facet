--!strict
local Types = require("./types")
local motion = require("./motion")
local feedbackPaint = require("./feedback_paint")

return function(ctx: Types.Context, source: GuiObject, magnitude: number)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local held = Compose.cell(false)
	local value = runtime.tween(function(use)
		return if use(held) then magnitude else 1
	end, {
		seconds = function(use)
			return ctx.metric("motion.durations.pressLift", use)
		end,
		ease = ctx.motionEase("present"),
		reducedMotion = motion.reduced(ctx),
	})
	local scaler = Host.UIScale { Name = "PressLift", Scale = value }
	local paint = feedbackPaint(ctx, source, scaler, {})
	return {
		value = value,
		visual = paint,
		press = function()
			held:set(true)
		end,
		release = function()
			held:set(false)
		end,
	}
end
