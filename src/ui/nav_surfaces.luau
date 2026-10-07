--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local materialize = require("./materialize")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local Overlay = require("./overlay_types")
local motionLevels = require("./motion")
local reducedMotion = motionLevels.reduced

type Controls = {
	DisclosureGroup: Types.Constructor<Nav.DisclosureGroupSpec, Frame>,
	CollapsibleView: Types.Constructor<Nav.CollapsibleViewSpec, TextButton>,
	Alert: Nav.AlertConstructor,
	Callout: Types.Constructor<Nav.CalloutSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
	Toggle: Types.Constructor<Inputs.ToggleProps, TextButton>,
	Picker: Nav.PickerConstructor,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local lists = layoutKit.of(ctx)
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	type CalloutRegistration = { id: number, eligible: ComposeTypes.Readable<boolean>, priority: number }
	local callouts = Compose.cell({} :: { CalloutRegistration })
	local nextCallout = 0
	local function body(content: Nav.Content): Instance
		return if type(content) == "function" then content() else content
	end
	local function empty(spec: Types.FrameProps, keys: { string }, name: string): Frame
		return Host.Frame(
			ctx.props(spec, keys, { Name = name, BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
	end
	local function presented<P>(
		spec: { isPresented: ComposeTypes.Cell<boolean>?, item: ComposeTypes.Cell<P?>? }
	): ComposeTypes.Body<boolean>
		assert(spec.isPresented or spec.item, "A presented control requires isPresented or item")
		return function(use: ComposeTypes.Use)
			return if spec.item then use(spec.item) ~= nil else use(assert(spec.isPresented))
		end
	end
	local function dismiss<P>(spec: {
		isPresented: ComposeTypes.Cell<boolean>?,
		item: ComposeTypes.Cell<P?>?,
		error: ComposeTypes.Cell<string?>?,
	}): ()
		if spec.item then
			spec.item:set(nil)
		end
		if spec.isPresented then
			spec.isPresented:set(false)
		end
		if spec.error and spec.error.set then
			spec.error:set(nil)
		end
	end

	local function revealMotion(expanded: ComposeTypes.Cell<boolean>): ((ComposeTypes.Use?) -> number, ComposeTypes.Readable<boolean>, (
		ComposeTypes.Use
	) -> number)
		local level = motionLevels.level(ctx)
		local reveal, fade = ctx.motionTiming("reveal"), ctx.motionEase("fade")
		local function motion(
			share: (ComposeTypes.Use) -> number,
			ease: ComposeTypes.Easing?,
			fades: boolean
		): (ComposeTypes.Use?) -> number
			local value = runtime.tween(function(use: ComposeTypes.Use): number
				return if use(expanded) then 1 else 0
			end, {
				seconds = function(use: ComposeTypes.Use): number
					if fades and level() == "limited" then
						return ctx.metric("motion.reducedFade", use)
					end
					return share(use) * (if expanded:peek() then reveal.enter else reveal.exit)
				end,
				ease = ease,
			})
			return function(use: ComposeTypes.Use?): number
				local current = level(use)
				if current == "none" or (current == "limited" and not fades) then
					return if read(expanded, use) then 1 else 0
				end
				return read(value, use)
			end
		end
		local progress, opacity =
			motion(function()
				return 1
			end, ctx.motionEase("present"), false), motion(function(use: ComposeTypes.Use): number
				return ctx.metric("motion.revealFadeShare", use)
			end, function(t: number): number
				return if level() == "limited" then fade(t) else t
			end, true)
		return progress,
			Compose.formula(function(use: ComposeTypes.Use): boolean
				return progress(use) <= 0
			end),
			function(use: ComposeTypes.Use): number
				return 1 - opacity(use)
			end
	end
	local function unroll(progress: (ComposeTypes.Use?) -> number, natural: ComposeTypes.Readable<Vector2>)
		return function(use: ComposeTypes.Use): Enum.AutomaticSize
			return if progress(use) >= 1 then E.AutomaticSize.Y else E.AutomaticSize.None
		end, function(use: ComposeTypes.Use): number?
			local amount = progress(use)
			return if amount >= 1 then nil else math.floor(use(natural).Y * amount + 0.5)
		end
	end

	UI.DisclosureGroup = ctx.construct("DisclosureGroup", function(spec: Nav.DisclosureGroupSpec): Frame
		assert(
			type(spec.expanded) == "table" and spec.expanded.set,
			"DisclosureGroup.expanded requires a writable Compose cell"
		)
		local gui = surfaces.service("GuiService")
		local side = spec.chevronPosition or "leading"
		assert(side == "leading" or side == "trailing", "Invalid DisclosureGroup.chevronPosition")
		assert(
			spec.appearance == nil or table.find({ "plain", "contained", "divided", "outline" }, spec.appearance),
			"Invalid DisclosureGroup.appearance"
		)
		local indent = spec.indent
		assert(
			indent == nil
				or (type(indent) == "number" and indent >= 0 and indent < math.huge)
				or (type(indent) == "string" and table.find({ "xs", "s", "m", "l", "xl" }, indent) ~= nil),
			"DisclosureGroup.indent must be a spacing step or a number of pixels"
		)
		local function chevron(use: ComposeTypes.Use): string
			return if use(spec.expanded) then "chevron.down" else "chevron.trailing"
		end
		local header = UI.Button "Header" {
			label = spec.label,
			icon = if side == "leading" then chevron else spec.icon,
			trailingIcon = if side == "trailing" then chevron else spec.icon,
			subtitle = spec.description,
			enabled = spec.enabled,
			textSize = spec.textSize,
			Size = D2.new(1, 0, 0, 44),
			selected = if spec.appearance == "outline" then nil else spec.expanded,
			appearance = if spec.appearance == "outline" then "utility" else nil,
			TextXAlignment = if spec.appearance == "outline" then E.TextXAlignment.Left else nil,
			onActivate = function()
				local value = not spec.expanded:peek()
				spec.expanded:set(value)
				if spec.onToggle then
					spec.onToggle(value)
				end
			end,
		}

		local headerContent = header:FindFirstChild("Content")
		local headerLayout = headerContent and headerContent:FindFirstChildWhichIsA("UIListLayout")
		if headerContent and headerLayout then
			headerLayout.HorizontalAlignment = E.HorizontalAlignment.Left
			local captions = headerContent:FindFirstChild("Captions")
			local words = captions or headerContent:FindFirstChild("Title")
			if words and (side == "trailing" or captions) then
				runtime.mount(function()
					return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
				end, words)
			end
			local caption = captions and captions:FindFirstChild("Description")
			if caption and caption:IsA("TextLabel") then
				caption.TextWrapped = true
			end
		end

		local progress, closed, hidden = revealMotion(spec.expanded)
		local caret = header:FindFirstChild(if side == "leading" then "LeadingIcon" else "TrailingIcon", true)
		if caret and caret:IsA("GuiObject") then
			runtime.decorate(caret, {
				Rotation = function(use: ComposeTypes.Use)
					local amount = progress(use)
					return if use(spec.expanded) then -90 * (1 - amount) else 90 * amount
				end,
			})
		end

		local root = ctx.column(
			{
				header,
				Compose.presence(spec.expanded, function(phase: Nav.PresencePhase)
					local node: Instance = body(spec.content)
					if spec.appearance == "divided" then
						node = ctx.column({
							ctx.styled(
								Host.Frame "Divider" { BorderSizePixel = 0, Size = D2.new(1, 0, 0, 1) },
								"divider"
							),
							node,
						})
					end
					local outline = spec.appearance == "outline"
					local function side(use: ComposeTypes.Use): number
						return if outline then 0 else ctx.controlSize(nil, "paddingX", use)
					end
					local inset = Host.UIPadding({
						PaddingTop = ctx.types.UDim.new(0, 8),
						PaddingBottom = ctx.types.UDim.new(0, 8),
						PaddingRight = function(use: ComposeTypes.Use)
							return ctx.types.UDim.new(0, side(use))
						end,
						PaddingLeft = function(use: ComposeTypes.Use)
							local step = indent
							return ctx.types.UDim.new(
								0,
								if type(step) == "number"
									then step
									elseif step then ctx.metric("space." .. step, use)
									else side(use)
							)
						end,
					})
					local fade = ctx.fade {
						Name = "RevealFade",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						GroupTransparency = hidden,
						node,
					}
					surfaces.attach(fade, { inset :: Types.Child })
					local automatic, height = unroll(progress, ctx.observe.AbsoluteSize(fade))
					local reveal = Host.Frame "Reveal" {
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						LayoutOrder = 2,
						Interactable = function(use: ComposeTypes.Use)
							return not use(phase.exiting)
						end,
						AutomaticSize = automatic,
						Size = function(use: ComposeTypes.Use)
							return D2.new(1, 0, 0, height(use) or 0)
						end,
						fade,
					}
					local function handBack()
						if gui and surfaces.within(gui.SelectedObject, reveal) and header.Parent then
							gui.SelectedObject = header
						end
					end
					Compose.watch(function(use: ComposeTypes.Use)
						if use(phase.exiting) then
							handBack()
						end
					end)
					Compose.cleanup(handBack)
					surfaces.keep(spec.content)
					return reveal
				end, {
					exit = function()
						return { completed = closed }
					end,
				}),
			},
			ctx.props(spec, {
				"label",
				"expanded",
				"content",
				"enabled",
				"onToggle",
				"description",
				"icon",
				"chevronPosition",
				"appearance",
				"controlSize",
				"textSize",
				"indent",
			}, { Name = "DisclosureGroup", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		)
		local rhythm = root:FindFirstChildWhichIsA("UIListLayout")
		if rhythm then
			runtime.decorate(rhythm, { Padding = ctx.types.UDim.new(0, 0) })
		end
		ctx.styled(root, "disclosure-group")
		if spec.appearance == "contained" then
			ctx.styled(root, "panel")
			runtime.decorate(root, { BackgroundTransparency = 0 })
			surfaces.skin(root, "panel")
		end
		if spec.appearance then
			ctx.styled(root, "disclosure-" .. spec.appearance)
		end
		return root
	end)

	UI.CollapsibleView = ctx.construct("CollapsibleView", function(spec: Nav.CollapsibleViewSpec): TextButton
		assert(
			type(spec.expanded) == "table" and spec.expanded.set,
			"CollapsibleView.expanded requires a writable Compose cell"
		)
		local buttonSpec: Inputs.ButtonProps & {
			content: Nav.Content?,
			expanded: ComposeTypes.Cell<boolean>?,
			initialFocus: string?,
			dismissButton: Nav.Value<boolean>?,
		} =
			table.clone(spec)
		buttonSpec.content = nil
		buttonSpec.expanded = nil
		buttonSpec.initialFocus = nil
		buttonSpec.dismissButton = nil
		buttonSpec.ref = nil
		buttonSpec.trailingIcon = spec.trailingIcon or "chevron.down"
		buttonSpec.corners = spec.corners or "pill"
		buttonSpec.onActivate = function()
			spec.expanded:set(not spec.expanded:peek())
		end
		local root = UI.Button(buttonSpec)
		local input = surfaces.service("UserInputService")
		local preferred = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		local progress, closed, hidden = revealMotion(spec.expanded)
		local function collapse()
			spec.expanded:set(false)
		end
		local title = root:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			runtime.decorate(title, { TextTruncate = E.TextTruncate.AtEnd, TextWrapped = false })
			runtime.mount(function()
				return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Shrink })
			end, title)
		end
		local caret = root:FindFirstChild("TrailingIcon", true)
		if spec.trailingIcon == nil and caret and caret:IsA("GuiObject") then
			runtime.decorate(caret, {
				Rotation = function(use: ComposeTypes.Use)
					return 180 * progress(use)
				end,
			})
		end
		local rootBox, rootAt = ctx.observe.AbsoluteSize(root), ctx.observe.AbsolutePosition(root)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.expanded, function(phase: Nav.PresencePhase?)
				local layer = assert(surfaces.parent(root))
				local extent, origin = ctx.observe.AbsoluteSize(layer), ctx.observe.AbsolutePosition(layer)
				local column = ctx.column({
					body(spec.content),
					Compose.show(function(use: ComposeTypes.Use)
						return read(spec.dismissButton, use) ~= false or use(preferred) == E.PreferredInput.Gamepad
					end, function()
						return UI.Button "Close" { label = "Close", onActivate = collapse }
					end),
					ctx.padding(16, 16),
				}, { Name = "ExpandedBody", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
				local natural = ctx.observe.AbsoluteSize(column)
				local chrome = Compose.cell(V2.zero)
				local target = Compose.formula(function(use: ComposeTypes.Use): Overlay.Rect
					local room, offset, at, box = use(extent), use(origin), use(rootAt), use(rootBox)
					local margin = ctx.metric("space.s", use)
					local w = math.min(
						math.max(box.X, (ctx.metric("controls.popup.panelWidth", use))),
						math.max(0, room.X - 2 * margin)
					)
					local h =
						math.min(math.max(use(natural).Y + use(chrome).Y, box.Y), math.max(0, room.Y - 2 * margin))
					local x, y = at.X - offset.X, at.Y - offset.Y
					return {
						x = math.clamp(x, margin, math.max(margin, room.X - margin - w)),
						y = math.clamp(y, margin, math.max(margin, room.Y - margin - h)),
						w = w,
						h = h,
					}
				end)
				local function lerp(use: ComposeTypes.Use): Overlay.Rect
					local goal, at, box, offset = use(target), use(rootAt), use(rootBox), use(origin)
					local t = progress(use)
					local x, y = at.X - offset.X, at.Y - offset.Y
					return {
						x = x + (goal.x - x) * t,
						y = y + (goal.y - y) * t,
						w = box.X + (goal.w - box.X) * t,
						h = box.Y + (goal.h - box.Y) * t,
					}
				end
				local fade = ctx.fade {
					Name = "ExpandedFade",
					BackgroundTransparency = 1,
					Size = function(use: ComposeTypes.Use)
						local goal, inset = use(target), use(chrome)
						return D2.fromOffset(goal.w - inset.X, goal.h - inset.Y)
					end,
					GroupTransparency = hidden,
					Host.ScrollingFrame "ExpandedScroll" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = D2.fromScale(1, 1),
						CanvasSize = function(use: ComposeTypes.Use)
							return D2.fromOffset(0, use(natural).Y)
						end,
						ScrollingDirection = E.ScrollingDirection.Y,
						ScrollBarThickness = 4,
						VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
						Selectable = false,
						column,
					},
				}
				local plate = surfaces.skin(ctx.styled(
					Host.Frame "Expanded" {
						Active = true,
						BackgroundTransparency = 0,
						ClipsDescendants = true,
						Position = function(use: ComposeTypes.Use)
							local rect = lerp(use)
							return D2.fromOffset(rect.x, rect.y)
						end,
						Size = function(use: ComposeTypes.Use)
							local rect = lerp(use)
							return D2.fromOffset(rect.w, rect.h)
						end,
						fade,
						Host.Frame "ContentBox" {
							BackgroundTransparency = 1,
							Interactable = false,
							Size = D2.fromScale(1, 1),
						},
						ctx.corner(),
					},
					"panel"
				))
				ctx.styled(plate, "floating")
				local content = assert(plate:FindFirstChild("ContentBox")) :: GuiObject
				local plateBox, contentBox = ctx.observe.AbsoluteSize(plate), ctx.observe.AbsoluteSize(content)
				Compose.watch(function(use: ComposeTypes.Use)
					use(plateBox)
					use(contentBox)
					local outer, inner = plate.AbsoluteSize, content.AbsoluteSize
					if inner.X > 0 and inner.Y > 0 then
						chrome:set(outer - inner)
					end
				end)
				local modal = surfaces.modal(
					function()
						return plate
					end,
					collapse,
					{
						Name = "CollapsibleModal",
						backgroundTransparency = 1,
						initialFocus = spec.initialFocus,
						exiting = if phase then phase.exiting else nil,
						appearance = progress,
					}
				)
				surfaces.keep(spec.content)
				return modal
			end, {
				presence = {
					exit = function(): ComposeTypes.Exiting
						return { completed = closed }
					end,
				},
			}),
		})
		return root
	end)

	local function alert<P>(spec: Nav.AlertSpec<P>): Frame
		local function words(value: Nav.AlertText<P>?, payload: P): Types.ValueString?
			return if type(value) == "function" then value(payload) else value
		end
		local function actionsFor(
			value: ({ Nav.AlertAction<P> } | ((P) -> { Nav.AlertAction<P> }))?,
			payload: P
		): { Nav.AlertAction<P> }?
			return if type(value) == "function" then value(payload) else value
		end
		local root = empty(spec, {
			"title",
			"message",
			"actions",
			"isPresented",
			"presenting",
			"item",
			"error",
			"icon",
			"severity",
			"suppression",
			"content",
			"maxWidth",
			"padding",
			"surface",
			"transition",
		}, "Alert")
		local fullScreen = spec.surface == "fullScreen"
		assert(
			spec.surface == nil or spec.surface == "dialog" or fullScreen,
			"Alert.surface must be dialog or fullScreen"
		)
		assert(
			spec.transition == nil or spec.transition == false or type(spec.transition) == "table",
			"Alert transition must be a table or false"
		)
		local transition: Nav.SourceTransition? = if type(spec.transition) == "table" then spec.transition else nil
		if transition then
			assert(
				type(transition) == "table",
				"Alert.transition requires Compose tween options and an optional native source"
			)
			for key in (transition :: unknown) :: { [string]: unknown } do
				assert(
					key == "source" or key == "seconds" or key == "ease",
					"Alert.transition supports source, seconds, ease"
				)
			end
		end
		local reduce = reducedMotion(ctx)
		local condition = presented(spec)
		local lastItem: P? = nil
		local generation = 0
		surfaces.attach(root, {
			surfaces.overlay(root, condition, function(phase: Nav.PresencePhase?): Instance
				if spec.suppression and spec.suppression.isSuppressed:peek() then
					dismiss(spec)
					return Host.Folder({})
				end
				local payload = (if spec.item then spec.item:peek() else read(spec.presenting)) :: P
				local actions: { Nav.AlertAction<P> } = actionsFor(spec.actions, payload)
					or { { id = "OK", label = "OK" } }
				assert(#actions > 0, "Alert requires at least one action")
				local cancel: Nav.AlertAction<P>?
				local initial: string?
				local identities: { [string]: boolean } = {}
				for _, action in actions do
					assert(
						type(action.id) == "string" and not identities[action.id],
						"Alert actions require unique ids"
					)
					identities[action.id] = true
					if action.role == "cancel" or action.shortcut == "cancelAction" then
						assert(cancel == nil, "Alert accepts one cancel action")
						cancel = action
					end
					if
						read(action.enabled) ~= false
						and action.role ~= "destructive"
						and (initial == nil or action.shortcut == "defaultAction")
					then
						initial = action.id
					end
				end
				local function activate(action: Nav.AlertAction<P>?): ()
					if action and read(action.enabled) == false then
						return
					end
					dismiss(spec)
					if action and action.onActivate then
						action.onActivate(payload)
					end
				end
				local offer = Compose.cell(V2.new(720, 720))
				local padding = spec.padding or 20
				local labelWidths = Compose.cell(0)
				local form = parts.stackedForm(ctx)
				local stacked = Compose.formula(function(use: ComposeTypes.Use)
					return #actions > 2
						or form(use)
						or use(offer).X < 480
						or use(labelWidths) > math.min(use(offer).X - 32, spec.maxWidth or 440) - padding * 2
				end)
				local contents: { Types.Child } = {}
				if spec.icon or spec.severity == "critical" or spec.error then
					table.insert(
						contents,
						ctx.icon(spec.icon or "status.warning", { Name = "AlertIcon", Size = D2.fromOffset(28, 28) })
					)
				end
				local title = words(spec.title, payload) or (spec.error and "Something went wrong")
				if title then
					local titleOrder = #contents + 1
					table.insert(
						contents,
						Compose.show(function(use: ComposeTypes.Use)
							return string.find(tostring(read(title, use)), "%S") ~= nil
						end, function()
							local heading = ctx.text({
								Name = "Title",
								Text = title,
								TextWrapped = true,
								TextXAlignment = E.TextXAlignment.Center,
								LayoutOrder = titleOrder,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							})
							heading:AddTag("facet-type-heading")
							return heading
						end)
					)
				end
				local message = words(spec.message, payload) or (spec.error and tostring(read(spec.error)))
				if message then
					table.insert(
						contents,
						ctx.styled(
							ctx.text({
								Name = "Message",
								Text = message,
								TextWrapped = true,
								TextXAlignment = E.TextXAlignment.Center,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							}),
							"secondary"
						)
					)
				end
				if spec.content then
					table.insert(contents, spec.content(payload))
				end
				local contentRoot = ctx.column(
					contents,
					{ Name = "AlertContent", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
				)
				local contentLayout = contentRoot:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
				if contentLayout then
					contentLayout.HorizontalAlignment = E.HorizontalAlignment.Center
				end
				local contentHeight = Compose.cell(0)
				local actionProps: Types.FrameNativeProps = {
					Name = "Actions",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = function(use: ComposeTypes.Use)
							return if use(stacked) then E.FillDirection.Vertical else E.FillDirection.Horizontal
						end,
						HorizontalFlex = function(use: ComposeTypes.Use)
							return if use(stacked) then E.UIFlexAlignment.None else E.UIFlexAlignment.Fill
						end,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = ctx.types.UDim.new(0, 8),
					}),
				}
				local textBounds: { ComposeTypes.Readable<Vector2> } = {}
				for index, action in actions do
					local button = UI.Button({
						Name = action.id,
						label = action.label,
						enabled = action.enabled,
						role = action.role,
						haptic = action.role == "destructive" or action.shortcut == "defaultAction",
						shortcut = if action.shortcut == "defaultAction"
							then { keyCode = "Return" }
							elseif type(action.shortcut) == "table" then action.shortcut
							else nil,
						Size = function(use: ComposeTypes.Use)
							return if use(stacked) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
						end,
						AutomaticSize = E.AutomaticSize.None,
						LayoutOrder = function(use: ComposeTypes.Use)
							return if action.role == "cancel" then (if use(stacked) then #actions + 1 else 0) else index
						end,
						onActivate = function()
							activate(action)
						end,
					})
					actionProps[#actionProps + 1] = button
					table.insert(textBounds, ctx.observe.TextBounds(button))
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local total = (#actions - 1) * 8
					for _, bounds in textBounds do
						total += use(bounds).X + 24
					end
					labelWidths:set(total)
				end)
				local actionBar: GuiObject = Host.Frame(actionProps)
				if spec.suppression then
					actionBar = ctx.column({
						actionBar,
						UI.Toggle "Suppression" {
							value = spec.suppression.isSuppressed,
							label = spec.suppression.label or "Do not show again",
						},
					}, { Name = "AlertFooter", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
				end
				local actionSize = ctx.layoutSize(actionBar)
				local function chrome(use: ComposeTypes.Use): number
					local package = read(ctx.config.theme, use)
					local recipe = if package and package.chrome then package.chrome.panel else nil
					local inset = if recipe then recipe.contentInsets else nil
					return padding * 2
						+ 8
						+ math.max(0, if inset then inset.top or 0 else 0)
						+ math.max(0, if inset then inset.bottom or 0 else 0)
				end
				local scroll, _, _, messageExtent, messageRested = parts.scroller(ctx, {
					Name = "AlertMessage",
					Selectable = false,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollingDirection = E.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					VerticalScrollBarInset = E.ScrollBarInset.ScrollBar,
					Size = function(use: ComposeTypes.Use)
						if fullScreen then
							return D2.new(1, 0, 1, -use(actionSize).Y - 12)
						end
						return D2.new(
							1,
							0,
							0,
							math.min(
								use(contentHeight),
								math.max(44, math.floor(use(offer).Y - use(actionSize).Y - chrome(use) - 32))
							)
						)
					end,
				}, { lists.list({}, true) :: Instance, contentRoot :: Instance }, { rest = spec.transition == nil })
				local layout: GuiObject
				if fullScreen then
					local readable = V2.new(spec.maxWidth or 960, math.huge)
					runtime.decorate(actionBar, { AnchorPoint = V2.new(0.5, 1), Position = D2.fromScale(0.5, 1) })
					runtime.decorate(scroll, { AnchorPoint = V2.new(0.5, 0), Position = D2.fromScale(0.5, 0) })
					surfaces.attach(actionBar, { Host.UISizeConstraint "ReadableWidth" { MaxSize = readable } })
					surfaces.attach(scroll, { Host.UISizeConstraint "ReadableWidth" { MaxSize = readable } })
					layout = Host.Frame "AlertLayout" {
						BackgroundTransparency = 1,
						Size = function(use: ComposeTypes.Use)
							local destination = use(offer)
							return if destination.X > 0 and destination.Y > 0
								then D2.fromOffset(destination.X, destination.Y)
								else D2.fromScale(1, 1)
						end,
						scroll :: Instance,
						actionBar,
						ctx.padding(padding, padding),
					}
				else
					layout = ctx.column(
						{ scroll, actionBar, ctx.padding(padding, padding), ctx.corner() },
						{ Name = "AlertLayout", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
					)
				end
				local panel = ctx.styled(
					ctx.fade {
						Name = "AlertPanel",
						BackgroundTransparency = 0,
						BorderSizePixel = 0,
						Size = D2.fromScale(1, 1),
						layout,
					},
					"alert"
				)
				if not fullScreen then
					surfaces.centered(panel, spec.maxWidth or 440)
				end
				ctx.styled(panel, "panel")
				surfaces.skin(panel, "panel")
				local settled = Compose.cell(false)
				local shown = if spec.transition == nil
					then surfaces.appearance(phase, ctx.motionTiming("dialog"), settled)
					else nil
				Compose.watch(function(use: ComposeTypes.Use)
					local height = use(messageExtent)
					if not use(messageRested) or shown == nil or shown.travel(use) >= 1 then
						contentHeight:set(height)
					end
					settled:set(use(messageRested) or #contents == 0)
				end)
				if shown then
					local presence = shown
					ctx.fadeTo(panel, function(use: ComposeTypes.Use)
						return 1 - presence.opacity(use)
					end)
					materialize(ctx, panel, {
						Size = if fullScreen then D2.fromScale(1, 1) else D2.new(1, -32, 0, 0),
						AutomaticSize = if fullScreen then E.AutomaticSize.None else E.AutomaticSize.Y,
					}, function(use: ComposeTypes.Use)
						local rest = ctx.metric("motion.materialize.modal", use)
						return if use(settled) then rest + (1 - rest) * presence.travel(use) else 1
					end)
				end
				local modal = surfaces.modal(function()
					return panel
				end, function()
					if cancel and read(cancel.enabled) == false then
						dismiss(spec)
					else
						activate(cancel)
					end
				end, {
					Name = "AlertModal",
					initialFocus = initial,
					outsideDismiss = false,
					exiting = if phase then phase.exiting else nil,
					appearance = if shown then shown.opacity else nil,
				})
				if transition then
					local phase = assert(phase)
					local ready = Compose.cell(false)
					local source: GuiObject? = read(transition.source)
					local sourcePosition: ComposeTypes.Readable<Vector2> = if source
						then ctx.observe.AbsolutePosition(source)
						else Compose.cell(V2.zero)
					local sourceSize: ComposeTypes.Readable<Vector2> = if source
						then ctx.observe.AbsoluteSize(source)
						else Compose.cell(V2.zero)
					local origin = ctx.observe.AbsolutePosition(modal)
					local progress = runtime.tween(function(use: ComposeTypes.Use)
						return if use(phase.exiting) then 0 elseif use(ready) then 1 else 0
					end, { seconds = transition.seconds or ctx.metric("motion.normal"), ease = transition.ease })
					local function amount(use: ComposeTypes.Use): number
						return if reduce(use) then 1 else use(progress)
					end
					if fullScreen then
						local sourceParent = if source
							then ctx.observe.Parent(source)
							else Compose.cell(nil :: Instance?)
						local corner = ctx.Host.UICorner({ CornerRadius = ctx.types.UDim.new(0, 0) })
						local sourceCorner = if source then source:FindFirstChildWhichIsA("UICorner") else nil
						local radius = if sourceCorner then sourceCorner.CornerRadius.Offset else 12
						local snapshot = if source then source:Clone() else nil
						if snapshot then
							runtime.adopt(snapshot)
							local copies: { [Instance]: Instance } = {}
							local function match(original: Instance, clone: Instance): ()
								copies[original] = clone
								local children = clone:GetChildren()
								for _, child in original:GetChildren() do
									if child.Archivable then
										for index, candidate in children do
											if
												candidate.Name == child.Name
												and candidate.ClassName == child.ClassName
											then
												table.remove(children, index)
												match(child, candidate)
												break
											end
										end
									end
								end
							end
							match(assert(source), snapshot)
							for original, clone in copies do
								if original:IsA("ViewportFrame") and clone:IsA("ViewportFrame") then
									local camera = original.CurrentCamera
									local copied: Instance? = if camera then copies[camera] else nil
									clone.CurrentCamera = (
										if copied and copied:IsA("Camera")
											then copied
											elseif camera and not camera:IsDescendantOf(assert(source)) then camera
											else nil
									) :: Camera
								end
							end
							local nodes = snapshot:GetDescendants()
							table.insert(nodes, snapshot)
							for _, node in nodes do
								if node:IsA("GuiObject") then
									node.Interactable, node.Active, node.Selectable = false, false, false
								elseif node:IsA("UIDragDetector") then
									node.Enabled = false
								elseif node:IsA("InputContext") then
									node.Enabled = false
								end
							end
							runtime.decorate(snapshot, {
								Name = "SourceSnapshot",
								AnchorPoint = V2.zero,
								Position = D2.fromOffset(0, 0),
								Size = function(use: ComposeTypes.Use)
									local extent = use(sourceSize)
									return D2.fromOffset(extent.X, extent.Y)
								end,
								AutomaticSize = E.AutomaticSize.None,
							})
							surfaces.attach(panel, {
								ctx.fade {
									Name = "SourcePreview",
									BackgroundTransparency = 1,
									Size = D2.fromScale(1, 1),
									Interactable = false,
									ZIndex = 2,
									Visible = function(use: ComposeTypes.Use)
										return use(sourceParent) ~= nil and amount(use) < 0.35
									end,
									GroupTransparency = function(use: ComposeTypes.Use)
										return math.clamp(amount(use) / 0.35, 0, 1)
									end,
									snapshot,
								},
							})
						end
						runtime.decorate(layout, {
							Interactable = function(use: ComposeTypes.Use)
								return not use(phase.exiting) and amount(use) >= 0.65
							end,
						})
						runtime.decorate(panel, {
							AnchorPoint = V2.zero,
							AutomaticSize = E.AutomaticSize.None,
							ClipsDescendants = true,
							Position = function(use: ComposeTypes.Use)
								local t = amount(use)
								local at = if use(sourceParent) then use(sourcePosition) - use(origin) else V2.zero
								return D2.fromOffset(at.X * (1 - t), at.Y * (1 - t))
							end,
							Size = function(use: ComposeTypes.Use)
								local t, destination = amount(use), use(offer)
								local size = if use(sourceParent) then use(sourceSize) else destination
								return D2.fromOffset(
									size.X + (destination.X - size.X) * t,
									size.Y + (destination.Y - size.Y) * t
								)
							end,
						})
						ctx.fadeTo(panel, function(use: ComposeTypes.Use)
							return if use(sourceParent) then 0 else 1 - amount(use)
						end)
						runtime.decorate(corner, {
							CornerRadius = function(use: ComposeTypes.Use)
								return ctx.types.UDim.new(0, radius * (1 - amount(use)))
							end,
						})
						surfaces.attach(panel, { corner })
						local backdrop = modal:FindFirstChild("DismissOutside")
						local preferred = surfaces.preference()
						runtime.decorate(backdrop, {
							BackgroundTransparency = function(use: ComposeTypes.Use)
								return 1 - amount(use) * (1 - 0.35 * preferred(use))
							end,
						})
					else
						ctx.fadeTo(panel, function(use: ComposeTypes.Use)
							return 1 - amount(use)
						end)
						runtime.decorate(panel, {
							Position = function(use: ComposeTypes.Use)
								local size, at, box, offset, t =
									use(offer), use(sourcePosition), use(sourceSize), use(origin), amount(use)
								local x, y = size.X / 2, size.Y / 2
								if source and source.Parent then
									x = (at.X - offset.X + box.X / 2) * (1 - t) + x * t
									y = (at.Y - offset.Y + box.Y / 2) * (1 - t) + y * t
								end
								return D2.fromOffset(x, y)
							end,
						})
						materialize(ctx, panel, {
							Size = D2.new(1, -32, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
						}, function(use: ComposeTypes.Use)
							if not source then
								return 1
							end
							local t = amount(use)
							local width = math.max(1, math.min(use(offer).X - 32, spec.maxWidth or 440))
							return math.max(0.01, use(sourceSize).X / width) * (1 - t) + t
						end)
					end
					local parent = ctx.observe.Parent(modal)
					local measured = ctx.observe.AbsoluteSize(modal)
					Compose.watch(function(use: ComposeTypes.Use)
						local size = use(measured)
						if use(parent) and (not fullScreen or (size.X > 0 and size.Y > 0)) then
							ready:set(true)
						end
					end)
				end
				local bounds = ctx.observe.AbsoluteSize(modal)
				Compose.watch(function(use: ComposeTypes.Use)
					local size = use(bounds)
					if size.X > 0 and size.Y > 0 then
						offer:set(size)
					end
				end)
				return modal
			end, {
				presence = if transition
					then {
						exit = function(): ComposeTypes.Exiting
							if reduce() then
								return { completed = Compose.cell(true) }
							end
							local motion =
								runtime.timeline({ duration = read(transition.seconds) or ctx.metric("motion.normal") })
							return { completed = motion.completed }
						end,
					}
					else nil,
				motion = if spec.transition == nil then ctx.motionTiming("dialog") else nil,
				identity = if spec.item
					then function(use: ComposeTypes.Use): number
						local value = use(assert(spec.item))
						if value ~= nil and value ~= lastItem then
							lastItem = value
							generation += 1
						end
						return generation
					end
					else nil,
				failure = function(failure)
					root:SetAttribute("FacetError", tostring(failure))
					dismiss(spec)
					if ctx.config.onError then
						ctx.config.onError(failure)
					end
					return Host.Folder "FailedAlert" {}
				end,
			}),
		})
		return root
	end
	UI.Alert = ctx.construct("Alert", alert)

	UI.Callout = ctx.construct("Callout", function(spec: Nav.CalloutSpec): Frame
		assert(type(spec.onRetire) == "function", "Callout requires onRetire")
		assert(spec.anchor, "Callout requires a native anchor")
		local where = "UI.Callout"
		parts.checkMedia(where, spec.media)
		local actionCount = parts.checkActions(ctx, where, spec.actions, 2)
		if spec.closeButton ~= nil and type(spec.closeButton) ~= "boolean" then
			error(`Facet {where}: closeButton must be true or false`, 0)
		end
		if spec.title ~= nil and not parts.bound(ctx, spec.title, "string") then
			error(`Facet {where}: title must be a string or a bound string`, 0)
		end
		local steps = spec.steps
		if steps ~= nil then
			local index = if type(steps) == "table" then steps.index else nil
			local count = if type(steps) == "table" then steps.count else nil
			local function whole(value: unknown): boolean
				return type(value) == "number" and value == math.floor(value) and value < math.huge
			end
			if
				not whole(index)
				or not whole(count)
				or (index :: number) < 1
				or (index :: number) > (count :: number)
			then
				error(`Facet {where}: steps must be \{ index, count } with whole numbers 1 <= index <= count`, 0)
			end
		end
		if spec.content == nil and spec.title == nil and spec.media == nil and steps == nil and actionCount == 0 then
			error(`Facet {where}: nothing to show. Supply content, or a title, media, steps or actions`, 0)
		end
		local input = surfaces.service("UserInputService")
		local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
		local calloutOwner = assert(Compose.currentOwner())
		local retired = Compose.cell(false)
		local anchorAvailable = surfaces.available(spec.anchor)
		local eligible = Compose.formula(function(use: ComposeTypes.Use)
			return use(anchorAvailable)
				and not use(retired)
				and read(spec.isPresented, use) ~= false
				and read(spec.seen, use) ~= true
				and read(spec.featureUsed, use) ~= true
				and (spec.afterSessions == nil or (read(spec.sessions, use) or 0) >= spec.afterSessions)
		end)
		nextCallout += 1
		local registration: CalloutRegistration =
			{ id = nextCallout, eligible = eligible, priority = spec.priority or 0 }
		local registered = table.clone(callouts:peek())
		table.insert(registered, registration)
		callouts:set(registered)
		Compose.cleanup(function()
			local next: { CalloutRegistration } = {}
			for _, entry in callouts:peek() do
				if entry ~= registration then
					table.insert(next, entry)
				end
			end
			callouts:set(next)
		end)
		local visible = Compose.formula(function(use: ComposeTypes.Use)
			local active: CalloutRegistration?
			for _, entry in use(callouts) do
				if use(entry.eligible) and (not active or entry.priority > active.priority) then
					active = entry
				end
			end
			return active == registration
		end)
		local root = empty(spec, {
			"anchor",
			"content",
			"dismissLabel",
			"edge",
			"align",
			"tail",
			"priority",
			"seen",
			"sessions",
			"afterSessions",
			"featureUsed",
			"onRetire",
			"onShow",
			"onHide",
			"isPresented",
			"title",
			"media",
			"steps",
			"actions",
			"closeButton",
		}, "Callout")
		local plate: Instance? = nil
		local function retire(reason: Nav.CalloutRetirement): ()
			if retired:peek() or calloutOwner.isDisposed() then
				return
			end
			local gui = ctx.config.guiService
			local current = if gui then gui.SelectedObject else nil
			if
				gui
				and plate
				and current
				and current:IsDescendantOf(plate)
				and spec.anchor.Selectable
				and spec.anchor.Parent
			then
				gui.SelectedObject = spec.anchor
			end
			retired:set(true)
			spec.onRetire(reason)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if read(spec.featureUsed, use) == true then
				retire("featureUsed")
			elseif read(spec.seen, use) == true then
				retire("seen")
			end
		end)
		local short = ctx.metric("motion.fast")
		local timing: Nav.MotionTiming = { enter = short, exit = short }
		surfaces.attach(root, {
			surfaces.overlay(spec.anchor, visible, function(phase: Nav.PresencePhase?)
				local settled = Compose.cell(false)
				local presence = surfaces.appearance(phase, timing, settled)
				if spec.onShow then
					local ok: boolean, failure: unknown = pcall(spec.onShow)
					if not ok then
						if ctx.config.onError then
							ctx.config.onError(failure)
						else
							warn(`Facet UI.Callout: onShow failed: {tostring(failure)}`)
						end
					end
				end
				Compose.cleanup(function()
					if spec.onHide then
						spec.onHide(if retired:peek() then "retired" else "hidden")
					end
				end)
				local position, size = ctx.observe.AbsolutePosition(spec.anchor), ctx.observe.AbsoluteSize(spec.anchor)
				local rows: { Types.Child } = {}
				if spec.title ~= nil or spec.closeButton == true then
					local header: { Types.Child } = {}
					if spec.title ~= nil then
						local title = spec.title :: Types.Value<string>
						local heading = ctx.text({
							Name = "Title",
							Text = function(use: ComposeTypes.Use): string
								return read(title, use) or ""
							end,
							TextWrapped = true,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						})
						heading:AddTag("facet-type-heading")
						table.insert(header, heading)
					end
					if spec.closeButton == true then
						table.insert(
							header,
							UI.Button "Close" {
								name = "Close",
								icon = "close",
								Size = D2.fromOffset(44, 44),
								AutomaticSize = E.AutomaticSize.None,
								onActivate = function()
									retire("dismissed")
								end,
							}
						)
					end
					local row = ctx.row(
						header,
						{ Name = "Header", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
					)
					table.insert(rows, row)
				end
				if spec.media then
					table.insert(rows, parts.media(ctx, spec.media))
				end
				if spec.content ~= nil then
					table.insert(rows, body(spec.content))
				end
				if steps then
					table.insert(
						rows,
						ctx.styled(
							ctx.text({
								Name = "Steps",
								Text = `{steps.index} of {steps.count}`,
							}),
							"secondary"
						)
					)
				end
				local actions: { Overlay.Action } = spec.actions or {}
				if #actions > 0 then
					local buttons: Types.FrameNativeProps = {
						Name = "Actions",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
					}
					buttons[#buttons + 1] = Host.UIListLayout({
						FillDirection = E.FillDirection.Horizontal,
						HorizontalFlex = E.UIFlexAlignment.Fill,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = ctx.types.UDim.new(0, 8),
					})
					for index, action in actions do
						buttons[#buttons + 1] = UI.Button({
							Name = action.id,
							label = action.label,
							role = action.role,
							enabled = action.enabled,
							busy = action.busy,
							LayoutOrder = index,
							onActivate = function()
								parts.call(action.onActivate, function()
									retire("action")
								end)
							end,
						})
					end
					table.insert(rows, Host.Frame(buttons))
				else
					table.insert(
						rows,
						UI.Button "Dismiss" {
							label = spec.dismissLabel or "Got it",
							onActivate = function()
								retire("dismissed")
							end,
						}
					)
				end
				table.insert(rows, ctx.padding(12, 12))
				local panel = ctx.styled(
					ctx.fade {
						Name = "CalloutPanel",
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - presence.opacity(use)
						end,
						Size = D2.fromOffset(280, 0),
						AutomaticSize = E.AutomaticSize.Y,
						ctx.corner() :: Types.Child,
						ctx.column(rows, {
							Name = "CalloutContent",
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
						}) :: Types.Child,
					},
					"callout"
				)
				ctx.modalPortal(panel, spec.anchor)
				ctx.styled(panel, "panel")
				ctx.styled(panel, "floating")
				surfaces.skin(panel)
				local layer = assert(surfaces.parent(spec.anchor))
				local extent = ctx.observe.AbsoluteSize(layer)
				local origin = ctx.observe.AbsolutePosition(layer)
				local sizes, rested = surfaces.atRest(presence.travel, settled, { panel })
				local measured = sizes[1]
				local function held(use: ComposeTypes.Use): Vector2?
					return if use(rested) and presence.travel(use) < 1 then use(measured) else nil
				end
				local tailed = spec.tail ~= false and spec.tail ~= "none"
				local function lift(use: ComposeTypes.Use): number
					return 8 + (if tailed then parts.tailSize(ctx, use) * math.sqrt(2) / 2 else 0)
				end
				local function above(use: ComposeTypes.Use, floor: number): number
					use(position)
					local outermost = 0
					local at: Instance? = spec.anchor
					while at and at ~= layer do
						if at:IsA("GuiObject") then
							outermost = at.ZIndex
						end
						at = at.Parent
					end
					return math.max(floor, outermost + floor - 93)
				end
				local placement = Compose.formula(function(use: ComposeTypes.Use)
					local at, bounds, offer, offset, box =
						use(position), use(size), use(extent), use(origin), use(measured)
					local x = at.X - offset.X
					local y = at.Y - offset.Y
					local align = read(spec.align, use) or "center"
					local left = if align == "leading"
						then x
						elseif align == "trailing" then x + bounds.X - box.X
						else x + (bounds.X - box.X) / 2
					local roomAbove = y >= box.Y + 16
					local roomBelow = y + bounds.Y + box.Y + 16 <= offer.Y
					local edge = read(spec.edge, use)
						or (if preferred and use(preferred) == E.PreferredInput.Touch then "top" else "bottom")
					local above = if edge == "top" then roomAbove or not roomBelow else roomAbove and not roomBelow
					local top = if above then y - box.Y - lift(use) else y + bounds.Y + lift(use)
					local gutter = ctx.metric("space.s", use)
					return {
						left = math.clamp(left, gutter, math.max(gutter, offer.X - box.X - gutter)),
						top = math.clamp(top, gutter, math.max(gutter, offer.Y - box.Y - gutter)),
					}
				end)
				local panelGeometry: Types.FrameNativeProps = {
					AutomaticSize = function(use: ComposeTypes.Use)
						return if held(use) then E.AutomaticSize.None else E.AutomaticSize.Y
					end,
					Size = function(use: ComposeTypes.Use)
						local box = held(use)
						return D2.fromOffset(
							math.min(280, math.max(44, use(extent).X - 2 * ctx.metric("space.s", use))),
							if box then math.ceil(box.Y) else 0
						)
					end,
					ZIndex = function(use: ComposeTypes.Use): number
						return above(use, 95)
					end,
				}
				runtime.decorate(panel, panelGeometry)
				local scale = surfaces.popover(
					panel,
					presence.travel,
					function(use: ComposeTypes.Use): (Vector2, Vector2)
						local at, anchorAt, anchorSize, offset, box =
							use(placement), use(position), use(size), use(origin), use(measured)
						local center = anchorAt.X - offset.X + anchorSize.X / 2 - at.left
						local above = anchorAt.Y - offset.Y >= at.top + box.Y
						return V2.new(at.left, at.top), V2.new(math.clamp(center, 0, box.X), if above then box.Y else 0)
					end,
					{
						pinned = true,
						rested = rested,
						size = measured,
						geometry = { Size = panelGeometry.Size, AutomaticSize = panelGeometry.AutomaticSize },
					}
				)
				local arrow: { Frame }? = if tailed
					then parts.tail(
						ctx,
						"Arrow",
						function(use: ComposeTypes.Use): (Vector2?, string)
							local at, bounds, offset, box, place =
								use(position), use(size), use(origin), use(measured), use(placement)
							local inset = parts.tailSize(ctx, use)
							local x = math.clamp(
								at.X - offset.X + bounds.X / 2 - place.left,
								inset,
								math.max(inset, box.X - inset)
							)
							local below = at.Y - offset.Y < place.top
							return V2.new(place.left + x, if below then place.top else place.top + box.Y),
								if below then "bottom" else "top"
						end,
						presence.opacity,
						function(use: ComposeTypes.Use): number
							return above(use, 95)
						end,
						{
							node = panel,
							scale = scale,
							corner = function(use: ComposeTypes.Use): Vector2
								local place = use(placement)
								return V2.new(place.left, place.top)
							end,
							size = measured,
							radius = function(use: ComposeTypes.Use): number
								return ctx.metric("radii.panel", use)
							end,
							role = "floating",
						}
					)
					else nil
				local input = surfaces.service("UserInputService")
				if input then
					runtime.connect(input, "InputBegan", function(event: InputObject, processed: boolean)
						if
							processed
							or (
								event.UserInputType ~= E.UserInputType.MouseButton1
								and event.UserInputType ~= E.UserInputType.Touch
							)
						then
							return
						end
						local function hit(node: GuiObject): boolean
							local point, at, bounds = event.Position, node.AbsolutePosition, node.AbsoluteSize
							return point.X >= at.X
								and point.X <= at.X + bounds.X
								and point.Y >= at.Y
								and point.Y <= at.Y + bounds.Y
						end
						if not hit(panel) and not hit(spec.anchor) then
							retire("tapAway")
						end
					end)
				end
				local gui = ctx.config.guiService
				plate = panel
				if gui then
					local anchor = spec.anchor
					local selection = ctx.observe.SelectedObject(gui)
					local panelAt = ctx.observe.AbsolutePosition(panel)
					local linked: string? = nil
					local linkedTarget: GuiObject? = nil
					local function unlink()
						if linked and (anchor :: any)["NextSelection" .. linked] == linkedTarget then
							(anchor :: any)["NextSelection" .. linked] = nil
						end
						linked, linkedTarget = nil, nil
					end
					local rebuilt = Compose.cell(0)
					local leaving: Instance? = nil
					runtime.connect(panel, "DescendantAdded", function()
						leaving = nil
						rebuilt:set(rebuilt:peek() + 1)
					end)
					runtime.connect(panel, "DescendantRemoving", function(node: Instance)
						if linkedTarget and (node == linkedTarget or linkedTarget:IsDescendantOf(node)) then
							leaving = linkedTarget
							rebuilt:set(rebuilt:peek() + 1)
						end
					end)
					Compose.watch(function(use: ComposeTypes.Use)
						use(rebuilt)
						local below = (use(panelAt) :: Vector2).Y > anchor.AbsolutePosition.Y
						local direction = if below then "Down" else "Up"
						local found = surfaces.firstSelectable(panel)
						local target = if found == leaving then nil else found
						if linked ~= direction or linkedTarget ~= target then
							unlink()
							if target and (anchor :: any)["NextSelection" .. direction] == nil then
								(anchor :: any)["NextSelection" .. direction] = target
								linked, linkedTarget = direction, target
							end
						end
					end)
					Compose.cleanup(function()
						unlink()
						local current = gui.SelectedObject
						if current and current:IsDescendantOf(panel) then
							gui.SelectedObject = if anchor.Selectable and anchor.Parent then anchor else nil
						end
					end)
					ctx.action(panel, "CalloutBack", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use)
						local current = use(selection) :: Instance?
						return current ~= nil and current:IsDescendantOf(panel)
					end, function()
						retire("dismissed")
					end, { priority = 2000 })
				end
				local overlayRoot = if arrow
					then Host.Folder "CalloutOverlay" { panel :: Instance, table.unpack(arrow) }
					else panel :: Instance
				surfaces.keep(spec.content)
				return overlayRoot
			end, { motion = timing }),
		})
		return root
	end)
end
