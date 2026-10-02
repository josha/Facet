--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local measuredScroll = require("./measured_scroll")
local scrollLock = require("./scroll_lock")
local freeze = require("./freeze")

type ButtonFactory = Types.Constructor<Inputs.ButtonProps, TextButton>
type UIControls = { Button: ButtonFactory }
type BackPlace = { AnchorPoint: Vector2?, Position: UDim2?, Size: UDim2?, LayoutOrder: number? }

local parts = {}

local WIDTHS: { [string]: string } = freeze({
	automatic = "controls.alert.maxWidth",
	narrow = "controls.popup.panelWidth",
	wide = "controls.dialog.wideWidth",
})
parts.WIDTHS = WIDTHS

local MEDIA_KEYS = table.freeze({ "aspectRatio", "background", "height", "image", "scaleMode" })
local HERO_KEYS = table.freeze({ "aspectRatio", "background", "content", "height", "image", "scaleMode", "sticky" })
local ACTION_KEYS = table.freeze({ "busy", "enabled", "id", "label", "onActivate", "role" })
local DIALOG_ACTION_KEYS = table.freeze({ "busy", "enabled", "id", "keepOpen", "label", "onActivate", "role" })
local SCALE_MODES: { [string]: boolean } = freeze({ fit = true, crop = true, stretch = true })
local ROLES: { [string]: boolean } = freeze({ default = true, cancel = true, destructive = true })

function parts.instance(value: unknown): boolean
	if typeof(value) == "Instance" then
		return true
	end
	return type(value) == "table" and type((value :: { [string]: unknown }).IsA) == "function"
end

function parts.readable(ctx: Types.Context, value: unknown): boolean
	return type(value) == "function" or ctx.Compose.isReadable(value)
end

function parts.bound(ctx: Types.Context, value: unknown, kind: string): boolean
	return type(value) == kind or parts.readable(ctx, value)
end

function parts.known(where: string, value: { [string]: unknown }, keys: { string }, label: string)
	for key in value do
		if type(key) ~= "string" or not table.find(keys, key) then
			error(`Facet {where}: unknown {label} option '{tostring(key)}'`, 0)
		end
	end
end

local function positive(value: unknown): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function checkShape(where: string, media: { [string]: unknown }, name: string)
	local ratio, height = media.aspectRatio, media.height
	if (ratio == nil) == (height == nil) then
		error(`Facet {where}: {name} takes exactly one of aspectRatio or height`, 0)
	end
	if ratio ~= nil and not positive(ratio) then
		error(`Facet {where}: {name}.aspectRatio must be a positive finite number`, 0)
	end
	if height ~= nil and not positive(height) and not (type(height) == "string" and height ~= "") then
		error(`Facet {where}: {name}.height must be positive finite pixels or a theme metric name`, 0)
	end
	if media.scaleMode ~= nil and (type(media.scaleMode) ~= "string" or not SCALE_MODES[media.scaleMode]) then
		error(`Facet {where}: {name}.scaleMode must be fit, crop or stretch`, 0)
	end
end

function parts.checkMedia(where: string, media: unknown)
	if media == nil then
		return
	end
	if type(media) ~= "table" then
		error(`Facet {where}: media must be a table with image and aspectRatio or height`, 0)
	end
	local fields = media :: { [string]: unknown }
	parts.known(where, fields, MEDIA_KEYS, "media")
	if type(fields.image) ~= "string" or fields.image == "" then
		error(`Facet {where}: media.image must be an image source string`, 0)
	end
	checkShape(where, fields, "media")
end

