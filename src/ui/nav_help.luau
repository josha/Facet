--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local help = require("./help")
local Inputs = require("./input_types")
local placement = require("./overlay_placement")
local parts = require("./overlay_parts")
local surfaceKit = require("./nav_surface_kit")
local overlayPresence = require("./nav_overlay_presence")
local overlayPortal = require("./nav_overlay_portal")
local popoverPlacement = require("./nav_popover_placement")

local HELP_DWELL = 0.45

return function(
	ctx: Types.Context,
	kit: surfaceKit.Kit,
	presence: overlayPresence.Presence,
	portal: overlayPortal.Portal,
	popover: popoverPlacement.Popover
): ()
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local gui, input = kit.gui, kit.input
	local appearance, atRest = presence.appearance, presence.atRest
	local overlay, parent = portal.overlay, portal.parent
	local helpPointer = Compose.createSharedResource(function()
		local buttons: { [string]: boolean } = {}
		local pressed = Compose.cell(false)
		local activity = Compose.cell(0)
		local focused = Compose.cell(true)
		local function mouseButton(kind: Enum.UserInputType): boolean
			return kind == E.UserInputType.MouseButton1
				or kind == E.UserInputType.MouseButton2
				or kind == E.UserInputType.MouseButton3
		end
		local function disturb()
			activity:set(activity:peek() + 1)
		end
		local function begin(event: InputObject)
			if mouseButton(event.UserInputType) then
				buttons[event.UserInputType.Name] = true
				pressed:set(true)
				disturb()
			end
		end
		local function finish(event: InputObject)
			if mouseButton(event.UserInputType) then
				buttons[event.UserInputType.Name] = nil
				pressed:set(next(buttons) ~= nil)
				disturb()
			end
		end
		local function change(event: InputObject)
			if
				event.UserInputType == E.UserInputType.MouseMovement
				or event.UserInputType == E.UserInputType.MouseWheel
			then
				disturb()
			end
		end
		if input then
			if input.GetMouseButtonsPressed then
				for _, event in input:GetMouseButtonsPressed() do
					begin(event)
				end
			end
			runtime.connect(input, "InputBegan", begin)
			runtime.connect(input, "InputEnded", finish)
			runtime.connect(input, "InputChanged", change)
		end
		local window = ctx.config.inputParent
		local focusSource = if window and window:IsA("PluginGui") then window else input
		if focusSource then
			runtime.connect(focusSource, "WindowFocusReleased", function()
				focused:set(false)
				table.clear(buttons)
				pressed:set(false)
				disturb()
			end)
			runtime.connect(focusSource, "WindowFocused", function()
				focused:set(true)
				disturb()
			end)
		end
		return {
			pressed = pressed,
			activity = activity,
			focused = focused,
			begin = begin,
			finish = finish,
			change = change,
			disturb = disturb,
		}
	end)
	help.register(ctx, function(anchor: GuiObject, value: Inputs.Help, plate: help.Plate?)
		local structured: Inputs.HelpSpec? = if type(value) == "table" and not Compose.isReadable(value)
			then value :: Inputs.HelpSpec
			else nil
		local text: Types.Value<string> = if structured then structured.body else value :: Types.Value<string>
		local gate = plate and plate.gate
		local state = ctx.observe.GuiState(anchor)
		local selection = if gui and gui.GetPropertyChangedSignal then ctx.observe.SelectedObject(gui) else nil
		local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
		local held = Compose.cell(false)
		local touchOffset: ComposeTypes.Cell<Vector2?> = Compose.cell(nil :: Vector2?)
		local function press(points: { Vector2 }, phase: Enum.UserInputState)
			if phase == E.UserInputState.Begin and ctx.read(gate) ~= false then
				local point = points[1]
				touchOffset:set(if point then point - anchor.AbsolutePosition else anchor.AbsoluteSize / 2)
				held:set(true)
				help.hold(anchor, true)
			end
		end
		if anchor:IsA("GuiButton") then
			runtime.connect(anchor, "TouchLongPress", function(points: { Vector2 }, phase: Enum.UserInputState)
				press(points, phase)
			end)
		elseif input then
			runtime.connect(input, "TouchLongPress", function(points: { Vector2 }, phase: Enum.UserInputState)
				local point: Vector2? = points[1]
				local layer = anchor:FindFirstAncestorWhichIsA("ScreenGui")
				if point == nil or layer == nil or not kit.displayed(anchor) then
					return
				end
				local offset = if layer.IgnoreGuiInset and gui then gui:GetGuiInset() else V2.zero
				local at, size = anchor.AbsolutePosition - offset, anchor.AbsoluteSize
				if point.X >= at.X and point.X <= at.X + size.X and point.Y >= at.Y and point.Y <= at.Y + size.Y then
					press({ point + offset }, phase)
				end
			end)
		end
		runtime.connect(anchor, "InputBegan", function()
			help.hold(anchor, false)
		end)
		local pointer = helpPointer()
		runtime.connect(anchor, "InputBegan", pointer.begin)
		runtime.connect(anchor, "InputEnded", pointer.finish)
		runtime.connect(anchor, "InputChanged", pointer.change)
		runtime.connect(anchor, "MouseMoved", pointer.disturb)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(pointer.pressed) or not use(pointer.focused) then
				held:set(false)
				touchOffset:set(nil)
			end
		end)
		if input then
			runtime.connect(input, "InputBegan", function(event: InputObject)
				if held:peek() and event.UserInputType == E.UserInputType.Touch then
					held:set(false)
					touchOffset:set(nil)
				end
			end)
		end
		local wanted = Compose.formula(function(use: ComposeTypes.Use): boolean
			local kind = if preferred then use(preferred) else nil
			if kind == E.PreferredInput.Touch or use(pointer.pressed) or not use(pointer.focused) then
				return false
			end
			local selected = if selection then use(selection) else nil
			return use(state) == E.GuiState.Hover
				or (selected ~= nil and (selected == anchor or anchor:IsDescendantOf(selected)))
		end)
		local rest = runtime.timeline({ duration = HELP_DWELL, autoplay = false })
		Compose.watch(function(use: ComposeTypes.Use)
			if use(wanted) then
				use(pointer.activity)
				rest:restart()
			else
				rest:pause()
				rest:seek(0)
			end
		end)
		local armed = Compose.formula(function(use: ComposeTypes.Use): boolean
			return ctx.read(gate, use) ~= false and (use(held) or (use(wanted) and use(rest.progress) >= 1))
		end)
		local shown = plate and plate.shown
		if shown then
			Compose.watch(function(use: ComposeTypes.Use)
				shown:set(use(armed))
			end)
		end
		local timing: Nav.MotionTiming = { enter = ctx.metric("motion.normal"), exit = ctx.metric("motion.fast") }
		kit.attach(anchor, {
			overlay(anchor, armed, function(phase: Nav.PresencePhase?)
				local settled = Compose.cell(false)
				local presence = appearance(phase, timing, settled)
				local layer = assert(parent(anchor))
				local at, bounds = ctx.observe.AbsolutePosition(anchor), ctx.observe.AbsoluteSize(anchor)
				local extent, origin = ctx.observe.AbsoluteSize(layer), ctx.observe.AbsolutePosition(layer)
				local label = ctx.text({
					Name = "HelpText",
					Text = function(use: ComposeTypes.Use)
						return ctx.read(text, use) or ""
					end,
					TextWrapped = true,
					Host.UISizeConstraint({ MaxSize = V2.new(264, math.huge) }) :: Types.Child,
				})
				label:AddTag("facet-type-caption")
				local panelProps: Types.CanvasGroupNativeProps = {
					Name = plate and plate.name or "Help",
					GroupTransparency = function(use: ComposeTypes.Use)
						return 1 - presence.opacity(use)
					end,
					AutomaticSize = E.AutomaticSize.XY,
					Size = D2.fromOffset(0, 0),
					ZIndex = 96,
				}
				panelProps[#panelProps + 1] = ctx.padding(8, 6)
				panelProps[#panelProps + 1] =
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = ctx.types.UDim.new(0, 4) })
				if structured and structured.title ~= nil then
					local title = structured.title
					local heading = ctx.text({
						Name = "HelpTitle",
						LayoutOrder = 1,
						Text = function(use: ComposeTypes.Use)
							return ctx.read(title, use) or ""
						end,
					})
					heading:AddTag("facet-type-heading")
					panelProps[#panelProps + 1] = heading
				end
				runtime.decorate(label, {
					LayoutOrder = 2,
					Visible = function(use: ComposeTypes.Use)
						return (ctx.read(text, use) or "") ~= ""
					end,
				})
				panelProps[#panelProps + 1] = label
				if structured and structured.shortcut then
					local chords: { string } = {}
					for _, chord in structured.shortcut do
						table.insert(chords, table.concat(chord, "+"))
					end
					local hint = ctx.text({
						Name = "HelpShortcut",
						LayoutOrder = 3,
						Text = table.concat(chords, " or "),
					})
					hint:AddTag("facet-type-caption")
					hint:AddTag("facet-secondary")
					panelProps[#panelProps + 1] = hint
				end
				local panel = ctx.fade(panelProps, true)
				local sizes, rested = atRest(presence.travel, settled, { panel, label })
				local measured = sizes[1]
				local edge = if structured and structured.edge then structured.edge else "top"
				local align = if structured and structured.align then structured.align else "center"
				local solution = Compose.formula(function(use: ComposeTypes.Use): placement.Placement
					local anchorAt, anchorSize, offer, offset, box =
						use(at), use(bounds), use(extent), use(origin), use(measured)
					local side = parts.tailSize(ctx, use)
					local contact = use(touchOffset)
					if contact then
						local point = anchorAt + contact - offset
						return placement.touch(
							{ x = point.X, y = point.Y },
							{ w = box.X, h = box.Y },
							{ x = 8, y = 8, w = math.max(0, offer.X - 16), h = math.max(0, offer.Y - 16) },
							ctx.metric("targetSizes.minimum", use) + ctx.metric("space.s", use)
						)
					end
					return placement.solve({
						source = {
							x = anchorAt.X - offset.X,
							y = anchorAt.Y - offset.Y,
							w = anchorSize.X,
							h = anchorSize.Y,
						},
						size = { w = box.X, h = box.Y },
						safe = { x = 8, y = 8, w = math.max(0, offer.X - 16), h = math.max(0, offer.Y - 16) },
						edge = edge,
						align = align,
						gap = 6 + side * math.sqrt(2) / 2,
						tail = side * math.sqrt(2),
						tailInset = 6,
					})
				end)
				ctx.styled(panel, "tooltip")
				local scale = popover(panel, presence.travel, function(use: ComposeTypes.Use): (Vector2, Vector2)
					local anchorAt, anchorSize, offset, box = use(at), use(bounds), use(origin), use(measured)
					local solved = use(solution)
					local centerX = anchorAt.X - offset.X + anchorSize.X / 2 - solved.x
					local centerY = anchorAt.Y - offset.Y + anchorSize.Y / 2 - solved.y
					local origin = if solved.edge == "bottom"
						then V2.new(math.clamp(centerX, 0, box.X), 0)
						elseif solved.edge == "top" then V2.new(math.clamp(centerX, 0, box.X), box.Y)
						elseif solved.edge == "right" then V2.new(0, math.clamp(centerY, 0, box.Y))
						else V2.new(box.X, math.clamp(centerY, 0, box.Y))
					return V2.new(solved.x, solved.y), origin
				end, {
					pinned = true,
					rested = rested,
					size = measured,
					geometry = { Size = panelProps.Size, AutomaticSize = panelProps.AutomaticSize },
				})
				local tail = parts.tail(
					ctx,
					"HelpTail",
					function(use: ComposeTypes.Use): (Vector2?, string)
						local solved = use(solution)
						if solved.tailSuppressed or solved.tailX == nil or solved.tailY == nil then
							return nil, solved.edge
						end
						return V2.new(solved.tailX, solved.tailY), solved.edge
					end,
					presence.opacity,
					function()
						return 96
					end,
					{
						node = panel,
						scale = scale,
						corner = function(use: ComposeTypes.Use): Vector2
							local solved = use(solution)
							return V2.new(solved.x, solved.y)
						end,
						size = measured,
						radius = function(use: ComposeTypes.Use): number
							return math.min(6, (ctx.metric("radii.control", use)))
						end,
						role = "tooltip",
					}
				)
				return Host.Folder "HelpOverlay" { panel :: Instance, table.unpack(tail) }
			end, { motion = timing }),
		})
	end)
end
