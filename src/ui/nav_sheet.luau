--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local release = require("./sheet_release")
local freeze = require("./freeze")

type Controls = {
	Sheet: Types.Constructor<Nav.SheetSpec, Frame>,
	Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
}
type Detent = { id: string, fraction: number?, height: number?, hug: boolean, index: number }
type Prepared = { detents: { Detent }, byId: { [string]: Detent }, cancel: Overlay.Action? }
type Session = {
	source: "grip" | "panel",
	origin: number,
	start: number,
	detent: string,
	acquired: boolean,
	slop: number,
	samples: { { height: number, at: number } },
}

local KEYS = {
	"title",
	"content",
	"detent",
	"detents",
	"isPresented",
	"interactiveDismissDisabled",
	"dragIndicator",
	"placement",
	"edge",
	"width",
	"closeButton",
	"header",
	"hero",
	"actions",
	"actionLayout",
	"contentInset",
	"scrollPolicy",
}
local PLACEMENTS: { [string]: boolean } =
	freeze({ automatic = true, adaptive = true, bottom = true, side = true, center = true })
local HANDLE = 20
local SHEET: { enter: number, exit: number } = freeze({ enter = 0.3, exit = 0.2 })
local SETTLE_LIMIT = 20
local SETTLE_PERIOD = 0.4

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local readSource = ctx.readSource
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local frames = runtime.host.frames
	local function now(): number
		return if frames then frames.now() else os.clock()
	end

	local function prepare(spec: Nav.SheetSpec): Prepared
		assert(type(spec.detent) == "table" and spec.detent.set, "Sheet.detent requires a writable Compose cell")
		local placement = spec.placement or "automatic"
		assert(PLACEMENTS[placement], "Sheet.placement must be automatic, adaptive, bottom, side or center")
		assert(
			spec.edge == nil
				or ((placement == "side" or placement == "adaptive") and (spec.edge == "left" or spec.edge == "right")),
			"Sheet.edge is left or right, and only with placement side or adaptive"
		)
		assert(spec.width == nil or parts.WIDTHS[spec.width] ~= nil, "Sheet.width must be automatic, narrow or wide")
		assert(
			spec.closeButton == nil
				or type(spec.closeButton) == "boolean"
				or parts.bound(ctx, spec.closeButton, "string"),
			"Sheet.closeButton must be a boolean or a label"
		)
		local header = spec.header
		assert(
			header == nil or header == false or parts.instance(header) or type(header) == "function",
			"Sheet.header must be an Instance, a content factory or false"
		)
		assert(
			spec.contentInset == nil or spec.contentInset == "standard" or spec.contentInset == "none",
			"Sheet.contentInset must be standard or none"
		)
		assert(
			spec.actionLayout == nil
				or spec.actionLayout == "automatic"
				or spec.actionLayout == "row"
				or spec.actionLayout == "stacked",
			"Sheet.actionLayout must be automatic, row or stacked"
		)
		assert(
			spec.scrollPolicy == nil or spec.scrollPolicy == "always" or spec.scrollPolicy == "atLargestDetent",
			"Sheet.scrollPolicy must be always or atLargestDetent"
		)
		assert(
			spec.dragIndicator == nil
				or spec.dragIndicator == "automatic"
				or spec.dragIndicator == "visible"
				or spec.dragIndicator == "hidden",
			"Sheet.dragIndicator must be automatic, visible or hidden"
		)
		parts.checkHero("UI.Sheet", spec.hero)
		parts.checkActions(ctx, "UI.Sheet", spec.actions, math.huge)
		local cancel: Overlay.Action? = nil
		local listed: { Overlay.Action } = spec.actions or {}
		for _, action in listed do
			if action.role == "cancel" then
				cancel = action
			end
		end
		local detents: { Detent } = {}
		local byId: { [string]: Detent } = {}
		local entries: { Nav.SheetDetent } = spec.detents or { "medium", "large" }
		assert(#entries > 0, "Invalid Sheet detent")
		for index, entry in entries do
			local d: Detent
			if entry == "medium" then
				d = { id = "medium", fraction = 0.5, hug = false, index = index }
			elseif entry == "large" then
				d = { id = "large", fraction = 0.95, hug = false, index = index }
			elseif entry == "hug" then
				d = { id = "hug", hug = true, index = index }
			else
				assert(type(entry) == "table", "Invalid Sheet detent")
				local custom = (entry :: unknown) :: { [string]: unknown }
				for key in custom do
					assert(key == "id" or key == "fraction" or key == "height", "Invalid Sheet detent")
				end
				assert(type(custom.id) == "string" and custom.id ~= "", "Invalid Sheet detent")
				assert(
					(custom.fraction == nil) ~= (custom.height == nil),
					"Sheet detent requires exactly one of fraction or height"
				)
				local fraction, height = custom.fraction, custom.height
				assert(
					if fraction ~= nil
						then type(fraction) == "number" and fraction > 0 and fraction <= 1
						else type(height) == "number" and height > 0 and height < math.huge,
					"Invalid Sheet detent extent"
				)
				d = {
					id = custom.id :: string,
					fraction = fraction :: number?,
					height = height :: number?,
					hug = false,
					index = index,
				}
			end
			assert(not byId[d.id], "Sheet detents require unique ids")
			byId[d.id] = d
			table.insert(detents, d)
		end
		return { detents = detents, byId = byId, cancel = cancel }
	end

	local function word(id: string): string
		if id == "hug" then
			return "Fit"
		end
		return string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
	end

	local function modalFor(
		spec: Nav.SheetSpec,
		prepared: Prepared,
		request: Nav.SheetRequest?,
		phase: Nav.PresencePhase?
	): Frame
		local detents, byId = prepared.detents, prepared.byId
		local declared = spec.placement or "automatic"
		local edge = spec.edge or "right"
		local gui = surfaces.service("GuiService")
		local input = surfaces.service("UserInputService")
		local reduced = if gui then ctx.observe.ReducedMotionEnabled(gui) else Compose.cell(false)
		local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if input
				and input.GetPropertyChangedSignal
			then ctx.observe.PreferredInput(input)
			else nil
		local function reduce(use: ComposeTypes.Use?): boolean
			return read(ctx.config.reducedMotion, use) == true or read(reduced, use) == true
		end
		local keyboard: (ComposeTypes.Use) -> number = function()
			return 0
		end
		if input and input.GetPropertyChangedSignal then
			local visible = ctx.observe.OnScreenKeyboardVisible(input)
			local size = ctx.observe.OnScreenKeyboardSize(input)
			keyboard = function(use: ComposeTypes.Use): number
				return if use(visible) == true then use(size).Y else 0
			end
		end
		local extent = Compose.cell(V2.new(0, 720))
		local function available(use: ComposeTypes.Use?): number
			local get: ComposeTypes.Use = use
				or function<T>(source: ComposeTypes.Readable<T>): T
					return source:peek()
				end
			return math.max(1, get(extent).Y - keyboard(get))
		end
		local function minimum(use: ComposeTypes.Use?): number
			return ctx.metric("targetSizes.minimum", use) * 4 + ctx.metric("space.m", use) * 2
		end
		local hugHeight: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local function heightOf(d: Detent, use: ComposeTypes.Use?): number
			local room = available(use)
			local want = if d.hug
				then readSource(hugHeight, use) or minimum(use)
				elseif d.fraction then room * d.fraction
				else assert(d.height)
			return math.min(room, math.max(minimum(use), want))
		end
		local function ordered(): { Detent }
			local out = table.clone(detents)
			table.sort(out, function(a: Detent, b: Detent): boolean
				local ha, hb = heightOf(a), heightOf(b)
				if ha ~= hb then
					return ha < hb
				end
				return a.index < b.index
			end)
			return out
		end
		local lastValid = if byId[spec.detent:peek()] then spec.detent:peek() else detents[1].id
		local function selected(use: ComposeTypes.Use?): Detent
			local id = readSource(spec.detent, use)
			local found = byId[id]
			if found then
				lastValid = id
				return found
			end
			return byId[lastValid]
		end
		local dragHeight: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local ready = Compose.cell(frames == nil)
		local motion = runtime.tween(function(use: ComposeTypes.Use)
			return use(dragHeight) or heightOf(selected(use), use)
		end, {
			seconds = 0.2,
			reducedMotion = function(use: ComposeTypes.Use): boolean
				return not use(ready)
			end,
		})
		local settling: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local stopSettle: (() -> ())? = nil
		local function painted(use: ComposeTypes.Use?): number
			local drag = readSource(dragHeight, use)
			if drag then
				return drag
			end
			if reduce(use) then
				return heightOf(selected(use), use)
			end
			local settle = if use then use(settling) else settling:peek()
			return if settle then settle else read(motion, use)
		end
		local function halt()
			local stop = stopSettle
			stopSettle = nil
			if stop then
				stop()
			end
			settling:set(nil)
		end
		local function launch(from: number, speed: number)
			halt()
			if frames == nil or reduce() then
				return
			end
			local position, velocity = from, speed
			local stiffness, damping = (2 * math.pi / SETTLE_PERIOD) ^ 2, 4 * math.pi / SETTLE_PERIOD
			settling:set(position)
			stopSettle = frames.onFrame(function(delta: number)
				local target = heightOf(selected())
				local remaining = math.min(delta, 0.25)
				while remaining > 0 do
					local step = math.min(remaining, 1 / 120)
					remaining -= step
					velocity += (-stiffness * (position - target) - damping * velocity) * step
					local nextPosition = position + velocity * step
					if (nextPosition - target) * (position - target) <= 0 then
						position, velocity = target, 0
						break
					end
					position = nextPosition
				end
				if math.abs(position - target) < 0.5 and math.abs(velocity) < 5 then
					halt()
					return
				end
				settling:set(position)
			end)
		end
		Compose.cleanup(halt)
		local canDismiss = function(use: ComposeTypes.Use?): boolean
			return read(spec.interactiveDismissDisabled, use) ~= true
		end
		local function close(reason: string)
			if request then
				request(reason)
			else
				spec.isPresented:set(false)
			end
		end
		local function interactive(reason: string)
			if canDismiss() then
				close(reason)
			end
		end
		local function select(id: string)
			dragHeight:set(nil)
			spec.detent:set(id)
		end
		local function cycle()
			local sorted = ordered()
			local index = table.find(sorted, selected()) or 1
			select(sorted[index % #sorted + 1].id)
		end
		local session: Session? = nil
		local function endSession()
			session = nil
			dragHeight:set(nil)
		end
		local function stops(): { release.Stop }
			local out: { release.Stop } = {}
			for _, d in ordered() do
				table.insert(out, { id = d.id, height = heightOf(d), index = d.index })
			end
			return out
		end
		local function grab(source: "grip" | "panel", y: number): boolean
			if session then
				return false
			end
			local kind = if preferred then preferred:peek() else nil
			session = {
				source = source,
				origin = y,
				start = painted(),
				detent = selected().id,
				acquired = source == "grip",
				slop = if source == "grip" then 0 elseif kind == E.PreferredInput.Touch then 14 else 6,
				samples = {},
			}
			local current = assert(session)
			if current.acquired then
				halt()
				dragHeight:set(current.start)
				table.insert(current.samples, { height = current.start, at = now() })
			end
			return true
		end
		local function move(source: "grip" | "panel", y: number)
			local current = session
			if current == nil or current.source ~= source then
				return
			end
			if not current.acquired then
				if math.abs(y - current.origin) < current.slop then
					return
				end
				current.acquired = true
				current.origin += if y > current.origin then current.slop else -current.slop
				halt()
				dragHeight:set(current.start)
				table.insert(current.samples, { height = current.start, at = now() })
			end
			local sorted = stops()
			local height = release.resist(
				current.start + current.origin - y,
				sorted[1].height,
				sorted[#sorted].height,
				available(),
				canDismiss(),
				ctx.metric("targetSizes.minimum")
			)
			dragHeight:set(height)
			table.insert(current.samples, { height = height, at = now() })
			if #current.samples > 8 then
				table.remove(current.samples, 1)
			end
		end
		local function velocity(current: Session): number
			local count = #current.samples
			if count < 2 then
				return 0
			end
			local last = current.samples[count]
			local first = last
			for index = count - 1, 1, -1 do
				if last.at - current.samples[index].at > 0.1 then
					break
				end
				first = current.samples[index]
			end
			local span = last.at - first.at
			if span < 1 / 240 or now() - last.at > 0.1 then
				return 0
			end
			return (last.height - first.height) / span
		end
		local function finish(source: "grip" | "panel")
			local current = session
			if current == nil or current.source ~= source then
				return
			end
			if not current.acquired then
				endSession()
				return
			end
			local height = dragHeight:peek() or current.start
			local speed = velocity(current)
			local choice = release.choose(stops(), height, speed, selected().id, canDismiss())
			if choice ~= "dismiss" then
				launch(height, speed)
			end
			endSession()
			if choice == "dismiss" then
				if request == nil or request("drag") then
					if request == nil then
						spec.isPresented:set(false)
					end
				else
					select(selected().id)
				end
				return
			end
			select(choice)
		end
		local watchedDetent = spec.detent:peek()
		Compose.watch(function(use: ComposeTypes.Use)
			local id = use(spec.detent)
			if id ~= watchedDetent then
				watchedDetent = id
				if session then
					endSession()
				end
			end
		end)
		Compose.cleanup(function()
			session = nil
		end)
		local function detector(name: string, source: "grip" | "panel"): Instance
			return Host.UIDragDetector({
				Name = name,
				DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
				DragAxis = V2.new(0, 1),
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				DragStart = function(position: Vector2)
					grab(source, position.Y)
				end,
				DragContinue = function(position: Vector2)
					move(source, position.Y)
				end,
				DragEnd = function()
					finish(source)
				end,
			})
		end
		local tallest = Compose.formula(function(use: ComposeTypes.Use): boolean
			local mine = heightOf(selected(use), use)
			for _, other in detents do
				if heightOf(other, use) > mine then
					return false
				end
			end
			return true
		end)
		local indicator = spec.dragIndicator or "automatic"
		local grabber = Host.TextButton "Grabber" {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.fromOffset(88, 44),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Text = "",
			AutoButtonColor = false,
			Selectable = #detents > 1,
			Activated = cycle,
			ctx.styled(
				Host.Frame "Pill" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.fromOffset(36, 5),
					BorderSizePixel = 0,
					Host.UICorner({ CornerRadius = ctx.types.UDim.new(1, 0) }),
				},
				"grabber"
			) :: Types.Child,
		}
		Compose.watch(function(use: ComposeTypes.Use)
			grabber:SetAttribute("AccessibleLabel", "Size: " .. word(selected(use).id))
		end)
		local handle = Host.Frame "DragHandle" {
			BackgroundTransparency = 1,
			Size = D2.new(1, 0, 0, HANDLE),
			Visible = indicator ~= "hidden",
			detector("UIDragDetector", "grip"),
			grabber :: Instance,
		}
		local regions: { GuiObject } = {}
		local hero = spec.hero
		local sticky = hero ~= nil and hero.sticky == true
		local overHero = spec.header == false and hero ~= nil
		local closeLabel: Types.Value<string> = if spec.closeButton == nil
				or type(spec.closeButton) == "boolean"
			then "Done"
			else spec.closeButton :: Types.Value<string>
		local function closeControl(): TextButton?
			if spec.closeButton == false then
				return nil
			end
			return UI.Button "Close" {
				label = closeLabel,
				appearance = "link",
				onActivate = function()
					close("close")
				end,
			}
		end
		local function heroFrame(): Frame
			local current = assert(hero)
			local frame = parts.media(ctx, current, "Hero")
			if current.content then
				local children: { Types.Child } = {
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				}
				if overHero then
					table.insert(
						children,
						Host.Frame({
							Name = "Strip",
							BackgroundTransparency = 1,
							LayoutOrder = 0,
							Size = function(use: ComposeTypes.Use)
								return D2.new(1, 0, 0, ctx.metric("targetSizes.minimum", use))
							end,
						})
					)
				end
				local content = current.content
				local node: Instance = if type(content) == "function" then content() else content :: Instance
				if node:IsA("GuiObject") then
					runtime.decorate(node, { LayoutOrder = 1 })
				end
				table.insert(children, node)
				surfaces.attach(frame, {
					Host.Frame "Art" {
						BackgroundTransparency = 1,
						Size = D2.fromScale(1, 1),
						table.unpack(children),
					},
				})
			end
			if overHero then
				local close = closeControl()
				if close then
					surfaces.attach(frame, {
						Host.Frame "Utilities" {
							BackgroundTransparency = 1,
							AnchorPoint = V2.new(1, 0),
							Position = D2.fromScale(1, 0),
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							ZIndex = 3,
							close,
						},
					})
				end
			end
			return frame
		end
		if sticky then
			table.insert(regions, heroFrame())
		end
		if not overHero then
			local header: { Types.Child } = {}
			if spec.header == nil then
				table.insert(
					header,
					ctx.styled(
						ctx.text({
							Name = "Title",
							Text = function(use: ComposeTypes.Use)
								return read(spec.title, use) or ""
							end,
							TextWrapped = true,
							Size = D2.fromOffset(0, 0),
							AutomaticSize = E.AutomaticSize.XY,
							Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }),
						}),
						"type-heading"
					)
				)
			elseif spec.header ~= false then
				local custom = spec.header
				local node: Instance = if type(custom) == "function" then custom() else custom :: Instance
				if node:IsA("GuiObject") then
					surfaces.attach(node, { Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) })
				end
				table.insert(header, node)
			end
			local close = closeControl()
			if close then
				table.insert(header, close)
			end
			if #header > 0 then
				local row: Types.FrameNativeProps = {
					Name = "Header",
					BackgroundTransparency = 1,
					Size = D2.new(1, 0, 0, 0),
					AutomaticSize = E.AutomaticSize.Y,
				}
				table.insert(
					row,
					Host.UIListLayout({
						FillDirection = E.FillDirection.Horizontal,
						HorizontalAlignment = E.HorizontalAlignment.Right,
						VerticalAlignment = E.VerticalAlignment.Center,
						SortOrder = E.SortOrder.LayoutOrder,
						Padding = ctx.types.UDim.new(0, 8),
					})
				)
				for _, child in header do
					table.insert(row, child)
				end
				table.insert(regions, Host.Frame(row))
			end
		end
		local inset = if spec.contentInset == "none" then 0 else 8
		local bodyLayout = Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder })
		local bodyPadding = ctx.padding(inset, inset)
		local bodyChildren: { Types.Child } = { bodyLayout }
		local content: Instance = if type(spec.content) == "function"
			then (spec.content :: () -> Instance)()
			else spec.content :: Instance
		if hero and not sticky then
			table.insert(bodyChildren, heroFrame())
			local inner: Types.FrameNativeProps = {
				Name = "Inset",
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Size = D2.new(1, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.Y,
			}
			table.insert(inner, Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }))
			table.insert(inner, ctx.padding(inset, inset))
			table.insert(inner, content)
			table.insert(bodyChildren, Host.Frame(inner))
		else
			table.insert(bodyChildren, bodyPadding)
			table.insert(bodyChildren, content)
		end
		local flex = Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill })
		local bodyProps: Types.ScrollingFrameNativeProps = {
			Name = "SheetContent",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollingDirection = E.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			ClipsDescendants = true,
			flex :: Instance,
		}
		local body = parts.scroller(ctx, bodyProps, bodyChildren, { name = "SheetFlow" })
		table.insert(regions, body)
		local function usable(action: Overlay.Action?): boolean
			return parts.usable(ctx, action)
		end
		local function press(action: Overlay.Action)
			if usable(action) then
				action.onActivate()
			end
		end
		local panelWidth = Compose.formula(function(use: ComposeTypes.Use): number
			return math.max(0, math.min(parts.width(ctx, spec.width, use), use(extent).X))
		end)
		local actions = spec.actions or {}
		if #actions > 0 then
			table.insert(
				regions,
				parts.actions(ctx, UI, actions, spec.actionLayout, function(use: ComposeTypes.Use)
					return use(panelWidth) - 32
				end, press).frame
			)
		end
		local contentSize = ctx.observe.AbsoluteContentSize(bodyLayout)
		local extra = if hero == nil or sticky then inset * 2 else 0
		local function natural(use: ComposeTypes.Use): number
			return use(contentSize).Y + extra
		end
		local chrome = function(use: ComposeTypes.Use): number
			return (if indicator == "hidden" then 0 else HANDLE) + 24 + 8
		end
		local room = parts.room(ctx, regions, body, natural, function(use: ComposeTypes.Use): number
			return math.max(0, painted(use) - chrome(use))
		end, true)
		runtime.decorate(flex, {
			FlexMode = function(use: ComposeTypes.Use)
				return if use(room.tight) then E.UIFlexMode.None else E.UIFlexMode.Fill
			end,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			local want = natural(use) + use(room.pinned) + chrome(use) + 8
			local previous = hugHeight:peek()
			if want > 0 and (previous == nil or math.abs(previous - want) > 0.5) then
				hugHeight:set(want)
			end
		end)
		if spec.scrollPolicy == "atLargestDetent" then
			runtime.decorate(body, {
				ScrollingEnabled = function(use: ComposeTypes.Use)
					return use(tallest) and not use(room.tight)
				end,
				Active = tallest,
			})
		end
		local pointer: (ComposeTypes.Use) -> boolean = function()
			return false
		end
		if declared == "adaptive" and input and input.GetPropertyChangedSignal then
			local mouse, touch = ctx.observe.MouseEnabled(input), ctx.observe.TouchEnabled(input)
			pointer = function(use: ComposeTypes.Use): boolean
				return use(mouse) == true and use(touch) ~= true
			end
		end
		local placed = Compose.formula(function(use: ComposeTypes.Use): string
			if declared == "adaptive" then
				return if use(extent).X >= 600 and pointer(use) then "side" else "bottom"
			end
			return if declared == "automatic" then "bottom" else declared
		end)
		local function anchors(use: ComposeTypes.Use): (number, number)
			local placement = use(placed)
			return if placement == "side" then (if edge == "left" then 0 else 1) else 0.5,
				if placement == "center" then 0.5 else 1
		end
		local shown = surfaces.appearance(phase, SHEET, ready)
		local function travel(use: ComposeTypes.Use): (number, number)
			local rest = 1 - shown(use)
			if rest <= 0 then
				return 0, 0
			end
			local placement = use(placed)
			if placement == "side" then
				local width = use(panelWidth)
				return rest * (if edge == "left" then -width else width), 0
			end
			if placement == "center" then
				return 0, 0
			end
			return 0, math.ceil(painted(use) * rest)
		end
		local panel = ctx.column({
			handle,
			room.frame,
			ctx.padding(16, 12),
			ctx.corner(),
			detector("PanelDrag", "panel") :: Instance,
		}, {
			Name = "SheetPanel",
			BackgroundTransparency = 0,
			AnchorPoint = function(use: ComposeTypes.Use)
				local anchorX, anchorY = anchors(use)
				return V2.new(anchorX, anchorY)
			end,
			Position = function(use: ComposeTypes.Use)
				local anchorX, anchorY = anchors(use)
				local y = if anchorY == 1 then -keyboard(use) else -keyboard(use) / 2
				local dx, dy = travel(use)
				return D2.new(anchorX, dx, anchorY, y + dy)
			end,
			AutomaticSize = E.AutomaticSize.None,
			Size = function(use: ComposeTypes.Use)
				return D2.fromOffset(use(panelWidth), painted(use))
			end,
		})
		local layout = panel:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?
		if layout then
			layout.Padding = ctx.types.UDim.new(0, 8)
		end
		ctx.styled(panel, "sheet")
		runtime.decorate(panel, {
			Attributes = {
				FacetPlacement = function(use: ComposeTypes.Use): string
					return use(placed)
				end,
			},
		})
		surfaces.skin(panel)
		local overlay = surfaces.modal(function()
			return panel
		end, function()
			if not canDismiss() then
				return
			end
			if prepared.cancel and usable(prepared.cancel) then
				press(prepared.cancel)
			else
				interactive("cancel")
			end
		end, {
			canDismiss = function(use: ComposeTypes.Use)
				return canDismiss(use)
			end,
			onOutside = function()
				interactive("outside")
			end,
			exiting = if phase then phase.exiting else nil,
			appearance = shown,
		})
		local size = ctx.observe.AbsoluteSize(overlay)
		local measured = Compose.cell(false)
		Compose.watch(function(use: ComposeTypes.Use)
			local value = use(size)
			if value.Y > 0 then
				extent:set(value)
				measured:set(true)
			end
		end)
		if frames and not ready:peek() then
			local panelSize = ctx.observe.AbsoluteSize(panel)
			local function textExtent(): number
				local total = 0
				for _, node in panel:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
						total += node.TextBounds.X + node.TextBounds.Y * 4096
					end
				end
				return total
			end
			local fontsReady = Compose.cell(true)
			local provider = ctx.config.services and ctx.config.services.ContentProvider
			if provider and task then
				fontsReady:set(false)
				local owner = assert(Compose.currentOwner())
				local thread = task.defer(function()
					local texts: { Instance } = {}
					for _, node in panel:GetDescendants() do
						if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
							table.insert(texts, node)
						end
					end
					pcall(function()
						provider:PreloadAsync(texts)
					end)
					if not owner.isDisposed() then
						fontsReady:set(true)
					end
				end)
				Compose.cleanup(function()
					if coroutine.status(thread) == "suspended" then
						pcall(task.cancel, thread)
					end
				end)
			end
			local started = Compose.cell(false)
			local clock = runtime.tween(function(use: ComposeTypes.Use): number
				return if use(started) then 1 else 0
			end, { seconds = SETTLE_LIMIT / 60 })
			started:set(true)
			local previous: string? = nil
			Compose.watch(function(use: ComposeTypes.Use)
				local elapsed = use(clock)
				local finished = elapsed >= 1
				if ready:peek() or elapsed <= 0 then
					return
				end
				local signature = if measured:peek()
					then string.format(
						"%d %d %d %d %d %d",
						extent:peek().X,
						extent:peek().Y,
						panelSize:peek().X,
						contentSize:peek().Y,
						room.pinned:peek(),
						textExtent()
					)
					else nil
				if finished or (fontsReady:peek() and signature ~= nil and signature == previous) then
					ready:set(true)
				end
				previous = signature
			end)
		end
		return overlay
	end

	UI.Sheet = ctx.construct("Sheet", function(spec: Nav.SheetSpec): Frame
		local prepared = prepare(spec)
		assert(
			type(spec.isPresented) == "table" and spec.isPresented.set,
			"Sheet.isPresented requires a writable Compose cell"
		)
		local root = Host.Frame(
			ctx.props(spec, KEYS, { Name = "Sheet", BackgroundTransparency = 1, Size = D2.fromOffset(0, 0) })
		)
		surfaces.attach(root, {
			surfaces.overlay(root, spec.isPresented, function(phase)
				return modalFor(spec, prepared, nil, phase)
			end, {
				motion = SHEET,
				failure = function(failure)
					root:SetAttribute("FacetError", tostring(failure))
					spec.isPresented:set(false)
					if ctx.config.onError then
						ctx.config.onError(failure)
					end
					return Host.Folder "FailedSheet" {}
				end,
			}),
		})
		return root
	end)

	surfaces.sheetModal = function(spec: Nav.SheetSpec, request: Nav.SheetRequest, phase: Nav.PresencePhase?): Frame
		return modalFor(spec, prepare(spec), request, phase)
	end
end
