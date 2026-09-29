--!strict
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion").reduced
local decoration = require("./native_decoration")
local richText = require("./rich_text")
local help = require("./help")
local activation = require("./activation")
local valueModel = require("./input_value")
local textField = require("./text_field")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ThemeTypes = require("./theme_types")
local EngineTypes = require("./engine_types")
local ComposeTypes = require("../vendor/compose/core")
type ValueState<T> = {
	value: Shared.Value<T>,
	onChange: ((T) -> ())?,
	readOnly: boolean?,
}
type LevelSpec = Shared.TextButtonProps & ValueState<number> & InputTypes.LevelOptions & {
	segment: ("bar" | "glyph" | "image")?,
	segmentSize: InputTypes.LevelSize?,
	starSize: InputTypes.LevelSize?,
	glyphs: InputTypes.Glyphs?,
	images: InputTypes.Images?,
	tint: InputTypes.Tint?,
}
type Adjust = {
	vertical: boolean?,
	once: boolean?,
	guard: boolean?,
	arrows: ((ComposeTypes.Use, number) -> boolean)?,
	extra: (((ComposeTypes.Use) -> boolean) -> ())?,
}
type ToggleButtonProps = InputTypes.ButtonProps & {
	value: Shared.Value<boolean>?,
	mixed: Shared.Value<boolean>?,
	presentation: ("switch" | "checkbox" | "button")?,
	onChange: ((boolean) -> ())?,
	indicatorPosition: ("leading" | "trailing")?,
}

local REPEAT_DELAY, REPEAT_INTERVAL = 0.4, 0.1

local function repeatHeld(
	frames: { onFrame: ((number) -> ()) -> () -> () },
	delay: number,
	interval: number,
	keep: () -> boolean,
	fire: () -> ()
): () -> ()
	local elapsed, deadline = 0, delay
	return frames.onFrame(function(delta: number)
		if not keep() then
			return
		end
		elapsed += delta
		local steps = 0
		while elapsed >= deadline and steps < 5 do
			fire()
			deadline += interval
			steps += 1
		end
		if steps == 5 then
			deadline = elapsed + interval
		end
	end)
end

