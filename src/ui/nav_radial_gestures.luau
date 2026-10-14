--!strict
local geometry = require("./nav_radial_geometry")
local Types = require("./types")
local Radial = require("./radial_types")
local Navigation = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local MenuTypes = require("./nav_radial_menu")
local ArrangementTypes = require("./nav_radial_layout")
local PaintTypes = require("./nav_radial_sectors")
local HubTypes = require("./nav_radial_center")

type NavigationHold = { count: number, saved: boolean, changed: boolean, watch: RBXScriptConnection? }
local navigationHolds = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: NavigationHold }
local function holdNavigation(gui: GuiService): () -> ()
	local hold = navigationHolds[gui]
	if hold == nil then
		local created: NavigationHold = { count = 0, saved = gui.GuiNavigationEnabled, changed = false }
		gui.GuiNavigationEnabled = false
		created.watch = gui:GetPropertyChangedSignal("GuiNavigationEnabled"):Connect(function()
			if gui.GuiNavigationEnabled then
				created.changed = true
			end
		end)
		navigationHolds[gui] = created
		hold = created
	end
	local held = hold :: NavigationHold
	held.count += 1
	local released = false
	return function()
		if released then
			return
		end
		released = true
		held.count -= 1
		if held.count == 0 then
			navigationHolds[gui] = nil
			if held.watch then
				held.watch:Disconnect()
			end
			if not held.changed and gui.GuiNavigationEnabled == false then
				gui.GuiNavigationEnabled = held.saved
			end
		end
	end
end

