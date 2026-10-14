--!strict

local Common = require("./common")
local Raster = require("../lib/raster")

local Blur = Raster.Blur
local Draw = Raster.Draw
local Field = Raster.Field
local Image = Raster.Image
local Numeric = Raster.Numeric

type Image = Raster.Image
type Field = Raster.Field
type Color = Raster.Color
type Generator = Raster.Generator

local DIRECTORY = "assets/themes/fantasy-parchment"
local SEED = 0x5EED

local PARCHMENT_LIGHT: Color = { 233, 218, 183 }
local PARCHMENT_DARK: Color = { 196, 172, 128 }
local EDGE_BROWN: Color = { 124, 96, 58 }
local INK: Color = { 62, 48, 34 }

local function noise(random: Generator, size: number, octaves: number): Field
	return Common.fbm(random, size, size, octaves, 4, 0)
end

local function bytes(image: Image): Field
	local field = Field.new(image.width, image.height, image.channels)
	for index = 0, image.width * image.height * image.channels - 1 do
		buffer.writef64(field.data, index * 8, buffer.readu8(image.data, index))
	end
	return field
end

local function unit(image: Image): Field
	return Field.map(bytes(image), function(value: number): number
		return value / 255.0
	end)
end

local function blend(sheet: Field, weights: Field, color: Color, factor: number?): Field
	local k = factor
	return Field.generate(sheet.width, sheet.height, 3, function(x: number, y: number, channel: number): number
		local weight = Field.at(weights, x, y)
		if k ~= nil then
			weight = k * weight
		end
		return Field.at(sheet, x, y, channel) * (1 - weight) + color[channel] * weight
	end)
end

local function parchmentBase(random: Generator, size: number): Field
	local base = noise(random, size, 5)
	local sheet = Field.generate(size, size, 3, function(x: number, y: number, channel: number): number
		local n = Field.at(base, x, y)
		return PARCHMENT_LIGHT[channel] * (1 - n) + PARCHMENT_DARK[channel] * n
	end)
	local streaks = noise(random, size, 2)
	local columns = size // 8
	local rows = table.create(size, 0)
	for y = 0, size - 1 do
		rows[y + 1] = Numeric.pairwiseSum(streaks.data, y * size * 8, columns, 1) / columns
	end
	sheet = Field.generate(size, size, 3, function(x: number, y: number, channel: number): number
		return Field.at(sheet, x, y, channel) + (rows[y + 1] - 0.5) * 14.0
	end)
	local stainLayer = Image.new(size, size, 1)
	for _ = 1, 4 do
		local centre = random:integers(0, size, 2)
		local cx, cy = centre[1], centre[2]
		local r = Numeric.trunc(size * (0.10 + 0.12 * random:random()))
		Draw.ellipse(stainLayer, { cx - r, cy - r, cx + r, cy + r }, { Numeric.trunc(28 + 30 * random:random()) })
	end
	local stain = unit(Blur.gaussian(stainLayer, size * 0.06))
	return Field.generate(size, size, 3, function(x: number, y: number, channel: number): number
		local s = Field.at(sheet, x, y, channel)
		local st = Field.at(stain, x, y)
		return s * (1 - st) + (s * 0.82 + EDGE_BROWN[channel] * 0.18) * st
	end)
end

local function deckleMask(random: Generator, size: number, margin: number): Field
	local mask = Image.new(size, size, 1)
	local steps = 64
	local points: { number } = {}
	for i = 0, steps * 4 - 1 do
		local t = i / (steps * 4)
		local per = t * 4
		local jitter = margin * (0.25 + 0.75 * random:random())
		local x, y
		if per < 1 then
			x, y = per * size, jitter
		elseif per < 2 then
			x, y = size - jitter, (per - 1) * size
		elseif per < 3 then
			x, y = size - (per - 2) * size, size - jitter
		else
			x, y = jitter, size - (per - 3) * size
		end
		table.insert(points, x)
		table.insert(points, y)
	end
	Draw.polygon(mask, points, { 255 })
	return unit(Blur.gaussian(mask, margin * 0.35))
end

local function ramp(size: number, border: number, power: number, strength: number): Field
	local distance = Common.edgeDistance(size, size)
	return Field.generate(size, size, 1, function(x: number, y: number): number
		return Numeric.clamp(1.0 - distance(x, y) / border, 0.0, 1.0) ^ power * strength
	end)
end

local function toImage(sheet: Field, alpha: Field): Image
	local out = Image.new(sheet.width, sheet.height, 4)
	for y = 0, sheet.height - 1 do
		for x = 0, sheet.width - 1 do
			local offset = (y * sheet.width + x) * 4
			for channel = 1, 3 do
				buffer.writeu8(
					out.data,
					offset + channel - 1,
					Numeric.trunc(Numeric.clamp(Field.at(sheet, x, y, channel), 0, 255))
				)
			end
			buffer.writeu8(out.data, offset + 3, Numeric.trunc(Field.at(alpha, x, y)))
		end
	end
	return out
end

