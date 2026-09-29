--!strict

local Children = require "../runtime/children"
local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Support = require "./support"
local Types = require "../reactive/types"
local keyed = require "./keyed"

export type Viewport = { x: number, y: number, width: number, height: number }
export type Size = { width: number, height: number }
export type Placement = { column: number, row: number, x: number, y: number, width: number, height: number }
export type Options<V> = {
	viewport: Types.Source<Viewport>,
	tileSize: Size,
	overscan: number?,
	read: (use: Types.Use, column: number, row: number) -> V?,
	render: (value: Types.Readable<V>, placement: Placement) -> Host.Node,
}

local KNOWN_FIELDS: { [string]: true } =
	{ viewport = true, tileSize = true, overscan = true, read = true, render = true }

local function finite(value: number): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function tileCollection<V>(options: Options<V>): Children.Directive
	local settings =
		Support.optionsOf(options, "TileCollection", "viewport = ..., tileSize = ..., read = ..., render = ...")
	Support.noUnknownFields(settings, "TileCollection", KNOWN_FIELDS)
	local viewport = Support.sourceOf(settings.viewport, "TileCollection", "viewport") :: Types.Body<Viewport>
	local read = Support.builderOf(settings.read, "TileCollection", "read") :: (Types.Use, number, number) -> V?
	local render =
		Support.builderOf(settings.render, "TileCollection", "render") :: (Types.Readable<V>, Placement) -> Host.Node
	local size = settings.tileSize
	if
		type(size) ~= "table"
		or not finite(size.width)
		or not finite(size.height)
		or size.width <= 0
		or size.height <= 0
	then
		Diagnostics.raise("tile-collection/invalid-size", "TileCollection needs positive finite tile dimensions", {})
	end
	Support.noUnknownFields(size, "TileCollection.tileSize", { width = true, height = true })
	local width, height = size.width, size.height
	local overscan = settings.overscan or 0
	if not finite(overscan) or overscan < 0 or overscan % 1 ~= 0 then
		Diagnostics.raise(
			"tile-collection/invalid-overscan",
			"TileCollection overscan must be a non-negative integer",
			{}
		)
	end

	return function(mountPoint: Children.MountPoint)
		local owner = Support.ownerFor "TileCollection"
		Support.mountPointOf(mountPoint, "TileCollection")
		local keys: { string } = {}
		local placements: { [string]: Placement } = {}
		owner.own(function()
			table.clear(keys)
			table.clear(placements)
		end)

		local function select(use: Types.Use): { V }
			local view = viewport(use)
			if
				not finite(view.x)
				or not finite(view.y)
				or not finite(view.width)
				or not finite(view.height)
				or view.width < 0
				or view.height < 0
			then
				Diagnostics.raise(
					"tile-collection/invalid-viewport",
					"TileCollection needs a finite viewport with non-negative dimensions",
					{}
				)
			end
			local values: { V } = {}
			local nextKeys: { string } = {}
			local nextPlacements: { [string]: Placement } = {}
			if view.width > 0 and view.height > 0 then
				local firstColumn = math.floor(view.x / width) - overscan
				local lastColumn = math.ceil((view.x + view.width) / width) - 1 + overscan
				local firstRow = math.floor(view.y / height) - overscan
				local lastRow = math.ceil((view.y + view.height) / height) - 1 + overscan
				for _, coordinate in { firstColumn, lastColumn, firstRow, lastRow } do
					if not finite(coordinate) or math.abs(coordinate) > 9007199254740990 then
						Diagnostics.raise(
							"tile-collection/invalid-viewport",
							"TileCollection coordinates must be safely representable integers",
							{}
						)
					end
				end
				for row = firstRow, lastRow do
					for column = firstColumn, lastColumn do
						local value = read(use, column, row)
						if value ~= nil then
							local key = string.format("%.0f:%.0f", column + 0, row + 0)
							local placement: Placement? = placements[key]
							if placement == nil then
								local fresh: Placement = {
									column = column,
									row = row,
									x = column * width,
									y = row * height,
									width = width,
									height = height,
								}
								table.freeze(fresh :: {})
								placement = fresh
							end
							values[#values + 1] = value
							nextKeys[#values] = key
							nextPlacements[key] = placement :: Placement
						end
					end
				end
			end
			keys = nextKeys
			placements = nextPlacements
			return values
		end

		keyed {
			from = select,
			key = function(_value: V, index: number): string
				return keys[index]
			end,
			render = function(value: Types.Readable<V>, _index: Types.Readable<number>, key: string): Host.Node
				return render(value, placements[key])
			end,
		}(mountPoint)
	end
end

return tileCollection
