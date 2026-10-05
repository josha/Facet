--!strict
local activation = require("./activation")
local scrollLock = require("./scroll_lock")
local reducedMotion = require("./motion").reduced
local settling = require("./settle")
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local CollectionTypes = require("./collection_types")
local InputTypes = require("./input_types")
local NavigationTypes = require("./navigation_types")
type Controls = {
	RowActions: Types.Constructor<CollectionTypes.RowActionsSpec, Frame>,
	Menu: NavigationTypes.MenuConstructor,
	Button: Types.Constructor<InputTypes.ButtonProps, TextButton>,
}
type RowEdge = CollectionTypes.RowEdge
type RowAction = CollectionTypes.RowAction
return function(ctx: Types.Context, UI: Controls): ()
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local read = ctx.read
	local readSource = ctx.readSource
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	local behavior = {
		"content",
		"leading",
		"trailing",
		"actionWidth",
		"fullSwipe",
		"open",
		"onOpenChange",
		"coordinator",
		"enabled",
		"reducedMotion",
		"onActivate",
		"editing",
		"swipeEnabled",
	}
	local FULL_SWIPE = 0.6
	local RESISTANCE = 0.55
	UI.RowActions = ctx.construct("RowActions", function(spec: CollectionTypes.RowActionsSpec): Frame
		local leading: Types.Value<{ RowAction }> = spec.leading or {}
		local trailing: Types.Value<{ RowAction }> = spec.trailing or {}
		local content = if type(spec.content) == "function" then spec.content() else spec.content
		assert(typeof(content) == "Instance" or type(content) == "table", "Facet.RowActions requires content")
		local cellEdits = activation.edits(content)
		local open: ComposeTypes.Cell<RowEdge?> = spec.open or Compose.cell(nil :: RowEdge?)
		local menuOpen = Compose.cell(false)
		local drag: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local dimensions = Compose.cell(V2.zero)
		local editWidth = Compose.cell(72)
		local measuredActionWidth = Compose.cell(0)
		local actionWidths: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local rowToken = {}
		local departure = runtime.timeline({ duration = ctx.metric("motion.durations.rowDeparture"), autoplay = false })
		local committing: ComposeTypes.Cell<{ action: RowAction, edge: RowEdge, from: number }?> =
			Compose.cell(nil :: { action: RowAction, edge: RowEdge, from: number }?)
		local fired = false
		local motionReduced = reducedMotion(ctx)
		local function reduced(use: ComposeTypes.Use?): boolean
			return if spec.reducedMotion == nil then motionReduced(use) else read(spec.reducedMotion, use) == true
		end
		local function actions(edge: string, use: ComposeTypes.Use?): { RowAction }
			return read(if edge == "leading" then leading else trailing, use)
		end
		local function bandWidth(edge: string, use: ComposeTypes.Use?): number
			local list = actions(edge, use)
			local iconic = #list > 0
			for _, action in list do
				iconic = iconic and action.icon ~= nil
			end
			local width = read(spec.actionWidth or (if iconic then 64 else 88), use)
			local measuredWidths = readSource(actionWidths, use)
			for _, action in list do
				width = math.max(width, measuredWidths[edge .. ":" .. action.id] or 0)
			end
			return math.min(width * #list, readSource(dimensions, use).X)
		end
		local function fullSwipe(edge: RowEdge): boolean
			local choice = spec.fullSwipe
			return if type(choice) == "table"
				then (if edge == "leading" then choice.leading else choice.trailing) ~= false
				else choice ~= false
		end
		local function setOpen(edge: RowEdge?): ()
			if spec.coordinator and edge then
				spec.coordinator:set(rowToken)
			end
			if spec.onOpenChange then
				spec.onOpenChange(edge)
			elseif type(open.set) == "function" then
				open:set(edge)
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local edge = readSource(open, use) :: RowEdge?
			if edge ~= nil and #actions(edge, use) == 0 then
				setOpen(nil)
			end
		end)
		if spec.coordinator then
			Compose.watch(function(use: ComposeTypes.Use)
				if readSource(open, use) ~= nil and spec.coordinator:peek() ~= rowToken then
					spec.coordinator:set(rowToken)
				end
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				local active = use(spec.coordinator)
				if active ~= rowToken then
					menuOpen:set(false)
					if readSource(open) ~= nil then
						setOpen(nil)
					end
				end
			end)
			Compose.cleanup(function()
				if spec.coordinator:peek() == rowToken then
					spec.coordinator:set(nil)
				end
			end)
		end
		local offset = Compose.formula(function(use: ComposeTypes.Use)
			local commit = use(committing)
			if commit then
				local fraction = if reduced(use) then 1 else math.min(1, use(departure.progress) / 0.7)
				local target = (if commit.edge == "leading" then 1 else -1) * use(dimensions).X
				return commit.from + (target - commit.from) * fraction
			end
			local live = use(drag)
			if live ~= nil then
				return live
			end
			local edge = use(open) :: RowEdge?
			return if edge == nil then 0 else bandWidth(edge, use) * (if edge == "leading" then 1 else -1)
		end)
		local shownOffset = offset:peek()
		local rowSettle = settling(
			ctx,
			function(): number
				return shownOffset
			end,
			ctx.motionSpring("snappy"),
			function(): boolean
				return reduced()
			end
		)
		Compose.watch(function(use: ComposeTypes.Use)
			local live = use(offset)
			if use(drag) ~= nil or use(committing) ~= nil then
				shownOffset = live
				return
			end
			if rowSettle.value:peek() == nil and math.abs(live - shownOffset) > 0.5 then
				rowSettle.launch(shownOffset, 0)
			end
			shownOffset = live
		end)
		local function current(): number
			return if drag:peek() ~= nil or reduced() then offset:peek() else (rowSettle.value:peek() or offset:peek())
		end
		local function invoke(action: RowAction): ()
			if action.onActivate then
				action.onActivate()
			end
		end
		local frames = assert(runtime.host.frames)
		local stopSettle: (() -> ())?
		local function settle(): ()
			if stopSettle then
				return
			end
			stopSettle = frames.onFrame(function()
				if stopSettle then
					stopSettle()
					stopSettle = nil
				end
				committing:set(nil)
				fired = false
			end)
		end
		Compose.cleanup(function()
			if stopSettle then
				stopSettle()
				stopSettle = nil
			end
		end)
		local function execute(action: RowAction, edge: string?): ()
			if committing:peek() or read(spec.enabled) == false or read(action.enabled) == false then
				return
			end
			local from = current()
			drag:set(nil)
			menuOpen:set(false)
			setOpen(nil)
			if action.role == "destructive" then
				committing:set({
					action = action,
					edge = (if edge == "leading" then "leading" else "trailing") :: RowEdge,
					from = from,
				})
				if reduced() then
					fired = true
					settle()
					invoke(action)
				else
					departure:restart()
				end
			else
				invoke(action)
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if readSource(open, use) ~= nil and fired then
				fired = false
				committing:set(nil)
			end
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if use(departure.completed) and not fired then
				local commit = committing:peek()
				if commit then
					fired = true
					settle()
					invoke(commit.action)
				end
			end
		end)

		local function paintedOffset(use: ComposeTypes.Use): number
			return if use(drag) ~= nil
					or use(committing) ~= nil
					or reduced(use)
				then use(offset)
				else (use(rowSettle.value) or use(offset))
		end
		local function armed(edge: RowEdge, use: ComposeTypes.Use): boolean
			local commit = use(committing)
			if commit then
				return commit.edge == edge
			end
			local live = use(drag)
			return live ~= nil
				and fullSwipe(edge)
				and #actions(edge, use) > 0
				and (if edge == "leading" then live > 0 else live < 0)
				and math.abs(live) >= use(dimensions).X * FULL_SWIPE
		end
		local function tray(edge: RowEdge): Frame
			local nativeProps: Types.FrameProps = {
				Name = edge,
				AnchorPoint = V2.new(if edge == "leading" then 0 else 1, 0),
				Position = D2.fromScale(if edge == "leading" then 0 else 1, 0),
				Size = function(use: ComposeTypes.Use)
					local reveal = math.abs(paintedOffset(use))
					return D2.new(0, if armed(edge, use) then reveal else math.min(bandWidth(edge, use), reveal), 1, 0)
				end,
				Visible = function(use: ComposeTypes.Use)
					local x = paintedOffset(use)
					return if edge == "leading" then x > 0 else x < 0
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Attributes = { FacetDragExclude = true } :: Types.Attributes,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
					HorizontalAlignment = if edge == "leading"
						then E.HorizontalAlignment.Right
						else E.HorizontalAlignment.Left,
					SortOrder = E.SortOrder.LayoutOrder,
				}) :: ComposeTypes.Child,
				Compose.keyed({
					from = function(use: ComposeTypes.Use)
						return actions(edge, use)
					end,
					key = function(action: RowAction)
						return action.id
					end,
					render = function(current: ComposeTypes.Readable<RowAction>, index: ComposeTypes.Readable<number>)
						local iconic = current:peek().icon ~= nil
						local function words(use: ComposeTypes.Use): string
							return read(use(current).label, use)
						end
						local function first(use: ComposeTypes.Use): boolean
							return use(index) == 1
						end
						local buttonProps: InputTypes.ButtonProps = {
							Name = current:peek().id,
							LayoutOrder = function(use: ComposeTypes.Use)
								return if edge == "leading" then -use(index) else use(index)
							end,
							Size = function(use: ComposeTypes.Use)
								if armed(edge, use) and first(use) then
									return D2.fromScale(1, 1)
								end
								return D2.new(0, bandWidth(edge, use) / math.max(1, #actions(edge, use)), 1, 0)
							end,
							Visible = function(use: ComposeTypes.Use)
								return not armed(edge, use) or first(use)
							end,
							AutomaticSize = E.AutomaticSize.None,
							label = if iconic then "" else words,
							name = if iconic then words else nil,
							role = current:peek().role,
							icon = current:peek().icon,
							enabled = function(use: ComposeTypes.Use)
								return read(spec.enabled, use) ~= false and read(use(current).enabled, use) ~= false
							end,
							onActivate = function()
								execute(current:peek(), edge)
							end,
						}
						local button = UI.Button(buttonProps)
						button:AddTag("facet-row-action")
						local caption = button:FindFirstChild("Title", true)
						local bounds = if caption and caption:IsA("TextLabel")
							then ctx.observe.TextBounds(caption)
							else ctx.observe.TextBounds(button)
						Compose.watch(function(use: ComposeTypes.Use)
							local size, action = use(bounds), use(current)
							local width = (if size then size.X else 0)
								+ 32
								+ (if action.icon then ctx.controlSize(nil, "iconSize", use) + 8 else 0)
							local id = edge .. ":" .. action.id
							if actionWidths:peek()[id] ~= width then
								local widths = table.clone(actionWidths:peek())
								widths[id] = width
								actionWidths:set(widths)
							end
						end)
						return button
					end,
				}),
			}
			return Host.Frame(nativeProps)
		end
		local root: Frame
		local contentFrame: Frame
		local activeInput: InputObject?
		local reveal: () -> ()
		local function began(input: InputObject): ()
			if input.UserInputType == E.UserInputType.Touch or input.UserInputType == E.UserInputType.MouseButton1 then
				activeInput = input
			end
		end
		local start: Vector2? = nil
		local startOffset = 0
		local axis: ("horizontal" | "vertical")? = nil
		local function cancelDrag()
			start, axis, activeInput = nil, nil, nil
			drag:set(nil)
		end
		local previousX, previousTime, velocity = 0, 0, 0
		local now = assert(ctx.runtime.host.frames).now
		local function begin(position: Vector2): ()
			if committing:peek() or read(spec.enabled) == false or not ctx.available(root) then
				return
			end
			start, startOffset, axis = position, current(), nil
			rowSettle.halt()
			previousX, previousTime, velocity = position.X, now(), 0
		end
		local function move(position: Vector2): ()
			if start == nil or read(spec.enabled) == false then
				return
			end
			local currentTime = now()
			local elapsed = currentTime - previousTime
			if elapsed >= 0.005 then
				velocity = (position.X - previousX) / elapsed
				previousX, previousTime = position.X, currentTime
			end
			local delta = position - start
			if axis == nil and math.max(math.abs(delta.X), math.abs(delta.Y)) >= 8 then
				axis = if math.abs(delta.X) > math.abs(delta.Y) then "horizontal" else "vertical"
			end
			if axis == "horizontal" then
				local maxLeading = if #actions("leading") > 0 then dimensions:peek().X else 0
				local maxTrailing = if #actions("trailing") > 0 then dimensions:peek().X else 0
				local raw = startOffset + delta.X
				local edge: RowEdge = if raw > 0 then "leading" else "trailing"
				local band = bandWidth(edge)
				if not fullSwipe(edge) and math.abs(raw) > band then
					raw = math.sign(raw) * (band + (math.abs(raw) - band) * RESISTANCE)
				end
				drag:set(math.clamp(raw, -maxTrailing, maxLeading))
			end
		end
		local pressed: InputObject?
		local function collectionRow(): Instance?
			local host = root.Parent
			while host and host:GetAttribute("FacetCollectionRow") ~= true do
				host = host.Parent
			end
			return host
		end
		local function tap(input: InputObject?): ()
			if readSource(open) ~= nil then
				setOpen(nil)
				return
			end
			local host = collectionRow()
			local hit = if host then host:FindFirstChild("RowHit") else nil
			if hit and activation.trigger(hit, input or pressed) then
				return
			end
			for _, node in contentFrame:GetDescendants() do
				if activation.trigger(node) then
					return
				end
			end
		end
		local function finish()
			if read(spec.enabled) == false then
				start, axis = nil, nil
				drag:set(nil)
				return
			end
			local value = drag:peek()
			local fling = if now() - previousTime < 0.1 then velocity else 0
			if value ~= nil and value ~= 0 and axis == "horizontal" and dimensions:peek().X > 0 then
				local edge: RowEdge = if value > 0 then "leading" else "trailing"
				local available = actions(edge)
				local width = dimensions:peek().X
				local flung = if now() - previousTime < 0.1 then velocity * ctx.metric("motion.fling.projection") else 0
				local projected = if flung * value > 0 then value + flung else value
				if fullSwipe(edge) and #available > 0 and width > 0 and math.abs(projected) >= width * FULL_SWIPE then
					execute(available[1], edge)
				elseif
					#available > 0
					and value ~= 0
					and (
						math.abs(value) >= bandWidth(edge) * 0.5
						or (math.abs(velocity) > 600 and velocity * value > 0 and now() - previousTime < 0.1)
					)
				then
					setOpen(edge)
				else
					setOpen(nil)
				end
			end
			start, axis = nil, nil
			drag:set(nil)
			if value ~= nil and committing:peek() == nil then
				rowSettle.launch(value, fling)
			end
		end
		local function release(): ()
			local tapped = start ~= nil and axis == nil and committing:peek() == nil
			finish()
			if tapped and read(spec.enabled) ~= false then
				tap()
			end
		end
		local preferred = if ctx.config.userInputService
			then ctx.observe.PreferredInput(ctx.config.userInputService)
			else nil
		local function touchFirst(use: ComposeTypes.Use?): boolean
			return preferred ~= nil and readSource(preferred, use) == E.PreferredInput.Touch
		end
		local function actionSize(use: ComposeTypes.Use): number
			return if #cellEdits > 0
					and preferred
					and use(preferred) ~= E.PreferredInput.KeyboardAndMouse
				then math.max(44, ctx.controlSize(nil, "height", use))
				else 0
		end
		local function actionWidth(use: ComposeTypes.Use): number
			local size = actionSize(use)
			return if size > 0 then math.max(size, use(measuredActionWidth)) else 0
		end
		local panned = false
		local stopPan: (() -> ())? = nil
		local function settlePan(): ()
			if stopPan then
				return
			end
			stopPan = frames.onFrame(function()
				if stopPan then
					stopPan()
					stopPan = nil
				end
				panned = false
			end)
		end
		Compose.cleanup(function()
			if stopPan then
				stopPan()
				stopPan = nil
			end
		end)
		local releaseScrollers: (() -> ())? = nil
		local function freeScrollers(): ()
			if releaseScrollers then
				releaseScrollers()
				releaseScrollers = nil
			end
		end
		local function holdScrollers(): ()
			if releaseScrollers == nil then
				releaseScrollers = scrollLock.holdOwnedAncestors(root)
			end
		end
		Compose.cleanup(freeScrollers)
		local function pan(
			positions: { Vector2 },
			translation: Vector2,
			panVelocity: Vector2,
			state: Enum.UserInputState
		): ()
			if state == E.UserInputState.Begin then
				local position: Vector2? = positions[1]
				if position == nil then
					return
				end
				panned = true
				begin(position - translation)
			end
			if state == E.UserInputState.Begin or state == E.UserInputState.Change or state == E.UserInputState.End then
				if start then
					move(start + translation)
					velocity, previousTime = panVelocity.X, now()
				end
				if state == E.UserInputState.End then
					freeScrollers()
					finish()
					settlePan()
				elseif axis == "horizontal" then
					holdScrollers()
				end
			else
				freeScrollers()
				cancelDrag()
				settlePan()
			end
		end
		local function swipeable(use: ComposeTypes.Use): boolean
			return #cellEdits == 0
				and use(committing) == nil
				and read(spec.editing, use) ~= true
				and read(spec.swipeEnabled, use) ~= false
				and read(spec.enabled, use) ~= false
				and (#actions("leading", use) + #actions("trailing", use)) > 0
		end
		local function swipeDetector(use: ComposeTypes.Use): boolean
			return swipeable(use)
				and not touchFirst(use)
				and not (preferred ~= nil and readSource(preferred, use) == E.PreferredInput.Gamepad)
		end
		local detectorDrag = false
		Compose.watch(function(use: ComposeTypes.Use)
			if not swipeDetector(use) and detectorDrag then
				detectorDrag = false
				cancelDrag()
			end
		end)
		local menuItems = Compose.formula(function(use: ComposeTypes.Use)
			local result: { NavigationTypes.MenuItem<string> } = {}
			local edges: { RowEdge } = { "leading" :: RowEdge, "trailing" :: RowEdge }
			for _, edge in edges do
				for _, action in actions(edge :: RowEdge, use) do
					table.insert(result, {
						id = edge .. ":" .. action.id,
						label = action.label,
						icon = action.icon,
						role = action.role,
						enabled = action.enabled,
						onSelect = function()
							execute(action, edge)
						end,
					})
				end
			end
			return result
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			if read(spec.enabled, use) == false then
				start, axis = nil, nil
				drag:set(nil)
				menuOpen:set(false)
				setOpen(nil)
			end
		end)
		root = Host.Frame(ctx.props(spec, behavior, {
			Size = D2.new(1, 0, 0, 44),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			tray("leading") :: ComposeTypes.Child,
			tray("trailing"),
			Host.Frame "Content" {
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, (if read(spec.editing, use) then -use(editWidth) else 0) - actionWidth(use), 1, 0)
				end,
				BackgroundTransparency = 1,
				Position = function(use: ComposeTypes.Use)
					local gutter = if read(spec.editing, use) then use(editWidth) else 0
					return D2.fromOffset(gutter + paintedOffset(use), 0)
				end,
				Attributes = {
					FacetDragRestX = function(use: ComposeTypes.Use)
						return if read(spec.editing, use) then use(editWidth) else 0
					end,
				} :: Types.Attributes,
				content :: ComposeTypes.Child,
				Host.TextButton "SwipeGrip" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					Selectable = false,
					ZIndex = 4,
					Visible = swipeable,
					InputBegan = function(input: InputObject)
						began(input)
						pressed = input
						local host = collectionRow()
						local hit = if host then host:FindFirstChild("RowHit") else nil
						if hit then
							activation.press(hit, input)
						end
					end,
					Activated = function(input: InputObject?)
						if touchFirst() and not panned and start == nil then
							tap(input)
						end
					end,
					Host.UIDragDetector({
						Enabled = swipeDetector,
						DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
						DragAxis = V2.new(1, 0),
						ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
						DragStart = function(position: Vector2)
							detectorDrag = true
							activation.drag(root, "start", position)
							begin(position)
						end,
						DragContinue = function(position: Vector2)
							if detectorDrag then
								if activation.drag(root, "move", position) then
									return
								end
								move(position)
							end
						end,
						DragEnd = function()
							if detectorDrag then
								detectorDrag = false
								activation.drag(root, "end", nil)
								release()
							end
						end,
					}),
				},
				Host.TextButton "DismissTray" {
					Size = D2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",
					Active = true,
					AutoButtonColor = false,
					Selectable = false,
					ZIndex = 5,
					Visible = function(use: ComposeTypes.Use)
						return readSource(open, use) ~= nil and use(committing) == nil
					end,
					InputBegan = function(input: InputObject)
						if
							input.UserInputType ~= E.UserInputType.MouseButton1
							and input.UserInputType ~= E.UserInputType.Touch
						then
							return
						end
						local host = collectionRow()
						local hit = if host then host:FindFirstChild("RowHit") else nil
						if hit then
							activation.press(hit, input)
						end
						if readSource(open) ~= nil and committing:peek() == nil then
							setOpen(nil)
						end
					end,
					Activated = function()
						if readSource(open) ~= nil and committing:peek() == nil then
							setOpen(nil)
						end
					end,
				},
			},
		}))
		local menuSpec: NavigationTypes.MenuSpec<string> = {
			trigger = root,
			items = menuItems,
			isPresented = menuOpen,
			triggers = { "secondary" :: "secondary" },
			enabled = function(use: ComposeTypes.Use?): boolean
				return read(spec.enabled, use) ~= false
					and readSource(committing, use) == nil
					and #readSource(menuItems, use) > 0
			end,
			onOpen = function()
				setOpen(nil)
				if spec.coordinator then
					spec.coordinator:set(rowToken)
				end
			end,
		}
		UI.Menu(menuSpec)
		if #cellEdits > 0 then
			runtime.mount(function()
				local button = UI.Button {
					Name = "CellActions",
					icon = "more",
					label = "",
					name = "Item actions",
					appearance = "plain",
					AnchorPoint = V2.new(1, 0.5),
					Position = D2.fromScale(1, 0.5),
					Size = function(use)
						return D2.fromOffset(actionSize(use), actionSize(use))
					end,
					Visible = function(use)
						return actionSize(use) > 0
					end,
					enabled = spec.enabled,
					onActivate = function()
						reveal()
					end,
					ZIndex = 5,
				}
				local size, unit = ctx.observe.AbsoluteSize(button), ctx.layoutUnit(root)
				Compose.watch(function(use: ComposeTypes.Use)
					measuredActionWidth:set(use(size).X / use(unit))
				end)
				return button
			end, root)
		end
		contentFrame = assert(root:FindFirstChild("Content")) :: Frame
		local grip = assert(contentFrame:FindFirstChild("SwipeGrip"))
		runtime.connect(grip, "TouchPan", pan)
		runtime.decorate(root, {
			Size = function(use: ComposeTypes.Use)
				local size = read(spec.Size, use) or D2.new(1, 0, 0, 44)
				local fraction = if use(committing)
					then (if reduced(use) then 1 else math.clamp((use(departure.progress) - 0.7) / 0.3, 0, 1))
					else 0
				return D2.new(
					size.X.Scale,
					size.X.Offset,
					size.Y.Scale * (1 - fraction),
					size.Y.Offset * (1 - fraction)
				)
			end,
		})
		local measured = ctx.observe.AbsoluteSize(root)
		Compose.watch(function(use: ComposeTypes.Use)
			dimensions:set(use(measured))
		end)
		function reveal()
			if read(spec.enabled) ~= false and committing:peek() == nil and #menuItems:peek() > 0 then
				setOpen(nil)
				if spec.coordinator then
					spec.coordinator:set(rowToken)
				end
				menuOpen:set(true)
			end
		end

		runtime.connect(root, "InputBegan", began)
		local inputService = ctx.config.userInputService
		if inputService then
			local function cancelInput(input: InputObject): ()
				if activeInput == input and input.UserInputState == E.UserInputState.Cancel then
					cancelDrag()
				end
			end
			runtime.connect(inputService, "InputChanged", cancelInput)
			runtime.connect(inputService, "InputEnded", cancelInput)
			runtime.connect(inputService, "WindowFocusReleased", cancelDrag)
		end
		if inputService then
			local service = inputService
			local function outside(input: InputObject): boolean
				local layer = root:FindFirstAncestorWhichIsA("LayerCollector")
				if layer == nil or not layer:IsA("ScreenGui") then
					return false
				end
				local point = V2.new(input.Position.X, input.Position.Y)
				local guiService = ctx.config.guiService
				if (layer :: ScreenGui).IgnoreGuiInset and guiService then
					point += guiService:GetGuiInset()
				end
				local at, size = root.AbsolutePosition, root.AbsoluteSize
				return point.X < at.X or point.Y < at.Y or point.X > at.X + size.X or point.Y > at.Y + size.Y
			end
			local listening: RBXScriptConnection? = nil
			local function release(): ()
				if listening then
					listening:Disconnect()
					listening = nil
				end
			end
			Compose.watch(function(use: ComposeTypes.Use)
				if readSource(open, use) == nil then
					release()
				elseif listening == nil then
					listening = service.InputBegan:Connect(function(input: InputObject)
						local kind = input.UserInputType
						if
							(kind == E.UserInputType.MouseButton1 or kind == E.UserInputType.Touch)
							and committing:peek() == nil
							and readSource(open) ~= nil
							and outside(input)
						then
							setOpen(nil)
						end
					end)
				end
			end)
			Compose.cleanup(release)
		end
		runtime.connect(root, "TouchLongPress", function(_: { Vector2 }, state: Enum.UserInputState)
			if state == E.UserInputState.Begin and #cellEdits == 0 then
				reveal()
			end
		end)
		local gui = ctx.config.guiService
		local selected: ComposeTypes.Cell<GuiObject?> = if gui
			then ctx.observe.SelectedObject(gui)
			else Compose.cell(nil :: GuiObject?)
		local function scope(): Instance
			return collectionRow() or root
		end
		local function eligible(use: ComposeTypes.Use): boolean
			local node = readSource(selected, use)
			return node ~= nil
				and node:IsDescendantOf(scope())
				and read(spec.enabled, use) ~= false
				and readSource(committing, use) == nil
				and not (node:IsA("TextBox") and node:IsFocused())
		end
		ctx.action(
			root,
			"RowActionsReveal",
			{ E.KeyCode.ButtonX, E.KeyCode.Menu },
			eligible,
			reveal,
			{ priority = 450 }
		)
		ctx.action(root, "RowActionsClose", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			return eligible(use) and (readSource(open, use) ~= nil or use(menuOpen))
		end, function()
			menuOpen:set(false)
			setOpen(nil)
		end, { priority = 300 })
		local function destructive(use: ComposeTypes.Use?): (RowAction?, RowEdge?)
			local edges: { RowEdge } = { "trailing" :: RowEdge, "leading" :: RowEdge }
			for _, edge in edges do
				for _, action in actions(edge :: RowEdge, use) do
					if action.role == "destructive" and read(action.enabled, use) ~= false then
						return action, edge :: RowEdge
					end
				end
			end
			return nil, nil
		end
		local function delete()
			local action, edge = destructive()
			if action then
				execute(action, edge)
			end
		end
		ctx.action(root, "RowActionsDelete", { E.KeyCode.Delete, E.KeyCode.Backspace }, function(use: ComposeTypes.Use)
			return eligible(use) and readSource(open, use) == nil and not use(menuOpen) and destructive(use) ~= nil
		end, delete, { priority = 300 })
		local toggleKeys: { Types.InputBindingNativeProps } = {
			{ KeyCode = E.KeyCode.Return, PrimaryModifier = E.KeyCode.LeftShift },
			{ KeyCode = E.KeyCode.Return, PrimaryModifier = E.KeyCode.RightShift },
		}
		ctx.action(root, "RowActionsToggle", toggleKeys, eligible, function()
			if menuOpen:peek() then
				menuOpen:set(false)
			else
				reveal()
			end
		end, { priority = 300 })
		ctx.shiftRoute(root, function()
			if read(spec.enabled) == false then
				return
			end
			if menuOpen:peek() then
				menuOpen:set(false)
			else
				reveal()
			end
		end)
		if spec.editing then
			runtime.mountFragment(function()
				return {
					Compose.show(function(use: ComposeTypes.Use)
						return read(spec.editing, use) == true and destructive(use) ~= nil
					end, function()
						local buttonProps: InputTypes.ButtonProps = {
							Name = "Delete",
							Size = function(use: ComposeTypes.Use)
								return D2.new(0, use(editWidth), 1, 0)
							end,
							ZIndex = 5,
							label = function(use: ComposeTypes.Use): string
								local action = destructive(use)
								return if action then read(action.label, use) else "Delete"
							end,
							role = "destructive" :: InputTypes.ButtonRole,
							onActivate = delete,
						}
						local button = UI.Button(buttonProps)
						local caption = button:FindFirstChild("Title", true)
						local bounds = if caption and caption:IsA("TextLabel")
							then ctx.observe.TextBounds(caption)
							else ctx.observe.TextBounds(button)
						Compose.watch(function(use: ComposeTypes.Use)
							local size = use(bounds)
							editWidth:set(math.min(use(dimensions).X, math.max(72, (if size then size.X else 0) + 32)))
						end)
						return button
					end),
				}
			end, root)
		end
		local previousSelection: GuiObject?
		Compose.watch(function(use: ComposeTypes.Use)
			local edge = use(open) :: RowEdge?
			if gui == nil then
				return
			end
			if edge ~= nil then
				local current = gui.SelectedObject
				if current and current:IsDescendantOf(scope()) then
					previousSelection = current
					local trayNode = root:FindFirstChild(edge)
					if trayNode then
						for _, child in trayNode:GetChildren() do
							if child:IsA("GuiButton") and child.Selectable and child.Interactable then
								gui.SelectedObject = child
								break
							end
						end
					end
				end
			elseif previousSelection and previousSelection.Parent then
				gui.SelectedObject = previousSelection
				previousSelection = nil
			end
		end)

		return ctx.styled(root, "RowActions")
	end)
end
