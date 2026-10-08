--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local materialize = require("./materialize")
local ComposeTypes = require("../vendor/compose/core")
local help = require("./help")
local Inputs = require("./input_types")
local placement = require("./overlay_placement")
local parts = require("./overlay_parts")
local motion = require("./motion")
local rest = require("./rest")
local fontReadiness = require("./font_readiness")
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
		local last: ComposeTypes.Cell<Enum.UserInputType>? = nil
		if input and input.GetLastInputType then
			local source = Compose.cell(input:GetLastInputType())
			last = source
			runtime.connect(input, "LastInputTypeChanged", function(value: Enum.UserInputType)
				source:set(value)
			end)
		end
		local preferred = if input and input.GetPropertyChangedSignal then ctx.observe.PreferredInput(input) else nil
		return function(use: ComposeTypes.Use): boolean
			local preference = if preferred then use(preferred) else nil
			if preference == E.PreferredInput.Touch then
				return false
			end
			if preference == E.PreferredInput.Gamepad then
				return true
			end
			local value = if last then use(last) else nil
			return active
				and (value == nil or value == E.UserInputType.Keyboard or string.find(value.Name, "^Gamepad") ~= nil)
		end
	end

	local function preference(): (ComposeTypes.Use) -> number
		local source = if gui and gui.GetPropertyChangedSignal then ctx.observe.PreferredTransparency(gui) else nil
		return function(use: ComposeTypes.Use): number
			local value = if source then use(source) else 1
			return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
		end
	end
	local function keep(...: unknown): ()
		for index = 1, select("#", ...) do
			local content = select(index, ...)
			if content and type(content) ~= "function" then
				local node = content :: Instance
				local parent = node.Parent
				if parent then
					runtime.mount(function()
						return runtime.borrow(node)
					end, parent)
				end
				Compose.cleanup(function()
					if node.Parent ~= nil then
						node.Parent = nil
					end
				end)
			end
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
		if
			node:IsA("GuiObject")
			and node.Visible
			and node.Selectable
			and node.Interactable
			and (not node:IsA("ScrollingFrame") or node:GetAttribute("FacetSelectionOwner") == true)
		then
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
		return if node:IsA("ScrollingFrame")
				and node.Selectable
				and (preferred == nil or node.Name == preferred)
			then node
			else nil
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
						inset(
							if authored.Scale == 0
									and authored.Offset == 0
									and extra == nil
									and (slot == nil or slot == "panel")
								then ctx.metric("space.m", use)
								else authored.Offset,
							name,
							slot,
							use
						) + (if extra then extra(name, use) else 0)
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
	): Nav.Presence
		local level = motion.level(ctx)
		local exiting: ComposeTypes.Readable<boolean> = if phase then phase.exiting else Compose.cell(false)
		local shown = Compose.cell(false)
		local fadeIn, fadeOut = ctx.metric("motion.presentFadeIn"), ctx.metric("motion.presentFadeOut")
		local present, fade = ctx.motionEase("present"), ctx.motionEase("fade")
		local progress = runtime.tween(function(use: ComposeTypes.Use): number
			return if use(exiting) or not use(shown) or (ready ~= nil and not use(ready)) then 0 else 1
		end, {
			seconds = function(_: ComposeTypes.Use): number
				if level() == "limited" then
					return ctx.metric("motion.reducedFade")
				end
				return if exiting:peek() then timing.exit else timing.enter
			end,
			ease = function(t: number): number
				return if level() == "limited" then fade(t) else present(t)
			end,
		})
		shown:set(true)
		local function raw(use: ComposeTypes.Use?): number
			if ready ~= nil and not ctx.read(ready, use) then
				return 0
			end
			return if level(use) == "none" then 1 else ctx.read(progress, use)
		end
		local function travel(use: ComposeTypes.Use?): number
			if ready ~= nil and not ctx.read(ready, use) then
				return 0
			end
			return if level(use) == "normal" then ctx.read(progress, use) else 1
		end
		local last = 0
		type Anchor = { p: number, o: number }
		local anchor: ComposeTypes.Cell<Anchor> = Compose.cell({ p = 0, o = 0 } :: Anchor)
		local function opacity(use: ComposeTypes.Use?): number
			local p = raw(use)
			if level(use) ~= "normal" then
				last = p
				return p
			end
			local from: Anchor = if use then use(anchor) else anchor:peek()
			local value
			if ctx.read(exiting, use) then
				local cleared = 1 - present(fadeOut)
				value = if from.p > cleared
					then from.o * math.clamp((p - cleared) / (from.p - cleared), 0, 1)
					elseif from.p > 0 then from.o * math.clamp(p / from.p, 0, 1)
					else 0
			else
				local opaque = math.max(present(fadeIn), from.p + 1e-3)
				value = from.o + (1 - from.o) * math.clamp((p - from.p) / (opaque - from.p), 0, 1)
			end
			last = value
			return value
		end
		Compose.watch(function(use: ComposeTypes.Use)
			use(exiting)
			anchor:set({ p = raw(), o = last })
		end)
		return { opacity = opacity, travel = travel }
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
		local fontsReady = fontReadiness(ctx, nodes)
		local rested = rest(ctx, function(): (string, boolean, boolean?)
			local parts: { string } = {}
			local filled = false
			local origin = nodes[1].AbsolutePosition
			local descendants = nodes[1]:GetDescendants()
			for _, node in nodes do
				table.insert(descendants, node)
				filled = filled or (node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0)
			end
			for _, node in descendants do
				if node:IsA("GuiObject") then
					local value = `{node.AbsolutePosition - origin}:{node.AbsoluteSize}:{node.Visible}`
					if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
						value ..= `:{node.TextBounds}`
					end
					table.insert(parts, value)
				end
			end
			return table.concat(parts, ";"), filled, nodes[1].Visible and fontsReady()
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
	): (ComposeTypes.Use) -> number
		local settings: Nav.PopoverOptions = options or {}
		local rested = settings.rested
		local rise = settings.rise
		local function scale(use: ComposeTypes.Use): number
			if panel:HasTag("facet-menu") or panel:HasTag("facet-popover") or panel:HasTag("facet-tooltip") then
				return 1
			end
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
					if rise and rise(use) ~= nil then
						return V2.zero
					end
					local _, origin = place(use)
					local box = use(size)
					return V2.new(
						if box.X > 0 then math.clamp(origin.X / box.X, 0, 1) else 0,
						if box.Y > 0 then math.clamp(origin.Y / box.Y, 0, 1) else 0
					)
				end,
				Position = function(use: ComposeTypes.Use)
					local at, origin = place(use)
					local distance = if rise then rise(use) else nil
					return if distance
						then D2.fromOffset(at.X, at.Y + distance * (1 - amount(use)))
						else D2.fromOffset(
							math.round((at.X + origin.X) * 1e4) / 1e4,
							math.round((at.Y + origin.Y) * 1e4) / 1e4
						)
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
		materialize(ctx, panel, assert(settings.geometry), scale, function(use: ComposeTypes.Use)
			local _, point = place(use)
			local box = if settings.size then use(settings.size) else panel.AbsoluteSize
			return V2.new(if box.X > 0 then point.X / box.X else 0.5, if box.Y > 0 then point.Y / box.Y else 0.5)
		end, panel:HasTag("facet-menu") or panel:HasTag("facet-popover") or panel:HasTag("facet-tooltip"))
		return scale
	end
	local function attached(anchor: GuiObject): boolean
		local at: Instance? = anchor
		while at do
			if at:IsA("GuiObject") and not at.Visible then
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
		local level = motion.level(ctx)
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
				local current = level()
				if not shown() or not attached(anchor) or current == "none" then
					return begin(Compose.cell(true), nil)
				end
				local scope = owner.createChild()
				local timeline = Compose.withOwner(scope, function()
					return runtime.timeline({
						duration = if current == "limited" then ctx.metric("motion.reducedFade") else timing.exit,
					})
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
			BorderSizePixel = 0,
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = spec.ZIndex or 100,
			Host.TextButton "DismissOutside" {
				BorderSizePixel = 0,
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
		if catcher and catcher:IsA("GuiObject") and gui then
			local service: GuiService = gui
			local band = ctx.observe.TopbarInset(service)
			local parent = ctx.observe.Parent(root)
			local unit = ctx.layoutUnit(root)
			local expansion = Compose.cell({ near = V2.zero, far = V2.zero, scale = 1 })
			Compose.watch(function(use: ComposeTypes.Use)
				use(band)
				use(parent)
				local scale = math.max(use(unit), 0.001)
				local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
				local inset = screen ~= nil
					and not screen.IgnoreGuiInset
					and screen.ScreenInsets == E.ScreenInsets.CoreUISafeInsets
				local near, far = V2.zero, V2.zero
				if inset then
					local ok, topLeft, bottomRight = pcall(service.GetGuiInset, service)
					if ok and typeof(topLeft) == "Vector2" then
						near = topLeft
						far = if typeof(bottomRight) == "Vector2" then bottomRight else V2.zero
					end
				end
				expansion:set({ near = near, far = far, scale = scale })
			end)
			runtime.decorate(catcher, {
				Position = function(use: ComposeTypes.Use): UDim2
					local value = use(expansion)
					return D2.fromOffset(-value.near.X / value.scale, -value.near.Y / value.scale)
				end,
				Size = function(use: ComposeTypes.Use): UDim2
					local value = use(expansion)
					return D2.new(
						1,
						(value.near.X + value.far.X) / value.scale,
						1,
						(value.near.Y + value.far.Y) / value.scale
					)
				end,
			})
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
				if
					selected ~= nil
					and scopes[#scopes] == root
					and use(mounted)
					and use(rootVisible)
					and not (exiting and use(exiting))
					and not focusIn(use)
				then
					guiService.SelectedObject = nil
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
						if at ~= anchor or anchor:GetAttribute("FacetOverlayPlaceholder") ~= true then
							table.insert(sources, ctx.observe.Visible(at))
						end
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
	local function parent(anchor: Instance): GuiBase2d?
		return (ctx.config.overlayParent or anchor:FindFirstAncestorWhichIsA("LayerCollector")) :: GuiBase2d?
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
			destination:set(parent(anchor))
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
					local function themed(): Instance
						local node = build(phase)
						local scope: Instance? = anchor
						local target = current:peek() :: Instance
						while scope and scope ~= target do
							local link = scope:FindFirstChildWhichIsA("StyleLink")
							if link then
								local observe = (
									ctx.observe :: unknown
								) :: { StyleSheet: (StyleLink) -> ComposeTypes.Cell<StyleSheet?> }
								local sheet = observe.StyleSheet(link :: StyleLink)
								local Links = (Host :: unknown) :: { StyleLink: ({ StyleSheet: unknown }) -> Instance }
								runtime.mountFragment(function()
									return { Links.StyleLink { StyleSheet = sheet } }
								end, node)
								break
							end
							scope = scope.Parent
						end
						return arrive(node)
					end
					return Host.Folder "OverlayPortal" {
						Compose.portal(current:peek(), function()
							if options and options.failure then
								return {
									Host.Folder({
										Compose.boundary(function()
											return themed()
										end, options.failure),
									}),
								}
							end
							return { themed() }
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
				if point == nil or layer == nil or not displayed(anchor) then
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
		attach(anchor, {
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
				local held: ComposeTypes.Cell<Vector2?> = Compose.cell(nil :: Vector2?)
				local panelProps: Types.CanvasGroupNativeProps = {
					Name = plate and plate.name or "Help",
					GroupTransparency = function(use: ComposeTypes.Use)
						return 1 - presence.opacity(use)
					end,
					AutomaticSize = function(use: ComposeTypes.Use)
						return if use(held) then E.AutomaticSize.None else E.AutomaticSize.XY
					end,
					Size = function(use: ComposeTypes.Use)
						local box = use(held)
						return if box then D2.fromOffset(math.ceil(box.X), math.ceil(box.Y)) else D2.fromOffset(0, 0)
					end,
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
				Compose.watch(function(use: ComposeTypes.Use)
					held:set(if use(rested) and presence.travel(use) < 1 then use(measured) else nil)
				end)
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
	return {
		modal = modal,
		skin = skin,
		inset = inset,
		centered = centered,
		attach = attach,
		service = service :: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
		within = within,
		keep = keep,
		firstSelectable = firstSelectable,
		preference = preference,
		selecting = selecting,
		overlay = overlay,
		parent = parent,
		available = available,
		appearance = appearance,
		atRest = atRest,
		popover = popover,
		sheetModal = nil,
	}
end
