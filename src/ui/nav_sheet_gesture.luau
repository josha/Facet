--!strict
local ControlTypes = require("./control_types")
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local parts = require("./overlay_parts")
local release = require("./sheet_release")
local settle = require("./settle")
local motion = require("./motion")
local reducedMotion = motion.reduced
local NavigationProps = require("./navigation_props")
local sheetDetents = require("./nav_sheet_detents")

type Detent = sheetDetents.Detent
type Prepared = sheetDetents.Prepared
type Session = {
	source: "grip" | "panel",
	origin: number,
	start: number,
	detent: string,
	acquired: boolean,
	slop: number,
	moved: boolean,
	samples: { { height: number, at: number } },
}

export type Gesture = {
	edge: string,
	level: (ComposeTypes.Use?) -> motion.Level,
	unit: ComposeTypes.Cell<number>,
	keyboard: (ComposeTypes.Use) -> number,
	extent: ComposeTypes.Cell<Vector2>,
	placed: ComposeTypes.Formula<string>,
	reserve: (string, ComposeTypes.Use?) -> number,
	pad: (string, ComposeTypes.Use?) -> number,
	hugHeight: ComposeTypes.Cell<number?>,
	ready: ComposeTypes.Cell<boolean>,
	painted: (ComposeTypes.Use?) -> number,
	canDismiss: (ComposeTypes.Use?) -> boolean,
	close: (string) -> (),
	interactive: (string) -> (),
	lowest: (ComposeTypes.Use?) -> number,
	standing: (ComposeTypes.Use?) -> number,
	pulled: (ComposeTypes.Use?) -> number,
	toward: () -> number,
	detector: (string, "grip" | "panel") -> Instance,
	tallest: ComposeTypes.Formula<boolean>,
	grabber: TextButton,
	handle: TextButton,
}

local HANDLE = 20
local HELD_PULL = 0.2

