--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local ComposeTypes = require("../vendor/compose/core")
local prepareMedia = require("./media_readiness")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")
local MediaShared = require("./media_shared")

type Extent = "fill" | number

return function(ctx: Types.Context, UI: ControlTypes.Controls, shared: MediaShared.Shared)
	local Host, Compose = ctx.Host, ctx.Compose
	local types, read = ctx.types, ctx.read
	local readString = read<<string?>>
	local bindString = shared.bind<<string>>
	local readExtent = read<<Extent?>>
	local E, D2 = types.Enum, types.UDim2
	local controlSize = ctx.controlSize
	UI.Image = ctx.construct("Image", function(spec: MediaProps.ImageProps): ImageLabel
		local keys = {
			"image",
			"tint",
			"scaleMode",
			"tileSize",
			"sliceCenter",
			"sliceScale",
			"paintRect",
			"resample",
			"shape",
			"width",
			"height",
			"aspectRatio",
		}
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
		local paint = spec.paintRect
		if paint ~= nil then
			assert(
				type(paint) == "table"
					and type(paint.x0) == "number"
					and type(paint.y0) == "number"
					and type(paint.x1) == "number"
					and type(paint.y1) == "number"
					and type(paint.width) == "number"
					and type(paint.height) == "number"
					and paint.x0 >= 0
					and paint.y0 >= 0
					and paint.x1 > paint.x0
					and paint.y1 > paint.y0
					and paint.x1 <= paint.width
					and paint.y1 <= paint.height,
				"Facet UI.Image: paintRect = { x0, y0, x1, y1, width, height } is the rectangle of the paint, "
					.. "inside an image of width by height source pixels"
			)
			assert(
				not Compose.isValue(spec.image) and type(spec.image) ~= "function",
				"Facet UI.Image: paintRect belongs to one image; author image as a static string with it"
			)
		end
		assert(
			spec.shape == nil or spec.shape == "rect" or spec.shape == "circle",
			"Facet UI.Image: shape must be rect or circle"
		)
		assert(
			spec.shape ~= "circle" or declared ~= "slice",
			"Facet UI.Image: a circle cannot slice; use fit, fill, crop, stretch or tile"
		)
		local ratio = spec.aspectRatio
		assert(
			ratio == nil or (type(ratio) == "number" and ratio > 0 and ratio < math.huge),
			"Facet UI.Image: aspectRatio must be a number above zero"
		)
		assert(ratio == nil or spec.shape ~= "circle", "Facet UI.Image: a circle has its own aspect ratio")
		local function span(value: Extent?, rest: number): (number, number)
			if value == nil then
				return 0, rest
			end
			if value == "fill" then
				return 1, 0
			end
			assert(
				type(value) == "number" and value == value and value >= 0,
				"Facet UI.Image: width and height must be fill or a number of pixels, 0 or more"
			)
			return 0, value
		end
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
				local width, height = readExtent(spec.width, use), readExtent(spec.height, use)
				if ratio ~= nil then
					if width == nil and height == nil then
						width, height = side * ratio, side
					elseif height == nil then
						height = if type(width) == "number" then width / ratio else "fill"
					elseif width == nil then
						width = if type(height) == "number" then height * ratio else "fill"
					end
				end
				local wide, across = span(width, side)
				local tall, down = span(height, side)
				return D2.new(wide, across, tall, down)
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
		if ratio ~= nil then
			defaults[#defaults + 1] = Host.UIAspectRatioConstraint {
				AspectRatio = ratio,
				DominantAxis = if spec.width ~= nil or spec.height == nil
					then E.DominantAxis.Width
					else E.DominantAxis.Height,
				AspectType = function(use: ComposeTypes.Use): Enum.AspectType
					local width, height = readExtent(spec.width, use), readExtent(spec.height, use)
					local led = (width == "fill" and height == nil) or (height == "fill" and width == nil)
					return if led then E.AspectType.ScaleWithParentSize else E.AspectType.FitWithinMaxSize
				end,
			}
		end
		local image = Host.ImageLabel(ctx.props(spec, keys, defaults))
		if paint ~= nil then
			image:SetAttribute("FacetPaintRect", types.Rect.new(paint.x0, paint.y0, paint.x1, paint.y1))
			image:SetAttribute("FacetSourceSize", types.Vector2.new(paint.width, paint.height))
		end
		prepareMedia(ctx, image, spec.ImageTransparency)
		return image
	end)
end