function parts.checkHero(where: string, hero: unknown)
	if hero == nil then
		return
	end
	if type(hero) ~= "table" then
		error(`Facet {where}: hero must be a table with image or content`, 0)
	end
	local fields = hero :: { [string]: unknown }
	parts.known(where, fields, HERO_KEYS, "hero")
	if (fields.image == nil) == (fields.content == nil) then
		error(`Facet {where}: hero takes exactly one of image or content`, 0)
	end
	if fields.image ~= nil and (type(fields.image) ~= "string" or fields.image == "") then
		error(`Facet {where}: hero.image must be an image source string`, 0)
	end
	if fields.content ~= nil then
		if not parts.instance(fields.content) and type(fields.content) ~= "function" then
			error(`Facet {where}: hero.content must be an Instance or a content factory`, 0)
		end
		if fields.scaleMode ~= nil then
			error(`Facet {where}: hero.scaleMode applies to an image only`, 0)
		end
	end
	if fields.sticky ~= nil and type(fields.sticky) ~= "boolean" then
		error(`Facet {where}: hero.sticky must be a boolean`, 0)
	end
	checkShape(where, fields, "hero")
end

function parts.checkActions(
	ctx: Types.Context,
	where: string,
	actions: unknown,
	max: number,
	reserved: { string }?,
	closes: boolean?
): number
	if actions == nil then
		return 0
	end
	if type(actions) ~= "table" or #(actions :: { unknown }) > max then
		error(`Facet {where}: actions must be a list of at most {max} actions`, 0)
	end
	local seen: { [string]: boolean } = {}
	local defaults, cancels = 0, 0
	for _, entry in actions :: { unknown } do
		if type(entry) ~= "table" then
			error(`Facet {where}: each action must be a table with id, label and onActivate`, 0)
		end
		local action = entry :: { [string]: unknown }
		parts.known(where, action, if closes then DIALOG_ACTION_KEYS else ACTION_KEYS, "action")
		if action.keepOpen ~= nil and type(action.keepOpen) ~= "boolean" then
			error(`Facet {where}: action keepOpen must be a boolean`, 0)
		end
		local id = action.id
		if type(id) ~= "string" or id == "" or seen[id] or string.find(id, "/", 1, true) then
			error(`Facet {where}: every action needs a unique string id without '/'`, 0)
		end
		if reserved and table.find(reserved, id) then
			error(`Facet {where}: action id '{id}' is reserved for a built-in button`, 0)
		end
		seen[id] = true
		if not parts.bound(ctx, action.label, "string") then
			error(`Facet {where}: action '{id}' needs a string label or a bound one`, 0)
		end
		for _, key in { "enabled", "busy" } do
			if action[key] ~= nil and not parts.bound(ctx, action[key], "boolean") then
				error(`Facet {where}: action '{id}' {key} must be a boolean or a bound one`, 0)
			end
		end
		if action.role ~= nil and (type(action.role) ~= "string" or not ROLES[action.role]) then
			error(`Facet {where}: action '{id}' role must be default, cancel or destructive`, 0)
		end
		if action.role == "default" then
			defaults += 1
		elseif action.role == "cancel" then
			cancels += 1
		end
		if type(action.onActivate) ~= "function" then
			error(`Facet {where}: action '{id}' needs an onActivate function`, 0)
		end
	end
	if defaults > 1 or cancels > 1 then
		error(`Facet {where}: only one action may take each of role default and role cancel`, 0)
	end
	return #(actions :: { unknown })
end

function parts.usable(ctx: Types.Context, action: Overlay.Action?, use: ComposeTypes.Use?): boolean
	return action ~= nil and ctx.read(action.enabled, use) ~= false and ctx.read(action.busy, use) ~= true
end

function parts.call<A...>(fn: (A...) -> (), settle: (() -> ())?, ...: A...)
	local ok: boolean, failure: unknown = pcall(fn, ...)
	if settle then
		settle()
	end
	if not ok then
		error(failure, 0)
	end
end

function parts.width(ctx: Types.Context, preset: Overlay.WidthPreset?, use: ComposeTypes.Use?): number
	return ctx.metric(parts.WIDTHS[preset or "automatic"], use)
end

local function length(ctx: Types.Context, value: number | string, use: ComposeTypes.Use?): number
	return if type(value) == "number" then value else ctx.metric(value, use)
end

