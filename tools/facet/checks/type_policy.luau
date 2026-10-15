--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Rule = require("../lib/rule")
local VerifyLute = require("../../vendor/verify/src/lute")

local BUDGET = "tools/typecheck/any_budget.json"
local DIRECTORIES = { "src", "eval", "examples", "tools", "tests", "bench" }
local BUDGETED = { "examples", "tools", "tests", "bench" }

export type Counts = { [string]: number }
export type Budget = { [string]: number? }

export type Inventory = {
	counts: Counts,
	locations: { string },
	failure: string?,
}

local function uses(source: string): ({ number }?, string?)
	local ok, result = pcall(VerifyLute.typePolicy.explicitAny, source)
	if not ok then
		local message = string.gsub(tostring(result), "^.-parsing failed:%s*", "")
		return nil, (string.gsub(message, "%s+$", ""))
	end
	return result :: { number }, nil
end

local function inventory(context: Rule.Context, directories: { string }): Inventory
	local counts: Counts = {}
	local locations: { string } = {}
	for _, directory in directories do
		local count = 0
		for _, relative in Files.walk(context.path(directory)) do
			local extension = Files.extension(relative)
			local path = directory .. "/" .. relative
			if (extension == ".luau" or extension == ".lua") and not Files.vendored(path) then
				local lines, problem = uses(Files.read(context.path(path)))
				if lines == nil then
					return { counts = counts, locations = locations, failure = ("%s: %s"):format(path, problem or "") }
				end
				count += #lines
				if directory == "src" then
					for _, line in lines do
						table.insert(locations, ("%s:%d"):format(path, line))
					end
				end
			end
		end
		counts[directory] = count
	end
	return { counts = counts, locations = locations }
end

local function readBudget(context: Rule.Context): (Budget?, string?)
	local path = context.path(BUDGET)
	if not Files.isFile(path) then
		return nil, BUDGET .. " is missing"
	end
	local document, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return nil, BUDGET .. ": " .. problem
	end
	local object = Json.asObject(document)
	if object == nil then
		return nil, BUDGET .. " is not a JSON object"
	end
	local budget: Budget = {}
	for _, directory in BUDGETED do
		local value = object[directory]
		if type(value) == "number" then
			budget[directory] = value
		elseif value ~= nil and not Json.isNull(value) then
			return nil, ("%s: %s must be a number or null"):format(BUDGET, directory)
		end
	end
	return budget, nil
end

local function violations(counts: Counts, budget: Budget): { string }
	local errors: { string } = {}
	for _, directory in { "src", "eval" } do
		if (counts[directory] or 0) > 0 then
			table.insert(errors, ("%s contains %d forbidden any types"):format(directory, counts[directory]))
		end
	end
	for _, directory in BUDGETED do
		local limit = budget[directory]
		local count = counts[directory]
		if limit ~= nil and count ~= nil and count > limit then
			table.insert(errors, ("%s: %d any types exceeds budget %d"):format(directory, count, limit))
		end
	end
	return errors
end

local function lowered(counts: Counts, budget: Budget): (Json.Object?, string?)
	for _, directory in BUDGETED do
		local old = budget[directory]
		local count = counts[directory] or 0
		if old ~= nil and count > old then
			return nil, ("cannot raise %s budget from %d to %d"):format(directory, old, count)
		end
	end
	local written = Json.object()
	for _, directory in BUDGETED do
		Json.set(written, directory, counts[directory] or 0)
	end
	return written, nil
end

local function encodeCounts(counts: Counts, sortKeys: boolean): string
	local object = Json.object()
	for _, directory in DIRECTORIES do
		if counts[directory] ~= nil then
			Json.set(object, directory, counts[directory])
		end
	end
	if sortKeys then
		return Json.encode(object, { sortKeys = true })
	end
	return Json.encode(object, { indent = 2 })
end

local function findings(context: Rule.Context): ({ string }, Counts?, { string })
	local budget, problem = readBudget(context)
	if budget == nil then
		return { "type policy: FAIL; " .. (problem or "") }, nil, {}
	end
	local directories: { string } = {}
	for _, directory in DIRECTORIES do
		if directory ~= "tests" or budget.tests ~= nil then
			table.insert(directories, directory)
		end
	end
	local found = inventory(context, directories)
	if found.failure ~= nil then
		return { "type policy: FAIL; " .. found.failure }, nil, {}
	end
	local notes: { string } = {}
	if budget.tests == nil then
		table.insert(notes, "tests budget pending: lead must run --lower-budgets after the test edits")
	end
	local errors = violations(found.counts, budget)
	for _, location in found.locations do
		table.insert(errors, location)
	end
	return errors, found.counts, notes
end

local function check(context: Rule.Context): { string }
	local errors, counts, notes = findings(context)
	if counts ~= nil then
		print(encodeCounts(counts, true))
	end
	for _, note in notes do
		print(note)
	end
	return errors
end

local function printCounts(context: Rule.Context, _invocation: Cli.Invocation): number
	local found = inventory(context, DIRECTORIES)
	if found.failure ~= nil then
		print("type policy: FAIL; " .. found.failure)
		return 1
	end
	print(encodeCounts(found.counts, false))
	return 0
end

