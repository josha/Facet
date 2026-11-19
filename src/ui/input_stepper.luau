--!strict
local valueModel = require("./input_value")
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ControlTypes = require("./control_types")
local ComposeTypes = require("../vendor/compose/core")
local layoutKit = require("./layout_kit")
local themeSupport = require("./theme_support")
local ThemeTypes = require("./theme_types")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local Host, read, Compose = ctx.Host, ctx.read, ctx.Compose
	local readValue = read<<number>>
	local D, D2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Enum
	local lists, enabled = kit.lists, kit.enabled
	local changed = kit.changed
	UI.Stepper = ctx.construct("Stepper", function(spec: InputTypes.StepperImplementationProps): Frame
		kit.requireValue(spec, "number", "Stepper")
		local model = valueModel({ min = spec.min, max = spec.max, step = spec.step or 1, format = spec.format }, read)
		local atLimit = Compose.selector(Compose.formula(function(use: ComposeTypes.Use): number
			local value = readValue(spec.value, use)
			return if value ~= value then 2 elseif value <= model.min then -1 elseif value >= model.max then 1 else 0
		end))
		local function adjust(direction)
			if enabled(spec) then
				changed(spec, model.stepped(readValue(spec.value), direction))
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
		local readout = ctx.text({
			Name = "Value",
			LayoutOrder = 2,
			Size = D2.fromOffset(40, 44),
			AutomaticSize = E.AutomaticSize.X,
			TextXAlignment = E.TextXAlignment.Center,
			TextYAlignment = E.TextYAlignment.Center,
			Text = "",
		})
		local controls = ctx.styled(
			Host.Frame "Controls" {
				LayoutOrder = 2,
				Size = D2.fromOffset(0, 44),
				AutomaticSize = E.AutomaticSize.X,
				lists.list({ align = "center" }, false),
				lists.insets(controlInsets),
				stepButton("Decrease", "decrement", -1, function(use: ComposeTypes.Use)
					return enabled(spec, use) and (use(atLimit(0)) or use(atLimit(1)))
				end),
				readout,
				stepButton("Increase", "increment", 1, function(use: ComposeTypes.Use)
					return enabled(spec, use) and (use(atLimit(0)) or use(atLimit(-1)))
				end),
			},
			"stepper-track"
		)
		local inset = Host.UIPadding {}
		local parts: { ComposeTypes.Child } = {
			lists.list({ gap = 12, align = "center" }, false),
			inset,
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
					AutomaticSize = E.AutomaticSize.Y,
					TextXAlignment = E.TextXAlignment.Left,
					Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill },
					ctx.styled(Host.UIPadding {}, "stepper-inset"),
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
		local function sized(height: number): UDim2
			return if spec.label then D2.new(1, 0, 0, height) else D2.fromOffset(0, height)
		end
		local content = Host.Frame "Content" {
			ZIndex = 1,
			BackgroundTransparency = 1,
			Size = sized(44),
			AutomaticSize = if spec.label then E.AutomaticSize.None else E.AutomaticSize.X,
			table.unpack(parts),
		}
		p[#p + 1] = content
		local theme = ctx.config.theme
		local function lifted(use: ComposeTypes.Use?): boolean
			return themeSupport.plateReach(read<<ThemeTypes.ReadOnlyThemePackage?>>(theme, use)) > 0
		end
		if Compose.isValue(theme) or type(theme) == "function" or lifted() then
			local owner = Compose.currentOwner()
			local room: ComposeTypes.Value<layoutKit.Room>? = nil
			Compose.watch(function(use: ComposeTypes.Use)
				local held = room
				if held == nil then
					if owner == nil or not lifted(use) then
						return
					end
					local made: ComposeTypes.Value<layoutKit.Room> =
						Compose.cell({ top = 0, right = 0, bottom = 0, left = 0 })
					Compose.withOwner(owner, function()
						lists.shadowRoom(controls, made, true)
					end)
					room = made
					held = made
				end
				local reach: layoutKit.Room = use(assert(held))
				inset.PaddingTop = D.new(0, reach.top)
				inset.PaddingRight = D.new(0, reach.right)
				inset.PaddingBottom = D.new(0, reach.bottom)
				inset.PaddingLeft = D.new(0, reach.left)
				content.Size = sized(44 + reach.top + reach.bottom)
			end)
		end
		local node = ctx.styled(Host.Frame(p), "stepper")
		ctx.skin(node, "stepperPlate")
		kit.valueAttributes(node, spec.value, model, readout)
		if spec.label ~= nil then
			kit.attributes(node, {
				AccessibleLabel = function(use: ComposeTypes.Use): string
					return read<<string?>>(spec.label, use) or ""
				end,
			})
		end
		kit.adjustment(node, spec, adjust, nil, model.min, model.max)
		return node
	end)
end
