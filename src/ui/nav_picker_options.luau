--!strict
local ControlTypes = require("./control_types")
local segmentMetrics = require("./segment_metrics")
local Types = require("./types")
local Nav = require("./navigation_types")
local Media = require("./media_types")
local Content = require("./content_types")
local reducedMotion = require("./motion").reduced
local scrollLock = require("./scroll_lock")
local ComposeTypes = require("../vendor/compose/core")
local NavigationProps = require("./navigation_props")
local PickerParts = require("./nav_picker_parts")

local RADIO_MARK = 18 + 8

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces, shared: PickerParts.Parts)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2, D = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2, ctx.types.UDim
	local pickerKeys, derive = shared.keys, shared.derive
	local layoutWidth, sideChrome, wrapCaptions = shared.layoutWidth, shared.sideChrome, shared.wrapCaptions
	local function slideSelection(
		picker: GuiObject,
		boxes: {
			[GuiObject]: {
				order: ComposeTypes.ReadOnlyValue<number>,
				size: ComposeTypes.ReadOnlyValue<Vector2>,
				at: ComposeTypes.ReadOnlyValue<Vector2>,
			},
		},
		currentOrder: ComposeTypes.Value<number>,
		indicator: Types.Input<string>?
	): ()
		local reduced = reducedMotion(ctx)
		local spring = ctx.motionSpring("control")
		local laidOut = ctx.observe.AbsoluteContentSize(assert(picker:FindFirstChildWhichIsA("UIListLayout", true)))
		local seenOrder: number?, seenStrip: Vector2? = nil, nil
		local function reshaped(before: Vector2, after: Vector2): boolean
			if before.Y <= 0 or after.Y <= 0 then
				return math.abs(after.X - before.X) > 0.5 or math.abs(after.Y - before.Y) > 0.5
			end
			return math.abs(after.X * before.Y - before.X * after.Y) > 0.5 * math.max(before.Y, after.Y)
		end
		local function landsWithStrip(use: ComposeTypes.Use): boolean
			local order, strip = use(currentOrder), use(laidOut)
			local reflowed = order == seenOrder and seenStrip ~= nil and reshaped(seenStrip, strip)
			seenOrder, seenStrip = order, strip
			return reduced(use) or reflowed
		end
		local sliding = runtime.spring(function(use: ComposeTypes.Use)
			return use(currentOrder)
		end, { period = spring.period, damping = spring.damping, tolerance = 1e-3, reducedMotion = landsWithStrip })
		local _, slot = runtime.mount(function()
			return Host.Folder "Slide" { Host.Frame "SlideUnit" { Size = D2.fromOffset(1, 1), Visible = false } }
		end, picker)
		local probe = (slot :: Instance):FindFirstChild("SlideUnit") :: GuiObject
		local unit = ctx.observe.AbsoluteSize(probe)
		local content = ctx.observe.AbsolutePosition(probe)
		local function rectAt(use: ComposeTypes.Use, order: number): (Vector2?, Vector2?)
			local scale = use(unit).X
			scale = if scale > 0 then scale else 1
			local room = use(laidOut) / scale
			for _, box in boxes do
				if use(box.order) == order then
					local at = (use(box.at) - use(content)) / scale
					local size = use(box.size) / scale
					at = V2.new(math.clamp(at.X, 0, room.X), math.clamp(at.Y, 0, room.Y))
					return at, V2.new(math.min(size.X, room.X - at.X), math.min(size.Y, room.Y - at.Y))
				end
			end
			return nil, nil
		end
		local rect = Compose.formula(function(use: ComposeTypes.Use): { Vector2 }?
			local at = use(sliding)
			local low = math.floor(at)
			local fromAt, fromSize = rectAt(use, low)
			local toAt, toSize = rectAt(use, low + 1)
			local t = at - low
			if fromAt == nil or fromSize == nil or (t > 0 and (toAt == nil or toSize == nil)) then
				fromAt, fromSize = rectAt(use, use(currentOrder))
				t = 0
			end
			if fromAt == nil or fromSize == nil then
				return nil
			end
			local place = if t > 0 then fromAt:Lerp(toAt :: Vector2, t) else fromAt
			local size = if t > 0 then fromSize:Lerp(toSize :: Vector2, t) else fromSize
			return { place, size }
		end)
		local function shown(use: ComposeTypes.Use): boolean
			return read(indicator, use) ~= "underline"
				and not reduced(use)
				and use(currentOrder) > 0
				and use(rect) ~= nil
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if shown(use) then
				picker:AddTag("facet-segmented-slides")
			elseif picker:HasTag("facet-segmented-slides") then
				picker:RemoveTag("facet-segmented-slides")
			end
		end)
		runtime.mount(function()
			return ctx.styled(
				Host.Frame "SelectionFill" {
					ZIndex = 0,
					Active = false,
					Visible = shown,
					Position = function(use: ComposeTypes.Use): UDim2
						local box = use(rect)
						return if box then D2.fromOffset(box[1].X, box[1].Y) else D2.new()
					end,
					Size = function(use: ComposeTypes.Use): UDim2
						local box = use(rect)
						return if box then D2.fromOffset(box[2].X, box[2].Y) else D2.new()
					end,
				},
				"segment-fill"
			)
		end, slot :: Instance)
	end
	local function optionsStyle<V>(
		spec: NavigationProps.PickerSpec<V>,
		choice: PickerParts.Choice<V>,
		style: string
	): GuiObject
		local isSelected, select, options = choice.isSelected, choice.select, choice.options
		local vertical = style ~= "segmented" or read(spec.axis) == "y"
		local function across(use: ComposeTypes.Use?): boolean
			return style == "segmented" and read(spec.axis, use) ~= "y"
		end
		local room = Compose.cell(math.huge)
		local spilling = Compose.cell(false)
		local segmentBoxes: {
			[GuiObject]: {
				order: ComposeTypes.ReadOnlyValue<number>,
				size: ComposeTypes.ReadOnlyValue<Vector2>,
				at: ComposeTypes.ReadOnlyValue<Vector2>,
			},
		} =
			{}
		local currentOrder, chosenOrder = Compose.cell(0), Compose.cell(0)
		local captionHeights: { [Instance]: number } = {}
		local tallestCaption = Compose.cell(0)
		local function measureCaptions(): ()
			local tallest = 0
			for _, height in captionHeights do
				tallest = math.max(tallest, height)
			end
			if tallest ~= tallestCaption:peek() then
				tallestCaption:set(tallest)
			end
		end
		local segmentInput = ctx.effectiveInput()
		local function authoredHeight(use: ComposeTypes.Use?): number?
			local size = read(spec.Size, use)
			local automatic = read(spec.AutomaticSize, use)
			if
				size
				and size.Y.Scale == 0
				and size.Y.Offset > 0
				and automatic ~= E.AutomaticSize.Y
				and automatic ~= E.AutomaticSize.XY
			then
				return size.Y.Offset
			end
			return nil
		end
		local function stripHeight(use: ComposeTypes.Use?): number
			local rung = ctx.controlSize(spec.controlSize, "height", use)
			if (spec.controlSize == nil and authoredHeight(use) == nil) or segmentInput(use) == "Touch" then
				rung = math.max(rung, 44 + 2 * segmentMetrics.inset)
			end
			local package = read(ctx.config.theme, use)
			local recipe = if package and package.chrome then package.chrome.control else nil
			local inset = if recipe then recipe.contentInsets else nil
			local caption = if use then use(tallestCaption) else tallestCaption:peek()
			if caption <= 0 or recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
				return rung
			end
			local chrome = math.max(0, if inset then inset.top or 0 else 0)
				+ math.max(0, if inset then inset.bottom or 0 else 0)
			return math.max(rung, math.ceil(caption) + chrome + 2 * segmentMetrics.inset)
		end
		local fixedOptions = not (Compose.isValue(spec.options) or type(spec.options) == "function")
		local children: { ComposeTypes.Child } = {
			Host.UIListLayout({
				FillDirection = derive(function(use: ComposeTypes.Use?)
					return if style ~= "segmented" or read(spec.axis, use) == "y"
						then E.FillDirection.Vertical
						else E.FillDirection.Horizontal
				end, spec.axis),
				SortOrder = E.SortOrder.LayoutOrder,
				Padding = D.new(0, 4),
				HorizontalFlex = derive(function(use: ComposeTypes.Use?)
					return if style == "segmented"
							and read(spec.axis, use) ~= "y"
							and read(spec.sizing, use) ~= "hug"
						then E.UIFlexAlignment.Fill
						else E.UIFlexAlignment.None
				end, spec.axis, spec.sizing),
				VerticalFlex = derive(function(use: ComposeTypes.Use?)
					return if style == "segmented"
							and read(spec.axis, use) == "y"
							and read(spec.sizing, use) ~= "hug"
						then E.UIFlexAlignment.Fill
						else E.UIFlexAlignment.None
				end, spec.axis, spec.sizing),
			}),
		}
		if spec.query then
			table.insert(children, UI.TextInput "Search" { value = spec.query, placeholder = "Search" })
		end
		table.insert(
			children,
			Compose.keyed({
				from = options,
				key = function(option: Nav.PickerOption<V>)
					return option.id or option.value
				end,
				render = function(
					source: ComposeTypes.ReadOnlyValue<Nav.PickerOption<V>>,
					index: ComposeTypes.ReadOnlyValue<number>
				)
					local selected = function(use: ComposeTypes.Use)
						return isSelected(use(source).value, use)
					end
					local current = source:peek()
					local fixed = fixedOptions and spec.query == nil
					local sealed = style == "segmented" and current.icon ~= nil
					local function labelOf(use: ComposeTypes.Use?): string
						if read(spec.iconOnly, use) then
							return ""
						end
						local option = if use then use(source) else source:peek()
						return read(option.label, use)
					end
					local function enabledOf(use: ComposeTypes.Use?): boolean
						local option = if use then use(source) else source:peek()
						return read(spec.enabled, use) ~= false and read(option.enabled, use) ~= false
					end
					local button = UI.Button({
						Name = tostring(current.id or current.value),
						LayoutOrder = if fixed then index:peek() else index,
						Size = function(use: ComposeTypes.Use)
							if across(use) then
								local height = stripHeight(use)
								height = math.max(authoredHeight(use) or 0, height)
								return D2.fromOffset(0, math.max(0, height - 2 * segmentMetrics.inset))
							end
							local height = if spec.controlSize ~= nil
								then ctx.controlSize(spec.controlSize, "height", use)
								else 44
							local automatic = read(spec.AutomaticSize, use)
							local hug = style == "segmented"
								and (automatic == E.AutomaticSize.X or automatic == E.AutomaticSize.XY)
							return D2.new(if hug then 0 else 1, 0, 0, height)
						end,
						AutomaticSize = if style ~= "segmented"
							then E.AutomaticSize.Y
							else derive(function(use: ComposeTypes.Use?)
								local automatic = read(spec.AutomaticSize, use)
								return if across(use)
									then E.AutomaticSize.X
									elseif
										automatic == E.AutomaticSize.X or automatic == E.AutomaticSize.XY
									then E.AutomaticSize.XY
									else E.AutomaticSize.Y
							end, spec.axis, spec.AutomaticSize),
						label = derive(labelOf, if fixed then nil else source, spec.iconOnly, current.label),
						name = function(use: ComposeTypes.Use): string
							local option = use(source)
							local badge = read(option.badge, use)
							return tostring(read(option.label, use))
								.. (if badge ~= nil and badge ~= "" then ` ({badge})` else "")
						end,
						subtitle = if source:peek().description ~= nil
								or source:peek().badge ~= nil
								or style == "radioGroup"
								or Compose.isValue(spec.options)
								or type(spec.options) == "function"
							then function(use: ComposeTypes.Use)
								return read(use(source).description, use) or ""
							end
							else nil,
						icon = shared.liveIcon(source),
						TextSize = spec.textSize,
						TextXAlignment = if style == "segmented" then E.TextXAlignment.Center else nil,
						trailingIcon = if read(spec.indicator) == "none" and style ~= "segmented"
							then "checkmark"
							else nil,
						selected = function(use: ComposeTypes.Use)
							local indicator = read(spec.indicator, use)
							return selected(use)
								and indicator ~= "underline"
								and (indicator ~= "none" or style == "segmented")
						end,
						enabled = derive(enabledOf, if fixed then nil else source, spec.enabled, current.enabled),
						haptic = function(use: ComposeTypes.Use)
							return spec.multiple == true or not selected(use)
						end,
						onActivate = function()
							select(source:peek().value)
						end,
					})
					if sealed then
						Compose.watch(function(use: ComposeTypes.Use)
							if labelOf(use) == "" then
								button:AddTag("facet-button-glyph")
							else
								button:RemoveTag("facet-button-glyph")
							end
						end)
					end
					local glyph = if sealed then button:FindFirstChild("LeadingIcon", true) else nil
					if glyph and (current.badge ~= nil or not fixed) then
						local corner = UI.badged(
							Host.Frame({ Name = "Anchor", BackgroundTransparency = 1, Size = D2.fromScale(1, 1) }),
							function(use: ComposeTypes.Use): string?
								local badge = read(use(source).badge, use)
								return if badge == nil then nil else tostring(badge)
							end
						)
						runtime.decorate(corner, { Size = D2.fromScale(1, 1), AutomaticSize = E.AutomaticSize.None })
						runtime.mount(function()
							return corner
						end, glyph)
					end
					if read(spec.indicator) == "none" and style ~= "segmented" then
						local check = button:FindFirstChild("TrailingIcon", true)
						if check and check:IsA("GuiObject") then
							Compose.watch(function(use: ComposeTypes.Use)
								check.Visible = selected(use)
							end)
						end
					end
					local badgeContent = button:FindFirstChild("Content")
					if
						badgeContent
						and (current.badge ~= nil or Compose.isValue(spec.options) or type(spec.options) == "function")
					then
						runtime.mountFragment(function()
							return {
								Compose.show(function(use: ComposeTypes.Use)
									local badge = read(use(source).badge, use)
									return badge ~= nil and badge ~= "" and not sealed
								end, function()
									local last = tostring(read(source:peek().badge))
									return UI.Badge({
										Name = "Count",
										LayoutOrder = 900,
										label = function(use: ComposeTypes.Use): string
											local badge = read(use(source).badge, use)
											if badge ~= nil and badge ~= "" then
												last = tostring(badge)
											end
											return last
										end,
									})
								end),
							}
						end, badgeContent)
					end
					if style == "radioGroup" then
						local trailing = spec.indicatorPosition == "trailing"
						runtime.mountFragment(function()
							return {
								ctx.styled(
									Host.Frame "Indicator" {
										Size = D2.fromOffset(18, 18),
										LayoutOrder = if trailing then 1000 else 0,
										BackgroundTransparency = 1,
										ctx.corner(9) :: Types.Child,
										ctx.styled(
											Host.Frame "Dot" {
												AnchorPoint = V2.new(0.5, 0.5),
												Position = D2.fromScale(0.5, 0.5),
												Size = D2.fromOffset(8, 8),
												Visible = selected,
												ctx.corner(4) :: Types.Child,
											},
											"fill"
										),
									},
									"radio-mark"
								),
							}
						end, (assert(button:FindFirstChild("Content"), "Picker radio rows use a content row")))
					end
					if
						source:peek().indicator ~= nil
						or Compose.isValue(spec.options)
						or type(spec.options) == "function"
					then
						local statusUI = UI
						surfaces.attach(button, {
							Compose.show(function(use: ComposeTypes.Use)
								return use(source).indicator ~= nil
							end, function()
								return statusUI.StatusIndicator({
									Name = "Status",
									AnchorPoint = V2.new(1, 0.5),
									Position = D2.new(1, -8, 0.5, 0),
									status = function(use: ComposeTypes.Use): Media.Status
										local mark = use(source).indicator
										if mark == nil then
											return "neutral"
										end
										local status = read(mark.status, use)
										return if status == nil then "neutral" else status
									end,
									form = source:peek().indicator
										and (source:peek().indicator :: Nav.OptionIndicator).form,
									count = function(use: ComposeTypes.Use)
										local mark = use(source).indicator
										return if mark then read(mark.count, use) else nil
									end,
								})
							end),
						})
					end
					local underlined = Compose.isValue(spec.indicator)
						or type(spec.indicator) == "function"
						or spec.indicator == "underline"
					surfaces.attach(button, {
						Host.UISizeConstraint({
							MinSize = function(use: ComposeTypes.Use)
								local strip = across(use)
								local width = if strip
									then math.max(
										0,
										44 - sideChrome(spec.controlSize, use, sealed and labelOf(use) == "")
									)
									else 44
								return V2.new(width, if spec.controlSize ~= nil or strip then 0 else 44)
							end,
							MaxSize = if style == "segmented"
								then function(use: ComposeTypes.Use): Vector2
									return V2.new(math.max(44, use(room) - 2 * segmentMetrics.inset), math.huge)
								end
								else nil,
						}),
						if underlined
							then Compose.show(function(use: ComposeTypes.Use)
								return read(spec.indicator, use) == "underline" and selected(use)
							end, function()
								return ctx.styled(
									Host.Frame "SelectionIndicator" {
										BorderSizePixel = 0,
										Size = D2.new(1, 0, 0, 2),
										Position = D2.new(0, 0, 1, -2),
										Selectable = false,
									},
									"selection-indicator"
								)
							end)
							else nil,
					})
					if style == "segmented" and not vertical then
						surfaces.attach(button, {
							Host.UIFlexItem({
								FlexMode = function(use: ComposeTypes.Use): Enum.UIFlexMode
									return if read(spec.sizing, use) == "hug"
										then E.UIFlexMode.None
										elseif across(use) then if use(spilling)
											then E.UIFlexMode.None
											else E.UIFlexMode.Grow
										else E.UIFlexMode.Fill
								end,
							}),
						})
					end
					if fixed and not (Compose.isValue(current.label) or type(current.label) == "function") then
						button:SetAttribute("FacetLabel", current.label)
					else
						Compose.watch(function(use: ComposeTypes.Use)
							button:SetAttribute("FacetLabel", read(use(source).label, use))
						end)
					end
					local family = if style == "segmented" then "facet-segment" else "facet-choice"
					button:AddTag(family)
					if style == "radioGroup" then
						wrapCaptions(button, spec.controlSize, function(use: ComposeTypes.Use): number
							return use(room) - RADIO_MARK
						end)
					end
					if style == "segmented" then
						local function peers(use: ComposeTypes.Use): number
							return #use(options)
						end
						wrapCaptions(button, spec.controlSize, function(use: ComposeTypes.Use): number
							return use(room) - 2 * segmentMetrics.inset
						end, peers)
						shared.wrapWhenLong(button, function(use: ComposeTypes.Use): string
							return `{use(room) - 2 * segmentMetrics.inset}|{peers(use)}`
						end, button, true)
						local caption = button:FindFirstChild("Title", true) or button:FindFirstChild("Label", true)
						local bounds = if caption and caption:IsA("TextLabel")
							then ctx.observe.TextBounds(caption)
							else ctx.observe.TextBounds(button)
						local captionUnit = ctx.layoutUnit(button)
						local extent = ctx.observe.AbsoluteSize(button)
						Compose.watch(function(use: ComposeTypes.Use)
							captionHeights[button] = use(bounds).Y / use(captionUnit)
							measureCaptions()
						end)
						segmentBoxes[button] =
							{ order = index, size = extent, at = ctx.observe.AbsolutePosition(button) }
						Compose.cleanup(function()
							captionHeights[button] = nil
							segmentBoxes[button] = nil
							measureCaptions()
						end)
					end
					local content = button:FindFirstChild("Content")
					local layout = if content then content:FindFirstChildWhichIsA("UIListLayout") else nil
					if style ~= "segmented" and layout then
						layout.HorizontalAlignment = E.HorizontalAlignment.Left
					end
					Compose.watch(function(use: ComposeTypes.Use)
						local indicator = read(spec.indicator, use)
						local chosen = selected(use)
						local current = chosen
							and indicator ~= "underline"
							and (indicator ~= "none" or style == "segmented")
						if current then
							button:AddTag(family .. "-current")
						elseif button:HasTag(family .. "-current") then
							button:RemoveTag(family .. "-current")
						end
						local order = use(index)
						if style ~= "segmented" then
							return
						end
						if chosen then
							chosenOrder:set(order)
						elseif chosenOrder:peek() == order then
							chosenOrder:set(0)
						end
						if current then
							currentOrder:set(order)
						elseif currentOrder:peek() == order then
							currentOrder:set(0)
						end
					end)
					local section = source:peek().sectionTitle
					if section ~= nil and style ~= "segmented" then
						runtime.decorate(button, { LayoutOrder = 2 })
						return ctx.column({
							ctx.styled(
								ctx.text({
									Name = "SectionTitle",
									Text = function(use: ComposeTypes.Use)
										return read(section, use) or ""
									end,
								}),
								"type-caption"
							),
							button,
						}, {
							Name = "Section-" .. button.Name,
							LayoutOrder = index,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
						})
					end
					return button
				end,
			})
		)
		local labelled = spec.label ~= nil and not vertical
		local strip = style == "segmented" and spec.label == nil and (spec.Size ~= nil or spec.AutomaticSize ~= nil)
		local declaredSize, declaredAutomatic = spec.Size, spec.AutomaticSize
		local function tall(use: ComposeTypes.Use): boolean
			local sizing = read(declaredAutomatic, use)
			return across(use) and (sizing == E.AutomaticSize.Y or sizing == E.AutomaticSize.XY)
		end
		local source = spec
		if strip then
			source = table.clone(spec)
			local fields = (source :: unknown) :: { [string]: unknown }
			fields.Size, fields.AutomaticSize = nil, nil
		end
		local defaults: Types.FrameNativeProps = {
			Name = "Picker",
			BackgroundTransparency = if style == "segmented" then nil else 1,
			Size = if strip
				then function(use: ComposeTypes.Use): UDim2
					local rung = ctx.controlSize(spec.controlSize, "height", use)
					local size: UDim2 = read(declaredSize, use) or D2.new(1, 0, 0, rung)
					if tall(use) then
						return D2.new(size.X.Scale, size.X.Offset, 0, rung)
					end
					return size
				end
				elseif style == "segmented" then function(use: ComposeTypes.Use): UDim2
					if not across(use) then
						return D2.new(1, 0, 0, 0)
					end
					return D2.new(if labelled then 0 else 1, 0, 0, stripHeight(use))
				end
				else D2.new(1, 0, 0, 0),
			AutomaticSize = if strip
				then function(use: ComposeTypes.Use): Enum.AutomaticSize
					local sizing: Enum.AutomaticSize = read(declaredAutomatic, use) or E.AutomaticSize.None
					if tall(use) then
						return if sizing == E.AutomaticSize.XY then E.AutomaticSize.X else E.AutomaticSize.None
					end
					if not across(use) then
						local wide = sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
						return if wide then E.AutomaticSize.XY else E.AutomaticSize.Y
					end
					return sizing
				end
				elseif style == "segmented" then derive(function(use: ComposeTypes.Use?)
					return if not across(use)
						then E.AutomaticSize.Y
						elseif labelled then E.AutomaticSize.X
						else E.AutomaticSize.None
				end, spec.axis)
				else E.AutomaticSize.Y,
		}
		local p = if spec.label == nil then ctx.props(source, pickerKeys, defaults) else defaults
		for _, child in children do
			table.insert((p :: unknown) :: { unknown }, child)
		end
		local scrolls = style == "segmented" and not vertical
		if scrolls then
			local scrollable: Types.ScrollingFrameNativeProps = {
				ScrollingDirection = E.ScrollingDirection.X,
				HorizontalScrollBarInset = E.ScrollBarInset.None,
				Selectable = false,
				AutomaticCanvasSize = E.AutomaticSize.None,
			}
			local fields = (p :: unknown) :: { [string]: unknown }
			for key, value in (scrollable :: unknown) :: { [string]: unknown } do
				if fields[key] == nil then
					fields[key] = value
				end
			end
		end
		local ready = Compose.cell(false)
		local fieldLabel: TextLabel? = nil
		local picker: GuiObject
		if style == "segmented" and labelled then
			local fading = (p :: unknown) :: Types.CanvasGroupNativeProps
			fading.GroupTransparency = function(use: ComposeTypes.Use): number
				return if use(ready) then 0 else 1
			end
			picker = ctx.fade(fading, nil, nil, true)
			local complete = false
			local settled = ctx.runtime.settled {
				sample = function(): string
					local parts = { tostring(picker.AbsoluteSize) }
					local filled = picker.AbsoluteSize.X > 0 and picker.AbsoluteSize.Y > 0
					local caption = fieldLabel
					if caption then
						table.insert(parts, `{caption.AbsolutePosition}:{caption.AbsoluteSize}:{caption.TextBounds}`)
						filled = filled
							and caption.AbsoluteSize.X > 0
							and caption.AbsoluteSize.Y > 0
							and caption.TextBounds.X <= caption.AbsoluteSize.X
							and caption.TextBounds.Y <= caption.AbsoluteSize.Y
					end
					for button in segmentBoxes do
						table.insert(
							parts,
							`{button.AbsolutePosition}:{button.AbsoluteSize}:{(button :: TextButton).TextBounds}`
						)
						filled = filled and button.AbsoluteSize.X > 0 and button.AbsoluteSize.Y > 0
					end
					complete = filled
					return table.concat(parts, ";")
				end,
				equals = function(a: string, b: string): boolean
					return complete and a == b
				end,
				timeout = ctx.metric("motion.restLimit"),
			}
			Compose.watch(function(use: ComposeTypes.Use)
				ready:set(use(settled))
			end)
		elseif scrolls then
			picker = Host.ScrollingFrame((p :: unknown) :: Types.ScrollingFrameNativeProps)
		else
			picker = Host.Frame(p)
		end
		local overflows: ComposeTypes.ReadOnlyValue<boolean>? = nil
		if scrolls then
			local scroller = picker :: ScrollingFrame
			scrollLock.own(scroller, ctx)
			local layout = assert(picker:FindFirstChildWhichIsA("UIListLayout", true))
			local extent = ctx.observe.AbsoluteContentSize(layout)
			local unit = ctx.layoutUnit(picker)
			local window = ctx.observe.AbsoluteWindowSize(scroller)
			local base = p.Size
			local function scaleOf(use: ComposeTypes.Use): number
				local scale = use(unit)
				return if scale > 0 then scale else 1
			end
			Compose.watch(function(use: ComposeTypes.Use)
				if not across(use) then
					spilling:set(false)
					return
				end
				local view = use(window).X
				local room = if spilling:peek() then view - 2 * segmentMetrics.inset * scaleOf(use) else view
				spilling:set(room > 0 and use(extent).X > room + 1)
			end)
			local spills: ComposeTypes.ReadOnlyValue<boolean> = spilling
			overflows = spills
			local fields = (p :: unknown) :: { [string]: unknown }
			local scrolling: { [string]: unknown } = {
				Size = function(use: ComposeTypes.Use): UDim2
					local size = read(base, use) or D2.new(1, 0, 0, stripHeight(use))
					if not across(use) then
						return size
					end
					local height = use(extent).Y / scaleOf(use)
					return D2.new(
						size.X.Scale,
						size.X.Offset,
						size.Y.Scale,
						math.max(size.Y.Offset, height + 2 * segmentMetrics.inset)
					)
				end,
			}
			if fields.CanvasSize == nil then
				scrolling.CanvasSize = function(use: ComposeTypes.Use): UDim2
					if not use(spills) then
						return D2.new(0, math.floor(use(window).X / scaleOf(use)), 1, 0)
					end
					return D2.new(0, math.ceil(use(extent).X / scaleOf(use)) + 2 * segmentMetrics.inset, 1, 0)
				end
			end
			if fields.ScrollingEnabled == nil then
				scrolling.ScrollingEnabled = function(use: ComposeTypes.Use): boolean
					return use(spills)
				end
			end
			if fields.ScrollBarThickness == nil then
				scrolling.ScrollBarThickness = function(use: ComposeTypes.Use): number
					return if use(spills) then segmentMetrics.inset - 1 else 0
				end
			end
			if fields.ClipsDescendants == nil then
				scrolling.ClipsDescendants = function(use: ComposeTypes.Use): boolean
					return use(spills)
				end
			end
			runtime.decorate(picker, scrolling)
			local revealed: string? = nil
			local shownOrder = 0
			Compose.watch(function(use: ComposeTypes.Use)
				local order, view = use(chosenOrder), use(window).X
				if not use(spills) then
					revealed = nil
					if scroller.CanvasPosition.X ~= 0 then
						scroller.CanvasPosition = V2.new(0, scroller.CanvasPosition.Y)
					end
					return
				elseif order <= 0 or view <= 0 then
					return
				end
				local chosen: GuiObject? = nil
				for button, box in segmentBoxes do
					if use(box.order) == order then
						chosen = button
						use(box.at)
						use(box.size)
					end
				end
				local key = `{order}:{view}:{use(extent).X}`
				if chosen == nil or chosen.AbsoluteSize.X <= 0 or key == revealed then
					return
				end
				local animated = revealed ~= nil and order ~= shownOrder
				revealed, shownOrder = key, order
				local inset = segmentMetrics.inset * scaleOf(use)
				local start = chosen.AbsolutePosition.X - scroller.AbsolutePosition.X - inset
				local length = chosen.AbsoluteSize.X + 2 * inset
				local delta = if start < 0 then start elseif start + length > view then start + length - view else 0
				if delta ~= 0 then
					UI.scrollTo(scroller, { x = scroller.CanvasPosition.X + delta }, { animated = animated })
				end
			end)
		end
		local function marked(root: GuiObject): GuiObject
			local signal = overflows
			if signal then
				Compose.watch(function(use: ComposeTypes.Use)
					root:SetAttribute("FacetOverflow", if use(signal) then true else nil)
				end)
			end
			return root
		end
		if not labelled then
			local width = layoutWidth(picker)
			Compose.watch(function(use: ComposeTypes.Use)
				room:set(use(width))
			end)
		end
		if style == "segmented" then
			picker:AddTag("facet-segmented")
			if spec.multiple ~= true then
				slideSelection(picker, segmentBoxes, currentOrder, (spec.indicator :: unknown) :: Types.Input<string>?)
			end
			surfaces.attach(picker, {
				Host.UISizeConstraint "TargetFloor" {
					MinSize = function(use: ComposeTypes.Use)
						local rung = if spec.controlSize ~= nil
							then ctx.controlSize(spec.controlSize, "height", use)
							else 44
						return V2.new(
							0,
							if read(spec.axis, use) == "y"
								then 0
								elseif segmentInput(use) == "Touch" then math.max(
									rung,
									44 + 2 * segmentMetrics.inset
								)
								elseif spec.controlSize ~= nil or authoredHeight(use) ~= nil then rung
								else rung + 2 * segmentMetrics.inset
						)
					end,
				},
			})
			if spec.corners then
				surfaces.attach(picker, {
					Host.UICorner "Corners" { CornerRadius = D.new(if spec.corners == "pill" then 1 else 0, 0) },
				})
				picker:AddTag(if spec.corners == "pill" then "facet-segmented-pill" else "facet-segmented-square")
			end
			if spec.appearance ~= nil then
				Compose.watch(function(use: ComposeTypes.Use)
					local word = shared.appearanceFor("segmented", read(spec.appearance, use))
					local stroke, utility = word == "stroke", word == "utility"
					if stroke then
						picker:AddTag("facet-segmented-stroke")
					elseif picker:HasTag("facet-segmented-stroke") then
						picker:RemoveTag("facet-segmented-stroke")
					end
					if utility then
						picker:AddTag("facet-segmented-utility")
					elseif picker:HasTag("facet-segmented-utility") then
						picker:RemoveTag("facet-segmented-utility")
					end
				end)
			end
		end
		if spec.label == nil then
			return marked(picker)
		end
		picker.Name = "Options"
		local label = ctx.text({
			Name = "Label",
			Text = derive(function(use: ComposeTypes.Use?)
				return read(spec.label, use) or ""
			end, spec.label),
			Size = D2.new(if vertical then 1 else 0, 0, 0, 0),
			AutomaticSize = if vertical then E.AutomaticSize.Y else E.AutomaticSize.XY,
			TextWrapped = vertical,
			TextXAlignment = E.TextXAlignment.Left,
		})
		local outer = ctx.props(spec, pickerKeys, {
			Name = "Picker",
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		if vertical then
			return ctx.column({ label, picker }, outer)
		end
		fieldLabel = label
		if style == "segmented" then
			runtime.mount(function()
				return Host.UIGradient "FadePaint" {
					Transparency = function(use: ComposeTypes.Use): NumberSequence
						return ctx.types.NumberSequence.new(if use(ready) then 0 else 1)
					end,
				}
			end, label)
		end
		runtime.mount(function()
			return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Grow })
		end, label)
		local row = ctx.row({ label, picker }, outer)
		local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
		layout.VerticalAlignment = E.VerticalAlignment.Center
		layout.Padding = D.new(0, 16)
		layout.Wraps = true
		local width = layoutWidth(row)
		Compose.watch(function(use: ComposeTypes.Use)
			room:set(use(width))
		end)

		local limit = picker:FindFirstChild("TargetFloor")
		local maxSize = function(use: ComposeTypes.Use)
			return V2.new(use(width), math.huge)
		end
		if limit then
			runtime.decorate(limit, { MaxSize = maxSize })
		else
			surfaces.attach(picker, { Host.UISizeConstraint({ MaxSize = maxSize }) })
		end
		return marked(row)
	end
	return optionsStyle
end
