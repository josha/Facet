--!strict
local reducedMotion = require("./motion").reduced
local inputKit = require("./input_kit")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ThemeTypes = require("./theme_types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

type ToggleButtonProps = InputProps.ButtonProps & {
	value: Shared.Value<boolean>?,
	mixed: Shared.Value<boolean>?,
	presentation: ("switch" | "checkbox" | "button")?,
	onChange: ((boolean) -> ())?,
	indicatorPosition: ("leading" | "trailing")?,
}

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime, Host, Compose, read = ctx.runtime, ctx.Host, ctx.Compose, ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local dynamic, writable, unskinned, typeRoles = kit.dynamic, kit.writable, kit.unskinned, kit.typeRoles
	UI.Toggle = ctx.construct("Toggle", function(spec: InputTypes.ToggleImplementationProps): TextButton
		assert(type(read(spec.value)) == "boolean", "Facet.Toggle: value must be boolean")
		assert(writable(spec.value) or spec.onChange, "Facet.Toggle: read-only value requires onChange")
		assert(
			spec.mixed == nil or writable(spec.mixed) or spec.onChange,
			"Facet.Toggle: read-only mixed requires onChange"
		)
		local presentation = spec.presentation or "switch"
		assert(
			presentation == "switch" or presentation == "checkbox" or presentation == "button",
			"Facet.Toggle: invalid presentation"
		)
		assert(
			spec.mixed == nil or (presentation == "checkbox" and type(read(spec.mixed)) == "boolean"),
			"Facet.Toggle: mixed requires a checkbox boolean source"
		)
		assert(
			spec.indicatorPosition == nil or spec.indicatorPosition == "leading" or spec.indicatorPosition == "trailing",
			"Facet.Toggle: invalid indicatorPosition"
		)
		local plain = spec.appearance == "plain"
		assert(not plain or presentation ~= "button", "Facet.Toggle: the button presentation cannot be plain")

		local p = table.clone(
			spec :: Shared.TextButtonProps & InputTypes.ButtonVisualOptions & InputTypes.ButtonInputOptions
		) :: ToggleButtonProps
		p.value, p.mixed, p.presentation, p.onChange, p.indicatorPosition, p.row, p.hint =
			nil, nil, nil, nil, nil, nil, nil
		p.selected = if spec.mixed == nil
			then spec.value
			else function(use: ComposeTypes.Use)
				return read(spec.value, use) or read(spec.mixed, use) == true
			end
		p.ref = nil
		local markRow: ((GuiObject) -> ())? = nil
		if plain then
			p.selected, p.appearance = nil, nil
		end
		p.onActivate = function()
			local value = if read(spec.mixed) then true else not read(spec.value)
			if spec.onChange then
				spec.onChange(value)
			else
				if writable(spec.mixed) then
					((spec.mixed :: unknown) :: ComposeTypes.Cell<boolean>):set(false)
				end
				(spec.value :: ComposeTypes.Cell<boolean>):set(value)
			end
		end
		if presentation ~= "button" then
			local rich = spec.row ~= nil
				or spec.hint ~= nil
				or spec.icon ~= nil
				or spec.trailingIcon ~= nil
				or spec.image ~= nil
			local trailing = spec.indicatorPosition == "trailing" or (spec.indicatorPosition == nil and spec.row ~= nil)
			local sized = spec.controlSize ~= nil
			local sizeLive = sized and (dynamic(ctx.config.theme) or dynamic(spec.controlSize))
			local function track(use: ComposeTypes.Use?): (number, number)
				if not sized then
					return if presentation == "switch" then 38 else 24, 24
				end
				if presentation == "switch" then
					local height = ctx.controlSize(spec.controlSize, "iconSize", use) + 4
					return math.round(38 * height / 24), height
				end
				local side = ctx.controlSize(spec.controlSize, "iconSize", use) + ctx.metric("space.xs", use)
				return side, side
			end
			local function sizedValue<T>(compute: (ComposeTypes.Use?) -> T): Shared.Value<T>
				return if sizeLive then compute else compute()
			end
			local function rounded(compute: (ComposeTypes.Use?) -> UDim): Shared.Value<UDim>
				return if sizeLive or dynamic(ctx.config.theme) then compute else compute()
			end
			local function boxed<T>(compute: (number) -> T): Shared.Value<T>
				return sizedValue(function(use)
					local _, side = track(use)
					return compute(side)
				end)
			end
			local function reserve(use: ComposeTypes.Use?): number
				return (track(use)) + 8
			end
			local mark = ctx.styled(
				Host.Frame "Mark" {
					AnchorPoint = V2.new(0.5, 0.5),
					Size = if presentation == "switch"
						then sizedValue(function(use)
							local _, height = track(use)
							return D2.fromOffset(height - 6, height - 6)
						end)
						else D2.fromOffset(12, 12),
					Position = if presentation == "switch" then nil else D2.fromScale(0.5, 0.5),
					Host.UICorner {
						CornerRadius = rounded(function(use)
							local _, height = track(use)
							return ctx.round(use, D.new(0, if presentation == "switch" then (height - 6) / 2 else 2))
						end),
					},
				},
				"toggle-mark"
			)
			if presentation == "switch" then
				local knobReduced = reducedMotion(ctx)
				local spring = ctx.motionSpring("control")
				local knob = runtime.spring(function(use: ComposeTypes.Use): number
					return if read(spec.value, use) == true then 0.7 else 0.3
				end, {
					period = spring.period,
					damping = spring.damping,
					reducedMotion = function(use: ComposeTypes.Use): boolean
						return knobReduced(use)
					end,
				})
				runtime.decorate(mark, {
					Position = function(use: ComposeTypes.Use)
						return D2.fromScale(use(knob), 0.5)
					end,
				})
			end
			local check = if presentation == "checkbox"
				then ctx.icon("checkmark", {
					Name = "Check",
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = boxed(function(side: number): UDim2
						local tick = math.floor(side * 2 / 3 + 0.5)
						return D2.fromOffset(tick, tick)
					end),
					BackgroundTransparency = 1,
					Visible = false,
				})
				else nil
			if check then
				check:AddTag("facet-toggle-check")
			end
			local indicator = ctx.styled(
				Host.Frame({
					Name = "Indicator",
					Size = sizedValue(function(use)
						return D2.fromOffset(track(use))
					end),
					AnchorPoint = if rich then V2.zero else V2.new(0, 0.5),
					Position = if rich
						then D2.fromOffset(0, 0)
						elseif trailing then D2.new(1, 8, 0.5, 0)
						else sizedValue(function(use)
							return D2.new(0, -reserve(use), 0.5, 0)
						end),
					Host.UICorner {
						CornerRadius = rounded(function(use)
							local _, height = track(use)
							return ctx.round(use, D.new(0, if presentation == "switch" then height / 2 else 4))
						end),
					} :: ComposeTypes.Child,
					mark,
					check,
				} :: Shared.FrameNativeProps),
				"toggle-indicator"
			)
			local function updateIndicator(use)
				local value, mixed = read(spec.value, use), read(spec.mixed, use) == true
				if presentation ~= "switch" then
					mark.Size = D2.fromOffset(12, 4)
					mark.Visible = mixed
					if check then
						check.Visible = value == true and not mixed
					end
				end
				indicator:SetAttribute("selected", value or mixed)
				if value or mixed then
					indicator:AddTag("facet-toggle-on")
				elseif indicator:HasTag("facet-toggle-on") then
					indicator:RemoveTag("facet-toggle-on")
				end
			end
			indicator:AddTag(if presentation == "switch" then "facet-toggle-switch" else "facet-toggle-checkbox")
			if dynamic(spec.value) or dynamic(spec.mixed) then
				Compose.watch(updateIndicator)
			else
				updateIndicator()
			end
			if presentation == "switch" then
				ctx.skin(indicator, "toggleTrack", { selected = p.selected })
				ctx.skin(mark, "toggleKnob", { selected = p.selected })
			end
			if rich then
				p.Text = ""
				local row: InputTypes.Row = spec.row or {}
				local title = ctx.text({ Name = "Title", Text = row.title or spec.label or "" })
				local labelSize = read(spec.textSize)
				assert(
					labelSize == nil or typeRoles[labelSize :: string] or type(labelSize) == "number",
					"Facet.Toggle: textSize must be a type role or a positive number"
				)
				if type(labelSize) == "string" then
					title:AddTag("facet-type-" .. labelSize)
				elseif type(labelSize) == "number" then
					title.TextSize = labelSize
				end
				p.textSize = nil
				local captions: { GuiObject } = { title }
				local described = row.description ~= nil or spec.hint ~= nil
				if described then
					table.insert(
						captions,
						ctx.text({
							Name = "Description",
							Text = row.description or spec.hint,
							Size = if spec.row then D2.fromScale(1, 0) else D2.fromOffset(0, 0),
							AutomaticSize = if spec.row then E.AutomaticSize.Y else E.AutomaticSize.XY,
							TextWrapped = spec.row ~= nil,
						})
					)
				end
				local leading = spec.icon or row.icon
				p.icon = nil
				local icons: { ComposeTypes.Child } = if leading
					then { ctx.icon(leading, { Name = "LeadingIcon" }) }
					else {}
				if spec.row then
					if not trailing then
						table.insert(icons, indicator)
					end
					local content, size, mark = ctx.listRow({
						leading = icons,
						captions = captions,
						trailing = if trailing then { indicator } else nil,
						described = described,
						controlSize = spec.controlSize,
					})
					table.insert(p, content)
					if spec.Size == nil then
						p.Size = size
						p.AutomaticSize = spec.AutomaticSize or E.AutomaticSize.Y
					end
					markRow = mark
				else
					local label: GuiObject = if described then ctx.column(captions) else title
					table.insert(icons, if trailing then label else indicator)
					table.insert(icons, if trailing then indicator else label)
					table.insert(p, ctx.row(icons))
				end
			else
				p.Text = spec.Text or spec.label or ""
				p.TextXAlignment = spec.TextXAlignment or E.TextXAlignment.Left
				local reactive = dynamic(ctx.config.theme) or dynamic(spec.controlSize) or sizeLive
				local function paddingAmount(side: "left" | "right" | "top" | "bottom"): Shared.Value<UDim>
					local function amount(use: ComposeTypes.Use?): UDim
						local package = read(ctx.config.theme, use)
						local skin = package and package.chrome and package.chrome.control
						local insets: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
						local offset = (
							if side == "left"
								then insets.left
								elseif side == "right" then insets.right
								elseif side == "top" then insets.top
								else insets.bottom
						) or 0
						if (trailing and side == "right") or (not trailing and side == "left") then
							offset += reserve(use)
						end
						return D.new(0, offset)
					end
					return if reactive then amount else amount()
				end
				local padding: Shared.UIPaddingNativeProps = {}
				local fields = (padding :: unknown) :: { [string]: Shared.Value<UDim> }
				local function inset(side: "left" | "right" | "top" | "bottom", key: string)
					local amount = paddingAmount(side)
					if reactive or ((amount :: unknown) :: UDim).Offset ~= 0 then
						fields[key] = amount
					end
				end
				inset("left", "PaddingLeft")
				inset("right", "PaddingRight")
				inset("top", "PaddingTop")
				inset("bottom", "PaddingBottom")
				table.insert(p, Host.UIPadding(padding))
				table.insert(p, indicator)
			end
		end
		if spec.haptic == nil then
			p.haptic = true
		end
		if presentation ~= "button" then
			unskinned[p] = true
		end
		local toggle = ctx.styled(UI.Button(p), "toggle")
		if markRow then
			markRow(toggle)
		end
		if presentation ~= "button" then
			toggle:AddTag("facet-toggle-row")
			if plain then
				toggle:AddTag("facet-toggle-plain")
			elseif spec.row ~= nil or spec.hint ~= nil or spec.icon ~= nil then
				toggle:AddTag("facet-toggle-settings")
			end
		end
		return toggle
	end)
end
