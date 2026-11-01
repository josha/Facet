--!strict
local Shared = require("./types")
local Controls = require("./control_types")
local Props = require("./hud_props")
local MediaProps = require("./media_props")
local format = require("./format")

return function(ctx: Shared.Context, UI: Controls.Controls)
	local C, runtime = ctx.Compose, ctx.runtime
	local readTime = ctx.read<<number?>>
	UI.Timer = ctx.construct("Timer", function(spec: Props.TimerProps): TextLabel
		assert((spec.deadline ~= nil) ~= (spec.start ~= nil), "Facet Timer requires either deadline or start")
		local frames = assert(runtime.host.frames, "Facet Timer requires a runtime clock")
		local now = spec.now or frames.now
		local completed, text = C.cell(false), C.cell("")
		local textProps: MediaProps.TextProps = { text = text, textRole = spec.textRole }
		local fields =
			ctx.props(spec, { "deadline", "start", "now", "hours", "textRole", "onComplete", "controls" }, textProps)
		local label = UI.Text(ctx.props(textProps, { "text", "textRole" }, fields))
		assert(label:IsA("TextLabel"))
		if spec.controls then
			spec.controls.completed = completed
			C.cleanup(function()
				if spec.controls then
					spec.controls.completed = nil
				end
			end)
		end
		C.watch(function(use: Shared.Use)
			local target = readTime(spec.deadline or spec.start, use)
			assert(
				target ~= nil and target == target and math.abs(target) < math.huge,
				"Facet Timer requires a finite time"
			)
			completed:set(false)
			local clock = runtime.clock(
				if spec.now
					then {}
					elseif spec.deadline ~= nil then { deadline = target, step = 1 }
					else { start = target, step = 1 }
			)
			local shownSeconds: number? = nil
			local shownHours: boolean? = nil
			C.watch(function(read: Shared.Use)
				if read(completed) then
					return
				end
				local elapsed = read(clock)
				local at = if spec.now then now() else nil
				assert(at == nil or (at == at and math.abs(at) < math.huge), "Facet Timer clock must be finite")
				local delta = if at ~= nil then (if spec.deadline ~= nil then target - at else at - target) else elapsed
				local seconds = math.max(0, if spec.deadline ~= nil then math.ceil(delta) else math.floor(delta))
				local hours = spec.hours
				if seconds ~= shownSeconds or hours ~= shownHours then
					text:set(format.duration(seconds, { hours = hours }))
					shownSeconds = seconds
					shownHours = hours
				end
				if spec.deadline ~= nil and delta <= 0 then
					completed:set(true)
					if spec.onComplete then
						spec.onComplete()
					end
				end
			end)
		end)
		return label
	end)
end
