--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Canvas = Raster.Canvas
local Field = Raster.Field
local Image = Raster.Image
local Numeric = Raster.Numeric
local Resample = Raster.Resample

type Image = Raster.Image
type Field = Raster.Field
type Color = Raster.Color

local DIRECTORY = "assets/themes/ornate-gauge"
local rgb = Common.rgb
local times = Common.times
local scale = Field.scale

local IRON_D = rgb(0x14, 0x11, 0x0E)
local IRON = rgb(0x2A, 0x24, 0x1D)
local IRON_L = rgb(0x46, 0x3C, 0x2F)
local BRASS_D = rgb(0x6B, 0x4E, 0x1C)
local BRASS = rgb(0xC0, 0x94, 0x3A)
local BRASS_L = rgb(0xF0, 0xD3, 0x8B)
local RUBY_D = rgb(0x66, 0x14, 0x1C)
local RUBY = rgb(0xC8, 0x2E, 0x3A)
local RUBY_L = rgb(0xFF, 0x9A, 0x9A)

local FACE_W, FACE_H = 64, 64
local NEEDLE_W, NEEDLE_H = 24, 64
local CAP_W, CAP_H = 28, 64

local function grad(width: number, height: number, entries: { { number | Color } }): Field
	return Field.vgrad(width, height, Common.stops(entries))
end

local function face(): Image
	local w, h = FACE_W, FACE_H
	local column: { Color } = {}
	local function band(y0: number, y1: number, top: Color, bottom: Color?)
		local low = bottom or top
		local n = y1 - y0 + 1
		for i = 0, n - 1 do
			local t = if n == 1 then 0.0 else i / (n - 1)
			column[y0 + i + 1] = {
				top[1] * (1 - t) + low[1] * t,
				top[2] * (1 - t) + low[2] * t,
				top[3] * (1 - t) + low[3] * t,
			}
		end
	end
	band(0, 1, IRON_D)
	band(2, 4, IRON_L, IRON)
	band(5, 8, BRASS_L, BRASS_D)
	band(9, 11, IRON, times(IRON_D, 0.9))
	band(12, 13, times(IRON_D, 0.45))
	band(14, h - 15, times(IRON_D, 0.55), times(IRON, 0.85))
	band(h - 14, h - 13, times(BRASS_D, 0.75))
	band(h - 12, h - 10, times(IRON_D, 0.9), IRON)
	band(h - 9, h - 6, BRASS, BRASS_D)
	band(h - 5, h - 3, IRON, times(IRON_L, 0.7))
	band(h - 2, h - 1, IRON_D)
	local c = Canvas.new(w, h)
	Canvas.paint(
		c,
		Field.generate(w, h, 3, function(_x: number, y: number, channel: number): number
			return column[y + 1][channel]
		end),
		Field.new(w, h, 1, 1.0)
	)
	return Canvas.image(c)
end

local function needle(): Image
	local w, h = NEEDLE_W, NEEDLE_H
	local c = Canvas.new(w, h)
	local cx = w / 2.0
	local outline = Common.mask(w, h)
	outline:poly({ cx, 0, cx + 8, h * 0.5, cx, h - 1, cx - 8, h * 0.5 })
	Canvas.paint(c, IRON_D, outline:arr())
	local blade = Common.mask(w, h)
	blade:poly({ cx, 2, cx + 6, h * 0.5, cx, h - 3, cx - 6, h * 0.5 })
	local b = blade:arr()
	Canvas.paint(c, grad(w, h, { { 0.0, BRASS_L }, { 0.35, BRASS }, { 0.65, BRASS_D }, { 1.0, BRASS } }), b)
	local high, low = Field.emboss(b, 0.8, 1)
	Canvas.paint(c, BRASS_L, scale(high, 0.7))
	Canvas.paint(c, IRON_D, scale(low, 0.55))
	local spine = Common.mask(w, h)
	spine:rect({ cx - 1, 6, cx, h - 7 })
	Canvas.paint(c, BRASS_L, scale(spine:arr(), 0.85))
	local ring = Common.mask(w, h)
	ring:ellipse({ cx - 7, h * 0.5 - 7, cx + 6, h * 0.5 + 6 })
	Canvas.paint(c, BRASS_D, ring:arr())
	local jewel = Common.mask(w, h)
	jewel:ellipse({ cx - 5, h * 0.5 - 5, cx + 4, h * 0.5 + 4 })
	Canvas.paint(c, RUBY_D, jewel:arr())
	local inner = Common.mask(w, h)
	inner:ellipse({ cx - 4, h * 0.5 - 4, cx + 3, h * 0.5 + 3 })
	Canvas.paint(c, RUBY, inner:arr())
	local glint = Common.mask(w, h)
	glint:ellipse({ cx - 3, h * 0.5 - 4, cx - 1, h * 0.5 - 2 })
	Canvas.paint(c, RUBY_L, scale(glint:arr(), 0.9))
	return Canvas.image(c)
