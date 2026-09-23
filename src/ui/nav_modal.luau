--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Core = require("../vendor/compose/core")

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
	local function within(node: Instance?, ancestor: Instance): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
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
	local function skin(panel: GuiObject, slot: string?): GuiObject
		local _, art = ctx.skin(panel, slot or "panel")
		if art and panel:FindFirstChildWhichIsA("UIListLayout") then
			local decoration = Host.Folder({ Name = "Chrome" })
			attach(panel, { decoration })
			art.Parent = decoration
		end
		return panel
	end

	local function modal(content: () -> GuiObject, dismiss: (string?) -> (), options: Nav.ModalOptions?): Frame
		local spec: Nav.ModalOptions = options or {}
		local previous = if gui then gui.SelectedObject else nil
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
			ZIndex = spec.ZIndex or 100,
			Host.TextButton({
				Name = "DismissOutside",
				Size = D2.fromScale(1, 1),
				Text = "",
				BackgroundTransparency = spec.backgroundTransparency or 0.35,
				BackgroundColor3 = ctx.types.Color3.new(0, 0, 0),
				AutoButtonColor = false,
				Selectable = false,
				ZIndex = spec.ZIndex or 100,
				Activated = function(input)
					if root and not ctx.available(root) then
						return
					end
					if input and input.Position and panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.Y > 0 then
						local point, at, size = input.Position, panel.AbsolutePosition, panel.AbsoluteSize
						if
							point.X >= at.X - 24
							and point.X <= at.X + size.X + 24
							and point.Y >= at.Y - 24
							and point.Y <= at.Y + size.Y + 24
						then
							return
						end
					end
					if ctx.read(spec.outsideDismiss) ~= false and ctx.read(spec.canDismiss) ~= false then
						if spec.onOutside then
							spec.onOutside()
						else
							back()
						end
					end
				end,
			}) :: Instance,
			panel,
		}
		root = Host.Frame(props)
		local modals = table.clone(ctx.modalScopes:peek())
		table.insert(modals, root)
		ctx.modalScopes:set(modals)
		Compose.cleanup(function()
			local remaining = {}
			for _, modal in ctx.modalScopes:peek() do
				if modal ~= root then
					table.insert(remaining, modal)
				end
			end
			ctx.modalScopes:set(remaining)
		end)
		ctx.action(
			root,
			"ModalBack",
			{ E.KeyCode.Escape, E.KeyCode.ButtonB },
			true,
			back,
			{ priority = spec.priority or 2000 }
		)
		if gui then
			local mounted = ctx.observe(root, "Parent")
			Compose.watch(function(use: Core.Use)
				if use(mounted) then
					gui.SelectedObject = firstSelectable(panel, spec.initialFocus) or firstSelectable(panel)
				end
			end)
			Compose.cleanup(function()
				if within(gui.SelectedObject, root) or gui.SelectedObject == nil then
					gui.SelectedObject = if previous and previous.Parent ~= nil then previous else nil
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
	local function available(anchor: GuiObject): Core.Readable<boolean>
		local owner = assert(Compose.currentOwner())
		local value = Compose.cell(false)
		local ancestryOwner: Core.Owner?
		local function locate()
			if owner.isDisposed() then
				return
			end
			if ancestryOwner then
				ancestryOwner.dispose()
			end
			local nextOwner = owner.createChild()
			ancestryOwner = nextOwner
			Compose.withOwner(nextOwner, function()
				local sources: { Core.Readable<boolean> } = {}
				local at: Instance? = anchor
				local attached = false
				while at do
					if at:IsA("GuiObject") then
						table.insert(sources, ctx.observe(at, "Visible"))
						table.insert(sources, ctx.observe(at, "Interactable"))
					end
					if at:IsA("LayerCollector") then
						attached = true
						table.insert(sources, ctx.observe(at, "Enabled"))
						break
					end
					at = at.Parent
				end
				Compose.watch(function(use: Core.Use)
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

	local function overlay(
		anchor: GuiObject,
		presented: Types.Value<boolean>,
		build: (Nav.PresencePhase?) -> Instance,
		options: Nav.OverlayOptions?
	): Types.Child
		local owner = assert(Compose.currentOwner())
		local enabled = available(anchor)
		local condition = function(use: Core.Use): boolean
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
			from = function(use: Core.Use)
				local target = use(destination)
				return if target then { target } else {}
			end,
			render = function(current)
				local function render(phase: Nav.PresencePhase?): Folder
					return Host.Folder({
						Name = "OverlayPortal",
						Compose.portal(current:peek(), function()
							if options and options.failure then
								return {
									Host.Folder({
										Compose.boundary(function()
											return build(phase)
										end, options.failure),
									}),
								}
							end
							return { build(phase) }
						end),
					})
				end
				return Host.Folder({
					Name = "Presentation",
					if options and options.presence
						then Compose.presence(condition, render, options.presence)
						else Compose.show(condition, render),
				})
			end,
		})
	end
	return {
		modal = modal,
		skin = skin,
		centered = centered,
		attach = attach,
		service = service :: (("GuiService") -> GuiService?) & (("UserInputService") -> UserInputService?),
		within = within,
		firstSelectable = firstSelectable,
		overlay = overlay,
		available = available,
	}
end
