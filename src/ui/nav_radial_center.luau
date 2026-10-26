--!strict
local geometry = require("./nav_radial_geometry")
local placement = require("./overlay_placement")
local Types = require("./types")
local Radial = require("./radial_types")
local Navigation = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local MenuTypes = require("./nav_radial_menu")
local ArrangementTypes = require("./nav_radial_layout")
local PaintTypes = require("./nav_radial_sectors")

export type Hub<V> = {
	showCenter: (use: ComposeTypes.Use) -> boolean,
	centerNode: TextButton,
	centerHit: TextButton,
	hideLauncher: (() -> ())?,
	reachOf: (ring: Radial.Layout<V>) -> number,
	preview: TextLabel,
	previewPlate: Frame,
}

return function<V>(
	ctx: Types.Context,
	UI: MenuTypes.Controls,
	surfaces: Navigation.Surfaces,
	menu: MenuTypes.Menu<V>,
	arrangement: ArrangementTypes.Arrangement<V>,
	paint: PaintTypes.Paint<V>,
	root: Frame,
	layoutUnit: ComposeTypes.ReadOnlyValue<number>,
	phase: Navigation.PresencePhase?
): Hub<V>
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local spec, corner, painted = menu.spec, menu.corner, menu.painted
	local path, candidate, naming, touchPoint = menu.path, menu.candidate, menu.naming, menu.touchPoint
	local preferred = menu.preferred
	local viewport, origin, launcher, anchorSize =
		arrangement.viewport, arrangement.origin, arrangement.launcher, arrangement.anchorSize
	local center, layout, sectors, fallback =
		arrangement.center, arrangement.layout, arrangement.sectors, arrangement.fallback
	local transparency, panel = paint.transparency, paint.panel
	local ringNavigation = spec.center == "empty" or spec.center == "content"
	local function showCenter(use: ComposeTypes.Use): boolean
		if corner and spec.center == "empty" and spec.centerPassThrough and not use(fallback) then
			return false
		end
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
			menu.back()
		elseif spec.center == "root" then
			menu.jump({})
		else
			menu.close()
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
			return D2.new(0.5, use(paint.listWidth) / 2 - painted(use) / 2, 0, 2 + painted(use) / 2)
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
	if launcher and launcher:IsA("GuiObject") then
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
			if phase and corner then
				Compose.watch(function(use: ComposeTypes.Use)
					if use(phase.exiting) then
						show()
					end
				end)
			end
			Compose.cleanup(show)
		end
	end
	if corner and launcher and launcher:IsA("GuiObject") then
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
	if not corner then
		local glyph = centerNode:FindFirstChild("LeadingIcon", true)
		if glyph then
			runtime.decorate(glyph, { ImageTransparency = transparency })
		end
	end
	if spec.center == "content" and spec.centerContent and not corner then
		local node = if type(spec.centerContent) == "function" then spec.centerContent() else spec.centerContent
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
	menu.skin(centerNode, spec.skin and spec.skin.center)
	local panelSize = ctx.observe.AbsoluteSize(panel)
	local function reachOf(ring: Radial.Layout<V>): number
		local reach = ring.inner
		for _, sector in ring.sectors do
			reach = math.max(reach, sector.outer)
		end
		return reach
	end
	local previewBounds = Compose.cell(V2.zero)
	local function previewSize(use: ComposeTypes.Use): Vector2
		local bounds = use(previewBounds)
		return V2.new(
			math.min(240, math.max(0, use(viewport).X - 16), if bounds.X > 0 then math.ceil(bounds.X) else 240),
			math.max(ctx.metric("typography.caption.size", use) + 12, math.ceil(bounds.Y))
		)
	end
	local function previewPlace(use: ComposeTypes.Use): (UDim2, Vector2)
		local ring = use(layout)
		if ring.list then
			return D2.new(0.5, -use(paint.listWidth) / 2, 0, 2), V2.zero
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
			local point = use(touchPoint)
			if near and (point or (preferred and use(preferred) == E.PreferredInput.Touch)) then
				local room = use(viewport)
				local contact = if point then V2.new(point.X, point.Y) - use(origin) else at + V2.new(near.x, near.y)
				local size = previewSize(use)
				local box = placement.touch(
					{ x = contact.X, y = contact.Y },
					{ w = size.X, h = size.Y },
					{ x = 8, y = 8, w = math.max(0, room.X - 16), h = math.max(0, room.Y - 16) },
					ctx.metric("targetSizes.minimum", use) + ctx.metric("space.s", use)
				)
				return D2.fromOffset(box.x + box.w / 2, box.y + box.h), V2.new(0.5, 1)
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
		if use(touchPoint) or preferred and use(preferred) == E.PreferredInput.Touch then
			return math.min(240, math.max(0, use(viewport).X - 16))
		end
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
				return D2.fromOffset(math.max(0, use(paint.listWidth) - 1.5 * painted(use)), 0)
			end
			return D2.fromOffset(0, 0)
		end,
		AutomaticSize = function(use: ComposeTypes.Use)
			return if use(layout).list then E.AutomaticSize.Y else E.AutomaticSize.XY
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
		TextWrapped = true,
		Text = function(use: ComposeTypes.Use)
			if not use(layout).list then
				local key = if use(naming) then use(candidate) else nil
				local entries = use(sectors)
				for sectorIndex = 1, #entries do
					local sector = entries[sectorIndex]
					if sector.key == key and paint.iconic(use, sector) then
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
			return if #labels > 0 then table.concat(labels, " › ") else read(spec.label, use) or "Quick actions"
		end,
		ZIndex = 106,
		ctx.padding(8, 6),
	})
	preview:AddTag("facet-type-caption")
	surfaces.attach(preview, {
		Host.UISizeConstraint {
			MaxSize = function(use: ComposeTypes.Use): Vector2
				return V2.new(if use(layout).list then math.huge else previewWidth(use), math.huge)
			end,
		},
	})
	local textBounds = ctx.layoutSize(preview, layoutUnit)
	Compose.watch(function(use: ComposeTypes.Use)
		local bounds = use(textBounds)
		previewBounds:set(bounds)
		paint.listHeaderHeight:set(bounds.Y)
	end)
	local previewText = ctx.observe.Text(preview)
	local function previewShown(use: ComposeTypes.Use): boolean
		return use(layout).list or use(naming) and use(candidate) ~= nil and use(previewText) ~= ""
	end
	runtime.decorate(preview, { Visible = previewShown })
	local previewPlate = ctx.styled(
		Host.Frame "SelectionPlate" {
			Position = function(use: ComposeTypes.Use): UDim2
				return (previewPlace(use))
			end,
			AnchorPoint = function(use: ComposeTypes.Use): Vector2
				return select(2, previewPlace(use))
			end,
			Size = function(use: ComposeTypes.Use): UDim2
				return D2.fromOffset(previewSize(use).X, previewSize(use).Y)
			end,
			Visible = function(use: ComposeTypes.Use): boolean
				return not use(layout).list and previewShown(use)
			end,
			ZIndex = 105,
		},
		"tooltip"
	)
	return {
		showCenter = showCenter,
		centerNode = centerNode,
		centerHit = centerHit,
		hideLauncher = hideLauncher,
		reachOf = reachOf,
		preview = preview,
		previewPlate = previewPlate,
	}
end
