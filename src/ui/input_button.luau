--!strict
local sizeFloor = require("./size_floor")
local reducedMotion = require("./motion").reduced
local decoration = require("./native_decoration")
local feedbackPaint = require("./feedback_paint")
local richText = require("./rich_text")
local help = require("./help")
local activation = require("./activation")
local inputKit = require("./input_kit")
local buttonContent = require("./input_button_content")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ThemeTypes = require("./theme_types")
local EngineTypes = require("./engine_types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local ComposeTypes = require("../vendor/compose/core")

return function(ctx: Shared.Context, UI: ControlTypes.Controls, kit: inputKit.Kit): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read = ctx.read
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local dynamic, enabled = kit.dynamic, kit.enabled
	local noKey, typeRoles = kit.noKey, kit.typeRoles
	local function captioned(package: ThemeTypes.ReadOnlyThemePackage?): boolean
		local recipe = package and package.chrome and package.chrome.control
		return recipe ~= nil and recipe.kind ~= "native" and recipe.kind ~= "none"
	end
	local dialogOrder = 0
	local roles: { [string]: boolean } = { default = true, cancel = true, destructive = true, onIndicator = true }
	local roleTags: { [string]: string } = {}
	for name in roles do
		roleTags[name] = "facet-role-" .. name
	end
	local contentGap = 8
	local lastHeight: number?, lastSize: UDim2?
	local function heightSize(rung: Shared.Input<Shared.ControlSize?>?, use: ComposeTypes.Use?): UDim2
		local height = ctx.controlSize(rung, "height", use)
		if height ~= lastHeight then
			lastHeight, lastSize = height, D2.fromOffset(0, height)
		end
		return assert(lastSize)
	end

	local buttonKeys = table.freeze({
		"cooldown",
		"charges",
		"haptic",
		"label",
		"compactLabel",
		"pop",
		"enabled",
		"disabled",
		"busy",
		"onActivate",
		"repeatDelay",
		"repeatInterval",
		"shortcut",
		"selected",
		"appearance",
		"help",
		"disclose",
		"controlSize",
		"corners",
		"role",
		"dialogAction",
		"icon",
		"glyph",
		"shortcutHint",
		"trailingIcon",
		"image",
		"imageAspectRatio",
		"imageFraming",
		"subtitle",
		"caption",
		"row",
		"name",
		"hint",
		"shape",
		"onPointerDown",
		"onPointerUp",
		"onPointerCancel",
		"textSize",
		"underline",
		"target",
	})
	local CONTROL_RUNGS = { "xsmall", "compact", "regular", "large" }
	local SMALLER: { [string]: Shared.ControlSize } =
		{ large = "regular", regular = "compact", compact = "xsmall", xsmall = "xsmall" }
	local RIM = 0.5 + 0.5 * math.sqrt(0.5)
	local rungTags: { string } = {}
	for index, name in CONTROL_RUNGS do
		rungTags[index] = "facet-size-" .. name
	end
	local escapeRich = richText.escape
	local idle: ComposeTypes.Directive = function() end
	local function sized(label: TextLabel | TextButton, textSize: Shared.Input<(number | Shared.TextRole)?>?)
		if textSize == nil then
			return
		end
		local function apply(value: (string | number)?)
			for role in typeRoles do
				if value ~= role and label:HasTag("facet-type-" .. role) then
					label:RemoveTag("facet-type-" .. role)
				end
			end
			if type(value) == "string" then
				assert(typeRoles[value], "Facet.Button: textSize must be a type role or a positive number")
				label:AddTag("facet-type-" .. value)
				label:ResetPropertyToDefault("TextSize")
			elseif type(value) == "number" then
				label.TextSize = value
			end
		end
		if dynamic(textSize) then
			Compose.watch(function(use: ComposeTypes.Use)
				apply(read<<(number | Shared.TextRole)?>>(textSize, use))
			end)
		else
			apply(read<<(number | Shared.TextRole)?>>(textSize))
		end
	end
	UI.Button = ctx.construct("Button", function(spec: InputProps.ButtonProps): TextButton
		local onActivate = spec.onActivate
		assert(
			spec.onActivate == nil or type(spec.onActivate) == "function",
			"Facet.Button: onActivate must be a function"
		)
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet.Button: shape must be rect or circle"
		)
		assert(
			spec.target == nil or spec.target == "hit" or spec.target == "thumb" or spec.target == "inline",
			"Facet.Button: target must be hit, thumb or inline"
		)
		local enabledLive = dynamic(spec.enabled) or dynamic(spec.disabled) or dynamic(spec.busy)
		local enabledSource: ComposeTypes.ReadOnlyValue<boolean>? = if enabledLive
			then Compose.formula(function(use: ComposeTypes.Use): boolean
				return enabled(spec, use)
			end)
			else nil
		local enabledFixed = if enabledLive then true else enabled(spec)
		local function isEnabled(use: ComposeTypes.Use?): boolean
			local source = enabledSource
			if source == nil then
				return enabledFixed
			end
			return if use then use(source) else source:peek()
		end
		local function cornerRadius(use: ComposeTypes.Use?): UDim
			local corners = read(spec.corners, use)
			assert(corners == "pill" or corners == "square", "Facet.Button: corners must be pill or square")
			return D.new(if corners == "pill" then 1 else 0, 0)
		end
		if spec.corners ~= nil then
			cornerRadius()
		end
		assert(
			spec.dialogAction == nil or spec.dialogAction == "default" or spec.dialogAction == "cancel",
			"Facet.Button: invalid dialogAction"
		)
		assert(
			spec.imageFraming == nil or spec.imageFraming == "fit" or spec.imageFraming == "crop",
			"Facet.Button: imageFraming must be fit or crop"
		)
		local hinted = spec.shortcutHint
		assert(
			hinted == nil or (hinted.IsA and hinted:IsA("InputAction")),
			"Facet.Button: shortcutHint must be a native InputAction"
		)
		local declaredSize = read<<(number | Shared.TextRole)?>>(spec.textSize)
		assert(
			declaredSize == nil
				or (type(declaredSize) == "string" and typeRoles[declaredSize])
				or (type(declaredSize) == "number" and declaredSize > 0 and declaredSize < math.huge),
			"Facet.Button: textSize must be a type role or a positive number"
		)
		local underline = spec.underline
		assert(
			underline == nil or underline == "always" or underline == "hover",
			"Facet.Button: underline must be always or hover"
		)
		local popSeconds = if spec.pop then ctx.metric("motion.durations.buttonPop") else 0
		local popTimeline = if spec.pop then runtime.timeline({ duration = popSeconds, autoplay = false }) else nil
		local popReduced = if popTimeline then reducedMotion(ctx) else nil
		local popStart = if popTimeline then Compose.cell(1) else nil
		local popScale
		if popTimeline then
			popTimeline:seek(popSeconds)
			local present = ctx.motionEase("present")
			local overshoot = ctx.metric("motion.materialize.popOvershoot")
			local decay = ctx.metric("motion.materialize.popDecay")
			popScale = Compose.formula(function(use: ComposeTypes.Use)
				if assert(popReduced)(use) then
					return 1
				end
				local phase = use(popTimeline.progress)
				return 1
					+ (use(assert(popStart)) - 1) * (1 - present(phase))
					+ overshoot * math.sin(math.pi * phase) * math.exp(-decay * phase)
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				if assert(popReduced)(use) then
					popTimeline:pause()
					popTimeline:seek(popSeconds)
				end
			end)
		end

		local node: TextButton
		local iconState: ComposeTypes.Value<ThemeTypes.SkinState>?
		local icon, trailingIcon = spec.icon or (spec.row and spec.row.icon), spec.trailingIcon
		if
			(icon ~= nil or trailingIcon ~= nil)
			and (
				ctx.iconVaries(icon)
				or ctx.iconVaries(trailingIcon)
				or (spec.row ~= nil and spec.onActivate ~= nil and ctx.iconVaries("chevron.trailing"))
			)
		then
			local initial: ThemeTypes.SkinState = "default"
			iconState = Compose.cell(initial)
		end
		local held, repeated = false, false
		local repeatable = spec.repeatDelay ~= nil or spec.repeatInterval ~= nil
		local repeatDelay, repeatInterval =
			spec.repeatDelay or kit.repeatDelay, spec.repeatInterval or kit.repeatInterval
		assert(
			repeatDelay > 0 and repeatDelay < math.huge and repeatInterval > 0 and repeatInterval < math.huge,
			"Facet.Button: repeat timings must be finite and positive"
		)
		local function activate(input: InputObject?, clicks: number?)
			local pressed: Instance? = node
			if
				activation.consumed(input)
				or (pressed and (help.consume(pressed) or activation.intercepted(pressed, input)))
			then
				return
			end
			local route = if node then ctx.shiftActivation(node, input) else nil
			local live = isEnabled()
			local open = live and node and ctx.available(node)
			if route and open then
				route()
				return
			end
			if open and onActivate then
				if popTimeline and popScale and popReduced and not held and not popReduced() then
					assert(popStart):set(popScale:peek())
					popTimeline:restart()
				end
				onActivate(input, clicks)
				open = ctx.available(node)
			end
			if open then
				activation.notify(node, input, clicks)
			end
		end
		local function activateShortcut()
			activate(nil, nil)
		end
		local function shortcutActive(use)
			local input = ctx.config.services.UserInputService
			return isEnabled(use)
				and node.Visible
				and node.Parent ~= nil
				and (not input or not input:GetFocusedTextBox())
		end
		local guiService = ctx.config.services.GuiService
		local lazyKeyboard = underline ~= "hover"
		local selectedForKeyboard: Shared.Input<boolean> = false
		local fallbackSelection: ComposeTypes.Value<boolean>?
		local rich = spec.icon ~= nil
			or spec.glyph ~= nil
			or spec.trailingIcon ~= nil
			or spec.image ~= nil
			or spec.row ~= nil
			or spec.subtitle ~= nil
			or spec.hint ~= nil
			or hinted ~= nil
		assert(
			underline == nil or (not rich and spec.compactLabel == nil and spec.shape ~= "circle"),
			"Facet.Button: underline belongs to a text button with no icon, image, row or compactLabel"
		)
		local enabledProperty: Shared.Input<boolean> = if enabledSource then enabledSource else enabledFixed
		local function controlSize(use)
			return heightSize(spec.controlSize, use)
		end
		local defaults: Shared.TextButtonProps = {
			Text = if rich then "" else spec.label or "",
			Size = if dynamic(ctx.config.theme) or dynamic(spec.controlSize) then controlSize else controlSize(),
			AutomaticSize = E.AutomaticSize.XY,
			AutoButtonColor = false,
		}
		local bare = spec.appearance == "bare"
		if bare then
			defaults.Size = D2.new()
			defaults.BackgroundTransparency = 1
		end
		local authored = spec.Size
		local function widthSet(size: UDim2): boolean
			return size.X.Scale > 0 or size.X.Offset > 0
		end
		local liveWidth = spec.AutomaticSize == nil and dynamic(authored)
		local bounded = (
			spec.AutomaticSize == E.AutomaticSize.None
			or spec.AutomaticSize == E.AutomaticSize.Y
			or liveWidth
			or dynamic(spec.AutomaticSize)
			or (spec.AutomaticSize == nil and typeof(authored) == "UDim2" and widthSet(authored))
		)
			and spec.image == nil
			and spec.row == nil
		if bounded and spec.AutomaticSize == nil then
			local wraps = not rich
				and spec.disclose ~= true
				and (spec.TextTruncate == nil or spec.TextTruncate == E.TextTruncate.None)
			if liveWidth then
				defaults.AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
					local size: UDim2 = read<<UDim2>>(assert(authored), use)
					return if widthSet(size) then E.AutomaticSize.Y else E.AutomaticSize.XY
				end
				if wraps then
					defaults.TextWrapped = function(use: ComposeTypes.Use): boolean
						local size: UDim2 = read<<UDim2>>(assert(authored), use)
						return widthSet(size)
					end
				end
			else
				defaults.AutomaticSize = E.AutomaticSize.Y
				if not rich then
					defaults.TextWrapped = wraps
				end
			end
		end
		if enabledProperty ~= true then
			defaults.Selectable = enabledProperty
			defaults.Interactable = enabledProperty
		end
		local p = ctx.props(spec, buttonKeys, defaults)
		local thumb = spec.target == "thumb" and ctx.config.userInputService ~= nil
		local targetFloor: ((ComposeTypes.Use?) -> number)? = if thumb
			then ctx.thumbFloor(if UI.environment ~= nil
				then UI.environment().thumbTarget
				else Compose.formula(function(use: ComposeTypes.Use): number
					return ctx.metric("targetSizes.thumb", use)
				end))
			elseif ctx.config.userInputService ~= nil then ctx.touchFloor()
			else nil
		local effective = if targetFloor then ctx.effectiveInput() else nil
		local leadingArt = icon ~= nil or spec.glyph ~= nil
		local circled = spec.shape == "circle" and (spec.icon ~= nil or spec.glyph ~= nil)
		local hasText = kit.hasText
		local function worded(use: ComposeTypes.Use?): boolean
			if circled or bare then
				return false
			end
			local row = spec.row
			return hasText(spec.label, use)
				or hasText(spec.subtitle, use)
				or hasText(spec.hint, use)
				or (not rich and hasText(spec.Text, use))
				or (rich and not leadingArt and hasText(spec.name, use))
				or (
					row ~= nil
					and (
						hasText(row.title, use)
						or hasText(row.description, use)
						or (row.value ~= nil and row.value ~= "")
					)
				)
		end
		local function touching(use: ComposeTypes.Use?): boolean
			return effective ~= nil and effective(use) == "Touch"
		end
		local function plateFloor(use: ComposeTypes.Use?): number
			local floor = targetFloor
			if floor == nil or not ((thumb and touching(use)) or worded(use)) then
				return 0
			end
			return floor(use)
		end
		local function reachFloor(use: ComposeTypes.Use?): number
			local floor = targetFloor
			if floor == nil or thumb or not touching(use) or worded(use) then
				return 0
			end
			return floor(use)
		end
		local constrainedCaption = bounded
			and not dynamic(spec.AutomaticSize)
			and spec.label ~= nil
			and spec.label ~= ""
			and spec.shape ~= "circle"
			and (spec.AutomaticSize == nil or rich)
		local function targetWidth(minimum: number, use: ComposeTypes.Use?): number
			return if spec.target == "inline" then math.min(minimum, ctx.metric("targetSizes.inline", use)) else minimum
		end
		if constrainedCaption then
			p[#p + 1] = Host.UISizeConstraint {
				MinSize = function(use: ComposeTypes.Use): Vector2
					local package = read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
					local skin = package and package.chrome and package.chrome.control
					local carve: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
					local minimum = plateFloor(use)
					local leadingGlyph, trailingGlyph = read(spec.icon, use), read(spec.trailingIcon, use)
					local glyphs = (if spec.glyph or (leadingGlyph ~= nil and leadingGlyph ~= "") then 1 else 0)
						+ (if trailingGlyph ~= nil and trailingGlyph ~= "" then 1 else 0)
					local glyphSide = ctx.controlSize(
						if spec.controlSize ~= nil then spec.controlSize else ctx.config.controlSize,
						"iconSize",
						use
					)
					local caption = read(spec.label, use)
					local captioned = caption ~= nil and caption ~= ""
					local content = if captioned
						then ctx.metric("typography.control.size", use) + glyphs * (glyphSide + contentGap)
						else glyphs * glyphSide + math.max(0, glyphs - 1) * contentGap
					return V2.new(
						math.max(
							targetWidth(minimum, use),
							2 * ctx.controlSize(spec.controlSize, "paddingX", use)
								+ (carve.left or 0)
								+ (carve.right or 0)
								+ content
						),
						minimum
					)
				end,
			}
		end
		if not rich and p.TextTruncate == nil then
			local automatic = p.AutomaticSize
			local function truncate(use: ComposeTypes.Use?): Enum.TextTruncate
				local sizing = read(automatic, use)
				return if sizing == E.AutomaticSize.X or sizing == E.AutomaticSize.XY
					then E.TextTruncate.None
					else E.TextTruncate.AtEnd
			end
			p.TextTruncate = if dynamic(automatic) then truncate else truncate()
		end
		local engaged = if underline == "hover" then Compose.cell(false) else nil
		local fillsGlyph = false
		if underline ~= nil then
			p.RichText = true
			p.Text = function(use: ComposeTypes.Use): string
				local words = escapeRich(tostring(read(spec.label, use) or ""))
				return if underline == "always" or use(assert(engaged)) then `<u>{words}</u>` else words
			end
		end
		local function activated(input: InputObject, clicks: number)
			if not repeated then
				activate(input, clicks)
			end
			repeated = false
			if spec.Activated then
				spec.Activated(input, clicks)
			end
		end
		local press: (InputObject, number) -> () = if repeatable or spec.Activated then activated else activate
		p.Activated = press

		if spec.Size ~= nil and spec.shape ~= "circle" then
			local given = spec.Size
			local sizing = spec.AutomaticSize
			local function floored(use: ComposeTypes.Use?): UDim2
				local size: UDim2 = read<<UDim2>>(given, use)
				local automatic = if sizing == nil then E.AutomaticSize.Y else read(sizing, use)
				local grows = automatic == E.AutomaticSize.Y or automatic == E.AutomaticSize.XY
				if grows and size.Y.Scale == 0 and size.Y.Offset == 0 then
					return D2.new(size.X.Scale, size.X.Offset, 0, ctx.controlSize(spec.controlSize, "height", use))
				end
				return size
			end
			p.Size = if dynamic(given)
					or dynamic(sizing)
					or dynamic(spec.controlSize)
					or dynamic(ctx.config.theme)
				then floored
				else floored()
		end
		if spec.shape == "circle" then
			if spec.Size == nil then
				p.Size = function(use: ComposeTypes.Use)
					local diameter = ctx.controlSize(spec.controlSize, "height", use)
					return D2.fromOffset(diameter, diameter)
				end
			end
			p.AutomaticSize = E.AutomaticSize.None
			local aspect: EngineTypes.UIAspectRatioConstraintProps = { AspectRatio = 1 }
			local authored = spec.Size
			if authored ~= nil and not dynamic(authored) then
				local size: UDim2 = read<<UDim2>>(authored)
				local wide = size.X.Scale ~= 0 or size.X.Offset ~= 0
				local tall = size.Y.Scale ~= 0 or size.Y.Offset ~= 0
				if wide ~= tall then
					aspect.AspectType = E.AspectType.ScaleWithParentSize
					aspect.DominantAxis = if wide then E.DominantAxis.Width else E.DominantAxis.Height
				end
			end
			p[#p + 1] = Host.UIAspectRatioConstraint(aspect)
			p[#p + 1] = Host.UICorner { CornerRadius = ctx.round }
		elseif spec.corners then
			p[#p + 1] = Host.UICorner { CornerRadius = if dynamic(spec.corners) then cornerRadius else cornerRadius() }
		end
		if spec.busy ~= nil then
			p[#p + 1] = Host.UIPadding {
				PaddingRight = function(use: ComposeTypes.Use): UDim
					if read(spec.busy, use) ~= true then
						return D.new(0, 0)
					end
					local package = read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
					local skin = package and package.chrome and package.chrome.control
					return D.new(0, 32 + (if skin and skin.contentInsets then skin.contentInsets.right or 0 else 0))
				end,
			}
			p[#p + 1] = Compose.show(function(use: ComposeTypes.Use)
				return read(spec.busy, use) == true
			end, function()
				local phase =
					runtime.timeline({ duration = ctx.metric("motion.durations.busyLoop"), repeats = math.huge })
				local dotsReduced = reducedMotion(ctx)
				local dots: Shared.FrameProps = {
					Name = "Busy",
					Size = D2.fromOffset(18, 18),
					AnchorPoint = V2.new(0, 0.5),
					Position = D2.new(1, 5, 0.5, 0),
					BackgroundTransparency = 1,
					ZIndex = 2,
				}
				for index = 1, 3 do
					dots[#dots + 1] = ctx.styled(
						Host.Frame(`Dot{index}`)({
							Size = D2.fromOffset(4, 4),
							Position = D2.fromOffset((index - 1) * 6, 7),
							BorderSizePixel = 0,
							BackgroundTransparency = function(use: ComposeTypes.Use)
								return if dotsReduced(use)
									then 0
									else 0.2 + 0.6 * ((use(phase.progress) + index / 3) % 1)
							end,
							ctx.corner(2),
						}),
						"fill"
					)
				end
				local busy = Host.Frame(dots)
				ctx.playWhileShown(phase, busy)
				return busy
			end)
		end
		local inputHint: GuiObject? = nil
		local corner = spec.shape == "circle"
		if hinted then
			local effective = ctx.effectiveInput()
			local live, binding = ctx.observe.Enabled(hinted), ctx.observe.PreferredBinding(hinted)
			local function cornerSize(use: ComposeTypes.Use): Shared.ControlSize
				return SMALLER[read<<Shared.ControlSize?>>(spec.controlSize, use) or "regular"]
			end
			inputHint = UI.ShortcutHint({
				Name = "ShortcutHint",
				action = hinted,
				cap = false,
				controlSize = if corner then cornerSize else spec.controlSize,
				AnchorPoint = if corner then V2.new(0.5, 0.5) else nil,
				Position = if corner then D2.fromScale(RIM, RIM) else nil,
				ZIndex = if corner then 2 else nil,
				Visible = function(use: ComposeTypes.Use): boolean
					if effective(use) == "Touch" or use(live) == false then
						return false
					end
					return if use(binding) then true else false
				end,
			})
		end
		local rowHint = if corner then nil else inputHint
		local markRow: ((GuiObject) -> ())? = nil
		if rich then
			fillsGlyph, markRow = buttonContent(ctx, kit, spec, p, iconState, bounded, sized, rowHint)
		end
		local captionFits = if ctx.config.theme ~= nil then Compose.cell(true) else nil
		local keyboardAttached = false
		local hapticSwitch = p.PressHapticEffect == nil and dynamic(spec.haptic)
		if p.PressHapticEffect == nil and not hapticSwitch then
			local effect = ctx.haptic(read(spec.haptic))
			if effect then
				p.PressHapticEffect = Compose.static(effect)
			end
		end
		node = ctx.styled(Host.TextButton(p), "button")
		if fillsGlyph then
			node:AddTag("facet-button-glyph")
		end
		if rich and spec.image ~= nil then
			node:AddTag("facet-button-media")
		end
		if markRow then
			markRow(node)
		end
		activation.mark(node)
		Compose.cleanup(activation.provide(node, activate))
		if spec.caption ~= nil then
			local caption = ctx.text({
				Name = "Caption",
				Text = spec.caption,
				AutomaticSize = E.AutomaticSize.XY,
				AnchorPoint = V2.new(0.5, 0),
				Position = function(use: ComposeTypes.Use): UDim2
					return D2.new(0.5, 0, 1, ctx.metric("space.xs", use))
				end,
			})
			ctx.textRole(caption, "caption")
			caption:AddTag("facet-button-outside")
			node.ClipsDescendants = false
			caption.Parent = node
		end
		if inputHint and corner then
			inputHint:AddTag("facet-button-outside")
			node.ClipsDescendants = false
			inputHint.Parent = node
		end
		if not rich then
			sized(node, spec.textSize)
			if spec.shape ~= "circle" then
				local owner = assert(Compose.currentOwner())
				local detach: ComposeTypes.Dispose?
				local attached = false
				local function attach()
					local grows = node.AutomaticSize
					if attached or grows == E.AutomaticSize.X or grows == E.AutomaticSize.XY then
						return
					end
					attached = true
					if detach then
						detach()
						detach = nil
					end
					Compose.withOwner(owner, function()
						local sizing = ctx.observe.AutomaticSize(node)
						runtime.mountFragment(function()
							return {
								Compose.show(function(use: ComposeTypes.Use)
									local grows = use(sizing)
									return grows ~= E.AutomaticSize.X and grows ~= E.AutomaticSize.XY
								end, function()
									local words = ctx.observe.Text(node)
									return Compose.show(function(use: ComposeTypes.Use)
										return use(words) ~= ""
									end, function()
										local fits, box = ctx.observe.TextFits(node), ctx.observe.AbsoluteSize(node)
										local measured: string? = nil
										Compose.watch(function(use: ComposeTypes.Use)
											use(box)
											use(fits)
											local width, whole =
												node.AbsoluteSize.X,
												node.TextFits and (captionFits == nil or use(captionFits))
											if not node:HasTag("facet-button-tight") and (whole or width <= 0) then
												return
											end
											local points, face =
												ctx.observeStyled.TextSize(node), ctx.observeStyled.FontFace(node)
											local metrics = `{width}|{use(words)}|{use(points)}|{use(face)}`
											if metrics ~= measured and node:HasTag("facet-button-tight") then
												measured = metrics
												local drawn = node.TextBounds.X
												local unit = 1
												local at: Instance? = node
												while at do
													local transform = at:FindFirstChildWhichIsA("UIScale")
													if transform then
														unit *= transform.Scale
													end
													at = at.Parent
												end
												local package =
													read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use)
												local skin = package and package.chrome and package.chrome.control
												local carve: ThemeTypes.Insets = if skin
													then skin.contentInsets or {}
													else {}
												local padding = (
													2 * ctx.controlSize(spec.controlSize, "paddingX", use)
													+ (carve.left or 0)
													+ (carve.right or 0)
												) * unit
												if drawn == 0 or (whole and drawn + padding <= width) then
													node:RemoveTag("facet-button-tight")
												end
											end
											if not whole and width > 0 and not node:HasTag("facet-button-tight") then
												measured = metrics
												node:AddTag("facet-button-tight")
											end
										end)
										Compose.cleanup(function()
											node:RemoveTag("facet-button-tight")
										end)
										return idle
									end)
								end),
							}
						end, node)
					end)
				end
				detach =
					Compose.cleanup(assert(runtime.host.observation).observeProperty(node, "AutomaticSize", attach))
				attach()
			end
		end
		if hapticSwitch then
			local appliedHaptic: HapticEffect? = nil
			local hapticApplied = false
			Compose.watch(function(use: ComposeTypes.Use)
				local effect = ctx.haptic(read(spec.haptic, use))
				if not hapticApplied or effect ~= appliedHaptic then
					hapticApplied, appliedHaptic = true, effect
					runtime.host.render.setProperty(node, "PressHapticEffect", effect)
				end
			end)
		end
		if rich and (spec.subtitle ~= nil or spec.hint ~= nil or (spec.row ~= nil and spec.row.description ~= nil)) then
			local row: InputTypes.Row = spec.row or {}
			local described = row.description or spec.subtitle or spec.hint
			Compose.watch(function(use: ComposeTypes.Use)
				if kit.hasText(described, use) then
					node:AddTag("facet-button-described")
				else
					node:RemoveTag("facet-button-described")
				end
			end)
		end
		assert(spec.disclose == nil or type(spec.disclose) == "boolean", "Facet.Button: disclose must be a boolean")
		local fits: ComposeTypes.ReadOnlyValue<boolean>? = nil
		if spec.disclose then
			local title = node:FindFirstChild("Title", true)
			local textFits = ctx.observe.TextFits(if title and title:IsA("TextLabel") then title else node)
			fits = textFits
			help.attach(ctx, node, spec.label or "", {
				name = "Disclosure",
				gate = function(use: ComposeTypes.Use): boolean
					return not use(textFits)
				end,
			})
		end
		if spec.help ~= nil then
			help.attach(ctx, node, spec.help, if fits then { gate = fits } else nil)
		end
		local owner = assert(Compose.currentOwner(), "Facet.Button requires a Compose owner")
		local selectionWired = false
		local function selectedLazily(...: boolean)
			local selected = ... ~= false
			if not guiService then
				if fallbackSelection then
					fallbackSelection:set(selected)
				else
					local source = Compose.cell(selected)
					fallbackSelection = source
					selectedForKeyboard = source
				end
			end
			if selectionWired or ComposeTypes.owner.isDisposed(owner) then
				return
			end
			selectionWired = true
			Compose.withOwner(owner, function()
				if guiService then
					local selected = ctx.selection.observe()
					selectedForKeyboard = function(use: ComposeTypes.Use): boolean
						return use(selected) == node
					end
				else
					runtime.connect(node, "SelectionLost", function()
						assert(fallbackSelection):set(false)
					end)
				end
				local function attachKeyboard()
					ctx.action(node, "Activate", { E.KeyCode.Return }, function(use: ComposeTypes.Use)
						local input = ctx.config.services.UserInputService
						return read(selectedForKeyboard, use) == true
							and isEnabled(use)
							and node.Visible
							and node.Parent ~= nil
							and (not input or not input:GetFocusedTextBox())
					end, function()
						activate(nil, nil)
					end, {
						priority = 5000,
						conditional = { binding = E.KeyCode.Space, when = ctx.spaceActivates(node) },
					})
				end
				if enabledLive or not lazyKeyboard then
					Compose.watch(function(use: ComposeTypes.Use)
						if not keyboardAttached and read(selectedForKeyboard, use) == true and isEnabled(use) then
							keyboardAttached = true
							Compose.withOwner(owner, attachKeyboard)
						end
					end)
				elseif isEnabled() then
					keyboardAttached = true
					attachKeyboard()
				end
			end)
		end
		if guiService then
			if lazyKeyboard then
				ctx.whenSelected(guiService, node, selectedLazily)
			else
				selectedLazily()
			end
		else
			if not lazyKeyboard then
				selectedLazily(false)
			end
			runtime.connect(node, "SelectionGained", selectedLazily)
		end
		if underline == "hover" then
			local state = ctx.observe.GuiState(node)
			Compose.watch(function(use: ComposeTypes.Use)
				local now = use(state)
				assert(engaged):set(
					now == E.GuiState.Hover or now == E.GuiState.Press or read(selectedForKeyboard, use) == true
				)
			end)
		end
		if not rich and ctx.config.theme ~= nil then
			local function needsCaption(use)
				return captioned(read<<ThemeTypes.ReadOnlyThemePackage?>>(ctx.config.theme, use))
			end
			local function caption()
				Compose.cleanup(function()
					node:RemoveTag("facet-button-captioned")
				end)
				local labelProps: Shared.TextLabelNativeProps = {
					Name = "Label",
					Size = D2.fromScale(1, 1),
					AutomaticSize = E.AutomaticSize.None,
					ZIndex = 1,
					Text = ctx.observe.Text(node),
					TextColor3 = ctx.observeStyled.TextColor3(node),
					FontFace = ctx.observeStyled.FontFace(node),
					TextSize = ctx.observeStyled.TextSize(node),
					TextXAlignment = ctx.observeStyled.TextXAlignment(node),
					TextYAlignment = ctx.observeStyled.TextYAlignment(node),
					TextWrapped = ctx.observeStyled.TextWrapped(node),
					RichText = ctx.observeStyled.RichText(node),
					TextScaled = ctx.observeStyled.TextScaled(node),
					TextTruncate = ctx.observeStyled.TextTruncate(node),
					LineHeight = ctx.observeStyled.LineHeight(node),
				}
				local label = ctx.styled(ctx.text(labelProps), "button-caption")
				local fits, size = ctx.observe.TextFits(label), ctx.observe.AbsoluteSize(label)
				Compose.watch(function(use: ComposeTypes.Use)
					use(size)
					use(fits)
					assert(captionFits):set(not needsCaption(use) or label.TextFits)
				end)
				local boundary = decoration(Compose, runtime, ctx.types, node, label, { inset = true })
				Compose.watch(function(use: ComposeTypes.Use)
					local visible = needsCaption(use)
					boundary.Visible = visible
					if visible then
						node:AddTag("facet-button-captioned")
					else
						node:RemoveTag("facet-button-captioned")
					end
				end)
				return boundary
			end
			if Compose.isValue(ctx.config.theme) or type(ctx.config.theme) == "function" then
				ctx.whenTheme("caption", captioned, function()
					runtime.mount(caption, node)
				end)
			elseif needsCaption() then
				runtime.mount(caption, node)
			end
		end
		if spec.compactLabel then
			assert(not rich, "Facet.Button: compactLabel requires a text button")
			local size = ctx.observe.AbsoluteSize(node)
			local measure: TextLabel
			runtime.mount(function()
				measure = ctx.text({
					Name = "FullLabelMeasure",
					Text = spec.label,
					FontFace = ctx.observeStyled.FontFace(node),
					TextSize = ctx.observeStyled.TextSize(node),
					Visible = false,
					TextWrapped = false,
					AutomaticSize = E.AutomaticSize.XY,
				})
				return measure
			end, node)
			local unit = ctx.layoutUnit(node)
			local bounds = ctx.observe.TextBounds(measure)
			local automatic = ctx.observe.AutomaticSize(node)
			local parent = ctx.observe.Parent(node)
			local available = Compose.cell(0)
			Compose.watch(function(use: ComposeTypes.Use)
				local holder = use(parent)
				if holder and (holder:IsA("GuiObject") or holder:IsA("ScreenGui")) then
					local box = ctx.observe.AbsoluteSize(holder)
					Compose.watch(function(inner: ComposeTypes.Use)
						available:set(inner(box).X)
					end)
				else
					available:set(0)
				end
			end)
			runtime.decorate(node, {
				Text = function(use: ComposeTypes.Use)
					local mode, scale = use(automatic), use(unit)
					local automaticWidth = mode == E.AutomaticSize.X or mode == E.AutomaticSize.XY
					local width = if automaticWidth and use(available) > 0
						then use(available) / scale
						else use(size).X / scale
					local compact = width > 0
						and use(bounds).X / scale > width - 2 * ctx.controlSize(spec.controlSize, "paddingX", use)
					return read(if compact then spec.compactLabel else spec.label, use)
				end,
			})
		end

		if not kit.unskinned[spec] then
			local function skin(use: ComposeTypes.Use?)
				ctx.skin(node, "control", {
					emphasis = read(spec.appearance, use) == "emphasis",
					selected = spec.selected,
					disabled = function(use: ComposeTypes.Use)
						return not isEnabled(use)
					end,
				})
			end
			local function plated(use: ComposeTypes.Use?): boolean
				local appearance = read<<string?>>(spec.appearance, use)
				return appearance ~= "utility"
					and appearance ~= "link"
					and appearance ~= "bare"
					and read(spec.BackgroundTransparency, use) ~= 1
			end
			if dynamic(spec.appearance) or dynamic(spec.BackgroundTransparency) then
				Compose.watch(function(use: ComposeTypes.Use)
					if plated(use) then
						skin(use)
					end
				end)
			elseif plated() then
				skin()
			end
		end

		local guiState = if iconState then ctx.observe.GuiState(node) else nil
		local previousTags: { [string]: true? } = {}
		local previousAttributes: { [string]: boolean | string } = {}
		local initialized = false
		local previousRung: Shared.ControlSize? = nil
		local function tag(name: string, active: boolean)
			if (previousTags[name] == true) ~= active then
				previousTags[name] = if active then true else nil
				if active then
					node:AddTag(name)
				else
					node:RemoveTag(name)
				end
			end
		end
		local setAttribute = node.SetAttribute
		local function attribute(name: string, value: boolean | string)
			if not initialized or previousAttributes[name] ~= value then
				previousAttributes[name] = value
				setAttribute(node, name, value)
			end
		end
		local function updateState(use)
			local selected, busy = read(spec.selected, use) == true, read(spec.busy, use) == true
			local available = isEnabled(use)
			local role, appearance =
				read<<InputTypes.ButtonRole?>>(spec.role, use) or "default",
				read<<string?>>(spec.appearance, use) or "standard"
			local roleChanged = not initialized or previousAttributes.role ~= role
			local appearanceChanged = not initialized or previousAttributes.appearance ~= appearance
			assert(roles[role], "Facet.Button: invalid semantic role")
			if not initialized then
				for _, name in node:GetTags() do
					previousTags[name] = true
				end
			end
			if iconState then
				local state = read(guiState, use)
				local visualState: ThemeTypes.SkinState = if not available
					then "disabled"
					elseif state == E.GuiState.Press then "pressed"
					elseif state == E.GuiState.Hover then "hover"
					elseif selected then "selected"
					else "default"
				iconState:set(visualState)
			end
			if roleChanged then
				for name: string, tagName in roleTags do
					tag(tagName, role == name)
				end
			end
			tag("facet-selected", selected)
			tag("facet-busy", busy)
			if not initialized then
				tag("facet-shape-circle", spec.shape == "circle")
			end
			tag("facet-disabled", not available)
			if appearanceChanged then
				tag("facet-accent", appearance == "emphasis")
				tag("facet-appearance-soft", appearance == "soft")
				tag("facet-appearance-utility", appearance == "utility")
				tag("facet-appearance-link", appearance == "link")
				tag("facet-appearance-bare", appearance == "bare")
				tag("facet-appearance-inverse", appearance == "inverse")
			end
			if roleChanged or appearanceChanged then
				tag(
					"facet-quiet-destructive",
					role == "destructive" and (appearance == "utility" or appearance == "link")
				)
			end
			local rung = read<<Shared.ControlSize?>>(spec.controlSize, use)
			if not initialized or previousRung ~= rung then
				for index, name in CONTROL_RUNGS do
					tag(rungTags[index], rung == name)
				end
				previousRung = rung
			end
			attribute("selected", selected)
			attribute("busy", busy)
			attribute("appearance", appearance)
			attribute("controlSize", rung or "regular")
			attribute("role", role)
			attribute("label", read<<string?>>(spec.name or spec.label or "", use) or "")
			initialized = true
		end
		local stateIsDynamic = iconState ~= nil
			or dynamic(spec.selected)
			or dynamic(spec.busy)
			or dynamic(spec.enabled)
			or dynamic(spec.disabled)
			or dynamic(spec.role)
			or dynamic(spec.appearance)
			or dynamic(spec.controlSize)
			or dynamic(spec.name)
			or dynamic(spec.label)
		if stateIsDynamic then
			Compose.watch(updateState)
		else
			updateState()
		end
		local pressBegan: ((InputObject) -> ())? = nil
		local pressEnded: ((InputObject) -> ())? = nil
		local pressCancelled: (() -> ())? = nil
		if repeatable or spec.onPointerDown or spec.onPointerUp or spec.onPointerCancel then
			local stopFrame: (() -> ())?
			local function release()
				held = false
				if stopFrame then
					stopFrame()
					stopFrame = nil
				end
			end
			local function cancel()
				local wasHeld = held
				release()
				if wasHeld and spec.onPointerCancel then
					spec.onPointerCancel()
				end
			end
			local function startRepeat()
				if stopFrame or not repeatable then
					return
				end
				stopFrame = kit.repeatHeld(assert(runtime.host.frames), repeatDelay, repeatInterval, function(): boolean
					if not held or not isEnabled() or not ctx.available(node) then
						release()
						return false
					end
					return true
				end, function()
					repeated = true
					activateShortcut()
				end)
			end
			Compose.cleanup(cancel)
			runtime.connect(node, "Destroying", cancel)
			local function began(input: InputObject)
				local kind = input.UserInputType.Name
				if
					isEnabled()
					and (
						kind == "MouseButton1"
						or kind == "Touch"
						or input.KeyCode == E.KeyCode.ButtonA
						or input.KeyCode == E.KeyCode.Return
						or input.KeyCode == E.KeyCode.Space
					)
				then
					held, repeated = true, false
					startRepeat()
					local pointerDown = spec.onPointerDown
					if pointerDown then
						pointerDown(input)
					end
				end
			end
			local function ended(input: InputObject)
				if held then
					release()
					local pointerUp = spec.onPointerUp
					if pointerUp then
						pointerUp(input)
					end
				end
			end
			pressBegan, pressEnded, pressCancelled = began, ended, cancel
			runtime.connect(node, "InputBegan", began)
			runtime.connect(node, "InputEnded", ended)
			runtime.connect(node, "MouseLeave", cancel)
		end

		local bindings: { Shared.InputBindingNativeProps } = {}
		if spec.shortcut then
			local shortcut = spec.shortcut
			assert(
				shortcut.keyCode ~= "Escape" and shortcut.keyCode ~= "Tab",
				"Facet.Button: Escape and Tab retain native navigation ownership"
			)
			local modifiers: { shift: boolean? } = shortcut.modifiers or {}
			local shifts: { Enum.KeyCode } = if modifiers.shift
				then { E.KeyCode.LeftShift, E.KeyCode.RightShift }
				else { noKey }
			for _, shift in shifts do
				bindings[#bindings + 1] =
					{ KeyCode = assert(E.KeyCode:FromName(shortcut.keyCode)), PrimaryModifier = shift }
			end
		end
		if spec.dialogAction then
			local key = if spec.dialogAction == "default" then E.KeyCode.Return else E.KeyCode.ButtonB
			local duplicate = false
			for _, binding in bindings do
				if binding.KeyCode == key and binding.PrimaryModifier == noKey then
					duplicate = true
				end
			end
			if not duplicate then
				bindings[#bindings + 1] = { KeyCode = key }
			end
		end
		if #bindings > 0 then
			local modified = spec.shortcut ~= nil
				and spec.shortcut.modifiers ~= nil
				and spec.shortcut.modifiers.shift == true
			local priority = if modified then 2001 else 2000
			if spec.dialogAction then
				dialogOrder += 1
				priority -= dialogOrder
			end
			ctx.action(node, "Shortcut", bindings, shortcutActive, activateShortcut, {
				priority = priority,
				sink = spec.dialogAction ~= nil or modified,
			})
		end
		if targetFloor and not constrainedCaption then
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use): boolean
						return plateFloor(use) > 0
					end, function()
						local extra = sizeFloor.of(node, Compose.cell)
						return Host.UISizeConstraint "TargetFloor" {
							MinSize = function(use: ComposeTypes.Use): Vector2
								local minimum = plateFloor(use)
								return V2.new(
									math.max(targetWidth(minimum, use), use(extra.x)),
									math.max(minimum, use(extra.y))
								)
							end,
						}
					end),
				}
			end, node)
		end
		if targetFloor then
			local function reached(input: InputObject, clicks: number)
				local layer = node:FindFirstAncestorWhichIsA("LayerCollector")
				local host = if layer then layer:FindFirstAncestorWhichIsA("BasePlayerGui") else nil
				if host and input then
					local point = input.Position
					for _, hit in (host :: BasePlayerGui):GetGuiObjectsAtPosition(point.X, point.Y) do
						if node:IsDescendantOf(hit) then
							break
						elseif
							hit ~= node
							and not hit:IsDescendantOf(node)
							and activation.marked(hit)
							and activation.trigger(hit, input, clicks)
						then
							return
						end
					end
				end
				press(input, clicks)
			end
			local function hitTarget(margin: ComposeTypes.ReadOnlyValue<Vector2>): GuiObject | ComposeTypes.Directive
				local function strip(name: string, anchor: Vector2, at: UDim2, band: boolean): TextButton
					local props: Shared.TextButtonProps = {
						Text = "",
						BackgroundTransparency = 1,
						AutoButtonColor = false,
						Selectable = false,
						Interactable = enabledProperty,
						AnchorPoint = anchor,
						Position = at,
						Size = function(use: ComposeTypes.Use): UDim2
							local gap = use(margin)
							return if band then D2.new(1, 2 * gap.X, 0, gap.Y) else D2.new(0, gap.X, 1, 0)
						end,
						Visible = function(use: ComposeTypes.Use): boolean
							local gap = use(margin)
							return (if band then gap.Y else gap.X) > 0
						end,
						Activated = reached,
					}
					local made = Host.TextButton(name)(props)
					local began, ended, cancelled = pressBegan, pressEnded, pressCancelled
					if began and ended and cancelled then
						runtime.connect(made, "InputBegan", began)
						runtime.connect(made, "InputEnded", ended)
						runtime.connect(made, "MouseLeave", cancelled)
					end
					return made
				end
				local strips = {
					strip("HitTop", V2.new(0.5, 1), D2.fromScale(0.5, 0), true),
					strip("HitBottom", V2.new(0.5, 0), D2.fromScale(0.5, 1), true),
					strip("HitLeading", V2.new(1, 0.5), D2.fromScale(0, 0.5), false),
					strip("HitTrailing", V2.new(0, 0.5), D2.fromScale(1, 0.5), false),
				}
				if spec.busy == nil then
					return Compose.fragment(function()
						return strips
					end)
				end
				local area = Host.Frame "HitTarget" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					table.unpack(strips),
				}
				return decoration(Compose, runtime, ctx.types, node, area)
			end
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use): boolean
						return reachFloor(use) > 0
					end, function()
						local moved = Compose.cell(0)
						runtime.connect(node, "AncestryChanged", function()
							moved:set(moved:peek() + 1)
						end)
						local holder = Compose.formula(function(use: ComposeTypes.Use): GuiBase2d?
							use(moved)
							local parent = node.Parent
							if
								parent
								and parent:IsA("GuiBase2d")
								and (parent:IsA("LayerCollector") or parent:FindFirstAncestorWhichIsA("LayerCollector"))
							then
								return parent
							end
							return nil
						end)
						local unit = Compose.cell(1)
						Compose.watch(function(use: ComposeTypes.Use)
							local parent = use(holder)
							if parent then
								local measured = ctx.layoutUnit(parent)
								Compose.watch(function(inner: ComposeTypes.Use)
									unit:set(inner(measured))
								end)
							end
						end)
						local plate = ctx.layoutSize(node, unit)
						local margin = Compose.formula(function(use: ComposeTypes.Use): Vector2
							local size, floor = use(plate), reachFloor(use)
							return V2.new(
								math.max(0, (targetWidth(floor, use) - size.X) / 2),
								math.max(0, (floor - size.Y) / 2)
							)
						end)
						return Compose.show(function(use: ComposeTypes.Use): boolean
							local gap = use(margin)
							return gap.X > 0 or gap.Y > 0
						end, function()
							return hitTarget(margin)
						end)
					end),
				}
			end, node)
		end

		if popTimeline then
			feedbackPaint(
				ctx,
				node,
				Host.UIScale "Pop" { Scale = popScale },
				{ Size = p.Size, AutomaticSize = p.AutomaticSize }
			)
		end
		if spec.cooldown ~= nil or spec.charges ~= nil then
			require("./input_button_cooldown")(ctx, node, spec.cooldown, spec.charges)
		end
		return node
	end)
end