function parts.media(ctx: Types.Context, media: Overlay.Media | Overlay.Hero, name: string?): Frame
	local Host, E, D2 = ctx.Host, ctx.types.Enum, ctx.types.UDim2
	local children: { Types.Child } = {}
	if media.image then
		table.insert(
			children,
			Host.ImageLabel "Image" {
				BackgroundTransparency = 1,
				Size = D2.fromScale(1, 1),
				Image = media.image,
				ScaleType = if media.scaleMode == "crop"
					then E.ScaleType.Crop
					elseif media.scaleMode == "stretch" then E.ScaleType.Stretch
					else E.ScaleType.Fit,
			}
		)
	end
	local height = media.height
	local props: Types.FrameNativeProps = {
		Name = name or "Media",
		BorderSizePixel = 0,
		BackgroundTransparency = if media.background then 0 else 1,
		BackgroundColor3 = media.background,
		Size = if height
			then function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, length(ctx, height, use))
			end
			elseif media.aspectRatio then D2.new(1, 0, 0, 100000)
			else D2.fromScale(1, 0),
	}
	for _, child in children do
		props[#props + 1] = child
	end
	local ratio = media.aspectRatio
	if ratio and not height then
		props[#props + 1] = Host.UIAspectRatioConstraint({ AspectRatio = ratio, DominantAxis = E.DominantAxis.Width })
	end
	return Host.Frame(props)
end

export type ActionGroup = { frame: Frame, stacked: ComposeTypes.Readable<boolean> }

function parts.stackedForm(ctx: Types.Context): (ComposeTypes.Use) -> boolean
	local E = ctx.types.Enum
	local tenFoot = ctx.tenFoot()
	local gui = ctx.config.guiService
	local text: ComposeTypes.Readable<unknown>? = if gui and gui.GetPropertyChangedSignal
		then ctx.observe.PreferredTextSize(gui)
		else nil
	return function(use: ComposeTypes.Use): boolean
		local size = if text then use(text) else nil
		return tenFoot(use) or size == E.PreferredTextSize.Larger or size == E.PreferredTextSize.Largest
	end
end

function parts.actions(
	ctx: Types.Context,
	UI: UIControls,
	actions: { Overlay.Action },
	layout: Overlay.ActionLayout?,
	offered: (ComposeTypes.Use) -> number,
	press: (Overlay.Action) -> (),
	height: number?
): ActionGroup
	local Compose, Host, E, D2 = ctx.Compose, ctx.Host, ctx.types.Enum, ctx.types.UDim2
	local mode = layout or "automatic"
	assert(
		mode == "automatic" or mode == "row" or mode == "stacked",
		"Facet actionLayout must be automatic, row or stacked"
	)
	local rowHeight = height or 44
	local widths: { ComposeTypes.Readable<Vector2> } = {}
	local measured = Compose.cell(0)
	local form = parts.stackedForm(ctx)
	local stacked = Compose.formula(function(use: ComposeTypes.Use): boolean
		if mode == "stacked" or #actions > 2 or (mode ~= "row" and form(use)) then
			return true
		end
		if ctx.read(ctx.config.controlSize, use) == "large" then
			return mode ~= "row" or use(measured) > offered(use)
		end
		return use(measured) > offered(use)
	end)
	local props: Types.FrameNativeProps = {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = D2.new(1, 0, 0, 0),
		AutomaticSize = E.AutomaticSize.Y,
		Host.UIListLayout({
			FillDirection = function(use: ComposeTypes.Use)
				return if use(stacked) then E.FillDirection.Vertical else E.FillDirection.Horizontal
			end,
			HorizontalFlex = function(use: ComposeTypes.Use)
				return if use(stacked) then E.UIFlexAlignment.None else E.UIFlexAlignment.Fill
			end,
			SortOrder = E.SortOrder.LayoutOrder,
			Padding = ctx.types.UDim.new(0, 8),
		}),
	}
	for index, action in actions do
		local button = UI.Button({
			Name = action.id,
			label = action.label,
			role = action.role,
			enabled = action.enabled,
			busy = action.busy,
			dialogAction = if action.role == "default" then "default" :: "default" else nil,
			Size = function(use: ComposeTypes.Use)
				return if use(stacked) then D2.new(1, 0, 0, rowHeight) else D2.fromOffset(0, rowHeight)
			end,
			AutomaticSize = E.AutomaticSize.None,
			LayoutOrder = function(use: ComposeTypes.Use)
				return if action.role == "cancel" then (if use(stacked) then #actions + 1 else 0) else index
			end,
			onActivate = function()
				press(action)
			end,
		})
		props[#props + 1] = button
		table.insert(widths, ctx.observe.TextBounds(button))
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local total = (#actions - 1) * 8
		for _, bounds in widths do
			total += use(bounds).X + 24
		end
		measured:set(total)
	end)
	return { frame = Host.Frame(props), stacked = stacked }
end

export type Room = {
	frame: ScrollingFrame,
	pinned: ComposeTypes.Readable<number>,
	tight: ComposeTypes.Readable<boolean>,
	bodyHeight: ComposeTypes.Readable<number>,
	overflowing: ComposeTypes.Readable<boolean>,
}

function parts.room(
	ctx: Types.Context,
	regions: { GuiObject },
	body: ScrollingFrame?,
	natural: (ComposeTypes.Use) -> number,
	maximum: (ComposeTypes.Use) -> number,
	fill: boolean
): Room
	local Compose, Host, E, D2 = ctx.Compose, ctx.Host, ctx.types.Enum, ctx.types.UDim2
	local gap = 8
	local sizes: { ComposeTypes.Readable<Vector2> } = {}
	for _, region in regions do
		if region ~= body then
			table.insert(sizes, ctx.observe.AbsoluteSize(region))
		end
	end
	local pinned = Compose.formula(function(use: ComposeTypes.Use): number
		local total = math.max(0, #regions - 1) * gap
		for _, size in sizes do
			total += use(size).Y
		end
		return total
	end)
	local tight = Compose.formula(function(use: ComposeTypes.Use): boolean
		local limit = maximum(use)
		if limit <= 0 then
			return false
		end
		local minimum = if body then math.min(44, natural(use)) else 0
		return use(pinned) + minimum > limit + 0.5
	end)
	local bodyHeight = Compose.formula(function(use: ComposeTypes.Use): number
		local content = natural(use)
		if use(tight) then
			return content
		end
		local room = math.max(0, maximum(use) - use(pinned))
		return if fill then room else math.min(content, room)
	end)
	local overflowing = Compose.formula(function(use: ComposeTypes.Use): boolean
		return not use(tight) and natural(use) > use(bodyHeight) + 1
	end)
	if body then
		ctx.runtime.decorate(body, {
			Size = function(use: ComposeTypes.Use)
				return D2.new(1, 0, 0, use(bodyHeight))
			end,
			ScrollingEnabled = function(use: ComposeTypes.Use)
				return not use(tight)
			end,
		})
	end
	local props: Types.ScrollingFrameNativeProps = {
		Name = "Room",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = E.ScrollingDirection.Y,
		CanvasSize = D2.fromOffset(0, 0),
		AutomaticCanvasSize = E.AutomaticSize.Y,
		ScrollingEnabled = tight,
		AutomaticSize = function(use: ComposeTypes.Use)
			return if fill or use(tight) then E.AutomaticSize.None else E.AutomaticSize.Y
		end,
		Size = function(use: ComposeTypes.Use)
			return if fill or use(tight) then D2.new(1, 0, 0, maximum(use)) else D2.new(1, 0, 0, 0)
		end,
		Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder, Padding = ctx.types.UDim.new(0, gap) }),
	}
	for index, region in regions do
		ctx.runtime.decorate(region, { LayoutOrder = index })
		props[#props + 1] = region
	end
	props.Selectable = false
	local frame = Host.ScrollingFrame(props)
	scrollLock.own(frame)
	parts.reach(ctx, frame, tight)
	return { frame = frame, pinned = pinned, tight = tight, bodyHeight = bodyHeight, overflowing = overflowing }
end

function parts.reach(ctx: Types.Context, scroller: ScrollingFrame, active: ComposeTypes.Readable<boolean>)
	local Compose, V2 = ctx.Compose, ctx.types.Vector2
	local gui = ctx.config.guiService
	local input = ctx.config.userInputService
	local frames = ctx.runtime.host.frames
	if gui == nil or input == nil or frames == nil then
		return
	end
	local function shown(node: Instance): boolean
		local at: Instance? = node
		while at and at ~= scroller do
			if at:IsA("GuiObject") and (not at.Visible or not at.Interactable) then
				return false
			end
			at = at.Parent
		end
		return at == scroller
	end
	local function nearest(from: GuiObject, direction: number): GuiObject?
		local top, bottom = from.AbsolutePosition.Y, from.AbsolutePosition.Y + from.AbsoluteSize.Y
		local middle = from.AbsolutePosition.X + from.AbsoluteSize.X / 2
		local best: GuiObject?, bestGap, bestSide = nil, math.huge, math.huge
		for _, node in scroller:GetDescendants() do
			if
				node:IsA("GuiObject")
				and node ~= from
				and node.Selectable
				and not node:IsA("ScrollingFrame")
				and not from:IsDescendantOf(node)
				and node.AbsoluteSize.X > 0
				and node.AbsoluteSize.Y > 0
				and shown(node)
			then
				local at, size = node.AbsolutePosition, node.AbsoluteSize
				local gap = if direction > 0 then at.Y - bottom else top - (at.Y + size.Y)
				local beyond = if direction > 0 then at.Y > top + 1 else at.Y + size.Y < bottom - 1
				if beyond and gap >= -size.Y / 2 then
					local side = math.abs(at.X + size.X / 2 - middle)
					if gap < bestGap - 0.5 or (math.abs(gap - bestGap) <= 0.5 and side < bestSide) then
						best, bestGap, bestSide = node, gap, side
					end
				end
			end
		end
		return best
	end
	local function reveal(node: GuiObject)
		local window = scroller.AbsolutePosition.Y
		local height = scroller.AbsoluteWindowSize.Y
		local at, size = node.AbsolutePosition.Y, node.AbsoluteSize.Y
		local canvas = scroller.CanvasPosition
		local limit = math.max(0, scroller.AbsoluteCanvasSize.Y - height)
		local shift = 0
		if at + size > window + height then
			shift = at + size - (window + height)
		elseif at < window then
			shift = at - window
		end
		scroller.CanvasPosition = V2.new(canvas.X, math.clamp(canvas.Y + shift, 0, limit))
	end
	local pending: (() -> ())? = nil
	local function cancel()
		local stop = pending
		pending = nil
		if stop then
			stop()
		end
	end
	Compose.cleanup(cancel)
	local settled: GuiObject? = nil
	local tracking: (() -> ())? = nil
	local function untrack()
		local stop = tracking
		tracking = nil
		settled = nil
		if stop then
			stop()
		end
	end
	Compose.watch(function(use: ComposeTypes.Use)
		if not use(active) then
			untrack()
		elseif tracking == nil then
			settled = gui.SelectedObject
			tracking = frames.onFrame(function()
				settled = gui.SelectedObject
			end)
		end
	end)
	Compose.cleanup(untrack)
	local directions: { [string]: number } = { Down = 1, DPadDown = 1, Up = -1, DPadUp = -1 }
	ctx.runtime.connect(input, "InputBegan", function(event: InputObject)
		local direction = if event.KeyCode then directions[event.KeyCode.Name] else nil
		local from = gui.SelectedObject
		if
			direction == nil
			or from == nil
			or from ~= settled
			or not active:peek()
			or not from:IsDescendantOf(scroller)
		then
			return
		end
		cancel()
		local waited = 0
		pending = frames.onFrame(function()
			waited += 1
			if waited < 6 then
				return
			end
			cancel()
			if gui.SelectedObject ~= from or from.Parent == nil or not active:peek() then
				return
			end
			local target = nearest(from, direction)
			if target then
				reveal(target)
				gui.SelectedObject = target
			end
		end)
	end)
end

function parts.back(
	ctx: Types.Context,
	UI: UIControls,
	label: Types.Value<string>?,
	onActivate: () -> (),
	place: BackPlace?
): TextButton
	local at: BackPlace = place or {}
	local props: Inputs.ButtonProps = {
		Name = "Back",
		label = label or "Back",
		icon = "chevron.leading",
		appearance = "utility",
		onActivate = onActivate,
		AnchorPoint = at.AnchorPoint,
		Position = at.Position,
		Size = at.Size,
		LayoutOrder = at.LayoutOrder,
	}
	local button = UI.Button(props)
	local row = button:FindFirstChildWhichIsA("UIListLayout", true)
	if row then
		ctx.runtime.decorate(row, {
			HorizontalAlignment = ctx.types.Enum.HorizontalAlignment.Left,
			Padding = function(use: ComposeTypes.Use)
				return ctx.types.UDim.new(0, ctx.metric("space.xs", use) / 2)
			end,
		})
	end
	return button
end

function parts.tailSize(ctx: Types.Context, use: ComposeTypes.Use?): number
	return ctx.metric("space.m", use)
end

export type TailPanel = {
	node: GuiObject,
	scale: (ComposeTypes.Use) -> number,
	corner: (ComposeTypes.Use) -> Vector2,
	size: ComposeTypes.Readable<Vector2>,
	radius: (ComposeTypes.Use) -> number,
	role: string,
}

local ARC = 0.5523

local function outlinePoints(
	w: number,
	h: number,
	r: number,
	edge: string?,
	t: number,
	d: number
): { { x: number, y: number, inX: number, inY: number, outX: number, outY: number } }
	local out = {}
	local function add(x: number, y: number, inX: number?, inY: number?, outX: number?, outY: number?)
		table.insert(out, { x = x, y = y, inX = inX or 0, inY = inY or 0, outX = outX or 0, outY = outY or 0 })
	end
	local k = ARC * r
	local function tail(side: string, a: number, b: number, c: number, e: number, f: number, g: number)
		if edge == side then
			add(a, b)
			add(c, e)
			add(f, g)
		end
	end
	add(r, 0, -k, 0, 0, 0)
	tail("bottom", t - d, 0, t, -d, t + d, 0)
	add(w - r, 0, 0, 0, k, 0)
	add(w, r, 0, -k, 0, 0)
	tail("left", w, t - d, w + d, t, w, t + d)
	add(w, h - r, 0, 0, 0, k)
	add(w - r, h, k, 0, 0, 0)
	tail("top", t + d, h, t, h + d, t - d, h)
	add(r, h, 0, 0, -k, 0)
	add(0, h - r, 0, k, 0, 0)
	tail("right", 0, t + d, -d, t, 0, t - d)
	add(0, r, 0, 0, 0, -k)
	return out
end
parts.outlinePoints = outlinePoints

function parts.tail(
	ctx: Types.Context,
	name: string,
	at: (ComposeTypes.Use) -> (Vector2?, string),
	amount: (ComposeTypes.Use) -> number,
	z: (ComposeTypes.Use) -> number,
	panel: TailPanel
): { Frame }
	local Compose, Host, D2, V2 = ctx.Compose, ctx.Host, ctx.types.UDim2, ctx.types.Vector2
	local anchor = ctx.observe.AnchorPoint(panel.node)
	local function geometry(use: ComposeTypes.Use): (Vector2?, string, number, number, number)
		local box = use(panel.size) :: Vector2
		local point, edge = at(use)
		local r = math.min(panel.radius(use), box.X / 2, box.Y / 2)
		local d = parts.tailSize(ctx, use) * math.sqrt(2) / 2
		if point == nil then
			return nil, edge, r, d, 0
		end
		local corner = panel.corner(use)
		local across = edge == "left" or edge == "right"
		local along = if across then box.Y else box.X
		local t = if across then point.Y - corner.Y else point.X - corner.X
		d = math.min(d, math.max(0, along / 2 - r))
		local reach = r + d + math.min(d, math.max(0, along / 2 - r - d))
		t = math.clamp(t, reach, math.max(reach, along - reach))
		local placed = if across then V2.new(point.X, corner.Y + t) else V2.new(corner.X + t, point.Y)
		return placed, edge, r, d, t
	end
	local wedge = ctx.styled(
		Host.Frame(name)({
			Size = function(use: ComposeTypes.Use)
				local point, _, _, d = geometry(use)
				local side = if point then d * math.sqrt(2) * panel.scale(use) else 0
				return D2.fromOffset(side, side)
			end,
			AnchorPoint = V2.new(0.5, 0.5),
			Rotation = 45,
			BorderSizePixel = 0,
			ZIndex = function(use: ComposeTypes.Use)
				return z(use) - 1
			end,
			Position = function(use: ComposeTypes.Use): UDim2
				local point = geometry(use) or V2.zero
				local corner = panel.corner(use)
				local box = use(panel.size)
				local at = use(anchor)
				local pivot = corner + V2.new(box.X * at.X, box.Y * at.Y)
				local placed = pivot + (point - pivot) * panel.scale(use)
				return D2.fromOffset(placed.X, placed.Y)
			end,
			Host.UIGradient "PresentationFade" {
				Transparency = function(use: ComposeTypes.Use)
					return ctx.types.NumberSequence.new(1 - amount(use))
				end,
			},
		}),
		"tail"
	)
	panel.node:AddTag("facet-outlined")
	local outline = ctx.styled(Host.Path2D "Outline" { Closed = true, ZIndex = z }, "outline")
	if panel.role == "tooltip" then
		outline:AddTag("facet-outline-tooltip")
	end
	Compose.watch(function(use: ComposeTypes.Use)
		local box = use(panel.size) :: Vector2
		if box.X <= 0 or box.Y <= 0 then
			return
		end
		local point, edge, r, d, t = geometry(use)
		local native: { Path2DControlPoint } = {}
		for _, p in outlinePoints(box.X, box.Y, r, if point then edge else nil, t, d) do
			table.insert(
				native,
				ctx.types.Path2DControlPoint.new(
					D2.fromScale(p.x / box.X, p.y / box.Y),
					D2.fromScale(p.inX / box.X, p.inY / box.Y),
					D2.fromScale(p.outX / box.X, p.outY / box.Y)
				)
			)
		end
		outline:SetControlPoints(native)
	end)
	local function inset(use: ComposeTypes.Use): number
		return math.ceil(parts.tailSize(ctx, use) * math.sqrt(2))
	end
	local border = Host.Frame "OutlineBoundary" {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		AnchorPoint = anchor,
		Position = function(use: ComposeTypes.Use)
			local box, pivot, pad = use(panel.size), use(anchor), inset(use)
			return D2.fromOffset(pad + box.X * pivot.X, pad + box.Y * pivot.Y)
		end,
		Size = function(use: ComposeTypes.Use)
			local box = use(panel.size) * panel.scale(use)
			return D2.fromOffset(box.X, box.Y)
		end,
		outline,
	}
	local fade = ctx.fade {
		Name = "OutlineFade",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Position = function(use: ComposeTypes.Use)
			local corner, pad = panel.corner(use), inset(use)
			return D2.fromOffset(corner.X - pad, corner.Y - pad)
		end,
		Size = function(use: ComposeTypes.Use)
			local box, pad = use(panel.size), inset(use)
			return D2.fromOffset(box.X + pad * 2, box.Y + pad * 2)
		end,
		GroupTransparency = function(use: ComposeTypes.Use)
			return 1 - amount(use)
		end,
		border,
	}
	return { wedge, fade }
end

parts.scroller = measuredScroll

return parts
