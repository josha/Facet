--!strict

local UI = require "./ui"
local Environment = require "./environment"
local Math = require "./math"

local Compose = require "../core"
local Design = require "../design"
local Patterns = require "../design/patterns"

type Resolved = Design.Resolved
type Props = { [string]: Resolved }
type Convert =
	"number"
	| "boolean"
	| "string"
	| "color"
	| "vector2"
	| "vector3"
	| "range"
	| "numberSequence"
	| "colorSequence"
	| "unit"
	| "nonNegative"
	| "tile"
	| "reach"
	| "angle"
type Binding = { property: string, convert: Convert, enum: string? }
type Bindings = { [string]: Binding }
type Build = (props: Props, children: { unknown }, name: string) -> unknown
export type Sequences = {
	numberSequence: ({ { number } }) -> unknown,
	colorSequence: ({ { number } }) -> unknown,
	numberRange: (low: number, high: number) -> unknown,
}

local MATERIALS = {
	"SmoothPlastic",
	"Plastic",
	"Neon",
	"Glass",
	"Metal",
	"CorrodedMetal",
	"Wood",
	"WoodPlanks",
	"Concrete",
	"Cobblestone",
	"Rock",
	"Slate",
	"Basalt",
	"Limestone",
	"Grass",
	"Ground",
	"Mud",
	"Fabric",
	"ForceField",
}
local SHAPES = { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge" }
local FACES = { "Front", "Back", "Top", "Bottom", "Left", "Right" }
local STREAMING = { "Default", "Atomic", "Persistent", "PersistentPerPlayer" }
local FIDELITY = { "Default", "Box", "Hull", "PreciseConvexDecomposition" }
local RENDER_FIDELITY = { "Automatic", "Precise", "Performance" }
local EMITTER_SHAPES = { "Box", "Sphere", "Cylinder", "Disc" }
local EMITTER_STYLES = { "Volume", "Surface" }
local EMITTER_ORIENTATIONS = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" }

local placement: { [string]: Design.Field } = {
	position = { type = "vector3", group = "Transform", order = 1 },
	rotation = { type = "vector3", group = "Transform", order = 2 },
	transform = { type = "value", group = "Transform", order = 3, advanced = true },
}

local function with(base: { [string]: Design.Field }, extra: { [string]: Design.Field }): { [string]: Design.Field }
	local fields = table.clone(base)
	for key, field in extra do
		fields[key] = field
	end
	return fields
end

local function field(kind: Design.FieldType, group: string, order: number, options: { string }?): Design.Field
	return { type = kind, group = group, order = order, options = options }
end

local physics: { [string]: Design.Field } = {
	canCollide = { type = "boolean", group = "Physics", order = 1, default = true },
	canQuery = { type = "boolean", group = "Physics", order = 2, default = true },
	canTouch = { type = "boolean", group = "Physics", order = 3, default = true },
	castShadow = { type = "boolean", group = "Physics", order = 4, default = true },
}

local attributes: { [string]: Design.Field } = {
	attributes = { type = "value", group = "Attributes", order = 1, advanced = true },
}

local physicsBindings: Bindings = {
	canCollide = { property = "CanCollide", convert = "boolean" },
	canQuery = { property = "CanQuery", convert = "boolean" },
	canTouch = { property = "CanTouch", convert = "boolean" },
	castShadow = { property = "CastShadow", convert = "boolean" },
}

local surface: { [string]: Design.Field } = {
	color = field("color", "Surface", 1),
	material = field("choice", "Surface", 2, MATERIALS),
	transparency = field("number", "Surface", 3),
	materialVariant = field("string", "Surface", 4),
	topSurface = {
		type = "choice",
		group = "Surface",
		order = 5,
		options = {
			"Smooth",
			"Glue",
			"Weld",
			"Studs",
			"Inlet",
			"Universal",
			"Hinge",
			"Motor",
			"SteppingMotor",
			"SmoothNoOutlines",
		},
		advanced = true,
	},
	bottomSurface = {
		type = "choice",
		group = "Surface",
		order = 6,
		options = {
			"Smooth",
			"Glue",
			"Weld",
			"Studs",
			"Inlet",
			"Universal",
			"Hinge",
			"Motor",
			"SteppingMotor",
			"SmoothNoOutlines",
		},
		advanced = true,
	},
}

local function light(extra: { [string]: Design.Field }): Design.Kind
	local fields = with({
		color = field("color", "Light", 1),
		brightness = field("number", "Light", 2),
		range = field("number", "Light", 3),
		shadows = field("boolean", "Light", 4),
		enabled = { type = "boolean", group = "Light", order = 7, default = true },
	}, extra)
	local defaults: { [string]: Design.Literal } = { color = "#FFE8C2", brightness = 1, range = 12 }
	return {
		fields = fields,
		defaults = defaults,
		children = "none",
		category = "Light",
		call = "",
		build = function(): unknown
			error "schema only"
		end,
	}
end

local function surfaceImage(extra: { [string]: Design.Field }): Design.Kind
	local fields = with({
		image = field("string", "Image", 1),
		face = field("choice", "Image", 2, FACES),
		color = field("color", "Image", 3),
		transparency = field("number", "Image", 4),
	}, extra)
	local defaults: { [string]: Design.Literal } = { face = "Front" }
	return {
		fields = fields,
		defaults = defaults,
		children = "none",
		category = "Surface",
		call = "",
		build = function(): unknown
			error "schema only"
		end,
	}
end

local function scalar(
	category: string,
	fields: { [string]: Design.Field },
	children: index<Design.Kind, "children">?
): Design.Kind
	return {
		fields = fields,
		children = children or "none",
		category = category,
		call = "",
		build = function(): unknown
			error "schema only"
		end,
	}
end

local partDefaults: { [string]: Design.Literal } = {
	size = { 4, 1, 4 },
	position = { 0, 0.5, 0 },
	color = "#A3A2A5",
	material = "SmoothPlastic",
}

local function kinds(): { [string]: Design.Kind }
	return {
		Pattern = {
			fields = {
				mode = field("choice", "Pattern", 1, { "linear", "grid", "radial" }),
				count = field("number", "Pattern", 2),
				columns = field("number", "Pattern", 3),
				rows = field("number", "Pattern", 4),
				radius = field("number", "Pattern", 5),
				phase = { type = "number", group = "Pattern", order = 15, advanced = true },
				extent = field("vector3", "Pattern", 6),
				spacing = field("vector3", "Pattern", 7),
				position = field("vector3", "Transform", 1),
				rotation = field("vector3", "Transform", 2),
				size = field("vector3", "Geometry", 1),
				color = field("color", "Surface", 1),
				namePattern = field("string", "Pattern", 8),
				indexOrigin = field("number", "Pattern", 9),
				variantBy = field("choice", "Pattern", 10, { "index", "sum" }),
				variants = { type = "value", group = "Pattern", order = 11, advanced = true },
				order = field("choice", "Pattern", 12, { "row", "column" }),
				fit = field("boolean", "Pattern", 13),
				gap = field("vector3", "Pattern", 14),
			},
			children = "template",
			template = "render",
			iteration = { fields = Patterns.fields },
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		Array = {
			fields = {},
			children = "template",
			template = "render",
			source = "from",
			key = "key",
			staticRows = true,
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		Model = {
			fields = with(
				placement,
				with(attributes, {
					streamingMode = field("choice", "Model", 1, STREAMING),
				})
			),
			children = "list",
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		Fragment = scalar("Structure", placement, "list"),
		Folder = scalar("Structure", {}, "list"),
		SpecialMesh = scalar("Mesh", {
			meshId = field("string", "Mesh", 1),
			textureId = field("string", "Mesh", 2),
			scale = field("vector3", "Mesh", 3),
			offset = field("vector3", "Mesh", 4),
			vertexColor = field("vector3", "Mesh", 6),
			meshType = field(
				"choice",
				"Mesh",
				5,
				{ "FileMesh", "Brick", "Sphere", "Cylinder", "Head", "Wedge", "Torso" }
			),
		}, "none"),
		Part = {
			fields = with(
				with(placement, with(physics, attributes)),
				with(surface, {
					shape = field("choice", "Shape", 1, SHAPES),
					partClass = {
						type = "choice",
						group = "Shape",
						order = 3,
						options = { "Auto", "Part", "WedgePart", "CornerWedgePart" },
						advanced = true,
					},
					size = field("vector3", "Shape", 2),
					meshId = field("string", "Mesh", 1),
					textureId = field("string", "Mesh", 2),
				})
			),
			defaults = partDefaults,
			children = "list",
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		MeshPart = {
			fields = with(
				with(placement, with(physics, attributes)),
				with(surface, {
					size = field("vector3", "Shape", 2),
					meshId = field("string", "Mesh", 1),
					textureId = field("string", "Mesh", 2),
					collisionFidelity = field("choice", "Mesh", 3, FIDELITY),
					renderFidelity = field("choice", "Mesh", 4, RENDER_FIDELITY),
				})
			),
			defaults = partDefaults,
			children = "list",
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		Attachment = {
			fields = with(placement, {}),
			children = "list",
			category = "Structure",
			call = "",
			build = function(): unknown
				error "schema only"
			end,
		},
		PointLight = light {},
		SpotLight = light {
			face = field("choice", "Light", 5, FACES),
			angle = field("number", "Light", 6),
		},
		SurfaceLight = light {
			face = field("choice", "Light", 5, FACES),
			angle = field("number", "Light", 6),
		},
		Decal = surfaceImage {},
		Texture = surfaceImage {
			tileU = field("number", "Image", 5),
			tileV = field("number", "Image", 6),
			offsetU = field("number", "Image", 7),
			offsetV = field("number", "Image", 8),
		},
		ParticleEmitter = scalar("Effect", {
			texture = field("string", "Appearance", 1),
			color = field("value", "Appearance", 2),
			size = field("value", "Appearance", 3),
			transparency = field("value", "Appearance", 4),
			lightEmission = field("number", "Appearance", 5),
			lightInfluence = field("number", "Appearance", 6),
			rotation = field("value", "Appearance", 7),
			rotSpeed = field("value", "Appearance", 8),
			orientation = field("choice", "Appearance", 9, EMITTER_ORIENTATIONS),
			rate = field("number", "Emission", 1),
			lifetime = field("value", "Emission", 2),
			speed = field("value", "Emission", 3),
			spreadAngle = field("value", "Emission", 4),
			acceleration = field("vector3", "Emission", 5),
			drag = field("number", "Emission", 6),
			windAffectsDrag = field("boolean", "Emission", 7),
			shape = field("choice", "Emission", 8, EMITTER_SHAPES),
			shapeStyle = field("choice", "Emission", 9, EMITTER_STYLES),
			emissionDirection = field("choice", "Emission", 10, FACES),
			enabled = { type = "boolean", group = "Emission", order = 11, default = true },
		}),
		Fire = scalar("Effect", {
			color = field("color", "Fire", 1),
			secondaryColor = field("color", "Fire", 2),
			heat = field("number", "Fire", 3),
			size = field("number", "Fire", 4),
			enabled = { type = "boolean", group = "Fire", order = 5, default = true },
		}),
		Smoke = scalar("Effect", {
			color = field("color", "Smoke", 1),
			opacity = field("number", "Smoke", 2),
			riseVelocity = field("number", "Smoke", 3),
			size = field("number", "Smoke", 4),
			enabled = { type = "boolean", group = "Smoke", order = 5, default = true },
		}),
		Sparkles = scalar("Effect", {
			color = field("color", "Sparkles", 1),
			enabled = { type = "boolean", group = "Sparkles", order = 2, default = true },
		}),
		Sound = scalar("Audio", {
			soundId = field("string", "Sound", 1),
			volume = field("number", "Sound", 2),
			playbackSpeed = field("number", "Sound", 3),
			looped = field("boolean", "Sound", 4),
			playing = field("boolean", "Sound", 5),
			rollOffMinDistance = field("number", "Sound", 6),
			rollOffMaxDistance = field("number", "Sound", 7),
		}),
	}
end

local function categories(): { string }
	return { "Structure", "Light", "Surface", "Effect", "Audio" }
end

local calls: { [string]: string } = {}
for name in kinds() do
	calls[name] = "Design." .. name
end

local function named(source: { [string]: Design.Kind }): { [string]: Design.Kind }
	for name, kind in source do
		kind.call = calls[name]
	end
	return source
end

local lightBindings: Bindings = {
	color = { property = "Color", convert = "color" },
	brightness = { property = "Brightness", convert = "number" },
	range = { property = "Range", convert = "reach" },
	shadows = { property = "Shadows", convert = "boolean" },
	enabled = { property = "Enabled", convert = "boolean" },
	face = { property = "Face", convert = "string", enum = "NormalId" },
	angle = { property = "Angle", convert = "angle" },
}

local imageBindings: Bindings = {
	transparency = { property = "Transparency", convert = "unit" },
	face = { property = "Face", convert = "string", enum = "NormalId" },
	tileU = { property = "StudsPerTileU", convert = "tile" },
	tileV = { property = "StudsPerTileV", convert = "tile" },
	offsetU = { property = "OffsetStudsU", convert = "number" },
	offsetV = { property = "OffsetStudsV", convert = "number" },
}

local emitterBindings: Bindings = {
	texture = { property = "Texture", convert = "string" },
	color = { property = "Color", convert = "colorSequence" },
	size = { property = "Size", convert = "numberSequence" },
	transparency = { property = "Transparency", convert = "numberSequence" },
	lightEmission = { property = "LightEmission", convert = "unit" },
	lightInfluence = { property = "LightInfluence", convert = "unit" },
	rotation = { property = "Rotation", convert = "range" },
	rotSpeed = { property = "RotSpeed", convert = "range" },
	orientation = { property = "Orientation", convert = "string", enum = "ParticleOrientation" },
	rate = { property = "Rate", convert = "nonNegative" },
	lifetime = { property = "Lifetime", convert = "range" },
	speed = { property = "Speed", convert = "range" },
	spreadAngle = { property = "SpreadAngle", convert = "vector2" },
	acceleration = { property = "Acceleration", convert = "vector3" },
	drag = { property = "Drag", convert = "nonNegative" },
	windAffectsDrag = { property = "WindAffectsDrag", convert = "boolean" },
	shape = { property = "Shape", convert = "string", enum = "ParticleEmitterShape" },
	shapeStyle = { property = "ShapeStyle", convert = "string", enum = "ParticleEmitterShapeStyle" },
	emissionDirection = { property = "EmissionDirection", convert = "string", enum = "NormalId" },
	enabled = { property = "Enabled", convert = "boolean" },
}

local fireBindings: Bindings = {
	color = { property = "Color", convert = "color" },
	secondaryColor = { property = "SecondaryColor", convert = "color" },
	heat = { property = "Heat", convert = "number" },
	size = { property = "Size", convert = "nonNegative" },
	enabled = { property = "Enabled", convert = "boolean" },
}

local smokeBindings: Bindings = {
	color = { property = "Color", convert = "color" },
	opacity = { property = "Opacity", convert = "unit" },
	riseVelocity = { property = "RiseVelocity", convert = "number" },
	size = { property = "Size", convert = "nonNegative" },
	enabled = { property = "Enabled", convert = "boolean" },
}

local sparklesBindings: Bindings = {
	color = { property = "SparkleColor", convert = "color" },
	enabled = { property = "Enabled", convert = "boolean" },
}

local soundBindings: Bindings = {
	soundId = { property = "SoundId", convert = "string" },
	volume = { property = "Volume", convert = "nonNegative" },
	playbackSpeed = { property = "PlaybackSpeed", convert = "nonNegative" },
	looped = { property = "Looped", convert = "boolean" },
	playing = { property = "Playing", convert = "boolean" },
	rollOffMinDistance = { property = "RollOffMinDistance", convert = "nonNegative" },
	rollOffMaxDistance = { property = "RollOffMaxDistance", convert = "nonNegative" },
}

local meshBindings: Bindings = {
	collisionFidelity = { property = "CollisionFidelity", convert = "string", enum = "CollisionFidelity" },
	renderFidelity = { property = "RenderFidelity", convert = "string", enum = "RenderFidelity" },
}

local function schema(): Design.Library
	return {
		name = "Roblox3D",
		containerKind = "Model",
		parameter = "Host",
		parameterType = "nil",
		prelude = {},
		returnType = "Instance",
		readable = "Compose.ReadOnlyValue",
		cell = "Compose.Cell",
		space = "3d",
		categories = categories(),
		kinds = named(kinds()),
	}
end

local function create(
	runtime: Compose.Runtime,
	environment: Environment.Environment,
	sequences: Sequences?
): Design.Library
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

	local function place(props: Props, set: ({ number }) -> ())
		local position: UI.Vector = { X = 0, Y = 0, Z = 0 }
		local rotation: UI.Vector = { X = 0, Y = 0, Z = 0 }
		local transform = Math.frame { X = 0, Y = 0, Z = 0 }
		local function update()
			set(
				Math.multiply(
					transform,
					Math.multiply(
						Math.frame(position),
						Math.rotation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
					)
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
		apply(props.transform, function(value: Design.Literal?)
			transform = Math.frame { X = 0, Y = 0, Z = 0 }
			if type(value) == "table" then
				local rows = if type(value[1]) == "table" then value else { value }
				for _, row in rows do
					assert(type(row) == "table", "A transform needs an operation or twelve numeric CFrame components")
					local position, angles = row.position, row.angles
					if position ~= nil or angles ~= nil then
						assert(
							(position ~= nil) ~= (angles ~= nil) and #row == 0,
							"A transform operation has one position or angles"
						)
						for key in row do
							assert(
								key == (if position ~= nil then "position" else "angles"),
								"A transform operation has one operand"
							)
						end
						local operand = if position ~= nil then position else angles
						assert(type(operand) == "table" and #operand == 3, "A transform operation needs three numbers")
						local x, y, z = operand[1], operand[2], operand[3]
						assert(
							type(x) == "number" and type(y) == "number" and type(z) == "number",
							"A transform operation needs three numbers"
						)
						local components = if position ~= nil
							then Math.frame { X = x, Y = y, Z = z }
							else Math.multiply(
								Math.multiply(Math.rotation(x, 0, 0), Math.rotation(0, y, 0)),
								Math.rotation(0, 0, z)
							)
						transform = Math.multiply(transform, components)
						continue
					end
					assert(#row == 12, "A transform has twelve numeric CFrame components")
					local components: { number } = {}
					for index = 1, 12 do
						local component = row[index]
						assert(type(component) == "number", "A transform has twelve numeric CFrame components")
						components[index] = component
					end
					transform = Math.multiply(transform, components)
				end
			end
			update()
		end)
		update()
	end

	local function text(value: Design.Literal?): string?
		return if type(value) == "string" then value else nil
	end

	local function hexColor(value: Design.Literal?): unknown
		if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
			return ui.hex(value)
		end
		if type(value) == "table" then
			local r, g, b = value[1], value[2], value[3]
			assert(
				type(r) == "number" and type(g) == "number" and type(b) == "number" and #value == 3,
				"A color has three RGB channels"
			)
			for key in value do
				assert(key == 1 or key == 2 or key == 3, "A color has three RGB channels")
			end
			return ui.values.color(r, g, b)
		end
		return nil
	end

	local function rgb(value: Design.Literal?): { number }?
		if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
			return {
				(tonumber(string.sub(value, 2, 3), 16) or 0) / 255,
				(tonumber(string.sub(value, 4, 5), 16) or 0) / 255,
				(tonumber(string.sub(value, 6, 7), 16) or 0) / 255,
			}
		end
		return nil
	end

	local function pair(value: Design.Literal?): (number?, number?)
		if type(value) ~= "table" then
			return nil, nil
		end
		local low, high = value[1], value[2]
		if type(low) == "number" and type(high) == "number" then
			return low, high
		end
		return nil, nil
	end

	local function sequence(value: Design.Literal?, color: boolean): { { number } }?
		if type(value) == "string" and color then
			local components = rgb(value)
			if components then
				return {
					{ 0, components[1], components[2], components[3] },
					{ 1, components[1], components[2], components[3] },
				}
			end
			return nil
		end
		if type(value) == "number" and not color then
			return { { 0, value }, { 1, value } }
		end
		if type(value) ~= "table" then
			return nil
		end
		local points: { { number } } = {}
		for _, point in value do
			if type(point) ~= "table" then
				return nil
			end
			local time, entry = point[1], point[2]
			if type(time) ~= "number" then
				return nil
			end
			if color then
				local components = rgb(entry)
				if components == nil then
					return nil
				end
				table.insert(points, { time, components[1], components[2], components[3] })
			elseif type(entry) == "number" then
				table.insert(points, { time, entry })
			else
				return nil
			end
		end
		return if #points > 0 then points else nil
	end

	local function converted(binding: Binding, value: Design.Literal?): unknown
		local kind = binding.convert
		if kind == "number" then
			return if type(value) == "number" then value else nil
		elseif kind == "nonNegative" then
			return if type(value) == "number" then math.max(value, 0) else nil
		elseif kind == "unit" then
			return if type(value) == "number" then math.clamp(value, 0, 1) else nil
		elseif kind == "reach" then
			return if type(value) == "number" then math.clamp(value, 0, 60) else nil
		elseif kind == "angle" then
			return if type(value) == "number" then math.clamp(value, 0, 180) else nil
		elseif kind == "tile" then
			return if type(value) == "number" then math.max(value, 0.01) else nil
		elseif kind == "boolean" then
			return value == true
		elseif kind == "string" then
			local item = text(value)
			if item == nil then
				return nil
			end
			return if binding.enum then ui.values.enum(binding.enum, item) else item
		elseif kind == "color" then
			return hexColor(value)
		elseif kind == "vector3" then
			local extent = vector(value, { X = 0, Y = 0, Z = 0 })
			return ui.values.vector3(extent.X, extent.Y, extent.Z)
		elseif kind == "vector2" then
			local x, y = pair(value)
			local make = ui.values.vector2
			return if x and y then make(x, y) else nil
		elseif kind == "range" then
			local low, high = pair(value)
			local make = if sequences then sequences.numberRange else nil
			if low and high and make then
				return make(low, high)
			end
			return nil
		elseif kind == "numberSequence" then
			local points = sequence(value, false)
			local make = if sequences then sequences.numberSequence else nil
			return if points and make then make(points) else nil
		end
		local points = sequence(value, true)
		local make = if sequences then sequences.colorSequence else nil
		return if points and make then make(points) else nil
	end

	local function bind(node: Compose.Node, props: Props, bindings: Bindings)
		for key, binding in bindings do
			apply(props[key], function(value: Design.Literal?)
				local made = converted(binding, value)
				if made ~= nil then
					ui.set(node, binding.property, made)
				end
			end)
		end
	end

	local function attach(parent: Compose.Node, children: { unknown })
		for _, child in children do
			if child ~= nil then
				ui.set(child, "Parent", parent)
			end
		end
	end

	local function describe(node: Compose.Node, props: Props)
		apply(props.attributes, function(value: Design.Literal?)
			if type(value) ~= "table" then
				return
			end
			local entries: { [string]: Design.Literal } = {}
			for key, item in value do
				if type(key) == "string" and type(item) ~= "table" then
					entries[key] = item
				end
			end
			ui.runtime.decorate(node, { Attributes = entries })
		end)
	end

	local function body(part: Compose.Node, props: Props, children: { unknown })
		ui.set(part, "Anchored", true)
		apply(props.topSurface, function(value: Design.Literal?)
			ui.set(part, "TopSurface", enumItem("SurfaceType", value, "Smooth"))
		end)
		apply(props.bottomSurface, function(value: Design.Literal?)
			ui.set(part, "BottomSurface", enumItem("SurfaceType", value, "Smooth"))
		end)
		apply(props.size, function(value: Design.Literal?)
			local extent = vector(value, { X = 4, Y = 1, Z = 4 })
			ui.set(part, "Size", ui.values.vector3(extent.X, extent.Y, extent.Z))
		end)
		apply(props.color, function(value: Design.Literal?)
			local made = hexColor(value)
			if made ~= nil then
				ui.set(part, "Color", made)
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
		bind(part, props, physicsBindings)
		describe(part, props)
		attach(part, children)
		place(props, function(frame: { number })
			ui.set(part, "CFrame", ui.values.cframe(frame))
		end)
	end

	local function plain(className: string, bindings: Bindings): Build
		return function(props: Props): unknown
			local node = ui.new(className)
			bind(node, props, bindings)
			return node
		end
	end

	local builds: { [string]: Build } = {
		Pattern = function(props: Props): unknown
			local template = props.render
			local render = if template then template.template else nil
			if render == nil then
				return ui.new "Model"
			end
			local config: { [string | number]: unknown } = {}
			for key, property in props do
				if key ~= "render" then
					config[key] = if property.readable then property.readable:peek() else property.literal
				end
			end
			local rows = Patterns.rows(config)
			local model = ui.new "Model"
			local function vectorLiteral(value: { number }): Design.Literal
				local result: { [string | number]: Design.Literal } = {}
				for index, component in value do
					result[index] = component
				end
				return result
			end
			for _, row in rows do
				local current: Design.Row = {
					id = row.id,
					name = row.name,
					visible = row.visible,
					position = vectorLiteral(row.position),
					rotation = vectorLiteral(row.rotation),
					size = vectorLiteral(row.size),
					color = if type(row.color) == "string" then row.color else vectorLiteral(row.color),
				}
				ui.set(render(Compose.cell(current)), "Parent", model)
			end
			return model
		end,
		Array = function(props: Props): unknown
			local source, template = props.from, props.render
			local rows = if source then source.rows else nil
			local render = if template then template.template else nil
			if rows == nil or render == nil then
				return ui.new "Model"
			end
			local key = assert(source and source.key, "An Array needs a key")
			local current = rows:peek()
			local seen: { [string | number]: boolean } = {}
			for _, row in current do
				local id = row[key]
				assert(type(id) == "string" or type(id) == "number", "An Array row needs a string or number key")
				assert(not seen[id], `Duplicate Array key {id}`)
				seen[id] = true
			end
			local model = ui.new "Model"
			for _, row in current do
				ui.set(render(Compose.cell(row)), "Parent", model)
			end
			return model
		end,
		Model = function(props: Props, children: { unknown }): unknown
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
			apply(props.streamingMode, function(value: Design.Literal?)
				ui.set(model, "ModelStreamingMode", enumItem("ModelStreamingMode", value, "Default"))
			end)
			describe(model, props)
			local offsets: { [Compose.Node]: { number } } = {}
			for _, child in children do
				if child ~= nil then
					ui.set(child, "Parent", model)
				end
			end
			for _, part in ui.descendants(model) do
				if part ~= primary and ui.isA(part, "BasePart") then
					offsets[part] = ui.components(ui.get(part, "CFrame"))
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
		Folder = function(_props: Props, children: { unknown }): unknown
			local folder = ui.new "Folder"
			attach(folder, children)
			return folder
		end,
		SpecialMesh = plain("SpecialMesh", {
			meshId = { property = "MeshId", convert = "string" },
			textureId = { property = "TextureId", convert = "string" },
			scale = { property = "Scale", convert = "vector3" },
			offset = { property = "Offset", convert = "vector3" },
			meshType = { property = "MeshType", convert = "string", enum = "MeshType" },
			vertexColor = { property = "VertexColor", convert = "vector3" },
		}),
		Part = function(props: Props, children: { unknown }): unknown
			local shape = props.shape and props.shape.literal
			local class = props.partClass and props.partClass.literal
			local part: Compose.Node = if class == "Part"
					or class == "WedgePart"
					or class == "CornerWedgePart"
				then ui.new(class)
				elseif shape == "Wedge" then ui.new "WedgePart"
				elseif shape == "CornerWedge" then ui.new "CornerWedgePart"
				else ui.new "Part"
			if ui.isA(part, "Part") then
				local block = part
				apply(props.shape, function(value: Design.Literal?)
					ui.set(block, "Shape", enumItem("PartType", value, "Block"))
				end)
			end
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
			body(part, props, children)
			return part
		end,
		MeshPart = function(props: Props, children: { unknown }): unknown
			local part = ui.new "MeshPart"
			apply(props.meshId, function(value: Design.Literal?)
				pcall(ui.set, part, "MeshId", text(value) or "")
			end)
			apply(props.textureId, function(value: Design.Literal?)
				pcall(ui.set, part, "TextureID", text(value) or "")
			end)
			bind(part, props, meshBindings)
			body(part, props, children)
			return part
		end,
		Attachment = function(props: Props): unknown
			local attachment = ui.new "Attachment"
			place(props, function(frame: { number })
				ui.set(attachment, "CFrame", ui.values.cframe(frame))
			end)
			return attachment
		end,
		PointLight = plain("PointLight", lightBindings),
		SpotLight = plain("SpotLight", lightBindings),
		SurfaceLight = plain("SurfaceLight", lightBindings),
		ParticleEmitter = plain("ParticleEmitter", emitterBindings),
		Fire = plain("Fire", fireBindings),
		Smoke = plain("Smoke", smokeBindings),
		Sparkles = plain("Sparkles", sparklesBindings),
		Sound = plain("Sound", soundBindings),
	}
	builds.Fragment = builds.Model
	for _, className in { "Decal", "Texture" } do
		builds[className] = function(props: Props): unknown
			local node = ui.new(className)
			apply(props.image, function(value: Design.Literal?)
				ui.set(node, "Texture", text(value) or "")
			end)
			apply(props.color, function(value: Design.Literal?)
				local made = hexColor(value)
				if made ~= nil then
					ui.set(node, "Color3", made)
				end
			end)
			bind(node, props, imageBindings)
			return node
		end
	end

	local library = schema()
	for name, kind in library.kinds do
		local build = assert(builds[name], `{name} has no build`)
		kind.build = function(props: Props, children: { unknown }, label: string): unknown
			local built = build(props, children, label)
			if built ~= nil then
				ui.set(built, "Name", label)
			end
			return built
		end
	end

	return library
end

return { create = create, schema = schema }
