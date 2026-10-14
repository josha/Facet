--!strict
local reducedMotion = require("./motion").reduced
local geometry = require("./nav_radial_geometry")
local adaptive = require("./adaptive")
local Types = require("./types")
local Radial = require("./radial_types")
local Navigation = require("./navigation_types")
local InputProps = require("./input_props")
local RadialProps = require("./radial_props")
local ComposeTypes = require("../vendor/compose/core")

local HOLD = 0.4

export type Controls = { Button: Types.Constructor<InputProps.ButtonProps, TextButton> }
export type Session<V> = {
	branchOrigin: { path: string, shape: Radial.SectorShape }?,
	capture: InputObject?,
	pressedAt: Vector3?,
	heldAt: Vector3?,
	inspectedUntil: number?,
	analog: boolean,
	held: boolean,
	suppressedInput: InputObject?,
	suppressedUntil: number?,
	suppressedKey: string?,
	suppressedSource: string?,
	openedByLauncher: boolean,
	launcherGesture: boolean,
	aimPointer: ((Vector3, boolean?, boolean?) -> Radial.Sector<V>? | false)?,
	aimAnalog: ((Vector2) -> ())?,
	candidateSector: (() -> Radial.Sector<V>?)?,
	freezeCenter: (() -> ())?,
	returnSelection: ((() -> (), string?) -> ())?,
}
export type Menu<V> = {
	spec: RadialProps.RadialMenuSpec<V>,
	session: Session<V>,
	preferred: ComposeTypes.Cell<Enum.PreferredInput>?,
	painted: (use: ComposeTypes.Use?) -> number,
	appearance: string,
	glyphOnly: (item: Radial.RadialItemBase<V>) -> boolean,
	follow: string,
	gestureSelection: string,
	contentFit: Radial.ContentFit,
	scrim: string,
	corner: boolean,
	ringWidth: (use: ComposeTypes.Use?) -> number?,
	reduced: (use: ComposeTypes.Use?) -> boolean,
	opened: ComposeTypes.Cell<boolean>,
	path: ComposeTypes.Cell<{ string }>,
	candidate: ComposeTypes.Cell<string?>,
	interacting: ComposeTypes.Cell<boolean>,
	naming: ComposeTypes.Cell<boolean>,
	touchPoint: ComposeTypes.Cell<Vector3?>,
	holding: Types.Playback,
	jump: (entries: { string }) -> (),
	cancel: () -> (),
	close: () -> (),
	open: () -> (),
	back: () -> (),
	nativeActivate: (sector: Radial.Sector<V>?, input: InputObject?, source: string?) -> (),
	pointing: () -> boolean,
	isPointer: (input: InputObject) -> boolean,
	beginPointer: (input: InputObject, onPanel: boolean?, fromLauncher: boolean?) -> (),
	skin: (node: GuiObject, definition: Radial.SkinImages?, selected: Types.Value<boolean>?) -> (),
}

