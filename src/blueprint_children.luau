--!strict
-- Normalize numeric entries before property validation. Table hash order is
-- irrelevant: children are copied by explicit, consecutive numeric index.
local function normalizeChildren(spec: any): any
	assert(type(spec) == "table", "Facet: expected a spec table")
	local count, largest = 0, 0
	for key in spec do
		if type(key) == "number" then
			assert(key >= 1 and key % 1 == 0, "Facet: child indices must be positive integers")
			count += 1
			largest = math.max(largest, key)
		end
	end
	if count == 0 then
		if spec.children ~= nil then
			local children = spec.children
			assert(type(children) == "table", "Facet: children must be an array of blueprints")
			local length, maximum = 0, 0
			for index, child in children do
				assert(
					type(index) == "number" and index >= 1 and index % 1 == 0,
					"Facet: child indices must be positive integers"
				)
				length += 1
				maximum = math.max(maximum, index)
				assert(
					type(child) == "table" and type(child.class) == "string" and type(child.props) == "table",
					"Facet: each child must be a blueprint"
				)
			end
			assert(length == maximum, "Facet: children must be a dense array (no holes)")
		end
		return spec
	end
	assert(count == largest, "Facet: children must be a dense array (no holes)")
	assert(spec.children == nil, "Facet: use numeric children or children, not both")
	local normalized, children = table.clone(spec), {}
	for i = 1, count do
		local child = spec[i]
		assert(
			type(child) == "table" and type(child.class) == "string" and type(child.props) == "table",
			"Facet: each child must be a blueprint"
		)
		children[i] = child
		normalized[i] = nil
	end
	normalized.children = children
	return normalized
end

return normalizeChildren
