--!strict

local fs = require "@std/fs"
local Path = require "@std/path"
local Metrics = require "../roblox/text-metrics"
local Datatypes = require "../roblox/datatypes"
local Wire = require "./wire"

type Font = { Family: string, Weight: unknown, Style: unknown }
type Parameters = { Text: string, Size: number, Font: Font, Width: number, RichText: boolean? }
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
		local face = Wire.parse(fs.readFileToString(DIRECTORY .. "/" .. entry.name)) :: Metrics.Face & {
			family: string,
			weight: string,
			style: string,
		}
		loaded[face.family .. "/" .. face.weight .. "/" .. face.style] = Metrics.create(face)
	end
	models = loaded
	return loaded
end

local function create(): (unknown) -> unknown
	local catalog = load()
	return function(value: unknown): unknown
		local parameters = value :: Parameters
		if parameters.RichText then
			error("unsupported_text_metrics: RichText", 0)
		end
		local font = parameters.Font
		local key = font.Family
			.. "/"
			.. (tostring(font.Weight):match "([^%.]+)$" or "")
			.. "/"
			.. (tostring(font.Style):match "([^%.]+)$" or "")
		local model = catalog[key]
		if model == nil then
			error("unsupported_text_metrics: font " .. key, 0)
		end
		local size = math.clamp(math.floor(parameters.Size), 1, 100)
		local width, lines = model.wrap(parameters.Text, size, parameters.Width)
		return Datatypes.Vector2.new(width, lines * size)
	end
end

return { create = create }
