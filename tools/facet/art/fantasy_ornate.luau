--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Canvas = Raster.Canvas
local Field = Raster.Field
local Image = Raster.Image
local Numeric = Raster.Numeric

type Image = Raster.Image
type Field = Raster.Field
type Color = Raster.Color
type Canvas = Raster.Canvas
type Generator = Raster.Generator
type Mask = Common.Mask

local DIRECTORY = "assets/themes/fantasy-ornate"
local SEED = 0x60D1
local rgb = Common.rgb
local times = Common.times
local scale = Field.scale

local VELVET_DEEP = rgb(26, 14, 24)
local VELVET = rgb(56, 26, 44)
local VELVET_HI = rgb(84, 40, 62)
local GOLD_SHADOW = rgb(70, 48, 16)
local GOLD_DARK = rgb(120, 88, 30)
local GOLD = rgb(178, 140, 60)
local GOLD_LIGHT = rgb(226, 196, 116)
local GOLD_HI = rgb(252, 240, 198)
local RUBY = rgb(158, 30, 44)
local RUBY_HI = rgb(238, 108, 108)
local EMERALD = rgb(30, 118, 78)
local EMERALD_HI = rgb(126, 216, 158)
local AMBER = rgb(255, 176, 62)
local AMBER_HI = rgb(255, 236, 176)
local INK = rgb(16, 10, 14)
local ICON_WHITE = rgb(240, 240, 242)

local function grad(width: number, height: number, entries: { { number | Color } }): Field
	return Field.vgrad(width, height, Common.stops(entries))
end

local function ones(width: number, height: number): Field
	return Field.new(width, height, 1, 1.0)
end

local function gild(canvas: Canvas, mask: Field, blurRadius: number, distance: number, warm: number?)
	local w, h = mask.width, mask.height
	local warmth = warm or 0.0
	local angles = Numeric.linspace(0, math.pi, h)
	local bands = table.create(h, 0)
	for y = 1, h do
		bands[y] = math.cos(angles[y]) * 0.5 + 0.5
	end
	local body = Field.generate(w, h, 3, function(_x: number, y: number, channel: number): number
		local band = bands[y + 1]
		local value = GOLD[channel] * (0.86 + 0.30 * band) + GOLD_LIGHT[channel] * (0.10 * band)
		if warmth ~= 0 then
			value = value * (1 - warmth) + GOLD_HI[channel] * warmth
		end
		return Numeric.clamp(value, 0, 1)
	end)
	Canvas.paint(canvas, body, mask)
	local high, low = Field.emboss(mask, blurRadius, distance)
	Canvas.paint(canvas, GOLD_HI, scale(high, 0.85))
	Canvas.paint(canvas, GOLD_SHADOW, scale(low, 0.80))
end

local function velvetField(random: Generator, w: number, h: number, tone: Color?, deep: Color?): Field
	local toneColor = tone or VELVET
	local deepColor = deep or VELVET_DEEP
	local n = Common.fbm(random, w, h, 5, 3, 2)
	local fine = Common.fbm(random, w, h, 6, 3, 2)
	return Field.generate(w, h, 3, function(x: number, y: number, channel: number): number
		local t = Numeric.clamp(0.42 * Field.at(n, x, y) + 0.28 * Field.at(fine, x, y) + 0.15, 0, 1)
		return deepColor[channel] * (1 - t) + toneColor[channel] * t
	end)
end

local function edgeVignette(w: number, h: number, border: number, strength: number, power: number): Field
	local distance = Common.edgeDistance(w, h)
	return Field.generate(w, h, 1, function(x: number, y: number): number
		return Numeric.clamp(1.0 - distance(x, y) / math.max(1.0, border), 0, 1) ^ power * strength
	end)
end

local function scrollPoints(
	cx: number,
	cy: number,
	a: number,
	b: number,
	t0: number,
	t1: number,
	count: number?,
	rotation: number?
): { number }
	local n = count or 90
	local rot = rotation or 0.0
	local ts = Numeric.linspace(t0, t1, n)
	local points = table.create(n * 2, 0)
	for index = 1, n do
		local r = a + b * ts[index]
		points[index * 2 - 1] = cx + r * math.cos(ts[index] + rot)
		points[index * 2] = cy + r * math.sin(ts[index] + rot)
	end
	return points
end

local function uniformCenter(c: Canvas, border: number)
	local middle = c.width // 2
	for y = 0, c.height - 1 do
		for x = border, c.width - border - 1 do
			for channel = 1, 3 do
				Field.set(c.rgb, x, y, Field.at(c.rgb, middle, y, channel), channel)
			end
			Field.set(c.alpha, x, y, Field.at(c.alpha, middle, y))
		end
	end
end

local function darken(c: Canvas, factor: number)
	c.rgb = scale(c.rgb, factor)
end

local function panelFill(random: Generator): Image
	local w, h = 128, 128
	local c = Canvas.new(w, h)
	Canvas.paint(c, velvetField(random, w, h), ones(w, h))
	Canvas.paint(c, VELVET_DEEP, edgeVignette(w, h, 32, 0.72, 1.4))
	local m = Common.mask(w, h)
	m:rring({ 9, 9, w - 10, h - 10 }, 4, 1)
	Canvas.paint(c, GOLD_DARK, scale(m:arr(), 0.55))
	return Canvas.image(c)
