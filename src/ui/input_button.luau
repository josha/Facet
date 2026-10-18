--!strict
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
	local dialogOrder = 0
	local roles: { [string]: boolean } = { default = true, cancel = true, destructive = true, onIndicator = true }
	local roleTags: { [string]: string } = {}
	for name in roles do
		roleTags[name] = "facet-role-" .. name
	end
	local contentGap = 8

	local buttonKeys = table.freeze({
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
		"trailingIcon",
		"image",
		"imageAspectRatio",
		"imageFraming",
		"subtitle",
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
	local rungTags: { string } = {}
	for index, name in CONTROL_RUNGS do
		rungTags[index] = "facet-size-" .. name
	end
	local escapeRich = richText.escape
	UI.Button = ctx.construct("Button", function(spec: InputProps.ButtonProps): TextButton
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
		local declaredSize = read(spec.textSize)
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
		local popSeconds = ctx.metric("motion.durations.buttonPop")
		local popTimeline = if spec.pop then runtime.timeline({ duration = popSeconds, autoplay = false }) else nil
		local popReduced = if popTimeline then reducedMotion(ctx) else nil
		local popStart = Compose.cell(1)
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
					+ (use(popStart) - 1) * (1 - present(phase))
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
		local iconState: ComposeTypes.Cell<ThemeTypes.SkinState>?
		if
			(spec.icon or spec.trailingIcon)
			and (
				ctx.iconVaries(spec.icon or (spec.row and spec.row.icon))
				or ctx.iconVaries(spec.trailingIcon)
				or (spec.row ~= nil and spec.onActivate ~= nil and ctx.iconVaries("chevron.trailing"))
			)
		then
			local initial: ThemeTypes.SkinState = "default"
			iconState = Compose.cell(initial)
		end
		local held, repeated, elapsed = false, false, 0
		local repeatDelay, repeatInterval =
			spec.repeatDelay or kit.repeatDelay, spec.repeatInterval or kit.repeatInterval
		assert(
			repeatDelay > 0 and repeatDelay < math.huge and repeatInterval > 0 and repeatInterval < math.huge,
			"Facet.Button: repeat timings must be finite and positive"
		)
		local function activate(...)
			local pressed: Instance? = node
			if
				activation.consumed((...))
				or (pressed and (help.consume(pressed) or activation.intercepted(pressed, (...))))
			then
				return
			end
			local route = if node then ctx.shiftActivation(node, (...)) else nil
			if route and enabled(spec) and ctx.available(node) then
				route()
				return
			end
			local live = enabled(spec)
			if live and node and ctx.available(node) and spec.onActivate then
				if popTimeline and popScale and popReduced and not held and not popReduced() then
					popStart:set(popScale:peek())
					popTimeline:restart()
				end
				spec.onActivate(...)
			end
			if live and node and ctx.available(node) then
				activation.notify(node, ...)
			end
		end
		local function shortcutActive(use)
			local input = ctx.config.services.UserInputService
			return enabled(spec, use)
				and node.Visible
				and node.Parent ~= nil
				and (not input or not input:GetFocusedTextBox())
		end
		local guiService = ctx.config.services.GuiService
		local lazyKeyboard = underline ~= "hover"
		local enabledLive = dynamic(spec.enabled) or dynamic(spec.disabled) or dynamic(spec.busy)
		local selectedForKeyboard: Shared.Value<boolean>
		local fallbackSelection: ComposeTypes.Cell<boolean>?
		local function observeSelection(): Shared.Value<boolean>
			local selected = ctx.observe.SelectedObject(assert(guiService))
			return function(use: ComposeTypes.Use)
				local target = use(selected)
				return node and target == node or false
			end
		end
		if guiService then
			selectedForKeyboard = if lazyKeyboard then false else observeSelection()
		else
			fallbackSelection = Compose.cell(false)
			selectedForKeyboard = assert(fallbackSelection)
		end
		local rich = spec.icon ~= nil
			or spec.glyph ~= nil
			or spec.trailingIcon ~= nil
			or spec.image ~= nil
			or spec.row ~= nil
			or spec.subtitle ~= nil
			or spec.hint ~= nil
		assert(
			underline == nil or (not rich and spec.compactLabel == nil and spec.shape ~= "circle"),
			"Facet.Button: underline belongs to a text button with no icon, image, row or compactLabel"
		)
		local enabledProperty = if dynamic(spec.enabled)
				or dynamic(spec.disabled)
				or dynamic(spec.busy)
			then function(use: ComposeTypes.Use)
				return enabled(spec, use)
			end
			else enabled(spec)
		local function controlSize(use)
			return D2.fromOffset(0, ctx.controlSize(spec.controlSize, "height", use))
		end
		local defaults: Shared.TextButtonNativeProps = {
			Text = if rich then "" else spec.label or "",
			Size = if dynamic(ctx.config.theme) or dynamic(spec.controlSize) then controlSize else controlSize(),
			AutomaticSize = E.AutomaticSize.XY,
			AutoButtonColor = false,
		}
		local authored = spec.Size
		local function widthSet(size: UDim2): boolean
			return size.X.Scale > 0 or size.X.Offset > 0
		end
		local liveWidth = spec.AutomaticSize == nil and dynamic(authored)
		local bounded = (
			spec.AutomaticSize == E.AutomaticSize.None
			or spec.AutomaticSize == E.AutomaticSize.Y
			or liveWidth
			or (spec.AutomaticSize == nil and typeof(authored) == "UDim2" and widthSet(authored :: UDim2))
		)
			and spec.image == nil
			and spec.row == nil
		if bounded and spec.AutomaticSize == nil then
			local wraps = not rich
				and spec.disclose ~= true
				and (spec.TextTruncate == nil or spec.TextTruncate == E.TextTruncate.None)
			if liveWidth then
				defaults.AutomaticSize = function(use: ComposeTypes.Use): Enum.AutomaticSize
					return if widthSet(read(authored, use) :: UDim2) then E.AutomaticSize.Y else E.AutomaticSize.XY
				end
				if wraps then
					defaults.TextWrapped = function(use: ComposeTypes.Use): boolean
						return widthSet(read(authored, use) :: UDim2)
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
		local constrainedCaption = bounded
			and spec.label ~= nil
			and spec.shape ~= "circle"
			and (spec.AutomaticSize == nil or rich)
		local function targetWidth(minimum: number, use: ComposeTypes.Use?): number
			return if spec.target == "inline" then math.min(minimum, ctx.metric("targetSizes.inline", use)) else minimum
		end
		if constrainedCaption then
			p[#p + 1] = Host.UISizeConstraint({
				MinSize = function(use: ComposeTypes.Use): Vector2
					local package = read(ctx.config.theme, use)
					local skin = package and package.chrome and package.chrome.control
					local carve: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
					local minimum = if targetFloor then targetFloor(use) else 0
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
			})
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
		local engaged = Compose.cell(false)
		local fillsGlyph = false
		if underline ~= nil then
			p.RichText = true
			p.Text = function(use: ComposeTypes.Use): string
				local words = escapeRich(tostring(read(spec.label, use) or ""))
				return if underline == "always" or use(engaged) then `<u>{words}</u>` else words
			end
		end
		local function sized(label: TextLabel | TextButton)
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
					if label:IsA("TextButton") then
						label.TextSize = value
					elseif label:IsA("TextLabel") then
						label.TextSize = value
					end
				end
			end
			if dynamic(spec.textSize) then
				Compose.watch(function(use: ComposeTypes.Use)
					apply(read(spec.textSize, use))
				end)
			elseif spec.textSize ~= nil then
				apply(read(spec.textSize))
			end
		end
		p.Activated = function(...)
			if not repeated then
				activate(...)
			end
			repeated = false
			if spec.Activated then
				spec.Activated(...)
			end
		end

		if spec.Size ~= nil and spec.shape ~= "circle" then
			local given = spec.Size
			local sizing = spec.AutomaticSize
			local function floored(use: ComposeTypes.Use?): UDim2
				local size: UDim2 = read(given, use)
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
				local size = authored :: UDim2
				local wide = size.X.Scale ~= 0 or size.X.Offset ~= 0
				local tall = size.Y.Scale ~= 0 or size.Y.Offset ~= 0
				if wide ~= tall then
					aspect.AspectType = E.AspectType.ScaleWithParentSize
					aspect.DominantAxis = if wide then E.DominantAxis.Width else E.DominantAxis.Height
				end
			end
			p[#p + 1] = Host.UIAspectRatioConstraint(aspect)
			p[#p + 1] = Host.UICorner({ CornerRadius = ctx.round })
		elseif spec.corners then
			p[#p + 1] = Host.UICorner({ CornerRadius = if dynamic(spec.corners) then cornerRadius else cornerRadius() })
		end
		if spec.busy ~= nil then
			p[#p + 1] = Host.UIPadding({
				PaddingRight = function(use: ComposeTypes.Use): UDim
					if read(spec.busy, use) ~= true then
						return D.new(0, 0)
					end
					local package = read(ctx.config.theme, use)
					local skin = package and package.chrome and package.chrome.control
					return D.new(0, 32 + (if skin and skin.contentInsets then skin.contentInsets.right or 0 else 0))
				end,
			})
			p[#p + 1] = Compose.show(function(use: ComposeTypes.Use)
				return read(spec.busy, use) == true
			end, function()
				local phase =
					runtime.timeline({ duration = ctx.metric("motion.durations.busyLoop"), repeats = math.huge })
				local dotsReduced = reducedMotion(ctx)
				local dots: Shared.FrameNativeProps = {
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
		local markRow: ((GuiObject) -> ())? = nil
		if rich then
			fillsGlyph, markRow = buttonContent(ctx, kit, spec, p, iconState, bounded, sized)
		end
		local captionFits = Compose.cell(true)
		local keyboardAttached = false
		local function attachKeyboard()
			ctx.action(
				node,
				"Activate",
				{ E.KeyCode.Return },
				function(use: ComposeTypes.Use)
					return read(selectedForKeyboard, use) == true and shortcutActive(use)
				end,
				activate,
				{ priority = 5000, conditional = { binding = E.KeyCode.Space, when = ctx.spaceActivates(node) } }
			)
		end
		if not lazyKeyboard then
			p[#p + 1] = Compose.show(function(use: ComposeTypes.Use)
				keyboardAttached = keyboardAttached or (read(selectedForKeyboard, use) == true and enabled(spec, use))
				return keyboardAttached
			end, function()
				attachKeyboard()
				return Compose.fragment(function()
					return {}
				end)
			end)
		end
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
		if not rich then
			sized(node)
			if spec.shape ~= "circle" then
				local sizing = ctx.observe.AutomaticSize(node)
				runtime.mountFragment(function()
					return {
						Compose.show(function(use: ComposeTypes.Use)
							local grows = use(sizing)
							return grows ~= E.AutomaticSize.X and grows ~= E.AutomaticSize.XY
						end, function()
							local words = ctx.observe.Text(node)
							local fits, box = ctx.observe.TextFits(node), ctx.observe.AbsoluteSize(node)
							local points, face = ctx.observeStyled.TextSize(node), ctx.observeStyled.FontFace(node)
							local measured: string? = nil
							Compose.watch(function(use: ComposeTypes.Use)
								if use(words) == "" then
									node:RemoveTag("facet-button-tight")
									return
								end
								use(box)
								use(fits)
								local width, whole = node.AbsoluteSize.X, node.TextFits and use(captionFits)
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
									local package = read(ctx.config.theme, use)
									local skin = package and package.chrome and package.chrome.control
									local carve: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
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
							return Compose.fragment(function()
								return {}
							end)
						end),
					}
				end, node)
			end
		end
		if underline == "hover" then
			local state = ctx.observe.GuiState(node)
			Compose.watch(function(use: ComposeTypes.Use)
				local now = use(state)
				engaged:set(
					now == E.GuiState.Hover or now == E.GuiState.Press or read(selectedForKeyboard, use) == true
				)
			end)
		end
		if hapticSwitch then
			Compose.watch(function(use: ComposeTypes.Use)
				node.PressHapticEffect = ctx.haptic(read(spec.haptic, use)) :: HapticEffect
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
		local fits: ComposeTypes.Readable<boolean>? = nil
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
		local function selectedLazily()
			if selectionWired or owner.isDisposed() then
				return
			end
			selectionWired = true
			Compose.withOwner(owner, function()
				if guiService then
					selectedForKeyboard = observeSelection()
				else
					runtime.connect(node, "SelectionLost", function()
						assert(fallbackSelection):set(false)
					end)
				end
				if enabledLive then
					Compose.watch(function(use: ComposeTypes.Use)
						if not keyboardAttached and read(selectedForKeyboard, use) == true and enabled(spec, use) then
							keyboardAttached = true
							Compose.withOwner(owner, attachKeyboard)
						end
					end)
				elseif enabled(spec) then
					keyboardAttached = true
					attachKeyboard()
				end
			end)
		end
		if lazyKeyboard and guiService then
			ctx.whenSelected(guiService, node, selectedLazily)
		elseif not guiService then
			runtime.connect(node, "SelectionGained", function()
				assert(fallbackSelection):set(true)
				if lazyKeyboard then
					selectedLazily()
				end
			end)
			if not lazyKeyboard then
				runtime.connect(node, "SelectionLost", function()
					assert(fallbackSelection):set(false)
				end)
			end
		end
		if not rich and ctx.config.theme ~= nil then
			local function needsCaption(use)
				local package = read(ctx.config.theme, use)
				local recipe = package and package.chrome and package.chrome.control
				return recipe ~= nil and recipe.kind ~= "native" and recipe.kind ~= "none"
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
					captionFits:set(not needsCaption(use) or label.TextFits)
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
			if Compose.isReadable(ctx.config.theme) or type(ctx.config.theme) == "function" then
				local attached = false
				runtime.mountFragment(function()
					return {
						Compose.show(function(use: ComposeTypes.Use)
							attached = attached or needsCaption(use)
							return attached
						end, caption),
					}
				end, node)
			elseif needsCaption() then
				runtime.mount(caption, node)
			end
		end
		if spec.compactLabel then
			assert(not rich, "Facet.Button: compactLabel requires a text button")
			local size = ctx.observeNative.AbsoluteSize(node)
			local measure: TextLabel
			runtime.mount(function()
				measure = ctx.text({
					Name = "FullLabelMeasure",
					Text = spec.label,
					FontFace = ctx.observeStyled.FontFace(node),
					TextSize = ctx.observeStyled.TextSize(node),
					Visible = false,
					TextWrapped = false,
				})
				return measure
			end, node)
			local unit = ctx.layoutUnit(node)
			local bounds = ctx.observeNative.TextBounds(measure)
			local automatic = ctx.observe.AutomaticSize(node)
			local parent = ctx.observe.Parent(node)
			local available = Compose.cell(0)
			local stopParent: (() -> ())? = nil
			local observation = assert(runtime.host.observation)
			Compose.watch(function(use: ComposeTypes.Use)
				if stopParent then
					stopParent()
					stopParent = nil
				end
				local holder = use(parent)
				if holder and (holder:IsA("GuiObject") or holder:IsA("ScreenGui")) then
					local function refresh()
						local box = observation.readProperty(holder, "AbsoluteSize") :: Vector2
						available:set(box.X)
					end
					stopParent = observation.observeProperty(holder, "AbsoluteSize", refresh)
					refresh()
				else
					available:set(0)
				end
			end)
			Compose.cleanup(function()
				if stopParent then
					stopParent()
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
			local function skin()
				ctx.skin(node, "control", {
					selected = spec.selected,
					disabled = function(use: ComposeTypes.Use)
						return not enabled(spec, use)
					end,
				})
			end
			local function plated(use: ComposeTypes.Use?): boolean
				local appearance = read(spec.appearance, use)
				return appearance ~= "utility" and appearance ~= "link" and read(spec.BackgroundTransparency, use) ~= 1
			end
			if dynamic(spec.appearance) or dynamic(spec.BackgroundTransparency) then
				Compose.watch(function(use: ComposeTypes.Use)
					if plated(use) then
						skin()
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
		local function attribute(name: string, value: boolean | string)
			if not initialized or previousAttributes[name] ~= value then
				previousAttributes[name] = value
				node:SetAttribute(name, value)
			end
		end
		local function updateState(use)
			local selected, busy = read(spec.selected, use) == true, read(spec.busy, use) == true
			local available = enabled(spec, use)
			local role, appearance = read(spec.role, use) or "default", read(spec.appearance, use) or "standard"
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
			for name: string, tagName in roleTags do
				tag(tagName, role == name)
			end
			tag("facet-selected", selected)
			tag("facet-busy", busy)
			tag("facet-shape-circle", spec.shape == "circle")
			tag("facet-disabled", not available)
			tag("facet-accent", appearance == "emphasis")
			tag("facet-appearance-soft", appearance == "soft")
			tag("facet-appearance-utility", appearance == "utility")
			tag("facet-appearance-link", appearance == "link")
			tag("facet-appearance-inverse", appearance == "inverse")
			tag("facet-quiet-destructive", role == "destructive" and (appearance == "utility" or appearance == "link"))
			local rung = read(spec.controlSize, use)
			for index, name in CONTROL_RUNGS do
				tag(rungTags[index], rung == name)
			end
			attribute("selected", selected)
			attribute("busy", busy)
			attribute("appearance", appearance)
			attribute("controlSize", rung or "regular")
			attribute("role", role)
			attribute("label", read(spec.name or spec.label or "", use))
			initialized = true
		end
		local stateIsDynamic = iconState ~= nil
		for _, source in
			{
				spec.selected,
				spec.busy,
				spec.enabled,
				spec.disabled,
				spec.role,
				spec.appearance,
				spec.controlSize,
				spec.name,
				spec.label,
			} :: { unknown }
		do
			stateIsDynamic = stateIsDynamic or dynamic(source)
		end
		if stateIsDynamic then
			Compose.watch(updateState)
		else
			updateState()
		end
		if
			spec.repeatDelay
			or spec.repeatInterval
			or spec.onPointerDown
			or spec.onPointerUp
			or spec.onPointerCancel
		then
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
				if stopFrame or not (spec.repeatDelay or spec.repeatInterval) then
					return
				end
				stopFrame = kit.repeatHeld(assert(runtime.host.frames), repeatDelay, repeatInterval, function(): boolean
					if not held or not enabled(spec) or not ctx.available(node) then
						release()
						return false
					end
					return true
				end, function()
					repeated = true
					activate()
				end)
			end
			Compose.cleanup(cancel)
			runtime.connect(node, "Destroying", cancel)
			runtime.connect(node, "InputBegan", function(input)
				local kind = input.UserInputType.Name
				if
					enabled(spec)
					and (
						kind == "MouseButton1"
						or kind == "Touch"
						or input.KeyCode == E.KeyCode.ButtonA
						or input.KeyCode == E.KeyCode.Return
						or input.KeyCode == E.KeyCode.Space
					)
				then
					held, repeated, elapsed = true, false, 0
					startRepeat()
					local pointerDown = spec.onPointerDown
					if pointerDown then
						pointerDown(input)
					end
				end
			end)
			runtime.connect(node, "InputEnded", function(input)
				if held then
					release()
					local pointerUp = spec.onPointerUp
					if pointerUp then
						pointerUp(input)
					end
				end
			end)
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
			ctx.action(node, "Shortcut", bindings, shortcutActive, activate, {
				priority = priority,
				sink = spec.dialogAction ~= nil or modified,
			})
		end
		if targetFloor and not constrainedCaption then
			local floor = targetFloor
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use): boolean
						return floor(use) > 0
					end, function()
						return Host.UISizeConstraint "TargetFloor" {
							MinSize = function(use: ComposeTypes.Use): Vector2
								local minimum = floor(use)
								return V2.new(targetWidth(minimum, use), minimum)
							end,
						}
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
		return node
	end)
end
