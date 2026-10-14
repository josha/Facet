--!strict

local Raster = require("../lib/raster")

local Draw = Raster.Draw
local Field = Raster.Field
local Image = Raster.Image
local Numeric = Raster.Numeric
local Resample = Raster.Resample

export type Image = Raster.Image
export type Field = Raster.Field
export type Color = Raster.Color
export type Generator = Raster.Generator

export type Output = { path: string, image: Image }

export type Target = {
	name: string,
	summary: string,
	generate: () -> { Output },
}

export type Mask = {
	width: number,
	height: number,
	scale: number,
	image: Image,
	rect: (self: Mask, box: { number }, fill: number?) -> (),
	rrect: (self: Mask, box: { number }, radius: number, fill: number?) -> (),
	rring: (self: Mask, box: { number }, radius: number, width: number, fill: number?) -> (),
	ellipse: (self: Mask, box: { number }, fill: number?) -> (),
	ering: (self: Mask, box: { number }, width: number, fill: number?) -> (),
	poly: (self: Mask, points: { number }, fill: number?) -> (),
	stroke: (self: Mask, points: { number }, width: number, caps: boolean?, fill: number?) -> (),
	arr: (self: Mask) -> Field,
}

local Common = {}

function Common.rgb(r: number, g: number, b: number): Color
	return { r / 255.0, g / 255.0, b / 255.0 }
end

function Common.times(color: Color, factor: number): Color
	return { color[1] * factor, color[2] * factor, color[3] * factor }
end

function Common.strokeWidth(width: number, scale: number): number
	return math.max(1, Numeric.roundHalfEven(width * scale))
end

