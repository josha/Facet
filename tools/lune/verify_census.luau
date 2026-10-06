--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Verify = require("../vendor/verify/src/core")
local requireDynamic = require :: (any) -> any
local inventory = serde.decode("json", fs.readFile("tests/case_inventory.json"))
local expected = {}
local sources = {}
for _, case in inventory.cases do
	expected[case.id] = case
	sources[case.source] = true
end
local actual = {}
for source in sources do
	local harness = Verify.createHarness({ source = source, now = os.clock, prefixIds = false })
	local registerCase = harness.case
	harness.case = function(self, name, definition)
		assert(
			type(definition) == "table" and type(definition.id) == "string",
			"every migrated case needs an explicit ID"
		)
		local id = definition.id
		assert(not actual[id], "duplicate registered case: " .. id)
		assert(
			expected[id] and expected[id].source == source and expected[id].name == name,
			"case differs from the migration census: " .. id
		)
		actual[id] = true
		local gated = expected[id].tier and "tier:" .. expected[id].tier
		assert(
			(definition.tags and definition.tags[1]) == (gated or nil),
			"case tier tag differs from the migration census: " .. id
		)
		registerCase(self, name, definition)
	end
	local register = requireDynamic("../../tests/" .. source .. ".spec")
	register(harness)
end
local count = 0
for id in expected do
	assert(actual[id], "missing migrated case: " .. id)
	count += 1
end
print(`Verify registration census: {count} unchanged case IDs across every migrated source`)
