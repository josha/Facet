--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local expect = Verify.expect
	local Raster = require("../tools/facet/lib/raster")
	local vectors = require("./fixtures/raster_vectors")

	local Blur = Raster.Blur
	local Canvas = Raster.Canvas
	local Draw = Raster.Draw
	local Field = Raster.Field
	local Image = Raster.Image
	local Numeric = Raster.Numeric
	local Resample = Raster.Resample

	type Image = Raster.Image

	local function bytes(hex: string): buffer
		local out = buffer.create(#hex // 2)
		for index = 0, #hex // 2 - 1 do
			buffer.writeu8(out, index, tonumber(string.sub(hex, index * 2 + 1, index * 2 + 2), 16) :: number)
		end
		return out
	end

	local function hexOf(data: buffer): string
		local parts = table.create(buffer.len(data), "")
		for index = 0, buffer.len(data) - 1 do
			parts[index + 1] = string.format("%02x", buffer.readu8(data, index))
		end
		return table.concat(parts)
	end

	local function image(width: number, height: number, channels: number, hex: string): Image
		return { width = width, height = height, channels = channels, data = bytes(hex) }
	end

	local function case(suite: string, name: string, run: () -> ())
		verifyHarness:case(name, {
			id = `raster_primitives::{suite}::{name}`,
			run = function()
				run()
			end,
		})
	end

	verifyHarness:suite("numeric", function()
		case("numeric", "rounding follows Python, C and float32 rules", function()
			expect(Numeric.roundHalfEven(0.5)):toBe(0)
			expect(Numeric.roundHalfEven(1.5)):toBe(2)
			expect(Numeric.roundHalfEven(2.5)):toBe(2)
			expect(Numeric.roundHalfEven(-2.5)):toBe(-2)
			expect(Numeric.roundHalfAway(2.5)):toBe(3)
			expect(Numeric.roundHalfAway(-2.5)):toBe(-3)
			expect(Numeric.trunc(-2.7)):toBe(-2)
			expect(Numeric.f32(0.1)):toBe(0.10000000149011612)
			expect(Numeric.roundUpF32(Numeric.f32(0.49999997))):toBe(1)
			expect(Numeric.roundUp(0.49999997)):toBe(0)
			expect(Numeric.floorMod(-30, 360)):toBe(330)
			expect(Numeric.floorMod(-720, 360)):toBe(0)
		end)

		case("numeric", "linspace and pairwise sums match numpy", function()
			expect(Numeric.linspace(0.0, 1.0, 7)[3]):toBe(vectors.linspaceThird)
			expect(Numeric.linspace(0.0, 1.0, 7)[7]):toBe(1.0)
			local values = buffer.create(18 * 8)
			for index = 0, 17 do
				buffer.writef64(values, index * 8, 0.1 * index + 1e-3 * index * index)
			end
			expect(Numeric.pairwiseSum(values, 0, 18, 1)):toBe(vectors.pairwiseSum)
		end)
	end)

	verifyHarness:suite("random", function()
		case("random", "PCG64 seeded through SeedSequence matches numpy default_rng", function()
			local generator = Raster.Random.new(0x60D1 + 70)
			for _, value in vectors.randomFirst do
				expect(generator:random()):toBe(value)
			end
			local integers = generator:integers(0, 144, 5)
			for index, value in vectors.randomIntegers do
				expect(integers[index]):toBe(value)
			end
			expect(generator:random()):toBe(vectors.randomAfter)
		end)
	end)

	verifyHarness:suite("draw", function()
		local function canvas(): Image
			return Image.new(14, 11, 1)
		end

		case("draw", "filled and outlined shapes match Pillow ImageDraw", function()
			local shapes: { { name: string, draw: (Image) -> (), expected: string } } = {
				{
					name = "ellipse",
					draw = function(target: Image)
						Draw.ellipse(target, { 1.5, 1.2, 12.7, 9.9 }, { 255 })
					end,
					expected = vectors.drawEllipse,
				},
				{
					name = "ellipse outline",
					draw = function(target: Image)
						Draw.ellipse(target, { 0, 0, 13, 10 }, nil, { 200 }, 2)
					end,
					expected = vectors.drawEllipseOutline,
				},
				{
					name = "rounded rectangle",
					draw = function(target: Image)
						Draw.roundedRectangle(target, { 1, 1, 12.4, 9.6 }, 3.3, { 255 })
					end,
					expected = vectors.drawRoundedRectangle,
				},
				{
					name = "rounded ring",
					draw = function(target: Image)
						Draw.roundedRectangle(target, { 0.6, 1, 13, 10 }, 4, nil, { 255 }, 2)
					end,
					expected = vectors.drawRoundedRing,
				},
				{
					name = "polygon",
					draw = function(target: Image)
						Draw.polygon(target, { 1.2, 0.5, 12.9, 3.3, 7.5, 10.4, 2.2, 7.7 }, { 255 })
					end,
					expected = vectors.drawPolygon,
				},
				{
					name = "curve-jointed line",
					draw = function(target: Image)
						Draw.line(target, { 1, 9, 6.5, 2.2, 12.8, 8.1 }, { 255 }, 3, "curve")
					end,
					expected = vectors.drawLine,
				},
				{
					name = "pieslice",
					draw = function(target: Image)
						Draw.pieslice(target, { 0, 0, 13, 10 }, 200.5, 330.25, { 255 })
					end,
					expected = vectors.drawPieslice,
				},
				{
					name = "arc",
					draw = function(target: Image)
						Draw.arc(target, { 1, 0, 12, 10 }, 10, 250, { 255 }, 2)
					end,
					expected = vectors.drawArc,
				},
				{
					name = "rectangle outline",
					draw = function(target: Image)
						Draw.rectangle(target, { 2.7, 1.2, 11, 9 }, nil, { 255 }, 2)
					end,
					expected = vectors.drawRectangleOutline,
				},
			}
			for _, shape in shapes do
				local target = canvas()
				shape.draw(target)
				expect(`{shape.name}: {hexOf(target.data)}`):toBe(`{shape.name}: {shape.expected}`)
			end
		end)

		case("draw", "wide curve-jointed lines, pieslices and rings compose like Pillow", function()
			local target = Image.new(96, 64, 1)
			Draw.line(target, { 5.5, 60.2, 30.1, 4.9, 55.7, 50.3, 90.2, 8.8 }, { 255 }, 13, "curve")
			Draw.pieslice(target, { 10, 10, 80, 60 }, -30, 120.5, { 128 })
			Draw.roundedRectangle(target, { 40.2, 2.8, 93.3, 30.6 }, 9.6, nil, { 77 }, 5)
			expect(string.format("%08x", Raster.Checksum.crc32(target.data))):toBe(vectors.drawCompositeDigest)
		end)
	end)

	verifyHarness:suite("resample", function()
		case("resample", "each filter matches Pillow Image.resize", function()
			local source = image(6, 5, 1, vectors.resampleSource)
			local cases: { { filter: Raster.Filter, width: number, height: number, expected: string } } = {
				{ filter = "lanczos", width = 3, height = 2, expected = vectors.resampleLanczos },
				{ filter = "bicubic", width = 9, height = 7, expected = vectors.resampleBicubic },
				{ filter = "bilinear", width = 4, height = 8, expected = vectors.resampleBilinear },
				{ filter = "nearest", width = 11, height = 3, expected = vectors.resampleNearest },
				{ filter = "box", width = 2, height = 2, expected = vectors.resampleBox },
			}
			for _, entry in cases do
				local resized = Resample.resize(source, entry.width, entry.height, entry.filter)
				expect(`{entry.filter}: {hexOf(resized.data)}`):toBe(`{entry.filter}: {entry.expected}`)
			end
		end)

		case("resample", "RGBA resizes premultiply alpha like Pillow", function()
			local source = image(4, 3, 4, vectors.resampleRgbaSource)
			expect(hexOf(Resample.resize(source, 2, 5, "lanczos").data)):toBe(vectors.resampleRgbaLanczos)
		end)
	end)

	verifyHarness:suite("filters", function()
		case("filters", "Gaussian blur matches Pillow's extended box blur", function()
			local source = image(7, 6, 1, vectors.blurSource)
			expect(hexOf(Blur.gaussian(source, 0.9).data)):toBe(vectors.blur09)
			expect(hexOf(Blur.gaussian(source, 2.2).data)):toBe(vectors.blur22)
		end)

		case("filters", "alpha compositing matches Pillow alpha_composite", function()
			local base = image(3, 1, 4, vectors.compositeBase)
			Image.alphaComposite(base, image(3, 1, 4, vectors.compositeOver), 0, 0)
			expect(hexOf(base.data)):toBe(vectors.compositeResult)
		end)

		case("filters", "the float canvas paints source-over and quantizes like numpy", function()
			local target = Canvas.new(2, 1)
			Canvas.paint(target, { 1, 0, 0 }, Field.new(2, 1, 1, 1.0))
			local half = Field.new(2, 1, 1, 0.5)
			Field.set(half, 1, 0, 0.0)
			Canvas.paint(target, { 0, 0, 1 }, half)
			local result = Canvas.image(target)
			expect(hexOf(result.data)):toBe("800080ffff0000ff")
		end)
	end)
end
