--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local anchoredPlacement = require("./overlay_placement")
local Overlay = require("./overlay_types")
local NavigationProps = require("./navigation_props")
local surfaceParts = require("./nav_surface_parts")

return function(
	ctx: Types.Context,
	UI: ControlTypes.Controls,
	surfaces: Nav.Surfaces,
	kit: surfaceParts.SurfaceParts
): ()
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local body = kit.body
	type CalloutRegistration = { id: number, eligible: ComposeTypes.ReadOnlyValue<boolean>, priority: number }
	local callouts = Compose.cell<<{ CalloutRegistration }>>({})
	local nextCallout = 0

	UI.Callout = ctx.construct("Callout", function(spec: NavigationProps.CalloutSpec): Frame
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
				type(index) ~= "number"
				or type(count) ~= "number"
				or not whole(index)
				or not whole(count)
				or index < 1
				or index > count
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
				and (spec.afterSessions == nil or (read<<number?>>(spec.sessions, use) or 0) >= spec.afterSessions)
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
		local root = kit.empty(spec, {
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
			if retired:peek() or ComposeTypes.owner.isDisposed(calloutOwner) then
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
						local title = spec.title
						local heading = ctx.text({
							Name = "Title",
							Text = function(use: ComposeTypes.Use): string
								return read<<string?>>(title, use) or ""
							end,
							TextWrapped = true,
							Size = D2.new(1, 0, 0, 0),
							AutomaticSize = E.AutomaticSize.Y,
							Host.UIFlexItem { FlexMode = E.UIFlexMode.Fill },
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
								Size = parts.closeTarget(ctx),
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
					local progress = steps
					table.insert(
						rows,
						ctx.styled(
							ctx.text({
								Name = "Steps",
								Text = function(use: ComposeTypes.Use): string
									return ctx.phrase(
										"Facet.IndexOf",
										"{current} of {count}",
										{ current = progress.index, count = progress.count },
										use
									)
								end,
							}),
							"secondary"
						)
					)
				end
				local actions: { Overlay.Action } = spec.actions or {}
				local actionButtons: { [string]: GuiObject } = {}
				if #actions > 0 then
					local buttons: Types.FrameProps = {
						Name = "Actions",
						BackgroundTransparency = 1,
						Size = D2.new(1, 0, 0, 0),
						AutomaticSize = E.AutomaticSize.Y,
					}
					buttons[#buttons + 1] = Host.UIListLayout {
						FillDirection = E.FillDirection.Horizontal,
						HorizontalFlex = E.UIFlexAlignment.Fill,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = ctx.types.UDim.new(0, 8),
					}
					for index, action in actions do
						local button = UI.Button {
							Name = action.id,
							label = action.label,
							role = action.role,
							appearance = if action.role == "default" then "emphasis" else nil,
							enabled = action.enabled,
							busy = action.busy,
							LayoutOrder = index,
							onActivate = function()
								parts.call(action.onActivate, function()
									retire("action")
								end)
							end,
						}
						buttons[#buttons + 1] = button
						actionButtons[action.id] = button
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
				local content = ctx.column(rows, {
					Name = "CalloutContent",
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				})
				assert(content:FindFirstChildWhichIsA("UIListLayout")).HorizontalFlex = E.UIFlexAlignment.Fill
				local body = Host.ScrollingFrame {
					Name = "CalloutBody",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = D2.new(1, 0, 0, 0),
					CanvasSize = D2.new(),
					AutomaticCanvasSize = E.AutomaticSize.Y,
					ScrollingDirection = E.ScrollingDirection.Y,
					ScrollBarThickness = 4,
					VerticalScrollBarInset = E.ScrollBarInset.None,
					Selectable = false,
					content,
				}
				local panel = ctx.styled(
					ctx.fade {
						Name = "CalloutPanel",
						GroupTransparency = function(use: ComposeTypes.Use)
							return 1 - presence.opacity(use)
						end,
						Size = D2.fromOffset(280, 0),
						AutomaticSize = E.AutomaticSize.Y,
						ctx.corner(),
						body,
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
				local sizes, rested = surfaces.atRest(presence.travel, settled, { panel, content })
				local measured, natural = sizes[1], sizes[2]
				local function held(use: ComposeTypes.Use): Vector2?
					return if use(rested) and presence.travel(use) < 1 then use(measured) else nil
				end
				local tailed = spec.tail ~= false and spec.tail ~= "none"
				local function lift(use: ComposeTypes.Use): number
					return 8 + (if tailed then parts.tailDepth(ctx, use) else 0)
				end
				runtime.decorate(body, {
					Size = function(use: ComposeTypes.Use)
						local gutter = ctx.metric("space.s", use)
						local top = use(position).Y - use(origin).Y
						local bottom = top + use(size).Y
						local gap = lift(use)
						local edge = read(spec.edge, use)
						local room = if edge == "leading" or edge == "trailing"
							then use(extent).Y - gutter * 2
							else math.max(top - gap - gutter, use(extent).Y - bottom - gap - gutter)
						local pad = ctx.metric("space.m", use)
						local chrome = surfaces.inset(pad, "top", nil, use) + surfaces.inset(pad, "bottom", nil, use)
						return D2.new(1, 0, 0, math.max(0, math.min(use(natural).Y, room - chrome)))
					end,
				})
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
					local align = read<<("leading" | "center" | "trailing")?>>(spec.align, use) or "center"
					local edge = read<<("top" | "bottom" | "leading" | "trailing")?>>(spec.edge, use)
						or (if preferred and use(preferred) == E.PreferredInput.Touch then "top" else "bottom")
					local gutter = ctx.metric("space.s", use)
					local solved = anchoredPlacement.solve({
						source = { x = x, y = y, w = bounds.X, h = bounds.Y },
						size = { w = box.X, h = box.Y },
						safe = {
							x = gutter,
							y = gutter,
							w = math.max(0, offer.X - gutter * 2),
							h = math.max(0, offer.Y - gutter * 2),
						},
						edge = edge,
						align = if align == "leading" then "start" elseif align == "trailing" then "end" else "center",
						gap = lift(use),
						tail = if tailed then parts.tailWidth(ctx, use) else 0,
						tailInset = ctx.metric("radii.panel", use),
					})
					return {
						left = solved.x,
						top = solved.y,
						edge = solved.edge,
						tailX = solved.tailX,
						tailY = solved.tailY,
						tailSuppressed = solved.tailSuppressed,
					}
				end)
				local panelGeometry: Types.FrameNativeProps = {
					AutomaticSize = function(use: ComposeTypes.Use)
						return if held(use) then E.AutomaticSize.None else E.AutomaticSize.Y
					end,
					Size = function(use: ComposeTypes.Use)
						local box = held(use)
						local at, bounds, offset, offer = use(position), use(size), use(origin), use(extent)
						local gutter = ctx.metric("space.s", use)
						local width = anchoredPlacement.width(
							{ x = at.X - offset.X, y = at.Y - offset.Y, w = bounds.X, h = bounds.Y },
							{ w = 280, h = use(measured).Y },
							{
								x = gutter,
								y = gutter,
								w = math.max(0, offer.X - gutter * 2),
								h = math.max(0, offer.Y - gutter * 2),
							},
							lift(use)
						)
						return D2.fromOffset(width, if box then math.ceil(box.Y) else 0)
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
						local centerX = anchorAt.X - offset.X + anchorSize.X / 2 - at.left
						local centerY = anchorAt.Y - offset.Y + anchorSize.Y / 2 - at.top
						local pivot = if at.edge == "bottom"
							then V2.new(math.clamp(centerX, 0, box.X), 0)
							elseif at.edge == "top" then V2.new(math.clamp(centerX, 0, box.X), box.Y)
							elseif at.edge == "right" then V2.new(0, math.clamp(centerY, 0, box.Y))
							else V2.new(box.X, math.clamp(centerY, 0, box.Y))
						return V2.new(at.left, at.top), pivot
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
							local place = use(placement)
							if place.tailSuppressed or place.tailX == nil or place.tailY == nil then
								return nil, place.edge
							end
							return V2.new(place.tailX, place.tailY), place.edge
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
					local linked: ("Down" | "Up")? = nil
					local linkedTarget: GuiObject? = nil
					local function unlink()
						if linked == "Down" and anchor.NextSelectionDown == linkedTarget then
							runtime.host.render.setProperty(anchor, "NextSelectionDown", nil)
						elseif linked == "Up" and anchor.NextSelectionUp == linkedTarget then
							runtime.host.render.setProperty(anchor, "NextSelectionUp", nil)
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
						local below = use(panelAt).Y > anchor.AbsolutePosition.Y
						local direction: "Down" | "Up" = if below then "Down" else "Up"
						local candidates: { parts.Candidate } = {}
						for _, action in actions do
							local candidate: parts.Candidate =
								{ id = action.id, role = action.role, usable = parts.usable(ctx, action, use) }
							table.insert(candidates, candidate)
						end
						local preferred = parts.initialAction(candidates)
						local chosen = if preferred then actionButtons[preferred] else nil
						local found = (if chosen then surfaces.firstSelectable(chosen) else nil)
							or surfaces.firstSelectable(panel)
						local target = if found == leaving then nil else found
						if linked ~= direction or linkedTarget ~= target then
							unlink()
							local existing = if below then anchor.NextSelectionDown else anchor.NextSelectionUp
							if target and existing == nil then
								if below then
									anchor.NextSelectionDown = target
								else
									anchor.NextSelectionUp = target
								end
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
					ctx.action(
						panel,
						"CalloutBack",
						{ E.KeyCode.Escape, E.KeyCode.ButtonB },
						function(use: ComposeTypes.Use): boolean
							local current = use(selection)
							return current ~= nil and current:IsDescendantOf(panel)
						end,
						function()
							retire("dismissed")
						end,
						{ priority = 2000 }
					)
				end
				local overlayRoot = if arrow then Host.Folder "CalloutOverlay" { panel, table.unpack(arrow) } else panel
				surfaces.keep(spec.content)
				return overlayRoot
			end, { motion = timing }),
		})
		return root
	end)
end
