--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local help = require("./help")
local Inputs = require("./input_types")
local placement = require("./overlay_placement")
local parts = require("./overlay_parts")
local reducedMotion = require("./motion")
local rest = require("./rest")
local scrollLock = require("./scroll_lock")

local HELP_DWELL = 0.45

return function(ctx: Types.Context): Nav.Surfaces
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local services: Types.Services = ctx.config.services or {}
	local function service(name: "GuiService" | "UserInputService"): (GuiService | UserInputService)?
		if name == "GuiService" then
			return services.GuiService or (if game then game:GetService("GuiService") else nil)
		end
		return services.UserInputService or (if game then game:GetService("UserInputService") else nil)
	end
	local gui = service("GuiService") :: GuiService?
	local input = service("UserInputService") :: UserInputService?

	local function selecting(): (ComposeTypes.Use) -> boolean
		local active = gui ~= nil and gui.SelectedObject ~= nil
		if active and input and input.GetLastInputType then
			local last = input:GetLastInputType()
			active = last == E.UserInputType.Keyboard or string.find(last.Name, "^Gamepad") ~= nil
		end
		local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
		return function(use: ComposeTypes.Use): boolean
			return active or (preferred ~= nil and use(preferred) == E.PreferredInput.Gamepad)
		end
	end

	local function preference(): (ComposeTypes.Use) -> number
		local source = if gui and gui.GetPropertyChangedSignal then ctx.observe.PreferredTransparency(gui) else nil
		return function(use: ComposeTypes.Use): number
			local value = if source then use(source) else 1
			return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
		end
	end
	local function within(node: Instance?, ancestor: Instance): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
	end
	local function displayed(node: Instance): boolean
		local at: Instance? = node
		while at and not at:IsA("LayerCollector") do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			end
			at = at.Parent
		end
		return at ~= nil
	end
	local function firstSelectable(node: Instance, preferred: string?): GuiObject?
		if node:IsA("GuiObject") and (not node.Visible or not node.Interactable) then
			return nil
		end
		if node:IsA("GuiObject") and node.Visible and node.Selectable and node.Interactable then
			if preferred == nil or node.Name == preferred then
				return node
			end
		end
		for _, child in node:GetChildren() do
			local found = firstSelectable(child, preferred)
			if found then
				return found
			end
		end
		return nil
	end
	local function attach<N>(node: N & Instance, children: { Types.Child }): N & Instance
		local stop = runtime.mountFragment(function()
			return children
		end, node)
		Compose.cleanup(stop)
		return node
	end
	local function inset(authored: number, side: string, slot: string?, use: ComposeTypes.Use?): number
		local package = ctx.read(ctx.config.theme, use)
		local recipe = if package and package.chrome then package.chrome[slot or "panel"] else nil
		local carve = if recipe then recipe.contentInsets else nil
		if carve == nil then
			return authored
		end
		local value = if side == "top"
			then carve.top
			elseif side == "bottom" then carve.bottom
			elseif side == "left" then carve.left
			else carve.right
		return math.max(authored, value or 0)
	end
	local function skin(panel: GuiObject, slot: string?, options: Nav.PanelSkin?): GuiObject
		local settings: Nav.PanelSkin = options or {}
		local extra = settings.reserve
		ctx.skin(panel, slot or "panel", { label = settings.title, onCaption = settings.onCaption })
		local padding = settings.padding or panel:FindFirstChildWhichIsA("UIPadding")
		if padding and (ctx.config.theme ~= nil or extra) then
			local function side(name: string, authored: UDim): (ComposeTypes.Use) -> UDim
				return function(use: ComposeTypes.Use): UDim
					return ctx.types.UDim.new(
						0,
						inset(authored.Offset, name, slot, use) + (if extra then extra(name, use) else 0)
					)
				end
			end
			runtime.decorate(padding, {
				PaddingTop = side("top", padding.PaddingTop),
				PaddingBottom = side("bottom", padding.PaddingBottom),
				PaddingLeft = side("left", padding.PaddingLeft),
				PaddingRight = side("right", padding.PaddingRight),
			})
		end
		return panel
	end

	local function appearance(
		phase: Nav.PresencePhase?,
		timing: Nav.MotionTiming,
		ready: ComposeTypes.Readable<boolean>?
	): Nav.Appearance
		local reduce = reducedMotion(ctx)
		local exiting: ComposeTypes.Readable<boolean> = if phase then phase.exiting else Compose.cell(false)
		local shown = Compose.cell(false)
		local progress = runtime.tween(function(use: ComposeTypes.Use): number
			return if use(exiting) or not use(shown) or (ready ~= nil and not use(ready)) then 0 else 1
		end, {
			seconds = function(_: ComposeTypes.Use): number
				return if exiting:peek() then timing.exit else timing.enter
			end,
			ease = ctx.motionEase("present"),
		})
		shown:set(true)
		return function(use: ComposeTypes.Use?): number
			if ready ~= nil and not ctx.read(ready, use) then
				return 0
			end
			if reduce(use) then
				return 1
			end
			return ctx.read(progress, use)
		end
	end
	local function atRest(
		amount: Nav.Appearance,
		ready: ComposeTypes.Cell<boolean>,
		nodes: { GuiObject },
		restart: ((ComposeTypes.Use) -> string)?
	): ({ ComposeTypes.Readable<Vector2> }, ComposeTypes.Readable<boolean>)
		local live: { ComposeTypes.Readable<Vector2> } = {}
		for index, node in nodes do
			live[index] = ctx.observe.AbsoluteSize(node)
		end
		local rested = rest(ctx, function(): (string, boolean)
			local parts: { string } = {}
			local filled = false
			for index, size in live do
				local value = size:peek()
				parts[index] = `{value.X},{value.Y}`
				filled = filled or (value.X > 0 and value.Y > 0)
			end
			return table.concat(parts, ";"), filled
		end, restart)
		local held: { ComposeTypes.Readable<Vector2> } = {}
		for index, size in live do
			local natural = Compose.cell(size:peek())
			held[index] = natural
			Compose.watch(function(use: ComposeTypes.Use)
				local value = use(size)
				if not use(rested) or amount(use) >= 1 then
					natural:set(value)
				end
			end)
		end
		Compose.watch(function(use: ComposeTypes.Use)
			if use(rested) then
				ready:set(true)
			end
		end)
		return held, rested
	end
	local function popover(
		panel: GuiObject,
		amount: Nav.Appearance,
		place: (ComposeTypes.Use) -> (Vector2, Vector2),
		options: Nav.PopoverOptions?
	): ()
		local settings: Nav.PopoverOptions = options or {}
		local rested = settings.rested
		local rise = settings.rise
		local function scale(use: ComposeTypes.Use): number
			if (rested and not use(rested)) or (rise and rise(use) ~= nil) then
				return 1
			end
			local from = settings.from or ctx.metric("motion.materialize.anchored", use)
			return from + (1 - from) * amount(use)
		end
		if settings.pinned then
			local size = settings.size or ctx.observe.AbsoluteSize(panel)
			runtime.decorate(panel, {
				AnchorPoint = function(use: ComposeTypes.Use)
					local _, origin = place(use)
					local box = use(size)
					return V2.new(
						if box.X > 0 then math.clamp(origin.X / box.X, 0, 1) else 0,
						if box.Y > 0 then math.clamp(origin.Y / box.Y, 0, 1) else 0
					)
				end,
				Position = function(use: ComposeTypes.Use)
					local at, origin = place(use)
					return D2.fromOffset(at.X + origin.X, at.Y + origin.Y)
				end,
			})
		else
			runtime.decorate(panel, {
				Position = function(use: ComposeTypes.Use)
					local at, origin = place(use)
					local distance = if rise then rise(use) else nil
					if distance then
						return D2.fromOffset(at.X, at.Y + distance * (1 - amount(use)))
					end
					local shrink = 1 - scale(use)
					return D2.fromOffset(at.X + origin.X * shrink, at.Y + origin.Y * shrink)
				end,
			})
		end
		attach(panel, { Host.UIScale "PresentationScale" { Scale = scale } })
	end
	local function attached(anchor: GuiObject): boolean
		local at: Instance? = anchor
		while at do
			if at:IsA("GuiObject") and (not at.Visible or not at.Interactable) then
				return false
			end
			if at:IsA("LayerCollector") then
				return at.Enabled
			end
			at = at.Parent
		end
		return false
	end
	local function departure(
		timing: Nav.MotionTiming,
		anchor: GuiObject,
		shown: () -> boolean
	): ComposeTypes.PresenceOptions
		local reduce = reducedMotion(ctx)
		local owner = assert(Compose.currentOwner())
		type Pending = {
			completed: ComposeTypes.Readable<boolean>,
			scope: ComposeTypes.Owner?,
		}
		local pending: ComposeTypes.Cell<Pending?> = Compose.cell(nil :: Pending?)
		local function release(entry: Pending?)
			if entry and entry.scope then
				entry.scope.dispose()
			end
		end
		Compose.watch(function(use: ComposeTypes.Use)
			local entry = use(pending)
			if entry and use(entry.completed) then
				pending:set(nil)
				release(entry)
			end
		end)
		Compose.cleanup(function()
			release(pending:peek())
		end)
		local function begin(
			completed: ComposeTypes.Readable<boolean>,
			scope: ComposeTypes.Owner?
		): ComposeTypes.Exiting
			release(pending:peek())
			pending:set({ completed = completed, scope = scope })
			return { completed = completed }
		end
		return {
			exit = function()
				if not shown() or not attached(anchor) or reduce() then
					return begin(Compose.cell(true), nil)
				end
				local scope = owner.createChild()
				local timeline = Compose.withOwner(scope, function()
					return runtime.timeline({ duration = timing.exit })
				end)
				return begin(timeline.completed, scope)
			end,
		}
	end

	local function modal(content: () -> GuiObject, dismiss: (string?) -> (), options: Nav.ModalOptions?): Frame
		local spec: Nav.ModalOptions = options or {}
		local exiting = spec.exiting
		local shown = spec.appearance
		local previous = if gui then gui.SelectedObject else nil
		local preferred = preference()
		local focusIn = selecting()
		local panel = content()
		runtime.decorate(panel, {
			SelectionGroup = true,
			SelectionBehaviorUp = E.SelectionBehavior.Stop,
			SelectionBehaviorDown = E.SelectionBehavior.Stop,
			SelectionBehaviorLeft = E.SelectionBehavior.Stop,
			SelectionBehaviorRight = E.SelectionBehavior.Stop,
			ZIndex = spec.ZIndex or 101,
		})
		local root: Frame
		local function near(point: Vector2): boolean
			local boxes: { GuiObject } = { panel }
			if root and root.AbsoluteSize.X > 0 then
				local full = panel.AbsoluteSize.X >= root.AbsoluteSize.X - 1
					and panel.AbsoluteSize.Y >= root.AbsoluteSize.Y - 1
				if full then
					boxes = {}
					for _, child in panel:GetChildren() do
						if child:IsA("GuiObject") and child.Visible then
							table.insert(boxes, child)
						end
					end
				end
			end
			for _, box in boxes do
				local at, size = box.AbsolutePosition, box.AbsoluteSize
				if
					size.X > 0
					and size.Y > 0
					and point.X >= at.X - 24
					and point.X <= at.X + size.X + 24
					and point.Y >= at.Y - 24
					and point.Y <= at.Y + size.Y + 24
				then
					return true
				end
			end
			return false
		end
		local back = function()
			if root and not ctx.available(root) then
				return
			end
			if ctx.read(spec.canDismiss) ~= false then
				dismiss("cancel")
			end
		end
		local props: Types.FrameNativeProps = {
			Name = spec.Name or "Modal",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = spec.ZIndex or 100,
			Host.TextButton "DismissOutside" {
				Size = D2.fromScale(1, 1),
				Active = true,
				Text = "",
				BackgroundTransparency = if spec.backgroundTransparency == nil
					then nil
					else function(use: ComposeTypes.Use)
						local authored = ctx.read(spec.backgroundTransparency, use)
						local value = if type(authored) == "number" then math.clamp(authored, 0, 1) else 1
						local amount = if shown then shown(use) else 1
						return if value >= 1 then 1 else 1 - (1 - value * preferred(use)) * amount
					end,
				BackgroundColor3 = if spec.backgroundTransparency == nil then nil else ctx.types.Color3.new(0, 0, 0),
				AutoButtonColor = false,
				Selectable = false,
				ZIndex = spec.ZIndex or 100,
				Activated = function(input)
					if root and not ctx.available(root) then
						return
					end
					if input and input.Position and near(V2.new(input.Position.X, input.Position.Y)) then
						return
					end
					if ctx.read(spec.outsideDismiss) ~= false and ctx.read(spec.canDismiss) ~= false then
						if spec.onOutside then
							spec.onOutside()
						else
							back()
						end
					end
				end,
			} :: Instance,
			panel,
		}
		if exiting then
			props.Interactable = function(use: ComposeTypes.Use)
				return not use(exiting)
			end
		end
		root = Host.Frame(props)
		local catcher = root:FindFirstChild("DismissOutside")
		if spec.backgroundTransparency == nil and catcher then
			catcher:AddTag("facet-scrim")
			if shown then
				attach(catcher, {
					Host.UIGradient "ScrimFade" {
						Transparency = function(use: ComposeTypes.Use)
							return ctx.types.NumberSequence.new(1 - shown(use))
						end,
					},
				})
			end
		end
		local released = false
		local landed = false
		local owned = false
		local function reclaimable(selected: Instance?): boolean
			if selected == nil or selected.Parent == nil or within(selected, root) then
				return true
			end
			if not owned or selected == previous then
				return false
			end
			for _, scope in ctx.modalScopes:peek() do
				if scope ~= root and within(selected, scope) then
					return false
				end
			end
			return true
		end
		local locked: Instance? = nil
		local function unlock()
			local layer = locked
			locked = nil
			if layer then
				scrollLock.release(layer, root)
			end
		end
		local function lock()
			local layer = if released then nil else root:FindFirstAncestorWhichIsA("LayerCollector")
			if layer == locked then
				return
			end
			unlock()
			if layer then
				locked = layer
				scrollLock.acquire(layer, root)
			end
		end
		runtime.connect(root, "AncestryChanged", lock)
		local function claim()
			local modals = table.clone(ctx.modalScopes:peek())
			table.insert(modals, root)
			ctx.modalScopes:set(modals)
			released = false
			lock()
		end
		claim()
		local function release()
			if released then
				return
			end
			released = true
			unlock()
			local remaining = {}
			for _, modal in ctx.modalScopes:peek() do
				if modal ~= root then
					table.insert(remaining, modal)
				end
			end
			ctx.modalScopes:set(remaining)
			if gui then
				if reclaimable(gui.SelectedObject) then
					gui.SelectedObject = if previous
							and previous.Parent ~= nil
							and not within(previous, root)
						then previous
						else nil
				end
			end
		end
		Compose.cleanup(release)
		if exiting then
			Compose.watch(function(use: ComposeTypes.Use)
				if use(exiting) then
					release()
				elseif released then
					local selected = if gui then gui.SelectedObject else nil
					if selected and not within(selected, root) then
						previous = selected
					end
					claim()
					landed = false
					owned = false
					if gui and selected then
						gui.SelectedObject = firstSelectable(panel, spec.initialFocus) or firstSelectable(panel)
					end
				end
			end)
		end
		ctx.action(
			root,
			"ModalBack",
			{ E.KeyCode.Escape, E.KeyCode.ButtonB },
			true,
			back,
			{ priority = spec.priority or 2000 }
		)
		if gui then
			local guiService: GuiService = gui
			local mounted = ctx.observe.Parent(root)
			local ancestry = Compose.cell(0)
			runtime.connect(root, "AncestryChanged", function()
				ancestry:set(ancestry:peek() + 1)
			end)
			local rootInteractive = ctx.observe.Interactable(root)
			local rootVisible = ctx.observe.Visible(root)
			local panelInteractive = ctx.observe.Interactable(panel)
			Compose.watch(function(use: ComposeTypes.Use)
				if not use(rootInteractive) or not use(panelInteractive) then
					if reclaimable(guiService.SelectedObject) then
						guiService.SelectedObject = if previous
								and previous.Parent ~= nil
								and not within(previous, root)
							then previous
							else nil
					end
				elseif
					use(mounted)
					and use(rootVisible)
					and use(ancestry) >= 0
					and not (exiting and use(exiting))
					and focusIn(use)
					and not within(guiService.SelectedObject, root)
				then
					local target = firstSelectable(panel, spec.initialFocus) or firstSelectable(panel)
					if target and displayed(target) then
						pcall(function()
							guiService.SelectedObject = target
						end)
					end
				end
			end)
			local selection = ctx.observe.SelectedObject(gui)
			local extent = ctx.observe.AbsoluteSize(panel)
			Compose.watch(function(use: ComposeTypes.Use)
				local selected = use(selection) :: Instance?
				use(extent)
				local scopes = use(ctx.modalScopes)
				if within(selected, root) then
					landed = true
					owned = true
					return
				end
				if not released and not (exiting and exiting:peek()) and root.Interactable and panel.Interactable then
					owned = false
				end
				if
					landed
					or scopes[#scopes] ~= root
					or not use(mounted)
					or not use(rootVisible)
					or (exiting and use(exiting))
					or not use(rootInteractive)
					or not use(panelInteractive)
					or not focusIn(use)
				then
					return
				end
				local target = firstSelectable(panel, spec.initialFocus) or firstSelectable(panel)
				if target and target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0 and displayed(target) then
					pcall(function()
						guiService.SelectedObject = target
					end)
				end
			end)
		end
		return root
	end
	local function centered(panel: GuiObject, width: number): GuiObject
		runtime.decorate(panel, {
			AnchorPoint = V2.new(0.5, 0.5),
			Position = D2.fromScale(0.5, 0.5),
			Size = D2.new(1, -32, 0, 0),
			AutomaticSize = E.AutomaticSize.Y,
		})
		attach(panel, { Host.UISizeConstraint({ MaxSize = V2.new(width or 440, math.huge) }) })
		return panel
	end
	local function available(anchor: GuiObject): ComposeTypes.Readable<boolean>
		local owner = assert(Compose.currentOwner())
		local value = Compose.cell(false)
		local ancestryOwner: ComposeTypes.Owner?
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ancestryOwner then
				ancestryOwner.dispose()
				ancestryOwner = nil
			end
			local root: Instance? = anchor
			while root and not root:IsA("LayerCollector") do
				root = root.Parent
			end
			if root == nil then
				value:set(false)
				return
			end
			local nextOwner = owner.createChild()
			ancestryOwner = nextOwner
			Compose.withOwner(nextOwner, function()
				local sources: { ComposeTypes.Readable<boolean> } = {}
				local at: Instance? = anchor
				local attached = false
				while at do
					if at:IsA("GuiObject") then
						table.insert(sources, ctx.observe.Visible(at))
						table.insert(sources, ctx.observe.Interactable(at))
					end
					if at:IsA("LayerCollector") then
						attached = true
						table.insert(sources, ctx.observe.Enabled(at))
						break
					end
					at = at.Parent
				end
				Compose.watch(function(use: ComposeTypes.Use)
					local enabled = attached
					for _, source in sources do
						if not use(source) then
							enabled = false
						end
					end
					value:set(enabled)
				end)
			end)
		end
		runtime.connect(anchor, "AncestryChanged", locate)
		locate()
		return value
	end

	local function arrive(node: Instance): Instance
		local frames = ctx.config.services and ctx.config.services.RunService
		if frames == nil then
			return node
		end
		local surfaces: { GuiObject } = {}
		local parts: { Instance } = if node:IsA("GuiObject") then { node } else node:GetChildren()
		for _, part in parts do
			if part:IsA("GuiObject") and part.Visible then
				part.Visible = false
				table.insert(surfaces, part)
			end
		end
		if #surfaces == 0 then
			return node
		end
		local connection: RBXScriptConnection? = nil
		connection = frames.Heartbeat:Connect(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			for _, surface in surfaces do
				if not surface.Visible then
					surface.Visible = true
				end
			end
		end)
		Compose.cleanup(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end)
		return node
	end
	local function overlay(
		anchor: GuiObject,
		presented: Types.Value<boolean>,
		build: (Nav.PresencePhase?) -> Instance,
		options: Nav.OverlayOptions?
	): Types.Child
		local owner = assert(Compose.currentOwner())
		local enabled = available(anchor)
		local condition = function(use: ComposeTypes.Use): boolean
			return use(enabled) and ctx.read(presented, use)
		end
		local destination = Compose.cell(nil :: Instance?)
		destination:set(ctx.config.overlayParent)
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ctx.config.overlayParent then
				return
			end
			local ancestor = anchor.Parent
			while ancestor do
				if ancestor:IsA("LayerCollector") then
					destination:set(ancestor)
					return
				end
				ancestor = ancestor.Parent
			end
			destination:set(nil)
		end
		runtime.connect(anchor, "AncestryChanged", locate)
		locate()
		return Compose.keyed({
			from = function(use: ComposeTypes.Use)
				local target = use(destination)
				return if target then { target } else {}
			end,
			render = function(current)
				local age: ComposeTypes.Readable<number>? = nil
				local function render(phase: Nav.PresencePhase?): Folder
					if phase then
						age = runtime.timeline({ duration = 0.001 }).elapsed
					end
					return Host.Folder "OverlayPortal" {
						Compose.portal(current:peek(), function()
							if options and options.failure then
								return {
									Host.Folder({
										Compose.boundary(function()
											return arrive(build(phase))
										end, options.failure),
									}),
								}
							end
							return { arrive(build(phase)) }
						end),
					}
				end
				local presence = if options and options.presence
					then options.presence
					elseif options and options.motion then departure(options.motion, anchor, function(): boolean
						local elapsed = age
						return elapsed ~= nil and elapsed:peek() > 0
					end)
					else nil
				local function presentation(): Folder
					return Host.Folder "Presentation" {
						if presence
							then Compose.presence(condition, render, presence)
							else Compose.show(condition, render),
					}
				end
				local identity = options and options.identity
				if identity then
					return Host.Folder "Presentations" {
						Compose.keyed({
							from = function(use: ComposeTypes.Use)
								return { identity(use) }
							end,
							render = presentation,
						}),
					}
				end
				return presentation()
			end,
		})
	end
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
		local function press(phase: Enum.UserInputState)
			if phase == E.UserInputState.Begin and ctx.read(gate) ~= false then
				held:set(true)
				help.hold(anchor, true)
			end
		end
		if anchor:IsA("GuiButton") then
			runtime.connect(anchor, "TouchLongPress", function(_: { Vector2 }, phase: Enum.UserInputState)
				press(phase)
			end)
		elseif input then
			runtime.connect(input, "TouchLongPress", function(points: { Vector2 }, phase: Enum.UserInputState)
				local point: Vector2? = points[1]
				local layer = anchor:FindFirstAncestorWhichIsA("ScreenGui")
				if point == nil or layer == nil or not displayed(anchor) then
					return
				end
				local offset = if layer.IgnoreGuiInset and gui then gui:GetGuiInset() else V2.zero
				local at, size = anchor.AbsolutePosition - offset, anchor.AbsoluteSize
				if point.X >= at.X and point.X <= at.X + size.X and point.Y >= at.Y and point.Y <= at.Y + size.Y then
					press(phase)
				end
			end)
		end
		runtime.connect(anchor, "InputBegan", function()
			help.hold(anchor, false)
		end)
		if input then
			runtime.connect(input, "InputBegan", function(event: InputObject)
				if held:peek() and event.UserInputType == E.UserInputType.Touch then
					held:set(false)
				end
			end)
		end
		local wanted = Compose.formula(function(use: ComposeTypes.Use): boolean
			local kind = if preferred then use(preferred) else nil
			if kind == E.PreferredInput.Touch then
				return false
			end
			local selected = if selection then use(selection) else nil
			return use(state) == E.GuiState.Hover
				or (selected ~= nil and (selected == anchor or anchor:IsDescendantOf(selected)))
		end)
		local rest = runtime.timeline({ duration = HELP_DWELL, autoplay = false })
		Compose.watch(function(use: ComposeTypes.Use)
			if use(wanted) then
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
		attach(anchor, {
			overlay(anchor, armed, function(phase: Nav.PresencePhase?)
				local settled = Compose.cell(false)
				local amount = appearance(phase, timing, settled)
				local layer: GuiBase2d = ctx.config.overlayParent :: GuiBase2d?
					or assert(anchor:FindFirstAncestorWhichIsA("LayerCollector"))
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
				local held: ComposeTypes.Cell<Vector2?> = Compose.cell(nil :: Vector2?)
				local panelProps: Types.CanvasGroupNativeProps = {
					Name = plate and plate.name or "Help",
					GroupTransparency = function(use: ComposeTypes.Use)
						return 1 - amount(use)
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if use(held) then E.AutomaticSize.None else E.AutomaticSize.XY
					end,
					Size = function(use: ComposeTypes.Use)
						local box = use(held)
						return if box then D2.fromOffset(box.X, box.Y) else D2.fromOffset(0, 0)
					end,
					ZIndex = 96,
				}
				table.insert(panelProps, ctx.padding(8, 6))
				table.insert(
					panelProps,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = ctx.types.UDim.new(0, 4) })
				)
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
					table.insert(panelProps, heading)
				end
				runtime.decorate(label, {
					LayoutOrder = 2,
					Visible = function(use: ComposeTypes.Use)
						return (ctx.read(text, use) or "") ~= ""
					end,
				})
				table.insert(panelProps, label)
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
					table.insert(panelProps, hint)
				end
				local panel = ctx.fade(panelProps)
				local sizes, rested = atRest(amount, settled, { panel })
				local measured = sizes[1]
				Compose.watch(function(use: ComposeTypes.Use)
					held:set(if use(rested) and amount(use) < 1 then use(measured) else nil)
				end)
				local edge = if structured and structured.edge then structured.edge else "top"
				local align = if structured and structured.align then structured.align else "center"
				local solution = Compose.formula(function(use: ComposeTypes.Use): placement.Placement
					local anchorAt, anchorSize, offer, offset, box =
						use(at), use(bounds), use(extent), use(origin), use(measured)
					local side = parts.tailSize(ctx, use)
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
				popover(panel, amount, function(use: ComposeTypes.Use): (Vector2, Vector2)
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
				end, { pinned = true, rested = rested, size = measured })
				ctx.styled(panel, "tooltip")
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
					amount,
					function()
						return 96
					end,
					{
						node = panel,
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
				return Host.Folder "HelpOverlay" { panel :: Instance, tail[1] }
			end, { motion = timing }),
		})
	end)
	return {
		modal = modal,
		skin = skin,
		inset = inset,
		centered = centered,
		attach = attach,
		service = service :: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
		within = within,
		firstSelectable = firstSelectable,
		preference = preference,
		selecting = selecting,
		overlay = overlay,
		available = available,
		appearance = appearance,
		atRest = atRest,
		popover = popover,
		sheetModal = nil,
	}
end
