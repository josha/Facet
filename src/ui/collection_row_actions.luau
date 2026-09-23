--!strict
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
	}
	UI.RowActions = ctx.construct(function(spec: CollectionTypes.RowActionsSpec): Frame
		local leading: Types.Value<{ RowAction }> = spec.leading or {}
		local trailing: Types.Value<{ RowAction }> = spec.trailing or {}
		local content = if type(spec.content) == "function" then spec.content() else spec.content
		assert(typeof(content) == "Instance" or type(content) == "table", "Facet.RowActions requires content")
		local open: ComposeTypes.Cell<RowEdge?> = spec.open or Compose.cell(nil :: RowEdge?)
		local menuOpen = Compose.cell(false)
		local drag: ComposeTypes.Cell<number?> = Compose.cell(nil :: number?)
		local dimensions = Compose.cell(V2.zero)
		local editWidth = Compose.cell(72)
		local actionWidths: ComposeTypes.Cell<{ [string]: number }> = Compose.cell({})
		local rowToken = {}
		local departure = runtime.timeline({ duration = 0.24, autoplay = false })
		local committing: ComposeTypes.Cell<{ action: RowAction, edge: RowEdge }?> =
			Compose.cell(nil :: { action: RowAction, edge: RowEdge }?)
		local fired = false
		local function reduced(use: ComposeTypes.Use?): boolean
			return read(if spec.reducedMotion == nil then ctx.config.reducedMotion else spec.reducedMotion, use) == true
		end
		local function actions(edge: string, use: ComposeTypes.Use?): { RowAction }
			return read(if edge == "leading" then leading else trailing, use)
		end
		local function bandWidth(edge: string, use: ComposeTypes.Use?): number
			local count, width = #actions(edge, use), read(spec.actionWidth or 88, use)
			local measuredWidths = read(actionWidths, use)
			for _, action in actions(edge :: RowEdge, use) do
				width = math.max(width, measuredWidths[edge .. ":" .. action.id] or 0)
			end
			return math.min(width * count, read(dimensions, use).X)
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
		if spec.coordinator then
			Compose.watch(function(use: ComposeTypes.Use)
				local active = use(spec.coordinator)
				if active ~= rowToken then
					menuOpen:set(false)
					if read(open, use) ~= nil then
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
				return (if commit.edge == "leading" then 1 else -1) * use(dimensions).X * fraction
			end
			local live = use(drag)
			if live ~= nil then
				return live
			end
			local edge = use(open) :: RowEdge?
			return if edge == nil then 0 else bandWidth(edge, use) * (if edge == "leading" then 1 else -1)
		end)
		local animated = runtime.spring(function(use: ComposeTypes.Use)
			return use(offset)
		end, { period = 0.2, damping = 1 })
		local function invoke(action: RowAction): ()
			if action.onActivate then
				action.onActivate()
			end
		end
		local function execute(action: RowAction, edge: string?): ()
			if committing:peek() or read(spec.enabled) == false or read(action.enabled) == false then
				return
			end
			drag:set(nil)
			menuOpen:set(false)
			setOpen(nil)
			if action.role == "destructive" then
				committing:set({
					action = action,
					edge = (if edge == "leading" then "leading" else "trailing") :: RowEdge,
				})
				if reduced() then
					fired = true
					invoke(action)
				else
					departure:restart()
				end
			else
				invoke(action)
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if use(departure.completed) and not fired then
				local commit = committing:peek()
				if commit then
					fired = true
					invoke(commit.action)
				end
			end
		end)

		local function paintedOffset(use: ComposeTypes.Use): number
			return if use(drag) ~= nil or use(committing) ~= nil or reduced(use) then use(offset) else use(animated)
		end
		local function tray(edge: RowEdge): Frame
			local nativeProps: Types.FrameProps = {
				Name = edge,
				AnchorPoint = V2.new(if edge == "leading" then 0 else 1, 0),
				Position = D2.fromScale(if edge == "leading" then 0 else 1, 0),
				Size = function(use: ComposeTypes.Use)
					return D2.new(0, math.min(bandWidth(edge, use), math.abs(paintedOffset(use))), 1, 0)
				end,
				Visible = function(use: ComposeTypes.Use)
					local x = paintedOffset(use)
					return use(committing) == nil and (if edge == "leading" then x > 0 else x < 0)
				end,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Host.UIListLayout({
					FillDirection = E.FillDirection.Horizontal,
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
						local buttonProps: InputTypes.ButtonProps = {
							Name = current:peek().id,
							LayoutOrder = index,
							Size = function(use: ComposeTypes.Use)
								return D2.new(1 / math.max(1, #actions(edge, use)), 0, 1, 0)
							end,
							AutomaticSize = E.AutomaticSize.None,
							label = function(use: ComposeTypes.Use): string
								return read(use(current).label, use)
							end,
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
						local bounds = ctx.observe(button, "TextBounds")
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
		local activeInput: InputObject?
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
			start, startOffset, axis = position, offset:peek(), nil
			previousX, previousTime, velocity = position.X, now(), 0
		end
		local function move(position: Vector2): ()
			if start == nil or read(spec.enabled) == false then
				return
			end
			local currentTime = now()
			local elapsed = currentTime - previousTime
			if elapsed > 0 then
				velocity = (position.X - previousX) / elapsed
			end
			previousX, previousTime = position.X, currentTime
			local delta = position - start
			if axis == nil and math.max(math.abs(delta.X), math.abs(delta.Y)) >= 8 then
				axis = if math.abs(delta.X) > math.abs(delta.Y) then "horizontal" else "vertical"
			end
			if axis == "horizontal" then
				local maxLeading = if #actions("leading") > 0 then dimensions:peek().X else 0
				local maxTrailing = if #actions("trailing") > 0 then dimensions:peek().X else 0
				drag:set(math.clamp(startOffset + delta.X, -maxTrailing, maxLeading))
			end
		end
		local function finish()
			if read(spec.enabled) == false then
				start, axis = nil, nil
				drag:set(nil)
				return
			end
			local value = drag:peek()
			if value ~= nil and axis == "horizontal" then
				local edge: RowEdge = if value > 0 then "leading" else "trailing"
				local available = actions(edge)
				local fullSwipe = if type(spec.fullSwipe) == "table"
					then spec.fullSwipe[edge] ~= false
					else spec.fullSwipe ~= false
				if fullSwipe and #available > 0 and math.abs(value) >= dimensions:peek().X * 0.7 then
					execute(available[1], edge)
				elseif
					#available > 0
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
		end
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
		local contentMenu = UI.Menu({
			Name = "ContextActions",
			trigger = content,
			items = menuItems,
			isPresented = menuOpen,
			triggers = {},
			Size = D2.fromScale(1, 1),
			AutomaticSize = E.AutomaticSize.None,
			onOpen = function()
				setOpen(nil)
			end,
		})
		root = Host.Frame(ctx.props(spec, behavior, {
			Size = D2.new(1, 0, 0, 44),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			tray("leading") :: ComposeTypes.Child,
			tray("trailing"),
			Host.Frame({
				Name = "Content",
				Size = function(use: ComposeTypes.Use)
					return D2.new(1, if read(spec.editing, use) then -use(editWidth) else 0, 1, 0)
				end,
				BackgroundTransparency = 1,
				Position = function(use: ComposeTypes.Use)
					local gutter = if read(spec.editing, use) then use(editWidth) else 0
					return D2.fromOffset(gutter + paintedOffset(use), 0)
				end,
				contentMenu,
			}),
			Host.UIDragDetector({
				Enabled = function(use: ComposeTypes.Use)
					return use(committing) == nil
						and read(spec.enabled, use) ~= false
						and (#actions("leading", use) + #actions("trailing", use)) > 0
				end,
				DragStyle = E.UIDragDetectorDragStyle.TranslateLine,
				DragAxis = V2.new(1, 0),
				ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
				DragStart = begin,
				DragContinue = move,
				DragEnd = finish,
			}),
		}))
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
		local measured = ctx.observe(root, "AbsoluteSize")
		Compose.watch(function(use: ComposeTypes.Use)
			dimensions:set(use(measured))
		end)
		local function reveal()
			if read(spec.enabled) ~= false and committing:peek() == nil and #menuItems:peek() > 0 then
				setOpen(nil)
				if spec.coordinator then
					spec.coordinator:set(rowToken)
				end
				menuOpen:set(true)
			end
		end

		runtime.connect(root, "InputBegan", function(input: InputObject)
			if input.UserInputType == E.UserInputType.Touch or input.UserInputType == E.UserInputType.MouseButton1 then
				activeInput = input
			end
			if input.UserInputType == E.UserInputType.MouseButton2 then
				reveal()
			end
		end)
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
		runtime.connect(root, "TouchLongPress", function(_: { Vector2 }, state: Enum.UserInputState)
			if state == E.UserInputState.Begin then
				reveal()
			end
		end)
		local gui = ctx.config.guiService
		local selected: ComposeTypes.Cell<GuiObject?> = if gui
			then ctx.observe(gui, "SelectedObject")
			else Compose.cell(nil :: GuiObject?)
		local function eligible(use: ComposeTypes.Use): boolean
			local node = read(selected, use)
			return node ~= nil
				and node:IsDescendantOf(root)
				and read(spec.enabled, use) ~= false
				and read(committing, use) == nil
				and not (node:IsA("TextBox") and node:IsFocused())
		end
		ctx.action(
			root,
			"RowActionsReveal",
			{ E.KeyCode.ButtonX, E.KeyCode.Menu },
			eligible,
			reveal,
			{ priority = 300 }
		)
		ctx.action(root, "RowActionsClose", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use: ComposeTypes.Use)
			return eligible(use) and (read(open, use) ~= nil or use(menuOpen))
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
			return eligible(use) and read(open, use) == nil and not use(menuOpen) and destructive(use) ~= nil
		end, delete, { priority = 300 })
		ctx.action(root, "RowActionsToggle", { E.KeyCode.Return }, function(use: ComposeTypes.Use)
			local input = ctx.config.userInputService
			return eligible(use)
				and input ~= nil
				and (input:IsKeyDown(E.KeyCode.LeftShift) or input:IsKeyDown(E.KeyCode.RightShift))
		end, function()
			if menuOpen:peek() then
				menuOpen:set(false)
			else
				reveal()
			end
		end, { priority = 300 })
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
						local bounds = ctx.observe(button, "TextBounds")
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
				if current and current:IsDescendantOf(root) then
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
