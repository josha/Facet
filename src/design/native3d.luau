--!strict

local Roblox3D = require("../vendor/compose/design-editor/roblox-3d-library")
local Types = require("./types")

local function kinds(): { [string]: Types.DerivedKind }
	local schema = Roblox3D.schema()
	local mappings: { [string]: { [string]: string } } = {
		Model = {},
		Part = {
			Size = "size",
			Color = "color",
			Material = "material",
			Transparency = "transparency",
			CanCollide = "canCollide",
		},
		PointLight = { Brightness = "brightness", Range = "range", Color = "color" },
	}
	local result: { [string]: Types.DerivedKind } = {}
	for name, mapping in mappings do
		local kind = schema.kinds[name]
		local fields: { [string]: Types.DerivedField } = {}
		for property, key in mapping do
			local field = kind.fields[key]
			fields[property] = {
				type = if property == "Material" or property == "Size" then "datatype" else field.type,
				options = field.options,
				datatype = if property == "Material"
					then "Enum.Material"
					elseif property == "Size" then "Vector3"
					else nil,
			}
		end
		result[name] = { children = kind.children == "list", fields = fields }
	end
	result.Part.fields.CFrame = { type = "datatype", datatype = "CFrame" }
	result.Part.fields.Anchored = { type = "boolean" }
	return result
end

return { kinds = kinds }
