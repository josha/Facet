--!strict

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local Cli = require("../lib/cli")
local OrderedJson = require("../lib/ordered-json")
local Raster = require("../lib/raster")

type Value = OrderedJson.Value

local OUT = "assets/themes/plate-samples.json"
local NOTE = "Alpha-weighted mean of each asset's nine-slice CENTRE rect \u{2014} the pixels a lifted label is read against. "
	.. "Regenerate with `lute run tools/facet art sample` whenever the art is re-cut; "
	.. "`lute run tools/facet art sample --check` re-hashes every file and fails if a sample is stale."

type Target = { package: string, module: string, folder: string, slots: { { string } } }

local TARGETS: { Target } = {
	{
		package = "fantasy-ornate",
		module = "fantasy_ornate",
		folder = "fantasy-ornate",
		slots = {
			{ "selected", "ornate_selection_selected" },
			{ "control", "ornate_button_default" },
			{ "field", "ornate_field" },
		},
	},
	{
		package = "glossy-touch",
		module = "glossy_touch",
		folder = "glossy-touch",
		slots = {
			{ "selected", "glossy_selection_selected" },
			{ "control", "glossy_button_default" },
			{ "field", "glossy_field" },
		},
	},
	{
		package = "pixel-quest",
		module = "pixel_quest",
		folder = "pixel-quest",
		slots = {
			{ "selected", "pixel_plate_default" },
			{ "control", "pixel_plate_default" },
			{ "field", "pixel_field" },
		},
	},
	{
		package = "compact-pointer",
		module = "compact_pointer",
		folder = "compact-pointer",
		slots = {
			{ "selected", "compact_button_pressed" },
			{ "control", "compact_button_default" },
			{ "field", "compact_field" },
		},
	},
	{
		package = "fantasy-parchment",
		module = "fantasy_parchment",
		folder = "fantasy-parchment",
		slots = {
			{ "selected", "parchment_button" },
			{ "control", "parchment_button" },
			{ "field", "parchment_field" },
		},
	},
}

local Sample = {}

local function sliceCenter(module: string, asset: string): { number }?
	local path = ("examples/themes/%s.luau"):format(module)
	local source = string.gsub(fs.readFileToString(path), "\r\n", "\n")
	local at = string.find(source, "\t" .. asset .. " = {", 1, true)
	if at == nil then
		error(("%s.luau declares no art entry '%s'"):format(module, asset), 0)
	end
	local block = string.sub(source, at, at + 599)
	local x0, y0, x1, y1 = string.match(block, "sliceCenter = { x0 = (%d+), y0 = (%d+), x1 = (%d+), y1 = (%d+) }")
	if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
		return nil
	end
	return { tonumber(x0) :: number, tonumber(y0) :: number, tonumber(x1) :: number, tonumber(y1) :: number }
end

function Sample.measure(image: Raster.Image, rect: { number }?): (number, number, number, number)
	local rgba = if image.channels == 4 then image else Raster.Image.convert(image, 4)
	local x0, y0, x1, y1 = 0, 0, rgba.width, rgba.height
	if rect ~= nil then
		x0, y0, x1, y1 = rect[1], rect[2], rect[3], rect[4]
	end
	x1 = math.min(x1, rgba.width)
	y1 = math.min(y1, rgba.height)
	local width, height = x1 - x0, y1 - y0
	if width <= 0 or height <= 0 then
		error("empty sample rect", 0)
	end
	local count = width * height
	local alphas = buffer.create(count * 8)
	local sums = { 0.0, 0.0, 0.0 }
	local index = 0
	for y = y0, y1 - 1 do
		for x = x0, x1 - 1 do
			local offset = (y * rgba.width + x) * 4
			local alpha = buffer.readu8(rgba.data, offset + 3) / 255.0
			buffer.writef64(alphas, index * 8, alpha)
			for channel = 1, 3 do
				sums[channel] += buffer.readu8(rgba.data, offset + channel - 1) * alpha
			end
			index += 1
		end
	end
	local total = Raster.Numeric.pairwiseSum(alphas, 0, count, 1)
	if total <= 0 then
		error("fully transparent sample rect", 0)
	end
	return sums[1] / total, sums[2] / total, sums[3] / total, total / count
