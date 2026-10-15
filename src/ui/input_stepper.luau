--!strict
local valueModel = require("./input_value")
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local Host, read = ctx.Host, ctx.read
	local D2, E = ctx.types.UDim2, ctx.types.Enum
	local lists, enabled = kit.lists, kit.enabled
	local changed = kit.changed
	UI.Stepper = ctx.construct("Stepper", function(spec: InputTypes.StepperImplementationProps): Frame
		kit.requireValue(spec, "number", "Stepper")
		local modelSpec = table.clone(spec) :: valueModel.Options
		modelSpec.step = spec.step or 1
		local model = valueModel(modelSpec, read)
		local function adjust(direction)
			if enabled(spec) then
				changed(spec, model.stepped(read(spec.value), direction))
			end
		end

		local function stepButton(
			name: string,
			glyph: string,
			direction: number,
			allowed: (ComposeTypes.Use) -> boolean
		)
			local button = UI.Button(name)({
				icon = glyph,
				name = name,
				haptic = true,
				repeatDelay = spec.repeatDelay or kit.repeatDelay,
				repeatInterval = spec.repeatInterval or kit.repeatInterval,
				LayoutOrder = if direction < 0 then 1 else 3,
				Size = D2.fromOffset(44, 44),
				AutomaticSize = E.AutomaticSize.None,
				Selectable = false,
				enabled = allowed,
				onActivate = function()
					adjust(direction)
				end,
			})
			button:AddTag("facet-stepper-button")
			return button
		end
		local controlInsets: Shared.Sides = { left = 2, right = 2 }
		local controls = ctx.styled(
			Host.Frame "Controls" {
				LayoutOrder = 2,
				Size = D2.fromOffset(0, 44),
				AutomaticSize = E.AutomaticSize.X,
				lists.list({ align = "center" }, false) :: ComposeTypes.Child,
				lists.insets(controlInsets) :: ComposeTypes.Child,
				stepButton("Decrease", "decrement", -1, function(use: ComposeTypes.Use)
					return enabled(spec, use) and read(spec.value, use) > model.min
				end),
				ctx.text({
					Name = "Value",
					LayoutOrder = 2,
					Size = D2.fromOffset(40, 44),
					AutomaticSize = E.AutomaticSize.X,
					TextXAlignment = E.TextXAlignment.Center,
					TextYAlignment = E.TextYAlignment.Center,
					Text = function(use: ComposeTypes.Use)
						return model.format(read(spec.value, use))
					end,
				}),
				stepButton("Increase", "increment", 1, function(use: ComposeTypes.Use)
					return enabled(spec, use) and read(spec.value, use) < model.max
				end),
			},
			"stepper-track"
		)
		local parts: { ComposeTypes.Child } = {
			lists.list({ gap = 12, align = "center" }, false),
			controls,
		}
		if spec.label then
			table.insert(
				parts,
				ctx.text({
					Name = "Label",
					LayoutOrder = 1,
					Text = spec.label,
					Size = D2.fromScale(0, 0),
					AutomaticSize = E.AutomaticSize.XY,
					TextXAlignment = E.TextXAlignment.Left,
					Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: ComposeTypes.Child,
					ctx.styled(Host.UIPadding({}), "stepper-inset") :: ComposeTypes.Child,
				})
			)
		end
		local p = ctx.props(spec, {
			"value",
			"min",
			"max",
			"step",
			"format",
			"enabled",
			"onChange",
			"label",
			"repeatDelay",
			"repeatInterval",
		}, {
			Selectable = function(use: ComposeTypes.Use): boolean
				return kit.stopEnabled(spec, use)
			end,
			Size = if spec.label then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
			AutomaticSize = if spec.label then E.AutomaticSize.Y else E.AutomaticSize.XY,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
		table.insert(
			p,
			Host.Frame "Content" {
				ZIndex = 1,
				BackgroundTransparency = 1,
				Size = if spec.label then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44),
				AutomaticSize = if spec.label then E.AutomaticSize.None else E.AutomaticSize.X,
				table.unpack(parts),
			}
		)
		local node = ctx.styled(Host.Frame(p), "stepper")
		ctx.skin(node, "stepperPlate")
		kit.valueAttributes(node, spec, model)
		if spec.label ~= nil then
			kit.attributes(node, {
				AccessibleLabel = function(use: ComposeTypes.Use): string
					return read(spec.label, use) or ""
				end,
			})
		end
		kit.adjustment(node, spec, adjust, nil, model.min, model.max)
		return node
	end)
end
