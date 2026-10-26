--!strict

local UI = require "./ui"
local Environment = require "./environment"
local Math = require "./math"

local Compose = require "../core"
local Design = require "../design"

type Resolved = Design.Resolved
type Props = { [string]: Resolved }

return function(runtime: Compose.Runtime, environment: Environment.Environment): Design.Library
	local ui = UI.create(runtime, environment, true)
	local function apply(property: Resolved?, set: (Design.Literal?) -> ())
		if property == nil then
			return
		end
		local readable = property.readable
		if readable then
			Compose.watch(function(use: Compose.Use)
				set(use(readable))
			end)
		else
			set(property.literal)
		end
	end

	local function vector(value: Design.Literal?, fallback: UI.Vector): UI.Vector
		if type(value) == "table" then
			local x, y, z = value[1], value[2], value[3]
			if type(x) == "number" and type(y) == "number" and type(z) == "number" then
				return { X = x, Y = y, Z = z }
			end
		end
		return fallback
	end

	local function enumItem(category: string, name: Design.Literal?, fallback: string): unknown
		return ui.values.enum(category, if type(name) == "string" then name else fallback)
	end

	local placement: { [string]: Design.Field } = {
		position = { type = "vector3", group = "Transform", order = 1 },
		rotation = { type = "vector3", group = "Transform", order = 2 },
	}

	local function with(extra: { [string]: Design.Field }): { [string]: Design.Field }
		local fields = table.clone(placement)
		for key, field in extra do
			fields[key] = field
		end
		return fields
	end

	local function place(props: Props, set: ({ number }) -> ())
		local position: UI.Vector = { X = 0, Y = 0, Z = 0 }
		local rotation: UI.Vector = { X = 0, Y = 0, Z = 0 }
		local function update()
			set(
				Math.multiply(
					Math.frame(position),
					Math.rotation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
				)
			)
		end
		apply(props.position, function(value: Design.Literal?)
			position = vector(value, { X = 0, Y = 0, Z = 0 })
			update()
		end)
		apply(props.rotation, function(value: Design.Literal?)
			rotation = vector(value, { X = 0, Y = 0, Z = 0 })
			update()
		end)
		update()
	end

	local partDefaults: { [string]: Design.Literal } = {
		size = { 4, 1, 4 },
		position = { 0, 0.5, 0 },
		color = "#A3A2A5",
		material = "SmoothPlastic",
	}
	local MATERIALS = { "SmoothPlastic", "Plastic", "Neon", "Glass", "Metal", "Wood", "Concrete", "Grass" }
	local SHAPES = { "Block", "Ball", "Cylinder", "Wedge" }
	local FACES = { "Front", "Back", "Top", "Bottom", "Left", "Right" }

	local function text(value: Design.Literal?): string?
		return if type(value) == "string" then value else nil
	end

	local function number(value: Design.Literal?, fallback: number): number
		return if type(value) == "number" then value else fallback
	end

	local function tint(node: Compose.Node, property: string, value: Design.Literal?)
		if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
			ui.set(node, property, ui.hex(value))
		end
	end

	local function attach(parent: Compose.Node, children: { unknown })
		for _, child in children do
			if child ~= nil then
				ui.set(child, "Parent", parent)
			end
		end
	end

	local function light(className: string, extra: { [string]: Design.Field }): Design.Kind
		local fields: { [string]: Design.Field } = {
			color = { type = "color", group = "Light", order = 1 },
			brightness = { type = "number", group = "Light", order = 2 },
			range = { type = "number", group = "Light", order = 3 },
			shadows = { type = "boolean", group = "Light", order = 4 },
		}
		for key, field in extra do
			fields[key] = field
		end
		local defaults: { [string]: Design.Literal } = { color = "#FFE8C2", brightness = 1, range = 12 }
		return {
			fields = fields,
			defaults = defaults,
			children = "none",
			category = "Light",
			call = "Design." .. className,
			build = function(props: Props): unknown
				local node = ui.new(className)
				apply(props.color, function(value: Design.Literal?)
					tint(node, "Color", value)
				end)
				apply(props.brightness, function(value: Design.Literal?)
					ui.set(node, "Brightness", number(value, 1))
				end)
				apply(props.range, function(value: Design.Literal?)
					ui.set(node, "Range", math.clamp(number(value, 12), 0, 60))
				end)
				apply(props.shadows, function(value: Design.Literal?)
					ui.set(node, "Shadows", value == true)
				end)
				if fields.face ~= nil then
					apply(props.face, function(value: Design.Literal?)
						ui.set(node, "Face", enumItem("NormalId", value, "Front"))
					end)
				end
				if fields.angle ~= nil then
					apply(props.angle, function(value: Design.Literal?)
						ui.set(node, "Angle", math.clamp(number(value, 90), 0, 180))
					end)
				end
				return node
			end,
		}
	end

	local function surfaceImage(className: string, extra: { [string]: Design.Field }): Design.Kind
		local fields: { [string]: Design.Field } = {
			image = { type = "string", group = "Image", order = 1 },
			face = { type = "choice", options = FACES, group = "Image", order = 2 },
			color = { type = "color", group = "Image", order = 3 },
			transparency = { type = "number", group = "Image", order = 4 },
		}
		for key, field in extra do
			fields[key] = field
		end
		local defaults: { [string]: Design.Literal } = { face = "Front" }
		return {
			fields = fields,
			defaults = defaults,
			children = "none",
			category = "Surface",
			call = "Design." .. className,
			build = function(props: Props): unknown
				local node = ui.new(className)
				apply(props.image, function(value: Design.Literal?)
					ui.set(
						node,
						if className == "Texture" or className == "Decal" then "Texture" else "Image",
						text(value) or ""
					)
				end)
				apply(props.face, function(value: Design.Literal?)
					ui.set(node, "Face", enumItem("NormalId", value, "Front"))
				end)
				apply(props.color, function(value: Design.Literal?)
					tint(node, "Color3", value)
				end)
				apply(props.transparency, function(value: Design.Literal?)
					ui.set(node, "Transparency", math.clamp(number(value, 0), 0, 1))
				end)
				if fields.tileU ~= nil then
					apply(props.tileU, function(value: Design.Literal?)
						ui.set(node, "StudsPerTileU", math.max(number(value, 2), 0.01))
					end)
					apply(props.tileV, function(value: Design.Literal?)
						ui.set(node, "StudsPerTileV", math.max(number(value, 2), 0.01))
					end)
					apply(props.offsetU, function(value: Design.Literal?)
						ui.set(node, "OffsetStudsU", number(value, 0))
					end)
					apply(props.offsetV, function(value: Design.Literal?)
						ui.set(node, "OffsetStudsV", number(value, 0))
					end)
				end
				return node
			end,
		}
	end

	local library: Design.Library = {
		name = "Roblox3D",
		parameter = "Host",
		parameterType = "nil",
		prelude = {},
		returnType = "Instance",
		readable = "Compose.ReadOnlyValue",
		cell = "Compose.Cell",
		space = "3d",
		kinds = {
			Model = {
				fields = with {},
				children = "list",
				call = "Design.Model",
				build = function(props: Props, children: { unknown }): unknown
					local model = ui.new "Model"
					local primary = ui.new "Part"
					ui.set(primary, "Name", "Pivot")
					ui.set(primary, "Anchored", true)
					ui.set(primary, "Transparency", 1)
					ui.set(primary, "CanCollide", false)
					ui.set(primary, "CanQuery", false)
					ui.set(primary, "Size", ui.values.vector3(0.2, 0.2, 0.2))
					ui.set(primary, "Parent", model)
					ui.set(model, "PrimaryPart", primary)
					local offsets: { [Compose.Node]: { number } } = {}
					for _, child in children do
						if child ~= nil then
							ui.set(child, "Parent", model)
							if ui.isA(child, "BasePart") then
								offsets[child] = ui.components(ui.get(child, "CFrame"))
							end
						end
					end
					place(props, function(frame: { number })
						ui.set(primary, "CFrame", ui.values.cframe(frame))
						for part, offset in offsets do
							ui.set(part, "CFrame", ui.values.cframe(Math.multiply(frame, offset)))
						end
					end)
					return model
				end,
			},
			Part = {
				fields = with {
					shape = { type = "choice", options = SHAPES, group = "Shape", order = 1 },
					size = { type = "vector3", group = "Shape", order = 2 },
					color = { type = "color", group = "Surface", order = 1 },
					material = { type = "choice", options = MATERIALS, group = "Surface", order = 2 },
					transparency = { type = "number", group = "Surface", order = 3 },
					materialVariant = { type = "string", group = "Surface", order = 4 },
					meshId = { type = "string", group = "Mesh", order = 1 },
					textureId = { type = "string", group = "Mesh", order = 2 },
				},
				defaults = partDefaults,
				children = "list",
				call = "Design.Part",
				build = function(props: Props, children: { unknown }): unknown
					local wedge = props.shape and props.shape.literal == "Wedge"
					local part: Compose.Node = if wedge then ui.new "WedgePart" else ui.new "Part"
					ui.set(part, "Anchored", true)
					ui.set(part, "TopSurface", ui.values.enum("SurfaceType", "Smooth"))
					ui.set(part, "BottomSurface", ui.values.enum("SurfaceType", "Smooth"))
					if ui.isA(part, "Part") then
						local block = part
						apply(props.shape, function(value: Design.Literal?)
							if value ~= "Wedge" then
								ui.set(block, "Shape", enumItem("PartType", value, "Block"))
							end
						end)
					end
					apply(props.size, function(value: Design.Literal?)
						local extent = vector(value, { X = 4, Y = 1, Z = 4 })
						ui.set(part, "Size", ui.values.vector3(extent.X, extent.Y, extent.Z))
					end)
					apply(props.color, function(value: Design.Literal?)
						if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
							ui.set(part, "Color", ui.hex(value))
						end
					end)
					apply(props.material, function(value: Design.Literal?)
						ui.set(part, "Material", enumItem("Material", value, "SmoothPlastic"))
					end)
					apply(props.transparency, function(value: Design.Literal?)
						ui.set(part, "Transparency", if type(value) == "number" then math.clamp(value, 0, 1) else 0)
					end)
					apply(props.materialVariant, function(value: Design.Literal?)
						ui.set(part, "MaterialVariant", text(value) or "")
					end)
					if props.meshId ~= nil or props.textureId ~= nil then
						local mesh = ui.new "SpecialMesh"
						ui.set(mesh, "MeshType", ui.values.enum("MeshType", "FileMesh"))
						apply(props.meshId, function(value: Design.Literal?)
							ui.set(mesh, "MeshId", text(value) or "")
						end)
						apply(props.textureId, function(value: Design.Literal?)
							ui.set(mesh, "TextureId", text(value) or "")
						end)
						ui.set(mesh, "Parent", part)
					end
					attach(part, children)
					place(props, function(frame: { number })
						ui.set(part, "CFrame", ui.values.cframe(frame))
					end)
					return part
				end,
			},
			PointLight = light("PointLight", {}),
			SpotLight = light("SpotLight", {
				face = { type = "choice", options = FACES, group = "Light", order = 5 },
				angle = { type = "number", group = "Light", order = 6 },
			}),
			SurfaceLight = light("SurfaceLight", {
				face = { type = "choice", options = FACES, group = "Light", order = 5 },
				angle = { type = "number", group = "Light", order = 6 },
			}),
			Decal = surfaceImage("Decal", {}),
			Texture = surfaceImage("Texture", {
				tileU = { type = "number", group = "Image", order = 5 },
				tileV = { type = "number", group = "Image", order = 6 },
				offsetU = { type = "number", group = "Image", order = 7 },
				offsetV = { type = "number", group = "Image", order = 8 },
			}),
		},
	}

	for _, kind in library.kinds do
		local build = kind.build
		kind.build = function(props: Props, children: { unknown }, name: string): unknown
			local built = build(props, children, name)
			if built ~= nil then
				ui.set(built, "Name", name)
			end
			return built
		end
	end

	return library
end
