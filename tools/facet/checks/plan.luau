--!strict

local Files = require("../lib/files")
local Json = require("../lib/json")
local Rule = require("../lib/rule")

local function specSources(context: Rule.Context): ({ [string]: string }, { string })
	local sources: { [string]: string } = {}
	local failures: { string } = {}
	for _, relative in Files.walk(context.path("tests")) do
		local suffix = string.sub(relative, -10)
		if suffix == ".spec.luau" or suffix == "_spec.luau" then
			local name = string.sub(relative, 1, -11)
			if sources[name] ~= nil then
				table.insert(failures, "spec files share the same ID: " .. name)
			end
			sources[name] = "tests/" .. relative
		end
	end
	return sources, failures
end

local function check(context: Rule.Context): { string }
	local path = context.path("tests/plan.json")
	if not Files.isFile(path) then
		return { "cannot read tests/plan.json: the file does not exist" }
	end
	local plan, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return { "cannot read tests/plan.json: " .. problem }
	end
	local units = Json.arrayField(plan, "units")
	if units == nil then
		return { "Verify plan must contain a units list" }
	end
	local sources, failures = specSources(context)
	local declared: { [string]: boolean } = {}
	local locators: { [string]: boolean } = {}
	for index, unit in units do
		local name = Json.stringField(unit, "id")
		if name == nil or name == "" then
			table.insert(failures, ("Verify plan unit %d needs a nonempty ID"):format(index))
			continue
		end
		if declared[name] then
			table.insert(failures, "duplicate Verify plan ID: " .. name)
		end
		declared[name] = true
		local locator = Json.stringField(unit, "locator")
		if locator == nil then
			table.insert(failures, ("Verify plan unit %s needs a locator"):format(name))
			continue
		end
		if locators[locator] then
			table.insert(failures, "duplicate Verify plan locator: " .. locator)
		end
		locators[locator] = true
		if sources[name] == nil then
			table.insert(failures, "Verify plan spec is not on disk: " .. name)
		elseif locator ~= sources[name] then
			table.insert(failures, ("Verify plan locator for %s must be %s"):format(name, sources[name]))
		end
	end
	local missing: { string } = {}
	for name in sources do
		if not declared[name] then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	for _, name in missing do
		table.insert(failures, "spec is missing from the Verify plan: " .. name)
	end
	return failures
end

local function plan(units: { { [string]: string } }): string
	local encoded: { unknown } = {}
	for _, unit in units do
		table.insert(encoded, unit)
	end
	return Json.encode({ units = encoded })
end

local function same(actual: { string }, expected: { string }): string?
	if #actual ~= #expected then
		return ("expected %s, got %s"):format(Rule.describe(expected), Rule.describe(actual))
	end
	for index, value in expected do
		if actual[index] ~= value then
			return ("expected %s, got %s"):format(Rule.describe(expected), Rule.describe(actual))
		end
	end
	return nil
end

local function cases(): { Rule.Case }
	return {
		{
			name = "every nested spec and the legacy suffix are accepted once",
			run = function()
				return Rule.within({
					["tests/native.spec.luau"] = "return {}",
					["tests/nested/control_spec.luau"] = "return {}",
					["tests/lib/helper.luau"] = "return {}",
					["tests/plan.json"] = plan({
						{ id = "native", locator = "tests/native.spec.luau" },
						{ id = "nested/control", locator = "tests/nested/control_spec.luau" },
					}),
				}, function(context)
					return same(check(context), {})
				end)
			end,
		},
		{
			name = "a missing source and an undeclared spec are rejected",
			run = function()
				return Rule.within({
					["tests/added.spec.luau"] = "return {}",
					["tests/plan.json"] = plan({ { id = "removed", locator = "tests/removed.spec.luau" } }),
				}, function(context)
					return same(check(context), {
						"Verify plan spec is not on disk: removed",
						"spec is missing from the Verify plan: added",
					})
				end)
			end,
		},
		{
			name = "duplicate IDs and locators are rejected",
			run = function()
				local unit = { id = "native", locator = "tests/native.spec.luau" }
				return Rule.within({
					["tests/native.spec.luau"] = "return {}",
					["tests/plan.json"] = plan({ unit, unit }),
				}, function(context)
					return same(check(context), {
						"duplicate Verify plan ID: native",
						"duplicate Verify plan locator: tests/native.spec.luau",
					})
				end)
			end,
		},
		{
			name = "a locator that does not match its source ID is rejected",
			run = function()
				return Rule.within({
					["tests/native.spec.luau"] = "return {}",
					["tests/plan.json"] = plan({ { id = "native", locator = "tests/other.spec.luau" } }),
				}, function(context)
					return same(check(context), { "Verify plan locator for native must be tests/native.spec.luau" })
				end)
			end,
		},
		{
			name = "unreadable, malformed and incomplete plans are rejected",
			run = function()
				return Rule.within({ ["tests/keep.txt"] = "" }, function(context)
					local absent = check(context)[1] or ""
					if string.find(absent, "cannot read tests/plan.json", 1, true) == nil then
						return "an absent plan: " .. absent
					end
					Files.write(context.path("tests/plan.json"), "{")
					local broken = check(context)[1] or ""
					if string.find(broken, "cannot read tests/plan.json", 1, true) == nil then
						return "a malformed plan: " .. broken
					end
					Files.write(context.path("tests/plan.json"), "[]")
					local shapeless = same(check(context), { "Verify plan must contain a units list" })
					if shapeless ~= nil then
						return shapeless
					end
					Files.write(context.path("tests/plan.json"), '{"units": [null, {"id": "native"}]}')
					return same(check(context), {
						"Verify plan unit 1 needs a nonempty ID",
						"Verify plan unit native needs a locator",
					})
				end)
			end,
		},
		{
			name = "spec files with colliding IDs are rejected",
			run = function()
				return Rule.within({
					["tests/native.spec.luau"] = "return {}",
					["tests/native_spec.luau"] = "return {}",
					["tests/plan.json"] = plan({ { id = "native", locator = "tests/native_spec.luau" } }),
				}, function(context)
					return same(check(context), { "spec files share the same ID: native" })
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "plan",
	summary = "tests/plan.json lists each spec file on disk exactly once.",
	check = check,
	cases = cases,
}

return rule
