--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local Nav = require("./navigation_types")
local InputProps = require("./input_props")
local Kit = require("./color_picker_kit")
local PickerState = require("./color_picker_state")
local Panel = require("./color_picker_panel")

type Use = ComposeTypes.Use
type PanelView = Panel.PanelView
type Spec = InputProps.ColorPickerProps
type Placement = { edge: string, x: number, y: number, w: number, h: number }

local CELL, GAP, PAD, MARGIN, MAX_COLUMNS = Kit.CELL, Kit.GAP, Kit.PAD, Kit.MARGIN, Kit.MAX_COLUMNS

return function(
	ctx: Shared.Context,
	UI: Kit.Deps,
	surfaces: Nav.Surfaces,
	kit: Kit.Kit,
	state: PickerState.State,
	panelView: Panel.Panel,
	rootProps: Spec
): Frame
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local chrome = kit.chrome
	local spec, labelled, placement, columns = state.spec, state.labelled, state.placement, state.columns
	local enabled, touch, presented, requestPresented, close =
		state.enabled, state.touch, state.presented, state.requestPresented, state.close

	local function panelWidth(use: Use, offer: Vector2, sheet: boolean, tenFoot: boolean): number
		local wide = MAX_COLUMNS * state.cellSize(use)
			+ (MAX_COLUMNS - 1) * GAP
			+ surfaces.inset(PAD, "left", nil, use)
			+ surfaces.inset(PAD, "right", nil, use)
		if sheet then
			return if tenFoot
				then (if offer.X > 0 then math.min(wide, offer.X - 2 * PAD) else wide)
				else offer.X - 2 * PAD
		end
		return if offer.X > 0 then math.min(wide, math.max(CELL, offer.X - 2 * MARGIN)) else wide
	end

	local function place(
		use: Use,
		view: PanelView,
		sheet: (Use) -> boolean,
		extent: ComposeTypes.Readable<Vector2>,
		origin: ComposeTypes.Readable<Vector2>,
		at: ComposeTypes.Readable<Vector2>,
		bounds: ComposeTypes.Readable<Vector2>,
		tenFoot: boolean
	): Placement
		local offer = use(extent)
		local corner = use(at) - use(origin)
		local size = use(bounds)
		if offer.X > 0 and offer.Y > 0 then
			corner = V2.new(
				math.clamp(corner.X, 0, math.max(0, offer.X - size.X)),
				math.clamp(corner.Y, 0, math.max(0, offer.Y - size.Y))
			)
		end
		local natural = view.chrome(use) + view.tech(use)
		local w = panelWidth(use, offer, sheet(use), tenFoot)
		if sheet(use) then
			local h = if offer.Y > 0 then math.min(natural, offer.Y - 2 * PAD) else natural
			if tenFoot then
				return {
					edge = "center",
					x = math.max(PAD, (offer.X - w) / 2),
					y = math.max(PAD, (offer.Y - h) / 2),
					w = w,
					h = h,
				}
			end
			return { edge = "sheet", x = PAD, y = math.max(PAD, offer.Y - h - PAD), w = w, h = h }
		end
		local below = offer.Y - (corner.Y + size.Y + GAP) - MARGIN
		local above = corner.Y - GAP - MARGIN
		local x = math.clamp(corner.X, MARGIN, math.max(MARGIN, offer.X - w - MARGIN))
		if natural <= below then
			return { edge = "bottom", x = x, y = corner.Y + size.Y + GAP, w = w, h = natural }
		end
		if natural <= above then
			return { edge = "top", x = x, y = corner.Y - GAP - natural, w = w, h = natural }
		end
		local right = corner.X + size.X + GAP + w <= offer.X - MARGIN
		local left = corner.X - GAP - w >= MARGIN
		if right or left then
			local h = math.min(natural, math.max(2 * CELL, offer.Y - 2 * MARGIN))
			local y = math.clamp(corner.Y, MARGIN, math.max(MARGIN, offer.Y - h - MARGIN))
			return {
				edge = if right then "right" else "left",
				x = if right then corner.X + size.X + GAP else corner.X - GAP - w,
				y = y,
				w = w,
				h = h,
			}
		end
		if below >= above then
			return { edge = "bottom", x = x, y = corner.Y + size.Y + GAP, w = w, h = math.max(2 * CELL, below) }
		end
		local h = math.max(2 * CELL, above)
		return { edge = "top", x = x, y = corner.Y - GAP - h, w = w, h = h }
	end

	local root: Frame
	local parts: { Shared.Child } = {}
	if labelled then
		table.insert(
			parts,
			ctx.text({
				Name = "Title",
				Text = function(use: Use)
					return chrome.labelText(spec, use)
				end,
				Size = D2.new(0, 0, 0, 0),
				AutomaticSize = E.AutomaticSize.XY,
				TextTruncate = E.TextTruncate.AtEnd,
				Host.UIFlexItem({ FlexMode = E.UIFlexMode.Fill }) :: Shared.Child,
			})
		)
	end
	local edge = if labelled then 24 else 32
	table.insert(parts, kit.swatch("Swatch", D2.fromOffset(edge, edge), state.currentPaint))
	if labelled then
		table.insert(
			parts,
			ctx.styled(
				ctx.text({
					Name = "Value",
					Text = function(use: Use)
						return state.valueText(use)
					end,
					TextTruncate = E.TextTruncate.AtEnd,
				}),
				"secondary"
			)
		)
		table.insert(parts, ctx.icon("chevron.down", { Name = "Chevron" }))
	end
	local row = ctx.row(parts, {
		Name = "Row",
		Size = if labelled then D2.fromScale(1, 1) else D2.fromOffset(0, 0),
		AutomaticSize = if labelled then E.AutomaticSize.None else E.AutomaticSize.XY,
		ctx.padding(if labelled then 10 else 6, 0) :: Shared.Child,
	})
	local layout = assert(row:FindFirstChildWhichIsA("UIListLayout"))
	layout.VerticalAlignment = E.VerticalAlignment.Center
	layout.HorizontalAlignment = if labelled then E.HorizontalAlignment.Left else E.HorizontalAlignment.Center
	local well = UI.Button("Well")({
		name = function(use: Use): string
			return state.semanticName(use)
		end,
		appearance = if labelled then nil else "utility",
		enabled = function(use: Use): boolean
			return enabled(use)
		end,
		Size = function(use: Use)
			local height = math.max(CELL, (ctx.controlSize(spec.controlSize, "height", use)))
			return if labelled then D2.new(1, 0, 0, height) else D2.fromOffset(CELL, CELL)
		end,
		AutomaticSize = E.AutomaticSize.None,
		onActivate = function()
			requestPresented(true)
		end,
		row,
	})
	if labelled then
		chrome.paint("ColorPicker", well, spec)
	end
	if spec.hint ~= nil or spec.errorText ~= nil then
		root = chrome.wrap({
			control = "ColorPicker",
			spec = { hint = spec.hint, errorText = spec.errorText },
			plate = well,
			focus = function()
				requestPresented(true)
			end,
			enabled = enabled,
			native = rootProps,
		})
	else
		root = ctx.column({ well }, rootProps)
	end
	local anchorAvailable = surfaces.available(well)
	local anchorSeen = false
	Compose.watch(function(use: Use)
		if use(anchorAvailable) then
			anchorSeen = true
		elseif anchorSeen and presented() then
			close("anchorLost")
		end
	end)
	surfaces.attach(root, {
		surfaces.overlay(well, presented, function()
			local layer = surfaces.parent(well)
			local extent = if layer then ctx.observe.AbsoluteSize(layer) else Compose.cell(V2.zero)
			local origin = if layer then ctx.observe.AbsolutePosition(layer) else Compose.cell(V2.zero)
			local at, bounds = ctx.observe.AbsolutePosition(well), ctx.observe.AbsoluteSize(well)
			local tenFoot = ctx.tenFoot()
			local function sheet(use: Use): boolean
				local offer = use(extent)
				return tenFoot(use) or (touch(use) and offer.X > 0 and offer.X < 600)
			end
			local room = Compose.cell(math.huge)
			local width = Compose.formula(function(use: Use): number
				local offer = use(extent)
				return if offer.X > 0 then panelWidth(use, offer, sheet(use), tenFoot(use)) else 0
			end)
			local view = panelView(true, sheet, room, width:peek())
			local where = Compose.formula(function(use: Use): Placement
				return place(use, view, sheet, extent, origin, at, bounds, tenFoot(use))
			end)
			Compose.watch(function(use: Use)
				local spot = use(where)
				room:set(spot.h - view.chrome(use))
				placement:set(spot.edge)
			end)
			Compose.cleanup(function()
				placement:set("closed")
			end)
			runtime.decorate(view.panel, {
				Size = function(use: Use)
					local spot = use(where)
					return D2.fromOffset(spot.w, spot.h)
				end,
				Position = function(use: Use)
					local spot = use(where)
					return D2.fromOffset(spot.x, spot.y)
				end,
				Attributes = {
					placement = function(use: Use): string
						return use(where).edge
					end,
				} :: Shared.Attributes,
			})
			local complete = false
			local settled = ctx.runtime.settled {
				sample = function(): string
					local spot = where:peek()
					local technique = view.panel:FindFirstChild("Technique", true) :: GuiObject
					local size = technique.AbsoluteSize
					local modes = view.panel:FindFirstChild("Modes", true)
					local strip = if modes then modes:FindFirstChildWhichIsA("UIListLayout", true) else nil
					local wrapped = true
					local rows = ""
					if modes and modes:IsA("GuiObject") and strip then
						local picker = strip.Parent
						local held = if picker and picker:IsA("GuiObject") then picker.AbsoluteSize.Y else 0
						wrapped = strip.AbsoluteContentSize.Y <= held + 1
						rows = `{strip.AbsoluteContentSize.Y}:{held}`
					end
					local position, bounds = view.panel.AbsolutePosition, view.panel.AbsoluteSize
					complete = wrapped and size.X > 0 and size.Y > 0 and spot.w > 0 and spot.h > 0
					return `{spot.x}:{spot.y}:{spot.w}:{spot.h}:{columns:peek()}:{size}:{rows}:{position}:{bounds}`
				end,
				equals = function(a: string, b: string): boolean
					return complete and a == b
				end,
				timeout = ctx.metric("motion.restLimit"),
			}
			ctx.fadeTo(view.panel, function(use: Use): number
				return if use(settled) then 0 else 1
			end)
			ctx.styled(view.panel, "panel")
			surfaces.skin(view.panel)
			return surfaces.modal(function()
				return view.panel
			end, function()
				close("cancel")
			end, {
				Name = "ColorPickerModal",
				backgroundTransparency = function(use: Use): number
					return if sheet(use) then 0.5 else 1
				end,
				onOutside = function()
					close("outside")
				end,
			})
		end),
	})
	return root
end
