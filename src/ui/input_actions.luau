--!strict
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime = ctx.runtime
	local stopEnabled, adjustment = kit.stopEnabled, kit.adjustment

	UI.feedback = function(kind: Shared.HapticKind)
		assert(type(kind) == "string", "Facet UI.feedback expects a feedback kind")
		local effect = ctx.haptic(kind) :: HapticEffect
		effect:Play()
	end

	UI.adjustable = function(node: GuiObject, options: InputTypes.AdjustableOptions)
		assert(
			type(options) == "table" and type(options.onAdjust) == "function",
			"Facet UI.adjustable requires onAdjust"
		)
		local axis = options.axis or "horizontal"
		assert(
			axis == "horizontal" or axis == "vertical" or axis == "none",
			`Facet UI.adjustable: axis '{tostring(axis)}' is not horizontal, vertical or none`
		)
		local canAdjust = options.canAdjust
		local bound = if axis == "none" then nil else math.huge
		runtime.decorate(node, {
			Selectable = function(use: ComposeTypes.Use): boolean
				return stopEnabled(options, use)
			end,
		})
		adjustment(node, options, options.onAdjust, nil, if bound then -bound else nil, bound, {
			vertical = axis == "vertical",
			once = options.repeats ~= true,
			arrows = function(use: ComposeTypes.Use, direction: number): boolean
				return canAdjust == nil or canAdjust(direction, use)
			end,
		})
	end
end
