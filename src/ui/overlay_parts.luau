--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Overlay = require("./overlay_types")
local Inputs = require("./input_types")
local measuredScroll = require("./measured_scroll")

type ButtonFactory = Types.Constructor<Inputs.ButtonProps, TextButton>
type UIControls = { Button: ButtonFactory }

local parts = {}

parts.WIDTHS = table.freeze({
	automatic = "controls.alert.maxWidth",
	narrow = "controls.popup.panelWidth",
	wide = "controls.dialog.wideWidth",
})

local MEDIA_KEYS = table.freeze({ "aspectRatio", "background", "height", "image", "scaleMode" })
local HERO_KEYS = table.freeze({ "aspectRatio", "background", "content", "height", "image", "scaleMode", "sticky" })
local ACTION_KEYS = table.freeze({ "busy", "enabled", "id", "label", "onActivate", "role" })
local SCALE_MODES = table.freeze({ fit = true, crop = true, stretch = true })
local ROLES = table.freeze({ default = true, cancel = true, destructive = true })

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
	reserved: { string }?
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
		parts.known(where, action, ACTION_KEYS, "action")
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
			else D2.fromScale(1, 0),
	}
	for _, child in children do
		table.insert(props, child)
	end
	local frame = Host.Frame(props)
	local ratio = media.aspectRatio
	if ratio and not height then
		local measured = ctx.observe(frame, "AbsoluteSize")
		ctx.runtime.decorate(frame, {
			Size = function(use: ComposeTypes.Use)
				local width = (use(measured) :: Vector2).X
				return D2.new(1, 0, 0, math.floor(width / ratio + 0.5))
			end,
		})
	end
	return frame
end

export type ActionGroup = { frame: Frame, stacked: ComposeTypes.Readable<boolean> }

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
	local stacked = Compose.formula(function(use: ComposeTypes.Use): boolean
		if mode == "stacked" or #actions > 2 then
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
		table.insert(props, button)
		table.insert(widths, ctx.observe(button, "TextBounds"))
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
			table.insert(sizes, ctx.observe(region, "AbsoluteSize"))
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
		table.insert(props, region)
	end
	local frame = Host.ScrollingFrame(props)
	return { frame = frame, pinned = pinned, tight = tight, bodyHeight = bodyHeight, overflowing = overflowing }
end

parts.scroller = measuredScroll

return parts