return function<V>(
	ctx: Types.Context,
	surfaces: Navigation.Surfaces,
	menu: MenuTypes.Menu<V>,
	arrangement: ArrangementTypes.Arrangement<V>,
	paint: PaintTypes.Paint<V>,
	hub: HubTypes.Hub<V>
)
	local Compose, runtime, read = ctx.Compose, ctx.runtime, ctx.read
	local E, V2 = ctx.types.Enum, ctx.types.Vector2
	local spec, session, appearance, gestureSelection = menu.spec, menu.session, menu.appearance, menu.gestureSelection
	local opened, path, candidate, interacting = menu.opened, menu.path, menu.candidate, menu.interacting
	local naming, touchPoint, holding = menu.naming, menu.touchPoint, menu.holding
	local jump, cancel, close, nativeActivate, beginPointer =
		menu.jump, menu.cancel, menu.close, menu.nativeActivate, menu.beginPointer
	local origin, center, layout, sectors, fallback =
		arrangement.origin, arrangement.center, arrangement.layout, arrangement.sectors, arrangement.fallback
	local buttons, focus, gui, panel = paint.buttons, paint.focus, paint.gui, paint.panel
	local showCenter, centerNode, reachOf = hub.showCenter, hub.centerNode, hub.reachOf
	local function choose(sector: Radial.Sector<V>?): Radial.Sector<V>?
		if sector and read(sector.item.enabled) == false then
			sector = nil
		end
		candidate:set(if sector then sector.key else nil)
		return sector
	end
	local function beyond(position: Vector3): boolean
		local ring = layout:peek()
		local at = center:peek() + origin:peek()
		return not ring.list and V2.new(position.X - at.X, position.Y - at.Y).Magnitude > reachOf(ring)
	end
	session.aimPointer = function(
		position: Vector3,
		dragging: boolean?,
		beginning: boolean?
	): (Radial.Sector<V> | false)?
		if fallback:peek() then
			return false
		end
		local at = center:peek() + origin:peek()
		local x, y = position.X - at.X, position.Y - at.Y
		local magnitude = math.sqrt(x * x + y * y)
		if
			beginning
			and spec.centerPassThrough
			and (spec.center == "empty" or spec.center == "content")
			and magnitude < layout:peek().inner
		then
			return false
		end
		if dragging and gestureSelection == "direction" then
			if magnitude < 26 then
				return choose(nil)
			end
			local entries = sectors:peek()
			local last = entries[#entries]
			if not last then
				return choose(nil)
			end
			local radius = (last.inner + last.outer) / 2
			x, y = x / magnitude * radius, y / magnitude * radius
		end
		return choose(
			geometry.hit(
				sectors:peek(),
				x,
				y,
				appearance,
				if dragging then 44 else nil,
				assert(session.candidateSector)()
			)
		)
	end
	session.aimAnalog = function(value: Vector2)
		if session.capture or not opened:peek() or not ctx.available(panel) then
			return
		end
		local magnitude = value.Magnitude
		if magnitude < 0.25 then
			session.analog = false
			interacting:set(false)
			candidate:set(nil)
			return
		end
		if magnitude < 0.35 and not session.analog then
			return
		end
		local entering = not session.analog
		if entering and session.freezeCenter then
			session.freezeCenter()
		end
		session.analog = true
		interacting:set(true)
		naming:set(true)
		if fallback:peek() then
			if entering then
				candidate:set(focus.move(if value.Y > 0 then "up" else "down"))
			end
		else
			local entries = sectors:peek()
			local last = entries[#entries]
			if not last then
				return
			end
			local radius = (last.inner + last.outer) / 2
			choose(
				geometry.hit(
					entries,
					value.X / magnitude * radius,
					-value.Y / magnitude * radius,
					"wedges",
					0,
					assert(session.candidateSector)()
				)
			)
		end
		local key = candidate:peek()
		if gui and key and buttons[key] then
			gui.SelectedObject = buttons[key]
		end
	end
	runtime.connect(panel, "InputBegan", function(input: InputObject)
		beginPointer(input, true)
	end)
	local inputService = surfaces.service("UserInputService")
	runtime.connect(inputService or panel, "InputChanged", function(input: InputObject)
		if
			session.capture
			and (
				input == session.capture
				or (
					session.capture.UserInputType == E.UserInputType.MouseButton1
					and input.UserInputType == E.UserInputType.MouseMovement
				)
			)
		then
			if input.UserInputState == E.UserInputState.Cancel then
				cancel()
			else
				if
					session.launcherGesture
					and not naming:peek()
					and session.heldAt
					and (input.Position - session.heldAt).Magnitude < 14
				then
					return
				end
				if session.capture.UserInputType == E.UserInputType.Touch then
					touchPoint:set(input.Position)
				end
				if session.heldAt and (input.Position - session.heldAt).Magnitude > 14 then
					holding:pause()
					if session.inspectedUntil == math.huge then
						session.inspectedUntil = nil
					end
				end
				naming:set(true)
				assert(session.aimPointer)(input.Position, true)
			end
		end
	end)
	runtime.connect(inputService or panel, "InputEnded", function(input: InputObject)
		if
			session.capture
			and (
				input == session.capture
				or (
					session.capture.UserInputType == E.UserInputType.MouseButton1
					and input.UserInputType == E.UserInputType.MouseButton1
				)
			)
		then
			if input.UserInputState == E.UserInputState.Cancel then
				cancel()
				return
			end
			local still = session.pressedAt and (input.Position - session.pressedAt).Magnitude < 8
			local outside = still and beyond(session.pressedAt :: Vector3) and beyond(input.Position)
			local launcherTap = session.launcherGesture
				and session.heldAt
				and (input.Position - session.heldAt).Magnitude < 14
			local sector = if outside or launcherTap then nil else assert(session.aimPointer)(input.Position, true)
			cancel()
			if outside then
				close()
			elseif type(sector) == "table" then
				nativeActivate(sector, input, "gesture")
			end
		end
	end)
	session.returnSelection = function(change: () -> (), key: string?)
		local held = gui ~= nil and surfaces.within(gui.SelectedObject, panel)
		change()
		local button = buttons[key or (if held then focus.first() else nil) or ""]
		if held and gui and button and button.Parent then
			gui.SelectedObject = button
		end
	end
	Compose.cleanup(function()
		cancel()
		session.aimPointer, session.aimAnalog, session.candidateSector, session.freezeCenter, session.returnSelection =
			nil, nil, nil, nil, nil
	end)

	if gui then
		local release: (() -> ())? = nil
		local function let()
			if release then
				release()
				release = nil
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if use(opened) and release == nil then
				release = holdNavigation(gui)
			elseif not use(opened) then
				let()
			end
		end)
		Compose.cleanup(let)
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local entries = use(sectors)
		local validPath = use(layout).path
		if #validPath < #path:peek() then
			jump(validPath)
		end
		local wanted, found = candidate:peek(), false
		for _, sector in entries do
			if sector.key == wanted and read(sector.item.enabled, use) ~= false then
				found = true
			end
		end
		if wanted and not found then
			candidate:set(nil)
		end
	end)
	if ctx.action then
		ctx.action(
			panel,
			"RadialAim",
			{ "Thumbstick1" },
			opened,
			function() end,
			{ priority = 2200, group = "Radial", direction2D = session.aimAnalog }
		)
		ctx.action(panel, "RadialCommit", { "ButtonA", "Return" }, function(use: ComposeTypes.Use)
			return use(opened) and use(candidate) ~= nil
		end, function()
			local selected = assert(session.candidateSector)()
			nativeActivate(selected, nil, "action")
		end, { priority = 2200, group = "Radial" })
		local directionalKeys: { [ComposeTypes.FocusDirection]: { Types.ActionBinding } } = {
			left = { "Left", "DPadLeft" },
			right = { "Right", "DPadRight" },
			up = { "Up", "DPadUp" },
			down = { "Down", "DPadDown" },
		}
		local toward: { [string]: Vector2 } = {
			left = V2.new(-1, 0),
			right = V2.new(1, 0),
			up = V2.new(0, -1),
			down = V2.new(0, 1),
		}
		local function ringStep(direction: string): (string?, boolean)
			local d = toward[direction]
			local entries = {}
			for _, sector in sectors:peek() do
				if read(sector.item.enabled) ~= false then
					table.insert(entries, sector)
				end
			end
			local function aligned(v: Vector2): number
				return if v.Magnitude > 0 then v.Unit:Dot(d) else -1
			end
			local current: Radial.Sector<V>? = nil
			for _, sector in entries do
				if sector.key == candidate:peek() then
					current = sector
				end
			end
			if current == nil then
				local best, bestKey = 0, nil
				for _, sector in entries do
					local score = aligned(V2.new(sector.x, sector.y))
					if score > best then
						best, bestKey = score, sector.key
					end
				end
				return bestKey, false
			end
			local here = V2.new(current.x, current.y)
			if read(showCenter) and aligned(-here) >= math.cos(math.rad(45)) then
				return nil, true
			end
			table.sort(entries, function(a, b)
				return math.atan2(a.x, -a.y) < math.atan2(b.x, -b.y)
			end)
			local at = table.find(entries, current) :: number
			local best, bestKey = 0, nil
			for _, step in { -1, 1 } do
				local neighbour = entries[(at - 1 + step) % #entries + 1]
				if neighbour ~= current then
					local score = aligned(V2.new(neighbour.x, neighbour.y) - here)
					if score > best then
						best, bestKey = score, neighbour.key
					end
				end
			end
			return bestKey, false
		end
		for direction, keys in directionalKeys do
			ctx.action(panel, "Radial-" .. direction, keys, opened, function()
				session.analog = false
				interacting:set(false)
				if fallback:peek() then
					local key = focus.move(direction :: ComposeTypes.FocusDirection)
					candidate:set(key)
					naming:set(true)
					if gui and key and buttons[key] then
						gui.SelectedObject = buttons[key]
					end
					return
				end
				local key, centre = ringStep(direction)
				if centre then
					candidate:set(nil)
					if gui then
						gui.SelectedObject = centerNode
					end
					return
				end
				if key == nil then
					return
				end
				candidate:set(key)
				naming:set(true)
				if gui and buttons[key] then
					gui.SelectedObject = buttons[key]
				end
			end, { priority = 2200, capture = true, group = "Radial" })
		end
	end
end
