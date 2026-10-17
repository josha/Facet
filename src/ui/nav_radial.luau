--!strict
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Navigation = require("./navigation_types")
local ControlTypes = require("./control_types")
local RadialProps = require("./radial_props")
local ComposeTypes = require("../vendor/compose/core")
local createMenu = require("./nav_radial_menu")
local arrangeRing = require("./nav_radial_layout")
local ArrangementTypes = require("./nav_radial_layout")
local MenuTypes = require("./nav_radial_menu")
local paintSectors = require("./nav_radial_sectors")
local buildCenter = require("./nav_radial_center")
local attachGestures = require("./nav_radial_gestures")
local createPresence = require("./nav_overlay_presence")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Navigation.Surfaces)
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local lists = layoutKit.of(ctx)
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local build = function<V>(spec: RadialProps.RadialMenuSpec<V>): Frame
		assert(spec.items, "RadialMenu requires items")
		local menu = createMenu(ctx, surfaces, spec)
		local session = menu.session
		local opened, scrim, skin = menu.opened, menu.scrim, menu.skin
		local cancel, close, open = menu.cancel, menu.close, menu.open
		local back: () -> () = menu.back
		local isPointer = menu.isPointer
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
		local timing = ctx.motionTiming("radial")
		local departure = createPresence(ctx).departure(timing, root, function(): boolean
			return not menu.reduced() and spec.transition ~= false
		end)
		local beginDeparture = assert(departure.exit)
		departure.exit = function(nodes): ComposeTypes.Exiting
			timing.exit = ctx.metric("motion.radial.exit")
			return beginDeparture(nodes)
		end
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
							session.openedByLauncher = opened:peek()
							menu.beginPointer(input, false, true)
						end
					end,
					onActivate = function(input: InputObject?)
						local echo = session.openedByLauncher and input ~= nil and isPointer(input)
						session.openedByLauncher = false
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
				local arrange: (Types.Context, MenuTypes.Menu<V>, Frame) -> ArrangementTypes.Arrangement<V> =
					arrangeRing
				local arrangement = arrange(ctx, menu, root)
				local paint = paintSectors(ctx, UI, surfaces, lists, menu, arrangement, phase)
				local hub = buildCenter(ctx, UI, surfaces, menu, arrangement, paint, root, layoutUnit, phase)
				attachGestures(ctx, surfaces, menu, arrangement, paint, hub)
				local viewport, origin, center, layout, fallback =
					arrangement.viewport,
					arrangement.origin,
					arrangement.center,
					arrangement.layout,
					arrangement.fallback
				local hideLauncher = hub.hideLauncher
				local modal = surfaces.modal(
					function()
						return paint.panel
					end,
					back,
					{
						appearance = function(use: ComposeTypes.Use?): number
							return 1 - if use then paint.transparency(use) else 0
						end,
					}
				)
				modal:SetAttribute("FacetArrivalGroup", true)
				surfaces.attach(modal, { hub.centerHit, hub.centerNode, hub.previewPlate, hub.preview })
				if hideLauncher then
					hideLauncher()
				end
				local catcher = modal:FindFirstChild("Scrim")
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
					local at, size = use(position), use(bounds)
					if size.X > 0 and size.Y > 0 then
						origin:set(at)
					end
				end)
				if spec.centerPassThrough and (spec.center == "empty" or spec.center == "content") then
					runtime.decorate(modal, { Active = fallback })
					if anchorGui then
						surfaces.attach(modal, {
							Compose.show(function(use: ComposeTypes.Use): boolean
								return not use(fallback)
							end, function()
								ctx.modalPortal(anchorGui, modal)
								return Compose.fragment(function()
									return {}
								end)
							end),
						})
					end
					local outside = modal:FindFirstChild("DismissTarget")
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
				presence = departure,
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
				session.held = true
				open()
			end)
			runtime.connect(spec.holdAction, "Released", function()
				if not session.held then
					return
				end
				session.held = false
				local selected = if session.analog and session.candidateSector
					then assert(session.candidateSector)()
					else nil
				if selected then
					menu.nativeActivate(selected, nil, "hold")
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
	UI.RadialMenu = ctx.construct("RadialMenu", build) :: ControlTypes.RadialMenuConstructor
end
