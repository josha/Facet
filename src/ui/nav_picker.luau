--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local fieldChrome = require("./field_chrome")
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")
local NavigationProps = require("./navigation_props")
local MenuItems = require("./nav_menu_items")
local PickerParts = require("./nav_picker_parts")
local pickerMenus = require("./nav_picker_menu")
local pickerCards = require("./nav_picker_cards")
local pickerOptions = require("./nav_picker_options")

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	buildMenu: MenuItems.BuildMenu
)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local shared = PickerParts(ctx, surfaces)
	local pickerKeys, derive = shared.keys, shared.derive
	local menus = pickerMenus(ctx, UI, shared, buildMenu)
	local cardsStyle = pickerCards(ctx, UI, shared)
	local optionsStyle = pickerOptions(ctx, UI, surfaces, shared)
	local function optionLabels(options: unknown): { unknown }
		local labels: { unknown } = {}
		if type(options) == "table" and not Compose.isReadable(options) then
			for _, option in options :: { { label: unknown } } do
				table.insert(labels, option.label)
			end
		end
		return labels
	end
	local function writable(cell: { set: unknown }, name: string)
		assert(type(cell) == "table" and type(cell.set) == "function", name .. " requires a writable Compose cell")
	end
	local optionFields: { [string]: boolean } = {
		id = true,
		value = true,
		label = true,
		description = true,
		icon = true,
		badge = true,
		enabled = true,
		meta = true,
		avatar = true,
		sectionTitle = true,
		indicator = true,
	}
	local function translate(word: string?, style: Nav.PickerStyle): string?
		if word == nil then
			return nil
		end
		if style == "segmented" then
			return if word == "standard" then "filled" elseif word == "contrast" then "stroke" else word
		elseif style == "menu" or style == "navigationLink" then
			return if word == "filled" then "standard" elseif word == "stroke" then "contrast" else word
		end
		return nil
	end
	local chrome = fieldChrome(ctx)
	UI.Picker = ctx.construct("Picker", function<V>(spec: NavigationProps.PickerSpec<V>): GuiObject
		writable(spec.selected, "Picker.selected")
		assert(spec.onChange == nil or type(spec.onChange) == "function", "Picker.onChange must be a function")
		assert(spec.onChanging == nil or type(spec.onChanging) == "function", "Picker.onChanging must be a function")
		assert(spec.required == nil or type(spec.required) == "boolean", "Picker.required must be a boolean")
		assert(
			spec.enabled == nil or type(read(spec.enabled)) == "boolean",
			"Picker.enabled must be a boolean or a readable boolean"
		)
		local declaredStyle: Nav.PickerStyle = spec.style or "automatic"
		chrome.check("Picker", {
			label = spec.label,
			requiredMark = spec.requiredMark,
			hint = spec.hint,
			errorText = spec.errorText,
			controlSize = spec.controlSize,
			corners = spec.corners,
		})
		shared.appearanceFor(declaredStyle, read(spec.appearance))
		assert(
			spec.maxHeight == nil
				or (type(spec.maxHeight) == "number" and spec.maxHeight > 0 and spec.maxHeight < math.huge),
			"Facet UI.Picker: maxHeight must be a finite number of pixels above zero"
		)
		assert(
			spec.maxHeight == nil or table.find({ "automatic", "menu", "navigationLink" }, declaredStyle),
			"Facet UI.Picker: maxHeight belongs to the menu styles"
		)
		assert(
			spec.valueAlignment == nil or spec.valueAlignment == "start" or spec.valueAlignment == "end",
			"Facet UI.Picker: valueAlignment must be start or end"
		)
		assert(
			spec.query == nil or declaredStyle ~= "segmented",
			"Facet UI.Picker: a segmented picker takes no query. Use navigationLink or menu for a searchable list"
		)
		assert(
			spec.indicatorPosition == nil or declaredStyle == "radioGroup",
			"Facet UI.Picker: indicatorPosition belongs to the radioGroup style"
		)
		assert(
			spec.indicatorPosition == nil or spec.indicatorPosition == "leading" or spec.indicatorPosition == "trailing",
			"Facet UI.Picker: indicatorPosition must be leading or trailing"
		)
		if spec.requiredMark == "required" and spec.label ~= nil then
			local marked = table.clone(spec)
			local words = spec.label
			marked.requiredMark = nil
			marked.label = function(use: ComposeTypes.Use)
				return (read(words, use) or "") .. " *"
			end
			return UI.Picker(marked)
		end
		if spec.hint ~= nil or spec.errorText ~= nil then
			local inner = table.clone(spec)
			local shell: Types.FrameNativeProps = {}
			local source = (inner :: unknown) :: { [string]: unknown }
			local target = (shell :: unknown) :: { [string]: unknown }
			for _, key in { "Name", "Size", "Position", "AnchorPoint", "LayoutOrder", "Visible", "ZIndex" } do
				target[key], source[key] = source[key], nil
			end
			inner.hint, inner.errorText = nil, nil
			inner.Name = "Control"
			local control = UI.Picker(inner)
			local failure = chrome.errorOf({ errorText = spec.errorText }, nil)
			Compose.watch(function(use: ComposeTypes.Use)
				local failing = failure(use) ~= ""
				for _, node in control:GetDescendants() do
					if node.Name == "Trigger" and node:IsA("GuiObject") then
						if failing then
							node:AddTag("facet-invalid")
						elseif node:HasTag("facet-invalid") then
							node:RemoveTag("facet-invalid")
						end
					end
				end
			end)
			shell.Name = shell.Name or "Picker"
			return chrome.wrap({
				control = "Picker",
				spec = { hint = spec.hint, errorText = spec.errorText },
				plate = control,
				focus = function() end,
				enabled = function(use: ComposeTypes.Use?)
					return read(spec.enabled, use) ~= false
				end,
				native = shell,
			})
		end
		assert(
			type(spec.options) == "table" or type(spec.options) == "function",
			"Facet UI.Picker: options must be an array of { value, label } entries, a Compose readable, or a function(use) that returns one"
		)
		local function isSelected(value: V, use: ComposeTypes.Use?): boolean
			if spec.multiple then
				return read(spec.selected, use)[value] == true
			else
				return read(spec.selected, use) == value
			end
		end
		local function commitSelection<T>(
			selected: ComposeTypes.Cell<T>,
			value: T,
			onChanging: ((T, T) -> boolean?)?,
			onChange: ((T) -> ())?
		)
			local previous = selected:peek()
			if onChanging and onChanging(value, previous) == false then
				return
			end
			runtime:batch(function()
				selected:set(value)
				if onChange then
					onChange(value)
				end
			end)
		end
		local function select(value: V)
			if read(spec.enabled) == false then
				return
			end
			if spec.multiple then
				local previous = spec.selected:peek()
				local nextValue: { [V]: boolean } = {}
				for key, flag in previous do
					if key ~= value then
						nextValue[key] = flag
					end
				end
				if not previous[value] then
					nextValue[value] = true
				end
				if spec.required and next(nextValue) == nil then
					return
				end
				commitSelection(spec.selected, nextValue, spec.onChanging, spec.onChange)
			else
				if value ~= spec.selected:peek() then
					commitSelection(spec.selected, value, spec.onChanging, spec.onChange)
				end
			end
		end
		local declaredIndicator, declaredAxis, declaredSizing = read(spec.indicator), read(spec.axis), read(spec.sizing)
		assert(
			declaredIndicator == nil or table.find({ "automatic", "pill", "underline", "none" }, declaredIndicator),
			"Invalid Picker.indicator"
		)
		assert(declaredAxis == nil or table.find({ "x", "y" }, declaredAxis), "Picker.axis must be x or y")
		assert(
			declaredSizing == nil or table.find({ "fill", "hug" }, declaredSizing),
			"Picker.sizing must be fill or hug"
		)
		local style = spec.style or "automatic"
		if style == "automatic" then
			local retained = ctx.config.services.RunService ~= nil and spec.query == nil
			local input = surfaces.service("UserInputService")
			local preferred = if input
				then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
				else Compose.cell(nil :: Enum.PreferredInput?)
			local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(false)
			local tenFoot = ctx.tenFoot()
			local width = Compose.cell(0)
			local measure = ctx.text({
				Name = "LabelMeasure",
				Text = derive(function(use: ComposeTypes.Use?)
					local labels = {}
					for _, option in read(spec.options, use) do
						table.insert(labels, tostring(read(option.label, use) or ""))
					end
					return table.concat(labels, "")
				end, spec.options, table.unpack(optionLabels(spec.options))),
				TextSize = spec.textSize,
				TextWrapped = false,
				Visible = false,
			})
			measure:AddTag("facet-type-control")
			local labelBounds = ctx.observeNative.TextBounds(measure)

			local resolved = Compose.formula(function(use: ComposeTypes.Use): Nav.PickerStyle
				if spec.query then
					return "navigationLink"
				end
				local list: { Nav.PickerOption<V> } = read(spec.options, use)
				local count = #list
				local available = use(width)
				local described = false
				for _, option in list do
					if option.description ~= nil then
						described = true
					end
				end
				local needed = use(labelBounds).X + count * 24 + math.max(0, count - 1) * 4 + 6
				if count <= 4 and not described and (available == 0 or needed <= available) then
					return "segmented"
				end
				local kind = use(preferred)
				if
					not tenFoot(use)
					and (kind == E.PreferredInput.KeyboardAndMouse or kind == E.PreferredInput.Touch)
				then
					return "menu"
				end
				return if count <= 6 then "inline" else "menu"
			end)
			local props = ctx.props(spec, pickerKeys, {
				Name = "Picker",
				BackgroundTransparency = 1,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			})
			props[#props + 1] = Compose.keyed({
				from = function(use: ComposeTypes.Use)
					local chosen = use(resolved)
					if not retained then
						return { chosen }
					end
					local choices: { Nav.PickerStyle } = { "menu" }
					local list: { Nav.PickerOption<V> } = read(spec.options, use)
					if #list <= 6 then
						table.insert(choices, "inline")
					end
					local described = false
					for _, option in list do
						described = described or option.description ~= nil
					end
					if #list <= 4 and not described then
						table.insert(choices, "segmented")
					end
					return choices
				end,
				render = function(current: ComposeTypes.Readable<Nav.PickerStyle>)
					local presentation: Nav.PickerStyle = current:peek()
					local function active(use: ComposeTypes.Use): boolean
						return use(resolved) == presentation
					end
					local function enabled(use: ComposeTypes.Use): boolean
						return active(use) and read(spec.enabled, use) ~= false
					end
					local automatic = props.AutomaticSize
					local size = derive(function(use: ComposeTypes.Use?)
						local sizing = read(automatic, use)
						return D2.fromScale(
							if sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY then 0 else 1,
							if sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY then 0 else 1
						)
					end, automatic)
					if spec.multiple then
						local child: NavigationProps.MultiplePickerSpec<V> = {
							options = spec.options,
							query = spec.query,
							placeholder = spec.placeholder,
							label = spec.label,
							required = spec.required,
							enabled = if retained then enabled else spec.enabled,
							indicator = spec.indicator,
							axis = spec.axis,
							sizing = spec.sizing,
							iconOnly = spec.iconOnly,
							textSize = spec.textSize,
							Name = "Presentation",
							Visible = if retained then active else nil,
							style = presentation,
							isPresented = opened,
							AutomaticSize = automatic,
							Size = size,
							controlSize = spec.controlSize,
							corners = if presentation == "menu"
									or presentation == "segmented"
									or presentation == "navigationLink"
								then spec.corners
								else nil,
							maxHeight = if presentation == "menu" or presentation == "navigationLink"
								then spec.maxHeight
								else nil,
							appearance = if spec.appearance ~= nil
									and (
										presentation == "menu"
										or presentation == "segmented"
										or presentation == "navigationLink"
									)
								then function(use: ComposeTypes.Use): string
									return translate(read(spec.appearance, use), presentation) or "utility"
								end
								else nil,
							valueAlignment = spec.valueAlignment,
							multiple = true :: true,
							selected = spec.selected,
							onChanging = spec.onChanging,
							onChange = spec.onChange,
						}
						return UI.Picker(child)
					else
						local child: NavigationProps.SinglePickerSpec<V> = {
							options = spec.options,
							query = spec.query,
							placeholder = spec.placeholder,
							label = spec.label,
							required = spec.required,
							enabled = if retained then enabled else spec.enabled,
							indicator = spec.indicator,
							axis = spec.axis,
							sizing = spec.sizing,
							iconOnly = spec.iconOnly,
							textSize = spec.textSize,
							Name = "Presentation",
							Visible = if retained then active else nil,
							style = presentation,
							isPresented = opened,
							AutomaticSize = automatic,
							Size = size,
							controlSize = spec.controlSize,
							corners = if presentation == "menu"
									or presentation == "segmented"
									or presentation == "navigationLink"
								then spec.corners
								else nil,
							maxHeight = if presentation == "menu" or presentation == "navigationLink"
								then spec.maxHeight
								else nil,
							appearance = if spec.appearance ~= nil
									and (
										presentation == "menu"
										or presentation == "segmented"
										or presentation == "navigationLink"
									)
								then function(use: ComposeTypes.Use): string
									return translate(read(spec.appearance, use), presentation) or "utility"
								end
								else nil,
							valueAlignment = spec.valueAlignment,
							multiple = false :: false,
							selected = spec.selected,
							onChanging = spec.onChanging,
							onChange = spec.onChange,
						}
						return UI.Picker(child)
					end
				end,
			})
			props[#props + 1] = measure
			local container = Host.Frame(props)
			local measured = ctx.observeNative.AbsoluteSize(container)
			Compose.watch(function(use: ComposeTypes.Use)
				local available = use(measured).X
				if available > 0 then
					width:set(available)
				end
			end)
			return container
		end
		local options = Compose.formula(function(use: ComposeTypes.Use)
			local query = string.lower(tostring(read(spec.query, use) or ""))
			local result: { Nav.PickerOption<V> } = {}
			local seen: { [V | string]: boolean } = {}
			local list: { Nav.PickerOption<V> } = read(spec.options, use)
			for key in list do
				assert(
					type(key) == "number" and key >= 1 and key <= #list and key % 1 == 0,
					"Picker options require a dense array"
				)
			end
			for _, option in list do
				for field in (option :: unknown) :: { [unknown]: unknown } do
					assert(
						type(field) == "string" and optionFields[field] == true,
						`Unknown Picker option field {tostring(field)}`
					)
				end
				assert(
					option.description == nil or type(read(option.description, use)) == "string",
					"Picker description must be text"
				)
				assert(
					option.enabled == nil or type(read(option.enabled, use)) == "boolean",
					"Picker option enabled must be a boolean"
				)
				assert(
					option.icon == nil or type(read(option.icon, use)) == "string",
					"Picker option icon must be an icon name"
				)
				local badge = read(option.badge, use)
				assert(
					badge == nil or type(badge) == "string" or type(badge) == "number",
					"Picker option badge must be text or a number"
				)
				local key = option.id or option.value
				assert(key ~= nil and not seen[key], "Picker options require unique values or ids")
				seen[key] = true
				assert(
					type(read(option.label, use)) == "string" and string.find(read(option.label, use), "%S") ~= nil,
					"Picker options require nonempty labels"
				)
				assert(
					read(spec.iconOnly) ~= true or option.icon ~= nil,
					"Picker.iconOnly requires an icon on each option"
				)
				local label = tostring(read(option.label, use) or "")
				if query == "" or string.find(string.lower(label), query, 1, true) then
					table.insert(result, option)
				end
			end
			return result
		end)
		local choice: PickerParts.Choice<V> = { isSelected = isSelected, select = select, options = options }
		if style == "menu" then
			return menus.menu(spec, choice)
		end
		if style == "navigationLink" then
			return menus.navigationLink(spec, choice)
		end
		if style == "cards" then
			return cardsStyle(spec, choice)
		end
		assert(table.find({ "segmented", "inline", "radioGroup", "navigationLink" }, style), "Unknown Picker style")
		return optionsStyle(spec, choice, style)
	end)
end