end

local function panelFrame(): Image
	local w, h = 160, 160
	local c = Canvas.new(w, h)
	local band = Common.mask(w, h)
	band:rring({ 2, 2, w - 3, h - 3 }, 8, 5)
	band:rring({ 10, 10, w - 11, h - 11 }, 5, 2)
	band:rring({ 15, 15, w - 16, h - 16 }, 4, 7)
	band:rring({ 26, 26, w - 27, h - 27 }, 3, 2)
	local bandMask = band:arr()
	gild(c, bandMask, 0.9, 1)

	local beads = Common.mask(w, h)
	local step, r = 10, 2.2
	for i = 0, w // step - 1 do
		local x = step / 2 + i * step
		beads:ellipse({ x - r, 18.5 - r, x + r, 18.5 + r })
		beads:ellipse({ x - r, h - 18.5 - r, x + r, h - 18.5 + r })
	end
	for i = 0, h // step - 1 do
		local y = step / 2 + i * step
		beads:ellipse({ 18.5 - r, y - r, 18.5 + r, y + r })
		beads:ellipse({ w - 18.5 - r, y - r, w - 18.5 + r, y + r })
	end
	local beadMask = Field.product(beads:arr(), bandMask)
	local high, low = Field.emboss(beadMask, 0.7, 1)
	Canvas.paint(c, GOLD_HI, scale(high, 0.9))
	Canvas.paint(c, GOLD_SHADOW, scale(low, 0.7))

	local corner = Common.mask(40, 40)
	corner:poly({ 28, 39, 39, 28, 39, 39 })
	corner:stroke({ 39, 24, 32, 28, 28, 32, 24, 39 }, 3.4)
	corner:stroke(scrollPoints(30.0, 30.0, 1.8, 1.75, 0.0, 5.9, nil, 2.2), 3.0)
	for _, spec in { { 0.60, 20.0 }, { 1.06, 16.5 }, { 0.14, 16.5 } } do
		local a, length = spec[1], spec[2]
		local x0, y0 = 30.0, 30.0
		local points: { number } = {}
		for _, t in { 0.0, 0.55, 1.0 } do
			table.insert(points, x0 - length * math.cos(a) * t)
			table.insert(points, y0 - length * math.sin(a) * t)
		end
		corner:stroke(points, 2.8)
		local ex, ey = points[5], points[6]
		corner:ellipse({ ex - 2.3, ey - 2.3, ex + 2.3, ey + 2.3 })
	end
	corner:ellipse({ 26.6, 26.6, 33.4, 33.4 })
	local topLeft = Field.flip(corner:arr(), true, true)
	local quarters: { { x: number, y: number, mask: Field } } = {
		{ x = 0, y = 0, mask = topLeft },
		{ x = w - 40, y = 0, mask = Field.flip(topLeft, true, false) },
		{ x = 0, y = h - 40, mask = Field.flip(topLeft, false, true) },
		{ x = w - 40, y = h - 40, mask = Field.flip(topLeft, true, true) },
	}
	local seat = Field.new(w, h, 1)
	for _, quarter in quarters do
		Field.maximumInto(seat, quarter.mask, quarter.x, quarter.y)
	end
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(seat, 1.6), 0.75))
	local full = Field.new(w, h, 1)
	for _, quarter in quarters do
		Field.maximumInto(full, quarter.mask, quarter.x, quarter.y)
	end
	gild(c, full, 0.8, 1, 0.10)

	local hole = Common.mask(w, h)
	hole:rrect({ 30, 30, w - 31, h - 31 }, 4)
	local keep = Field.map(hole:arr(), function(value: number): number
		return 1.0 - value
	end)
	c.alpha = Field.product(c.alpha, keep)
	return Canvas.image(c)
end

local function cornerOrnament(): Image
	local s = 48
	local c = Canvas.new(s, s)
	local m = Common.mask(s, s)
	m:poly({ 2, 2, 44, 2, 44, 7, 9, 7, 9, 44, 2, 44 })
	m:poly({ 2, 2, 18, 2, 2, 18 })
	m:stroke({ 44, 4.5, 46, 6.5 }, 2.0)
	m:stroke({ 14, 12, 36, 12 }, 2.2)
	m:stroke({ 12, 14, 12, 36 }, 2.2)
	m:stroke(scrollPoints(35.0, 15.0, 1.0, 1.05, 0.0, 4.6, nil, 4.4), 2.0)
	m:stroke(scrollPoints(15.0, 35.0, 1.0, 1.05, 0.0, 4.6, nil, 2.9), 2.0)
	m:stroke(scrollPoints(17.5, 17.5, 1.6, 1.9, 0.0, 5.8, nil, 0.8), 3.0)
	for _, spec in { { 0.30, 20.0 }, { 0.78, 17.0 }, { 1.26, 20.0 } } do
		local a, length = spec[1], spec[2]
		local x0, y0 = 17.0, 17.0
		local points: { number } = {}
		for _, t in { 0.0, 0.55, 1.0 } do
			table.insert(points, x0 + length * math.cos(a) * t)
			table.insert(points, y0 + length * math.sin(a) * t)
		end
		m:stroke(points, 2.4)
		local ex, ey = points[5], points[6]
		m:ellipse({ ex - 2.1, ey - 2.1, ex + 2.1, ey + 2.1 })
	end
	m:ellipse({ 13.0, 13.0, 22.0, 22.0 })
	local mask = m:arr()
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(mask, 1.8), 0.55))
	gild(c, mask, 0.8, 1, 0.12)
	local jewel = Common.mask(s, s)
	jewel:ellipse({ 14.4, 14.4, 20.6, 20.6 })
	Canvas.paint(c, RUBY, jewel:arr())
	local glint = Common.mask(s, s)
	glint:ellipse({ 15.6, 15.4, 18.4, 18.0 })
	Canvas.paint(c, RUBY_HI, scale(glint:arr(), 0.9))
	return Canvas.image(c)