return function(ctx: Shared.Context, UI: InputTypes.InputControls): ()
	local lists = layoutKit.of(ctx)
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read, props = ctx.read, ctx.props
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local noKey: Enum.KeyCode = assert(E.KeyCode:FromValue(0))
	local dialogOrder = 0
	local unskinned = setmetatable({} :: { [unknown]: boolean }, { __mode = "k" })
	local roles: { [string]: boolean } = { default = true, cancel = true, destructive = true, onIndicator = true }
	local roleTags: { [string]: string } = {}
	for name in roles do
		roleTags[name] = "facet-role-" .. name
	end
	local function dynamic(source: unknown): boolean
		return Compose.isReadable(source) or type(source) == "function"
	end
	local function hasText(source: Shared.Value<string>?, use: ComposeTypes.Use?): boolean
		local value = read(source, use)
		return value ~= nil and value ~= ""
	end
	local function enabled(
		spec: InputTypes.EnabledOptions | InputTypes.NumberInputOptions | InputTypes.LevelOptions | { value: Shared.Value<number>, onChange: ((number) -> ())? },
		use: ComposeTypes.Use?
	): boolean
		local state = spec :: InputTypes.EnabledOptions
		return read(state.enabled, use) ~= false and read(state.disabled, use) ~= true and read(state.busy, use) ~= true
	end
	local function writable(source: unknown): boolean
		return type(source) == "table"
			and Compose.isReadable(source)
			and type((source :: { [string]: unknown }).set) == "function"
	end
	local function requireValue(
		spec: { value: Shared.Value<number>, onChange: ((number) -> ())? },
		kind: "boolean" | "number" | "string",
		name: string
	): ()
		assert(type(read(spec.value)) == kind, `Facet.{name}: value must resolve to a {kind}`)
		assert(
			writable(spec.value) or type(spec.onChange) == "function" or (spec :: ValueState<number>).readOnly == true,
			`Facet.{name}: editing a read-only value requires onChange`
		)
	end

	local function changed(
		spec: { value: Shared.Value<number>, onChange: ((number) -> ())? },
		nextValue: number
	): boolean
		if read(spec.value) == nextValue then
			return false
		end
		if spec.onChange then
			spec.onChange(nextValue)
		else
			(spec.value :: ComposeTypes.Cell<number>):set(nextValue)
		end
		return read(spec.value) == nextValue
	end
	local function attributes(node: Instance, values: Shared.Attributes): Instance
		runtime.decorate(node, { Attributes = values })
		return node
	end
	local function valueAttributes(
		node: GuiObject,
		spec: { value: Shared.Value<number>, onChange: ((number) -> ())? },
		model: valueModel.Model
	): ()
		attributes(node, {
			value = function(use: ComposeTypes.Use)
				return model.quantize(read(spec.value, use))
			end,
			minimum = model.min,
			maximum = model.max,
			semanticValue = function(use: ComposeTypes.Use)
				return `{model.format(read(spec.value, use))} of {model.min} to {model.max}`
			end,
		})
	end
	local function adjustment(
		node: GuiObject,
		spec: { value: Shared.Value<number>, onChange: ((number) -> ())? },
		apply: (number) -> (),
		cancel: (() -> ())?,
		minimum: number,
		maximum: number,
		options: Adjust?
	): ()
		local adjust: Adjust = options or {}
		local landing = false
		local function arrowHeld(): boolean
			local input = ctx.config.services.UserInputService
			if input == nil then
				return false
			end
			local probe = (input :: unknown) :: {
				IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
				IsGamepadButtonDown: ((UserInputService, Enum.UserInputType, Enum.KeyCode) -> boolean)?,
			}
			for _, key in { E.KeyCode.Up, E.KeyCode.Down, E.KeyCode.Left, E.KeyCode.Right } do
				if probe.IsKeyDown and input:IsKeyDown(key) then
					return true
				end
			end
			for _, key in { E.KeyCode.DPadUp, E.KeyCode.DPadDown, E.KeyCode.DPadLeft, E.KeyCode.DPadRight } do
				if probe.IsGamepadButtonDown and input:IsGamepadButtonDown(E.UserInputType.Gamepad1, key) then
					return true
				end
			end
			return false
		end
		local guiService = ctx.config.services.GuiService
		local target = guiService and guiService.SelectedObject
		local selected = Compose.cell(target ~= nil and (target == node or target:IsDescendantOf(node)))
		if guiService then
			local nativeSelection = ctx.observe.SelectedObject(guiService)
			Compose.watch(function(use: ComposeTypes.Use)
				local target = use(nativeSelection)
				local inside = target ~= nil and (target == node or target:IsDescendantOf(node))
				if selected:peek() and not inside and cancel then
					cancel()
				end
				if inside and not selected:peek() and adjust.guard then
					landing = arrowHeld()
				end
				selected:set(inside)
			end)
		else
			runtime.connect(node, "SelectionGained", function()
				selected:set(true)
			end)
			runtime.connect(node, "SelectionLost", function()
				selected:set(false)
				if cancel then
					cancel()
				end
			end)
		end
		local active = function(use: ComposeTypes.Use)
			return read(selected, use) and enabled(spec, use)
		end
		runtime.mountFragment(function()
			return {
				Compose.show(active, function()
					local heldAction: InputAction?
					local heldArrow = Compose.cell(0)
					local stopFrame: (() -> ())?
					local function stopRepeat()
						heldAction = nil
						if stopFrame then
							stopFrame()
							stopFrame = nil
						end
					end
					Compose.cleanup(stopRepeat)
					Compose.watch(function(use: ComposeTypes.Use)
						if not active(use) or not ctx.available(node, use) then
							stopRepeat()
						end
					end)
					local function bind(
						name: string,
						keys: Shared.ActionBindings,
						source: Shared.Value<boolean>,
						direction: number,
						arrow: boolean?
					)
						local action: InputAction
						action = ctx.action(node, name, keys, source, function()
							if arrow and landing then
								return
							end
							stopRepeat()
							if arrow then
								heldArrow:set(direction)
							end
							apply(direction)
							heldAction = action
							local probe = (action :: unknown) :: { GetState: ((InputAction) -> unknown)? }
							local state = probe.GetState
							local engaged = state ~= nil and state(action) == true
							if runtime.host.frames and not adjust.once then
								local timing = (spec :: unknown) :: { repeatDelay: number?, repeatInterval: number? }
								stopFrame = repeatHeld(
									runtime.host.frames,
									timing.repeatDelay or REPEAT_DELAY,
									timing.repeatInterval or REPEAT_INTERVAL,
									function(): boolean
										if
											not read(source)
											or not ctx.available(node)
											or (engaged and state and state(action) ~= true)
										then
											stopRepeat()
											return false
										end
										return true
									end,
									function()
										apply(direction)
									end
								)
							end
						end, {
							priority = 250,
							capture = true,
							onReleased = function()
								if arrow then
									landing = false
									if heldArrow:peek() == direction then
										heldArrow:set(0)
									end
								end
								if heldAction == action then
									stopRepeat()
								end
							end,
						})
					end
					bind("Decrease", { E.KeyCode.Comma, E.KeyCode.ButtonL1 }, active, -1)
					bind("Increase", { E.KeyCode.Period, E.KeyCode.ButtonR1 }, active, 1)
					if minimum ~= nil and maximum ~= nil then
						for _, direction in { -1, 1 } do
							local keys = if adjust.vertical
								then (if direction < 0
									then { E.KeyCode.Down, E.KeyCode.DPadDown }
									else { E.KeyCode.Up, E.KeyCode.DPadUp })
								else (if direction < 0
									then { E.KeyCode.Left, E.KeyCode.DPadLeft }
									else { E.KeyCode.Right, E.KeyCode.DPadRight })
							bind(
								if direction < 0 then "DecreaseArrow" else "IncreaseArrow",
								keys,
								function(use: ComposeTypes.Use)
									if use(heldArrow) == direction then
										return active(use)
									end
									local arrows = adjust.arrows
									if arrows then
										return active(use) and arrows(use, direction)
									end
									local value = read(spec.value, use)
									return active(use) and (if direction < 0 then value > minimum else value < maximum)
								end,
								direction,
								true
							)
						end
					end
					if adjust.extra then
						adjust.extra(active)
					end
					if cancel then
						ctx.action(
							node,
							"Cancel",
							{ E.KeyCode.Escape, E.KeyCode.ButtonB },
							active,
							cancel,
							{ priority = 100 }
						)
					end
					return Compose.fragment(function()
						return {}
					end)
				end),
			}
		end, node)
	end
	local icon = ctx.icon

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
	})
	local CONTROL_RUNGS = { "xsmall", "compact", "regular", "large" }
	local rungTags: { string } = {}
	for index, name in CONTROL_RUNGS do
		rungTags[index] = "facet-size-" .. name
	end
	local typeRoles: { [string]: boolean } = {
		caption = true,
		label = true,
		body = true,
		heading = true,
		title = true,
		control = true,
		strong = true,
		numeral = true,
	}
	local escapeRich = richText.escape
	UI.Button = ctx.construct("Button", function(spec: InputTypes.ButtonProps): TextButton
		assert(
			spec.onActivate == nil or type(spec.onActivate) == "function",
			"Facet.Button: onActivate must be a function"
		)
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet.Button: shape must be rect or circle"
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
		local repeatDelay, repeatInterval = spec.repeatDelay or REPEAT_DELAY, spec.repeatInterval or REPEAT_INTERVAL
		assert(
			repeatDelay > 0 and repeatDelay < math.huge and repeatInterval > 0 and repeatInterval < math.huge,
			"Facet.Button: repeat timings must be finite and positive"
		)
		local function activate(...)
			local pressed: Instance? = node
			if activation.consumed((...)) or (pressed and help.consume(pressed)) then
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
		}
		local authored = spec.Size
		local bounded = typeof(authored) == "UDim2"
			and ((authored :: UDim2).X.Scale > 0 or (authored :: UDim2).X.Offset > 0)
			and spec.AutomaticSize == nil
			and spec.image == nil
			and spec.row == nil
			and spec.subtitle == nil
			and spec.hint == nil
		if bounded then
			defaults.AutomaticSize = E.AutomaticSize.Y
			if not rich then
				defaults.TextWrapped = spec.disclose ~= true
					and (spec.TextTruncate == nil or spec.TextTruncate == E.TextTruncate.None)
			end
		end
		if enabledProperty ~= true then
			defaults.Selectable = enabledProperty
			defaults.Interactable = enabledProperty
		end
		local p = props(spec, buttonKeys, defaults)
		if bounded and spec.label ~= nil and spec.shape ~= "circle" then
			table.insert(
				p,
				Host.UISizeConstraint({
					MinSize = function(use: ComposeTypes.Use): Vector2
						local package = read(ctx.config.theme, use)
						local skin = package and package.chrome and package.chrome.control
						local carve: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
						return V2.new(
							2 * ctx.controlSize(spec.controlSize, "paddingX", use)
								+ (carve.left or 0)
								+ (carve.right or 0)
								+ ctx.metric("typography.control.size", use),
							0
						)
					end,
				})
			)
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
			table.insert(p, Host.UIAspectRatioConstraint(aspect))
			table.insert(p, Host.UICorner({ CornerRadius = ctx.round }))
		elseif spec.corners then
			table.insert(
				p,
				Host.UICorner({ CornerRadius = if dynamic(spec.corners) then cornerRadius else cornerRadius() })
			)
		end
		if popTimeline then
			table.insert(p, Host.UIScale "Pop" { Scale = popScale })
		end
		if spec.busy ~= nil then
			table.insert(
				p,
				Host.UIPadding({
					PaddingRight = function(use: ComposeTypes.Use): UDim
						if read(spec.busy, use) ~= true then
							return D.new(0, 0)
						end
						local package = read(ctx.config.theme, use)
						local skin = package and package.chrome and package.chrome.control
						return D.new(0, 32 + (if skin and skin.contentInsets then skin.contentInsets.right or 0 else 0))
					end,
				})
			)
			table.insert(
				p,
				Compose.show(function(use: ComposeTypes.Use)
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
						table.insert(
							dots,
							ctx.styled(
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
						)
					end
					local busy = Host.Frame(dots)
					ctx.playWhileShown(phase, busy)
					return busy
				end)
			)
		end
		local markRow: ((GuiObject) -> ())? = nil
		local function listRow(
			content: { ComposeTypes.Child },
			lead: number,
			captions: { GuiObject },
			described: boolean
		): Frame
			local frame, size, mark = ctx.listRow({
				leading = table.move(content, 1, lead, 1, {}),
				captions = captions,
				trailing = table.move(content, lead + 1, #content, 1, {}),
				described = described,
				controlSize = spec.controlSize,
			})
			if spec.Size == nil then
				p.Size = size
				p.AutomaticSize = spec.AutomaticSize or E.AutomaticSize.Y
			end
			markRow = mark
			return frame
		end
		if rich then
			local content: { ComposeTypes.Child } = {}
			local imageCard = spec.image ~= nil
			local hugs = false
			local rungIcon: Shared.Value<UDim2>? = nil
			if spec.controlSize ~= nil then
				local function iconSide(use: ComposeTypes.Use?): UDim2
					local side = ctx.controlSize(spec.controlSize, "iconSize", use)
					return D2.fromOffset(side, side)
				end
				rungIcon = if dynamic(ctx.config.theme) or dynamic(spec.controlSize) then iconSide else iconSide()
			end
			if imageCard then
				assert(
					type(spec.imageAspectRatio or 16 / 9) == "number" and (spec.imageAspectRatio or 16 / 9) > 0,
					"Facet.Button: imageAspectRatio must be positive"
				)
				local authored = spec.Size
				local fixed = dynamic(authored)
					or (authored ~= nil and ((authored :: UDim2).Y.Scale ~= 0 or (authored :: UDim2).Y.Offset ~= 0))
				p.Size = authored or D2.fromOffset(240, 0)
				p.AutomaticSize = spec.AutomaticSize or (if fixed then E.AutomaticSize.None else E.AutomaticSize.Y)
				hugs = spec.AutomaticSize == E.AutomaticSize.Y
					or spec.AutomaticSize == E.AutomaticSize.XY
					or (spec.AutomaticSize == nil and not fixed)
				local function radius(use: ComposeTypes.Use?): number
					return if read(spec.corners, use) == "square" then 0 else ctx.metric("radii.control", use)
				end
				local live = dynamic(ctx.config.theme) or dynamic(spec.corners)
				table.insert(
					content,
					Host.Frame "Media" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Size = if hugs then D2.new(1, 0, 0, 100000) else D2.fromScale(1, 0),
						if hugs
							then Host.UIAspectRatioConstraint({
								AspectRatio = spec.imageAspectRatio or 16 / 9,
								DominantAxis = E.DominantAxis.Width,
							})
							else Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						Host.ImageLabel "Image" {
							Image = spec.image,
							BackgroundTransparency = 1,
							AnchorPoint = if hugs then nil else V2.new(0.5, 0.5),
							Position = if hugs then nil else D2.fromScale(0.5, 0.5),
							Size = if not hugs
								then D2.fromScale(1, 1)
								elseif live then function(use: ComposeTypes.Use)
									return D2.new(1, 0, 1, radius(use))
								end
								else D2.new(1, 0, 1, radius()),
							ScaleType = if spec.imageFraming == "fit" then E.ScaleType.Fit else E.ScaleType.Crop,
							Host.UICorner({
								CornerRadius = if live
									then function(use: ComposeTypes.Use)
										return D.new(0, radius(use))
									end
									else D.new(0, radius()),
							}),
							if hugs
								then nil
								else Host.UIAspectRatioConstraint({
									AspectRatio = spec.imageAspectRatio or 16 / 9,
									AspectType = E.AspectType.FitWithinMaxSize,
								}),
						},
					}
				)
			end
			local row: InputTypes.Row = spec.row or {}
			local leading = spec.icon or row.icon
			if leading then
				table.insert(
					content,
					icon(leading, {
						Name = "LeadingIcon",
						Size = rungIcon,
						Visible = if dynamic(leading)
							then function(use: ComposeTypes.Use): boolean
								return read(leading, use) ~= ""
							end
							else nil,
					}, iconState)
				)
			end
			local label = row.title or spec.label or (if leading then nil else spec.name) or ""
			local description = row.description or spec.subtitle or spec.hint
			local lead = #content
			local rowCaptions: { GuiObject } = {}
			local wordless = leading ~= nil and description == nil and not dynamic(label) and label == ""
			if not (spec.shape == "circle" and spec.icon) and not wordless then
				local function caption(name: string, text: Shared.Value<string>): TextLabel
					local live = dynamic(text)
					local function words(use: ComposeTypes.Use?): string
						return read(text, use) or ""
					end
					local function shown(use: ComposeTypes.Use?): boolean
						local value = read(text, use)
						return value ~= nil and value ~= ""
					end
					local made = ctx.text({
						Name = name,
						Text = if live then words else words(),
						Visible = if live then shown else shown(),
						Size = if imageCard then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
						AutomaticSize = if imageCard then E.AutomaticSize.Y else E.AutomaticSize.XY,
						TextWrapped = imageCard,
					})
					if name == "Title" then
						sized(made)
						if bounded then
							made.TextTruncate = E.TextTruncate.AtEnd
							runtime.mount(function()
								return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink })
							end, made)
						end
					end
					return made
				end
				if spec.row then
					rowCaptions = { caption("Title", label) }
					if description then
						table.insert(rowCaptions, caption("Description", description))
					end
				else
					local captions = if description
						then ctx.column({ caption("Title", label), caption("Description", description) }, {
							Name = "Captions",
							Size = if imageCard then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
							AutomaticSize = if imageCard then E.AutomaticSize.Y else E.AutomaticSize.XY,
						})
						else caption("Title", label)
					if imageCard then
						captions:AddTag("facet-button-media-body")
					end
					table.insert(content, captions)
				end
				if row.value ~= nil then
					local value = caption("Value", row.value)
					value:AddTag("facet-secondary")
					table.insert(content, value)
				end
			end
			if spec.row and spec.onActivate and not spec.trailingIcon then
				table.insert(content, icon("chevron.trailing", { Name = "Disclosure" }, iconState))
			end
			if spec.trailingIcon then
				table.insert(content, icon(spec.trailingIcon, { Name = "TrailingIcon", Size = rungIcon }, iconState))
			end
			local contentFrame = if imageCard
				then ctx.column(content, {
					Name = "Content",
					ZIndex = 1,
					Size = if hugs then D2.fromScale(1, 0) else D2.fromScale(1, 1),
					AutomaticSize = if hugs then E.AutomaticSize.Y else E.AutomaticSize.None,
					ClipsDescendants = true,
				})
				elseif spec.row then listRow(content, lead, rowCaptions, description ~= nil)
				elseif description then ctx.row(content, {
					Name = "Content",
					ZIndex = 1,
					AnchorPoint = function(use: ComposeTypes.Use)
						return if hasText(description, use) then V2.zero else V2.new(0, 0.5)
					end,
					Position = function(use: ComposeTypes.Use)
						return if hasText(description, use) then D2.fromScale(0, 0) else D2.fromScale(0, 0.5)
					end,
					Size = if spec.TextXAlignment == nil
						then nil
						else function(use: ComposeTypes.Use)
							return if hasText(description, use) then D2.fromOffset(0, 0) else D2.fromScale(1, 0)
						end,
				})
				else ctx.row(content, {
					Name = "Content",
					ZIndex = 1,
					Size = D2.fromScale(1, 1),
					AutomaticSize = if bounded then E.AutomaticSize.None else nil,
				})
			if not imageCard then
				local layout = assert(contentFrame:FindFirstChildWhichIsA("UIListLayout"))
				layout.VerticalAlignment = E.VerticalAlignment.Center
				if not spec.row and (not description or spec.TextXAlignment ~= nil) then
					local alignment = spec.TextXAlignment
					if alignment == nil then
						layout.HorizontalAlignment = E.HorizontalAlignment.Center
					else
						runtime.decorate(layout, {
							HorizontalAlignment = function(use: ComposeTypes.Use): Enum.HorizontalAlignment
								local value = read(alignment, use)
								return if value == E.TextXAlignment.Left
									then E.HorizontalAlignment.Left
									elseif value == E.TextXAlignment.Right then E.HorizontalAlignment.Right
									else E.HorizontalAlignment.Center
							end,
						})
					end
				end
			end
			local glyph = if leading
					and not imageCard
					and not spec.row
					and not description
				then contentFrame:FindFirstChild("LeadingIcon")
				else nil
			if glyph and spec.AutomaticSize == E.AutomaticSize.None and label == "" then
				fillsGlyph = true
				contentFrame.AutomaticSize = E.AutomaticSize.None
				local box = ctx.observe.AbsoluteSize(contentFrame)
				runtime.mount(function()
					return Host.UISizeConstraint({
						MaxSize = function(use: ComposeTypes.Use): Vector2
							local room = use(box)
							local side = math.max(1, math.min(room.X, room.Y))
							return V2.new(side, side)
						end,
					})
				end, glyph)
			end
			table.insert(p, contentFrame)
		end
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
			table.insert(
				p,
				Compose.show(function(use: ComposeTypes.Use)
					keyboardAttached = keyboardAttached
						or (read(selectedForKeyboard, use) == true and enabled(spec, use))
					return keyboardAttached
				end, function()
					attachKeyboard()
					return Compose.fragment(function()
						return {}
					end)
				end)
			)
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
							local fits, box = ctx.observe.TextFits(node), ctx.observe.AbsoluteSize(node)
							local words, points, face =
								ctx.observe.Text(node),
								ctx.observeStyled.TextSize(node),
								ctx.observeStyled.FontFace(node)
							local measured: string? = nil
							Compose.watch(function(use: ComposeTypes.Use)
								use(box)
								use(fits)
								local width, whole = node.AbsoluteSize.X, node.TextFits
								local metrics = `{width}|{use(words)}|{use(points)}|{use(face)}`
								if metrics ~= measured and node:HasTag("facet-button-tight") then
									measured = metrics
									node:RemoveTag("facet-button-tight")
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
				if hasText(described, use) then
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
				local boundary = decoration(
					Compose,
					runtime,
					ctx.types,
					node,
					ctx.styled(ctx.text(labelProps), "button-caption"),
					{ inset = true }
				)
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
				})
				return measure
			end, node)
			local bounds = ctx.observe.TextBounds(measure)
			runtime.decorate(node, {
				Text = function(use: ComposeTypes.Use)
					local compact = use(size).X > 0 and use(bounds).X > use(size).X - 24
					return read(if compact then spec.compactLabel else spec.label, use)
				end,
			})
		end

		if not unskinned[spec] then
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
		local previousTags: { [string]: boolean } = {}
		local previousAttributes: { [string]: boolean | string } = {}
		local initialized = false
		local initialTags: { [string]: boolean }? = nil
		local function tag(name: string, active: boolean)
			if previousTags[name] ~= active then
				previousTags[name] = active
				if active then
					node:AddTag(name)
				elseif initialized or (initialTags ~= nil and initialTags[name]) then
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
				local present: { [string]: boolean } = {}
				for _, name in node:GetTags() do
					present[name] = true
				end
				initialTags = present
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
			initialTags = nil
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
			local function startRepeat()
				if stopFrame or not (spec.repeatDelay or spec.repeatInterval) then
					return
				end
				stopFrame = repeatHeld(assert(runtime.host.frames), repeatDelay, repeatInterval, function(): boolean
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
			Compose.cleanup(release)
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
			runtime.connect(node, "MouseLeave", function()
				if held and spec.onPointerCancel then
					spec.onPointerCancel()
				end
				release()
			end)
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
		if spec.controlSize ~= nil and ctx.config.userInputService ~= nil then
			local floor = ctx.touchFloor()
			runtime.mount(function()
				return Host.UISizeConstraint "TargetFloor" {
					MinSize = function(use: ComposeTypes.Use): Vector2
						local minimum = floor(use)
						if ctx.controlSize(spec.controlSize, "height", use) >= minimum then
							return V2.zero
						end
						return V2.new(minimum, minimum)
					end,
				}
			end, node)
		end

		return node
	end)

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

	textField(ctx, UI)

	UI.Stepper = ctx.construct("Stepper", function(spec: InputTypes.StepperImplementationProps): Frame
		requireValue(spec, "number", "Stepper")
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
				repeatDelay = spec.repeatDelay or REPEAT_DELAY,
				repeatInterval = spec.repeatInterval or REPEAT_INTERVAL,
				LayoutOrder = if direction < 0 then 1 else 3,
				Size = D2.fromOffset(44, 44),
				AutomaticSize = E.AutomaticSize.None,
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
		local p = props(spec, {
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
			Selectable = true,
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
		valueAttributes(node, spec, model)
		adjustment(node, spec, adjust, nil, model.min, model.max)
		return node
	end)

	local function paintedPart(
		native: Shared.FrameProps,
		image: Shared.Value<string>?,
		role: string,
		slot: string
	): Frame
		if image then
			table.insert(
				native,
				Host.ImageLabel "Artwork" {
					Image = image,
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					ScaleType = E.ScaleType.Stretch,
				}
			)
		end
		local node = ctx.styled(Host.Frame(native), role)
		if not image then
			ctx.skin(node, slot)
		end
		return node
	end

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
		adjustment(node, options :: any, options.onAdjust, nil, if bound then -bound else nil :: any, bound :: any, {
			vertical = axis == "vertical",
			once = options.repeats ~= true,
			arrows = function(use: ComposeTypes.Use, direction: number): boolean
				return canAdjust == nil or canAdjust(direction, use)
			end,
		})
	end

	require("./slider")(ctx, UI, {
		enabled = enabled,
		writable = writable,
		attributes = attributes,
		valueAttributes = valueAttributes,
		adjustment = adjustment,
		paintedPart = paintedPart,
	})

	local function level(source: InputTypes.RatingProps | InputTypes.LevelPickerProps, rating: boolean): TextButton
		local spec = (source :: Shared.TextButtonProps) :: LevelSpec
		requireValue(spec, "number", if rating then "Rating" else "LevelPicker")
		local count = spec.count or 5
		assert(
			type(count) == "number" and count > 0 and count % 1 == 0 and count < math.huge,
			"Facet.LevelPicker: count must be a positive integer"
		)
		local minimum = if spec.allowZero == false then 1 else 0
		local segment = if rating then "glyph" else spec.segment or "bar"
		assert(table.find({ "bar", "glyph", "image" }, segment), "Facet.LevelPicker: invalid segment")
		assert(segment == "glyph" or spec.glyphs == nil, "Facet.LevelPicker: glyphs require glyph segments")
		assert(segment == "image" or spec.images == nil, "Facet.LevelPicker: images require image segments")
		local markSizes: { [string]: number } = { small = 20, medium = 28, large = 36 }
		local markSize =
			assert(markSizes[spec.starSize or spec.segmentSize or "small"], "Facet.LevelPicker: invalid size")
		local glyphs: InputTypes.Glyphs = spec.glyphs or { filled = "★", empty = "☆" }
		local function interactive(use)
			return enabled(spec, use) and spec.readOnly ~= true
		end
		local function apply(value)
			if interactive() then
				changed(spec, math.clamp(value, minimum, count))
			end
		end
		local marks: { ComposeTypes.Child } = {}
		for index = 1, count do
			local filled = function(use: ComposeTypes.Use)
				return read(spec.value, use) >= index
			end
			local name, size = `Level{index}`, D2.fromOffset(markSize, markSize)
			local mark: GuiObject
			local paint: "TextColor3" | "ImageColor3" | "BackgroundColor3"
			if segment == "glyph" then
				mark, paint =
					ctx.text({
						Name = name,
						Size = size,
						BackgroundTransparency = 1,
						Selectable = false,
						TextSize = markSize,
						TextXAlignment = E.TextXAlignment.Center,
						Text = function(use: ComposeTypes.Use)
							return if filled(use) then glyphs.filled else glyphs.empty
						end,
					}), "TextColor3"
			elseif segment == "image" then
				local images = spec.images
				assert(
					images and images.filled and images.empty,
					"Facet.LevelPicker: image segments require filled and empty images"
				)
				mark, paint =
					Host.ImageLabel({
						Name = name,
						Size = size,
						BackgroundTransparency = 1,
						Selectable = false,
						Image = function(use: ComposeTypes.Use)
							return if filled(use) then images.filled else images.empty
						end,
					}), "ImageColor3"
			else
				mark, paint =
					ctx.styled(
						Host.Frame(name)({
							Size = D2.fromOffset(markSize, math.round(markSize * (0.3 + 0.7 * index / count))),
							Selectable = false,
							ctx.corner(2),
						}),
						"level-segment"
					), "BackgroundColor3"
				local bar = mark
				Compose.watch(function(use: ComposeTypes.Use)
					if filled(use) then
						bar:AddTag("facet-level-on")
					elseif bar:HasTag("facet-level-on") then
						bar:RemoveTag("facet-level-on")
					end
				end)
			end
			if spec.tint then
				Compose.watch(function(use: ComposeTypes.Use)
					local color = read(if filled(use) then spec.tint.filled else spec.tint.empty, use)
					if color ~= nil then
						if mark:IsA("TextLabel") then
							mark.TextColor3 = color
						elseif mark:IsA("ImageLabel") then
							mark.ImageColor3 = color
						else
							(mark :: Frame).BackgroundColor3 = color
						end
					else
						mark:ResetPropertyToDefault(paint)
					end
				end)
			end
			table.insert(marks, mark)
		end
		local contentProps: Shared.FrameNativeProps = {
			Name = "Marks",
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			BackgroundTransparency = 1,
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			lists.list({ gap = 2, align = "end" }, false),
		}
		for index, mark in marks do
			runtime.decorate(mark, { LayoutOrder = index })
			table.insert(contentProps, mark)
		end
		local markContent = Host.Frame(contentProps)

		local effectiveInput = ctx.effectiveInput()
		local room, drawn = Compose.cell(math.huge), Compose.cell(math.huge)
		local function spacing(use: ComposeTypes.Use, width: number): number
			local reach = if effectiveInput(use) == "Touch" then ctx.metric("targetSizes.minimum", use) else 0
			local fits = if count > 1 then math.floor((width - count * markSize) / (count - 1)) else math.huge
			return math.max(2, math.min(reach - markSize, fits))
		end
		local function gap(use: ComposeTypes.Use): number
			return spacing(use, use(room))
		end
		runtime.decorate(assert(markContent:FindFirstChildWhichIsA("UIListLayout")), {
			Padding = function(use: ComposeTypes.Use): UDim
				return D.new(0, math.min(gap(use), spacing(use, use(drawn))))
			end,
		})

		local root: TextButton
		local dragging: boolean?
		local snapshot: number?
		local suppressActivation: boolean?
		local function valueAt(position: Vector2 | Vector3): number
			local width = root.AbsoluteSize.X
			if width <= 0 then
				return read(spec.value)
			end
			return math.clamp(math.floor((position.X - root.AbsolutePosition.X) / width * count) + 1, 1, count)
		end
		local function cancel()
			if dragging then
				dragging = false
				suppressActivation = true
				changed(spec, assert(snapshot))
			end
		end
		local p = props(
			spec,
			{
				"value",
				"count",
				"allowZero",
				"enabled",
				"readOnly",
				"glyphs",
				"images",
				"tint",
				"segment",
				"starSize",
				"segmentSize",
				"onChange",
			},
			{
				PressHapticEffect = if spec.PressHapticEffect == nil and ctx.haptic(true)
					then Compose.static(ctx.haptic(true))
					else nil,
				Text = "",
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = function(use: ComposeTypes.Use): UDim2
					return D2.fromOffset(count * markSize + math.max(0, count - 1) * gap(use), math.max(44, markSize))
				end,
				Selectable = interactive,
				Interactable = interactive,
				markContent :: ComposeTypes.Child,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink }),
				Host.UIDragDetector "Scrub" {
					ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
					Enabled = interactive,
					DragStart = function(position)
						if interactive() then
							dragging, snapshot = true, read(spec.value)
							apply(valueAt(position))
						end
					end,
					DragContinue = function(position)
						if dragging then
							apply(valueAt(position))
						end
					end,
					DragEnd = function()
						if dragging then
							dragging = false
							suppressActivation = true
						end
					end,
				},
			} :: Shared.TextButtonNativeProps
		)
		p.Activated = function(input: InputObject, clickCount: number)
			if suppressActivation then
				suppressActivation = false
				return
			end
			if input and input.Position then
				local value = valueAt(input.Position)
				apply(if value == read(spec.value) and minimum == 0 then 0 else value)
			else
				apply(if read(spec.value) == count then minimum else (read(spec.value) :: number) + 1)
			end
			if spec.Activated then
				spec.Activated(input, clickCount)
			end
		end
		root = ctx.styled(Host.TextButton(p), if rating then "rating" else "level-picker")
		local parent = ctx.observe.Parent(root)
		local unit = ctx.observe.AbsoluteSize((marks[1] :: unknown) :: GuiObject)
		local holderSize = Compose.cell(0)
		local observation = runtime.host.observation
		local stopHolder: (() -> ())? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local holder = use(parent) :: Instance?
			if stopHolder then
				stopHolder()
				stopHolder = nil
			end
			local fixed = holder
				and holder:IsA("GuiObject")
				and holder.AutomaticSize ~= E.AutomaticSize.X
				and holder.AutomaticSize ~= E.AutomaticSize.XY
			if fixed and observation then
				local frame = holder :: GuiObject
				local function measure()
					holderSize:set(frame.AbsoluteSize.X)
				end
				stopHolder = observation.observeProperty(frame, "AbsoluteSize", measure)
				measure()
			else
				holderSize:set(0)
			end
		end)
		Compose.cleanup(function()
			if stopHolder then
				stopHolder()
			end
		end)
		local own = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			local width, scale = use(holderSize), (use(unit) :: Vector2).X / markSize
			room:set(if width > 0 and scale > 0 then width / scale else math.huge)
			local box = use(own).X
			drawn:set(if box > 0 and scale > 0 then box / scale else math.huge)
		end)
		local function published(use: ComposeTypes.Use): number
			return math.clamp(read(spec.value, use), minimum, count)
		end
		attributes(root, {
			value = published,
			minimum = minimum,
			maximum = count,
			semanticValue = function(use: ComposeTypes.Use)
				return `{published(use)} of {minimum} to {count}`
			end,
		})
		runtime.connect(root, "InputBegan", function()
			suppressActivation = false
		end)
		adjustment(root, spec, function(direction)
			apply((read(spec.value) :: number) + direction)
		end, cancel, minimum, count)
		Compose.watch(function(use: ComposeTypes.Use)
			if not interactive(use) then
				cancel()
			end
		end)
		local input = ctx.config.services.UserInputService
		if input then
			local preference = ctx.observe.PreferredInput(input)
			Compose.watch(function(use: ComposeTypes.Use)
				if use(preference) == E.PreferredInput.Gamepad then
					cancel()
				end
			end)
		end
		return root
	end

	UI.Rating = ctx.construct("Rating", function(spec: InputTypes.RatingProps): TextButton
		return level(spec, true)
	end)
	UI.LevelPicker = ctx.construct("LevelPicker", function(spec: InputTypes.LevelPickerProps): TextButton
		return level(spec, false)
	end)
	UI.Chip = ctx.construct("Chip", function(spec: InputTypes.ChipImplementationProps): TextButton | Frame
		assert(
			spec.selected == nil or writable(spec.selected) or type(spec.onToggle) == "function",
			"Facet.Chip: read-only selected requires onToggle"
		)
		assert(spec.selected ~= nil or spec.onRemove, "Facet.Chip: selected or onRemove is required")
		assert(spec.editing == nil or spec.onRemove ~= nil, "Facet UI.Chip: editing requires onRemove")
		if spec.selected ~= nil and spec.onRemove ~= nil and spec.editing == nil then
			error("Facet UI.Chip: a selectable chip with onRemove requires editing, the caller's edit-mode cell", 0)
		end
		local removable = spec.onRemove ~= nil
		local function editing(use: ComposeTypes.Use?): boolean
			if not removable then
				return false
			end
			return spec.selected == nil or read(spec.editing, use) == true
		end
		local p = (table.clone(spec) :: unknown) :: InputTypes.ButtonProps & {
			onToggle: ((boolean) -> ())?,
			onRemove: (() -> ())?,
			editing: Shared.Value<boolean>?,
			removeLabel: Shared.Value<string>?,
			removeFocusFallback: Shared.Value<GuiObject?>?,
			leading: Instance?,
			trailing: Instance?,
		}
		p.onToggle, p.onRemove, p.editing, p.removeLabel, p.removeFocusFallback, p.leading, p.trailing =
			nil, nil, nil, nil, nil, nil, nil
		p.ref = nil
		local node: TextButton
		local pendingFocus: GuiObject?
		local gui = ctx.config.services.GuiService
		local function candidate(): GuiObject?
			if node.Parent then
				local siblings = node.Parent:GetChildren()
				local ordinal: { [Instance]: number } = {}
				for index, sibling in siblings do
					ordinal[sibling] = index
				end
				table.sort(siblings, function(a: Instance, b: Instance): boolean
					local first = if a:IsA("GuiObject") then a.LayoutOrder else 0
					local second = if b:IsA("GuiObject") then b.LayoutOrder else 0
					return if first == second then ordinal[a] < ordinal[b] else first < second
				end)
				local index = table.find(siblings, node)
				local function target(at: number): GuiObject?
					local sibling = siblings[at]
					if
						sibling
						and sibling:IsA("GuiObject")
						and sibling:GetAttribute("editing") ~= nil
						and sibling.Selectable
						and ctx.available(sibling)
					then
						return sibling
					end
					return nil
				end
				if index then
					for at = index + 1, #siblings do
						local found = target(at)
						if found then
							return found
						end
					end
					for at = index - 1, 1, -1 do
						local found = target(at)
						if found then
							return found
						end
					end
				end
			end
			return read(spec.removeFocusFallback)
		end
		local function restore()
			if
				gui
				and pendingFocus
				and pendingFocus.Parent
				and (gui.SelectedObject == node or gui.SelectedObject == nil)
			then
				gui.SelectedObject = pendingFocus
			end
			pendingFocus = nil
		end
		local function remove()
			if not enabled(spec) or not ctx.available(node) then
				return
			end
			if gui and gui.SelectedObject == node then
				pendingFocus = candidate()
			end
			assert(spec.onRemove)()
			if node.Parent == nil then
				restore()
			end
		end
		p.onActivate = function()
			if editing() then
				remove()
			elseif spec.selected then
				local value = not read(spec.selected)
				if spec.onToggle then
					spec.onToggle(value)
				else
					(spec.selected :: ComposeTypes.Cell<boolean>):set(value)
				end
			end
		end
		p.Selectable = function(use: ComposeTypes.Use)
			return (spec.selected ~= nil or removable) and enabled(spec, use)
		end
		if p.haptic == nil and spec.selected ~= nil then
			p.haptic = true
		end
		if spec.leading or spec.trailing or removable then
			p.Text = ""
			local contents: { ComposeTypes.Child } = {}
			if spec.leading then
				table.insert(contents, spec.leading)
			end
			table.insert(contents, ctx.text({ Name = "Title", Text = spec.label or "" }))
			if spec.trailing then
				table.insert(contents, spec.trailing)
			end
			if removable then
				table.insert(
					contents,
					ctx.text({
						Name = "Remove",
						Text = "×",
						Visible = function(use: ComposeTypes.Use)
							return editing(use)
						end,
					})
				)
			end
			local row = ctx.row(contents, {
				Name = "Content",
				AnchorPoint = V2.new(0, 0.5),
				Position = D2.fromScale(0, 0.5),
			})
			assert(row:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
			table.insert(p, row)
		end
		if p.haptic == nil and spec.selected ~= nil then
			p.haptic = true
		end
		node = ctx.styled(UI.Button(p), "chip")
		node:AddTag("facet-selection-mark")
		if removable then
			attributes(
				node,
				{
					AccessibleLabel = function(use: ComposeTypes.Use): string
						if not editing(use) then
							return read(spec.label, use) or ""
						end
						local named = read(spec.removeLabel, use)
						return named or `Remove {read(spec.label, use) or ""}`
					end,
					editing = function(use: ComposeTypes.Use)
						return editing(use)
					end,
				} :: Shared.Attributes
			)
			local holding = false
			local function removalHeld(): boolean
				local input = ctx.config.services.UserInputService
				local probe = (input :: unknown) :: {
					IsKeyDown: ((UserInputService, Enum.KeyCode) -> boolean)?,
					GetConnectedGamepads: ((UserInputService) -> { Enum.UserInputType })?,
					IsGamepadButtonDown: ((UserInputService, Enum.UserInputType, Enum.KeyCode) -> boolean)?,
				}?
				if input == nil or probe == nil or probe.IsKeyDown == nil then
					return false
				end
				if input:IsKeyDown(E.KeyCode.Delete) or input:IsKeyDown(E.KeyCode.Backspace) then
					return true
				end
				if probe.GetConnectedGamepads == nil or probe.IsGamepadButtonDown == nil then
					return false
				end
				for _, pad in input:GetConnectedGamepads() do
					if input:IsGamepadButtonDown(pad, E.KeyCode.ButtonX) then
						return true
					end
				end
				return false
			end
			local focused: ComposeTypes.Readable<GuiObject?> = if gui
				then ctx.observe.SelectedObject(gui)
				else Compose.cell(nil :: GuiObject?)
			local wasFocused = false
			Compose.watch(function(use: ComposeTypes.Use)
				local now = use(focused) == (node :: Instance)
				if now and not wasFocused then
					holding = removalHeld()
				end
				wasFocused = now
			end)
			ctx.action(
				node,
				"RemoveChip",
				{ E.KeyCode.Delete, E.KeyCode.Backspace, E.KeyCode.ButtonX },
				function(use: ComposeTypes.Use)
					return use(focused) == (node :: Instance) and editing(use) and enabled(spec, use)
				end,
				function()
					if holding then
						return
					end
					remove()
				end,
				{
					priority = 100,
					onReleased = function()
						holding = false
					end,
				}
			)
		end
		Compose.cleanup(restore)
		return node
	end)

	UI.ShortcutHint = ctx.construct(
		"ShortcutHint",
		function(spec: InputTypes.ShortcutHintImplementationProps): TextLabel | Frame
			assert((spec.action == nil) ~= (spec.keys == nil), "Facet.ShortcutHint: supply action or keys")
			assert(spec.action == nil or spec.separator == nil, "Facet.ShortcutHint: separator applies only to keys")
			local semantic = { "action", "keys", "separator", "controlSize" }
			if spec.label ~= nil then
				assert(
					spec.labelPosition == nil or spec.labelPosition == "start" or spec.labelPosition == "end",
					"Facet.ShortcutHint: labelPosition must be start or end"
				)
				local hint = UI.ShortcutHint(({
					Name = "Keys",
					action = spec.action,
					keys = spec.keys,
					separator = spec.separator,
					controlSize = spec.controlSize,
				} :: unknown) :: InputTypes.ShortcutHintProps)
				local caption = ctx.styled(
					ctx.text({ Name = "Label", Text = spec.label, AutomaticSize = E.AutomaticSize.XY }),
					"secondary"
				)
				return ctx.row(
					if spec.labelPosition == "start" then { caption, hint } else { hint, caption },
					props(
						spec :: Shared.GuiObjectNativeProps,
						{ "action", "keys", "separator", "controlSize", "label", "labelPosition" },
						{
							Name = "ShortcutHint",
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							BackgroundTransparency = 1,
						}
					) :: Shared.FrameNativeProps
				)
			end
			if spec.keys then
				return ctx.styled(
					ctx.text(props(spec, semantic, {
						Text = function(use: ComposeTypes.Use)
							local chords: { { string } } = read(assert(spec.keys), use)
							assert(
								type(chords) == "table" and #chords > 0,
								"Facet.ShortcutHint: keys must be a nonempty list of chords"
							)
							local parts: { string } = {}
							for _, chord in chords do
								assert(
									type(chord) == "table" and #chord > 0,
									"Facet.ShortcutHint: chords cannot be empty"
								)
								for _, key in chord do
									assert(
										type(key) == "string" and key ~= "",
										"Facet.ShortcutHint: key names must be nonempty strings"
									)
								end
								table.insert(parts, table.concat(chord, "+"))
							end
							local separator = read(spec.separator, use) or " / "
							assert(
								type(separator) == "string" and separator ~= "",
								"Facet.ShortcutHint: separator must be a nonempty string"
							)
							if string.find(separator, "^%a+$") then
								separator = ` {separator} `
							end
							return table.concat(parts, separator)
						end,
						Size = function(use: ComposeTypes.Use)
							local side = ctx.controlSize(spec.controlSize, "iconSize", use) + 8
							return D2.fromOffset(side, side)
						end,
						AutomaticSize = E.AutomaticSize.XY,
						BackgroundTransparency = 0,
						TextXAlignment = E.TextXAlignment.Center,
					})),
					"shortcut-hint"
				)
			end
			local action = spec.action
			assert(
				action and action.IsA and action:IsA("InputAction"),
				"Facet.ShortcutHint: action must be a native InputAction"
			)
			local binding = ctx.observe.PreferredBinding(action)
			local keyNames: { [string]: string } = {
				Return = "Enter",
				KeypadEnter = "Enter",
				Escape = "Esc",
				Space = "Space",
				Backspace = "Delete",
				Tab = "Tab",
				LeftShift = "Shift",
				RightShift = "Shift",
				LeftControl = "Ctrl",
				RightControl = "Ctrl",
				LeftAlt = "Alt",
				RightAlt = "Alt",
			}
			local p = props(
				spec :: Shared.GuiObjectNativeProps,
				semantic,
				{ Size = D2.fromOffset(0, 0), AutomaticSize = E.AutomaticSize.XY, BackgroundTransparency = 0 }
			)
			table.insert(
				p,
				Compose.keyed({
					from = function(use: ComposeTypes.Use)
						local value = use(binding)
						local list: { InputBinding } = if value then { value } else {}
						return list
					end,
					render = function(_, _, current: InputBinding)
						local name, key = ctx.observe.DisplayName(current), ctx.observe.KeyCode(current)
						local primary, secondary =
							ctx.observe.PrimaryModifier(current), ctx.observe.SecondaryModifier(current)
						local image = ctx.observe.DisplayImage(current)
						local input = ctx.config.services.UserInputService
						local nativeImage = Compose.formula(function(use: ComposeTypes.Use): Content | string | nil
							local content = use(image)
							if content and content.SourceType and content.SourceType.Name ~= "None" then
								return content
							end
							if input and input.GetImageForKeyCode then
								local ok, asset = pcall(input.GetImageForKeyCode, input, use(key))
								if ok and type(asset) == "string" and asset ~= "" then
									return asset
								end
							end
							return nil
						end)
						return Host.Frame "PreferredBinding" {
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							BackgroundTransparency = 1,
							Compose.keyed({
								from = function(use: ComposeTypes.Use)
									local asset = use(nativeImage)
									return {
										if asset == nil
											then "text"
											elseif type(asset) == "string" then "Image"
											else "ImageContent",
									}
								end,
								render = function(_, _, kind: string): GuiObject
									if kind ~= "text" then
										local native: Shared.ImageLabelNativeProps = {
											Name = "Glyph",
											BackgroundTransparency = 1,
											Size = function(use: ComposeTypes.Use)
												local size = ctx.controlSize(spec.controlSize, "iconSize", use)
												return D2.fromOffset(size, size)
											end,
										}
										if kind == "Image" then
											native.Image = function(use: ComposeTypes.Use): string
												return use(nativeImage) :: string
											end
										else
											native.ImageContent = function(use: ComposeTypes.Use): Content
												return use(nativeImage) :: Content
											end
										end
										return Host.ImageLabel(native)
									end
									return ctx.text({
										Name = "Key",
										Text = function(use: ComposeTypes.Use): string
											local custom = use(name)
											if custom and custom ~= "" then
												return custom
											end
											local keys: { string } = {}
											local service = input
											for _, code in { use(primary), use(secondary), use(key) } do
												if code and code ~= noKey then
													local ok, found = true, ""
													if service and service.GetStringForKeyCode then
														ok, found = pcall(function(): string
															return service:GetStringForKeyCode(code)
														end)
													end
													local text = if ok and type(found) == "string" then found else ""
													if text == "" then
														text = keyNames[code.Name] or code.Name
													end
													table.insert(keys, text)
												end
											end
											return table.concat(keys, "+")
										end,
									})
								end,
							}),
						}
					end,
				})
			)
			return ctx.styled(Host.Frame(p :: Shared.FrameNativeProps), "shortcut-hint")
		end
	)
end
