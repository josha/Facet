--!strict
local geometry = require("./nav_radial_geometry")
local layoutKit = require("./layout_kit")
local Types = require("./types")
local Radial = require("./radial_types")
local Navigation = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local MenuTypes = require("./nav_radial_menu")
local ArrangementTypes = require("./nav_radial_layout")

export type Paint<V> = {
	transparency: (use: ComposeTypes.Use) -> number,
	buttons: { [string]: TextButton },
	iconic: (use: ComposeTypes.Use, live: Radial.Sector<V>) -> boolean,
	focus: ComposeTypes.FocusScope<string>,
	gui: GuiService?,
	panel: ScrollingFrame,
	listWidth: ComposeTypes.ReadOnlyValue<number>,
	listHeaderHeight: ComposeTypes.Value<number>,
}

local PATH_THICKNESS_LIMIT = 100

return function<V>(
	ctx: Types.Context,
	UI: MenuTypes.Controls,
	surfaces: Navigation.Surfaces,
	lists: layoutKit.Kit,
	menu: MenuTypes.Menu<V>,
	arrangement: ArrangementTypes.Arrangement<V>,
	phase: Navigation.PresencePhase?
): Paint<V>
	local Host, Compose, runtime, read = ctx.Host, ctx.Compose, ctx.runtime, ctx.read
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local spec, session = menu.spec, menu.session
	local reduced, appearance = menu.reduced, menu.appearance
	local contentFit: Radial.ContentFit = menu.contentFit
	local preferred, candidate, naming = menu.preferred, menu.candidate, menu.naming
	local following, center = arrangement.following, arrangement.center
	local captionPadding, wordWidths, sectors, fallback =
		arrangement.captionPadding, arrangement.wordWidths, arrangement.sectors, arrangement.fallback
	local captionWidths = arrangement.captionWidths
	local entry = runtime.timeline({ duration = ctx.metric("motion.radial.enter") })
	Compose.watch(function(use: ComposeTypes.Use)
		use(arrangement.centerTarget)
		if entry.completed:peek() then
			following:set(true)
		end
	end)
	local spreadFrom = ctx.metric("motion.materialize.radialSpread")
	local fading = runtime.tween(function(use: ComposeTypes.Use)
		return if phase and use(phase.exiting) then 1 else 0
	end, { seconds = ctx.metric("motion.radial.exit") })
	local function spread(use: ComposeTypes.Use): number
		if reduced(use) then
			return 1
		end
		local present = ctx.motionEase("present", use)
		local shown = present(use(entry.progress)) * (1 - present(use(fading)))
		return spreadFrom + (1 - spreadFrom) * shown
	end
	local function transparency(use: ComposeTypes.Use): number
		if reduced(use) then
			return 0
		end
		return math.max(1 - use(entry.progress), use(fading))
	end
	local buttons: { [string]: TextButton } = {}
	local ringFits: ComposeTypes.Value<{ [string]: { ring: number, inner: number, outer: number } }> = Compose.cell({})
	local fittedWidths: ComposeTypes.Value<{ [string]: number }> = Compose.cell({})
	local function iconSide(use: ComposeTypes.Use): number
		return if spec.iconSize ~= nil then read(spec.iconSize, use) else ctx.controlSize(nil, "iconSize", use)
	end
	local function iconic(use: ComposeTypes.Use, live: Radial.Sector<V>): boolean
		if live.list then
			return false
		end
		if menu.glyphOnly(live.item) then
			return true
		end
		local item = live.item
		local icon = item.icon ~= nil or (item.compactLabel ~= nil and item.compactLabel.icon ~= nil)
		if not icon or live.sharedIcon == true then
			return false
		end
		local padding = captionPadding(use)
		local button = buttons[live.key]
		local inset = button and button:FindFirstChildWhichIsA("UIPadding")
		if inset then
			local left = inset:GetStyled("PaddingLeft") :: UDim
			local right = inset:GetStyled("PaddingRight") :: UDim
			padding = left.Offset + right.Offset
		end
		local width = math.min(geometry.labelBounds(live, 40).w, use(fittedWidths)[live.key] or math.huge)
		return (use(wordWidths)[live.key] or 0) + padding > width
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
	local listHeaderHeight = Compose.cell(0)
	local function listTop(use: ComposeTypes.Use): number
		return math.max(48, math.ceil(use(listHeaderHeight)) + 10)
	end
	local listWidth = Compose.formula(function(use: ComposeTypes.Use): number
		local width = ctx.metric("controls.popup.panelWidth", use)
		local words = use(wordWidths)
		for _, sector in use(sectors) do
			local item = sector.item
			local icon = item.icon or (item.compactLabel and item.compactLabel.icon)
			local content = (words[sector.key] or 0)
				+ captionPadding(use)
				+ (if icon then ctx.controlSize(nil, "iconSize", use) + ctx.metric("space.s", use) else 0)
			width = math.max(width, content + 2 * ctx.metric("space.m", use) + 8)
		end
		return math.min(width, math.max(0, use(arrangement.viewport).X - 32))
	end)
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
			return if use(fallback) then D2.new(0, use(listWidth), 1, -listTop(use) - 32) else D2.fromScale(1, 1)
		end,
		Position = function(use: ComposeTypes.Use)
			return if use(fallback) then D2.new(0.5, -use(listWidth) / 2, 0, listTop(use)) else D2.fromOffset(0, 0)
		end,
		Active = function(use: ComposeTypes.Use)
			return use(fallback) or not spec.centerPassThrough
		end,
		Interactable = menu.opened,
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
					if spec.center and spec.center ~= "back" and not menu.corner then
						table.insert(entries, prefix .. "/$navigation")
					end
				end
				visit(read(spec.items, use), "")
				return entries
			end,
			render = function(key: ComposeTypes.ReadOnlyValue<string>)
				local current: ComposeTypes.Value<Radial.Sector<V>?> = Compose.cell(nil :: Radial.Sector<V>?)
				local fittedShape: ComposeTypes.Value<Radial.SectorShape?> = Compose.cell(nil :: Radial.SectorShape?)
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
						local from = session.branchOrigin
						local branch = if from and from.path == table.concat(sector.path, "/") then from.shape else nil
						local centred = branch == nil and entry.completed:peek()
						local function unfold(use: ComposeTypes.Use, shape: Radial.SectorShape): Radial.SectorShape
							local parent = assert(branch)
							local present = ctx.motionEase("present", use)
							local p = if use(branchPhase.exiting)
								then 1 - present(1 - use(opacity))
								else present(use(arrival))
							local start = ctx.metric("motion.unfoldStart", use)
							local factor = start + (1 - start) * p
							local middle = (parent.inner + parent.outer) / 2
							local radius = middle + (math.sqrt(shape.x * shape.x + shape.y * shape.y) - middle) * p
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
						local function travel(use: ComposeTypes.Use, live: Radial.Sector<V>): (number, number)
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
								or (live.item.selected ~= nil and read(live.item.selected, use) == live.item.value)
						end
						local function box(use: ComposeTypes.Use, live: Radial.Sector<V>): (number, number)
							if appearance == "buttons" then
								local diameter = math.max(
									44,
									live.size,
									if iconic(use, live)
										then 0
										else (use(wordWidths)[live.key] or 0) + captionPadding(use)
								)
								return diameter, diameter
							end
							local iconOnly = iconic(use, live)
							local bounds = geometry.labelBounds(use(fittedShape) or live, if iconOnly then 160 else 40)
							return if iconOnly then bounds.h else bounds.w, bounds.h
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
							icon = sector.item.icon or (sector.item.compactLabel and sector.item.compactLabel.icon),
							AnchorPoint = function(use: ComposeTypes.Use)
								return if currentSector(use).list then V2.zero else V2.new(0.5, 0.5)
							end,
							BackgroundTransparency = if appearance == "wedges"
									or spec.buttonSurface == "none"
								then function(use: ComposeTypes.Use): number
									return if use(fallback) then 0 else 1
								end
								else nil,
							LayoutOrder = function(use: ComposeTypes.Use)
								return currentSector(use).index
							end,
							InputBegan = menu.beginPointer,
							MouseEnter = function()
								if
									not session.capture
									and not session.analog
									and (preferred == nil or preferred:peek() ~= E.PreferredInput.Touch)
								then
									candidate:set(currentSector().key)
									naming:set(menu.pointing())
								end
							end,
							MouseLeave = function()
								if not session.capture and not session.analog then
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
								local width, height = box(use, live)
								return D2.fromOffset(width, height)
							end,
							TextWrapped = false,
							enabled = function(use: ComposeTypes.Use)
								return read(currentSector(use).item.enabled, use) ~= false
							end,
							selected = chosen,
							onActivate = function(input: InputObject?)
								menu.nativeActivate(currentSector(), input)
							end,
							SelectionGained = function()
								focus.focus(currentSector().key)
								candidate:set(currentSector().key)
							end,
							ZIndex = 105,
						})
						button:AddTag("facet-radial-label")
						Compose.watch(function(use: ComposeTypes.Use)
							if use(fallback) then
								button:AddTag("facet-radial-row")
							elseif button:HasTag("facet-radial-row") then
								button:RemoveTag("facet-radial-row")
							end
						end)
						buttons[sector.key] = button
						if spec.captions and appearance == "buttons" then
							local words = ctx.text({
								Name = "Text",
								Text = function(use: ComposeTypes.Use): string
									return read(currentSector(use).item.label, use) or ""
								end,
								Size = D2.fromOffset(0, 0),
								AutomaticSize = E.AutomaticSize.XY,
								TextWrapped = false,
								Interactable = false,
								ZIndex = 107,
							})
							words:AddTag("facet-type-caption")
							local plate = ctx.styled(
								Host.Frame({
									Name = "ItemCaption",
									AnchorPoint = V2.new(0.5, 0),
									Position = function(use: ComposeTypes.Use): UDim2
										return D2.new(0.5, 0, 1, ctx.metric("space.xs", use))
									end,
									Size = D2.fromOffset(0, 0),
									AutomaticSize = E.AutomaticSize.XY,
									Interactable = false,
									Visible = function(use: ComposeTypes.Use): boolean
										local live = currentSector(use)
										return not live.list and iconic(use, live)
									end,
									ZIndex = 106,
									ctx.padding(8, 4),
								}),
								"tooltip"
							)
							surfaces.attach(plate, { words })
							surfaces.attach(button, { plate })
						end
						local floor = button:FindFirstChildWhichIsA("UISizeConstraint")
						if floor then
							floor:Destroy()
						end
						local glyph = button:FindFirstChild("LeadingIcon", true)
						if glyph then
							runtime.decorate(glyph, {
								Visible = function(use: ComposeTypes.Use)
									local live = currentSector(use)
									return live.list or iconic(use, live)
								end,
								Size = function(use: ComposeTypes.Use): UDim2
									local live = currentSector(use)
									local theme = ctx.controlSize(nil, "iconSize", use)
									if live.list or not iconic(use, live) then
										return D2.fromOffset(theme, theme)
									end
									local width, height = box(use, live)
									local room = math.min(width, height)
									local side = math.min(iconSide(use), math.max(room - 4, theme))
									return D2.fromOffset(side, side)
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
						menu.skin(button, spec.skin and spec.skin.item, function(use: ComposeTypes.Use)
							return use(candidate) == currentSector(use).key
						end)
						local caption = button:FindFirstChild("Title", true)
						local textNode = if caption and caption:IsA("TextLabel") then caption else button
						local natural = ctx.styled(
							Host.TextLabel({
								Name = "CaptionMeasure",
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								TextXAlignment = E.TextXAlignment.Left,
								Text = function(use: ComposeTypes.Use): string
									return read(currentSector(use).item.label, use) or ""
								end,
								FontFace = ctx.observeStyled.FontFace(textNode),
								TextSize = ctx.observeStyled.TextSize(textNode),
								TextWrapped = false,
								TextTruncate = E.TextTruncate.None,
								TextTransparency = 1,
								Interactable = false,
								Size = D2.fromOffset(0, 0),
								AutomaticSize = E.AutomaticSize.XY,
							}),
							"Text"
						)
						surfaces.attach(button, { natural })
						local unit = ctx.layoutUnit(button)
						local fullBounds, paintedBounds =
							ctx.layoutBounds(natural, unit), ctx.layoutBounds(textNode, unit)
						local measured = Compose.formula(function(use: ComposeTypes.Use): Vector2
							local full, painted = use(fullBounds), use(paintedBounds)
							return V2.new(math.max(full.X, painted.X), math.max(full.Y, painted.Y))
						end)
						Compose.watch(function(use: ComposeTypes.Use)
							local natural = use(fullBounds).X
							if natural > 0 and captionWidths:peek()[sector.key] ~= natural then
								local widths = table.clone(captionWidths:peek())
								widths[sector.key] = natural
								captionWidths:set(widths)
							end
						end)
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

						local strokeOwner = Compose.currentOwner()
						local extraStrokes: { Path2D } = {}
						local candidate = Compose.cell(false)
						local function extraStroke(index: number): Path2D
							local existing = extraStrokes[index]
							if existing then
								return existing
							end
							local stroke = Compose.withOwner(assert(strokeOwner), function(): Path2D
								local made = Host.Path2D("SectorBand" .. tostring(index + 1)) {
									Thickness = paint.Thickness,
									Closed = false,
									ZIndex = 102,
								}
								ctx.styled(made, "radial-sector")
								if candidate:peek() then
									made:AddTag("facet-radial-candidate")
								end
								return made
							end)
							extraStrokes[index] = stroke
							return stroke
						end
						Compose.watch(function(use: ComposeTypes.Use)
							local on = chosen(use)
							candidate:set(on)
							for _, stroke in { paint, table.unpack(extraStrokes) } do
								if on then
									stroke:AddTag("facet-radial-candidate")
								else
									stroke:RemoveTag("facet-radial-candidate")
								end
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
								return if currentSector(use).list then D2.new(1, 0, 0, 44) else D2.fromScale(1, 1)
							end,
							button,
						}, nil, false)
						local shaped = Compose.cell(false)
						local shape = Host.Frame "Paint" {
							BackgroundTransparency = 1,
							Visible = function(use: ComposeTypes.Use)
								return appearance == "wedges" and not currentSector(use).list and use(shaped)
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
							local iconSize = iconSide(use) + 8
							local fitted = geometry.fitContent(
								live,
								if iconOnly
									then iconSize
									elseif text.X > 0 then text.X + captionPadding(use)
									else label.w,
								if iconOnly
									then iconSize
									elseif text.Y > 0 then math.max(text.Y, ctx.controlSize(nil, "height", use))
									else label.h,
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
									if entry.inner == live.inner and (fit == nil or fit.ring ~= live.inner) then
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
							fittedShape:set(fitted)
							local width = geometry.labelBounds(fitted, 40).w
							if fittedWidths:peek()[live.key] ~= width then
								local widths = table.clone(fittedWidths:peek())
								widths[live.key] = width
								fittedWidths:set(widths)
							end
							local painted = if branch and moving(use, live) then unfold(use, fitted) else fitted
							local bounds = geometry.paint(painted)
							placed:set({ x = bounds.x, y = bounds.y })
							shape.Size = D2.fromOffset(bounds.w, bounds.h)
							local band = math.max(1, fitted.outer - fitted.inner)
							local strokes = math.max(1, math.ceil(band / PATH_THICKNESS_LIMIT - 1e-6))
							local function strokePoints(part: Radial.Paint): { Path2DControlPoint }
								local points: { Path2DControlPoint } = {}
								for _, point in part.points do
									local sx, sy = part.w / bounds.w, part.h / bounds.h
									table.insert(
										points,
										ctx.types.Path2DControlPoint.new(
											D2.fromScale(
												(point.x * part.w + part.x - bounds.x) / bounds.w,
												(point.y * part.h + part.y - bounds.y) / bounds.h
											),
											D2.fromScale(point.inX * sx, point.inY * sy),
											D2.fromScale(point.outX * sx, point.outY * sy)
										)
									)
								end
								return points
							end
							if strokes == 1 then
								paint.Thickness = band
								paint:SetControlPoints(strokePoints(bounds))
							end
							local step = (painted.outer - painted.inner) / strokes
							for index = 1, math.max(strokes, #extraStrokes + 1) do
								local stroke = if index == 1 then paint else extraStroke(index - 1)
								if index > strokes then
									stroke.Visible = false
								elseif strokes > 1 then
									local part = table.clone(painted)
									part.inner = painted.inner + (index - 1) * step
									part.outer = painted.inner + index * step
									stroke.Visible = true
									stroke.Thickness = band / strokes
									stroke:SetControlPoints(strokePoints(geometry.paint(part)))
									if index > 1 and stroke.Parent ~= shape then
										stroke.Parent = shape
									end
								end
							end
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
							shape.Position =
								D2.fromOffset(at.X + bounds.x + dx + lag * live.x, at.Y + bounds.y + dy + lag * live.y)
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
	return {
		transparency = transparency,
		buttons = buttons,
		iconic = iconic,
		focus = focus,
		gui = gui,
		panel = panel,
		listWidth = listWidth,
		listHeaderHeight = listHeaderHeight,
	}
end