end

local function edgeRail(): Image
	local w, h = 64, 24
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 0, 5, w - 1, h - 6 }, 3)
	local bodyMask = body:arr()
	gild(c, bodyMask, 0.8, 1)
	local rib = Common.mask(w, h)
	local period = 16
	for _, phase in { 0.0, math.pi } do
		local points: { number } = {}
		for x = 0, (w + 1) * 2 - 1 do
			local xx = x / 2.0
			table.insert(points, xx)
			table.insert(points, h / 2 + 3.1 * math.sin(2 * math.pi * xx / period + phase))
		end
		rib:stroke(points, 1.6, false)
	end
	local ribMask = Field.product(rib:arr(), bodyMask)
	local high, low = Field.emboss(ribMask, 0.6, 1)
	Canvas.paint(c, GOLD_HI, scale(high, 0.85))
	Canvas.paint(c, GOLD_SHADOW, scale(low, 0.75))
	local studs = Common.mask(w, h)
	for i = 0, w // period - 1 do
		local x = period / 2 + i * period
		studs:ellipse({ x - 2.6, h / 2 - 2.6, x + 2.6, h / 2 + 2.6 })
	end
	Canvas.paint(c, RUBY, Field.product(studs:arr(), bodyMask))
	local shine = Common.mask(w, h)
	for i = 0, w // period - 1 do
		local x = period / 2 + i * period
		shine:ellipse({ x - 1.5, h / 2 - 1.7, x + 0.2, h / 2 - 0.1 })
	end
	Canvas.paint(c, RUBY_HI, scale(shine:arr(), 0.9))
	return Canvas.image(c)
end

local function plaque(random: Generator): Image
	local w, h = 176, 56
	local c = Canvas.new(w, h)
	local outer = Common.mask(w, h)
	outer:rrect({ 2, 4, w - 3, h - 5 }, 8)
	local outerMask = outer:arr()
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(outerMask, 2.0), 0.5))
	gild(c, outerMask, 1.1, 1)
	local face = Common.mask(w, h)
	face:rrect({ 9, 11, w - 10, h - 12 }, 5)
	local faceMask = face:arr()
	Canvas.paint(c, velvetField(random, w, h, rgb(64, 30, 50)), faceMask)
	local high, low = Field.emboss(faceMask, 1.0, 1)
	Canvas.paint(c, INK, scale(high, 0.75))
	Canvas.paint(c, GOLD_LIGHT, scale(low, 0.35))
	local rim = Common.mask(w, h)
	rim:rring({ 9, 11, w - 10, h - 12 }, 5, 1)
	Canvas.paint(c, GOLD_LIGHT, scale(rim:arr(), 0.8))
	return Canvas.image(c)
end

type ButtonStyle = { faceLow: Color, faceHigh: Color, warm: number, inset: boolean, rimGold: boolean }

local function buttonCommon(random: Generator, size: number, style: ButtonStyle): Canvas
	local w, h = size, size
	local c = Canvas.new(w, h)
	local outer = Common.mask(w, h)
	outer:rrect({ 1, 1, w - 2, h - 2 }, 7)
	gild(c, outer:arr(), 1.0, 1, style.warm)
	local step = Common.mask(w, h)
	step:rring({ 5, 5, w - 6, h - 6 }, 5, 2)
	Canvas.paint(c, if style.rimGold then GOLD_HI else GOLD_SHADOW, scale(step:arr(), 0.6))
	local face = Common.mask(w, h)
	face:rrect({ 8, 8, w - 9, h - 9 }, 4)
	local faceMask = face:arr()
	local gradient =
		grad(w, h, { { 0.0, style.faceHigh }, { 0.55, style.faceLow }, { 1.0, times(style.faceLow, 0.82) } })
	local texture = velvetField(random, w, h, rgb(70, 34, 54))
	local mixed = Field.zip(gradient, texture, function(g: number, t: number): number
		return Numeric.clamp(g * 0.72 + t * 0.28, 0, 1)
	end)
	Canvas.paint(c, mixed, faceMask)
	local high, low = Field.emboss(faceMask, 1.0, 1)
	if style.inset then
		Canvas.paint(c, INK, scale(high, 0.85))
		Canvas.paint(c, GOLD_LIGHT, scale(low, 0.30))
	else
		Canvas.paint(c, GOLD_HI, scale(high, 0.30))
		Canvas.paint(c, INK, scale(low, 0.55))
	end
	return c
