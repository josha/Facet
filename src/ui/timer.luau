--!strict
local Shared = require("./types")
local Controls = require("./control_types")
local Props = require("./hud_props")
local MediaProps = require("./media_props")
local format = require("./format")

return function(ctx: Shared.Context, UI: Controls.Controls)
	local C, runtime = ctx.Compose, ctx.runtime
	UI.Timer = ctx.construct("Timer", function(spec: Props.TimerProps): TextLabel
		assert((spec.deadline ~= nil) ~= (spec.start ~= nil), "Facet Timer requires either deadline or start")
		local frames = assert(runtime.host.frames, "Facet Timer requires a runtime clock")
		local now = spec.now or frames.now
		local completed, text = C.cell(false), C.cell("")
		local fields = (
			ctx.props(spec, { "deadline", "start", "now", "hours", "textRole", "onComplete", "controls" }) :: unknown
		) :: { [string]: unknown }
		fields.textRole = spec.textRole
		fields.text = text
		local label = UI.Text((fields :: unknown) :: MediaProps.TextProps) :: TextLabel
		if spec.controls then
			spec.controls.completed = completed
			C.cleanup(function()
				if spec.controls then
					spec.controls.completed = nil
				end
			end)
		end
		C.watch(function(use: Shared.Use)
			local target = ctx.read(spec.deadline or spec.start, use)
			assert(
				target ~= nil and target == target and math.abs(target) < math.huge,
				"Facet Timer requires a finite time"
			)
			local scheduler = runtime.scheduler()
			local active = true
			C.cleanup(function()
				active = false
			end)
			completed:set(false)
			local tick: () -> ()
			tick = function()
				if not active then
					return
				end
				local at = now()
				assert(at == at and math.abs(at) < math.huge, "Facet Timer clock must be finite")
				local delta = if spec.deadline ~= nil then target - at else at - target
				local seconds = math.max(0, if spec.deadline ~= nil then math.ceil(delta) else math.floor(delta))
				text:set(format.duration(seconds, { hours = spec.hours }))
				if spec.deadline ~= nil and delta <= 0 then
					completed:set(true)
					if spec.onComplete then
						spec.onComplete()
					end
					return
				end
				local delay = if spec.deadline ~= nil then delta - seconds + 1 else seconds + 1 - delta
				scheduler.after(delay, tick)
			end
			tick()
		end)
		return label
	end)
end
