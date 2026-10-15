--!strict
local textField = require("./text_field")
local inputKit = require("./input_kit")
local inputButton = require("./input_button")
local inputToggle = require("./input_toggle")
local inputStepper = require("./input_stepper")
local inputLevel = require("./input_level")
local inputChip = require("./input_chip")
local inputShortcutHint = require("./input_shortcut_hint")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls): ()
	local kit = inputKit(ctx)
	local runtime = ctx.runtime
	local stopEnabled, adjustment = kit.stopEnabled, kit.adjustment
	inputButton(ctx, UI, kit)
	inputToggle(ctx, UI, kit)
	textField(ctx, UI)
	inputStepper(ctx, UI, kit)

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

	require("./slider")(ctx, UI, {
		enabled = kit.enabled,
		stopEnabled = stopEnabled,
		writable = kit.writable,
		attributes = kit.attributes,
		valueAttributes = kit.valueAttributes,
		adjustment = adjustment,
		paintedPart = kit.paintedPart,
	})

	inputLevel(ctx, UI, kit)
	inputChip(ctx, UI, kit)
	inputShortcutHint(ctx, UI, kit)
end