end

local BUTTONS: { [string]: ButtonStyle } = {
	default = { faceLow = rgb(52, 26, 42), faceHigh = rgb(86, 44, 66), warm = 0.0, inset = false, rimGold = false },
	hover = { faceLow = rgb(78, 40, 60), faceHigh = rgb(116, 62, 88), warm = 0.26, inset = false, rimGold = true },
	pressed = { faceLow = rgb(30, 14, 25), faceHigh = rgb(44, 22, 36), warm = 0.0, inset = true, rimGold = false },
}

local function button(random: Generator, state: string): Image
	local c = buttonCommon(random, 64, BUTTONS[state])
	local w, h = 64, 64
	if state == "pressed" then
		darken(c, 0.72)
		local shade = Common.mask(w, h)
		shade:rrect({ 8, 8, w - 9, 20 }, 4)
		Canvas.paint(c, INK, scale(Field.blur(shade:arr(), 2.2), 0.45))
	end
	if state == "hover" then
		local glow = Common.mask(w, h)
		glow:rring({ 1, 1, w - 2, h - 2 }, 7, 2)
		Canvas.paint(c, GOLD_HI, scale(Field.blur(glow:arr(), 1.4), 0.55))
	end
	return Canvas.image(c)
end

local function selection(random: Generator, state: string): Image
	local w, h = 64, 64
	local c = Canvas.new(w, h)
	if state == "default" then
		local plate = Common.mask(w, h)
		plate:rrect({ 2, 2, w - 3, h - 3 }, 6)
		local plateMask = plate:arr()
		Canvas.paint(c, scale(velvetField(random, w, h, rgb(48, 24, 38)), 0.8), scale(plateMask, 0.92))
		local rim = Common.mask(w, h)
		rim:rring({ 2, 2, w - 3, h - 3 }, 6, 1)
		Canvas.paint(c, GOLD_DARK, scale(rim:arr(), 0.65))
		return Canvas.image(c)
	end
	local outer = Common.mask(w, h)
	outer:rrect({ 0, 0, w - 1, h - 1 }, 7)
	gild(c, outer:arr(), 1.0, 1, 0.28)
	local inner = Common.mask(w, h)
	inner:rring({ 4, 4, w - 5, h - 5 }, 5, 2)
	Canvas.paint(c, GOLD_HI, scale(inner:arr(), 0.8))
	local face = Common.mask(w, h)
	face:rrect({ 8, 8, w - 9, h - 9 }, 4)
	local faceMask = face:arr()
	Canvas.paint(
		c,
		grad(w, h, { { 0.0, rgb(24, 66, 52) }, { 0.5, rgb(16, 46, 38) }, { 1.0, rgb(10, 30, 26) } }),
		faceMask
	)
	local glow = Field.product(Field.blur(faceMask, 3.0), faceMask)
	Canvas.paint(c, EMERALD_HI, scale(glow, 0.22))
	local high, low = Field.emboss(faceMask, 1.0, 1)
	Canvas.paint(c, INK, scale(high, 0.6))
	Canvas.paint(c, EMERALD_HI, scale(low, 0.35))
	for _, centre in { { 8, 8 }, { w - 9, 8 }, { 8, h - 9 }, { w - 9, h - 9 } } do
		local cx, cy = centre[1], centre[2]
		local gem = Common.mask(w, h)
		gem:ellipse({ cx - 4.2, cy - 4.2, cx + 4.2, cy + 4.2 })
		gild(c, gem:arr(), 0.6, 1, 0.5)
		local stone = Common.mask(w, h)
		stone:ellipse({ cx - 2.8, cy - 2.8, cx + 2.8, cy + 2.8 })
		Canvas.paint(c, RUBY, stone:arr())
		local glint = Common.mask(w, h)
		glint:ellipse({ cx - 1.9, cy - 1.9, cx - 0.1, cy - 0.3 })
		Canvas.paint(c, RUBY_HI, scale(glint:arr(), 0.95))
	end
	return Canvas.image(c)
end

local function fieldPlate(): Image
	local w, h = 64, 64
	local c = Canvas.new(w, h)
	local outer = Common.mask(w, h)
	outer:rrect({ 1, 1, w - 2, h - 2 }, 6)
	gild(c, outer:arr(), 1.0, 1)
	local well = Common.mask(w, h)
	well:rrect({ 6, 6, w - 7, h - 7 }, 4)
	local wellMask = well:arr()
	Canvas.paint(
		c,
		grad(w, h, { { 0.0, rgb(18, 12, 16) }, { 0.45, rgb(30, 20, 28) }, { 1.0, rgb(38, 26, 34) } }),
		wellMask
	)
	local high, low = Field.emboss(wellMask, 1.4, 2)
	Canvas.paint(c, INK, scale(high, 0.95))
	Canvas.paint(c, GOLD_LIGHT, scale(low, 0.28))
	local rim = Common.mask(w, h)
	rim:rring({ 6, 6, w - 7, h - 7 }, 4, 1)
	Canvas.paint(c, GOLD_DARK, scale(rim:arr(), 0.7))
	return Canvas.image(c)