local function compose(key: number, size: number, border: number, deckle: number, kind: string): Image
	local random = Raster.Random.new(SEED + key)
	local sheet = parchmentBase(random, size)
	if kind == "button" then
		local tint: Color = { 172, 132, 82 }
		sheet = Field.generate(size, size, 3, function(x: number, y: number, channel: number): number
			return Field.at(sheet, x, y, channel) * 0.86 + tint[channel] * 0.14
		end)
	elseif kind == "field" then
		sheet = Field.map(sheet, function(value: number): number
			return math.min(value * 1.06 + 8.0, 255.0)
		end)
		sheet = blend(sheet, ramp(size, border, 1.2, 0.16), PARCHMENT_DARK)
	end
	sheet = blend(sheet, ramp(size, border, 1.6, if kind == "panel" then 0.55 else 0.30), EDGE_BROWN)

	local line = Image.new(size, size, 1)
	local off = Numeric.trunc(deckle + border * 0.28)
	local box = { off, off, size - 1 - off, size - 1 - off }
	if kind == "button" then
		Draw.rectangle(line, box, nil, { 255 }, math.max(3, size // 20))
	elseif kind == "field" then
		Draw.rectangle(line, box, nil, { 210 }, math.max(1, size // 40))
	else
		local w = math.max(2, size // 48)
		Draw.rectangle(line, box, nil, { 255 }, w)
		local off2 = off + w + math.max(1, w // 2)
		Draw.rectangle(line, { off2, off2, size - 1 - off2, size - 1 - off2 }, nil, { 140 }, math.max(1, w // 2))
	end
	local lineField = unit(Blur.gaussian(line, 0.7))
	local fibre = noise(random, size, 3)
	lineField = Field.zip(lineField, fibre, function(l: number, f: number): number
		return l * (0.65 + 0.35 * f)
	end)
	sheet = blend(sheet, lineField, INK, 0.85)
	local alpha = Field.map(deckleMask(random, size, deckle), function(value: number): number
		return value * 255.0
	end)
	return toImage(sheet, alpha)
end

local function sliderTrack(random: Generator): Image
	local w, h = 96, 20
	local base = parchmentBase(random, 96)
	local sheet = Field.generate(w, h, 3, function(x: number, y: number, channel: number): number
		return Field.at(base, x, y, channel)
	end)
	local shade = Field.generate(w, h, 1, function(_x: number, y: number): number
		return Numeric.clamp(1.0 - math.min(y, h - 1 - y) / 7.0, 0, 1) ^ 1.4
	end)
	sheet = Field.generate(w, h, 3, function(x: number, y: number, channel: number): number
		local weight = Field.at(shade, x, y) * 0.5
		return Field.at(sheet, x, y, channel) * (1 - weight) + EDGE_BROWN[channel] * weight
	end)
	local groove = Image.new(w, h, 1)
	Draw.line(groove, { 4, h // 2, w - 4, h // 2 }, { 230 }, 3)
	sheet = blend(sheet, unit(Blur.gaussian(groove, 0.8)), INK, 0.8)
	local alpha = Field.new(w, h, 1, 255.0)
	for x = 0, 2 do
		for y = 0, h - 1 do
			Field.set(alpha, x, y, Field.at(alpha, x, y) * ((x + 1) / 4))
			Field.set(alpha, w - 1 - x, y, Field.at(alpha, w - 1 - x, y) * ((x + 1) / 4))
		end
	end
	return toImage(sheet, alpha)
end

local function sliderThumb(random: Generator): Image
	local s = 28
	local image = Image.new(s, s, 4)
	Draw.ellipse(image, { 1, 1, s - 2, s - 2 }, { 126, 42, 34, 255 })
	Draw.ellipse(image, { 3, 3, s - 4, s - 4 }, { 150, 52, 40, 255 })
	Draw.ellipse(image, { 7, 7, s - 8, s - 8 }, nil, { 96, 30, 24, 255 }, 2)
	Draw.ellipse(image, { 9, 8, 15, 12 }, { 196, 96, 80, 190 })
	local grain = noise(random, s, 3)
	local out = Image.copy(image)
	for y = 0, s - 1 do
		for x = 0, s - 1 do
			local factor = 0.9 + 0.2 * Field.at(grain, x, y)
			local offset = (y * s + x) * 4
			for channel = 0, 2 do
				local value = buffer.readu8(image.data, offset + channel) * factor
				buffer.writeu8(out.data, offset + channel, Numeric.trunc(Numeric.clamp(value, 0, 255)))
			end
		end
	end
	return out
end

local function badgeSeal(random: Generator): Image
	local s = 28
	local base = parchmentBase(random, 32)
	local sheet = Field.generate(s, s, 3, function(x: number, y: number, channel: number): number
		return Field.at(base, x, y, channel)
	end)
	local mask = Image.new(s, s, 1)
	Draw.ellipse(mask, { 0, 0, s - 1, s - 1 }, { 255 })
	local ring = Image.new(s, s, 1)
	Draw.ellipse(ring, { 1, 1, s - 2, s - 2 }, nil, { 255 }, 2)
	sheet = blend(sheet, unit(Blur.gaussian(ring, 0.5)), INK, 0.85)
	return toImage(sheet, bytes(mask))
end

local FantasyParchment = {}

FantasyParchment.name = "fantasy-parchment"
FantasyParchment.summary = "fantasy-parchment theme package art"

function FantasyParchment.generate(): { Common.Output }
	local function r(key: number): Generator
		return Raster.Random.new(SEED + key)
	end
	return {
		{ path = `{DIRECTORY}/parchment_panel.png`, image = compose(1, 144, 40, 7.0, "panel") },
		{ path = `{DIRECTORY}/parchment_button.png`, image = compose(2, 64, 16, 2.5, "button") },
		{ path = `{DIRECTORY}/parchment_field.png`, image = compose(3, 64, 16, 2.0, "field") },
		{ path = `{DIRECTORY}/parchment_slider_track.png`, image = sliderTrack(r(4)) },
		{ path = `{DIRECTORY}/parchment_slider_thumb.png`, image = sliderThumb(r(5)) },
		{ path = `{DIRECTORY}/parchment_badge.png`, image = badgeSeal(r(6)) },
	}
end

return FantasyParchment :: Common.Target