local function lowerBudgets(context: Rule.Context, _invocation: Cli.Invocation): number
	local budget, problem = readBudget(context)
	if budget == nil then
		print("type policy: FAIL; " .. (problem or ""))
		return 1
	end
	local found = inventory(context, DIRECTORIES)
	if found.failure ~= nil then
		print("type policy: FAIL; " .. found.failure)
		return 1
	end
	local written, refusal = lowered(found.counts, budget)
	if written == nil then
		print("type policy: FAIL; " .. (refusal or ""))
		return 1
	end
	Files.write(context.path(BUDGET), Json.pretty(written))
	local updated = readBudget(context) or {}
	local errors = violations(found.counts, updated)
	print(encodeCounts(found.counts, true))
	for _, message in errors do
		print(message)
	end
	for _, location in found.locations do
		print(location)
	end
	return if #errors == 0 then 0 else 1
end

local function count(source: string): number
	local lines = uses(source)
	return if lines then #lines else -1
end

local function cases(): { Rule.Case }
	return {
		{
			name = "annotations, casts and nested types count",
			run = function()
				return Rule.expect(
					count("local x: any = y :: any; type T = (any) -> {any}") == 4,
					"expected 4 uses, got " .. count("local x: any = y :: any; type T = (any) -> {any}")
				)
			end,
		},
		{
			name = "strings, comments and identifiers do not count",
			run = function()
				local first = count('local many = "any"; local s = [=[any]=] -- any\n--[==[any]==]')
				local second = count("local s = 'escaped \\' any'")
				return Rule.expect(
					first == 0 and second == 0,
					("expected 0 and 0, got %d and %d"):format(first, second)
				)
			end,
		},
		{
			name = "interpolation expressions count",
			run = function()
				local inside = count("local s = `any {x :: any} {`any {y :: any}`}`")
				local escaped = count("local s = `any \\{any\\}`")
				return Rule.expect(
					inside == 2 and escaped == 0,
					("expected 2 and 0, got %d and %d"):format(inside, escaped)
				)
			end,
		},
		{
			name = "budgets fail when exceeded and src fails at one use",
			run = function()
				local counts: Counts = { src = 0, examples = 0, tools = 0, tests = 0, bench = 0 }
				local budget: Budget = { examples = 0, tools = 0, tests = 0, bench = 0 }
				if #violations(counts, budget) ~= 0 then
					return "a clean inventory failed"
				end
				counts.examples = 1
				if #violations(counts, budget) ~= 1 then
					return "an exceeded budget did not fail once"
				end
				counts.src = 1
				return Rule.expect(#violations(counts, budget) == 2, "a src use did not fail")
			end,
		},
		{
			name = "budgets only decrease and a pending tests budget can be set",
			run = function()
				local counts: Counts = { src = 2, examples = 2, tools = 2, tests = 2, bench = 2 }
				local budget: Budget = { examples = 3, tools = 3, bench = 3 }
				local written = lowered(counts, budget)
				if written == nil or written.tests ~= 2 then
					return "the pending tests budget was not set"
				end
				counts.tools = 4
				local raised = lowered(counts, budget)
				return Rule.expect(raised == nil, "a raised budget was accepted")
			end,
		},
		{
			name = "an invalid source fails",
			run = function()
				local lines = uses("local value: any = 'unfinished")
				return Rule.expect(lines == nil, "an unfinished string parsed")
			end,
		},
		{
			name = "the inventory excludes vendor and counts each directory",
			run = function()
				local files: { [string]: string } = {}
				for _, directory in DIRECTORIES do
					files[directory .. "/main.luau"] = "local value: any = 'any'"
					files[directory .. "/vendor/dependency.luau"] = "type Value = any | any"
				end
				return Rule.within(files, function(context)
					local found = inventory(context, DIRECTORIES)
					for _, directory in DIRECTORIES do
						if found.counts[directory] ~= 1 then
							return ("%s counted %s"):format(directory, tostring(found.counts[directory]))
						end
					end
					return Rule.expect(
						#found.locations == 1 and found.locations[1] == "src/main.luau:1",
						"locations: " .. table.concat(found.locations, ", ")
					)
				end)
			end,
		},
		{
			name = "UTF-8 sources and CRLF line endings are read",
			run = function()
				return Rule.within({
					["src/main.luau"] = 'local text = "\u{e9}\u{1F600}"\r\nlocal value: number = 1\r\n',
					["examples/main.luau"] = 'local label = "\u{2014}"\r\nlocal value: any = 1\r\n',
					[BUDGET] = Json.encode({ examples = 1, tools = 0, tests = 0, bench = 0 }),
				}, function(context)
					local errors = findings(context)
					return Rule.expect(#errors == 0, Rule.describe(errors))
				end)
			end,
		},
		{
			name = "lowering the budgets rewrites the budget file",
			run = function()
				return Rule.within({
					["examples/main.luau"] = "local value: any = 1",
					[BUDGET] = Json.encode({ examples = 5, tools = 0, tests = Json.null, bench = 0 }),
				}, function(context)
					local code = lowerBudgets(context, Cli.parse({}))
					local written = Json.decode(Files.read(context.path(BUDGET)))
					if code ~= 0 then
						return "lowering failed"
					end
					return Rule.expect(
						Json.numberField(written, "examples") == 1 and Json.numberField(written, "tests") == 0,
						Json.encode(written)
					)
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "type-policy",
	summary = "src has no any type; examples, tools, tests and bench stay within tools/typecheck/any_budget.json.",
	check = check,
	cases = cases,
	actions = {
		counts = { summary = "print the current any counts", run = printCounts },
		["lower-budgets"] = { summary = "lower the budgets to the current counts; never raises", run = lowerBudgets },
	},
}

return rule
