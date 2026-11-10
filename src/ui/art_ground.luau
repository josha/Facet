--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Paint = require("./paint_bounds")
local decoration = require("./native_decoration")

export type Margins = { top: number, right: number, bottom: number, left: number }
type Spacing = (Types.Input<Types.Space>?, ComposeTypes.Use?) -> number

local SIDES: { "top" | "right" | "bottom" | "left" } = { "top", "right", "bottom", "left" }

local function margins(ctx: Types.Context): ComposeTypes.Value<Margins>
	return ctx.Compose.cell({ top = 0, right = 0, bottom = 0, left = 0 })
end

local function padding(
	ctx: Types.Context,
	spacing: Spacing,
	authored: Types.Input<Types.Padding>?,
	carve: ComposeTypes.ReadOnlyValue<Margins>
): Types.Input<Types.Padding>
	local D = ctx.types.UDim
	return function(use: ComposeTypes.Use): Types.Padding
		local value = ctx.read<<Types.Padding?>>(authored, use)
		local given: { [string]: unknown } = if type(value) == "table"
			then (value :: unknown) :: { [string]: unknown }
			else { top = value, right = value, bottom = value, left = value }
		local extra = (use(carve) :: unknown) :: { [string]: number }
		local sides: { [string]: UDim } = {}
		for _, name in SIDES do
			local side = given[name]
			sides[name] = if typeof(side) == "UDim"
				then D.new(side.Scale, side.Offset + extra[name])
				else D.new(0, spacing(side :: Types.Space?, use) + extra[name])
		end
		return (sides :: unknown) :: Types.Padding
	end
end

local function declared(art: GuiObject): (Paint.Box?, string, Paint.Slice?)
	if not art:IsA("ImageLabel") then
		return nil, "Stretch", nil
	end
	local rect, size = art:GetAttribute("FacetPaintRect"), art:GetAttribute("FacetSourceSize")
	if typeof(rect) ~= "Rect" or typeof(size) ~= "Vector2" or size.X <= 0 or size.Y <= 0 then
		return nil, "Stretch", nil
	end
	local center = art.SliceCenter
	return {
		x0 = rect.Min.X,
		y0 = rect.Min.Y,
		x1 = rect.Max.X,
		y1 = rect.Max.Y,
		width = size.X,
		height = size.Y,
	},
		art.ScaleType.Name,
		{ x0 = center.Min.X, y0 = center.Min.Y, x1 = center.Max.X, y1 = center.Max.Y, scale = art.SliceScale }
end

local function mount(ctx: Types.Context, frame: Frame, art: GuiObject, carve: ComposeTypes.Value<Margins>)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	art.AnchorPoint = V2.zero
	art.AutomaticSize = E.AutomaticSize.None
	art.Position = D2.new(0, 0, 0, 0)
	art.Size = D2.fromScale(1, 1)
	art.ZIndex = 0
	local bed = Host.Frame "Ground" {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Size = D2.fromScale(1, 1),
		art,
	}
	bed:AddTag("facet-art-ground")
	runtime.mount(function()
		return Host.Folder "GroundBounds" { decoration(Compose, runtime, ctx.types, frame, bed) }
	end, frame)
	local box, mode, slice = declared(art)
	if box == nil then
		return
	end
	local painted: Paint.Box = box
	local shareX = (painted.x0 + painted.width - painted.x1) / painted.width
	local shareY = (painted.y0 + painted.height - painted.y1) / painted.height
	local size = ctx.layoutSize(frame, ctx.layoutUnit(frame, "ArtGroundUnit"))
	Compose.watch(function(use: ComposeTypes.Use)
		local extent = use(size)
		if extent.X <= 0 or extent.Y <= 0 then
			return
		end
		local current = carve:peek()
		local automatic = frame.AutomaticSize
		local width, height = extent.X, extent.Y
		if mode == "Stretch" then
			local hugsX = automatic == E.AutomaticSize.X or automatic == E.AutomaticSize.XY
			local hugsY = automatic == E.AutomaticSize.Y or automatic == E.AutomaticSize.XY
			if hugsX and shareX < 1 then
				width = (width - current.left - current.right) / (1 - shareX)
			end
			if hugsY and shareY < 1 then
				height = (height - current.top - current.bottom) / (1 - shareY)
			end
		end
		local paint = Paint.place({ x = 0, y = 0, width = width, height = height }, painted, mode, slice, 0)
		local wanted: Margins = {
			top = math.max(0, math.floor(paint.y + 0.5)),
			right = math.max(0, math.floor(width - paint.x - paint.width + 0.5)),
			bottom = math.max(0, math.floor(height - paint.y - paint.height + 0.5)),
			left = math.max(0, math.floor(paint.x + 0.5)),
		}
		if
			wanted.top ~= current.top
			or wanted.right ~= current.right
			or wanted.bottom ~= current.bottom
			or wanted.left ~= current.left
		then
			carve:set(wanted)
		end
	end)
end

return table.freeze({ margins = margins, padding = padding, mount = mount })