end

local function barTrack(): Image
	local w, h = 96, 28
	local c = Canvas.new(w, h)
	local outer = Common.mask(w, h)
	outer:rrect({ 0, 1, w - 1, h - 2 }, 9)
	gild(c, outer:arr(), 1.0, 1)
	local groove = Common.mask(w, h)
	groove:rrect({ 5, 6, w - 6, h - 7 }, 5)
	local grooveMask = groove:arr()
	Canvas.paint(
		c,
		grad(w, h, { { 0.0, rgb(14, 8, 12) }, { 0.6, rgb(26, 16, 24) }, { 1.0, rgb(34, 22, 30) } }),
		grooveMask
	)
	local high, low = Field.emboss(grooveMask, 1.3, 2)
	Canvas.paint(c, INK, scale(high, 0.95))
	Canvas.paint(c, GOLD_LIGHT, scale(low, 0.30))
	local rim = Common.mask(w, h)
	rim:rring({ 5, 6, w - 6, h - 7 }, 5, 1)
	Canvas.paint(c, GOLD_DARK, scale(rim:arr(), 0.8))
	return Canvas.image(c)
end

local function barFill(): Image
	local w, h = 96, 20
	local c = Canvas.new(w, h)
	local body = Common.mask(w, h)
	body:rrect({ 0, 0, w - 1, h - 1 }, 6)
	local bodyMask = body:arr()
	Canvas.paint(
		c,
		grad(w, h, {
			{ 0.00, rgb(255, 226, 150) },
			{ 0.22, AMBER },
			{ 0.55, rgb(226, 122, 26) },
			{ 0.80, rgb(168, 66, 16) },
			{ 1.00, rgb(120, 40, 12) },
		}),
		bodyMask
	)
	local gloss = Common.mask(w, h)
	gloss:rrect({ 0, 2, w - 1, 6 }, 2)
	Canvas.paint(c, AMBER_HI, scale(Field.product(Field.blur(gloss:arr(), 1.2), bodyMask), 0.55))
	local ring = Common.mask(w, h)
	ring:rring({ 0, 0, w - 1, h - 1 }, 6, 1)
	Canvas.paint(c, rgb(255, 246, 214), scale(ring:arr(), 0.45))
	uniformCenter(c, 8)
	return Canvas.image(c)
end

local function barCap(side: string): Image
	local w, h = 28, 36
	local c = Canvas.new(w, h)
	local m = Common.mask(w, h)
	m:poly({ 3, 18, 11, 3, 24, 8, 24, 28, 11, 33 })
	m:ellipse({ 12, 11, 26, 25 })
	m:stroke(scrollPoints(9, 18, 1.0, 1.1, 0.0, 4.2, nil, 1.6), 2.4)
	local mask = m:arr()
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(mask, 1.8), 0.5))
	gild(c, mask, 0.9, 1, 0.2)
	local jewel = Common.mask(w, h)
	jewel:ellipse({ 15, 14, 23, 22 })
	Canvas.paint(c, RUBY, jewel:arr())
	local glint = Common.mask(w, h)
	glint:ellipse({ 16.2, 15.2, 19.4, 18.0 })
	Canvas.paint(c, RUBY_HI, scale(glint:arr(), 0.9))
	local image = Canvas.image(c)
	return if side == "start" then image else Image.flipLeftRight(image)
end

local function barCenter(): Image
	local w, h = 36, 28
	local c = Canvas.new(w, h)
	local m = Common.mask(w, h)
	m:poly({ 4, 22, 6, 8, 12, 15, 18, 4, 24, 15, 30, 8, 32, 22 })
	m:rect({ 4, 20, 32, 25 })
	local mask = m:arr()
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(mask, 1.8), 0.5))
	gild(c, mask, 0.8, 1, 0.22)
	local gems: { { x: number, y: number, color: Color } } = {
		{ x = 6.5, y = 8.5, color = EMERALD },
		{ x = 18, y = 5.5, color = RUBY },
		{ x = 29.5, y = 8.5, color = EMERALD },
	}
	for _, gem in gems do
		local g = Common.mask(w, h)
		g:ellipse({ gem.x - 2.3, gem.y - 2.3, gem.x + 2.3, gem.y + 2.3 })
		Canvas.paint(c, gem.color, g:arr())
	end
	local band = Common.mask(w, h)
	band:rect({ 5, 21.5, 31, 23.5 })
	Canvas.paint(c, RUBY, scale(band:arr(), 0.75))
	return Canvas.image(c)
end

