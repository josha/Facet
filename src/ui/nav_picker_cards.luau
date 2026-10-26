--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local NavigationProps = require("./navigation_props")
local PickerParts = require("./nav_picker_parts")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, shared: PickerParts.Parts)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local pickerKeys = shared.keys
	local function cardsStyle<V>(spec: NavigationProps.PickerSpec<V>, choice: PickerParts.Choice<V>): GuiObject
		local isSelected, select, options = choice.isSelected, choice.select, choice.options
		local across = read(spec.axis) == "x"
		local function clear()
			if read(spec.enabled) == false or spec.multiple then
				return
			end
			local single = (spec :: unknown) :: NavigationProps.SinglePickerSpec<V>
			local previous = single.selected:peek()
			if single.onChanging and single.onChanging((nil :: unknown) :: V, previous) == false then
				return
			end
			local optional = (single.selected :: unknown) :: ComposeTypes.Value<V?>
			runtime:batch(function()
				optional:set(nil)
				if single.onChange then
					single.onChange((nil :: unknown) :: V)
				end
			end)
		end
		local cards = ctx.column({
			Compose.keyed({
				from = options,
				key = function(option: Nav.PickerOption<V>)
					return option.id or option.value
				end,
				render = function(
					source: ComposeTypes.ReadOnlyValue<Nav.PickerOption<V>>,
					index: ComposeTypes.ReadOnlyValue<number>
				)
					local key = tostring(source:peek().id or source:peek().value)
					local chosen = function(use: ComposeTypes.Use)
						return isSelected(use(source).value, use)
					end
					local card = UI.Button({
						Name = "Card-" .. key,
						LayoutOrder = index,
						Size = if across then D2.fromOffset(200, 0) else D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						label = function(use: ComposeTypes.Use)
							return read(use(source).label, use)
						end,
						subtitle = function(use: ComposeTypes.Use)
							return read(use(source).description, use) or ""
						end,
						icon = shared.liveIcon(source),
						controlSize = spec.controlSize,
						appearance = function(use: ComposeTypes.Use): string
							return if chosen(use) then "emphasis" else "standard"
						end,
						selected = chosen,
						enabled = function(use: ComposeTypes.Use)
							return read(spec.enabled, use) ~= false and read(use(source).enabled, use) ~= false
						end,
						onActivate = function()
							local value = source:peek().value
							if isSelected(value) and spec.required == false then
								clear()
							else
								select(value)
							end
						end,
					})
					card:AddTag("facet-card-option")
					local cardWidth = shared.layoutWidth(card)
					shared.wrapCaptions(card, spec.controlSize, function(use: ComposeTypes.Use): number
						return use(cardWidth)
					end)
					local content = card:FindFirstChild("Content")
					if content then
						runtime.mountFragment(function()
							local parts: { Types.Child } = {}
							if source:peek().meta ~= nil then
								table.insert(
									parts,
									ctx.styled(
										ctx.text({
											Name = "Meta",
											LayoutOrder = 50,
											Text = function(use: ComposeTypes.Use)
												return read(use(source).meta, use) or ""
											end,
										}),
										"secondary"
									)
								)
							end
							if source:peek().badge ~= nil then
								table.insert(
									parts,
									ctx.styled(
										Host.Frame "Badge" {
											LayoutOrder = 60,
											Size = D2.fromOffset(0, 0),
											AutomaticSize = E.AutomaticSize.XY,
											ctx.text({
												Name = "Count",
												Text = function(use: ComposeTypes.Use)
													local badge = read(use(source).badge, use)
													return if badge == nil then "" else tostring(badge)
												end,
											}) :: Types.Child,
										},
										"badge"
									)
								)
							end
							return parts
						end, content)
					end
					Compose.watch(function(use: ComposeTypes.Use)
						card:SetAttribute("FacetLabel", read(use(source).label, use))
					end)
					return card
				end,
			}),
		}, { Name = "Cards", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		local layout = assert(cards:FindFirstChildWhichIsA("UIListLayout"))
		if across then
			layout.FillDirection = E.FillDirection.Horizontal
			layout.Wraps = true
		end
		local outer = ctx.props(spec, pickerKeys, {
			Name = "Picker",
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		if spec.label == nil then
			return ctx.column({ cards }, outer)
		end
		return ctx.column({
			ctx.text({
				Name = "Label",
				Text = function(use: ComposeTypes.Use)
					return read(spec.label, use) or ""
				end,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
				TextWrapped = true,
			}),
			cards,
		}, outer)
	end
	return cardsStyle
end
