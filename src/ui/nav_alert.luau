--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Nav = require("./navigation_types")
local materialize = require("./materialize")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local ControlTypes = require("./control_types")
local NavigationProps = require("./navigation_props")
local reducedMotion = require("./motion").reduced
local surfaceParts = require("./nav_surface_parts")
local arrival = require("./overlay_arrival")

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	kit: surfaceParts.SurfaceParts
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local lists = layoutKit.of(ctx)
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local function presented<P>(
		spec: { isPresented: ComposeTypes.Value<boolean>?, item: ComposeTypes.Value<P?>? }
	): ComposeTypes.Body<boolean>
		assert(spec.isPresented or spec.item, "A presented control requires isPresented or item")
		return function(use: ComposeTypes.Use)
			return if spec.item then use(spec.item) ~= nil else use(assert(spec.isPresented))
		end
	end
	local function dismiss<P>(spec: {
		isPresented: ComposeTypes.Value<boolean>?,
		item: ComposeTypes.Value<P?>?,
		error: ComposeTypes.Value<string?>?,
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

	local function alert<P>(spec: NavigationProps.AlertSpec<P>): Frame
		local function words(value: Nav.AlertText<P>?, payload: P): Types.ValueString?
			return if type(value) == "function" then value(payload) else value
		end
		local function actionsFor(
			value: ({ Nav.AlertAction<P> } | ((P) -> { Nav.AlertAction<P> }))?,
			payload: P
		): { Nav.AlertAction<P> }?
			return if type(value) == "function" then value(payload) else value
		end
		local root = kit.empty(spec, {
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
				local primary: Nav.AlertAction<P>?
				local candidates: { parts.Candidate } = {}
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
					if action.role == "default" then
						assert(primary == nil, "Alert accepts one default action")
						primary = action
					end
					local candidate: parts.Candidate = {
						id = action.id,
						role = if action.shortcut == "cancelAction" then action.role or "cancel" else action.role,
						usable = read(action.enabled) ~= false,
						default = action.shortcut == "defaultAction",
					}
					table.insert(candidates, candidate)
				end
				local initial = parts.initialAction(candidates)
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
				local textBounds: { ComposeTypes.ReadOnlyValue<Vector2> } = {}
				for index, action in actions do
					local button = UI.Button({
						Name = action.id,
						label = action.label,
						enabled = action.enabled,
						role = action.role,
						appearance = if action.role == "default" then "emphasis" else nil,
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
					ctx.fade({
						Name = "AlertPanel",
						BackgroundTransparency = 0,
						BorderSizePixel = 0,
						Size = D2.fromScale(1, 1),
						layout,
					}, true),
					"alert"
				)
				if not fullScreen then
					surfaces.centered(panel, spec.maxWidth or 440)
				end
				ctx.styled(panel, if fullScreen then "pane" else "panel")
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
					end, nil, true)
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
					local sourcePosition: ComposeTypes.ReadOnlyValue<Vector2> = if source
						then ctx.observe.AbsolutePosition(source)
						else Compose.cell(V2.zero)
					local sourceSize: ComposeTypes.ReadOnlyValue<Vector2> = if source
						then ctx.observe.AbsoluteSize(source)
						else Compose.cell(V2.zero)
					local origin = ctx.observe.AbsolutePosition(modal)
					local arrived = arrival.ready(phase)
					local progress = runtime.tween(function(use: ComposeTypes.Use)
						return if use(phase.exiting)
							then 0
							elseif use(ready) and (arrived == nil or use(arrived)) then 1
							else 0
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
						local backdrop = modal:FindFirstChild("Scrim")
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
end
