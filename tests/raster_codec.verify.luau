--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local expect = Verify.expect
	local fs = require("@std/fs")
	local Raster = require("../tools/facet/lib/raster")
	local vectors = require("./fixtures/raster_vectors")

	local Zlib = require("../tools/facet/lib/zlib")
	local Png = Raster.Png
	local Image = Raster.Image

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

	local function pseudoRandom(length: number, seed: number): buffer
		local out = buffer.create(length)
		local state = seed
		for index = 0, length - 1 do
			state = (state * 1103515245 + 12345) % 2147483648
			buffer.writeu8(out, index, state // 65536 % 256)
		end
		return out
	end

	local function littleEndian(value: number, width: number): string
		local out = buffer.create(width)
		for index = 0, width - 1 do
			buffer.writeu8(out, index, bit32.band(bit32.rshift(value, index * 8), 0xFF))
		end
		return buffer.tostring(out)
	end

	local function member(raw: string, plain: string, header: string?): string
		return (header or "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff")
			.. raw
			.. littleEndian(Zlib.crc32(buffer.fromstring(plain)), 4)
			.. littleEndian(#plain, 4)
	end

	local RAW_FIXED = "cb48cdc9c957c84027b900"
	local RAW_DYNAMIC = "ed8e3b16c2300c047b4eb1575b64057f121b241bf0ed213901454aaa7d3bcd8c18ab62c9cd02b62691a8a966c2"
		.. "87c70486a40337d309696b1b861e95dd14a2759f85cf9daee960511f4351d4aee8f30bee3373a3437e90f0ada0170d10"
		.. "1675bcb81e2732995fe49f7962e607"
	local GZIP_PYTHON = "1f8b08000000000002ff4b4b4c4e2d5128cf2f4a29e60200348e09810c000000"
	local FIXED_TEXT = "hello hello hello hello\n"
	local DYNAMIC_TEXT = string.rep(
		"crane fjord mocha ninja sushi adieu grey colour theatre centre favour litre cheque kerb tyre pyjamas "
			.. "crane fjord mocha ninja sushi adieu axe asked cakes walked chairs\n",
		3
	)

	local function case(suite: string, name: string, run: () -> ())
		verifyHarness:case(name, {
			id = `raster_codec::{suite}::{name}`,
			run = function()
				run()
			end,
		})
	end

	verifyHarness:suite("checksums", function()
		case("checksums", "CRC-32 and Adler-32 match the published check values", function()
			expect(Zlib.crc32(buffer.fromstring("123456789"))):toBe(0xCBF43926)
			expect(Zlib.crc32(buffer.fromstring(""))):toBe(0)
			expect(Zlib.crc32(buffer.fromstring("The quick brown fox jumps over the lazy dog"))):toBe(0x414FA339)
			expect(Zlib.adler32(buffer.fromstring("Wikipedia"))):toBe(0x11E60398)
			expect(Zlib.adler32(buffer.fromstring(""))):toBe(1)
		end)

		case("checksums", "Adler-32 stays exact across its reduction blocks", function()
			local data = buffer.create(20000)
			buffer.fill(data, 0, 0xFF)
			local a, b = 1, 0
			for _ = 1, 20000 do
				a = (a + 255) % 65521
				b = (b + a) % 65521
			end
			expect(Zlib.adler32(data)):toBe(b * 65536 + a)
		end)
	end)

	verifyHarness:suite("deflate", function()
		case("deflate", "inflates zlib streams with stored, fixed and dynamic blocks", function()
			local dynamic: { string } = {}
			for _ = 1, 3 do
				for value = 0, 255 do
					table.insert(dynamic, string.char(value))
				end
			end
			table.insert(dynamic, string.rep("facet facet facet ", 20))
			expect(buffer.tostring(Zlib.decompress(bytes(vectors.zlibEmpty)))):toBe("")
			expect(buffer.tostring(Zlib.decompress(bytes(vectors.zlibFixed)))):toBe("hello hello hello hello")
			expect(buffer.tostring(Zlib.decompress(bytes(vectors.zlibStored)))):toBe("stored block data")
			expect(buffer.tostring(Zlib.decompress(bytes(vectors.zlibDynamic)))):toBe(table.concat(dynamic))
		end)

		case("deflate", "round-trips empty, short, repetitive, structured and random data", function()
			local samples = {
				buffer.create(0),
				buffer.fromstring("a"),
				buffer.fromstring(string.rep("abcabcabd", 500)),
				buffer.fromstring(string.rep("\0", 70000)),
				pseudoRandom(5000, 7),
				pseudoRandom(150000, 11),
			}
			local structured = buffer.create(120000)
			for index = 0, 119999 do
				buffer.writeu8(structured, index, (index * 7 + index // 300) % 251)
			end
			table.insert(samples, structured)
			for _, sample in samples do
				local compressed = Zlib.compress(sample)
				expect(buffer.tostring(Zlib.decompress(compressed))):toBe(buffer.tostring(sample))
			end
		end)

		case("deflate", "compresses redundant data and stores random data", function()
			local zeros = buffer.create(70000)
			expect(buffer.len(Zlib.compress(zeros)) < 400):toBe(true)
			local noise = pseudoRandom(5000, 3)
			local compressed = Zlib.compress(noise)
			expect(buffer.len(compressed) <= 5000 + 16):toBe(true)
			expect(bit32.band(bit32.rshift(buffer.readu8(compressed, 2), 1), 3)):toBe(0)
			local text = buffer.fromstring(string.rep("the art is regenerated in memory and compared. ", 40))
			local textual = Zlib.compress(text)
			expect(bit32.band(bit32.rshift(buffer.readu8(textual, 2), 1), 3) ~= 0):toBe(true)
		end)

		case("deflate", "rejects a corrupt checksum, a bad header and a truncated stream", function()
			local good = Zlib.compress(buffer.fromstring(string.rep("verify ", 100)))
			local corrupt = buffer.create(buffer.len(good))
			buffer.copy(corrupt, 0, good)
			local last = buffer.len(corrupt) - 1
			buffer.writeu8(corrupt, last, bit32.bxor(buffer.readu8(corrupt, last), 0xFF))
			expect(function()
				Zlib.decompress(corrupt)
			end):toThrow("Adler-32")
			expect(function()
				Zlib.decompress(bytes("7800aaaaaaaa"))
			end):toThrow("header")
			local truncated = buffer.create(6)
			buffer.copy(truncated, 0, good, 0, 6)
			expect(function()
				Zlib.decompress(truncated)
			end):toThrow("ends early")
		end)

		case("deflate", "inflates raw blocks, stores past the block limit and refuses malformed blocks", function()
			local fixed = bytes(RAW_FIXED)
			local out, after = Zlib.inflate(fixed)
			expect(buffer.tostring(out)):toBe(FIXED_TEXT)
			expect(after):toBe(buffer.len(fixed))
			expect(buffer.tostring((Zlib.inflate(bytes(RAW_DYNAMIC))))):toBe(DYNAMIC_TEXT)
			local plain = buffer.fromstring(string.rep("0123456789abcdef", 9000))
			local stored = Zlib.deflate(plain, { stored = true })
			expect(buffer.len(stored)):toBe(buffer.len(plain) + 15)
			expect(buffer.tostring((Zlib.inflate(stored)))):toBe(buffer.tostring(plain))
			expect(hexOf(Zlib.compress(buffer.fromstring("stored block data"), { stored = true }))):toBe(
				vectors.zlibStored
			)
			local malformed: { { string } } = {
				{ "\x07", "invalid block type" },
				{ "\x01\x05\x00\x00\x00hello", "does not match its complement" },
				{ "\x03\x02\x00", "before the start of the output" },
				{ string.sub(buffer.tostring(bytes(RAW_DYNAMIC)), 1, 40), "ends early" },
			}
			for _, refusal in malformed do
				expect(function()
					Zlib.inflate(buffer.fromstring(refusal[1]))
				end):toThrow(refusal[2])
			end
		end)
	end)

	verifyHarness:suite("gzip", function()
		case("gzip", "reads a member written by Python and skips header fields", function()
			expect(buffer.tostring(Zlib.gunzip(bytes(GZIP_PYTHON)))):toBe("facet words\n")
			local fixed = buffer.tostring(bytes(RAW_FIXED))
			local fields = "\x1f\x8b\x08\x1d\x00\x00\x00\x00\x00\x03\x03\x00abcwords.txt\x00a comment\x00"
			expect(buffer.tostring(Zlib.gunzip(buffer.fromstring(member(fixed, FIXED_TEXT, fields))))):toBe(FIXED_TEXT)
			local checked = "\x1f\x8b\x08\x0a\x00\x00\x00\x00\x00\x03x\x00"
			local crc = bit32.band(Zlib.crc32(buffer.fromstring(checked)), 0xFFFF)
			local withCrc = member(buffer.tostring(bytes(RAW_DYNAMIC)), DYNAMIC_TEXT, checked .. littleEndian(crc, 2))
			expect(buffer.tostring(Zlib.gunzip(buffer.fromstring(withCrc)))):toBe(DYNAMIC_TEXT)
		end)

		case("gzip", "round-trips, joins members and skips zero padding", function()
			local sample = pseudoRandom(70000, 5)
			expect(buffer.tostring(Zlib.gunzip(Zlib.gzip(sample)))):toBe(buffer.tostring(sample))
			expect(buffer.tostring(Zlib.gunzip(Zlib.gzip(buffer.create(0), { stored = true })))):toBe("")
			local joined = member(buffer.tostring(bytes(RAW_FIXED)), FIXED_TEXT)
				.. buffer.tostring(Zlib.gzip(buffer.fromstring("tail\n"), { stored = true }))
				.. "\x00\x00\x00"
			expect(buffer.tostring(Zlib.gunzip(buffer.fromstring(joined)))):toBe(FIXED_TEXT .. "tail\n")
		end)

		case("gzip", "refuses a member that does not match its trailer or is not gzip", function()
			local good = member(buffer.tostring(bytes(RAW_FIXED)), FIXED_TEXT)
			local python = buffer.tostring(bytes(GZIP_PYTHON))
			local refusals: { { string } } = {
				{
					string.sub(good, 1, #good - 8) .. "\x00\x00\x00\x00" .. string.sub(good, -4),
					"CRC-32 does not match",
				},
				{ string.sub(good, 1, #good - 4) .. "\x01\x00\x00\x00", "recorded length does not match" },
				{ "PK\x03\x04 not a gzip file", "no gzip magic" },
				{ python .. "trailing", "no gzip magic" },
				{ "", "no gzip member" },
				{ string.sub(python, 1, #python - 3), "trailer ends early" },
			}
			for _, refusal in refusals do
				expect(function()
					Zlib.gunzip(buffer.fromstring(refusal[1]))
				end):toThrow(refusal[2])
			end
		end)
	end)

	verifyHarness:suite("png", function()
		case("png", "decodes PNGs that Pillow wrote for each color type and bit depth", function()
			local expected = {
				{ data = vectors.pngRgba, pixels = vectors.pngRgbaPixels, channels = 4, width = 3 },
				{ data = vectors.pngRgb, pixels = vectors.pngRgbPixels, channels = 3, width = 3 },
				{ data = vectors.pngGrey, pixels = vectors.pngGreyPixels, channels = 1, width = 4 },
				{ data = vectors.pngGreyAlpha, pixels = vectors.pngGreyAlphaPixels, channels = 2, width = 2 },
				{ data = vectors.pngPalette, pixels = vectors.pngPalettePixels, channels = 4, width = 3 },
				{ data = vectors.pngBilevel, pixels = vectors.pngBilevelPixels, channels = 1, width = 9 },
				{ data = vectors.pngDeep, pixels = "0012ff", channels = 1, width = 3 },
				{ data = vectors.pngNibble, pixels = vectors.pngNibblePixels, channels = 3, width = 5 },
			}
			for _, vector in expected do
				local image = Png.decode(bytes(vector.data))
				expect(image.width):toBe(vector.width)
				expect(image.channels):toBe(vector.channels)
				expect(hexOf(image.data)):toBe(vector.pixels)
			end
		end)

		case("png", "round-trips images with one to four channels", function()
			for channels = 1, 4 do
				local width, height = 37, 23
				local image = {
					width = width,
					height = height,
					channels = channels,
					data = pseudoRandom(width * height * channels, channels),
				}
				for y = 0, height - 1, 3 do
					buffer.fill(image.data, y * width * channels, y % 256, width * channels)
				end
				local decoded = Png.decode(Png.encode(image))
				expect(Image.equal(decoded, image)):toBe(true)
			end
		end)

		case("png", "rejects a bad signature and a chunk CRC mismatch", function()
			local encoded = Png.encode(Image.new(4, 4, 4, { 1, 2, 3, 4 }))
			local broken = buffer.create(buffer.len(encoded))
			buffer.copy(broken, 0, encoded)
			buffer.writeu8(broken, 20, bit32.bxor(buffer.readu8(broken, 20), 1))
			expect(function()
				Png.decode(broken)
			end):toThrow("CRC")
			expect(function()
				Png.decode(buffer.fromstring("not a png at all"))
			end):toThrow("signature")
		end)

		case("png", "decodes every PNG in the repository with all five row filters", function()
			local files: { string } = {}
			local function walk(directory: string)
				for _, entry in fs.listDirectory(directory) do
					local path = directory .. "/" .. entry.name
					if entry.type == "dir" then
						walk(path)
					elseif string.lower(string.sub(entry.name, -4)) == ".png" then
						table.insert(files, path)
					end
				end
			end
			walk("assets")
			table.sort(files)
			expect(#files >= 140):toBe(true)
			local filters: { [number]: boolean } = {}
			for _, path in files do
				local data = buffer.fromstring(fs.readFileToString(path))
				local width = buffer.readu8(data, 16) * 16777216
					+ buffer.readu8(data, 17) * 65536
					+ buffer.readu8(data, 18) * 256
					+ buffer.readu8(data, 19)
				local height = buffer.readu8(data, 20) * 16777216
					+ buffer.readu8(data, 21) * 65536
					+ buffer.readu8(data, 22) * 256
					+ buffer.readu8(data, 23)
				local image = Png.decode(data)
				expect(image.width):toBe(width)
				expect(image.height):toBe(height)
				local parts: { string } = {}
				for _, chunk in Png.chunks(data) do
					if chunk.kind == "IDAT" then
						table.insert(parts, buffer.tostring(chunk.data))
					end
				end
				local raw = Zlib.decompress(buffer.fromstring(table.concat(parts)))
				local stride = width * image.channels + 1
				for row = 0, height - 1 do
					filters[buffer.readu8(raw, row * stride)] = true
				end
				if width * height <= 262144 then
					expect(Image.equal(Png.decode(Png.encode(image)), image)):toBe(true)
				end
			end
			for filter = 0, 4 do
				expect(filters[filter]):toBe(true)
			end
		end)
	end)
end
