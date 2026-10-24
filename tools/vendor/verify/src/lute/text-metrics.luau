--!strict

local fs = require "@std/fs"
local Path = require "@std/path"
local Metrics = require "../roblox/text-metrics"
local Datatypes = require "../roblox/datatypes"
local json = require "@std/json"
local Values = require "../roblox/ui-values"

local function numbers(value: json.Value): { number }
	local result: { number } = {}
	for _, entry in assert(json.asArray(value)) do
		table.insert(result, Values.number(entry))
	end
	return result
end

local function decode(source: string): (Metrics.Face, string)
	local root = assert(json.asObject(json.deserialize(source)))
	local tokens: { string } = {}
	for _, entry in assert(json.asArray(root.tokens)) do
		table.insert(tokens, Values.string(entry))
	end
	local pairs: { { number } } = {}
	for _, entry in assert(json.asArray(root.pairs)) do
		local pair = numbers(entry)
		assert(#pair == 2)
		for _, index in pair do
			assert(index % 1 == 0 and index >= 1 and index <= #tokens)
		end
		table.insert(pairs, pair)
	end
	local sizes: { Metrics.Row } = {}
	for _, entry in assert(json.asArray(root.sizes)) do
		local row = assert(json.asObject(entry))
		local advances, adjustments = numbers(row.advances), numbers(row.adjustments)
		local starts = if row.starts == nil then nil else numbers(row.starts)
		local ends = if row.ends == nil then nil else numbers(row.ends)
		assert(#advances == #tokens and #adjustments == #pairs)
		assert(starts == nil or #starts == #tokens)
		assert(ends == nil or #ends == #tokens)
		table.insert(sizes, {
			advances = advances,
			adjustments = adjustments,
			starts = starts,
			ends = ends,
			height = if row.height == nil then nil else Values.number(row.height),
		})
	end
	assert(#sizes == 100)
	local key = Values.string(root.family) .. "/" .. Values.string(root.weight) .. "/" .. Values.string(root.style)
	return { tokens = tokens, pairs = pairs, sizes = sizes }, key
end

local DIRECTORY = Path.format(Path.join(Path.dirname(Path.resolve(debug.info(1, "s"))), "fixtures/text"))
local models: { [string]: Metrics.Model }? = nil

local function load(): { [string]: Metrics.Model }
	if models then
		return models
	end
	local loaded: { [string]: Metrics.Model } = {}
	for _, entry in fs.listDirectory(DIRECTORY) do
		if entry.type ~= "file" or not entry.name:match "%.json$" then
			continue
		end
		local face, key = decode(fs.readFileToString(DIRECTORY .. "/" .. entry.name))
		loaded[key] = Metrics.create(face)
	end
	models = loaded
	return loaded
end

local function create(): (Values.TextParameters) -> unknown
	local catalog = load()
	return function(parameters: Values.TextParameters): unknown
		if parameters.RichText then
			error("unsupported_text_metrics: RichText", 0)
		end
		local font = parameters.Font
		local key = font.Family
			.. "/"
			.. Values.enumName(font.Weight, "FontWeight")
			.. "/"
			.. Values.enumName(font.Style, "FontStyle")
		local model = catalog[key]
		if model == nil then
			error("unsupported_text_metrics: font " .. key, 0)
		end
		local size = math.clamp(math.floor(parameters.Size), 1, 100)
		local width, lines = model.wrap(parameters.Text, size, parameters.Width)
		return Datatypes.Vector2.new(width, lines * model.height(size))
	end
end

return { create = create }