return function<V>(ctx: Types.Context, surfaces: Navigation.Surfaces, spec: RadialProps.RadialMenuSpec<V>): Menu<V>
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2 = ctx.types.Enum, ctx.types.UDim2
	local input = surfaces.service("UserInputService")
	local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
	local distant = ctx.tenFoot()
	local function painted(use: ComposeTypes.Use?): number
		return if distant(use) then 32 * adaptive.TEN_FOOT_SCALE else 32
	end
	local function choice<T>(value: T?, fallback: T, choices: { T }, name: string): T
		local selected = if value == nil then fallback else value
		assert(table.find(choices, selected), "RadialMenu invalid " .. name)
		return selected
	end
	local appearance = choice(spec.appearance, "wedges", { "wedges", "buttons" }, "appearance")
	local function glyphOnly(item: Radial.RadialItemBase<V>): boolean
		local icon = item.icon ~= nil or (item.compactLabel ~= nil and item.compactLabel.icon ~= nil)
		return icon
			and (
				item.labelStyle == "icon"
				or (item.compactLabel ~= nil and item.compactLabel.prefer == true)
				or appearance == "buttons"
			)
	end
	local follow = choice(spec.follow, "idle", { "idle", "always", "fixed" }, "follow")
	local gestureSelection = choice(spec.gestureSelection, "bounded", { "bounded", "direction" }, "gestureSelection")
	local contentFit: Radial.ContentFit = spec.contentFit or "radial"
	choice(contentFit, "radial", { "both", "radial", "angular", "none" }, "contentFit")
	choice(spec.navigation, "replace", { "replace", "expand" }, "navigation")
	choice(spec.expansion, "fan", { "fan", "ring" }, "expansion")
	choice(spec.center, "back", { "back", "root", "close", "content", "empty" }, "center")
	choice(spec.completion, "close", { "close", "back", "root", "stay" }, "completion")
	choice(spec.buttonSurface, "native", { "native", "none" }, "buttonSurface")
	local scrim = choice(spec.scrim, "none", { "dark", "light", "none" }, "scrim")
	local _, presetSweep = geometry.arc(spec.preset or "donut")
	local corner = presetSweep < 360
	local function ringWidth(use: ComposeTypes.Use?): number?
		local width = read(spec.ringWidth, use)
		if width == nil or type(width) == "number" then
			return width
		end
		assert(
			width == "narrow" or width == "regular" or width == "wide",
			"RadialMenu ringWidth must be a number of pixels or narrow, regular or wide"
		)
		return ctx.metric("controls.radial." .. width, use)
	end
	local motionReduced = reducedMotion(ctx)
	local function reduced(use: ComposeTypes.Use?): boolean
		return spec.transition == false or motionReduced(use)
	end
	local function validate(
		items: { Radial.RadialItem<V> },
		use: ComposeTypes.Use,
		ancestors: { [{ Radial.RadialItem<V> }]: boolean }
	)
		assert(type(items) == "table" and not ancestors[items], "RadialMenu requires an acyclic item tree")
		ancestors[items] = true
		local ids: { [string]: boolean } = {}
		for _, item in items do
			assert(
				type(item.id) == "string" and item.id ~= "$navigation" and not ids[item.id],
				"RadialMenu requires unique nonreserved item ids"
			)
			ids[item.id] = true
			choice(item.completion, "close", { "stay", "back", "root", "close" }, "item completion")
			choice(item.navigation, "replace", { "replace", "expand" }, "item navigation")
			choice(item.expansion, "fan", { "fan", "ring" }, "item expansion")
			assert(not (item.children and item.onSelect), "RadialMenu items use children or onSelect")
			if item.children then
				validate(read(item.children, use), use, ancestors)
			end
		end
		ancestors[items] = nil
	end
	Compose.watch(function(use: ComposeTypes.Use)
		validate(read(spec.items, use), use, {})
	end)
	local opened: ComposeTypes.Cell<boolean> = spec.isPresented or Compose.cell(spec.launcher == false)
	local path: ComposeTypes.Cell<{ string }> = Compose.cell({})
	local candidate: ComposeTypes.Cell<string?> = Compose.cell(nil :: string?)
	local session: Session<V> = { analog = false, held = false, openedByLauncher = false, launcherGesture = false }
	local origins: { [string]: Radial.SectorShape } = {}
	local function jump(entries: { string })
		session.branchOrigin = nil
		path:set(entries)
	end
	Compose.watch(function(use: ComposeTypes.Use)
		if not use(opened) then
			session.branchOrigin = nil
		end
	end)
	local interacting = Compose.cell(false)
	local naming = Compose.cell(false)
	local touchPoint: ComposeTypes.Cell<Vector3?> = Compose.cell(nil :: Vector3?)
	local holding = runtime.timeline({ duration = HOLD, autoplay = false })
	local function cancel()
		if session.inspectedUntil == math.huge then
			session.inspectedUntil = os.clock() + 0.3
		end
		session.capture, session.analog, session.launcherGesture = nil, false, false
		interacting:set(false)
		naming:set(false)
		touchPoint:set(nil)
		holding:pause()
		candidate:set(nil)
	end
	Compose.watch(function(use: ComposeTypes.Use)
		if
			use(holding.completed)
			and session.capture
			and not session.launcherGesture
			and session.capture.UserInputType == E.UserInputType.Touch
		then
			naming:set(true)
			session.inspectedUntil = math.huge
		end
	end)
	local function close()
		if not opened:peek() then
			return
		end
		opened:set(false)
		jump({})
		cancel()
		if spec.onClose then
			spec.onClose()
		end
	end
	local function open()
		if read(spec.enabled) == false or opened:peek() then
			return
		end
		local anchor = read(spec.anchor)
		if type(anchor) == "table" and anchor.visible == false then
			return
		end
		opened:set(true)
		if spec.onOpen then
			spec.onOpen()
		end
	end
	local function back()
		cancel()
		local entries = table.clone(path:peek())
		if #entries == 0 then
			close()
		else
			local leaving = table.concat(path:peek(), "/")
			local popped = table.remove(entries)
			local shape = origins[leaving]
			session.branchOrigin = if shape then { path = table.concat(entries, "/"), shape = shape } else nil
			local function change()
				path:set(entries)
				candidate:set(nil)
			end
			if session.returnSelection then
				session.returnSelection(change, table.concat(entries, "/") .. "/" .. tostring(popped))
			else
				change()
			end
		end
	end
	local function activate(sector: Radial.Sector<V>?)
		if not sector or not opened:peek() then
			return
		end
		local item = sector.item
		if read(spec.enabled) == false or read(item.enabled) == false or read(item.hidden) == true then
			return
		end
		cancel()
		if item.id == "$navigation" then
			back()
			return
		end
		if item.children then
			local entries = table.clone(sector.path)
			table.insert(entries, item.id)
			local key = table.concat(entries, "/")
			session.branchOrigin = { path = key, shape = sector :: Radial.SectorShape }
			origins[key] = sector :: Radial.SectorShape
			local function change()
				path:set(entries)
				candidate:set(nil)
			end
			if session.returnSelection then
				session.returnSelection(change)
			else
				change()
			end
			return
		end
		local state = item.checked or item.selected
		local completion = item.completion
			or (if item.dismiss == false then "stay" elseif item.dismiss == true then "close" else spec.completion)
			or (if state then "stay" else "close")
		if completion == "close" then
			close()
		elseif completion == "root" then
			jump({})
		elseif completion == "back" then
			back()
		end
		if item.checked then
			local value = not item.checked:peek()
			item.checked:set(value)
			if item.onChange then
				item.onChange(value)
			end
		elseif item.selected then
			if item.selected:peek() ~= item.value then
				item.selected:set(item.value)
				if item.onChange then
					item.onChange(item.value)
				end
			end
		else
			local select: (() -> ())? = item.onSelect
			if select then
				select()
			end
		end
	end
	local function nativeActivate(sector: Radial.Sector<V>?, input: InputObject?, source: string?)
		if not sector then
			return
		end
		source = source or "native"
		if
			session.inspectedUntil
			and os.clock() < session.inspectedUntil
			and input
			and input.UserInputType == E.UserInputType.Touch
		then
			return
		end
		if
			session.suppressedUntil
			and os.clock() < session.suppressedUntil
			and session.suppressedKey == sector.key
			and session.suppressedSource ~= source
			and (input == nil or session.suppressedInput == nil or input == session.suppressedInput)
		then
			return
		end
		session.suppressedInput, session.suppressedUntil, session.suppressedKey, session.suppressedSource =
			input, os.clock() + 0.3, sector.key, source
		activate(sector)
	end
	local function pointing(): boolean
		local input = surfaces.service("UserInputService") :: UserInputService?
		return touchPoint:peek() == nil
			and (preferred == nil or preferred:peek() ~= E.PreferredInput.Touch)
			and input ~= nil
			and type(input.GetLastInputType) == "function"
			and input:GetLastInputType() == E.UserInputType.MouseMovement
	end
	local function isPointer(input: InputObject): boolean
		return input.UserInputType == E.UserInputType.MouseButton1 or input.UserInputType == E.UserInputType.Touch
	end
	local function beginPointer(input: InputObject, onPanel: boolean?, fromLauncher: boolean?)
		if not session.capture and opened:peek() and isPointer(input) and session.aimPointer then
			session.suppressedInput, session.suppressedUntil, session.inspectedUntil = nil, nil, nil
			if not fromLauncher and session.aimPointer(input.Position, false, true) == false then
				return
			end
			session.capture, session.pressedAt, session.heldAt =
				input, if onPanel then input.Position else nil, input.Position
			session.launcherGesture = fromLauncher == true
			if input.UserInputType == E.UserInputType.Touch then
				touchPoint:set(input.Position)
				holding:restart()
			end
			if session.freezeCenter then
				session.freezeCenter()
			end
			interacting:set(true)
		end
	end
	local function skin(node: GuiObject, definition: Radial.SkinImages?, selected: Types.Value<boolean>?)
		if not definition then
			return
		end
		local guiState = ctx.observe.GuiState(node)
		surfaces.attach(node, {
			Host.ImageLabel "RadialSkin" {
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = node.ZIndex - 1,
				Image = function(use: ComposeTypes.Use)
					local state = use(guiState)
					return (
						if state == E.GuiState.Press
							then definition.pressed
							elseif state == E.GuiState.Hover then definition.hover
							elseif selected and read(selected, use) then definition.selected
							else nil
					)
						or definition.default
						or ""
				end,
			},
		})
	end
	return {
		spec = spec,
		session = session,
		preferred = preferred,
		painted = painted,
		appearance = appearance,
		glyphOnly = glyphOnly,
		follow = follow,
		gestureSelection = gestureSelection,
		contentFit = contentFit,
		scrim = scrim,
		corner = corner,
		ringWidth = ringWidth,
		reduced = reduced,
		opened = opened,
		path = path,
		candidate = candidate,
		interacting = interacting,
		naming = naming,
		touchPoint = touchPoint,
		holding = holding,
		jump = jump,
		cancel = cancel,
		close = close,
		open = open,
		back = back,
		nativeActivate = nativeActivate,
		pointing = pointing,
		isPointer = isPointer,
		beginPointer = beginPointer,
		skin = skin,
	}
end
