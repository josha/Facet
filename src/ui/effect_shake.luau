--!strict
local Shared = require("./types")
local Types = require("./effect_types")
local reducedMotion = require("./motion").reduced

return function(ctx: Shared.Context, UI: Types.Controls)
	function UI.shake(targets: Shared.Value<{ GuiObject }>, options: Types.ShakeOptions?): Types.Sequence
		local intensity = if options and options.intensity ~= nil then options.intensity else 1
		assert(intensity >= 0 and intensity < math.huge, "Facet shake intensity must be finite and nonnegative")
		local originals: { [GuiObject]: number } = {}
		local connections: { RBXScriptConnection } = {}
		local alive = true
		local reduce = reducedMotion(ctx)
		local angle, cycles = 0, 0
		local function restore()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			for target, rotation in originals do
				pcall(function()
					target.Rotation = rotation
				end)
			end
			table.clear(originals)
		end
		local sequence = UI.sequence {
			steps = {
				{
					duration = "shake",
					easing = "shake",
					sample = function(progress: number)
						if reduce() then
							return
						end
						local phase = math.clamp(progress, 0, 1)
						local offset = if phase == 0 or phase == 1
							then 0
							else math.sin(phase * 2 * math.pi * cycles) * (1 - phase) * angle
						for target, rotation in originals do
							target.Rotation = rotation + offset
						end
					end,
					onEnd = restore,
				},
			},
		}
		local function cancel()
			sequence.cancel()
			restore()
		end
		ctx.Compose.watch(function(use: Shared.Use)
			ctx.read(targets, use)
			if next(originals) ~= nil then
				cancel()
			end
		end)
		ctx.Compose.cleanup(function()
			alive = false
			cancel()
		end)
		return {
			running = sequence.running,
			completed = sequence.completed,
			cancel = cancel,
			finish = sequence.finish,
			play = function()
				if not alive then
					return
				end
				cancel()
				local current = ctx.read(targets)
				for _, target in current do
					assert(target:IsA("GuiObject"), "Facet shake requires GuiObject targets")
				end
				angle = ctx.metric("motion.distances.shakeAngle") * intensity
				assert(angle < math.huge, "Facet shake angle must be finite")
				cycles = ctx.metric("motion.materialize.shakeCycles")
				if not reduce() then
					for _, target in current do
						if originals[target] == nil then
							originals[target] = target.Rotation
							table.insert(connections, target.Destroying:Connect(cancel))
						end
					end
				end
				sequence.play()
			end,
		}
	end
end
