--!strict
local layoutKit = require("./layout_kit")
local reducedMotion = require("./motion").reduced
local geometry = require("./nav_radial_geometry")
local adaptive = require("./adaptive")
local Types = require("./types")
local Radial = require("./radial_types")
local Navigation = require("./navigation_types")
local Inputs = require("./input_types")
local ComposeTypes = require("../vendor/compose/core")

type NavigationHold = { count: number, saved: boolean, changed: boolean, watch: RBXScriptConnection? }
local HOLD = 0.4
local navigationHolds: { [Instance]: NavigationHold } = setmetatable({} :: any, { __mode = "k" })
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
return function(
	ctx: Types.Context,
	UI: {
		Button: Types.Constructor<Inputs.ButtonProps, TextButton>,
		RadialMenu: Radial.RadialMenuConstructor,
	},
	surfaces: Navigation.Surfaces
)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local lists = layoutKit.of(ctx)
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local build: Radial.RadialMenuBuilder = function<V>(spec: Radial.RadialMenuSpec<V>): Frame
		assert(spec.items, "RadialMenu requires items")

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
		local gestureSelection =
			choice(spec.gestureSelection, "bounded", { "bounded", "direction" }, "gestureSelection")
		local contentFit: Radial.ContentFit = spec.contentFit or "both"
		choice(contentFit, "both", { "both", "radial", "angular", "none" }, "contentFit")
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
		local branchOrigin: { path: string, shape: Radial.SectorShape }? = nil
		local origins: { [string]: Radial.SectorShape } = {}
		local function jump(entries: { string })
			branchOrigin = nil
			path:set(entries)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if not use(opened) then
				branchOrigin = nil
			end
		end)
		local interacting = Compose.cell(false)
		local naming = Compose.cell(false)
		local holding = runtime.timeline({ duration = HOLD, autoplay = false })
		local capture: InputObject?
		local pressedAt: Vector3?
		local heldAt: Vector3?
		local inspectedUntil: number?
		local analog, held = false, false
		local suppressedInput: InputObject?
		local suppressedUntil: number?
		local suppressedKey: string?
		local suppressedSource: string?
		local openedByLauncher = false
		local aimPointer: ((Vector3, boolean?, boolean?) -> Radial.Sector<V>? | false)?
		local aimAnalog: ((Vector2) -> ())?
		local candidateSector: (() -> Radial.Sector<V>?)?
		local freezeCenter: (() -> ())?
		local returnSelection: ((() -> (), string?) -> ())?
		local function cancel()
			if inspectedUntil == math.huge then
				inspectedUntil = os.clock() + 0.3
			end
			capture, analog = nil, false
			interacting:set(false)
			naming:set(false)
			holding:pause()
			candidate:set(nil)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if use(holding.completed) and capture and capture.UserInputType == E.UserInputType.Touch then
				naming:set(true)
				inspectedUntil = math.huge
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
				branchOrigin = if shape then { path = table.concat(entries, "/"), shape = shape } else nil
				local function change()
					path:set(entries)
					candidate:set(nil)
				end
				if returnSelection then
					returnSelection(change, table.concat(entries, "/") .. "/" .. tostring(popped))
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
				branchOrigin = { path = key, shape = sector :: Radial.SectorShape }
				origins[key] = sector :: Radial.SectorShape
				local function change()
					path:set(entries)
					candidate:set(nil)
				end
				if returnSelection then
					returnSelection(change)
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
			elseif item.onSelect then
				item.onSelect()
			end
		end
		local function nativeActivate(sector: Radial.Sector<V>?, input: InputObject?, source: string?)
			if not sector then
				return
			end
			source = source or "native"
			if
				inspectedUntil
				and os.clock() < inspectedUntil
				and input
				and input.UserInputType == E.UserInputType.Touch
			then
				return
			end
			if
				suppressedUntil
				and os.clock() < suppressedUntil
				and suppressedKey == sector.key
				and suppressedSource ~= source
				and (input == nil or suppressedInput == nil or input == suppressedInput)
			then
				return
			end
			suppressedInput, suppressedUntil, suppressedKey, suppressedSource =
				input, os.clock() + 0.3, sector.key, source
			activate(sector)
		end
		local function pointing(): boolean
			local input = surfaces.service("UserInputService") :: any
			return input ~= nil
				and type(input.GetLastInputType) == "function"
				and input:GetLastInputType() == E.UserInputType.MouseMovement
		end
		local function isPointer(input: InputObject): boolean
			return input.UserInputType == E.UserInputType.MouseButton1 or input.UserInputType == E.UserInputType.Touch
		end
		local function beginPointer(input: InputObject, onPanel: boolean?)
			if not capture and opened:peek() and isPointer(input) and aimPointer then
				suppressedInput, suppressedUntil, inspectedUntil = nil, nil, nil
				if aimPointer(input.Position, false, true) == false then
					return
				end
				capture, pressedAt, heldAt = input, if onPanel then input.Position else nil, input.Position
				if input.UserInputType == E.UserInputType.Touch then
					holding:restart()
				end
				if freezeCenter then
					freezeCenter()
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
		local anchored = read(spec.anchor)
		local anchorGui = if anchored
				and (typeof(anchored) == "Instance" or (type(anchored) == "table" and anchored.IsA))
			then anchored :: GuiObject
			else nil
		local root = Host.Frame(ctx.props(spec, {
			"items",
			"label",
			"launcher",
			"icon",
			"preset",
			"appearance",
			"buttonSurface",
			"distribution",
			"navigation",
			"expansion",
			"center",
			"centerLabel",
			"centerContent",
			"centerPassThrough",
			"completion",
			"anchor",
			"follow",
			"clearance",
			"ringWidth",
			"contentFit",
			"gestureSelection",
			"enabled",
			"holdAction",
			"skin",
			"onOpen",
			"onClose",
			"isPresented",
			"transition",
			"scrim",
		}, {
			Name = "RadialMenu",
			BackgroundTransparency = 1,
			Size = D2.fromOffset(0, 0),
			AutomaticSize = if anchorGui then E.AutomaticSize.None else E.AutomaticSize.XY,
		}))
		local layoutUnit = ctx.layoutUnit(root)
		if spec.launcher ~= false then
			local overAnchor: ((ComposeTypes.Use) -> UDim2)? = nil
			if anchorGui then
				local at, size = ctx.observe.AbsolutePosition(anchorGui), ctx.observe.AbsoluteSize(anchorGui)
				local own = ctx.observe.AbsolutePosition(root)
				overAnchor = function(use: ComposeTypes.Use): UDim2
					local middle = use(at) + use(size) / 2 - use(own)
					return D2.fromOffset(middle.X, middle.Y)
				end
			end
			surfaces.attach(root, {
				UI.Button "Launcher" {
					AnchorPoint = if overAnchor then V2.new(0.5, 0.5) else nil,
					Position = overAnchor,
					label = spec.label or "Quick actions",
					name = spec.label or "Quick actions",
					icon = spec.icon or (if spec.label == nil then "more" else nil),
					shape = if spec.label == nil then "circle" :: "circle" else nil,
					enabled = spec.enabled,
					InputBegan = function(input: InputObject)
						if not opened:peek() and isPointer(input) then
							open()
							openedByLauncher = opened:peek()
							beginPointer(input)
						end
					end,
					onActivate = function(input: InputObject?)
						local echo = openedByLauncher and input ~= nil and isPointer(input)
						openedByLauncher = false
						if echo then
							return
						end
						if opened:peek() then
							close()
						else
							open()
						end
					end,
				},
			})
		end
		surfaces.attach(root, {
			surfaces.overlay(root, opened, function(phase: Navigation.PresencePhase?)
				local layer = ctx.config.overlayParent :: GuiBase2d?
					or root:FindFirstAncestorWhichIsA("LayerCollector") :: GuiBase2d?
				local measured = layer ~= nil and layer.AbsoluteSize.X > 0 and layer.AbsoluteSize.Y > 0
				local viewport = Compose.cell(if measured then (layer :: GuiBase2d).AbsoluteSize else V2.new(640, 480))
				local origin = Compose.cell(if measured then (layer :: GuiBase2d).AbsolutePosition else V2.zero)
				local anchor = read(spec.anchor)
				local launcher = if anchor == nil then root:FindFirstChild("Launcher") else nil
				local focal = anchor or launcher
				local nativeAnchor = focal and (typeof(focal) == "Instance" or (type(focal) == "table" and focal.IsA))
				local anchorPosition = if nativeAnchor then ctx.observe.AbsolutePosition(focal :: GuiObject) else nil
				local anchorSize = if nativeAnchor then ctx.observe.AbsoluteSize(focal :: GuiObject) else nil
				local shelves: { { position: ComposeTypes.Readable<Vector2>, size: ComposeTypes.Readable<Vector2> } } =
					{}
				local shelf = if nativeAnchor and not corner then (focal :: Instance).Parent else nil
				while shelf and shelf ~= layer and shelf:IsA("GuiObject") do
					table.insert(shelves, {
						position = ctx.observe.AbsolutePosition(shelf :: GuiObject),
						size = ctx.observe.AbsoluteSize(shelf :: GuiObject),
					})
					shelf = shelf.Parent
				end
				local rawInner = Compose.formula(function(use: ComposeTypes.Use): number
					local inner = math.max(
						24,
						if type(read(spec.clearance, use)) == "number" then read(spec.clearance, use) else 40
					)
					local focal = read(spec.anchor, use)
					if type(focal) == "table" and type(focal.clearance) == "number" then
						inner = math.max(inner, focal.clearance)
					end
					if anchorSize then
						local extent = use(anchorSize)
						inner = math.max(inner, math.max(extent.X, extent.Y) / 2)
					end
					return inner
				end)
				local rawCenter = Compose.formula(function(use: ComposeTypes.Use)
					local size = use(viewport)
					local live = read(spec.anchor, use)
					local preset = spec.preset or "donut"
					local at = V2.new(
						if string.find(preset, "left")
							then 16
							elseif string.find(preset, "right") then size.X - 16
							else size.X / 2,
						if string.find(preset, "top")
							then 16
							elseif string.find(preset, "bottom") then size.Y - 16
							else size.Y / 2
					)
					if anchorPosition and anchorSize and (launcher == nil or use(anchorSize).X > 0) then
						at = use(anchorPosition) + use(anchorSize) / 2 - use(origin)
					elseif live and live.x and live.y then
						at = V2.new(live.x, live.y) - use(origin)
					end
					local _, sweep = geometry.arc(preset)
					if sweep < 360 then
						return at
					end
					local reach = use(rawInner) + (ringWidth(use) or 44)
					return V2.new(
						math.clamp(at.X, reach + 12, math.max(reach + 12, size.X - reach - 12)),
						math.clamp(at.Y, reach + 20, math.max(reach + 20, size.Y - reach - 20))
					)
				end)
				local centerTarget = Compose.cell(rawCenter:peek())
				local innerTarget = Compose.cell(rawInner:peek())
				Compose.watch(function(use: ComposeTypes.Use)
					local at, inner = use(rawCenter), use(rawInner)
					if follow ~= "fixed" and (follow == "always" or not use(interacting)) then
						centerTarget:set(at)
						innerTarget:set(inner)
					end
				end)
				local frozenCenter = Compose.cell(centerTarget:peek())
				local centerSpring = ctx.motionSpring("quick")
				local movingCenter = runtime.spring(function(use: ComposeTypes.Use)
					return use(centerTarget)
				end, { period = centerSpring.period, damping = centerSpring.damping })
				local following = Compose.cell(false)
				local center = Compose.formula(function(use: ComposeTypes.Use)
					if use(interacting) and follow ~= "always" then
						return use(frozenCenter)
					end
					return if reduced(use) or not use(following) then use(centerTarget) else use(movingCenter)
				end)
				freezeCenter = function()
					frozenCenter:set(center:peek())
				end
				local function solve(use: ComposeTypes.Use, flatten: boolean): Radial.Layout<V>
					local size, at, inner = use(viewport), use(centerTarget), use(innerTarget)
					local start, sweep = geometry.arc(spec.preset or "donut")
					local room = if sweep == 360
						then math.min(at.X - 12, size.X - at.X - 12, at.Y - 20, size.Y - at.Y - 20)
						else math.min(size.X - 28, size.Y - 28)
					local minimum = ctx.metric("targetSizes.minimum", use)
					for _, space in shelves do
						local position, extent = use(space.position) - use(origin), use(space.size)
						local fit = math.min(
							at.X - position.X,
							position.X + extent.X - at.X,
							at.Y - position.Y,
							position.Y + extent.Y - at.Y
						)
						if fit >= inner + minimum then
							room = math.min(room, fit)
							break
						end
					end
					local radius = math.max(inner + 1, math.min(240, room))
					local band = math.max(minimum, radius - inner)
					local floor = math.min(band, math.max(minimum, ringWidth(use) or 0))
					local items = read(spec.items, use)
					local prefix: { string } = {}
					local levels: { { Radial.Sector<V> } } = {}
					local ring = inner
					local padding = ctx.metric("space.s", use)
					local textSize = ctx.metric("typography.control.size", use)
					local iconSize = ctx.controlSize(nil, "iconSize", use)
					local function estimate(item: Radial.RadialItemBase<V>): (number, number)
						if glyphOnly(item) then
							return iconSize, iconSize
						end
						local label = read(item.label, use) or ""
						return (utf8.len(label) or #label) * textSize * 0.6, textSize
					end
					local navigation, expansion = spec.navigation or "replace", spec.expansion or "fan"
					local currentStart, currentSweep = start, sweep
					local function append(): { Radial.Sector<V> }
						local shown: { Radial.RadialItem<V> } = {}
						local seen: { [string]: boolean } = {}
						for _, item in items do
							assert(
								type(item.id) == "string" and not seen[item.id],
								"RadialMenu items require unique ids per level"
							)
							seen[item.id] = true
							assert(
								not (item.checked and item.selected),
								"RadialMenu state items require checked or selected"
							)
							assert(
								not ((item.checked or item.selected) and (item.children or item.onSelect)),
								"RadialMenu state items use onChange"
							)
							if read(item.hidden, use) ~= true then
								table.insert(shown, item)
							end
						end
						if spec.center and spec.center ~= "back" and not corner and #prefix == #use(path) then
							local navigationItem: Radial.RadialItemBase<V> & { checked: nil?, selected: nil?, value: nil?, onChange: nil? } =
								{
									id = "$navigation",
									label = if #prefix > 0 then "Back" else "Close",
									icon = if #prefix > 0 then "chevron.leading" else "close",
									labelStyle = "icon" :: "icon",
								}
							if #prefix == 0 and spec.distribution == "compass" then
								local slots: { [string]: boolean } = {}
								for _, item in shown do
									if item.slot then
										slots[item.slot] = true
									end
								end
								local compassSlots: { Radial.CompassSlot } =
									{ "SW", "S", "SE", "NW", "W", "E", "NE", "N" }
								for _, slot in compassSlots do
									if not slots[slot] then
										navigationItem.slot = slot :: Radial.CompassSlot
										break
									end
								end
								if navigationItem.slot then
									table.insert(shown, navigationItem)
								end
							else
								table.insert(shown, navigationItem)
							end
						end
						local ri = ring
						local distribution = if #prefix == 0 then spec.distribution or "even" else "even"
						local levelStart = currentStart
						local last = shown[#shown]
						if last and last.id == "$navigation" and distribution == "even" and currentSweep == 360 then
							levelStart = 225 - (#shown - 1) * 360 / #shown
						end
						local levelBand = band
						do
							local extent, target = 0, 0
							for _, probe in geometry.sectors(shown, levelStart, currentSweep, distribution, ri, ri + 1) do
								local width, height = estimate(probe.item)
								local ux, uy = math.sin(math.rad(probe.angle)), -math.cos(math.rad(probe.angle))
								local hw, hh = width / 2 + padding, height / 2 + padding
								local middle = ri + math.abs(hw * ux) + math.abs(hh * uy)
								for _, dx in { -hw, hw } do
									for _, dy in { -hh, hh } do
										local x, y = middle * ux + dx, middle * uy + dy
										extent = math.max(extent, math.sqrt(x * x + y * y) - ri)
									end
								end
								local chord = 2 * math.sin(math.rad(math.min(probe.span, 180) / 2)) * 0.86
								target = math.max(target, 2 * (minimum / chord - ri))
							end
							local wanted = 2 * math.ceil(math.max(extent, target) / 2)
							levelBand = math.clamp(wanted, floor, band)
						end
						ring = ri + levelBand + 4
						local sectors =
							geometry.sectors(shown, levelStart, currentSweep, distribution, ri, ri + levelBand)
						for _, sector in sectors do
							sector.path = table.clone(prefix)
							sector.key = table.concat(prefix, "/") .. "/" .. sector.id
						end
						table.insert(levels, sectors)
						return sectors
					end
					local current = append()
					for _, id in use(path) do
						local parent: Radial.Sector<V>?
						for sectorIndex = 1, #current do
							local sector = current[sectorIndex]
							if sector.id == id and read(sector.item.enabled, use) ~= false then
								parent = sector
								break
							end
						end
						if not parent or not parent.item.children then
							break
						end
						navigation = if flatten then "replace" else parent.item.navigation or navigation
						expansion = parent.item.expansion or expansion
						table.insert(prefix, id)
						items = read(parent.item.children, use)
						if navigation == "replace" then
							levels, ring = {}, inner
							currentStart, currentSweep = start, sweep
						elseif expansion == "fan" then
							currentSweep = math.min(sweep, math.max(parent.span, #items * 32))
							currentStart = parent.angle - currentSweep / 2
							if sweep < 360 then
								currentStart = math.clamp(currentStart, start, start + sweep - currentSweep)
							end
						else
							currentStart, currentSweep = start, sweep
						end
						current = append()
					end
					local result: { Radial.Sector<V> } = {}
					local list = room < inner + band or band < minimum
					for levelIndex = 1, #levels do
						local level = levels[levelIndex]
						for sectorIndex = 1, #level do
							local sector = level[sectorIndex]
							list = list or sector.size < 44 or sector.outer > room
							table.insert(result, sector)
						end
					end
					list = list and gestureSelection ~= "direction"
					if list then
						result = {}
						for _, sector in current do
							if sector.id ~= "$navigation" then
								table.insert(result, sector)
							end
						end
					end
					for index, sector in result do
						sector.index, sector.list = index, list
					end
					return { sectors = result, list = list, inner = inner, path = prefix }
				end
				local layout = Compose.formula(function(use: ComposeTypes.Use): Radial.Layout<V>
					local stacked = solve(use, false)
					if not stacked.list or #use(path) == 0 then
						return stacked
					end
					local flat = solve(use, true)
					return if flat.list then stacked else flat
				end)
				local sectors = Compose.formula(function(use: ComposeTypes.Use)
					return use(layout).sectors
				end)
				local fallback = Compose.formula(function(use: ComposeTypes.Use)
					return use(layout).list
				end)
				candidateSector = function()
					local entries = sectors:peek()
					for sectorIndex = 1, #entries do
						local sector = entries[sectorIndex]
						if sector.key == candidate:peek() then
							return sector
						end
					end
					return nil
				end
				local entry = runtime.timeline({ duration = ctx.metric("motion.radial.enter") })
				Compose.watch(function(use: ComposeTypes.Use)
					use(centerTarget)
					if entry.completed:peek() then
						following:set(true)
					end
				end)
				local spreadFrom = ctx.metric("motion.materialize.radialSpread")
				local function spread(use: ComposeTypes.Use): number
					return if reduced(use)
						then 1
						else spreadFrom + (1 - spreadFrom) * ctx.motionEase("present", use)(use(entry.progress))
				end
				local fading = runtime.tween(function(use: ComposeTypes.Use)
					return if phase and use(phase.exiting) then 1 else 0
				end, { seconds = ctx.metric("motion.radial.exit") })
				local function transparency(use: ComposeTypes.Use): number
					if reduced(use) then
						return 0
					end
					return math.max(1 - use(entry.progress), use(fading))
				end
				local buttons: { [string]: TextButton } = {}
				local ringFits: ComposeTypes.Cell<{ [string]: { ring: number, inner: number, outer: number } }> =
					Compose.cell({})
				local wordWidths: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
				local function iconic(use: ComposeTypes.Use, live: Radial.Sector<V>): boolean
					if live.list then
						return false
					end
					if glyphOnly(live.item) then
						return true
					end
					local item = live.item
					local icon = item.icon ~= nil or (item.compactLabel ~= nil and item.compactLabel.icon ~= nil)
					return icon and (use(wordWidths)[live.key] or 0) > geometry.labelBounds(live, 40).w
				end
				local focus = Compose.createFocusScope({
					from = sectors,
					key = function(sector: Radial.Sector<V>)
						return sector.key
					end,
					disabled = function(sector: Radial.Sector<V>)
						return read(sector.item.enabled) == false
					end,
					position = function(sector: Radial.Sector<V>)
						return if sector.list then 0 else sector.x, if sector.list then sector.index * 48 else sector.y
					end,
					autoFocus = false,
				})
				local selectingInput = surfaces.selecting()
				Compose.watch(function(use: ComposeTypes.Use)
					if selectingInput(use) and use(focus.current) == nil and #use(sectors) > 0 then
						focus.first()
					end
				end)
				local gui = surfaces.service("GuiService")
				local attributes: Types.Attributes = {
					Presentation = function(use: ComposeTypes.Use)
						return if use(fallback) then "list" else "radial"
					end,
				}
				local panelProps: Types.ScrollingFrameNativeProps = {
					Name = "RadialPanel",
					BackgroundTransparency = function(use: ComposeTypes.Use)
						return if use(fallback) then 0 else 1
					end,
					Size = function(use: ComposeTypes.Use)
						return if use(fallback) then D2.new(1, -32, 1, -80) else D2.fromScale(1, 1)
					end,
					Position = function(use: ComposeTypes.Use)
						return if use(fallback) then D2.fromOffset(16, 48) else D2.fromOffset(0, 0)
					end,
					Active = function(use: ComposeTypes.Use)
						return use(fallback) or not spec.centerPassThrough
					end,
					Interactable = opened,
					Selectable = false,
					CanvasSize = D2.fromOffset(0, 0),
					AutomaticCanvasSize = function(use: ComposeTypes.Use)
						return if use(fallback) then E.AutomaticSize.Y else E.AutomaticSize.None
					end,
					ScrollingEnabled = fallback,
					ClipsDescendants = fallback,
					ScrollBarThickness = function(use: ComposeTypes.Use)
						return if use(fallback) then 6 else 0
					end,
					Attributes = attributes,
					Compose.show(fallback, function()
						return lists.list({ gap = 4 }, true)
					end),
					Compose.keyed({
						from = function(use: ComposeTypes.Use)
							local entries: { string } = {}
							local function visit(items: { Radial.RadialItem<V> }, prefix: string)
								for _, item in items do
									local key = prefix .. "/" .. item.id
									table.insert(entries, key)
									if item.children then
										visit(read(item.children, use), if prefix == "" then item.id else key)
									end
								end
								if spec.center and spec.center ~= "back" and not corner then
									table.insert(entries, prefix .. "/$navigation")
								end
							end
							visit(read(spec.items, use), "")
							return entries
						end,
						render = function(key: ComposeTypes.Readable<string>)
							local current: ComposeTypes.Cell<Radial.Sector<V>?> = Compose.cell(nil :: Radial.Sector<V>?)
							local painted = Compose.cell(false)
							local present = Compose.formula(function(use: ComposeTypes.Use): Radial.Sector<V>?
								local entries = use(sectors)
								for sectorIndex = 1, #entries do
									local sector = entries[sectorIndex]
									if sector.key == use(key) then
										return sector
									end
								end
								return nil
							end)
							Compose.watch(function(use: ComposeTypes.Use)
								local sector = use(present)
								if sector then
									current:set(sector)
								end
							end)
							return Host.Frame("SectorSlot" .. key:peek())({
								BackgroundTransparency = 1,
								Visible = painted,
								Interactable = function(use: ComposeTypes.Use)
									return use(present) ~= nil
								end,
								LayoutOrder = function(use: ComposeTypes.Use)
									local sector = use(current)
									return if sector then sector.index else 0
								end,
								Size = function(use: ComposeTypes.Use)
									local sector = use(current)
									return if sector and sector.list then D2.new(1, 0, 0, 44) else D2.fromScale(1, 1)
								end,
								Compose.presence(function(use: ComposeTypes.Use)
									return use(present)
								end, function(branchPhase: Navigation.PresencePhase)
									local function currentSector(use: ComposeTypes.Use?): Radial.Sector<V>
										return assert(if use then use(current) else current:peek())
									end
									painted:set(true)
									Compose.cleanup(function()
										painted:set(false)
									end)
									local entered = Compose.cell(false)
									local opacity = runtime.tween(function(use: ComposeTypes.Use)
										return if use(entered) and not use(branchPhase.exiting) then 1 else 0
									end, { seconds = ctx.metric("motion.radial.exit") })
									local arrival = runtime.tween(function(use: ComposeTypes.Use)
										return if use(entered) then 1 else 0
									end, { seconds = ctx.metric("motion.radial.slot") })
									local sector = assert(currentSector())
									local from = branchOrigin
									local branch = if from and from.path == table.concat(sector.path, "/")
										then from.shape
										else nil
									local centred = branch == nil and entry.completed:peek()
									local function unfold(
										use: ComposeTypes.Use,
										shape: Radial.SectorShape
									): Radial.SectorShape
										local parent = assert(branch)
										local present = ctx.motionEase("present", use)
										local p = if use(branchPhase.exiting)
											then 1 - present(1 - use(opacity))
											else present(use(arrival))
										local start = ctx.metric("motion.unfoldStart", use)
										local factor = start + (1 - start) * p
										local middle = (parent.inner + parent.outer) / 2
										local radius = middle
											+ (math.sqrt(shape.x * shape.x + shape.y * shape.y) - middle) * p
										local angle = parent.angle + geometry.delta(shape.angle, parent.angle) * factor
										local result = table.clone(shape)
										result.angle, result.span = angle, shape.span * factor
										result.inner = parent.inner + (shape.inner - parent.inner) * p
										result.outer = parent.outer + (shape.outer - parent.outer) * p
										result.x = math.sin(math.rad(angle)) * radius
										result.y = -math.cos(math.rad(angle)) * radius
										return result
									end
									local function moving(use: ComposeTypes.Use, live: Radial.Sector<V>): boolean
										return (branch ~= nil or centred) and not live.list and not reduced(use)
									end
									local function travel(
										use: ComposeTypes.Use,
										live: Radial.Sector<V>
									): (number, number)
										if not moving(use, live) then
											return 0, 0
										end
										if branch then
											local shown = unfold(use, live)
											return shown.x - live.x, shown.y - live.y
										end
										local amount = ctx.metric("motion.materialize.branch", use) * (1 - use(arrival))
										return -live.x * amount, -live.y * amount
									end
									local function chosen(use: ComposeTypes.Use): boolean
										local live = currentSector(use)
										return use(candidate) == live.key
											or use(focus.current) == live.key
											or read(live.item.checked, use) == true
											or (
												live.item.selected ~= nil
												and read(live.item.selected, use) == live.item.value
											)
									end
									local button = UI.Button({
										Name = sector.id,
										corners = if appearance == "buttons" then "pill" :: "pill" else nil,
										appearance = if appearance == "wedges" then "utility" else nil,
										ClipsDescendants = appearance == "wedges",
										label = function(use: ComposeTypes.Use)
											local live = currentSector(use)
											return if iconic(use, live) then "" else read(live.item.label, use)
										end,
										name = function(use: ComposeTypes.Use): string
											return read(currentSector(use).item.label, use) or ""
										end,
										icon = sector.item.icon
											or (sector.item.compactLabel and sector.item.compactLabel.icon),
										AnchorPoint = function(use: ComposeTypes.Use)
											return if currentSector(use).list then V2.zero else V2.new(0.5, 0.5)
										end,
										BackgroundTransparency = if appearance == "wedges"
												or spec.buttonSurface == "none"
											then 1
											else nil,
										LayoutOrder = function(use: ComposeTypes.Use)
											return currentSector(use).index
										end,
										InputBegan = beginPointer,
										MouseEnter = function()
											if not capture and not analog then
												candidate:set(currentSector().key)
												naming:set(pointing())
											end
										end,
										MouseLeave = function()
											if not capture and not analog then
												candidate:set(nil)
												naming:set(false)
											end
										end,
										AutomaticSize = E.AutomaticSize.None,
										Position = function(use: ComposeTypes.Use)
											local at, live = use(center), currentSector(use)
											if live.list then
												return D2.fromOffset(0, 0)
											end
											local scale = spread(use)
											local dx, dy = travel(use, live)
											return D2.fromOffset(at.X + live.x * scale + dx, at.Y + live.y * scale + dy)
										end,
										Size = function(use: ComposeTypes.Use)
											local live = currentSector(use)
											if live.list then
												return D2.new(1, -8, 0, 44)
											end
											if appearance == "buttons" then
												local diameter = math.max(44, live.size)
												return D2.fromOffset(diameter, diameter)
											end
											local bounds = geometry.labelBounds(live, 40)
											return D2.fromOffset(bounds.w, bounds.h)
										end,
										TextWrapped = true,
										enabled = function(use: ComposeTypes.Use)
											return read(currentSector(use).item.enabled, use) ~= false
										end,
										selected = chosen,
										onActivate = function(input: InputObject?)
											nativeActivate(currentSector(), input)
										end,
										SelectionGained = function()
											focus.focus(currentSector().key)
											candidate:set(currentSector().key)
										end,
										ZIndex = 105,
									})
									buttons[sector.key] = button
									local glyph = button:FindFirstChild("LeadingIcon", true)
									if glyph then
										runtime.decorate(glyph, {
											Visible = function(use: ComposeTypes.Use)
												local live = currentSector(use)
												return live.list or iconic(use, live)
											end,
										})
									end
									Compose.watch(function(use: ComposeTypes.Use)
										local live = currentSector(use)
										if not live.list and iconic(use, live) then
											button:AddTag("facet-button-glyph")
										else
											button:RemoveTag("facet-button-glyph")
										end
									end)
									if appearance == "wedges" then
										ctx.styled(button, "radial-item")
									end
									Compose.cleanup(function()
										buttons[sector.key] = nil
									end)
									skin(button, spec.skin and spec.skin.item, function(use: ComposeTypes.Use)
										return use(candidate) == currentSector(use).key
									end)
									local caption = button:FindFirstChild("Title", true)
									local measured = ctx.observe.TextBounds(
										if caption and caption:IsA("TextLabel") then caption else button
									)
									Compose.watch(function(use: ComposeTypes.Use)
										local width = use(measured).X
										if width > 0 and wordWidths:peek()[sector.key] ~= width then
											local widths = table.clone(wordWidths:peek())
											widths[sector.key] = width
											wordWidths:set(widths)
										end
									end)
									local paint = Host.Path2D "Sector" {
										Thickness = sector.outer - sector.inner,
										Closed = false,
										ZIndex = 102,
									}
									ctx.styled(paint, "radial-sector")
									Compose.watch(function(use: ComposeTypes.Use)
										if chosen(use) then
											paint:AddTag("facet-radial-candidate")
										else
											paint:RemoveTag("facet-radial-candidate")
										end
									end)
									local wrapper = ctx.fade({
										Name = "Sector-" .. sector.id,
										BackgroundTransparency = 1,
										GroupTransparency = function(use: ComposeTypes.Use)
											return if reduced(use)
												then transparency(use)
												else 1 - (1 - transparency(use)) * use(opacity)
										end,
										ClipsDescendants = false,
										LayoutOrder = function(use: ComposeTypes.Use)
											return currentSector(use).index
										end,
										Size = function(use: ComposeTypes.Use)
											return if currentSector(use).list
												then D2.new(1, 0, 0, 44)
												else D2.fromScale(1, 1)
										end,
										button,
									})
									local shaped = Compose.cell(false)
									local shape = Host.Frame "Paint" {
										BackgroundTransparency = 1,
										Visible = function(use: ComposeTypes.Use)
											return appearance == "wedges"
												and not currentSector(use).list
												and use(shaped)
										end,
										paint,
									}
									surfaces.attach(wrapper, { shape })
									local placed = Compose.cell(nil :: { x: number, y: number }?)
									Compose.watch(function(use: ComposeTypes.Use)
										if use(present) == nil then
											return
										end
										local live = currentSector(use)
										local text = use(measured)
										local label = geometry.labelBounds(live, 40)
										local iconOnly = iconic(use, live)
										local iconSize = ctx.controlSize(nil, "iconSize", use)
										local fitted = geometry.fitContent(
											live,
											if iconOnly then iconSize elseif text.X > 0 then text.X else label.w,
											if iconOnly then iconSize elseif text.Y > 0 then text.Y else label.h,
											6,
											contentFit
										)
										local ready = iconOnly or text.X > 0 or (read(live.item.label, use) or "") == ""
										local complete = ready
										if contentFit == "radial" then
											local own = ringFits:peek()[live.key]
											if
												ready
												and (
													not own
													or own.ring ~= live.inner
													or own.inner ~= fitted.inner
													or own.outer ~= fitted.outer
												)
											then
												local nextFits = table.clone(ringFits:peek())
												nextFits[live.key] =
													{ ring = live.inner, inner = fitted.inner, outer = fitted.outer }
												ringFits:set(nextFits)
											end
											local shown: { [string]: boolean } = {}
											for _, entry in use(sectors) do
												shown[entry.key] = true
											end
											local fits = use(ringFits)
											for _, entry in use(sectors) do
												local fit = fits[entry.key]
												if
													entry.inner == live.inner and (fit == nil or fit.ring ~= live.inner)
												then
													complete = false
												end
											end
											for key, fit in fits do
												if shown[key] and fit.ring == live.inner then
													fitted.inner = math.min(fitted.inner, fit.inner)
													fitted.outer = math.max(fitted.outer, fit.outer)
												end
											end
										end
										if complete and not shaped:peek() then
											shaped:set(true)
										end
										local bounds = geometry.paint(
											if branch and moving(use, live) then unfold(use, fitted) else fitted
										)
										placed:set({ x = bounds.x, y = bounds.y })
										shape.Size = D2.fromOffset(bounds.w, bounds.h)
										paint.Thickness = math.max(1, fitted.outer - fitted.inner)
										local points: { Path2DControlPoint } = {}
										for _, point in bounds.points do
											table.insert(
												points,
												ctx.types.Path2DControlPoint.new(
													D2.fromScale(point.x, point.y),
													D2.fromScale(point.inX, point.inY),
													D2.fromScale(point.outX, point.outY)
												)
											)
										end
										paint:SetControlPoints(points)
									end)
									Compose.watch(function(use: ComposeTypes.Use)
										local bounds = use(placed)
										if bounds == nil then
											return
										end
										local live, at = currentSector(use), use(center)
										local dx, dy = 0, 0
										if not branch then
											dx, dy = travel(use, live)
										end
										local lag = spread(use) - 1
										shape.Position = D2.fromOffset(
											at.X + bounds.x + dx + lag * live.x,
											at.Y + bounds.y + dy + lag * live.y
										)
									end)
									entered:set(true)
									return wrapper
								end, {
									exit = function(): ComposeTypes.Exiting
										return if reduced()
											then { completed = Compose.cell(true) }
											else runtime.timeline({ duration = ctx.metric("motion.radial.exit") })
									end,
								}),
							})
						end,
					}),
				}
				local panel = Host.ScrollingFrame(panelProps)
				Compose.watch(function(use: ComposeTypes.Use)
					if use(fallback) then
						panel:AddTag("facet-panel")
					else
						panel:RemoveTag("facet-panel")
					end
				end)
				local ringNavigation = spec.center == "empty" or spec.center == "content"
				local function showCenter(use: ComposeTypes.Use): boolean
					if corner or use(fallback) or not ringNavigation then
						return true
					end
					for _, sector in use(sectors) do
						if sector.id == "$navigation" then
							return false
						end
					end
					return true
				end
				local function navigating(use: ComposeTypes.Use?): boolean
					return corner or ringNavigation or (if use then use(fallback) else fallback:peek())
				end
				local function centerAction()
					if navigating() or spec.center == nil or spec.center == "back" then
						back()
					elseif spec.center == "root" then
						jump({})
					else
						close()
					end
				end
				local function hub(use: ComposeTypes.Use): number
					return if showCenter(use) then math.min(painted(use), 2 * use(layout).inner - 4) else 0
				end
				local function centerName(use: ComposeTypes.Use): string
					local depth = #use(path)
					if navigating(use) or spec.center == nil or spec.center == "back" then
						return (if navigating(use) then nil else read(spec.centerLabel, use))
							or if depth == 0 then "Close" else "Back"
					end
					return read(spec.centerLabel, use) or if spec.center == "root" then "Home" else "Close"
				end
				local function morph(use: ComposeTypes.Use): number
					return 1 - transparency(use)
				end
				local function diameter(use: ComposeTypes.Use): number
					if use(fallback) then
						return painted(use)
					end
					if corner and launcher and anchorSize then
						local extent = use(anchorSize)
						local from = math.max(painted(use), math.min(extent.X, extent.Y))
						return math.floor(painted(use) + (from - painted(use)) * (1 - morph(use)) + 0.5)
					end
					return hub(use)
				end
				local function centerAt(use: ComposeTypes.Use): UDim2
					if use(fallback) then
						return D2.new(1, -16 - painted(use) / 2, 0, 2 + painted(use) / 2)
					end
					local at = use(center)
					return D2.fromOffset(at.X, at.Y)
				end
				local hideLauncher: (() -> ())? = nil
				local centerNode = UI.Button "Center" {
					corners = "pill" :: "pill",
					appearance = "utility",
					name = centerName,
					icon = function(use: ComposeTypes.Use): string
						return if spec.center == "root" and not navigating(use)
							then "chevron.up"
							elseif centerName(use) == "Back" then "chevron.leading"
							else "close"
					end,
					Visible = showCenter,
					Position = centerAt,
					AnchorPoint = V2.new(0.5, 0.5),
					Size = function(use: ComposeTypes.Use)
						local size = diameter(use)
						return D2.fromOffset(size, size)
					end,
					AutomaticSize = E.AutomaticSize.None,
					ZIndex = 105,
					onActivate = centerAction,
				}
				local centerHit = Host.TextButton "CenterHit" {
					Text = "",
					BackgroundTransparency = 1,
					Selectable = false,
					Visible = showCenter,
					Position = centerAt,
					AnchorPoint = V2.new(0.5, 0.5),
					Size = function(use: ComposeTypes.Use)
						local size = math.max(diameter(use), (ctx.metric("targetSizes.minimum", use)))
						return D2.fromOffset(size, size)
					end,
					ZIndex = 104,
					Activated = centerAction,
				}
				if corner and launcher and launcher:IsA("GuiObject") then
					local hidden = launcher :: GuiObject

					hideLauncher = function()
						local automatic, size = root.AutomaticSize, root.Size
						local held = automatic ~= E.AutomaticSize.None
						local extent = root.AbsoluteSize / layoutUnit:peek()
						local function show()
							hidden.Visible = true
							if held then
								root.AutomaticSize, root.Size = automatic, size
							end
						end
						if held then
							root.AutomaticSize, root.Size = E.AutomaticSize.None, D2.fromOffset(extent.X, extent.Y)
						end
						hidden.Visible = false
						if phase then
							Compose.watch(function(use: ComposeTypes.Use)
								if use(phase.exiting) then
									show()
								end
							end)
						end
						Compose.cleanup(show)
					end
					local glyph = centerNode:FindFirstChild("LeadingIcon", true)
					if glyph then
						runtime.decorate(glyph, {
							ImageTransparency = function(use: ComposeTypes.Use): number
								return 1 - morph(use)
							end,
						})
					end
					surfaces.attach(centerNode, {
						ctx.icon(spec.icon or "more", {
							Name = "LauncherIcon",
							AnchorPoint = V2.new(0.5, 0.5),
							Position = D2.fromScale(0.5, 0.5),
							ImageTransparency = morph,
						}),
					})
				end
				if spec.center == "content" and spec.centerContent and not corner then
					local node = if type(spec.centerContent) == "function"
						then spec.centerContent()
						else spec.centerContent
					runtime.decorate(node, {
						Position = function(use: ComposeTypes.Use)
							local at = use(center)
							return D2.fromOffset(at.X, at.Y)
						end,
						AnchorPoint = V2.new(0.5, 0.5),
						ZIndex = 105,
					})
					surfaces.attach(panel, { node })
				end
				skin(centerNode, spec.skin and spec.skin.center)
				local panelSize = ctx.observe.AbsoluteSize(panel)
				local function reachOf(ring: Radial.Layout<V>): number
					local reach = ring.inner
					for _, sector in ring.sectors do
						reach = math.max(reach, sector.outer)
					end
					return reach
				end
				local function previewPlace(use: ComposeTypes.Use): (UDim2, Vector2)
					local ring = use(layout)
					if ring.list then
						return D2.fromOffset(16, 40), V2.new(0, 1)
					end
					local at = use(center)
					do
						local key = use(candidate)
						local near: Radial.Sector<V>? = nil
						for _, sector in ring.sectors do
							if sector.key == key then
								near = sector
							end
						end
						local angle = math.rad(if near then near.angle else geometry.arc(spec.preset or "donut") + 45)
						local dx, dy = math.sin(angle), -math.cos(angle)
						local reach = if near
							then math.sqrt(near.x * near.x + near.y * near.y) + math.max(44, near.size) / 2 + ctx.metric(
								"space.xs",
								use
							)
							else reachOf(ring) + ctx.metric("space.s", use)
						local function side(value: number): number
							return if value > 0.3 then 0 elseif value < -0.3 then 1 else 0.5
						end
						return D2.fromOffset(at.X + dx * reach, at.Y + dy * reach), V2.new(side(dx), side(dy))
					end
				end
				local function previewWidth(use: ComposeTypes.Use): number
					local place, anchor = previewPlace(use)
					local x, room = place.X.Offset, use(viewport).X
					local fits = if anchor.X == 0
						then room - 8 - x
						elseif anchor.X == 1 then x - 8
						else 2 * math.min(x - 8, room - 8 - x)
					return math.max(0, math.min(240, fits))
				end
				local preview = ctx.text({
					Name = "SelectionPreview",
					Size = function(use: ComposeTypes.Use): UDim2
						if use(layout).list then
							return D2.new(1, -32 - 1.5 * painted(use), 0, 0)
						end
						return D2.fromOffset(previewWidth(use), ctx.metric("typography.caption.size", use) + 4)
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if use(layout).list then E.AutomaticSize.Y else E.AutomaticSize.None
					end,
					Position = function(use: ComposeTypes.Use): UDim2
						return (previewPlace(use))
					end,
					AnchorPoint = function(use: ComposeTypes.Use): Vector2
						local _, anchor = previewPlace(use)
						return anchor
					end,
					TextXAlignment = function(use: ComposeTypes.Use)
						local _, anchor = previewPlace(use)
						return if anchor.X == 0.5
							then E.TextXAlignment.Center
							elseif anchor.X == 0 then E.TextXAlignment.Left
							else E.TextXAlignment.Right
					end,
					TextTruncate = E.TextTruncate.AtEnd,
					Text = function(use: ComposeTypes.Use)
						if not use(layout).list then
							local key = if use(naming) then use(candidate) else nil
							local entries = use(sectors)
							for sectorIndex = 1, #entries do
								local sector = entries[sectorIndex]
								if sector.key == key and iconic(use, sector) then
									local label = read(sector.item.label, use) or ""
									local detail = read(sector.item.description, use)
									return label .. (if detail then " · " .. detail else "")
								end
							end
							return ""
						end

						local labels: { string } = {}
						local items: { Radial.RadialItem<V> }? = read(spec.items, use)
						for _, id in use(path) do
							local found: Radial.RadialItem<V>? = nil
							local level: { Radial.RadialItem<V> } = items or {}
							for itemIndex = 1, #level do
								local item = level[itemIndex]
								if item.id == id then
									found = item
								end
							end
							if found == nil then
								break
							end
							table.insert(labels, tostring(read(found.label, use) or id))
							items = read(found.children, use)
						end
						return if #labels > 0
							then table.concat(labels, " › ")
							else read(spec.label, use) or "Quick actions"
					end,
					ZIndex = 106,
				})
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
				aimPointer = function(
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
							assert(candidateSector)()
						)
					)
				end
				aimAnalog = function(value: Vector2)
					if capture or not opened:peek() or not ctx.available(panel) then
						return
					end
					local magnitude = value.Magnitude
					if magnitude < 0.25 then
						analog = false
						interacting:set(false)
						candidate:set(nil)
						return
					end
					if magnitude < 0.35 and not analog then
						return
					end
					local entering = not analog
					if entering and freezeCenter then
						freezeCenter()
					end
					analog = true
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
								assert(candidateSector)()
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
						capture
						and (
							input == capture
							or (
								capture.UserInputType == E.UserInputType.MouseButton1
								and input.UserInputType == E.UserInputType.MouseMovement
							)
						)
					then
						if input.UserInputState == E.UserInputState.Cancel then
							cancel()
						else
							if heldAt and (input.Position - heldAt).Magnitude > 14 then
								holding:pause()
								if inspectedUntil == math.huge then
									inspectedUntil = nil
								end
							end
							naming:set(true)
							assert(aimPointer)(input.Position, true)
						end
					end
				end)
				runtime.connect(inputService or panel, "InputEnded", function(input: InputObject)
					if
						capture
						and (
							input == capture
							or (
								capture.UserInputType == E.UserInputType.MouseButton1
								and input.UserInputType == E.UserInputType.MouseButton1
							)
						)
					then
						if input.UserInputState == E.UserInputState.Cancel then
							cancel()
							return
						end
						local still = pressedAt and (input.Position - pressedAt).Magnitude < 8
						local outside = still and beyond(pressedAt :: Vector3) and beyond(input.Position)
						local sector = if outside then nil else assert(aimPointer)(input.Position, true)
						cancel()
						if outside then
							close()
						elseif type(sector) == "table" then
							nativeActivate(sector, input, "gesture")
						end
					end
				end)
				returnSelection = function(change: () -> (), key: string?)
					local held = gui ~= nil and surfaces.within(gui.SelectedObject, panel)
					change()
					local button = buttons[key or (if held then focus.first() else nil) or ""]
					if held and gui and button and button.Parent then
						gui.SelectedObject = button
					end
				end
				Compose.cleanup(function()
					cancel()
					aimPointer, aimAnalog, candidateSector, freezeCenter, returnSelection = nil, nil, nil, nil, nil
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
						{ priority = 2200, group = "Radial", direction2D = aimAnalog }
					)
					ctx.action(panel, "RadialCommit", { "ButtonA", "Return" }, function(use: ComposeTypes.Use)
						return use(opened) and use(candidate) ~= nil
					end, function()
						local selected = assert(candidateSector)()
						nativeActivate(selected, nil, "action")
					end, { priority = 2200, group = "Radial" })
					local directionalKeys: { [ComposeTypes.FocusDirection]: { Types.ActionBinding } } = {
						left = { "Left", "DPadLeft" },
						right = { "Right", "DPadRight" },
						up = { "Up", "DPadUp" },
						down = { "Down", "DPadDown" },
					}
					for direction, keys in directionalKeys do
						ctx.action(panel, "Radial-" .. direction, keys, opened, function()
							analog = false
							interacting:set(false)
							local key = focus.move(direction :: ComposeTypes.FocusDirection)
							candidate:set(key)
							naming:set(true)
							if gui and key and buttons[key] then
								gui.SelectedObject = buttons[key]
							end
						end, { priority = 2200, capture = true, group = "Radial" })
					end
				end
				local modal = surfaces.modal(
					function()
						return panel
					end,
					back,
					{
						appearance = function(use: ComposeTypes.Use?): number
							return 1 - if use then transparency(use) else 0
						end,
					}
				)
				surfaces.attach(modal, { centerHit, centerNode, preview })
				if hideLauncher then
					hideLauncher()
				end
				local catcher = modal:FindFirstChild("DismissOutside")
				if catcher then
					if scrim == "dark" then
						catcher:AddTag("facet-radial-scrim")
					elseif scrim == "none" then
						local clear = catcher :: GuiObject
						clear:RemoveTag("facet-scrim")
						clear.BackgroundTransparency = 1
					end
					runtime.decorate(catcher, {
						Position = function(use: ComposeTypes.Use)
							local size = use(viewport)
							return D2.fromOffset(-size.X, -size.Y)
						end,
						Size = function(use: ComposeTypes.Use)
							local size = use(viewport)
							return D2.new(1, 2 * size.X, 1, 2 * size.Y)
						end,
					})
				end
				if spec.skin and spec.skin.background then
					skin(modal, spec.skin.background)
				end
				local bounds = ctx.observe.AbsoluteSize(modal)
				local position = ctx.observe.AbsolutePosition(modal)
				Compose.watch(function(use: ComposeTypes.Use)
					origin:set(use(position))
				end)
				if spec.centerPassThrough and (spec.center == "empty" or spec.center == "content") then
					local outside = modal:FindFirstChild("DismissOutside")
					if outside then
						runtime.decorate(outside, { Visible = fallback })
					end
					for _, edge in { "Top", "Bottom", "Left", "Right" } do
						local rectangle = Compose.formula(function(use: ComposeTypes.Use)
							local size, at, radius = use(viewport), use(center), use(layout).inner
							local left, right =
								math.clamp(at.X - radius, 0, size.X), math.clamp(at.X + radius, 0, size.X)
							local top, bottom =
								math.clamp(at.Y - radius, 0, size.Y), math.clamp(at.Y + radius, 0, size.Y)
							if edge == "Top" then
								return { 0, 0, size.X, top }
							end
							if edge == "Bottom" then
								return { 0, bottom, size.X, size.Y - bottom }
							end
							if edge == "Left" then
								return { 0, top, left, bottom - top }
							end
							return { right, top, size.X - right, bottom - top }
						end)
						surfaces.attach(modal, {
							Host.TextButton({
								Name = "Dismiss" .. edge,
								Text = "",
								BackgroundTransparency = 1,
								Selectable = false,
								ZIndex = 100,
								Visible = function(use: ComposeTypes.Use)
									return not use(fallback) and use(opened)
								end,
								Position = function(use: ComposeTypes.Use)
									local r = use(rectangle)
									return D2.fromOffset(r[1], r[2])
								end,
								Size = function(use: ComposeTypes.Use)
									local r = use(rectangle)
									return D2.fromOffset(r[3], r[4])
								end,
								Activated = back,
							}),
						})
					end
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local size = use(bounds)
					if size.X > 0 and size.Y > 0 then
						if viewport:peek() ~= size then
							cancel()
						end
						viewport:set(size)
					end
				end)
				return modal
			end, {
				presence = {
					exit = function(): ComposeTypes.Exiting
						if reduced() or spec.transition == false then
							return { completed = Compose.cell(true) }
						end
						return runtime.timeline({ duration = ctx.metric("motion.radial.exit") })
					end,
				},
			}),
		})
		Compose.watch(function(use: ComposeTypes.Use)
			local anchor = read(spec.anchor, use)
			if not use(opened) then
				cancel()
			end
			if read(spec.enabled, use) == false or (type(anchor) == "table" and anchor.visible == false) then
				close()
			end
		end)
		if spec.holdAction then
			runtime.connect(spec.holdAction, "Pressed", function()
				held = true
				open()
			end)
			runtime.connect(spec.holdAction, "Released", function()
				if not held then
					return
				end
				held = false
				local selected = if analog and candidateSector then assert(candidateSector)() else nil
				if selected then
					nativeActivate(selected, nil, "hold")
				else
					cancel()
				end
			end)
		end
		local launcher = root:FindFirstChild("Launcher")
		if launcher and launcher:IsA("GuiObject") then
			skin(launcher, spec.skin and spec.skin.launcher)
		end
		return root
	end
	UI.RadialMenu = ctx.construct("RadialMenu", build)
end
