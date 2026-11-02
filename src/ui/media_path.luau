--!strict
local Types = require("./types")
local Engine = require("./engine_types")
local Media = require("./media_types")
local ComposeTypes = require("../vendor/compose/core")
local pathShapes = require("./nav_path_shapes")
local ControlTypes = require("./control_types")
local MediaProps = require("./media_props")

return function(ctx: Types.Context, UI: ControlTypes.Controls)
	local Host, Compose = ctx.Host, ctx.Compose
	local types, read = ctx.types, ctx.read
	local D2 = types.UDim2
	local metric = ctx.metric
	UI.Path = ctx.construct("Path", function(spec: MediaProps.PathProps): Frame
		assert(spec.points ~= nil, "Facet Path requires points")
		local width, height = spec.width, spec.height
		assert(width == nil or (type(width) == "number" and width > 0), "Facet Path width must be a positive number")
		assert(
			height == nil or (type(height) == "number" and height > 0),
			"Facet Path height must be a positive number"
		)
		local stroke: Engine.Path2DProps = {
			Name = "Stroke",
			Closed = function(use: ComposeTypes.Use): boolean
				return read(spec.closed, use) == true
			end,
		}
		if spec.thickness ~= nil then
			stroke.Thickness = function(use: ComposeTypes.Use): number
				local value = read(spec.thickness, use)
				if type(value) == "string" then
					return metric(value, use)
				end
				assert(
					type(value) == "number" and value > 0,
					"Facet Path thickness must be a positive number or a theme metric name"
				)
				return value
			end
		end
		if spec.tint ~= nil then
			stroke.Color3 = function(use: ComposeTypes.Use): Color3
				return assert(read<<Color3?>>(spec.tint, use))
			end
		end
		local path = ctx.styled(Host.Path2D(stroke), "path")
		local previousRole: string?
		Compose.watch(function(use: ComposeTypes.Use)
			local role = read(spec.role, use) or "content"
			assert(
				role == "content" or role == "secondary" or role == "accent",
				"Facet Path role must be content, secondary or accent"
			)
			if previousRole then
				path:RemoveTag(previousRole)
			end
			local tag = "facet-path-" .. role
			previousRole = tag
			path:AddTag(tag)
		end)
		Compose.watch(function(use: ComposeTypes.Use)
			local points = read<<{ Media.PathPoint }>>(spec.points, use)
			assert(type(points) == "table", "Facet Path points must be a list of pathShapes points")
			assert(#points <= pathShapes.MAX_CONTROL_POINTS, "Facet Path takes at most 100 control points")
			local native: { Path2DControlPoint } = {}
			for _, point in points do
				table.insert(
					native,
					types.Path2DControlPoint.new(
						D2.fromScale(point.x, point.y),
						D2.fromScale(point.inX, point.inY),
						D2.fromScale(point.outX, point.outY)
					)
				)
			end
			path:SetControlPoints(native)
		end)
		local props = ctx.props(spec, { "points", "thickness", "closed", "role", "tint", "width", "height" }, {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = if width or height then D2.fromOffset(width or height or 0, height or width or 0) else nil,
		})
		props[#props + 1] = path
		return Host.Frame(props)
	end)
end
