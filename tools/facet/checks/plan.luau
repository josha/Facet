--!strict
local Verify = require("../../vendor/verify/src/core")

local Files = require("../lib/files")
local Json = require("../lib/json")
local Rule = require("../lib/rule")

local function specSources(context: Rule.Context, root: string, suffix: string): ({ [string]: string }, { string })
	local sources: { [string]: string } = {}
	local failures: { string } = {}
	for _, relative in Files.walk(context.path(root)) do
		if string.sub(relative, -#suffix) == suffix then
			sources[string.sub(relative, 1, -#suffix - 1)] = root .. "/" .. relative
		end
	end
	return sources, failures
end

local function checkPlan(context: Rule.Context, catalog: string, root: string, suffix: string): { string }
	local path = context.path(catalog)
	if not Files.isFile(path) then
		return { "cannot read " .. catalog .. ": the file does not exist" }
	end
	local plan, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return { "cannot read " .. catalog .. ": " .. problem }
	end
	local units = Json.arrayField(plan, "units")
	if units == nil then
		return { "Verify plan must contain a units list" }
	end
	local sources, failures = specSources(context, root, suffix)
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

local function check(context: Rule.Context): { string }
	local failures = checkPlan(context, "tests/plan.json", "tests", ".verify.luau")
	if Files.isDirectory(context.path("tools/studio/live")) then
		for _, failure in checkPlan(context, "tools/studio/live/plan.json", "tools/studio/live/suites", ".luau") do
			table.insert(failures, failure)
		end
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

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "live source additions and removals must update the committed plan", {
		id = prefix .. "live source additions and removals must update the committed plan",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["tools/studio/live/suites/added.luau"] = "return {}",
				["tools/studio/live/plan.json"] = plan({
					{ id = "removed", locator = "tools/studio/live/suites/removed.luau" },
				}),
			}, function(context)
				Verify.expect(
					same(checkPlan(context, "tools/studio/live/plan.json", "tools/studio/live/suites", ".luau"), {
						"Verify plan spec is not on disk: removed",
						"spec is missing from the Verify plan: added",
					})
				)
					:toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "every nested Verify file is accepted once", {
		id = prefix .. "every nested Verify file is accepted once",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["tests/native.verify.luau"] = "return {}",
				["tests/nested/control.verify.luau"] = "return {}",
				["tests/lib/helper.luau"] = "return {}",
				["tests/plan.json"] = plan({
					{ id = "native", locator = "tests/native.verify.luau" },
					{ id = "nested/control", locator = "tests/nested/control.verify.luau" },
				}),
			}, function(context)
				Verify.expect(same(check(context), {})):toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "a missing source and an undeclared spec are rejected", {
		id = prefix .. "a missing source and an undeclared spec are rejected",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["tests/added.verify.luau"] = "return {}",
				["tests/plan.json"] = plan({ { id = "removed", locator = "tests/removed.verify.luau" } }),
			}, function(context)
				Verify.expect(same(check(context), {
					"Verify plan spec is not on disk: removed",
					"spec is missing from the Verify plan: added",
				})):toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "duplicate IDs and locators are rejected", {
		id = prefix .. "duplicate IDs and locators are rejected",
		run = function(test: Verify.Context)
			local unit = { id = "native", locator = "tests/native.verify.luau" }
			Rule.within(test, {
				["tests/native.verify.luau"] = "return {}",
				["tests/plan.json"] = plan({ unit, unit }),
			}, function(context)
				Verify.expect(same(check(context), {
					"duplicate Verify plan ID: native",
					"duplicate Verify plan locator: tests/native.verify.luau",
				})):toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "a locator that does not match its source ID is rejected", {
		id = prefix .. "a locator that does not match its source ID is rejected",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["tests/native.verify.luau"] = "return {}",
				["tests/plan.json"] = plan({ { id = "native", locator = "tests/other.verify.luau" } }),
			}, function(context)
				Verify.expect(
					same(check(context), { "Verify plan locator for native must be tests/native.verify.luau" })
				)
					:toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "unreadable, malformed and incomplete plans are rejected", {
		id = prefix .. "unreadable, malformed and incomplete plans are rejected",
		run = function(test: Verify.Context)
			Rule.within(test, { ["tests/keep.txt"] = "" }, function(context)
				local absent = check(context)[1] or ""
				if string.find(absent, "cannot read tests/plan.json", 1, true) == nil then
					error("an absent plan: " .. absent, 0)
				end
				Files.write(context.path("tests/plan.json"), "{")
				local broken = check(context)[1] or ""
				if string.find(broken, "cannot read tests/plan.json", 1, true) == nil then
					error("a malformed plan: " .. broken, 0)
				end
				Files.write(context.path("tests/plan.json"), "[]")
				local shapeless = same(check(context), { "Verify plan must contain a units list" })
				if shapeless ~= nil then
					Verify.expect(shapeless):toBeNil()
					return
				end
				Files.write(context.path("tests/plan.json"), '{"units": [null, {"id": "native"}]}')
				Verify.expect(same(check(context), {
					"Verify plan unit 1 needs a nonempty ID",
					"Verify plan unit native needs a locator",
				})):toBeNil()
			end)
		end,
	})
	harness:case(prefix .. "a file with the old spec suffix is not a Verify file", {
		id = prefix .. "a file with the old spec suffix is not a Verify file",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["tests/native.verify.luau"] = "return {}",
				["tests/old.spec.luau"] = "return {}",
				["tests/plan.json"] = plan({ { id = "native", locator = "tests/native.verify.luau" } }),
			}, function(context)
				Verify.expect(same(check(context), {})):toBeNil()
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "plan",
	summary = "The committed Verify plans list each test and live suite source exactly once.",
	check = check,
	register = register,
}

return rule
