--!strict
local decoration = require("./native_decoration")
local valueModel = require("./input_value")
local InputTypes = require("./input_types")
local Shared = require("./types")
local ThemeTypes = require("./theme_types")
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
type ToggleButtonProps = InputTypes.ButtonProps & {
	value: Shared.Value<boolean>?,
	mixed: Shared.Value<boolean>?,
	presentation: ("switch" | "checkbox" | "button")?,
	onChange: ((boolean) -> ())?,
	indicatorPosition: ("leading" | "trailing")?,
}

return function(ctx: Shared.Context, UI: InputTypes.InputControls): ()
	local runtime, Host, Compose = ctx.runtime, ctx.Host, ctx.Compose
	local read, props = ctx.read, ctx.props
	local D, D2, V2, E = ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local noKey: Enum.KeyCode = assert(E.KeyCode:FromValue(0))
	local dialogOrder = 0
	local roles: { [string]: boolean } = { default = true, cancel = true, destructive = true, onIndicator = true }
	local function dynamic(source: unknown): boolean
		return Compose.isReadable(source) or type(source) == "function"
	end
	local function enabled(
		spec: InputTypes.EnabledOptions | InputTypes.TextInputOptions | InputTypes.NumberInputOptions | InputTypes.LevelOptions | { value: Shared.Value<number>, onChange: ((number) -> ())? },
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
	local function attributes(node, values)
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
		maximum: number
	): ()
		local guiService = ctx.config.services.GuiService
		local target = guiService and guiService.SelectedObject
		local selected = Compose.cell(target ~= nil and (target == node or target:IsDescendantOf(node)))
		if guiService then
			local nativeSelection = ctx.observe(guiService, "SelectedObject")
			Compose.watch(function(use: ComposeTypes.Use)
				local target = use(nativeSelection)
				local inside = target ~= nil and (target == node or target:IsDescendantOf(node))
				if selected:peek() and not inside and cancel then
					cancel()
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
					local function bind(name, keys, source, direction)
						local action: InputAction
						action = ctx.action(node, name, keys, source, function()
							stopRepeat()
							apply(direction)
							heldAction = action
							if runtime.host.frames then
								local elapsed, deadline = 0, 0.4
								stopFrame = runtime.host.frames.onFrame(function(delta)
									if not read(source) or not ctx.available(node) then
										stopRepeat()
										return
									end
									elapsed += delta
									local steps = 0
									while elapsed >= deadline and steps < 5 do
										apply(direction)
										deadline += 0.1
										steps += 1
									end
									if steps == 5 then
										deadline = elapsed + 0.1
									end
								end)
							end
						end, {
							priority = 100,
							onReleased = function()
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
							bind(
								if direction < 0 then "DecreaseArrow" else "IncreaseArrow",
								if direction < 0
									then { E.KeyCode.Left, E.KeyCode.DPadLeft }
									else { E.KeyCode.Right, E.KeyCode.DPadRight },
								function(use: ComposeTypes.Use)
									local value = read(spec.value, use)
									return active(use) and (if direction < 0 then value > minimum else value < maximum)
								end,
								direction
							)
						end
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

	local buttonKeys = {
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
	}
	UI.Button = ctx.construct(function(spec: InputTypes.ButtonProps): TextButton
		assert(
			spec.onActivate == nil or type(spec.onActivate) == "function",
			"Facet.Button: onActivate must be a function"
		)
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet.Button: shape must be rect or circle"
		)
		assert(
			spec.corners == nil or spec.corners == "pill" or spec.corners == "square",
			"Facet.Button: corners must be pill or square"
		)
		assert(
			spec.dialogAction == nil or spec.dialogAction == "default" or spec.dialogAction == "cancel",
			"Facet.Button: invalid dialogAction"
		)
		local popTimeline = if spec.pop then runtime.timeline({ duration = 0.45, autoplay = false }) else nil
		local popStart = Compose.cell(1)
		local popScale
		if popTimeline then
			popTimeline:seek(0.45)
			popScale = Compose.formula(function(use: ComposeTypes.Use)
				if read(ctx.config.reducedMotion, use) then
					return 1
				end
				local phase = use(popTimeline.progress)
				return 1
					+ (use(popStart) - 1) * (1 - phase) ^ 3
					+ 0.25 * math.sin(math.pi * phase) * math.exp(-3 * phase)
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				if read(ctx.config.reducedMotion, use) then
					popTimeline:pause()
					popTimeline:seek(0.45)
				end
			end)
		end

		local node: TextButton
		local iconState: ComposeTypes.Cell<ThemeTypes.SkinState>?
		if spec.icon or spec.trailingIcon then
			local initial: ThemeTypes.SkinState = "default"
			iconState = Compose.cell(initial)
		end
		local held, repeated, elapsed = false, false, 0
		local repeatDelay, repeatInterval = spec.repeatDelay or 0.4, spec.repeatInterval or 0.1
		assert(
			repeatDelay > 0 and repeatDelay < math.huge and repeatInterval > 0 and repeatInterval < math.huge,
			"Facet.Button: repeat timings must be finite and positive"
		)
		local function activate(...)
			if enabled(spec) and node and ctx.available(node) and spec.onActivate then
				if popTimeline and not held and not read(ctx.config.reducedMotion) then
					popStart:set(popScale:peek())
					popTimeline:restart()
				end
				spec.onActivate(...)
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
		local selectedForKeyboard: Shared.Value<boolean>
		local fallbackSelection: ComposeTypes.Cell<boolean>?
		if guiService then
			local selected = ctx.observe(guiService, "SelectedObject")
			selectedForKeyboard = function(use: ComposeTypes.Use)
				local target = read(selected, use)
				return node and target == node or false
			end
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
		local p = props(spec, buttonKeys, {
			Text = if rich then "" else spec.label or "",
			Size = if dynamic(ctx.config.theme) or dynamic(spec.controlSize) then controlSize else controlSize(),
			AutomaticSize = E.AutomaticSize.XY,
			Selectable = enabledProperty,
			Interactable = enabledProperty,
		})
		p.Activated = function(...)
			if not repeated then
				activate(...)
			end
			repeated = false
			if spec.Activated then
				spec.Activated(...)
			end
		end

		if spec.shape == "circle" then
			if spec.Size == nil then
				p.Size = function(use: ComposeTypes.Use)
					local diameter = ctx.controlSize(spec.controlSize, "height", use)
					return D2.fromOffset(diameter, diameter)
				end
			end
			p.AutomaticSize = E.AutomaticSize.None
			table.insert(p, Host.UIAspectRatioConstraint({ AspectRatio = 1 }))
			table.insert(p, Host.UICorner({ CornerRadius = D.new(1, 0) }))
		elseif spec.corners then
			table.insert(p, Host.UICorner({ CornerRadius = D.new(if spec.corners == "pill" then 1 else 0, 0) }))
		end
		if popTimeline then
			table.insert(p, Host.UIScale({ Name = "Pop", Scale = popScale }))
		end
		if spec.busy ~= nil then
			table.insert(
				p,
				Compose.show(function(use: ComposeTypes.Use)
					return read(spec.busy, use) == true
				end, function()
					local phase = runtime.timeline({ duration = 1, repeats = math.huge })
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
								Host.Frame({
									Name = `Dot{index}`,
									Size = D2.fromOffset(4, 4),
									Position = D2.fromOffset((index - 1) * 6, 7),
									BorderSizePixel = 0,
									BackgroundTransparency = function(use: ComposeTypes.Use)
										return if read(ctx.config.reducedMotion, use)
											then 0
											else 0.2 + 0.6 * ((use(phase.progress) + index / 3) % 1)
									end,
									ctx.corner(2),
								}),
								"fill"
							)
						)
					end
					return Host.Frame(dots)
				end)
			)
		end
		if rich then
			local content: { ComposeTypes.Child } = {}
			local imageCard = spec.image ~= nil
			if imageCard then
				assert(
					type(spec.imageAspectRatio or 16 / 9) == "number" and (spec.imageAspectRatio or 16 / 9) > 0,
					"Facet.Button: imageAspectRatio must be positive"
				)
				p.Size = spec.Size or D2.fromOffset(240, 260)
				p.AutomaticSize = spec.AutomaticSize or E.AutomaticSize.None
				table.insert(
					content,
					Host.ImageLabel({
						Name = "Image",
						Image = spec.image,
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0.55, 0),
						ScaleType = if spec.imageFraming == "fit" then E.ScaleType.Fit else E.ScaleType.Crop,
						Host.UIAspectRatioConstraint({
							AspectRatio = spec.imageAspectRatio or 16 / 9,
							DominantAxis = E.DominantAxis.Width,
							AspectType = E.AspectType.FitWithinMaxSize,
						}),
					})
				)
			end
			if spec.icon then
				table.insert(content, icon(spec.icon, { Name = "LeadingIcon" }, iconState))
			end
			local row: InputTypes.Row = spec.row or {}
			local label = row.title or spec.label or spec.name or ""
			local description = row.description or spec.subtitle or spec.hint
			if not (spec.shape == "circle" and spec.icon) then
				local function caption(name: string, text: Shared.Value<string>): TextLabel
					return ctx.text({
						Name = name,
						Text = function(use: ComposeTypes.Use)
							return read(text, use) or ""
						end,
						Visible = function(use: ComposeTypes.Use)
							local value = read(text, use)
							return value ~= nil and value ~= ""
						end,
						Size = if imageCard then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
						AutomaticSize = if imageCard then E.AutomaticSize.Y else E.AutomaticSize.XY,
						TextWrapped = imageCard,
					})
				end
				table.insert(
					content,
					if description
						then ctx.column({ caption("Title", label), caption("Description", description) }, {
							Name = "Captions",
							Size = if imageCard then D2.new(1, 0, 0, 0) else D2.fromOffset(0, 0),
							AutomaticSize = if imageCard then E.AutomaticSize.Y else E.AutomaticSize.XY,
						})
						else caption("Title", label)
				)
			end
			if spec.trailingIcon then
				table.insert(content, icon(spec.trailingIcon, { Name = "TrailingIcon" }, iconState))
			end
			table.insert(
				p,
				if imageCard
					then ctx.column(content, {
						Name = "Content",
						ZIndex = 1,
						Size = D2.fromScale(1, 1),
						AutomaticSize = E.AutomaticSize.None,
						ClipsDescendants = true,
					})
					else ctx.row(
						content,
						{ Name = "Content", ZIndex = 1, AnchorPoint = V2.new(0, 0.5), Position = D2.fromScale(0, 0.5) }
					)
			)
		end
		local keyboardAttached = false
		table.insert(
			p,
			Compose.show(function(use: ComposeTypes.Use)
				keyboardAttached = keyboardAttached or (read(selectedForKeyboard, use) == true and enabled(spec, use))
				return keyboardAttached
			end, function()
				ctx.action(node, "Activate", { E.KeyCode.Return, E.KeyCode.Space }, function(use: ComposeTypes.Use)
					return read(selectedForKeyboard, use) == true and shortcutActive(use)
				end, activate, { priority = 5000 })
				return Compose.fragment(function()
					return {}
				end)
			end)
		)
		node = ctx.styled(Host.TextButton(p), "button")
		if not guiService then
			runtime.connect(node, "SelectionGained", function()
				assert(fallbackSelection):set(true)
			end)
			runtime.connect(node, "SelectionLost", function()
				assert(fallbackSelection):set(false)
			end)
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
					Text = ctx.observe(node, "Text"),
					TextColor3 = ctx.observeStyled(node, "TextColor3"),
					FontFace = ctx.observeStyled(node, "FontFace"),
					TextSize = ctx.observeStyled(node, "TextSize"),
					TextXAlignment = ctx.observeStyled(node, "TextXAlignment"),
					TextYAlignment = ctx.observeStyled(node, "TextYAlignment"),
					TextWrapped = ctx.observeStyled(node, "TextWrapped"),
					RichText = ctx.observeStyled(node, "RichText"),
					TextScaled = ctx.observeStyled(node, "TextScaled"),
					TextTruncate = ctx.observeStyled(node, "TextTruncate"),
					LineHeight = ctx.observeStyled(node, "LineHeight"),
				}
				local boundary = decoration(
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
			local size = ctx.observe(node, "AbsoluteSize")
			local measure: TextLabel
			runtime.mount(function()
				measure = ctx.text({
					Name = "FullLabelMeasure",
					Text = spec.label,
					FontFace = ctx.observeStyled(node, "FontFace"),
					TextSize = ctx.observeStyled(node, "TextSize"),
					Visible = false,
					TextWrapped = false,
				})
				return measure
			end, node)
			local bounds = ctx.observe(measure, "TextBounds")
			runtime.decorate(node, {
				Text = function(use: ComposeTypes.Use)
					local compact = use(size).X > 0 and use(bounds).X > use(size).X - 24
					return read(if compact then spec.compactLabel else spec.label, use)
				end,
			})
		end

		ctx.skin(node, "control", {
			selected = spec.selected,
			disabled = function(use: ComposeTypes.Use)
				return not enabled(spec, use)
			end,
		})

		local guiState = if iconState then ctx.observe(node, "GuiState") else nil
		local previousTags: { [string]: boolean } = {}
		local previousAttributes: { [string]: boolean | string } = {}
		local initialized = false
		local function tag(name: string, active: boolean)
			if previousTags[name] ~= active then
				previousTags[name] = active
				if active then
					node:AddTag(name)
				elseif initialized or node:HasTag(name) then
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
			for name: string in roles do
				tag("facet-role-" .. name, role == name)
			end
			tag("facet-selected", selected)
			tag("facet-busy", busy)
			tag("facet-shape-circle", spec.shape == "circle")
			tag("facet-disabled", not available)
			tag("facet-accent", appearance == "emphasis")
			attribute("selected", selected)
			attribute("busy", busy)
			attribute("appearance", appearance)
			attribute("controlSize", read(spec.controlSize, use) or "regular")
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
		if spec.repeatDelay or spec.repeatInterval or spec.onPointerDown or spec.onPointerUp then
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
					if spec.onPointerDown then
						spec.onPointerDown(input)
					end
				end
			end)
			runtime.connect(node, "InputEnded", function(input)
				if held then
					held = false
					if spec.onPointerUp then
						spec.onPointerUp(input)
					end
				end
			end)
			runtime.connect(node, "MouseLeave", function()
				if held and spec.onPointerCancel then
					spec.onPointerCancel()
				end
				held = false
			end)
			if spec.repeatDelay or spec.repeatInterval then
				Compose.cleanup(assert(runtime.host.frames).onFrame(function(delta)
					if not held then
						return
					end
					if not enabled(spec) or not ctx.available(node) then
						held = false
						return
					end
					elapsed += delta
					local threshold = if repeated then repeatInterval else repeatDelay
					if elapsed >= threshold then
						elapsed %= threshold
						repeated = true
						activate()
					end
				end))
			end
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
				table.insert(
					bindings,
					{ KeyCode = assert(E.KeyCode:FromName(shortcut.keyCode)), PrimaryModifier = shift }
				)
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
				table.insert(bindings, { KeyCode = key })
			end
		end
		if #bindings > 0 then
			local priority = 2000
			if spec.dialogAction then
				dialogOrder += 1
				priority -= dialogOrder
			end
			ctx.action(node, "Shortcut", bindings, shortcutActive, activate, {
				priority = priority,
				sink = spec.dialogAction ~= nil,
			})
		end

		return node
	end)

	UI.Toggle = ctx.construct(function(spec: InputTypes.ToggleImplementationProps): TextButton
		assert(type(read(spec.value)) == "boolean", "Facet.Toggle: value must be boolean")
		assert(writable(spec.value) or spec.onChange, "Facet.Toggle: read-only value requires onChange")
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
		p.onActivate = function()
			local value = if read(spec.mixed) then true else not read(spec.value)
			if spec.onChange then
				spec.onChange(value)
			else
				if writable(spec.mixed) then
					(spec.mixed :: ComposeTypes.Cell<boolean>):set(false)
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
			local trailing = spec.indicatorPosition == "trailing"
			local reserve = (if presentation == "switch" then 38 else 24) + 8
			local mark = ctx.styled(
				Host.Frame({
					Name = "Mark",
					AnchorPoint = V2.new(0.5, 0.5),
					Size = D2.fromOffset(
						if presentation == "switch" then 18 else 12,
						if presentation == "switch" then 18 else 12
					),
					Position = D2.fromScale(0.5, 0.5),
					ctx.corner(if presentation == "switch" then 9 else 2),
				}),
				"toggle-mark"
			)
			local indicator = ctx.styled(
				Host.Frame({
					Name = "Indicator",
					Size = D2.fromOffset(if presentation == "switch" then 38 else 24, 24),
					AnchorPoint = if rich then V2.zero else V2.new(0, 0.5),
					Position = if rich
						then D2.fromOffset(0, 0)
						elseif trailing then D2.new(1, 8, 0.5, 0)
						else D2.new(0, -reserve, 0.5, 0),
					ctx.corner(if presentation == "switch" then 12 else 4) :: ComposeTypes.Child,
					mark,
				} :: Shared.FrameNativeProps),
				"toggle-indicator"
			)
			local function updateIndicator(use)
				local value, mixed = read(spec.value, use), read(spec.mixed, use) == true
				if presentation == "switch" then
					mark.Position = D2.fromScale(if value then 0.7 else 0.3, 0.5)
				else
					mark.Size = D2.fromOffset(12, if mixed then 4 else 12)
					mark.Visible = value or mixed
				end
				indicator:SetAttribute("selected", value or mixed)
			end
			if dynamic(spec.value) or dynamic(spec.mixed) then
				Compose.watch(updateIndicator)
			else
				updateIndicator()
			end
			ctx.skin(indicator, "toggleTrack", { selected = p.selected })
			ctx.skin(mark, "toggleKnob", { selected = p.selected })
			if rich then
				p.Text = ""
				local row: InputTypes.Row = spec.row or {}
				local label: GuiObject = ctx.text({ Text = row.title or spec.label or "" })
				if row.description or spec.hint then
					label = ctx.column({ label, ctx.text({ Text = row.description or spec.hint }) })
				end
				table.insert(
					p,
					ctx.row(if spec.indicatorPosition == "trailing" then { label, indicator } else { indicator, label })
				)
			else
				p.Text = spec.Text or spec.label or ""
				p.TextXAlignment = spec.TextXAlignment or E.TextXAlignment.Left
				local reactive = dynamic(ctx.config.theme) or dynamic(spec.controlSize)
				local function paddingAmount(side: "left" | "right" | "top" | "bottom"): Shared.Value<UDim>
					local function amount(use: ComposeTypes.Use?): UDim
						local package = read(ctx.config.theme, use)
						local skin = package and package.chrome and package.chrome.control
						local insets: ThemeTypes.Insets = if skin then skin.contentInsets or {} else {}
						local base = if side == "left" or side == "right"
							then ctx.controlSize(spec.controlSize, "paddingX", use)
							else 0
						local offset = math.max(base, insets[side] or 0)
						if (trailing and side == "right") or (not trailing and side == "left") then
							offset += reserve
						end
						return D.new(0, offset)
					end
					return if reactive then amount else amount()
				end
				local padding: Shared.UIPaddingNativeProps = {
					PaddingLeft = paddingAmount("left"),
					PaddingRight = paddingAmount("right"),
					PaddingTop = paddingAmount("top"),
					PaddingBottom = paddingAmount("bottom"),
				}
				table.insert(p, Host.UIPadding(padding))
				table.insert(p, indicator)
			end
		end
		return ctx.styled(UI.Button(p), "toggle")
	end)

	local textKeys = {
		"value",
		"numericValue",
		"presentation",
		"min",
		"max",
		"parse",
		"format",
		"validate",
		"maxLength",
		"enabled",
		"disabled",
		"placeholder",
		"multiline",
		"onChange",
		"onCommit",
		"onCancel",
		"invalid",
		"clearButton",
		"clearButtonMode",
	}
	UI.TextInput = ctx.construct(function(spec: InputTypes.TextInputImplementationProps): TextBox
		assert(type(read(spec.value)) == "string", "Facet.TextInput: value must resolve to a string")
		assert(
			writable(spec.value) or type(spec.onChange) == "function",
			"Facet.TextInput: a read-only value requires onChange"
		)
		for key, callback in
			{
				parse = spec.parse,
				format = spec.format,
				validate = spec.validate,
				onChange = spec.onChange,
				onCommit = spec.onCommit,
				onCancel = spec.onCancel,
			} :: { [string]: unknown }
		do
			assert(callback == nil or type(callback) == "function", `Facet.TextInput: {key} must be a function`)
		end
		local numeric = spec.presentation == "number"
		assert(
			not numeric or writable(spec.numericValue),
			"Facet.TextInput: numeric presentation requires numericValue"
		)
		assert(not numeric or spec.multiline ~= true, "Facet.TextInput: numeric input must be single-line")
		assert(spec.enabled == nil or spec.disabled == nil, "Facet.TextInput: use enabled or disabled, not both")
		assert(
			spec.presentation == nil or table.find({ "plain", "search", "number" }, spec.presentation),
			"Facet.TextInput: invalid presentation"
		)
		for _, bound in { spec.min, spec.max } do
			assert(
				bound == nil or (type(bound) == "number" and bound == bound and math.abs(bound) < math.huge),
				"Facet.TextInput: numeric bounds must be finite"
			)
		end
		assert(spec.min == nil or spec.max == nil or spec.min <= spec.max, "Facet.TextInput: min must not exceed max")
		assert(
			spec.maxLength == nil or (spec.maxLength >= 0 and spec.maxLength % 1 == 0),
			"Facet.TextInput: maxLength must be a nonnegative integer"
		)
		assert(
			spec.invalid == nil or (Compose.isReadable(spec.invalid) and type(read(spec.invalid)) == "boolean"),
			"Facet.TextInput: invalid must be a boolean readable"
		)
		local editing = Compose.cell(false)
		local invalid = Compose.cell(false)
		local validationMessage = Compose.cell("")
		local mayReject = numeric or spec.invalid ~= nil
		local errorTimeline = if mayReject then runtime.timeline({ duration = 0.24, autoplay = false }) else nil
		if errorTimeline then
			assert(errorTimeline):seek(0.24)
		end
		local textHeight, messageHeight = Compose.cell(18), Compose.cell(0)

		local writing, disposed, snapshot = false, false, read(spec.value)
		local node: TextBox
		local function updateValue(value: string): ()
			if read(spec.value) == value then
				return
			end
			if spec.onChange then
				spec.onChange(value)
			else
				(spec.value :: ComposeTypes.Cell<string>):set(value)
			end
		end
		local function setText(value: string): ()
			if node.Text ~= value then
				writing = true
				node.Text = value
				writing = false
			end
		end
		local function markInvalid(value: boolean, message: string?): ()
			invalid:set(value)
			validationMessage:set(if value then message or "Check this value." else "")
			if writable(spec.invalid) then
				(spec.invalid :: ComposeTypes.Cell<boolean>):set(value)
			end
			if value and errorTimeline and not read(ctx.config.reducedMotion) then
				errorTimeline:restart()
			end
		end

		local function normalize(text: string): string?
			local length = utf8.len(text)
			if length == nil then
				return nil
			end
			if spec.maxLength and length > spec.maxLength then
				text = string.sub(text, 1, (utf8.offset(text, spec.maxLength + 1) :: number) - 1)
			end
			local normalized = if spec.validate then spec.validate(text) else text
			if type(normalized) ~= "string" or utf8.len(normalized) == nil then
				return nil
			end
			return normalized
		end
		local function propose(text: string): ()
			if disposed or not enabled(spec) then
				return
			end
			local accepted = normalize(text)
			if accepted == nil then
				setText(read(spec.value))
				return
			end
			updateValue(accepted)
			setText(read(spec.value))
		end
		local function cancel()
			if not editing:peek() then
				return
			end
			editing:set(false)
			updateValue(snapshot)
			setText(read(spec.value))
			if node:IsFocused() then
				node:ReleaseFocus(false)
			end
			if spec.onCancel then
				spec.onCancel()
			end
		end
		local function commit(reason: InputTypes.CommitReason): ()
			if disposed or not editing:peek() then
				return
			end
			editing:set(false)
			if not enabled(spec) then
				return
			end
			local value = read(spec.value)
			if numeric then
				local ok, number = pcall(function(text: string): number?
					return if spec.parse then spec.parse(text) else tonumber(text)
				end, value)
				if
					not ok
					or type(number) ~= "number"
					or number ~= number
					or math.abs(number) == math.huge
					or (spec.min and number < spec.min)
					or (spec.max and number > spec.max)
				then
					markInvalid(
						true,
						if not ok
								or type(number) ~= "number"
								or number ~= number
								or math.abs(number) == math.huge
							then "Enter a valid number."
							elseif spec.min and number < spec.min then `Enter a value of at least {spec.min}.`
							else `Enter a value of at most {spec.max}.`
					)
					return
				end
				local formattedOk, formatted = pcall(function(value: number): string
					return if spec.format then spec.format(value) else tostring(value)
				end, number)
				if not formattedOk or type(formatted) ~= "string" or utf8.len(formatted) == nil then
					markInvalid(true)
					return
				end
				if spec.validate then
					local valid, normalized = pcall(spec.validate, formatted)
					if not valid or type(normalized) ~= "string" or utf8.len(normalized) == nil then
						markInvalid(true)
						return
					end
					formatted = normalized
				end
				if spec.maxLength and utf8.len(formatted) > spec.maxLength then
					markInvalid(true)
					return
				end
				local accepted = false
				runtime:batch(function()
					updateValue(formatted)
					accepted = read(spec.value) == formatted
					if accepted then
						assert(spec.numericValue):set(number)
					end
				end)
				if not accepted then
					setText(read(spec.value))
					markInvalid(true)
					return
				end
				value = formatted
				setText(formatted)
				markInvalid(false)
			else
				local normalized = normalize(value)
				if normalized == nil then
					markInvalid(true)
					return
				end
				value = normalized
				updateValue(value)
				if read(spec.value) ~= value then
					setText(read(spec.value))
					markInvalid(true)
					return
				end
				setText(value)
			end
			if spec.onCommit then
				spec.onCommit(value, reason)
			end
		end
		local p = props(spec, textKeys, {
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(
					240,
					if use(validationMessage) ~= "" then math.max(44, use(textHeight) + use(messageHeight) + 16) else 44
				)
			end,
			Text = read(spec.value),
			PlaceholderText = spec.placeholder or "",
			ClearTextOnFocus = false,
			MultiLine = spec.multiline == true,
			TextXAlignment = E.TextXAlignment.Left,
			TextYAlignment = if mayReject then E.TextYAlignment.Top else E.TextYAlignment.Center,
			TextEditable = function(use: ComposeTypes.Use)
				return enabled(spec, use)
			end,
			Selectable = function(use: ComposeTypes.Use)
				return enabled(spec, use)
			end,
		})
		p.Focused = function(...)
			if enabled(spec) and not editing:peek() then
				snapshot = read(spec.value)
				editing:set(true)
			end
			if spec.Focused then
				spec.Focused(...)
			end
		end
		p.FocusLost = function(enterPressed, input)
			if input and (input.KeyCode == E.KeyCode.Escape or input.KeyCode == E.KeyCode.ButtonB) then
				cancel()
			else
				commit(if enterPressed then "submit" else "focusLost")
			end
			if spec.FocusLost then
				spec.FocusLost(enterPressed, input)
			end
		end
		table.insert(p, ctx.padding(10, 6))

		local messageNode
		if mayReject then
			messageNode = ctx.styled(
				ctx.text({
					Name = "ValidationMessage",
					Text = validationMessage,
					Visible = function(use: ComposeTypes.Use)
						return use(validationMessage) ~= ""
					end,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					TextWrapped = true,
					Position = function(use: ComposeTypes.Use)
						return D2.fromOffset(0, use(textHeight) + 4)
					end,
				}),
				"validation"
			)
			table.insert(p, messageNode)
			table.insert(
				p,
				Host.UIScale({
					Name = "ValidationPulse",
					Scale = function(use: ComposeTypes.Use)
						if read(ctx.config.reducedMotion, use) then
							return 1
						end
						local phase = use(assert(errorTimeline).progress)
						return 1 - 0.03 * math.sin(math.pi * phase) * (1 - phase)
					end,
				})
			)
		end

		local mode = spec.clearButtonMode
			or (if spec.clearButton or spec.presentation == "search" then "always" else "never")
		assert(
			table.find({ "always", "never", "whileEditing", "unlessEditing" }, mode),
			"Facet.TextInput: invalid clearButtonMode"
		)
		if mode ~= "never" then
			table.insert(
				p,
				UI.Button({
					Name = "Clear",
					label = "Clear",
					Size = D2.fromOffset(44, 32),
					AutomaticSize = E.AutomaticSize.None,
					AnchorPoint = V2.new(1, 0.5),
					Position = D2.fromScale(1, 0.5),
					Visible = function(use: ComposeTypes.Use)
						return enabled(spec, use)
							and read(spec.value, use) ~= ""
							and (
								mode == "always"
								or (mode == "whileEditing" and use(editing))
								or (mode == "unlessEditing" and not use(editing))
							)
					end,
					onActivate = function()
						propose("")
					end,
				})
			)
		end
		node = ctx.styled(ctx.styled(ctx.styled(Host.TextBox(p), "text"), "field"), "text-input")
		if messageNode then
			local bounds, messageBounds = ctx.observe(node, "TextBounds"), ctx.observe(messageNode, "TextBounds")
			Compose.watch(function(use: ComposeTypes.Use)
				textHeight:set(use(bounds).Y)
				messageHeight:set(use(messageBounds).Y)
			end)
			local wasInvalid = false
			Compose.watch(function(use: ComposeTypes.Use)
				local sourceInvalid = read(spec.invalid, use) == true
				if sourceInvalid and not wasInvalid and not invalid:peek() then
					markInvalid(true)
				end
				if not sourceInvalid and wasInvalid then
					markInvalid(false)
				end
				wasInvalid = sourceInvalid
				if read(ctx.config.reducedMotion, use) then
					assert(errorTimeline):pause()
					assert(errorTimeline):seek(0.24)
				end
			end)
		end
		ctx.action(node, "TextEditing", {
			E.KeyCode.Up,
			E.KeyCode.Down,
			E.KeyCode.Left,
			E.KeyCode.Right,
			E.KeyCode.DPadUp,
			E.KeyCode.DPadDown,
			E.KeyCode.DPadLeft,
			E.KeyCode.DPadRight,
		}, editing, function() end, { priority = 10000 })

		local _, editingContext = ctx.action(
			node,
			"Cancel",
			{ E.KeyCode.Escape, E.KeyCode.ButtonB },
			editing,
			cancel,
			{ priority = 10000 }
		)
		local nativeEditingAvailable = ctx.observe(editingContext, "Enabled")
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(nativeEditingAvailable) and editing:peek() then
				editing:set(false)
				if node:IsFocused() then
					node:ReleaseFocus(false)
				end
			end
		end)
		runtime.connect(node, "ReturnPressedFromOnScreenKeyboard", function()
			if spec.multiline ~= true then
				commit("submit")
				if node:IsFocused() then
					node:ReleaseFocus(false)
				end
			end
		end)
		attributes(node, {
			invalid = function(use: ComposeTypes.Use)
				return use(invalid) or read(spec.invalid, use) == true
			end,
			validationMessage = validationMessage,
		})
		Compose.cleanup(assert(runtime.host.observation).observeProperty(node, "Text", function()
			if not writing and editing:peek() then
				propose(node.Text)
			end
		end))
		Compose.watch(function(use: ComposeTypes.Use)
			setText(read(spec.value, use))
			if enabled(spec, use) then
				node:RemoveTag("facet-disabled")
			else
				node:AddTag("facet-disabled")
			end
			if not enabled(spec, use) and editing:peek() then
				editing:set(false)
				if node:IsFocused() then
					node:ReleaseFocus(false)
				end
			end
		end)

		Compose.cleanup(function()
			disposed = true
		end)
		ctx.skin(node, "field", {
			disabled = function(use: ComposeTypes.Use)
				return not enabled(spec, use)
			end,
		})
		return node
	end)

	UI.Stepper = ctx.construct(function(spec: InputTypes.StepperImplementationProps): Frame
		requireValue(spec, "number", "Stepper")
		local modelSpec = table.clone(spec) :: valueModel.Options
		modelSpec.step = spec.step or 1
		local model = valueModel(modelSpec, read)
		local function adjust(direction)
			if enabled(spec) then
				changed(spec, model.stepped(read(spec.value), direction))
			end
		end
		local parts: { ComposeTypes.Child } = {}
		if spec.label then
			table.insert(parts, ctx.text({ Text = spec.label }))
		end
		table.insert(
			parts,
			UI.Button({
				Name = "Decrease",
				label = "−",
				enabled = function(use: ComposeTypes.Use)
					return enabled(spec, use) and read(spec.value, use) > model.min
				end,
				onActivate = function()
					adjust(-1)
				end,
			})
		)
		table.insert(
			parts,
			ctx.text({
				Name = "Value",
				Text = function(use: ComposeTypes.Use)
					return model.format(read(spec.value, use))
				end,
			})
		)
		table.insert(
			parts,
			UI.Button({
				Name = "Increase",
				label = "+",
				enabled = function(use: ComposeTypes.Use)
					return enabled(spec, use) and read(spec.value, use) < model.max
				end,
				onActivate = function()
					adjust(1)
				end,
			})
		)
		local p = props(spec, { "value", "min", "max", "step", "format", "enabled", "onChange", "label" }, {
			Selectable = true,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = E.AutomaticSize.XY,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
		table.insert(p, ctx.row(parts, { Name = "Content", ZIndex = 1 }))
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
				Host.ImageLabel({
					Name = "Artwork",
					Image = image,
					BackgroundTransparency = 1,
					Size = D2.fromScale(1, 1),
					ScaleType = E.ScaleType.Stretch,
				})
			)
		end
		local node = ctx.styled(Host.Frame(native), role)
		if not image then
			ctx.skin(node, slot)
		end
		return node
	end

	UI.Slider = ctx.construct(function(spec: InputTypes.SliderImplementationProps): Frame
		requireValue(spec, "number", "Slider")
		local model = valueModel(spec :: valueModel.Options, read)
		local track: Frame
		local dragging: boolean?
		local snapshot: number?
		local function apply(value)
			if enabled(spec) then
				return changed(spec, model.quantize(value))
			end
			return false
		end
		local function fromPosition(position: Vector2): ()
			local width = track.AbsoluteSize.X
			if width > 0 then
				apply(model.fromFraction((position.X - track.AbsolutePosition.X) / width))
			end
		end
		local function cancel()
			if dragging then
				dragging = false
				if snapshot ~= nil then
					changed(spec, assert(snapshot))
				end
			end
		end
		local detector = Host.UIDragDetector({
			Name = "Drag",
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use: ComposeTypes.Use)
				return enabled(spec, use)
			end,
			DragStart = function(position)
				if enabled(spec) then
					dragging, snapshot = true, read(spec.value)
					if spec.tapToPosition ~= false then
						fromPosition(position)
					end
				end
			end,
			DragContinue = function(position)
				if dragging then
					fromPosition(position)
				end
			end,
			DragEnd = function()
				if not dragging then
					return
				end
				dragging = false
				if spec.onCommit then
					spec.onCommit(read(spec.value))
				end
			end,
		})
		track = ctx.styled(
			Host.Frame({
				Name = "Track",
				Size = D2.new(1, 0, 0, 44),
				BackgroundTransparency = 1,
				Selectable = function(use: ComposeTypes.Use)
					return enabled(spec, use)
				end,
				paintedPart({
					Name = "Rail",
					Size = D2.new(1, 0, 0, 6),
					Position = D2.fromScale(0, 0.5),
					AnchorPoint = V2.new(0, 0.5),
					ctx.corner(3),
				}, spec.trackImage, "slider-rail", "sliderTrack") :: ComposeTypes.Child,
				ctx.styled(
					Host.Frame({
						Name = "Fill",
						Size = function(use: ComposeTypes.Use)
							return D2.new(model.fraction(read(spec.value, use)), 0, 0, 6)
						end,
						Position = D2.fromScale(0, 0.5),
						AnchorPoint = V2.new(0, 0.5),
						ctx.corner(3),
					}),
					"slider-fill"
				),
				paintedPart({
					Name = "Thumb",
					Size = D2.fromOffset(24, 24),
					AnchorPoint = V2.new(0.5, 0.5),
					Position = function(use: ComposeTypes.Use)
						return D2.fromScale(model.fraction(read(spec.value, use)), 0.5)
					end,
					ctx.corner(12),
				}, spec.thumbImage, "slider-thumb", "sliderThumb"),
				detector :: ComposeTypes.Child,
			} :: Shared.FrameNativeProps),
			"slider-track"
		)
		local fill = assert(track:FindFirstChild("Fill"))
		assert(fill:IsA("Frame"))
		ctx.skin(fill, "barFill")
		local input = ctx.config.services.UserInputService
		if input then
			local preferred = ctx.observe(input, "PreferredInput")
			Compose.watch(function(use: ComposeTypes.Use)
				if use(preferred) == E.PreferredInput.Gamepad then
					cancel()
				end
			end)
		end
		adjustment(track, spec, function(direction)
			if apply(model.stepped(read(spec.value), direction)) and spec.onCommit then
				spec.onCommit(read(spec.value))
			end
		end, cancel, model.min, model.max)
		Compose.watch(function(use: ComposeTypes.Use)
			if not enabled(spec, use) then
				cancel()
			end
		end)
		local readout = ctx.text({
			Name = "Value",
			Text = function(use: ComposeTypes.Use)
				return model.format(read(spec.value, use))
			end,
		})
		local parts: { ComposeTypes.Child } = {}
		if spec.row then
			local row = spec.row
			local header = { readout }
			if spec.label or row.title then
				table.insert(
					header,
					1,
					ctx.text({
						Name = "Label",
						Text = row.title or spec.label,
						Size = D2.fromOffset(0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
					})
				)
			end
			table.insert(
				parts,
				ctx.row(header, { Name = "Header", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
			)
			if row.description then
				table.insert(
					parts,
					ctx.text({
						Name = "Description",
						Text = row.description,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						TextWrapped = true,
					})
				)
			end
			table.insert(parts, track)
		else
			if spec.label then
				table.insert(parts, ctx.text({ Name = "Label", Text = spec.label }))
			end
			runtime.decorate(track, { Size = D2.fromOffset(0, 44) })
			runtime.mount(function()
				return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
			end, track)
			table.insert(parts, track)
			table.insert(parts, readout)
		end
		local native = props(spec, {
			"value",
			"min",
			"max",
			"step",
			"format",
			"enabled",
			"onChange",
			"onCommit",
			"label",
			"tapToPosition",
			"row",
			"thumbImage",
			"trackImage",
		}, { Size = D2.fromOffset(240, 0), AutomaticSize = E.AutomaticSize.Y })
		local node = ctx.styled(if spec.row then ctx.column(parts, native) else ctx.row(parts, native), "slider")
		if not spec.row then
			assert(node:FindFirstChildWhichIsA("UIListLayout")).VerticalAlignment = E.VerticalAlignment.Center
		end
		valueAttributes(node, spec, model)
		return node
	end)

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
		local markSize = ({ small = 20, medium = 28, large = 36 })[spec.starSize or spec.segmentSize or "small"]
		assert(markSize, "Facet.LevelPicker: invalid size")
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
			local native: Shared.TextLabelNativeProps & Shared.ImageLabelNativeProps & Shared.FrameNativeProps = {
				Name = `Level{index}`,
				Size = D2.fromOffset(markSize, markSize),
				BackgroundTransparency = 1,
				Selectable = false,
			}
			local mark: GuiObject
			local paint: "TextColor3" | "ImageColor3" | "BackgroundColor3"
			if segment == "glyph" then
				native.TextSize = markSize
				native.TextXAlignment = E.TextXAlignment.Center
				native.Text = function(use: ComposeTypes.Use)
					return if filled(use) then glyphs.filled else glyphs.empty
				end
				mark, paint = ctx.text(native), "TextColor3"
			elseif segment == "image" then
				assert(
					spec.images and spec.images.filled and spec.images.empty,
					"Facet.LevelPicker: image segments require filled and empty images"
				)
				native.Image = function(use: ComposeTypes.Use)
					return if filled(use) then spec.images.filled else spec.images.empty
				end
				mark, paint = Host.ImageLabel(native), "ImageColor3"
			else
				native.BackgroundTransparency = function(use: ComposeTypes.Use)
					return if filled(use) then 0 else 0.65
				end
				native.Size = D2.fromOffset(markSize, markSize * index / count)
				table.insert(native, ctx.corner(2))
				mark, paint = ctx.styled(Host.Frame(native), "fill"), "BackgroundColor3"
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
			Host.UIListLayout({
				FillDirection = E.FillDirection.Horizontal,
				SortOrder = E.SortOrder.LayoutOrder,
				VerticalAlignment = E.VerticalAlignment.Bottom,
				Padding = D.new(0, 2),
			}),
		}
		for index, mark in marks do
			runtime.decorate(mark, { LayoutOrder = index })
			table.insert(contentProps, mark)
		end
		local markContent = Host.Frame(contentProps)

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
				Text = "",
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = D2.fromOffset(count * markSize + math.max(0, count - 1) * 2, math.max(44, markSize)),
				Selectable = interactive,
				Interactable = interactive,
				markContent :: ComposeTypes.Child,
				Host.UIDragDetector({
					Name = "Scrub",
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
				}),
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
		attributes(root, {
			value = spec.value,
			minimum = minimum,
			maximum = count,
			semanticValue = function(use: ComposeTypes.Use)
				return `{read(spec.value, use)} of {minimum} to {count}`
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
			local preference = ctx.observe(input, "PreferredInput")
			Compose.watch(function(use: ComposeTypes.Use)
				if use(preference) == E.PreferredInput.Gamepad then
					cancel()
				end
			end)
		end
		return root
	end

	UI.Rating = ctx.construct(function(spec: InputTypes.RatingProps): TextButton
		return level(spec, true)
	end)
	UI.LevelPicker = ctx.construct(function(spec: InputTypes.LevelPickerProps): TextButton
		return level(spec, false)
	end)
	UI.Chip = ctx.construct(function(spec: InputTypes.ChipImplementationProps): TextButton | Frame
		assert(
			spec.selected == nil or writable(spec.selected) or type(spec.onToggle) == "function",
			"Facet.Chip: read-only selected requires onToggle"
		)
		assert(spec.selected ~= nil or spec.onRemove, "Facet.Chip: selected or onRemove is required")
		local p = table.clone(
			spec :: Shared.TextButtonNativeProps & InputTypes.ButtonVisualOptions & InputTypes.ButtonInputOptions
		) :: InputTypes.ButtonProps & {
			onToggle: ((boolean) -> ())?,
			onRemove: (() -> ())?,
			removeLabel: Shared.Value<string>?,
			removeFocusFallback: Shared.Value<GuiObject?>?,
			leading: Instance?,
			trailing: Instance?,
		}
		p.onToggle, p.onRemove, p.removeLabel, p.removeFocusFallback, p.leading, p.trailing =
			nil, nil, nil, nil, nil, nil
		p.ref = nil
		p.onActivate = function()
			if spec.selected then
				local value = not read(spec.selected)
				if spec.onToggle then
					spec.onToggle(value)
				else
					(spec.selected :: ComposeTypes.Cell<boolean>):set(value)
				end
			end
		end
		p.Selectable = function(use: ComposeTypes.Use)
			return spec.selected ~= nil and enabled(spec, use)
		end
		if spec.leading or spec.trailing then
			p.Text = ""
			local contents: { ComposeTypes.Child } = {}
			if spec.leading then
				table.insert(contents, spec.leading)
			end
			table.insert(contents, ctx.text({ Text = spec.label or "" }))
			if spec.trailing then
				table.insert(contents, spec.trailing)
			end
			table.insert(p, ctx.row(contents))
		end
		local rootProps: Shared.FrameNativeProps = {}
		if spec.onRemove then
			rootProps.Name, p.Name = p.Name, nil
			rootProps.Size, p.Size = p.Size, nil
			rootProps.Position, p.Position = p.Position, nil
			rootProps.AnchorPoint, p.AnchorPoint = p.AnchorPoint, nil
			rootProps.LayoutOrder, p.LayoutOrder = p.LayoutOrder, nil
			rootProps.Visible, p.Visible = p.Visible, nil
			rootProps.ZIndex, p.ZIndex = p.ZIndex, nil

			p.Name = "Body"
		end
		local body = UI.Button(p)
		if not spec.onRemove then
			return ctx.styled(body, "chip")
		end
		local root: Frame
		local remove: TextButton
		local pendingFocus: GuiObject?
		local gui = ctx.config.services.GuiService
		local function candidate()
			if root.Parent then
				local siblings = root.Parent:GetChildren()
				local ordinal = {}
				for index, sibling in siblings do
					ordinal[sibling] = index
				end
				table.sort(siblings, function(a, b)
					local first = if a:IsA("GuiObject") then a.LayoutOrder else 0
					local second = if b:IsA("GuiObject") then b.LayoutOrder else 0
					return if first == second then ordinal[a] < ordinal[b] else first < second
				end)
				local index = table.find(siblings, root)
				local function target(at: number): GuiButton?
					local sibling = siblings[at]
					if sibling then
						for _, child in sibling:GetDescendants() do
							if
								child.Name == "Remove"
								and child:IsA("GuiButton")
								and child.Selectable
								and ctx.available(child)
							then
								return child
							end
						end
					end
					return nil
				end
				if index then
					for at = index + 1, #siblings do
						local node = target(at)
						if node then
							return node
						end
					end
					for at = index - 1, 1, -1 do
						local node = target(at)
						if node then
							return node
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
				and (gui.SelectedObject == remove or gui.SelectedObject == nil)
			then
				gui.SelectedObject = pendingFocus
			end
			pendingFocus = nil
		end
		remove = UI.Button({
			Name = "Remove",
			label = spec.removeLabel or "Remove",
			enabled = spec.enabled,
			onActivate = function()
				if gui and gui.SelectedObject == remove then
					pendingFocus = candidate()
				end
				spec.onRemove()
				if root.Parent == nil then
					restore()
				end
			end,
		})
		root = ctx.styled(ctx.row({ body, remove }, rootProps), "chip")
		Compose.cleanup(restore)
		return root
	end)

	UI.ShortcutHint = ctx.construct(function(spec: InputTypes.ShortcutHintImplementationProps): TextLabel | Frame
		assert((spec.action == nil) ~= (spec.keys == nil), "Facet.ShortcutHint: supply action or keys")
		local semantic = { "action", "keys", "separator", "controlSize", "over" }
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
							assert(type(chord) == "table" and #chord > 0, "Facet.ShortcutHint: chords cannot be empty")
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
						return table.concat(parts, separator)
					end,
					Size = function(use: ComposeTypes.Use)
						return D2.fromOffset(0, ctx.controlSize(spec.controlSize, "iconSize", use) + 8)
					end,
					AutomaticSize = E.AutomaticSize.X,
				})),
				"shortcut-hint"
			)
		end
		local action = spec.action
		assert(
			action and action.IsA and action:IsA("InputAction"),
			"Facet.ShortcutHint: action must be a native InputAction"
		)
		local binding = ctx.observe(action, "PreferredBinding")
		local p = props(
			spec :: Shared.GuiObjectNativeProps,
			semantic,
			{ Size = D2.fromOffset(0, 0), AutomaticSize = E.AutomaticSize.XY, BackgroundTransparency = 1 }
		)
		table.insert(
			p,
			Compose.keyed({
				from = function(use: ComposeTypes.Use)
					local value = use(binding)
					return if value then { value } else {}
				end,
				render = function(_, _, current: InputBinding)
					local name, key = ctx.observe(current, "DisplayName"), ctx.observe(current, "KeyCode")
					local primary, secondary =
						ctx.observe(current, "PrimaryModifier"), ctx.observe(current, "SecondaryModifier")
					local image = ctx.observe(current, "DisplayImage")
					local input = ctx.config.services.UserInputService
					local nativeImage = Compose.formula(function(use: ComposeTypes.Use): Content | string | nil
						local content = use(image)
						if content and content.SourceType and content.SourceType.Name ~= "None" then
							return content
						end
						if input and input.GetImageForKeyCode then
							local asset = input:GetImageForKeyCode(use(key))
							if asset ~= "" then
								return asset
							end
						end
						return nil
					end)
					return Host.Frame({
						Name = "PreferredBinding",
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
							render = function(_, _, kind)
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
									Text = function(use: ComposeTypes.Use)
										local custom = use(name)
										if custom and custom ~= "" then
											return custom
										end
										local keys = {}
										for _, code in { use(primary), use(secondary), use(key) } do
											if code and code ~= noKey then
												table.insert(
													keys,
													if input and input.GetStringForKeyCode
														then input:GetStringForKeyCode(code)
														else code.Name
												)
											end
										end
										return table.concat(keys, "+")
									end,
								})
							end,
						}),
					})
				end,
			})
		)
		return ctx.styled(Host.Frame(p :: Shared.FrameNativeProps), "shortcut-hint")
	end)
end
