--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local Overlay = require("./overlay_types")
local reducedMotion = require("./motion")

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
	local POPOVER: Nav.MotionTiming = { enter = 0.15, exit = 0.1 }
	local DIALOG: Nav.MotionTiming = { enter = 0.2, exit = 0.15 }
	local REVEAL: Nav.MotionTiming = { enter = 0.25, exit = 0.2 }
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
			local words = headerContent:FindFirstChild("Captions") or headerContent:FindFirstChild("Title")
			if side == "trailing" and words then
				runtime.mount(function()
					return Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
				end, words)
			end
		end

		local reduce = reducedMotion(ctx)
		local travel = runtime.tween(function(use: ComposeTypes.Use): number
			return if use(spec.expanded) then 1 else 0
		end, {
			seconds = function(_: ComposeTypes.Use): number
				return if spec.expanded:peek() then REVEAL.enter else REVEAL.exit
			end,
			ease = Compose.easing.outCubic,
		})
		local function progress(use: ComposeTypes.Use?): number
			if reduce(use) then
				return if read(spec.expanded, use) then 1 else 0
			end
			return read(travel, use)
		end
		local closed = Compose.formula(function(use: ComposeTypes.Use): boolean
			return progress(use) <= 0
		end)
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
					local inset = Host.UIPadding({
						PaddingTop = ctx.types.UDim.new(0, 8),
						PaddingBottom = ctx.types.UDim.new(0, 8),
						PaddingLeft = if indent == nil
							then nil
							else function(use: ComposeTypes.Use)
								local step = indent
								return ctx.types.UDim.new(
									0,
									if type(step) == "number"
										then step
										elseif step then ctx.metric("space." .. step, use)
										else 0
								)
							end,
					})
					local fade = Host.CanvasGroup "RevealFade" {
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - progress(use)
						end,
						node,
					}
					surfaces.attach(fade, { inset :: Types.Child })
					local natural = ctx.observe.AbsoluteSize(fade)
					local reveal = Host.Frame "Reveal" {
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						LayoutOrder = 2,
						Interactable = function(use: ComposeTypes.Use)
							return not use(phase.exiting)
						end,
						AutomaticSize = function(use: ComposeTypes.Use)
							return if progress(use) >= 1 then E.AutomaticSize.Y else E.AutomaticSize.None
						end,
						Size = function(use: ComposeTypes.Use)
							local amount = progress(use)
							return if amount >= 1
								then D2.new(1, 0, 0, 0)
								else D2.new(1, 0, 0, math.floor(use(natural).Y * amount + 0.5))
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
		buttonSpec.onActivate = function()
			spec.expanded:set(not spec.expanded:peek())
		end
		local root = UI.Button(buttonSpec)
		local input = surfaces.service("UserInputService")
		local preferred = if input
			then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
			else Compose.cell(nil :: Enum.PreferredInput?)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.expanded, function(phase: Nav.PresencePhase?)
				local function close()
					spec.expanded:set(false)
				end
				local shown = surfaces.appearance(phase, DIALOG)
				return surfaces.modal(
					function()
						local sheet = surfaces.skin(ctx.styled(
							ctx.column({
								ctx.text({ Text = spec.label }),
								body(spec.content),
								Compose.show(function(use: ComposeTypes.Use)
									return read(spec.dismissButton, use) ~= false
										or use(preferred) == E.PreferredInput.Gamepad
								end, function()
									return UI.Button "Close" { label = "Close", onActivate = close }
								end),
								ctx.padding(16, 16),
								ctx.corner(),
							}, {
								Name = "Expanded",
								BackgroundTransparency = 0,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							}),
							"panel"
						))
						return surfaces.centered(
							Host.CanvasGroup "ExpandedPresentation" {
								BackgroundTransparency = 1,
								GroupTransparency = function(use: ComposeTypes.Use)
									return 1 - shown(use)
								end,
								sheet :: Instance,
								Host.UIScale "PresentationScale" {
									Scale = function(use: ComposeTypes.Use)
										return 0.94 + 0.06 * shown(use)
									end,
								} :: Instance,
							},
							640
						)
					end,
					close,
					{
						initialFocus = spec.initialFocus,
						exiting = if phase then phase.exiting else nil,
						appearance = shown,
					}
				)
			end, { motion = DIALOG }),
		})
		return root
	end)

	local function alert<P>(spec: Nav.AlertSpec<P>): Frame
		local function words(value: (string | ((P) -> string))?, payload: P): string?
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
		local gui = surfaces.service("GuiService")
		local reduced = if gui then ctx.observe.ReducedMotionEnabled(gui) else Compose.cell(false)
		local function reduce(use: ComposeTypes.Use?): boolean
			return read(reduced, use) or read(ctx.config.reducedMotion, use) == true
		end
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
				local stacked = Compose.formula(function(use: ComposeTypes.Use)
					return #actions > 2
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
				if spec.suppression then
					table.insert(
						contents,
						UI.Toggle "Suppression" {
							value = spec.suppression.isSuppressed,
							label = spec.suppression.label or "Do not show again",
						}
					)
				end
				local contentRoot = ctx.column(
					contents,
					{ Name = "AlertContent", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
				)
				local contentSize = ctx.observe.AbsoluteSize(contentRoot)
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
					table.insert(actionProps, button)
					table.insert(textBounds, ctx.observe.TextBounds(button))
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local total = (#actions - 1) * 8
					for _, bounds in textBounds do
						total += use(bounds).X + 24
					end
					labelWidths:set(total)
				end)
				local actionBar = Host.Frame(actionProps)
				local actionSize = ctx.observe.AbsoluteSize(actionBar)
				local function chrome(use: ComposeTypes.Use): number
					local package = read(ctx.config.theme, use)
					local recipe = if package and package.chrome then package.chrome.panel else nil
					local inset = if recipe then recipe.contentInsets else nil
					return padding * 2
						+ 8
						+ math.max(0, if inset then inset.top or 0 else 0)
						+ math.max(0, if inset then inset.bottom or 0 else 0)
				end
				local scroll = parts.scroller(ctx, {
					Name = "AlertMessage",
					Selectable = false,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollingDirection = E.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					Size = function(use: ComposeTypes.Use)
						if fullScreen then
							return D2.new(1, 0, 1, -use(actionSize).Y - 12)
						end
						return D2.new(
							1,
							0,
							0,
							math.min(
								use(contentSize).Y,
								math.max(44, use(offer).Y - use(actionSize).Y - chrome(use) - 32)
							)
						)
					end,
				}, { lists.list({}, true) :: Instance, contentRoot :: Instance })
				local layout: GuiObject
				if fullScreen then
					local readable = V2.new(spec.maxWidth or 960, math.huge)
					runtime.decorate(actionBar, { AnchorPoint = V2.new(0.5, 1), Position = D2.fromScale(0.5, 1) })
					runtime.decorate(scroll, { AnchorPoint = V2.new(0.5, 0), Position = D2.fromScale(0.5, 0) })
					surfaces.attach(actionBar, { Host.UISizeConstraint "ReadableWidth" { MaxSize = readable } })
					surfaces.attach(scroll, { Host.UISizeConstraint "ReadableWidth" { MaxSize = readable } })
					layout = Host.CanvasGroup "AlertLayout" {
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
					Host.CanvasGroup "AlertPanel" {
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
				local shown = if spec.transition == nil then surfaces.appearance(phase, DIALOG) else nil
				if shown then
					runtime.decorate(panel, {
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - shown(use)
						end,
					})
					surfaces.attach(panel, {
						Host.UIScale "PresentationScale" {
							Scale = function(use: ComposeTypes.Use)
								return 0.94 + 0.06 * shown(use)
							end,
						},
					})
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
					appearance = shown,
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
					end, { seconds = transition.seconds or 0.2, ease = transition.ease })
					local function amount(use: ComposeTypes.Use): number
						return if reduce(use) then 1 else use(progress)
					end
					if fullScreen then
						local sourceParent = if source
							then ctx.observe.Parent(source)
							else Compose.cell(nil :: Instance?)
						local corner = ctx.corner(0)
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
								Host.CanvasGroup "SourcePreview" {
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
							GroupTransparency = 0,
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
							GroupTransparency = function(use: ComposeTypes.Use)
								return if use(sourceParent) then 0 else 1 - amount(use)
							end,
						})
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
						runtime.decorate(panel, {
							GroupTransparency = function(use: ComposeTypes.Use)
								return 1 - amount(use)
							end,
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
						surfaces.attach(panel, {
							Host.UIScale "PresentationScale" {
								Scale = function(use: ComposeTypes.Use)
									if not source then
										return 1
									end
									local t = amount(use)
									local width = math.max(1, math.min(use(offer).X - 32, spec.maxWidth or 440))
									return math.max(0.01, use(sourceSize).X / width) * (1 - t) + t
								end,
							},
						})
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
							local motion = runtime.timeline({ duration = read(transition.seconds) or 0.2 })
							return { completed = motion.completed }
						end,
					}
					else nil,
				motion = if spec.transition == nil then DIALOG else nil,
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
		local function retire(reason: Nav.CalloutRetirement): ()
			if retired:peek() or calloutOwner.isDisposed() then
				return
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
		surfaces.attach(root, {
			surfaces.overlay(spec.anchor, visible, function(phase: Nav.PresencePhase?)
				local amount = surfaces.appearance(phase, POPOVER)
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
					table.insert(
						buttons,
						Host.UIListLayout({
							FillDirection = E.FillDirection.Horizontal,
							HorizontalFlex = E.UIFlexAlignment.Fill,
							SortOrder = E.SortOrder.LayoutOrder,
							Padding = ctx.types.UDim.new(0, 8),
						})
					)
					for index, action in actions do
						table.insert(
							buttons,
							UI.Button({
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
						)
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
					Host.CanvasGroup "CalloutPanel" {
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
				local layer: GuiBase2d = ctx.config.overlayParent :: GuiBase2d?
					or assert(spec.anchor:FindFirstAncestorWhichIsA("LayerCollector"))
				local extent = ctx.observe.AbsoluteSize(layer)
				local origin = ctx.observe.AbsolutePosition(layer)
				local measured = ctx.observe.AbsoluteSize(panel)
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
					local above = if read(spec.edge, use) == "top"
						then roomAbove or not roomBelow
						else roomAbove and not roomBelow
					local top = if above then y - box.Y - 8 else y + bounds.Y + 8
					local gutter = ctx.metric("space.s", use)
					return {
						left = math.clamp(left, gutter, math.max(gutter, offer.X - box.X - gutter)),
						top = math.clamp(top, gutter, math.max(gutter, offer.Y - box.Y - gutter)),
					}
				end)
				runtime.decorate(panel, {
					Size = function(use: ComposeTypes.Use)
						return D2.fromOffset(
							math.min(280, math.max(44, use(extent).X - 2 * ctx.metric("space.s", use))),
							0
						)
					end,
					ZIndex = function(use: ComposeTypes.Use): number
						return above(use, 95)
					end,
				})
				surfaces.popover(panel, amount, function(use: ComposeTypes.Use): (Vector2, Vector2)
					local at, anchorAt, anchorSize, offset, box =
						use(placement), use(position), use(size), use(origin), use(measured)
					local center = anchorAt.X - offset.X + anchorSize.X / 2 - at.left
					local above = anchorAt.Y - offset.Y >= at.top + box.Y
					return V2.new(at.left, at.top), V2.new(math.clamp(center, 0, box.X), if above then box.Y else 0)
				end)
				local arrow: Frame?
				if spec.tail ~= false and spec.tail ~= "none" then
					arrow = ctx.styled(
						Host.Frame "Arrow" {
							Size = D2.fromOffset(10, 10),
							Rotation = 45,
							BorderSizePixel = 0,
							ZIndex = function(use: ComposeTypes.Use): number
								return above(use, 94)
							end,
							Host.UIGradient "PresentationFade" {
								Transparency = function(use: ComposeTypes.Use)
									return ctx.types.NumberSequence.new(1 - amount(use))
								end,
							} :: Types.Child,
							Position = function(use: ComposeTypes.Use)
								local at, bounds, offset, box, place =
									use(position), use(size), use(origin), use(measured), use(placement)
								local x = math.clamp(
									at.X - offset.X + bounds.X / 2 - place.left,
									12,
									math.max(12, box.X - 12)
								)
								return D2.fromOffset(
									place.left + x - 5,
									place.top + (if at.Y - offset.Y < place.top then -5 else box.Y - 5)
								)
							end,
						},
						"callout"
					)
					ctx.styled(arrow :: Frame, "panel")
				end
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
				return if arrow then Host.Folder "CalloutOverlay" { panel :: Instance, arrow } else panel :: Instance
			end, { motion = POPOVER }),
		})
		return root
	end)
end