local function toggleTrack(state: string): Image
	local w, h = 72, 32
	local c = Canvas.new(w, h)
	local on = state == "on"
	local outer = Common.mask(w, h)
	outer:rrect({ 0, 1, w - 1, h - 2 }, 12)
	gild(c, outer:arr(), 1.0, 1, if on then 0.25 else 0.0)
	local channel = Common.mask(w, h)
	channel:rrect({ 4, 5, w - 5, h - 6 }, 9)
	local channelMask = channel:arr()
	if on then
		Canvas.paint(
			c,
			grad(w, h, { { 0.0, rgb(70, 178, 122) }, { 0.5, EMERALD }, { 1.0, rgb(14, 66, 46) } }),
			channelMask
		)
		Canvas.paint(c, EMERALD_HI, scale(Field.product(Field.blur(channelMask, 3.0), channelMask), 0.25))
	else
		Canvas.paint(
			c,
			grad(w, h, { { 0.0, rgb(20, 14, 20) }, { 0.5, rgb(34, 24, 32) }, { 1.0, rgb(46, 34, 42) } }),
			channelMask
		)
	end
	local high, low = Field.emboss(channelMask, 1.3, 2)
	Canvas.paint(c, INK, scale(high, if on then 0.7 else 0.95))
	Canvas.paint(c, GOLD_LIGHT, scale(low, 0.30))
	local rim = Common.mask(w, h)
	rim:rring({ 4, 5, w - 5, h - 6 }, 9, 1)
	Canvas.paint(c, if on then GOLD_LIGHT else GOLD_DARK, scale(rim:arr(), 0.75))
	return Canvas.image(c)
end

local function toggleKnob(state: string): Image
	local s = 28
	local c = Canvas.new(s, s)
	local default = state == "default"
	local ring = Common.mask(s, s)
	ring:ellipse({ 1, 1, s - 2, s - 2 })
	local ringMask = ring:arr()
	Canvas.paint(c, GOLD_SHADOW, scale(Field.blur(ringMask, 1.8), 0.55))
	gild(c, ringMask, 0.9, 1, if default then 0.3 else 0.0)
	local jewel = Common.mask(s, s)
	jewel:ellipse({ 6, 6, s - 7, s - 7 })
	local jewelMask = jewel:arr()
	local gradient = grad(s, s, { { 0.0, rgb(214, 74, 92) }, { 0.45, RUBY }, { 1.0, rgb(84, 14, 28) } })
	Canvas.paint(c, if default then gradient else scale(gradient, 0.62), jewelMask)
	local glint = Common.mask(s, s)
	glint:ellipse({ 9, 8.5, 14, 12.5 })
	Canvas.paint(c, RUBY_HI, scale(glint:arr(), if default then 0.95 else 0.45))
	if state == "pressed" then
		darken(c, 0.78)
		local shade = Common.mask(s, s)
		shade:ellipse({ 5, 5, s - 6, s - 6 })
		Canvas.paint(c, INK, scale(Field.blur(shade:arr(), 1.6), 0.28))
	end
	return Canvas.image(c)
end

local function stepperPlate(state: string): Image
	local w, h = 40, 40
	local c = Canvas.new(w, h)
	local outer = Common.mask(w, h)
	outer:rrect({ 1, 1, w - 2, h - 2 }, 6)
	gild(c, outer:arr(), 0.9, 1, if state == "default" then 0.15 else 0.0)
	local face = Common.mask(w, h)
	face:rrect({ 6, 6, w - 7, h - 7 }, 3)
	local faceMask = face:arr()
	if state == "default" then
		Canvas.paint(c, grad(w, h, { { 0.0, rgb(84, 42, 64) }, { 1.0, rgb(46, 22, 38) } }), faceMask)
		local high, low = Field.emboss(faceMask, 1.0, 1)
		Canvas.paint(c, GOLD_HI, scale(high, 0.28))
		Canvas.paint(c, INK, scale(low, 0.5))
	else
		Canvas.paint(c, grad(w, h, { { 0.0, rgb(26, 12, 22) }, { 1.0, rgb(42, 20, 34) } }), faceMask)
		local high, low = Field.emboss(faceMask, 1.2, 2)
		Canvas.paint(c, INK, scale(high, 0.9))
		Canvas.paint(c, GOLD_LIGHT, scale(low, 0.3))
		darken(c, 0.8)
	end
	return Canvas.image(c)
end

local function icon(name: string): Image
	local s = 32
	local m = Common.mask(s, s)
	local c = Canvas.new(s, s)
	if name == "chevron_right" then
		m:stroke({ 12, 7, 21, 16, 12, 25 }, 3.6)
	elseif name == "chevron_down" then
		m:stroke({ 7, 12, 16, 21, 25, 12 }, 3.6)
	elseif name == "plus" then
		m:rrect({ 14.2, 6, 17.8, 26 }, 1.6)
		m:rrect({ 6, 14.2, 26, 17.8 }, 1.6)
	elseif name == "minus" then
		m:rrect({ 6, 14.2, 26, 17.8 }, 1.6)
	elseif name == "check" then
		m:stroke({ 7, 17, 13.5, 23.5, 25, 9 }, 3.8)
	elseif name == "cross" then
		m:stroke({ 9, 9, 23, 23 }, 3.6)
		m:stroke({ 23, 9, 9, 23 }, 3.6)
	elseif name == "gear" then
		local cx, cy = 16.0, 16.0
		local outerRadius, innerRadius = 14.2, 10.2
		local count = 8
		local span = 2 * math.pi / count
		local points: { number } = {}
		for i = 0, count - 1 do
			local a0 = i * span - math.pi / 2
			for _, spec in
				{ { outerRadius, -0.20 }, { outerRadius, 0.20 }, { innerRadius, 0.30 }, { innerRadius, 0.70 } }
			do
				local radius, offset = spec[1], spec[2]
				local angle = if offset < 0 then a0 - span * 0.20 else a0 + span * offset
				table.insert(points, cx + radius * math.cos(angle))
				table.insert(points, cy + radius * math.sin(angle))
			end
		end
		m:poly(points)
		m:ellipse({ cx - 10.2, cy - 10.2, cx + 10.2, cy + 10.2 })
		local hole = Common.mask(s, s)
		hole:ellipse({ cx - 4.6, cy - 4.6, cx + 4.6, cy + 4.6 })
		Canvas.paint(c, ICON_WHITE, Field.difference(m:arr(), hole:arr()))
		return Canvas.image(c)
	else
		error(name, 2)
	end
	Canvas.paint(c, ICON_WHITE, m:arr())
	return Canvas.image(c)
