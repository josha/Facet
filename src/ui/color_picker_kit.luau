--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")
local colorValue = require("./color_value")
local fieldChrome = require("./field_chrome")
local ControlTypes = require("./control_types")

type Use = ComposeTypes.Use
export type Hsv = colorValue.Hsv
export type Item = colorValue.Swatch
export type Paint = { color: Color3?, alpha: number }
export type Deps = ControlTypes.BuilderControls
export type Kit = {
	chrome: fieldChrome.Chrome,
	color: colorValue.ColorValue,
	WHITE: Color3,
	BLACK: Color3,
	LIGHT: Color3,
	DARK: Color3,
	normalize: (unknown) -> ({ Item }?, string?),
	ring: (string) -> Frame,
	swatch: (string, Shared.Value<UDim2>, (Use) -> Paint) -> Frame,
}

local MODE_LABEL: { [string]: string } =
	{ swatches = "Swatches", spectrum = "Spectrum", sliders = "Sliders", brick = "Bricks" }
local CELL, GAP, PAD, SPACE, MARGIN = 44, 4, 12, 8, 8
local MAX_COLUMNS = 8
local GRID_WIDTH = MAX_COLUMNS * CELL + (MAX_COLUMNS - 1) * GAP
local RING, BUBBLE = 20, 44

local function isColor(value: unknown): boolean
	return typeof(value) == "Color3"
end

local function unit(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

local function writable(source: unknown): boolean
	return type(source) == "table" and type((source :: { [string]: unknown }).set) == "function"
end

local function new(ctx: Shared.Context): Kit
	local Compose, Host = ctx.Compose, ctx.Host
	local E, D2, V2 = ctx.types.Enum, ctx.types.UDim2, ctx.types.Vector2
	local C3 = ctx.types.Color3
	local chrome = fieldChrome(ctx)
	local color = colorValue({ Color3 = C3, BrickColor = ctx.types.BrickColor })
	local WHITE, BLACK = C3.new(1, 1, 1), C3.new(0, 0, 0)
	local LIGHT, DARK, MUTED = C3.fromRGB(255, 255, 255), C3.fromRGB(204, 204, 204), C3.fromRGB(128, 128, 128)

	local function normalize(list: unknown): ({ Item }?, string?)
		if type(list) ~= "table" then
			return nil, "is an array of Color3 or { color, label? }"
		end
		local out: { Item } = {}
		local seen: { [string]: boolean } = {}
		for index, entry in list :: { unknown } do
			local paint: unknown, label: unknown = entry, nil
			if type(entry) == "table" then
				local fields = entry :: { [unknown]: unknown }
				paint, label = fields.color, fields.label
				for key in fields do
					if key ~= "color" and key ~= "label" then
						return nil, `item {index} has an unknown key '{tostring(key)}' (it is \{ color, label? })`
					end
				end
			end
			if not isColor(paint) or (label ~= nil and type(label) ~= "string") then
				return nil, `item {index} is a Color3 or \{ color = Color3, label = string? }`
			end
			local c = paint :: Color3
			local words = label :: string?
			local key = words or color.hex(c)
			if seen[key] then
				return nil, `repeats '{key}' (a label or hex is the item's key)`
			end
			seen[key] = true
			table.insert(out, { color = c, label = words, key = key })
		end
		return out, nil
	end

	local function ring(name: string): Frame
		local function stroke(tint: Color3, thickness: number): UIStroke
			return Host.UIStroke "Stroke" { Color = tint, Thickness = thickness, Transparency = 0 }
		end
		return Host.Frame(name)({
			Size = D2.fromOffset(RING, RING),
			BackgroundTransparency = 1,
			ctx.corner(RING) :: Shared.Child,
			stroke(BLACK, 1),
			Host.Frame "Band" {
				AnchorPoint = V2.new(0.5, 0.5),
				Position = D2.fromScale(0.5, 0.5),
				Size = D2.new(1, -2, 1, -2),
				BackgroundTransparency = 1,
				ctx.corner(RING) :: Shared.Child,
				stroke(WHITE, 3),
				Host.Frame "Inner" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.new(1, -6, 1, -6),
					BackgroundTransparency = 1,
					ctx.corner(RING) :: Shared.Child,
					stroke(BLACK, 1),
				},
			},
		})
	end

	local function swatch(name: string, edge: Shared.Value<UDim2>, paint: (Use) -> Paint): Frame
		local function checkerView(): Frame
			local cells: { Shared.Child } = {}
			for index, place in { { 0, 0 }, { 0.5, 0 }, { 0, 0.5 }, { 0.5, 0.5 } } do
				table.insert(
					cells,
					Host.Frame(string.char(64 + index))({
						Size = D2.fromScale(0.5, 0.5),
						Position = D2.fromScale(place[1], place[2]),
						BorderSizePixel = 0,
						BackgroundColor3 = if index == 1 or index == 4 then LIGHT else DARK,
					})
				)
			end
			local checker: Shared.FrameNativeProps = {
				Name = "Checker",
				Size = D2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = function(use: Use)
					local p = paint(use)
					return p.color ~= nil and p.alpha < 1
				end,
			}
			for _, cell in cells do
				checker[#checker + 1] = cell
			end
			return Host.Frame(checker)
		end
		return ctx.styled(
			Host.Frame(name)({
				Size = edge,
				BorderSizePixel = 0,
				BackgroundColor3 = function(use: Use)
					return paint(use).color or WHITE
				end,
				BackgroundTransparency = function(use: Use)
					local p = paint(use)
					return if p.color ~= nil and p.alpha >= 1 then 0 else 1
				end,
				ctx.corner() :: Shared.Child,
				Host.UIStroke({ Thickness = 1, ApplyStrokeMode = E.ApplyStrokeMode.Border }),
				Compose.show(function(use: Use): boolean
					local p = paint(use)
					return p.color ~= nil and p.alpha < 1
				end, function(): CanvasGroup
					return Host.CanvasGroup {
						Name = "Paint",
						Size = D2.fromScale(1, 1),
						BorderSizePixel = 0,
						BackgroundTransparency = 1,
						ctx.corner() :: Shared.Child,
						checkerView(),
						Host.Frame "Plate" {
							Size = D2.fromScale(1, 1),
							BorderSizePixel = 0,
							BackgroundColor3 = function(use: Use)
								return paint(use).color or WHITE
							end,
							BackgroundTransparency = function(use: Use)
								local p = paint(use)
								return if p.color == nil then 1 else 1 - p.alpha
							end,
						},
					}
				end),
				Host.Frame "Empty" {
					AnchorPoint = V2.new(0.5, 0.5),
					Position = D2.fromScale(0.5, 0.5),
					Size = D2.new(1, 0, 0, 1),
					Rotation = -45,
					BorderSizePixel = 0,
					BackgroundColor3 = MUTED,
					Visible = function(use: Use)
						return paint(use).color == nil
					end,
				},
			}),
			"color-swatch"
		)
	end

	return {
		chrome = chrome,
		color = color,
		WHITE = WHITE,
		BLACK = BLACK,
		LIGHT = LIGHT,
		DARK = DARK,
		normalize = normalize,
		ring = ring,
		swatch = swatch,
	}
end

return {
	MODE_LABEL = MODE_LABEL,
	CELL = CELL,
	GAP = GAP,
	PAD = PAD,
	SPACE = SPACE,
	MARGIN = MARGIN,
	MAX_COLUMNS = MAX_COLUMNS,
	GRID_WIDTH = GRID_WIDTH,
	RING = RING,
	BUBBLE = BUBBLE,
	isColor = isColor,
	unit = unit,
	writable = writable,
	new = new,
}
