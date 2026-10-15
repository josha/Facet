--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local OverlayProps = require("./overlay_props")
local MenuItems = require("./nav_menu_items")
local PickerParts = require("./nav_picker_parts")

type Controls = {
	Picker: ControlTypes.PickerConstructor,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
	Popover: Types.Constructor<OverlayProps.PopoverSpec, GuiObject>,
}

return function(ctx: Types.Context, UI: Controls, shared: PickerParts.Parts, buildMenu: MenuItems.BuildMenu)
	local Compose, runtime, read = ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local pickerKeys, appearanceFor = shared.keys, shared.appearanceFor
	local function menuStyle<V>(spec: NavigationProps.PickerSpec<V>, choice: PickerParts.Choice<V>): GuiObject
		local isSelected, select, options = choice.isSelected, choice.select, choice.options
		local native: Types.FrameNativeProps = ctx.props(spec, pickerKeys)
		local menuSpec: NavigationProps.MenuSpec<V> = { items = {} }
		for key, value in pairs(native) do
			menuSpec[key] = value
		end
		menuSpec.enabled = spec.enabled
		menuSpec.isPresented = spec.isPresented
		menuSpec.query = spec.query
		menuSpec.maxHeight = spec.maxHeight
		local valueText = function(use: ComposeTypes.Use): string
			local labels = {}
			for _, option in read(spec.options, use) do
				if isSelected(option.value, use) then
					table.insert(labels, read(option.label, use))
				end
			end
			return if #labels > 0
				then table.concat(labels, ", ")
				else read(spec.placeholder, use) or (if spec.label == nil then "Choose" else "Choose")
		end
		local triggerProps: InputProps.ButtonProps = {
			Name = "Trigger",
			label = valueText,
			enabled = spec.enabled,
			controlSize = spec.controlSize,
			corners = spec.corners,
			appearance = if spec.appearance ~= nil
				then function(use: ComposeTypes.Use): string
					local word = appearanceFor("menu", read(spec.appearance, use))
					return if word == "contrast" then "emphasis" elseif word == "utility" then "utility" else "default"
				end
				else nil,
			Attributes = { FacetLabel = valueText } :: Types.Attributes,
			ctx.icon("chevron.up.chevron.down", {
				Name = "Disclosure",
				Size = D2.fromOffset(12, 12),
				AnchorPoint = V2.new(1, 0.5),
				Position = D2.new(1, 20, 0.5, 0),
				BackgroundTransparency = 1,
			}) :: Types.Child,
		}
		if spec.Size ~= nil and spec.label == nil then
			local automatic = spec.AutomaticSize or E.AutomaticSize.None
			triggerProps.AutomaticSize = automatic
			triggerProps.Size = function(use: ComposeTypes.Use)
				local sizing = read(automatic, use)
				local width = sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
				local height = sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY
				return D2.new(
					if width then 0 else 1,
					0,
					if height then 0 else 1,
					if height then ctx.controlSize(spec.controlSize, "height", use) else 0
				)
			end
			triggerProps.TextTruncate = E.TextTruncate.AtEnd
			triggerProps.TextWrapped = false
			triggerProps.ClipsDescendants = true
		end
		local trigger = UI.Button(triggerProps)
		trigger:AddTag("facet-disclosure")
		menuSpec.trigger = function(): GuiObject
			return trigger
		end
		menuSpec.items = function(use: ComposeTypes.Use)
			local items = {}
			for _, option in use(options) do
				table.insert(items, {
					id = option.id or tostring(option.value),
					label = option.label,
					icon = option.icon,
					description = option.description,
					badge = option.badge,
					meta = option.meta,
					avatar = option.avatar,
					sectionTitle = option.sectionTitle,
					dismiss = not spec.multiple,
					marked = function(use: ComposeTypes.Use)
						return isSelected(option.value, use)
					end,
					enabled = option.enabled,
					onSelect = function()
						select(option.value)
					end,
				})
			end
			return items
		end
		if spec.label == nil then
			return buildMenu(menuSpec, true)
		end
		menuSpec.Name = "Value"
		menuSpec.Size = nil
		menuSpec.AutomaticSize = E.AutomaticSize.XY
		menuSpec.AnchorPoint = nil
		menuSpec.Position = nil
		local inline = spec.valueAlignment == "start"
		local label = ctx.text({
			Name = "Label",
			Text = function(use: ComposeTypes.Use)
				return read(spec.label, use) or ""
			end,
			Size = if inline then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0),
			AutomaticSize = if inline then E.AutomaticSize.XY else E.AutomaticSize.Y,
			TextWrapped = not inline,
			TextXAlignment = E.TextXAlignment.Left,
		})
		if inline then
			local hug = function(use: ComposeTypes.Use): boolean
				return read(spec.sizing, use) == "hug"
			end
			local row = ctx.row(
				{ label, buildMenu(menuSpec, true) },
				ctx.props(spec, pickerKeys, {
					Name = spec.Name or "Picker",
					BackgroundTransparency = 1,
					Size = function(use: ComposeTypes.Use)
						return if hug(use) then D2.fromOffset(0, 0) else D2.new(1, 0, 0, 0)
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if hug(use) then E.AutomaticSize.XY else E.AutomaticSize.Y
					end,
				})
			)
			local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
			layout.VerticalAlignment = E.VerticalAlignment.Center
			layout.Wraps = true
			row:SetAttribute("FacetValueAlignment", "start")
			return row
		end
		local column = ctx.column(
			{ label, buildMenu(menuSpec, true) },
			ctx.props(spec, pickerKeys, {
				Name = spec.Name or "Picker",
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
		)
		assert(column:FindFirstChildWhichIsA("UIListLayout")).Padding = D.new(0, 4)
		return column
	end
	local function linkStyle<V>(spec: NavigationProps.PickerSpec<V>, choice: PickerParts.Choice<V>): GuiObject
		local isSelected = choice.isSelected
		local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
		local chosenText = function(use: ComposeTypes.Use): string
			for _, option in read(spec.options, use) do
				if isSelected(option.value, use) then
					local label: string = read(option.label, use)
					return label
				end
			end
			return read(spec.placeholder, use) or "Choose"
		end
		local native: Types.FrameNativeProps = ctx.props(spec, pickerKeys)
		local triggerProps = (native :: unknown) :: InputProps.ButtonProps
		triggerProps.Name = spec.Name or "Picker"
		triggerProps.enabled = spec.enabled
		triggerProps.label = spec.label or chosenText
		triggerProps.trailingIcon = if spec.label ~= nil then "chevron.trailing" else nil
		if spec.label ~= nil then
			triggerProps.row = { title = spec.label }
			local given = spec.Size
			triggerProps.Size = function(use: ComposeTypes.Use): UDim2
				local base: UDim2 = read(given, use) or D2.fromScale(1, 0)
				local floor = ctx.controlSize(spec.controlSize, "height", use)
				return D2.new(base.X.Scale, base.X.Offset, base.Y.Scale, math.max(base.Y.Offset, floor))
			end
			triggerProps.AutomaticSize = spec.AutomaticSize or E.AutomaticSize.Y
			triggerProps.ClipsDescendants = true
		end
		triggerProps.controlSize = spec.controlSize
		triggerProps.corners = spec.corners
		triggerProps.appearance = if spec.appearance ~= nil
			then function(use: ComposeTypes.Use): string
				local word = appearanceFor("navigationLink", read(spec.appearance, use))
				return if word == "contrast" then "emphasis" elseif word == "utility" then "utility" else "standard"
			end
			else nil
		local trigger = UI.Button(triggerProps)
		local row = trigger:FindFirstChild("Content")
		local chevron = row and row:FindFirstChild("TrailingIcon")
		if chevron and chevron:IsA("GuiObject") then
			chevron.LayoutOrder = 100
		end
		if spec.label ~= nil and row then
			runtime.mountFragment(function()
				return {
					ctx.styled(
						ctx.text({
							Name = "Trailing",
							LayoutOrder = 90,
							Text = chosenText,
						}),
						"secondary"
					),
				}
			end, row)
		end
		UI.Popover {
			isPresented = opened,
			onPresentedChange = function(value: boolean)
				opened:set(value)
			end,
			trigger = trigger :: GuiButton,
			edge = "bottom" :: "bottom",
			align = "end" :: "end",
			maxWidth = ctx.metric("controls.popup.panelWidth"),
			maxHeight = spec.maxHeight or 400,
			title = spec.label,
			content = function(): Instance
				local choices: NavigationProps.PickerSpec<V>
				if spec.multiple then
					local source: NavigationProps.MultiplePickerSpec<V> = spec
					local child = table.clone(source)
					child.Name, child.style, child.isPresented = "Choices", "inline", nil
					child.Size = D2.new(1, 0, 0, 0)
					child.appearance, child.corners, child.maxHeight, child.requiredMark = nil, nil, nil, nil
					child.indicator = "none"
					child.onChange = function(value: { [V]: boolean })
						if source.onChange then
							source.onChange(value)
						end
					end
					choices = child
				else
					local source: NavigationProps.SinglePickerSpec<V> = spec
					local child = table.clone(source)
					child.Name, child.style, child.isPresented = "Choices", "inline", nil
					child.Size = D2.new(1, 0, 0, 0)
					child.appearance, child.corners, child.maxHeight, child.requiredMark = nil, nil, nil, nil
					child.indicator = "none"
					child.onChange = function(value: V)
						opened:set(false)
						if source.onChange then
							source.onChange(value)
						end
					end
					choices = child
				end
				local picker = (UI.Picker :: unknown) :: (NavigationProps.PickerSpec<V>) -> GuiObject
				return ctx.column({ picker(choices) }, {
					Name = "PickerSearch",
					Size = function(use: ComposeTypes.Use)
						return D2.fromOffset(ctx.metric("controls.popup.panelWidth", use) - 16, 0)
					end,
					AutomaticSize = E.AutomaticSize.Y,
				})
			end,
		}
		return trigger
	end
	return { menu = menuStyle, navigationLink = linkStyle }
end