end

local function endcap(): Image
	local w, h = CAP_W, CAP_H
	local c = Canvas.new(w, h)
	local cx = w / 2.0
	local body = Common.mask(w, h)
	body:rrect({ 1, 2, w - 2, h - 3 }, 6)
	local bd = body:arr()
	Canvas.paint(c, grad(w, h, { { 0.0, BRASS_L }, { 0.22, BRASS }, { 0.6, BRASS_D }, { 1.0, times(BRASS, 0.8) } }), bd)
	local high, low = Field.emboss(bd, 1.0, 2)
	Canvas.paint(c, BRASS_L, scale(high, 0.75))
	Canvas.paint(c, IRON_D, scale(low, 0.7))
	for _, dx in { -6, 6 } do
		local flute = Common.mask(w, h)
		flute:rrect({ cx + dx - 1, 10, cx + dx + 1, h - 11 }, 1)
		local f = flute:arr()
		Canvas.paint(c, IRON_D, scale(f, 0.55))
		Canvas.paint(c, BRASS_L, scale(Field.shift(f, 1, 0), 0.35))
	end
	local boss = Common.mask(w, h)
	boss:ellipse({ cx - 5, h * 0.5 - 5, cx + 4, h * 0.5 + 4 })
	Canvas.paint(c, IRON, boss:arr())
	local bossInner = Common.mask(w, h)
	bossInner:ellipse({ cx - 4, h * 0.5 - 4, cx + 3, h * 0.5 + 3 })
	Canvas.paint(c, BRASS, bossInner:arr())
	for _, y in { 12, h - 13 } do
		local rivet = Common.mask(w, h)
		rivet:ellipse({ cx - 2, y - 2, cx + 1, y + 1 })
		local r = rivet:arr()
		Canvas.paint(c, BRASS_L, r)
		Canvas.paint(c, IRON_D, scale(Field.shift(r, 0, 1), 0.5))
	end
	return Canvas.image(c)
end

local function contactSheet(faceImage: Image, needleImage: Image, capImage: Image): Image
	local rows = { { 320, 0.08 }, { 520, 0.5 }, { 760, 0.94 } }
	local pad, gap = 24, 20
	local dialHeight = 56
	local w = pad * 2 + 760
	local h = pad * 2 + #rows * (dialHeight + gap)
	local sheet = Common.checker(w, h, 16, { 34, 32, 38 }, { 41, 39, 46 })
	local y = pad
	for _, spec in rows do
		local width, fraction = spec[1], spec[2]
		local dial = Image.new(width, dialHeight, 4)
		Image.alphaComposite(dial, Resample.resize(faceImage, width, dialHeight, "bilinear"), 0, 0)
		local cap = Resample.resize(capImage, CAP_W, dialHeight, "bilinear")
		Image.alphaComposite(dial, cap, 0, 0)
		Image.alphaComposite(dial, cap, width - CAP_W, 0)
		local travel = width - 2 * CAP_W - NEEDLE_W
		local nx = CAP_W + Numeric.roundHalfEven(travel * fraction)
		Image.alphaComposite(dial, Resample.resize(needleImage, NEEDLE_W, dialHeight, "bilinear"), nx, 0)
		Image.paste(sheet, dial, pad, y, dial)
		y += dialHeight + gap
	end
	return sheet
end

local OrnateGauge = {}

OrnateGauge.name = "ornate-gauge"
OrnateGauge.summary = "ornate-gauge theme package art"

function OrnateGauge.generate(): { Common.Output }
	local faceImage, needleImage, capImage = face(), needle(), endcap()
	local stride = FACE_W * 4
	for y = 0, FACE_H - 1 do
		local first = buffer.readstring(faceImage.data, y * stride, 4)
		for x = 1, FACE_W - 1 do
			if buffer.readstring(faceImage.data, y * stride + x * 4, 4) ~= first then
				error("gauge_face.png is not horizontally invariant; a stretch would distort it", 0)
			end
		end
	end
	return {
		{ path = `{DIRECTORY}/gauge_face.png`, image = faceImage },
		{ path = `{DIRECTORY}/gauge_needle.png`, image = needleImage },
		{ path = `{DIRECTORY}/gauge_endcap.png`, image = capImage },
		{
			path = `{DIRECTORY}/source/preview/contact-sheet.png`,
			image = contactSheet(faceImage, needleImage, capImage),
		},
	}
end

return OrnateGauge :: Common.Target
