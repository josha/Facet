--!strict

local value = {}

function value.validate(item: any, depth: number?, seen: any?): any
	local level, visiting = depth or 0, seen or {}
	assert(level <= 12, "Structured values support at most 12 levels")
	local kind = type(item)
	if kind == "number" then
		assert(item == item and math.abs(item) < 1000000, "Use finite numbers below one million")
	elseif kind == "string" then
		assert(#item <= 10000, "Text exceeds 10000 bytes")
	elseif kind == "table" then
		assert(not visiting[item], "Structured values cannot contain cycles")
		visiting[item] = true
		local count = 0
		for key, child in item do
			count += 1
			assert(count <= 500, "Structured values support at most 500 entries")
			assert(
				type(key) == "string" or (type(key) == "number" and key % 1 == 0 and key > 0),
				"Invalid structured value key"
			)
			value.validate(child, level + 1, visiting)
		end
		visiting[item] = nil
	else
		assert(kind == "boolean", "Use strings, numbers, booleans, arrays, or objects")
	end
	return item
end

function value.literal(item: any): string
	local kind = type(item)
	if kind == "string" then
		return string.format("%q", item)
	end
	if kind == "number" or kind == "boolean" then
		return tostring(item)
	end
	assert(kind == "table", "Unsupported source literal")
	local keys, pieces = {}, {}
	for key in item do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then
			return a < b
		end
		return type(a) == "number"
	end)
	for _, key in keys do
		table.insert(pieces, "[" .. value.literal(key) .. "] = " .. value.literal(item[key]))
	end
	return "{ " .. table.concat(pieces, ", ") .. " }"
end

function value.color(hex: string): any
	assert(string.match(hex, "^#%x%x%x%x%x%x$"), "Use a color in #RRGGBB format")
	return {
		tag = "color",
		r = tonumber(string.sub(hex, 2, 3), 16),
		g = tonumber(string.sub(hex, 4, 5), 16),
		b = tonumber(string.sub(hex, 6, 7), 16),
	}
end

return value
