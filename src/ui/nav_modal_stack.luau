--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local scrollLock = require("./scroll_lock")
local surfaceKit = require("./nav_surface_kit")
local modalInput = require("./nav_modal_input")
local glass = require("./glass")

export type Modal = (() -> GuiObject, (string?) -> (), Nav.ModalOptions?) -> Frame
local touchControls = (
	setmetatable({}, { __mode = "k" }) :: unknown
) :: { [GuiService]: { count: number, enabled: boolean } }

return function(ctx: Types.Context, kit: surfaceKit.Kit): Modal
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local gui = kit.gui
	local within, displayed, firstSelectable = kit.within, kit.displayed, kit.firstSelectable
	local function modal(content: () -> GuiObject, dismiss: (string?) -> (), options: Nav.ModalOptions?): Frame
		local spec: Nav.ModalOptions = options or {}
		local exiting = spec.exiting
		local shown = spec.appearance
		local previous = if gui then gui.SelectedObject else nil
		local preferred = kit.preference()
		local focusIn = kit.selecting()
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
			local margin = spec.outsideMargin or 24
			local boxes: { GuiObject } = { panel }
			if root and root.AbsoluteSize.X > 0 then
				local full = panel.AbsoluteSize.X >= root.AbsoluteSize.X - 1
					and panel.AbsoluteSize.Y >= root.AbsoluteSize.Y - 1
				if full then
					boxes = {}
					for _, child in panel:GetChildren() do
						if child:IsA("GuiObject") and child.Visible and child.Name ~= "OutlineFade" then
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
					and point.X >= at.X - margin
					and point.X <= at.X + size.X + margin
					and point.Y >= at.Y - margin
					and point.Y <= at.Y + size.Y + margin
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
			Host.Frame "Scrim" {
				BorderSizePixel = 0,
				Size = D2.fromScale(1, 1),
				Active = false,
				BackgroundTransparency = if spec.backgroundTransparency == nil
					then nil
					else function(use: ComposeTypes.Use)
						local authored = ctx.read(spec.backgroundTransparency, use)
						local value = if type(authored) == "number" then math.clamp(authored, 0, 1) else 1
						local amount = if shown then shown(use) else 1
						return if value >= 1 then 1 else 1 - (1 - value * preferred(use)) * amount
					end,
				BackgroundColor3 = if spec.backgroundTransparency == nil then nil else ctx.types.Color3.new(0, 0, 0),
				Selectable = false,
				ZIndex = spec.ZIndex or 100,
			} :: Instance,
			Host.TextButton "DismissTarget" {
				BorderSizePixel = 0,
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Active = true,
				Text = "",
				AutoButtonColor = false,
				Selectable = false,
				Interactable = true,
				ZIndex = spec.ZIndex or 100,
				Activated = function(input)
					if
						input
						and input.UserInputType
						and input.UserInputType ~= E.UserInputType.MouseButton1
						and input.UserInputType ~= E.UserInputType.Touch
					then
						return
					end
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
		glass.hold(ctx, root)
		local catcher = root:FindFirstChild("Scrim")
		if spec.backgroundTransparency == nil and catcher then
			catcher:AddTag("facet-scrim")
			if shown then
				kit.attach(catcher, {
					Compose.show(function(use: ComposeTypes.Use): boolean
						return shown(use) < 1
					end, function()
						return Host.UIGradient "ScrimFade" {
							Transparency = function(use: ComposeTypes.Use)
								return ctx.types.NumberSequence.new(1 - shown(use))
							end,
						}
					end),
				})
			end
		end
		if catcher and catcher:IsA("GuiObject") and gui then
			local service: GuiService = gui
			local band = ctx.observe.TopbarInset(service)
			local parent = ctx.observe.Parent(root)
			local bounds = ctx.observe.AbsoluteSize(root)
			local unit = ctx.layoutUnit(root)
			local expansion = Compose.cell({ near = V2.zero, far = V2.zero, scale = 1 })
			Compose.watch(function(use: ComposeTypes.Use)
				use(band)
				use(parent)
				use(bounds)
				local scale = math.max(use(unit), 0.001)
				local screen = root:FindFirstAncestorWhichIsA("ScreenGui")
				local near, far = V2.zero, V2.zero
				if screen then
					near, far = glass.bands(ctx, service, screen)
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
		local heldTouch: GuiService? = nil
		local function holdTouch()
			if gui == nil or heldTouch ~= nil then
				return
			end
			local lease = touchControls[gui]
			if lease == nil then
				lease = { count = 0, enabled = gui.TouchControlsEnabled }
				touchControls[gui] = lease
			end
			lease.count += 1
			heldTouch = gui
			gui.TouchControlsEnabled = false
		end
		local function releaseTouch()
			local service = heldTouch
			heldTouch = nil
			if service then
				local lease = touchControls[service]
				if lease then
					lease.count -= 1
					if lease.count == 0 then
						touchControls[service] = nil
						service.TouchControlsEnabled = lease.enabled
					end
				end
			end
		end
		local function entryTarget(): GuiObject?
			local chosen = if spec.entry then spec.entry() else nil
			if chosen and displayed(chosen) then
				return chosen
			end
			return firstSelectable(panel, spec.initialFocus) or firstSelectable(panel)
		end
		local provisional = Compose.cell(nil :: GuiObject?)
		local function settleEntry(target: GuiObject?)
			local chosen = if spec.entry and target then spec.entry() else nil
			provisional:set(if spec.entry and target and chosen ~= target then target else nil)
		end
		local landed = false
		local owned = false
		local lastSelection: Instance? = nil
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
		local relocateInput: () -> () = function() end
		local function lock()
			local layer = if released then nil else root:FindFirstAncestorWhichIsA("LayerCollector")
			if layer == locked then
				return
			end
			relocateInput()
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
			holdTouch()
			lock()
		end
		claim()
		local releaseInput, locateInput = modalInput.acquire(ctx, root)
		relocateInput = locateInput
		Compose.cleanup(releaseInput)
		local function release()
			if released then
				return
			end
			released = true
			releaseTouch()
			unlock()
			local remaining = {}
			for _, modal in ctx.modalScopes:peek() do
				if modal ~= root then
					table.insert(remaining, modal)
				end
			end
			modalInput.release(root)
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
						local target = entryTarget()
						gui.SelectedObject = target
						settleEntry(target)
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
		if gui and spec.entry then
			local guiService: GuiService = gui
			local entry = spec.entry
			local descendants = Compose.cell(0)
			local selection = ctx.observe.SelectedObject(guiService)
			runtime.connect(panel, "DescendantAdded", function()
				descendants:set(descendants:peek() + 1)
			end)
			Compose.watch(function(use: ComposeTypes.Use)
				use(descendants)
				use(selection)
				local held = use(provisional)
				if held == nil then
					return
				end
				if guiService.SelectedObject ~= held then
					provisional:set(nil)
					return
				end
				local scopes = use(ctx.modalScopes)
				if
					scopes[#scopes] ~= root
					or (exiting and use(exiting))
					or not use(ctx.observe.Interactable(root))
					or not use(ctx.observe.Interactable(panel))
				then
					return
				end
				local better = entry()
				if better and better ~= held then
					local size = use(ctx.observe.AbsoluteSize(better))
					local parent = use(ctx.observe.Parent(better))
					if parent and size.X > 0 and size.Y > 0 and displayed(better) then
						guiService.SelectedObject = better
						if guiService.SelectedObject == better then
							provisional:set(nil)
						end
					end
				end
			end)
		end
		if gui then
			local guiService: GuiService = gui
			if kit.input then
				runtime.connect(kit.input, "LastInputTypeChanged", function(value: Enum.UserInputType)
					if
						value == E.UserInputType.MouseMovement
						or value == E.UserInputType.MouseButton1
						or value == E.UserInputType.Touch
					then
						if within(guiService.SelectedObject, root) then
							lastSelection = nil
							guiService.SelectedObject = nil
						end
					end
				end)
			end
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
					local target = entryTarget()
					if target and displayed(target) then
						pcall(function()
							guiService.SelectedObject = target
						end)
						settleEntry(target)
					end
				end
			end)
			local selection = ctx.observe.SelectedObject(gui)
			local extent = ctx.observe.AbsoluteSize(panel)
			local landing = runtime.settled({
				ready = function(): boolean
					local target = entryTarget()
					return landed
						or (
							target ~= nil
							and target.AbsoluteSize.X > 0
							and target.AbsoluteSize.Y > 0
							and displayed(target)
						)
				end,
				sample = function(): Vector2
					local target = entryTarget()
					return if target then target.AbsoluteSize else V2.zero
				end,
			})
			Compose.watch(function(use: ComposeTypes.Use)
				local selected = use(selection) :: Instance?
				use(extent)
				use(landing)
				local scopes = use(ctx.modalScopes)
				local usable = true
				local at = selected or lastSelection
				while at and at ~= root do
					if at:IsA("GuiObject") then
						local visible = use(ctx.observe.Visible(at))
						local interactable = use(ctx.observe.Interactable(at))
						usable = usable and visible and interactable
					end
					at = use(ctx.observe.Parent(at)) :: Instance?
				end
				if within(selected, root) then
					local replaced = lastSelection ~= nil and lastSelection ~= selected and not displayed(lastSelection)
					landed = true
					owned = true
					lastSelection = selected
					if
						replaced
						and scopes[#scopes] == root
						and use(rootInteractive)
						and use(panelInteractive)
						and not (exiting and use(exiting))
						and focusIn(use)
					then
						settleEntry(selected :: GuiObject)
					end
					if
						not usable
						and scopes[#scopes] == root
						and use(rootInteractive)
						and use(panelInteractive)
						and not (exiting and use(exiting))
					then
						gui.SelectedObject = if focusIn(use) then entryTarget() else nil
					end
					return
				end
				local lost = if selected
					then not displayed(selected)
					else lastSelection ~= nil and not displayed(lastSelection)
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
					(landed and not lost)
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
				local target = entryTarget()
				if target and target.AbsoluteSize.X > 0 and target.AbsoluteSize.Y > 0 and displayed(target) then
					pcall(function()
						guiService.SelectedObject = target
					end)
					settleEntry(target)
				end
			end)
		end
		return root
	end
	return modal
end
