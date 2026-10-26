--!strict

local Compose = require("../vendor/compose/core")
local Design = require("../vendor/compose/design/types")
local ControlTypes = require("../ui/control_types")
local EffectTypes = require("../ui/effect_types")
local Types = require("./types")

type Literal = Design.Literal

local ROLES = { "control", "flick", "move", "quick", "sheet", "snappy", "travel" }

local function motion(UI: ControlTypes.Controls): Types.Motion
	return {
		animate = function(source: Compose.ReadOnlyValue<Literal?>, role: string): Compose.ReadOnlyValue<Literal?>
			return UI.follow(source, role)
		end,
		sequence = function(
			sequence: Design.Sequence,
			states: { [string]: Compose.Value<Literal?> },
			outputs: { [string]: () -> () }
		): Design.Player
			local steps: { EffectTypes.SequenceStep } = {}
			for _, step in sequence.steps do
				local compiled: EffectTypes.SequenceStep =
					{ delay = step.delay, duration = step.duration, easing = step.easing }
				local target, to = step.state, step.to
				local held = if target ~= nil then states[target] else nil
				if held ~= nil and to ~= nil then
					if type(to) == "number" then
						local from: number? = nil
						compiled.sample = function(progress: number)
							local current = held:peek()
							local origin = if progress > 0 and from ~= nil
								then from
								elseif type(current) == "number" then current
								else to
							from = if progress >= 1 then nil else origin
							held:set(origin + (to - origin) * progress)
						end
					else
						compiled.onStart = function()
							held:set(to)
						end
					end
				end
				local output = step.output
				if output ~= nil then
					compiled.onEnd = outputs[output]
				end
				table.insert(steps, compiled)
			end
			return UI.sequence { steps = steps }
		end,
	}
end

return { roles = ROLES, motion = motion }