local function scaled(values: { number }, scale: number): { number }
	local out = table.create(#values, 0)
	for index, value in values do
		out[index] = value * scale
	end
	return out
end

function Common.mask(width: number, height: number, scale: number?): Mask
	local factor = scale or 4
	local mask = {
		width = width,
		height = height,
		scale = factor,
		image = Image.new(width * factor, height * factor, 1),
	}

	function mask.rect(self: Mask, box: { number }, fill: number?)
		Draw.rectangle(self.image, scaled(box, self.scale), { fill or 255 })
	end

	function mask.rrect(self: Mask, box: { number }, radius: number, fill: number?)
		Draw.roundedRectangle(self.image, scaled(box, self.scale), radius * self.scale, { fill or 255 })
	end

	function mask.rring(self: Mask, box: { number }, radius: number, width: number, fill: number?)
		Draw.roundedRectangle(
			self.image,
			scaled(box, self.scale),
			radius * self.scale,
			nil,
			{ fill or 255 },
			Common.strokeWidth(width, self.scale)
		)
	end

	function mask.ellipse(self: Mask, box: { number }, fill: number?)
		Draw.ellipse(self.image, scaled(box, self.scale), { fill or 255 })
	end

	function mask.ering(self: Mask, box: { number }, width: number, fill: number?)
		Draw.ellipse(self.image, scaled(box, self.scale), nil, { fill or 255 }, Common.strokeWidth(width, self.scale))
	end

	function mask.poly(self: Mask, points: { number }, fill: number?)
		Draw.polygon(self.image, scaled(points, self.scale), { fill or 255 })
	end

	function mask.stroke(self: Mask, points: { number }, width: number, caps: boolean?, fill: number?)
		local ink = { fill or 255 }
		local sp = scaled(points, self.scale)
		local w = Common.strokeWidth(width, self.scale)
		if #sp > 2 then
			Draw.line(self.image, sp, ink, w, "curve")
		end
		if caps ~= false then
			local r = w / 2.0
			local last = #sp - 1
			for _, index in { 1, last } do
				local x, y = sp[index], sp[index + 1]
				Draw.ellipse(self.image, { x - r, y - r, x + r, y + r }, ink)
			end
		end
	end

	function mask.arr(self: Mask): Field
		return Field.fromImage(Resample.resize(self.image, self.width, self.height, "lanczos"))
	end

	return mask :: Mask
end

function Common.rrectMask(width: number, height: number, box: { number }, radius: number): Field
	local mask = Common.mask(width, height)
	mask:rrect(box, radius)
	return mask:arr()
end

function Common.hairline(width: number, height: number, box: { number }, radius: number, inset: number?): Field
	local amount = inset or 1.0
	local outer = Common.rrectMask(width, height, box, radius)
	local inner = Common.rrectMask(
		width,
		height,
		{ box[1] + amount, box[2] + amount, box[3] - amount, box[4] - amount },
		math.max(0.0, radius - amount)
	)
	return Field.difference(outer, inner)
end

function Common.stops(entries: { { number | Color } }): { Raster.Stop }
	local out: { Raster.Stop } = {}
	for _, entry in entries do
		table.insert(out, { at = entry[1] :: number, color = entry[2] :: Color })
	end
	return out
end

function Common.inset(mask: Field, distance: number): Field
	return Field.difference(mask, Field.shift(mask, 0, distance))
end

function Common.fbm(
	random: Generator,
	width: number,
	height: number,
	octaves: number,
	base: number,
	floor: number
): Field
	local accumulator = Field.new(width, height, 1)
	local amplitude, total = 1.0, 0.0
	for octave = 0, octaves - 1 do
		local cells = math.max(floor, base * 2 ^ octave)
		local values = random:randomArray(cells * cells)
		local grid = Image.new(cells, cells, 1)
		for index, value in values do
			buffer.writeu8(grid.data, index - 1, Numeric.trunc(value * 255))
		end
		local upsampled = Resample.resize(grid, width, height, "bicubic")
		local weight = amplitude
		for index = 0, width * height - 1 do
			local sample = buffer.readu8(upsampled.data, index) / 255.0
			buffer.writef64(accumulator.data, index * 8, buffer.readf64(accumulator.data, index * 8) + weight * sample)
		end
		total += amplitude
		amplitude *= 0.55
	end
	return Field.map(accumulator, function(value: number): number
		return value / total
	end)
end

function Common.edgeDistance(width: number, height: number): (x: number, y: number) -> number
	return function(x: number, y: number): number
		return math.min(math.min(x, width - 1 - x), math.min(y, height - 1 - y))
	end
end

function Common.nineSlice(image: Image, border: number, width: number, height: number, filter: Raster.Filter?): Image
	local resample: Raster.Filter = filter or "bilinear"
	local sw, sh = image.width, image.height
	local b = border
	local out = Image.new(width, height, 4)
	local cw, ch = width - 2 * b, height - 2 * b
	local parts = {
		{ 0, 0, b, b, 0, 0, b, b },
		{ sw - b, 0, sw, b, width - b, 0, b, b },
		{ 0, sh - b, b, sh, 0, height - b, b, b },
		{ sw - b, sh - b, sw, sh, width - b, height - b, b, b },
		{ b, 0, sw - b, b, b, 0, cw, b },
		{ b, sh - b, sw - b, sh, b, height - b, cw, b },
		{ 0, b, b, sh - b, 0, b, b, ch },
		{ sw - b, b, sw, sh - b, width - b, b, b, ch },
		{ b, b, sw - b, sh - b, b, b, cw, ch },
	}
	for _, part in parts do
		if part[7] > 0 and part[8] > 0 then
			local piece = Image.crop(image, part[1], part[2], part[3], part[4])
			Image.alphaComposite(out, Resample.resize(piece, part[7], part[8], resample), part[5], part[6])
		end
	end
	return out
end

function Common.checker(width: number, height: number, size: number?, a: { number }?, b: { number }?): Image
	local cell = size or 8
	local image = Image.new(width, height, 3, a or { 56, 56, 62 })
	local other = b or { 42, 42, 48 }
	for y = 0, height - 1, cell do
		for x = 0, width - 1, cell do
			if ((x // cell) + (y // cell)) % 2 == 1 then
				Draw.rectangle(image, { x, y, x + cell - 1, y + cell - 1 }, other)
			end
		end
	end
	return image
end

export type Item = { name: string, image: Image, border: number?, previews: { { number } }? }

function Common.outputs(directory: string, items: { Item }): ({ Output }, { [string]: Item })
	local outputs: { Output } = {}
	local index: { [string]: Item } = {}
	for _, item in items do
		table.insert(outputs, { path = `{directory}/{item.name}`, image = item.image })
		index[item.name] = item
	end
	return outputs, index
end

function Common.stretch(
	index: { [string]: Item },
	names: { string },
	sizes: { { number } }?,
	filter: Raster.Filter?
): { Image }
	local images: { Image } = {}
	for _, name in names do
		local item = index[name]
		local use: { { number } }? = if sizes ~= nil then sizes else item.previews
		local border = item.border
		if border ~= nil and border ~= 0 and use ~= nil then
			for _, size in use do
				table.insert(images, Common.nineSlice(item.image, border, size[1], size[2], filter))
			end
		else
			table.insert(images, item.image)
		end
	end
	return images
end

function Common.clipped(image: Image, width: number, height: number): Image
	return Image.crop(image, 0, 0, width, height)
end

export type Row = { label: string, images: { Image }, backdrop: { number }? }

export type Sheet = {
	title: string,
	width: number,
	rows: { Row },
	add: (self: Sheet, label: string, images: { Image }, backdrop: { number }?) -> (),
	render: (self: Sheet) -> Image,
}

function Common.sheet(title: string, width: number?): Sheet
	local sheet = { title = title, width = width or 1500, rows = {} :: { Row } }

	function sheet.add(self: Sheet, label: string, images: { Image }, backdrop: { number }?)
		table.insert(self.rows, { label = label, images = images, backdrop = backdrop })
	end

	function sheet.render(self: Sheet): Image
		local pad, gap, labelHeight = 16, 18, 20
		local total = 52 + pad
		for _, row in self.rows do
			local tallest = 0
			for _, image in row.images do
				tallest = math.max(tallest, image.height)
			end
			total += labelHeight + tallest + gap
		end
		local out = Image.new(self.width, total, 3, { 26, 26, 30 })
		Raster.Font.draw(out, pad, 18, self.title, { 236, 226, 200 }, 2)
		local y = 52
		for _, row in self.rows do
			Raster.Font.draw(out, pad, y + 4, row.label, { 168, 172, 182 })
			y += labelHeight
			local x = pad
			local tallest = 0
			for _, image in row.images do
				tallest = math.max(tallest, image.height)
			end
			for _, image in row.images do
				local backdrop = if row.backdrop == nil
					then Common.checker(image.width, image.height)
					else Image.new(image.width, image.height, 3, row.backdrop)
				local composed = Image.convert(backdrop, 4)
				Image.alphaComposite(composed, image, 0, 0)
				Image.paste(out, Image.convert(composed, 3), x, y)
				Draw.rectangle(out, { x, y, x + image.width - 1, y + image.height - 1 }, nil, { 90, 90, 98 })
				x += image.width + 12
			end
			y += tallest + gap
		end
		return out
	end

	return sheet :: Sheet
end

return table.freeze(Common)
