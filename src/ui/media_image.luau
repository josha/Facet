--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local ComposeTypes = require("../vendor/compose/core")
local prepareMedia = require("./media_readiness")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, Compose = ctx.Host, ctx.Compose
	local types, read = ctx.types, ctx.read
	local readString = read<<string?>>
	local bindString = shared.bind<<string>>
	local E, D2 = types.Enum, types.UDim2
	local controlSize = ctx.controlSize
	UI.Image = ctx.construct("Image", function(spec: MediaProps.ImageProps): ImageLabel
		local keys = { "image", "tint", "scaleMode", "tileSize", "sliceCenter", "sliceScale", "resample", "shape" }
		local declared = readString(spec.scaleMode)
		local live = Compose.isValue(spec.scaleMode) or type(spec.scaleMode) == "function"
		assert(
			not live or (spec.tileSize == nil and spec.sliceCenter == nil),
			"Facet UI.Image: tile and slice are static; author scaleMode as a word with its geometry"
		)
		if declared == "tile" then
			local tile = spec.tileSize
			assert(
				type(tile) == "table"
					and type(tile.width) == "number"
					and type(tile.height) == "number"
					and tile.width > 0
					and tile.height > 0
					and tile.width % 1 == 0
					and tile.height % 1 == 0,
				"Facet UI.Image: scaleMode tile requires tileSize = { width, height } in whole pixels above zero"
			)
		else
			assert(spec.tileSize == nil, "Facet UI.Image: tileSize requires scaleMode tile")
		end
		if declared == "slice" then
			local rect = spec.sliceCenter
			assert(
				type(rect) == "table"
					and type(rect.x0) == "number"
					and type(rect.y0) == "number"
					and type(rect.x1) == "number"
					and type(rect.y1) == "number"
					and rect.x1 > rect.x0
					and rect.y1 > rect.y0,
				"Facet UI.Image: scaleMode slice requires sliceCenter = { x0, y0, x1, y1 } in source pixels"
			)
			assert(
				spec.sliceScale == nil or (type(spec.sliceScale) == "number" and spec.sliceScale > 0),
				"Facet UI.Image: sliceScale must be above zero"
			)
		else
			assert(spec.sliceCenter == nil, "Facet UI.Image: sliceCenter requires scaleMode slice")
			assert(spec.sliceScale == nil, "Facet UI.Image: sliceScale requires scaleMode slice")
		end
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet UI.Image: shape must be rect or circle"
		)
		assert(
			spec.shape ~= "circle" or declared ~= "slice",
			"Facet UI.Image: a circle cannot slice; use fit, fill, crop, stretch or tile"
		)
		local modes: { [string]: Enum.ScaleType } = {
			fit = E.ScaleType.Fit,
			fill = E.ScaleType.Crop,
			crop = E.ScaleType.Crop,
			stretch = E.ScaleType.Stretch,
			tile = E.ScaleType.Tile,
			slice = E.ScaleType.Slice,
		}
		local defaults: Engine.ImageLabelProps = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = bindString(spec.image, ""),
			Size = function(use: ComposeTypes.Use): UDim2
				local side = controlSize(nil, "height", use)
				return D2.fromOffset(side, side)
			end,
		}
		if spec.tint ~= nil then
			defaults.ImageColor3 = spec.tint
		end
		if spec.scaleMode ~= nil then
			defaults.ScaleType = function(use: ComposeTypes.Use): Enum.ScaleType
				local mode = readString(spec.scaleMode, use)
				assert(
					not live or (mode ~= "tile" and mode ~= "slice"),
					"Facet UI.Image: a bound scaleMode cannot be tile or slice, which need static geometry"
				)
				return (
					assert(
						modes[mode or "stretch"],
						"Facet UI.Image: scaleMode must be fit, fill, crop, stretch, tile or slice"
					)
				)
			end
		end
		if spec.tileSize ~= nil then
			defaults.TileSize = D2.fromOffset(spec.tileSize.width, spec.tileSize.height)
		end
		if spec.sliceCenter ~= nil then
			local rect = spec.sliceCenter
			defaults.SliceCenter = types.Rect.new(rect.x0, rect.y0, rect.x1, rect.y1)
			defaults.SliceScale = spec.sliceScale or 1
		end
		if spec.resample ~= nil then
			defaults.ResampleMode = function(use: ComposeTypes.Use): Enum.ResamplerMode
				local mode = readString(spec.resample, use) or "default"
				assert(
					mode == "default" or mode == "pixelated",
					"Facet UI.Image: resample must be default or pixelated"
				)
				return if mode == "pixelated" then E.ResamplerMode.Pixelated else E.ResamplerMode.Default
			end
		end
		if spec.shape == "circle" then
			defaults[#defaults + 1] = Host.UICorner { CornerRadius = ctx.round }
			defaults[#defaults + 1] = Host.UIAspectRatioConstraint { AspectRatio = 1 }
		end
		local image = Host.ImageLabel(ctx.props(spec, keys, defaults))
		prepareMedia(ctx, image, spec.ImageTransparency)
		return image
	end)
end
