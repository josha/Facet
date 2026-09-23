--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Inputs = require("./input_types")
local Core = require("../vendor/compose/core")

type Controls = {
	DisclosureGroup: Types.Constructor<Nav.DisclosureGroupSpec, Frame>,
	CollapsibleView: Types.Constructor<Nav.CollapsibleViewSpec, TextButton>,
	Alert: Nav.AlertConstructor,
	Sheet: Types.Constructor<Nav.SheetSpec, Frame>,
	Callout: Types.Constructor<Nav.CalloutSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
	Toggle: Types.Constructor<Inputs.ToggleProps, TextButton>,
	Picker: Nav.PickerConstructor,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	type CalloutRegistration = { id: number, eligible: Core.Readable<boolean>, priority: number }
	local callouts = Compose.cell({} :: { CalloutRegistration })
	local nextCallout = 0
	local function body<P, R>(content: R | ((P) -> R), payload: P): R
		return if type(content) == "function" then content(payload) else content
	end
	local function empty(spec: Types.FrameProps, keys: { string }, name: string): Frame
		return Host.Frame(
			ctx.props(spec, keys, { Name = name, BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
	end
	local function presented<P>(spec: { isPresented: Core.Cell<boolean>?, item: Core.Cell<P?>? }): Core.Body<boolean>
		assert(spec.isPresented or spec.item, "A presented control requires isPresented or item")
		return function(use: Core.Use)
			return if spec.item then use(spec.item) ~= nil else use(assert(spec.isPresented))
		end
	end
	local function dismiss<P>(
		spec: { isPresented: Core.Cell<boolean>?, item: Core.Cell<P?>?, error: Core.Cell<string?>? }
	): ()
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

	UI.DisclosureGroup = ctx.construct(function(spec: Nav.DisclosureGroupSpec): Frame
		assert(spec.expanded and spec.expanded.set, "DisclosureGroup.expanded requires a writable Compose cell")
		local gui = surfaces.service("GuiService")
		local side = spec.chevronPosition or "leading"
		assert(side == "leading" or side == "trailing", "Invalid DisclosureGroup.chevronPosition")
		assert(
			spec.appearance == nil or table.find({ "plain", "contained", "divided" }, spec.appearance),
			"Invalid DisclosureGroup.appearance"
		)
		local function chevron(use: Core.Use): string
			return if use(spec.expanded) then "chevron.down" else "chevron.trailing"
		end
		local header = UI.Button({
			Name = "Header",
			label = spec.label,
			icon = if side == "leading" then chevron else spec.icon,
			trailingIcon = if side == "trailing" then chevron else spec.icon,
			subtitle = spec.description,
			enabled = spec.enabled,
			Size = D2.new(1, 0, 0, 44),
			selected = spec.expanded,
			onActivate = function()
				local value = not spec.expanded:peek()
				spec.expanded:set(value)
				if spec.onToggle then
					spec.onToggle(value)
				end
			end,
		})

		local root = ctx.column(
			{
				header,
				Compose.show(spec.expanded, function()
					local node: Instance = body(spec.content, nil)
					if spec.appearance == "divided" then
						node = ctx.column({
							ctx.styled(
								Host.Frame({ Name = "Divider", BorderSizePixel = 0, Size = D2.new(1, 0, 0, 1) }),
								"divider"
							),
							node,
						})
					end
					if node:IsA("GuiObject") then
						runtime.decorate(node, { LayoutOrder = 2 })
					end
					Compose.cleanup(function()
						if gui and surfaces.within(gui.SelectedObject, node) and header.Parent then
							gui.SelectedObject = header
						end
					end)
					return node
				end),
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
			}, { Name = "DisclosureGroup", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y })
		)
		ctx.styled(root, "disclosure")
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

	UI.CollapsibleView = ctx.construct(function(spec: Nav.CollapsibleViewSpec): TextButton
		assert(spec.expanded and spec.expanded.set, "CollapsibleView.expanded requires a writable Compose cell")
		local buttonSpec: Inputs.ButtonProps & {
			content: Nav.Content?,
			expanded: Core.Cell<boolean>?,
			initialFocus: string?,
			dismissButton: Nav.Value<boolean>?,
		} =
			table.clone(spec)
		buttonSpec.content = nil
		buttonSpec.expanded = nil
		buttonSpec.initialFocus = nil
		buttonSpec.dismissButton = nil
		buttonSpec.onActivate = function()
			spec.expanded:set(not spec.expanded:peek())
		end
		local root = UI.Button(buttonSpec)
		local input = surfaces.service("UserInputService")
		local preferred = if input then ctx.observe(input, "PreferredInput") else Compose.cell(nil)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.expanded, function()
				local function close()
					spec.expanded:set(false)
				end
				return surfaces.modal(function()
					return surfaces.centered(
						surfaces.skin(ctx.styled(
							ctx.column({
								ctx.text({ Text = spec.label }),
								body(spec.content, nil),
								Compose.show(function(use: Core.Use)
									return read(spec.dismissButton, use) ~= false
										or use(preferred) == E.PreferredInput.Gamepad
								end, function()
									return UI.Button({ Name = "Close", label = "Close", onActivate = close })
								end),
								ctx.padding(16, 16),
								ctx.corner(),
							}, {
								Name = "Expanded",
								BackgroundTransparency = 0,
								Size = D2.new(1, -32, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							}),
							"panel"
						)),
						640
					)
				end, close, { initialFocus = spec.initialFocus })
			end),
		})
		return root
	end)

	local function alert<P>(spec: Nav.AlertSpec<P>): Frame
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
		local transition: Nav.SourceTransition? = if type(spec.transition) == "table" then spec.transition else nil
		if transition then
			assert(
				type(transition) == "table",
				"Alert.transition requires Compose tween options and an optional native source"
			)
			for key in transition do
				assert(
					key == "source" or key == "seconds" or key == "ease",
					"Alert.transition supports source, seconds, ease"
				)
			end
		end
		local gui = surfaces.service("GuiService")
		local reduced = if gui then ctx.observe(gui, "ReducedMotionEnabled") else Compose.cell(false)
		local function reduce(use: Core.Use?): boolean
			return read(reduced, use) or read(ctx.config.reducedMotion, use) == true
		end
		local condition = presented(spec)
		surfaces.attach(root, {
			surfaces.overlay(root, condition, function(phase)
				if spec.suppression and spec.suppression.isSuppressed:peek() then
					dismiss(spec)
					return Host.Folder({})
				end
				local payload = (if spec.item then spec.item:peek() else read(spec.presenting)) :: P
				local actions: { Nav.AlertAction<P> } = body(spec.actions, payload) or { { id = "OK", label = "OK" } }
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
					if action.role == "cancel" then
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
				local stacked = Compose.formula(function(use: Core.Use)
					return #actions > 2
						or use(offer).X < 480
						or use(labelWidths) > math.min(use(offer).X - 32, spec.maxWidth or 440) - padding * 2
				end)
				local contents: { Types.Child } = {}
				if spec.icon or spec.severity == "critical" or spec.error then
					table.insert(
						contents,
						ctx.icon(spec.icon or "status.warning", { Name = "AlertIcon", Size = D2.fromOffset(24, 24) })
					)
				end
				local title = body(spec.title, payload) or (spec.error and "Something went wrong")
				if title then
					table.insert(
						contents,
						Compose.show(function(use: Core.Use)
							return string.find(tostring(read(title, use)), "%S") ~= nil
						end, function()
							return ctx.text({
								Name = "Title",
								Text = title,
								TextWrapped = true,
								Size = D2.new(1, 0, 0, 0),
								AutomaticSize = E.AutomaticSize.Y,
							})
						end)
					)
				end
				local message = body(spec.message, payload) or (spec.error and tostring(read(spec.error)))
				if message then
					table.insert(
						contents,
						ctx.text({
							Name = "Message",
							Text = message,
							TextWrapped = true,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
						})
					)
				end
				if spec.content then
					table.insert(contents, spec.content(payload))
				end
				if spec.suppression then
					table.insert(
						contents,
						UI.Toggle({
							Name = "Suppression",
							value = spec.suppression.isSuppressed,
							label = spec.suppression.label or "Do not show again",
						})
					)
				end
				local contentRoot = ctx.column(
					contents,
					{ Name = "AlertContent", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
				)
				local contentSize = ctx.observe(contentRoot, "AbsoluteSize")
				local actionProps: Types.FrameNativeProps = {
					Name = "Actions",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = function(use: Core.Use)
							return if use(stacked) then E.FillDirection.Vertical else E.FillDirection.Horizontal
						end,
						HorizontalFlex = function(use: Core.Use)
							return if use(stacked) then E.UIFlexAlignment.None else E.UIFlexAlignment.Fill
						end,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = ctx.types.UDim.new(0, 8),
					}),
				}
				local textBounds: { Core.Readable<Vector2> } = {}
				for index, action in actions do
					local button = UI.Button({
						Name = action.id,
						label = action.label,
						enabled = action.enabled,
						role = action.role,
						shortcut = if action.shortcut == "defaultAction"
							then { keyCode = "Return" }
							elseif type(action.shortcut) == "table" then action.shortcut
							else nil,
						Size = function(use: Core.Use)
							return if use(stacked) then D2.new(1, 0, 0, 44) else D2.fromOffset(0, 44)
						end,
						AutomaticSize = E.AutomaticSize.None,
						LayoutOrder = function(use: Core.Use)
							return if action.role == "cancel" then (if use(stacked) then #actions + 1 else 0) else index
						end,
						onActivate = function()
							activate(action)
						end,
					})
					table.insert(actionProps, button)
					table.insert(textBounds, ctx.observe(button, "TextBounds"))
				end
				Compose.watch(function(use: Core.Use)
					local total = (#actions - 1) * 8
					for _, bounds in textBounds do
						total += use(bounds).X + 24
					end
					labelWidths:set(total)
				end)
				local actionBar = Host.Frame(actionProps)
				local actionSize = ctx.observe(actionBar, "AbsoluteSize")
				local scroll = Host.ScrollingFrame({
					Name = "AlertMessage",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasSize = D2.fromOffset(0, 0),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					ScrollingDirection = E.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					Size = function(use: Core.Use)
						if fullScreen then
							return D2.new(1, 0, 1, -use(actionSize).Y - 12)
						end
						return D2.new(
							1,
							0,
							0,
							math.min(
								use(contentSize).Y,
								math.max(44, use(offer).Y - use(actionSize).Y - padding * 2 - 40)
							)
						)
					end,
					contentRoot,
				})
				local layout: GuiObject
				if fullScreen then
					runtime.decorate(actionBar, { AnchorPoint = V2.new(0, 1), Position = D2.fromScale(0, 1) })
					layout = Host.CanvasGroup({
						Name = "AlertLayout",
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						scroll :: Instance,
						actionBar,
						ctx.padding(padding, padding),
					})
				else
					layout = ctx.column(
						{ scroll, actionBar, ctx.padding(padding, padding), ctx.corner() },
						{ Name = "AlertLayout", Size = D2.new(1, 0, 0, 0), AutomaticSize = E.AutomaticSize.Y }
					)
				end
				local panel = ctx.styled(
					Host.CanvasGroup({
						Name = "AlertPanel",
						BackgroundTransparency = 0,
						BorderSizePixel = 0,
						Size = D2.fromScale(1, 1),
						layout,
					}),
					"alert"
				)
				if not fullScreen then
					surfaces.centered(panel, spec.maxWidth or 440)
				end
				ctx.styled(panel, "panel")
				surfaces.skin(panel, "panel")
				local modal = surfaces.modal(function()
					return panel
				end, function()
					if cancel and read(cancel.enabled) == false then
						dismiss(spec)
					else
						activate(cancel)
					end
				end, { Name = "AlertModal", initialFocus = initial, outsideDismiss = false })
				if transition then
					local phase = assert(phase)
					local ready = Compose.cell(false)
					local source = read(transition.source)
					local sourcePosition: Core.Readable<Vector2> = if source
						then ctx.observe(source, "AbsolutePosition")
						else Compose.cell(V2.zero)
					local sourceSize: Core.Readable<Vector2> = if source
						then ctx.observe(source, "AbsoluteSize")
						else Compose.cell(V2.zero)
					local origin = ctx.observe(modal, "AbsolutePosition")
					local progress = runtime.tween(function(use: Core.Use)
						return if use(phase.exiting) then 0 elseif use(ready) then 1 else 0
					end, { seconds = transition.seconds or 0.2, ease = transition.ease })
					local function amount(use: Core.Use): number
						return if reduce(use) then 1 else use(progress)
					end
					if fullScreen then
						local sourceParent = if source then ctx.observe(source, "Parent") else Compose.cell(nil)
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
								Size = D2.fromScale(1, 1),
								AutomaticSize = E.AutomaticSize.None,
							})
							surfaces.attach(panel, {
								Host.CanvasGroup({
									Name = "SourcePreview",
									BackgroundTransparency = 1,
									Size = D2.fromScale(1, 1),
									Interactable = false,
									ZIndex = 2,
									Visible = function(use: Core.Use)
										return use(sourceParent) ~= nil and amount(use) < 0.65
									end,
									GroupTransparency = function(use: Core.Use)
										return math.clamp((amount(use) - 0.15) / 0.5, 0, 1)
									end,
									snapshot,
								}),
							})
						end
						runtime.decorate(layout, {
							Interactable = function(use: Core.Use)
								return not use(phase.exiting) and amount(use) >= 0.65
							end,
							GroupTransparency = function(use: Core.Use)
								return if snapshot then 1 - math.clamp((amount(use) - 0.15) / 0.5, 0, 1) else 0
							end,
						})
						runtime.decorate(panel, {
							AnchorPoint = V2.zero,
							AutomaticSize = E.AutomaticSize.None,
							ClipsDescendants = true,
							Position = function(use: Core.Use)
								local t = amount(use)
								local at = if use(sourceParent) then use(sourcePosition) - use(origin) else V2.zero
								return D2.fromOffset(at.X * (1 - t), at.Y * (1 - t))
							end,
							Size = function(use: Core.Use)
								local t, destination = amount(use), use(offer)
								local size = if use(sourceParent) then use(sourceSize) else destination
								return D2.fromOffset(
									size.X + (destination.X - size.X) * t,
									size.Y + (destination.Y - size.Y) * t
								)
							end,
							GroupTransparency = function(use: Core.Use)
								return if use(sourceParent) then 0 else 1 - amount(use)
							end,
						})
						runtime.decorate(corner, {
							CornerRadius = function(use: Core.Use)
								return ctx.types.UDim.new(0, radius * (1 - amount(use)))
							end,
						})
						surfaces.attach(panel, { corner })
						local backdrop = modal:FindFirstChild("DismissOutside")
						runtime.decorate(backdrop, {
							BackgroundTransparency = function(use: Core.Use)
								return 1 - amount(use) * 0.65
							end,
						})
					else
						runtime.decorate(panel, {
							GroupTransparency = function(use: Core.Use)
								return 1 - amount(use)
							end,
							Position = function(use: Core.Use)
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
							Host.UIScale({
								Name = "PresentationScale",
								Scale = function(use: Core.Use)
									if not source then
										return 1
									end
									local t = amount(use)
									local width = math.max(1, math.min(use(offer).X - 32, spec.maxWidth or 440))
									return math.max(0.01, use(sourceSize).X / width) * (1 - t) + t
								end,
							}),
						})
					end
					local parent = ctx.observe(modal, "Parent")
					Compose.watch(function(use: Core.Use)
						if use(parent) then
							ready:set(true)
						end
					end)
					runtime.decorate(modal, {
						Interactable = function(use: Core.Use)
							return not use(phase.exiting)
						end,
					})
				end
				local bounds = ctx.observe(modal, "AbsoluteSize")
				Compose.watch(function(use: Core.Use)
					local size = use(bounds)
					if size.X > 0 and size.Y > 0 then
						offer:set(size)
					end
				end)
				return modal
			end, {
				presence = if transition
					then {
						exit = function()
							if reduce() then
								return { completed = Compose.cell(true) }
							end
							local motion = runtime.timeline({ duration = read(transition.seconds) or 0.2 })
							return { completed = motion.completed }
						end,
					}
					else nil,
				failure = function(failure)
					root:SetAttribute("FacetError", tostring(failure))
					dismiss(spec)
					if ctx.config.onError then
						ctx.config.onError(failure)
					end
					return Host.Folder({ Name = "FailedAlert" })
				end,
			}),
		})
		return root
	end
	UI.Alert = ctx.construct(alert)

	UI.Sheet = ctx.construct(function(spec: Nav.SheetSpec): Frame
		assert(spec.detent and spec.detent.set, "Sheet.detent requires a writable Compose cell")
		type Detent = { id: string, fraction: number?, height: number? }
		local detents: { Detent } = {}
		local seenDetents: { [string]: boolean } = {}
		local entries: { Nav.SheetDetent } = spec.detents or { "medium", "large" }
		for _, entry in entries do
			local d: Detent
			if entry == "medium" then
				d = { id = "medium", fraction = 0.5 }
			elseif entry == "large" then
				d = { id = "large", fraction = 0.95 }
			else
				assert(type(entry) == "table", "Invalid Sheet detent")
				d = entry
			end
			assert(type(d) == "table" and type(d.id) == "string" and (d.fraction or d.height), "Invalid Sheet detent")
			assert(not seenDetents[d.id], "Sheet detents require unique ids")
			assert((d.fraction == nil) ~= (d.height == nil), "Sheet detent requires exactly one of fraction or height")
			assert(
				if d.fraction
					then type(d.fraction) == "number" and d.fraction > 0 and d.fraction <= 1
					else type(d.height) == "number" and d.height > 0 and d.height < math.huge,
				"Invalid Sheet detent extent"
			)
			seenDetents[d.id] = true
			table.insert(detents, d)
		end
		local root = empty(
			spec,
			{ "title", "content", "detent", "detents", "isPresented", "interactiveDismissDisabled", "dragIndicator" },
			"Sheet"
		)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.isPresented, function()
				local function close()
					spec.isPresented:set(false)
				end
				local available = Compose.cell(720)
				local dragHeight: Core.Cell<number?> = Compose.cell(nil :: number?)
				local function height(detent: Detent, use: Core.Use?): number
					return math.min(
						read(available, use),
						detent.height or read(available, use) * assert(detent.fraction)
					)
				end
				local function current(use: Core.Use?): number
					local selected = read(spec.detent, use)
					for _, detent in detents do
						if detent.id == selected then
							return height(detent, use)
						end
					end
					error("Sheet.detent must name a declared detent")
				end
				local gui = surfaces.service("GuiService")
				local reduced = if gui then ctx.observe(gui, "ReducedMotionEnabled") else Compose.cell(false)
				local motion = runtime.tween(function(use: Core.Use)
					return use(dragHeight) or current(use)
				end, { seconds = 0.2 })
				local function painted(use: Core.Use?): number
					return if read(ctx.config.reducedMotion, use) == true or read(reduced, use)
						then read(dragHeight, use) or current(use)
						else read(motion, use)
				end
				local dragging, origin, startHeight = false, 0, 0
				local detector = Host.UIDragDetector({
					DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
					DragAxis = V2.new(0, 1),
					ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
					DragStart = function(position: Vector2)
						dragging, origin, startHeight = true, position.Y, painted()
						dragHeight:set(startHeight)
					end,
					DragContinue = function(position: Vector2)
						if dragging then
							dragHeight:set(math.clamp(startHeight + origin - position.Y, 0, available:peek()))
						end
					end,
					DragEnd = function()
						if not dragging then
							return
						end
						dragging = false
						local wanted = dragHeight:peek() or current()
						local nearest: Detent?
						local distance, minimum = math.huge, math.huge
						for _, detent in detents do
							local extent = height(detent)
							minimum = math.min(minimum, extent)
							if math.abs(extent - wanted) < distance then
								nearest, distance = detent, math.abs(extent - wanted)
							end
						end
						dragHeight:set(nil)
						if wanted < minimum * 0.7 and read(spec.interactiveDismissDisabled) ~= true then
							close()
						else
							spec.detent:set(assert(nearest).id)
						end
					end,
				})
				local resizeOptions: { Nav.PickerOption<string> } = {}
				for _, detent in detents do
					table.insert(resizeOptions, { value = detent.id, label = detent.id })
				end
				local panel = ctx.column({
					Host.Frame({
						Name = "DragHandle",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 24),
						Visible = spec.dragIndicator ~= "hidden",
						detector,
					}),
					ctx.text({ Name = "Title", Text = spec.title }),
					UI.Picker({
						Name = "Size",
						selected = spec.detent,
						options = resizeOptions,
						multiple = false :: false,
						style = "segmented" :: "segmented",
					}),
					Host.ScrollingFrame({
						Name = "SheetContent",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						CanvasSize = D2.fromOffset(0, 0),
						AutomaticCanvasSize = E.AutomaticSize.Y,
						ScrollingDirection = E.ScrollingDirection.Y,
						ScrollBarThickness = 6,
						Size = D2.new(1, 0, 0, 0),
						ClipsDescendants = true,
						Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						body(spec.content, nil),
					}),
					UI.Button({ Name = "Close", label = "Close", onActivate = close, Size = D2.new(1, 0, 0, 44) }),
					ctx.padding(16, 12),
					ctx.corner(),
				}, {
					Name = "SheetPanel",
					BackgroundTransparency = 0,
					AnchorPoint = V2.new(0.5, 1),
					Position = D2.fromScale(0.5, 1),
					AutomaticSize = E.AutomaticSize.None,
					Size = function(use: Core.Use)
						return D2.new(1, 0, 0, math.min(use(available), math.max(220, use(dragHeight) or painted(use))))
					end,
				})
				ctx.styled(panel, "sheet")
				surfaces.skin(panel)
				local overlay = surfaces.modal(
					function()
						return panel
					end,
					close,
					{
						canDismiss = function(use: Core.Use)
							return read(spec.interactiveDismissDisabled, use) ~= true
						end,
					}
				)
				local size = ctx.observe(overlay, "AbsoluteSize")
				Compose.watch(function(use: Core.Use)
					local value = use(size)
					if value.Y > 0 then
						available:set(value.Y)
					end
				end)
				return overlay
			end),
		})
		return root
	end)

	UI.Callout = ctx.construct(function(spec: Nav.CalloutSpec): Frame
		assert(type(spec.onRetire) == "function", "Callout requires onRetire")
		assert(spec.anchor, "Callout requires a native anchor")
		local retired = Compose.cell(false)
		local anchorAvailable = surfaces.available(spec.anchor)
		local eligible = Compose.formula(function(use: Core.Use)
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
		local visible = Compose.formula(function(use: Core.Use)
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
		}, "Callout")
		local function retire(reason: Nav.CalloutRetirement): ()
			if retired:peek() then
				return
			end
			retired:set(true)
			spec.onRetire(reason)
		end
		Compose.watch(function(use: Core.Use)
			if read(spec.featureUsed, use) == true then
				retire("featureUsed")
			elseif read(spec.seen, use) == true then
				retire("seen")
			end
		end)
		surfaces.attach(root, {
			surfaces.overlay(spec.anchor, visible, function()
				if spec.onShow then
					spec.onShow()
				end
				Compose.cleanup(function()
					if spec.onHide then
						spec.onHide(if retired:peek() then "retired" else "hidden")
					end
				end)
				local position, size =
					ctx.observe(spec.anchor, "AbsolutePosition"), ctx.observe(spec.anchor, "AbsoluteSize")
				local panel = ctx.styled(
					ctx.column({
						body(spec.content, nil),
						UI.Button({
							Name = "Dismiss",
							label = spec.dismissLabel or "Got it",
							onActivate = function()
								retire("dismissed")
							end,
						}),
						ctx.padding(12, 12),
						ctx.corner(),
					}, {
						Name = "CalloutPanel",
						BackgroundTransparency = 0,
						Size = D2.fromOffset(280, 0),
						AutomaticSize = E.AutomaticSize.Y,
					}),
					"callout"
				)
				ctx.modalPortal(panel, spec.anchor)
				ctx.styled(panel, "panel")
				surfaces.skin(panel)
				local layer = assert(spec.anchor:FindFirstAncestorWhichIsA("LayerCollector"))
				local extent = ctx.observe(layer, "AbsoluteSize")
				local origin = ctx.observe(layer, "AbsolutePosition")
				local measured = ctx.observe(panel, "AbsoluteSize")
				local placement = Compose.formula(function(use: Core.Use)
					local at, bounds, offer, offset, box =
						use(position), use(size), use(extent), use(origin), use(measured)
					local x = at.X - offset.X
					local y = at.Y - offset.Y
					local align = read(spec.align, use) or "center"
					local left = if align == "leading"
						then x
						elseif align == "trailing" then x + bounds.X - box.X
						else x + (bounds.X - box.X) / 2
					local above = read(spec.edge, use) == "top"
						or (y + bounds.Y + box.Y + 16 > offer.Y and y >= box.Y + 16)
					local top = if above then y - box.Y - 8 else y + bounds.Y + 8
					return {
						left = math.clamp(left, 8, math.max(8, offer.X - box.X - 8)),
						top = math.clamp(top, 8, math.max(8, offer.Y - box.Y - 8)),
					}
				end)
				runtime.decorate(panel, {
					Size = function(use: Core.Use)
						return D2.fromOffset(math.min(280, math.max(44, use(extent).X - 16)), 0)
					end,
					Position = function(use: Core.Use)
						local at = use(placement)
						return D2.fromOffset(at.left, at.top)
					end,
					ZIndex = 110,
				})
				local arrow: Frame?
				if spec.tail ~= false and spec.tail ~= "none" then
					arrow = ctx.styled(
						Host.Frame({
							Name = "Arrow",
							Size = D2.fromOffset(10, 10),
							Rotation = 45,
							BorderSizePixel = 0,
							ZIndex = 109,
							Position = function(use: Core.Use)
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
						}),
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
				return if arrow then Host.Folder({ Name = "CalloutOverlay", panel, arrow }) else panel
			end),
		})
		return root
	end)
end