end

local function velvetTile(random: Generator): Image
	local w, h = 64, 64
	local c = Canvas.new(w, h)
	local base = velvetField(random, w, h)
	local ax = Numeric.linspace(0, 2 * math.pi, w, false)
	local ay = Numeric.linspace(0, 2 * math.pi, h, false)
	for index = 1, w do
		ax[index] = math.cos(ax[index]) * 0.5 + 0.5
	end
	for index = 1, h do
		ay[index] = math.cos(ay[index]) * 0.5 + 0.5
	end
	local rolled = Field.roll(base, w // 2, h // 2)
	local blended = Field.generate(w, h, 3, function(x: number, y: number, channel: number): number
		local weight = ax[x + 1] * ay[y + 1]
		local value = Field.at(base, x, y, channel) * weight + Field.at(rolled, x, y, channel) * (1 - weight)
		return Numeric.clamp(value, 0, 1)
	end)
	Canvas.paint(c, blended, ones(w, h))
	local motif = Common.mask(w, h)
	local offsets = {
		{ 0, 0 },
		{ w, 0 },
		{ 0, h },
		{ w, h },
		{ w // 2, h // 2 },
		{ -w // 2, h // 2 },
		{ w // 2, -h // 2 },
		{ 3 * w // 2, h // 2 },
		{ w // 2, 3 * h // 2 },
	}
	for _, offset in offsets do
		local ox, oy = offset[1], offset[2]
		motif:poly({ ox, oy - 11, ox + 7, oy, ox, oy + 11, ox - 7, oy })
		motif:stroke(scrollPoints(ox, oy, 1.0, 1.0, 0.0, 3.4), 1.4)
	end
	Canvas.paint(c, VELVET_HI, scale(motif:arr(), 0.42))
	return Canvas.image(c)
end

local FantasyOrnate = {}

FantasyOrnate.name = "fantasy-ornate"
FantasyOrnate.summary = "fantasy-ornate theme package art"

function FantasyOrnate.generate(): { Common.Output }
	local function r(key: number): Generator
		return Raster.Random.new(SEED + key)
	end
	local items: { Common.Item } = {}
	local function add(name: string, image: Image, border: number?, previews: { { number } }?)
		table.insert(items, { name = name, image = image, border = border, previews = previews })
	end
	add("ornate_panel_fill.png", panelFill(r(1)), 32, { { 180, 110 }, { 320, 200 }, { 460, 130 } })
	add("ornate_panel_frame.png", panelFrame(), 40, { { 180, 140 }, { 330, 210 }, { 470, 150 } })
	local joined = Common.nineSlice(panelFill(r(1)), 32, 160, 160)
	Image.alphaComposite(joined, panelFrame())
	add("ornate_panel_tail.png", Common.panelTail(joined, 32, 12, 8))
	local topLeft = cornerOrnament()
	add("ornate_corner_tl.png", topLeft)
	add("ornate_corner_tr.png", Image.flipLeftRight(topLeft))
	add("ornate_corner_bl.png", Image.flipTopBottom(topLeft))
	add("ornate_corner_br.png", Image.rotate180(topLeft))
	add("ornate_edge_rail.png", edgeRail())
	add("ornate_plaque.png", plaque(r(5)), 20, { { 140, 56 }, { 240, 56 }, { 380, 56 } })
	for index, state in { "default", "hover", "pressed" } do
		add(`ornate_button_{state}.png`, button(r(9 + index), state), 16, { { 140, 44 } })
	end
	for index, state in { "default", "selected" } do
		add(`ornate_selection_{state}.png`, selection(r(19 + index), state), 16, { { 200, 44 } })
	end
	add("ornate_field.png", fieldPlate(), 16, { { 160, 44 }, { 280, 44 }, { 160, 64 } })
	add("ornate_bar_track.png", barTrack(), 12, { { 120, 28 }, { 240, 28 }, { 360, 28 } })
	add("ornate_bar_fill.png", barFill(), 8, { { 40, 20 }, { 140, 20 }, { 300, 20 } })
	add("ornate_bar_cap_start.png", barCap("start"))
	add("ornate_bar_cap_end.png", barCap("end"))
	add("ornate_bar_center.png", barCenter())
	for _, state in { "off", "on" } do
		add(`ornate_toggle_track_{state}.png`, toggleTrack(state), 14, { { 72, 32 }, { 96, 32 } })
	end
	for _, state in { "default", "pressed" } do
		add(`ornate_toggle_knob_{state}.png`, toggleKnob(state))
	end
	for _, state in { "default", "pressed" } do
		add(`ornate_stepper_plate_{state}.png`, stepperPlate(state), 12, { { 40, 40 }, { 64, 40 } })
	end
	add("ornate_velvet_tile.png", velvetTile(r(70)))
	local iconNames = { "chevron_right", "chevron_down", "plus", "minus", "check", "cross", "gear" }
	for _, name in iconNames do
		add(`ornate_icon_{name}.png`, icon(name))
	end
	local outputs, by = Common.outputs(DIRECTORY, items)

	local sheet = Common.sheet("fantasy-ornate — nine-slice stretch test + whole-image assets")
	local function row(label: string, names: { string }, sizes: { { number } }?)
		sheet:add(label, Common.stretch(by, names, sizes))
	end
	row("panel fill  (128x128 b32) stretched 180x110 / 320x200 / 460x130", { "ornate_panel_fill.png" })
	row("panel frame (160x160 b40) stretched — corners must stay crisp", { "ornate_panel_frame.png" })
	row(
		"corner ornaments tl / tr / bl / br (48x48 whole)",
		{ "ornate_corner_tl.png", "ornate_corner_tr.png", "ornate_corner_bl.png", "ornate_corner_br.png" }
	)
	local rail = by["ornate_edge_rail.png"].image
	local tiled = Image.new(384, 24, 4)
	for i = 0, 5 do
		Image.alphaComposite(tiled, rail, i * 64, 0)
	end
	sheet:add("edge rail 64x24 — TILED x6 (tile-only asset, period 64; seam must be invisible)", { tiled })
	row("plaque (176x56 b20) stretched — blank board, text is a live sub-slot", { "ornate_plaque.png" })
	row(
		"button default / hover / pressed @140x44 (same insets, different art)",
		{ "ornate_button_default.png", "ornate_button_hover.png", "ornate_button_pressed.png" }
	)
	row(
		"button default @ 80x44 / 240x44 / 140x88 — slice stress",
		{ "ornate_button_default.png" },
		{ { 80, 44 }, { 240, 44 }, { 140, 88 } }
	)
	row(
		"selection default / selected @200x44 — 'selected' is a new construction",
		{ "ornate_selection_default.png", "ornate_selection_selected.png" }
	)
	row("field (64x64 b16) stretched", { "ornate_field.png" })
	row("bar track (96x28 b12) stretched", { "ornate_bar_track.png" })
	row("bar fill (96x20 b8) stretched 40 / 140 / 300 px", { "ornate_bar_fill.png" })
	local track = by["ornate_bar_track.png"].image
	local fill = by["ornate_bar_fill.png"].image
	local capStart = by["ornate_bar_cap_start.png"].image
	local capEnd = by["ornate_bar_cap_end.png"].image
	local crown = by["ornate_bar_center.png"].image
	local assembled: { Image } = {}
	for _, pct in { 0.15, 0.55, 1.0 } do
		local bw, bh = 300, 36
		local comp = Image.new(bw, bh, 4)
		Image.alphaComposite(comp, Common.nineSlice(track, 12, bw - 24, 28), 12, 4)
		local full = Common.nineSlice(fill, 8, bw - 34, 20)
		Image.alphaComposite(comp, Common.clipped(full, math.max(1, Numeric.trunc((bw - 34) * pct)), 20), 17, 8)
		Image.alphaComposite(comp, capStart, 0, 0)
		Image.alphaComposite(comp, capEnd, bw - 28, 0)
		Image.alphaComposite(comp, crown, (bw - 36) // 2, 4)
		table.insert(assembled, comp)
	end
	sheet:add("assembled bar: track + window-clipped fill (15/55/100%) + caps + crown", assembled)
	row("toggle track off / on (72x32 b14) + knob default / pressed (28x28)", {
		"ornate_toggle_track_off.png",
		"ornate_toggle_track_on.png",
		"ornate_toggle_knob_default.png",
		"ornate_toggle_knob_pressed.png",
	})
	row(
		"stepper plate default / pressed (40x40 b12) at 40x40 and 64x40",
		{ "ornate_stepper_plate_default.png", "ornate_stepper_plate_pressed.png" }
	)
	local tile = by["ornate_velvet_tile.png"].image
	local tiled2 = Image.new(256, 128, 4)
	for yy = 0, 1 do
		for xx = 0, 3 do
			Image.alphaComposite(tiled2, tile, xx * 64, yy * 64)
		end
	end
	sheet:add("velvet damask tile 64x64 — TILED 4x2 (seam check)", { tiled2 })
	local icons: { Image } = {}
	for _, name in iconNames do
		table.insert(icons, by[`ornate_icon_{name}.png`].image)
	end
	sheet:add("icons 32x32 near-white on transparency (chevron_right/down, plus, minus, check, cross, gear)", icons)
	table.insert(outputs, { path = `{DIRECTORY}/source/preview/contact-sheet.png`, image = sheet:render() })
	return outputs
end

return FantasyOrnate :: Common.Target
