--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Capture = require("../../tools/play/host/capture")
local QA = require("../../tools/play/host/qa")
local Devices = require("../../tools/play/host/devices")
local Png = require("../../tools/facet/lib/raster/png")
local Files = require("../../tools/facet/lib/files")

local function raster(width: number, height: number, pixel: (number, number) -> number): Capture.Raster
	local data = buffer.create(width * height * 3)
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local value = pixel(x, y)
			local offset = (y * width + x) * 3
			for channel = 0, 2 do
				buffer.writeu8(data, offset + channel, value)
			end
		end
	end
	return { width = width, height = height, channels = 3, data = data }
end

local function sparse(x: number, y: number): number
	return if x >= 16 and x < 24 and y >= 16 and y < 24 then 220 else 20
end

return function(harness: Verify.Harness)
	harness:case("capture triage separates uniform, tiny, low contrast and sparse images", function(t)
		for _, fixture in
			{
				{
					image = raster(128, 128, function()
						return 20
					end),
					classification = "unusable",
					blank = true,
				},
				{ image = raster(32, 32, sparse), classification = "unusable", blank = false },
				{
					image = raster(128, 128, function(x)
						return 120 + x % 3
					end),
					classification = "needs-review",
					blank = false,
				},
				{ image = raster(128, 128, sparse), classification = "needs-review", blank = false },
			}
		do
			local inspection = Capture.inspect(fixture.image)
			t:expect(inspection.classification):toBe(fixture.classification)
			t:expect(inspection.blank):toBe(fixture.blank)
		end
	end)
	harness:case("capture triage does not call an unsampled pixel uniform", function(t)
		local image = raster(128, 128, function(x, y)
			return if x == 1 and y == 1 then 220 else 20
		end)
		local inspection = Capture.inspect(image)
		t:expect(inspection.dominant):toBe(1)
		t:expect(inspection.blank):toBe(false)
		t:expect(inspection.classification):toBe("needs-review")
	end)
	harness:case("capture triage preserves alpha variation for review", function(t)
		local data = buffer.create(128 * 128 * 4)
		for pixel = 0, 128 * 128 - 1 do
			buffer.writeu32(data, pixel * 4, 0x141414 + bit32.lshift(pixel % 256, 24))
		end
		local encoded = Png.encode({ width = 128, height = 128, channels = 4, data = data }, true)
		local decoded = assert(Capture.decode(buffer.tostring(encoded)))
		local inspection = Capture.inspect(decoded)
		t:expect(decoded.channels):toBe(4)
		t:expect(inspection.blank):toBe(false)
		t:expect(inspection.classification):toBe("needs-review")
	end)
	harness:case("noise and a world-only horizon remain unreviewed rather than approved UI", function(t)
		for _, image in
			{
				raster(128, 128, function(x, y)
					return (x * 37 + y * 71) % 256
				end),
				raster(128, 128, function(_x, y)
					return if y < 64 then 180 else 40
				end),
			}
		do
			local inspection = Capture.inspect(image)
			t:expect(inspection.classification):toBe("unreviewed")
			t:expect(inspection.blank):toBe(false)
		end
	end)
	harness:case("conversion retains decodable rejected and sparse images without changing pixels", function(t)
		local directory = Files.temporaryDirectory("capture-conversion-")
		t:defer(function()
			Files.remove(directory)
		end)
		for _, image in
			{ raster(128, 128, function()
				return 20
			end), raster(128, 128, sparse) }
		do
			local source, target = directory .. "/source.png", directory .. "/normalized.png"
			Files.write(source, buffer.tostring(Png.encode(image, true)))
			local inspection, problem = Capture.convert(source, target)
			t:expect(problem):toBe(nil)
			t:expect(inspection ~= nil):toBe(true)
			local decoded = assert(Capture.decode(Files.read(target)))
			t:expect(buffer.tostring(decoded.data)):toBe(buffer.tostring(image.data))
		end
		Files.write(directory .. "/broken.png", "not an image")
		local inspection = Capture.convert(directory .. "/broken.png", directory .. "/broken-output.png")
		t:expect(inspection):toBe(nil)
		t:expect(Files.isFile(directory .. "/broken-output.png")):toBe(false)
	end)
	harness:case("QA retains sparse captures for review without adding them to judge inputs or retrying", function(t)
		local directory = Files.temporaryDirectory("capture-qa-")
		t:defer(function()
			Files.remove(directory)
		end)
		local source = directory .. "/source.png"
		Files.write(source, buffer.tostring(Png.encode(raster(128, 128, sparse), true)))
		local calls = 0
		local stems: { string } = {}
		local shots: { QA.Shot } = {}
		local context = (
			{
				session = {
					capture = function(options: { stem: string })
						calls += 1
						table.insert(stems, options.stem)
						return { ok = true, artifact = { reference = source } }
					end,
				},
				probe = "probe",
				outputs = directory .. "/outputs",
				captures = directory .. "/captures",
				scratch = directory .. "/scratch",
				shots = shots,
				log = function(_line: string) end,
			} :: unknown
		) :: QA.Context
		local qa = QA.create(context, Devices.get("desktop"))
		Files.write(context.captures .. "/desktop/sparse.png", "stale capture")
		qa:capture("sparse")
		t:expect(calls):toBe(1)
		t:expect(#shots):toBe(1)
		t:expect(shots[1].classification):toBe("needs-review")
		t:expect(shots[1].blank):toBe(false)
		t:expect(shots[1].path):toBe(nil)
		t:expect(Files.isFile(assert(shots[1].reviewPath))):toBe(true)
		t:expect(Files.isFile(context.captures .. "/desktop/sparse.png")):toBe(false)
		local firstPath = assert(shots[1].reviewPath)
		local firstBytes = Files.read(firstPath)
		Files.write(
			source,
			buffer.tostring(Png.encode(
				raster(128, 128, function(_x, y)
					return if y < 64 then 180 else 40
				end),
				true
			))
		)
		qa:capture("sparse")
		t:expect(calls):toBe(2)
		t:expect(stems[1] ~= stems[2]):toBe(true)
		t:expect(shots[2].classification):toBe("unreviewed")
		t:expect(shots[2].reviewPath ~= firstPath):toBe(true)
		t:expect(Files.read(firstPath)):toBe(firstBytes)
		t:expect(Files.isFile(assert(shots[2].path))):toBe(true)
	end)
end