return function(
	ctx: Types.Context,
	UI: ControlTypes.BuilderControls,
	surfaces: Nav.Surfaces,
	word: (string) -> string
): (
	NavigationProps.SheetSpec,
	ComposeTypes.Cell<string>,
	Prepared,
	Nav.SheetRequest?,
	Nav.PresencePhase?,
	GuiObject?
) -> Gesture
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local readSource = ctx.readSource
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local frames = runtime.host.frames
	local function now(): number
		return if frames then frames.now() else os.clock()
	end
	return function(
		spec: NavigationProps.SheetSpec,
		detent: ComposeTypes.Cell<string>,
		prepared: Prepared,
		request: Nav.SheetRequest?,
		phase: Nav.PresencePhase?,
		anchor: GuiObject?
	): Gesture
		local detents, byId = prepared.detents, prepared.byId
		local declared = spec.placement or "automatic"
		local edge = spec.edge or "right"
		local gui = surfaces.service("GuiService")
		local input = surfaces.service("UserInputService")
		local preferred: ComposeTypes.Readable<Enum.PreferredInput>? = if input
				and input.GetPropertyChangedSignal
			then ctx.observe.PreferredInput(input)
			else nil
		local reduce = reducedMotion(ctx)
		local level = motion.level(ctx)
		local unit = Compose.cell(1)
		local keyboard: (ComposeTypes.Use) -> number = function()
			return 0
		end
		if input and input.GetPropertyChangedSignal then
			local visible = ctx.observe.OnScreenKeyboardVisible(input)
			local size = ctx.observe.OnScreenKeyboardSize(input)
			keyboard = function(use: ComposeTypes.Use): number
				return if use(visible) == true then use(size).Y / use(unit) else 0
			end
		end
		local layer = if anchor then surfaces.parent(anchor) else ctx.config.overlayParent
		local initial = if layer and layer:IsA("GuiBase2d") then (layer :: GuiBase2d).AbsoluteSize else V2.zero
		local extent = Compose.cell(if initial.Y > 0 then initial else V2.new(0, 720))
		local pointer: (ComposeTypes.Use) -> boolean = function()
			return false
		end
		if declared == "adaptive" and input and input.GetPropertyChangedSignal then
			local mouse, touch = ctx.observe.MouseEnabled(input), ctx.observe.TouchEnabled(input)
			pointer = function(use: ComposeTypes.Use): boolean
				return use(mouse) == true and use(touch) ~= true
			end
		end
		local tenFoot = ctx.tenFoot()
		local placed = Compose.formula(function(use: ComposeTypes.Use): string
			if (declared == "automatic" or declared == "adaptive") and tenFoot(use) then
				return "center"
			end
			if declared == "adaptive" then
				return if use(extent).X >= 600 and pointer(use) then "side" else "bottom"
			end
			return if declared == "automatic" then "bottom" else declared
		end)
		local function from(use: ComposeTypes.Use?): string
			return if read(placed, use) == "side" then edge else "bottom"
		end
		local indicator = spec.dragIndicator or "automatic"
		local BASE: { [string]: number } = { top = 12, bottom = 12, left = 16, right = 16 }
		local RESERVED: { [string]: string } = { bottom = "top", right = "left", left = "right" }
		local function reserve(side: string, use: ComposeTypes.Use?): number
			return BASE[side] + (if indicator ~= "hidden" and RESERVED[from(use)] == side then HANDLE + 8 else 0)
		end
		local function pad(side: string, use: ComposeTypes.Use?): number
			return surfaces.inset(0, side, nil, use) + reserve(side, use)
		end
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
		local lastValid = if byId[detent:peek()] then detent:peek() else detents[1].id
		local function selected(use: ComposeTypes.Use?): Detent
			local id = readSource(detent, use)
			local found = byId[id]
			if found then
				lastValid = id
				return found
			end
			return byId[lastValid]
		end
		local dragHeight: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local ready = Compose.cell(frames == nil)
		local settleTo = settle(ctx, function(): number
			return heightOf(selected())
		end, ctx.motionSpring("sheet"))
		local halt, launch = settleTo.halt, settleTo.launch
		local function painted(use: ComposeTypes.Use?): number
			local drag = readSource(dragHeight, use)
			if drag then
				return drag
			end
			if reduce(use) then
				return heightOf(selected(use), use)
			end
			local settling = readSource(settleTo.value, use)
			if settling then
				return math.min(available(use), math.max(minimum(use), settling))
			end
			return heightOf(selected(use), use)
		end
		local shownHeight = heightOf(selected())
		Compose.watch(function(use: ComposeTypes.Use)
			local drag = use(dragHeight)
			local goal = heightOf(selected(use), use)
			if drag then
				shownHeight = drag
				return
			end
			if use(ready) and settleTo.value:peek() == nil and math.abs(goal - shownHeight) > 0.5 then
				launch(shownHeight, 0)
			end
			shownHeight = goal
		end)
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
			detent:set(id)
		end
		local function nextUp(use: ComposeTypes.Use?): Detent?
			local sorted = ordered()
			local index = table.find(sorted, selected(use)) or 1
			return sorted[index + 1]
		end
		local dragged = -math.huge
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
				moved = false,
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
			if source == "grip" and math.abs(y - current.origin) > 4 then
				dragged = now()
				current.moved = true
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
		local function velocity(samples: { { height: number, at: number } }): number
			local count = #samples
			if count < 2 then
				return 0
			end
			local last = samples[count]
			local first = last
			for index = count - 1, 1, -1 do
				if last.at - samples[index].at > 0.1 then
					break
				end
				first = samples[index]
			end
			local span = last.at - first.at
			if span < 1 / 240 or now() - last.at > 0.1 then
				return 0
			end
			return (last.height - first.height) / span
		end
		local function tapped()
			local grow = if canDismiss() then nil else nextUp()
			if grow then
				select(grow.id)
			else
				interactive("close")
			end
		end
		local function finish(source: "grip" | "panel")
			local current = session
			if current == nil or current.source ~= source then
				return
			end
			if source == "grip" and not current.moved then
				endSession()
				dragged = now()
				tapped()
				return
			end
			if not current.acquired then
				endSession()
				return
			end
			local height = dragHeight:peek() or current.start
			local speed = velocity(current.samples)
			local choice = release.choose(stops(), height, speed, selected().id, canDismiss())
			if choice == "dismiss" then
				session = nil
				if request == nil then
					spec.isPresented:set(false)
				elseif not request("drag") then
					select(selected().id)
				end
				return
			end
			launch(
				height,
				speed,
				if math.abs(speed) > ctx.metric("motion.fling.bounceSpeed") then ctx.motionSpring("flick") else nil
			)
			endSession()
			select(choice)
		end
		if phase then
			Compose.watch(function(use: ComposeTypes.Use)
				if not use(phase.exiting) and session == nil then
					dragHeight:set(nil)
				end
			end)
		end
		local function lowest(use: ComposeTypes.Use?): number
			local out = math.huge
			for _, d in detents do
				out = math.min(out, heightOf(d, use))
			end
			return out
		end
		local function standing(use: ComposeTypes.Use?): number
			return math.max(painted(use), lowest(use))
		end
		local watchedDetent = detent:peek()
		Compose.watch(function(use: ComposeTypes.Use)
			local id = use(detent)
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
		local pull = Compose.cell(0)
		local pulling: { origin: number, moved: boolean, samples: { { height: number, at: number } } }? = nil
		local held = Compose.cell(false)
		local pullBack = settle(ctx, function(): number
			return 0
		end, ctx.motionSpring("sheet"))
		local function pulled(use: ComposeTypes.Use?): number
			if read(held, use) then
				return readSource(pull, use)
			end
			return readSource(pullBack.value, use) or readSource(pull, use)
		end
		local function toward(): number
			return if edge == "left" then -1 else 1
		end
		local function pullTo(x: number)
			local current = pulling
			if current == nil then
				return
			end
			if math.abs(x - current.origin) > 4 then
				dragged = now()
				current.moved = true
			end
			local amount = math.max(0, (x - current.origin) * toward())
			pull:set(if canDismiss() then amount else amount * HELD_PULL)
			table.insert(current.samples, { height = pull:peek(), at = now() })
		end
		local function release()
			local current = pulling
			pulling = nil
			if current == nil then
				return
			end
			held:set(false)
			if not current.moved then
				pullBack.launch(pull:peek(), 0)
				pull:set(0)
				dragged = now()
				tapped()
				return
			end
			local amount = pull:peek()
			local speed = velocity(current.samples)
			local width = math.min(parts.width(ctx, spec.width), extent:peek().X)
			if canDismiss() and (amount > width / 3 or speed > 600) then
				if request == nil then
					spec.isPresented:set(false)
					return
				elseif request("drag") then
					return
				end
			end
			pullBack.launch(amount, speed)
			pull:set(0)
		end
		Compose.cleanup(function()
			pulling = nil
		end)
		local function detector(name: string, source: "grip" | "panel"): Instance
			local function sideways(): boolean
				return source == "grip" and from() ~= "bottom"
			end
			return Host.UIDragDetector({
				Name = name,
				CursorIcon = function(use: ComposeTypes.Use): string
					if source == "panel" then
						return ""
					end
					return if from(use) == "bottom"
						then "rbxasset://SystemCursors/SizeNS"
						else "rbxasset://SystemCursors/SizeEW"
				end,
				ActivatedCursorIcon = function(): string
					return if source == "grip" then "rbxasset://SystemCursors/ClosedHand" else ""
				end,
				DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
				DragAxis = function(use: ComposeTypes.Use)
					return if source == "grip" and from(use) ~= "bottom" then V2.new(1, 0) else V2.new(0, 1)
				end,
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				Enabled = if source == "panel" and preferred
					then function(use: ComposeTypes.Use): boolean
						return use(preferred) ~= E.PreferredInput.Gamepad
					end
					else nil,
				DragStart = function(position: Vector2)
					if sideways() then
						if pulling == nil then
							local from = pulled()
							pullBack.halt()
							local finger = if canDismiss() then from else from / HELD_PULL
							pulling = { origin = position.X - finger * toward(), moved = false, samples = {} }
							pull:set(from)
							held:set(true)
						end
					else
						grab(source, position.Y)
					end
				end,
				DragContinue = function(position: Vector2)
					if sideways() then
						pullTo(position.X)
					else
						move(source, position.Y)
					end
				end,
				DragEnd = function()
					if sideways() then
						release()
					else
						finish(source)
					end
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
		local grabber = Host.TextButton "Grabber" {
			SelectionOrder = -2,
			Attributes = { FacetFocusPart = "Pill" } :: Types.Attributes,
			AnchorPoint = V2.new(0.5, 0.5),
			Position = function(use: ComposeTypes.Use): UDim2
				local side = from(use)
				local offset = surfaces.inset(0, RESERVED[side], nil, use) + HANDLE / 2
				return if side == "bottom"
					then D2.new(0.5, 0, 0, offset)
					elseif side == "left" then D2.new(1, -offset, 0.5, 0)
					else D2.new(0, offset, 0.5, 0)
			end,
			Visible = indicator ~= "hidden",
			Size = function(use: ComposeTypes.Use)
				return if from(use) == "bottom" then D2.fromOffset(88, 44) else D2.fromOffset(44, 88)
			end,
			BackgroundTransparency = 1,
			ZIndex = 2,
			Text = "",
			AutoButtonColor = false,
			Selectable = function(use: ComposeTypes.Use)
				return #detents > 1 or canDismiss(use)
			end,
			Activated = function(input: InputObject?)
				if now() - dragged < 0.3 then
					return
				end
				if
					input ~= nil
					and (
						input.UserInputType == E.UserInputType.Touch
						or input.UserInputType == E.UserInputType.MouseButton1
					)
				then
					tapped()
					return
				end
				local grow = nextUp()
				if grow then
					select(grow.id)
				else
					interactive("close")
				end
			end,
			detector("UIDragDetector", "grip"),
			ctx.styled(
				Host.Frame "Pill" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = function(use: ComposeTypes.Use)
						return if from(use) == "bottom" then D2.fromOffset(36, 5) else D2.fromOffset(5, 36)
					end,
					BorderSizePixel = 0,
					Host.UICorner({ CornerRadius = ctx.round }),
				},
				"grabber"
			) :: Types.Child,
		}

		if gui and gui.GetPropertyChangedSignal and preferred then
			local selection = ctx.observe.SelectedObject(gui)
			local pad = preferred
			runtime.decorate(assert(grabber:FindFirstChildWhichIsA("UIDragDetector")), {
				Enabled = function(use: ComposeTypes.Use): boolean
					return not (use(pad) == E.PreferredInput.Gamepad and use(selection) == grabber)
				end,
			})
		end
		local function stepTo(direction: number, use: ComposeTypes.Use?): Detent?
			local sorted = ordered()
			return sorted[(table.find(sorted, selected(use)) or 1) + direction]
		end
		UI.adjustable(grabber, {
			axis = "horizontal",
			onAdjust = function(direction: number)
				local target = stepTo(direction)
				if target then
					select(target.id)
				end
			end,
			canAdjust = function(direction: number, use: ComposeTypes.Use?): boolean
				return stepTo(direction, use) ~= nil
			end,
		})
		Compose.watch(function(use: ComposeTypes.Use)
			grabber:SetAttribute(
				"AccessibleLabel",
				if nextUp(use) then "Resize: " .. word(selected(use).id) else "Close sheet"
			)
		end)
		return {
			edge = edge,
			level = level,
			unit = unit,
			keyboard = keyboard,
			extent = extent,
			placed = placed,
			reserve = reserve,
			pad = pad,
			hugHeight = hugHeight,
			ready = ready,
			painted = painted,
			canDismiss = canDismiss,
			close = close,
			interactive = interactive,
			lowest = lowest,
			standing = standing,
			pulled = pulled,
			toward = toward,
			detector = detector,
			tallest = tallest,
			grabber = grabber,
			handle = grabber,
		}
	end
end
