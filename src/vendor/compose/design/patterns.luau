--!strict

export type Color = string | { number }
export type Row =
	{ id: string, name: string, position: { number }, rotation: { number }, size: { number }, color: Color }
type Vector = { x: number, y: number, z: number }
type Record = { [string | number]: unknown }
local ZERO: Vector = { x = 0, y = 0, z = 0 }

local fields: { { id: string, type: "string" | "vector3" | "color", luauType: string? } } = {
	{ id = "id", type = "string" },
	{ id = "name", type = "string" },
	{ id = "position", type = "vector3" },
	{ id = "rotation", type = "vector3" },
	{ id = "size", type = "vector3" },
	{ id = "color", type = "color", luauType = "unknown" },
}

local function number(value: unknown, fallback: number): number
	if value == nil then
		return fallback
	end
	assert(type(value) == "number" and value == value and math.abs(value) < 1e6, "A pattern needs finite numbers")
	return value
end

local function record(value: unknown): Record
	assert(type(value) == "table", "A pattern value is a record")
	local result: Record = {}
	for key, item in value do
		assert(type(key) == "string" or type(key) == "number", "A pattern key is text or a number")
		result[key] = item
	end
	return result
end

local function triple(value: unknown, fallback: Vector): Vector
	if value == nil then
		return fallback
	end
	local values = record(value)
	assert(#values == 3, "A pattern vector has three numbers")
	for key in values do
		assert(key == 1 or key == 2 or key == 3, "A pattern vector has three numbers")
	end
	return { x = number(values[1], 0), y = number(values[2], 0), z = number(values[3], 0) }
end

local function color(value: unknown, fallback: Color): Color
	if value == nil then
		return fallback
	end
	if type(value) == "string" then
		assert(string.match(value, "^#%x%x%x%x%x%x$"), "A pattern color is hex or an RGB vector")
		return value
	end
	local channels = triple(value, ZERO)
	return { channels.x, channels.y, channels.z }
end

local function rows(props: { [string | number]: unknown }): { Row }
	local mode = props.mode or "linear"
	assert(mode == "linear" or mode == "grid" or mode == "radial", "A pattern is linear, grid or radial")
	local columns = number(props.columns, 3)
	local rowCount = number(props.rows, 3)
	local count = if mode == "grid" then columns * rowCount else number(props.count, 3)
	local columnMajor = props.order == "column"
	assert(props.order == nil or columnMajor or props.order == "row", "A grid order is row or column")
	assert(props.fit == nil or type(props.fit) == "boolean", "Grid fitting is a boolean")
	assert(count >= 0 and count <= 500 and count % 1 == 0, "A pattern has 0 to 500 instances")
	assert(
		columns >= 1 and columns % 1 == 0 and rowCount >= 1 and rowCount % 1 == 0,
		"A grid has positive integer columns and rows"
	)
	local origin = triple(props.position, ZERO)
	local spacing = triple(props.spacing, { x = 3, y = 0, z = 0 })
	local extent = triple(props.extent, { x = 9, y = 0, z = 9 })
	local gap = triple(props.gap, ZERO)
	local rotation = triple(props.rotation, ZERO)
	local size = triple(props.size, { x = 4, y = 1, z = 4 })
	local radius = number(props.radius, 3)
	local indexOrigin = number(props.indexOrigin, 1)
	assert(indexOrigin % 1 == 0, "A pattern index origin is an integer")
	local name = props.namePattern or "Item%d"
	assert(type(name) == "string" and #name <= 160, "A pattern has a short name pattern")
	local _, placeholders = string.gsub(name, "%%d", "")
	assert(
		placeholders == 1 or (mode == "grid" and placeholders == 2),
		"A name pattern has one index or two grid indices"
	)
	assert(not string.find(string.gsub(name, "%%d", ""), "%%"), "A name pattern contains only %d placeholders")
	local variants: { Record } = {}
	if props.variants ~= nil then
		local data = record(props.variants)
		assert(#data <= 32, "A pattern has at most 32 variants")
		for key in data do
			assert(
				type(key) == "number" and key >= 1 and key <= #data and key % 1 == 0,
				"Pattern variants form a dense list"
			)
		end
		for index = 1, #data do
			table.insert(variants, record(data[index]))
		end
	end
	local bySum = props.variantBy == "sum"
	assert(props.variantBy == nil or bySum or props.variantBy == "index", "A pattern varies by index or grid sum")
	local baseColor = color(props.color, "#FFFFFF")
	local rx, ry, rz = math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local result: { Row } = {}
	for index = 0, count - 1 do
		local column = if columnMajor then math.floor(index / rowCount) else index % columns
		local row = if columnMajor then index % rowCount else math.floor(index / columns)
		local variantIndex = if bySum then column + row else index
		local variant: Record = if #variants > 0 then variants[variantIndex % #variants + 1] else {}
		for key in variant do
			assert(
				key == "position" or key == "rotation" or key == "size" or key == "color" or key == "name",
				"A pattern variant has position, rotation, size, color or name"
			)
		end
		local offset = triple(variant.position, ZERO)
		local turn = triple(variant.rotation, ZERO)
		local x: number = offset.x
		local y: number = offset.y
		local z: number = offset.z
		local yaw: number = 0
		if mode == "radial" then
			local angle = index / count * math.pi * 2
			x = math.sin(angle) * radius + x
			z = math.cos(angle) * radius + z
			yaw = math.deg(angle)
		elseif mode == "grid" then
			x, z =
				(column + 0.5) * extent.x / columns - extent.x / 2 + x,
				(row + 0.5) * extent.z / rowCount - extent.z / 2 + z
		else
			x, y, z = index * spacing.x + x, index * spacing.y + y, index * spacing.z + z
		end
		local shade = color(variant.color, baseColor)
		local extent_ = triple(variant.size, size)
		if mode == "grid" and props.fit == true then
			extent_ = { x = extent.x / columns - gap.x, y = extent_.y, z = extent.z / rowCount - gap.z }
		end
		assert(extent_.x > 0 and extent_.y > 0 and extent_.z > 0, "Pattern sizes are positive")
		local id = if placeholders == 2
			then string.format(name, column + indexOrigin, row + indexOrigin)
			else string.format(name, index + indexOrigin)
		local label = variant.name or id
		assert(type(label) == "string" and #label <= 160, "A pattern variant has a short name")
		table.insert(result, {
			id = id,
			name = label,
			position = {
				origin.x + (cy * cz + sy * sx * sz) * x + (-cy * sz + sy * sx * cz) * y + sy * cx * z,
				origin.y + cx * sz * x + cx * cz * y - sx * z,
				origin.z + (-sy * cz + cy * sx * sz) * x + (sy * sz + cy * sx * cz) * y + cy * cx * z,
			},
			rotation = { rotation.x + turn.x, rotation.y + turn.y + yaw, rotation.z + turn.z },
			size = { extent_.x, extent_.y, extent_.z },
			color = shade,
		})
	end
	return result
end

return { rows = rows, fields = fields }