end

local function roundTo4(value: number): Value
	return OrderedJson.float(tonumber(string.format("%.4f", value)) :: number)
end

function Sample.build(): (string, { string })
	local samples = OrderedJson.object()
	local lines: { string } = {}
	for _, target in TARGETS do
		local bySlot = OrderedJson.object()
		for _, slot in target.slots do
			local name, asset = slot[1], slot[2]
			local relative = ("assets/themes/%s/%s.png"):format(target.folder, asset)
			if not fs.exists(relative) then
				error(("missing %s"):format(relative), 0)
			end
			local bytes = fs.readFileToString(relative)
			local rect = sliceCenter(target.module, asset)
			local image = Raster.Png.decode(buffer.fromstring(bytes))
			local r, g, b, alpha = Sample.measure(image, rect)
			local entry = OrderedJson.object()
			OrderedJson.set(entry, "r", OrderedJson.int(Raster.Numeric.roundHalfEven(r)))
			OrderedJson.set(entry, "g", OrderedJson.int(Raster.Numeric.roundHalfEven(g)))
			OrderedJson.set(entry, "b", OrderedJson.int(Raster.Numeric.roundHalfEven(b)))
			OrderedJson.set(entry, "alpha", roundTo4(alpha))
			OrderedJson.set(entry, "size", OrderedJson.string(("%dx%d"):format(image.width, image.height)))
			OrderedJson.set(entry, "asset", OrderedJson.string(asset))
			OrderedJson.set(entry, "file", OrderedJson.string(relative))
			OrderedJson.set(
				entry,
				"sha256",
				OrderedJson.string(Raster.Checksum.hex(crypto.digest(crypto.hash.sha256, bytes)))
			)
			if rect == nil then
				OrderedJson.set(entry, "sliceCenter", OrderedJson.null)
			else
				local center = OrderedJson.object()
				OrderedJson.set(center, "x0", OrderedJson.int(rect[1]))
				OrderedJson.set(center, "y0", OrderedJson.int(rect[2]))
				OrderedJson.set(center, "x1", OrderedJson.int(rect[3]))
				OrderedJson.set(center, "y1", OrderedJson.int(rect[4]))
				OrderedJson.set(entry, "sliceCenter", center)
			end
			OrderedJson.set(bySlot, name, entry)
			table.insert(
				lines,
				("%-16s %-9s %-28s rgb(%d, %d, %d)  alpha=%s"):format(
					target.package,
					name,
					asset,
					Raster.Numeric.roundHalfEven(r),
					Raster.Numeric.roundHalfEven(g),
					Raster.Numeric.roundHalfEven(b),
					OrderedJson.compact(roundTo4(alpha))
				)
			)
		end
		OrderedJson.set(samples, target.package, bySlot)
	end
	table.sort(lines)
	local root = OrderedJson.object()
	OrderedJson.set(root, "schema", OrderedJson.string("facet-art-plate-samples/1"))
	OrderedJson.set(root, "note", OrderedJson.string(NOTE))
	OrderedJson.set(root, "samples", samples)
	return OrderedJson.dumps(root, true) .. "\n", lines
end

function Sample.run(invocation: Cli.Invocation): number
	local ok, built, summary = pcall(Sample.build)
	if not ok then
		print(("facet art sample: %s"):format(tostring(built)))
		return 1
	end
	local text = built :: string
	if Cli.switch(invocation, "check") then
		if not fs.exists(OUT) then
			print("facet art sample: plate-samples.json is missing")
			return 1
		end
		if string.gsub(fs.readFileToString(OUT), "\r\n", "\n") ~= text then
			print("facet art sample: plate-samples.json is stale")
			return 1
		end
		print("facet art sample: up to date")
		return 0
	end
	fs.writeStringToFile(OUT, text)
	for _, line in summary :: { string } do
		print(line)
	end
	print(("facet art sample: wrote %s"):format(OUT))
	return 0
end

return table.freeze(Sample)
