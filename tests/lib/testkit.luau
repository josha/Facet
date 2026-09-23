--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local testkit = {}

type Case = { name: string, fn: () -> (), id: string? }
type Suite = { name: string, spec: string, cases: { Case } }

export type CaseOptions = { id: string? }
export type RunOptions = {
	jsonOut: string?,
	tier: string?,
	registeredSpecs: number?,
}

local suites: { Suite } = {}
local currentSuite: Suite? = nil

local function callerSpec(): string
	for level = 2, 16 do
		local ok, src = pcall(debug.info, level, "s")
		if not ok or src == nil or src == "" then
			break
		end
		local rel = string.match(src, "/tests/(.+)$") or string.match(src, "^tests/(.+)$")
		if rel ~= nil and string.find(rel, "^lib/") == nil then
			return string.match(rel, "^(.*)%.spec$") or rel
		end
	end
	return "unknown"
end

function testkit.describe(name: string, body: () -> ())
	local suite: Suite = { name = name, spec = callerSpec(), cases = {} }
	table.insert(suites, suite)
	local prev = currentSuite
	currentSuite = suite
	body()
	currentSuite = prev
end

local beforeEachHooks: { () -> () } = {}
local afterEachHooks: { () -> () } = {}

function testkit.beforeEach(fn: () -> ())
	table.insert(beforeEachHooks, fn)
end

function testkit.afterEach(fn: () -> ())
	table.insert(afterEachHooks, fn)
end

function testkit.it(name: string, fn: () -> (), options: CaseOptions?)
	assert(currentSuite, "it() must be called inside describe()")
	table.insert((currentSuite :: Suite).cases, { name = name, fn = fn, id = if options then options.id else nil })
end

local function deepEq(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEq(v, (b :: any)[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if (a :: any)[k] == nil then
			return false
		end
	end
	return true
end

function testkit.expect(value: any)
	local negated = false
	local exp = {}

	local function check(ok: boolean, msg: string)
		if negated then
			ok = not ok
		end
		if not ok then
			error((negated and "[never] " or "") .. msg, 3)
		end
	end

	exp.never = function()
		negated = not negated
		return exp
	end
	exp.toBe = function(expected: any)
		check(value == expected, string.format("expected %s to be %s", tostring(value), tostring(expected)))
		return exp
	end
	exp.toEqual = function(expected: any)
		check(deepEq(value, expected), "tables not equal")
		return exp
	end
	exp.toBeTruthy = function()
		check(value and true or false, string.format("expected %s to be truthy", tostring(value)))
		return exp
	end
	exp.toBeFalsy = function()
		check(not value, string.format("expected %s to be falsy", tostring(value)))
		return exp
	end
	exp.toBeNil = function()
		check(value == nil, string.format("expected %s to be nil", tostring(value)))
		return exp
	end
	exp.toBeCloseTo = function(expected: number, tolerance: number?)
		local tol = tolerance or 1e-4
		check(
			math.abs(value - expected) <= tol,
			string.format("expected %s to be close to %s (±%s)", tostring(value), tostring(expected), tostring(tol))
		)
		return exp
	end
	exp.toBeGreaterThan = function(expected: number)
		check(value > expected, string.format("expected %s to be > %s", tostring(value), tostring(expected)))
		return exp
	end
	exp.toBeGreaterThanOrEqual = function(expected: number)
		check(value >= expected, string.format("expected %s to be >= %s", tostring(value), tostring(expected)))
		return exp
	end
	exp.toBeLessThan = function(expected: number)
		check(value < expected, string.format("expected %s to be < %s", tostring(value), tostring(expected)))
		return exp
	end
	exp.toBeLessThanOrEqual = function(expected: number)
		check(value <= expected, string.format("expected %s to be <= %s", tostring(value), tostring(expected)))
		return exp
	end
	exp.toThrow = function()
		check(not (pcall(value)), "expected function to throw")
		return exp
	end

	return exp
end

function testkit.registeredSpecCount(runnerPath: string): number
	local ok, source = pcall(fs.readFile, runnerPath)
	if not ok or type(source) ~= "string" then
		return 0
	end
	local n = 0
	for line in string.gmatch(source :: string, "[^\n]+") do
		if string.match(line, '^%s*require%("%./([%w_/%.]+)"%)') then
			n += 1
		end
	end
	return n
end

function testkit.run(options: RunOptions?): boolean
	local opts: RunOptions = options or {}
	local passed, failed = 0, 0
	local failures: { string } = {}
	local cases: { any } = {}
	local specsSeen: { [string]: boolean } = {}
	local startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
	local runStart = os.clock()

	for _, suite in suites do
		print("\27[1m" .. suite.name .. "\27[0m")
		specsSeen[suite.spec] = true
		for _, case in suite.cases do
			local caseStart = os.clock()
			local ok, err = pcall(function()
				for _, hook in beforeEachHooks do
					hook()
				end
				case.fn()
			end)

			for _, hook in afterEachHooks do
				local hookOk, hookErr = pcall(hook)
				if not hookOk and ok then
					ok, err = false, hookErr
				end
			end

			local ms = math.floor((os.clock() - caseStart) * 1000000 + 0.5) / 1000
			local record = {
				id = case.id or `{suite.spec}::{suite.name}::{case.name}`,
				suite = suite.name,
				spec = suite.spec,
				name = case.name,
				status = if ok then "pass" else "fail",
				ms = ms,
				error = if ok then nil else tostring(err),
			}
			table.insert(cases, record)
			if ok then
				passed += 1
				print("  \27[32m✓\27[0m " .. case.name)
			else
				failed += 1
				print("  \27[31m✗ " .. case.name .. "\27[0m")
				print("      " .. tostring(err))
				table.insert(failures, suite.name .. " › " .. case.name .. "\n      " .. tostring(err))
			end
		end
	end

	print("")
	if failed == 0 then
		print(string.format("\27[32m%d passed\27[0m", passed))
	else
		print(string.format("\27[31m%d failed\27[0m, \27[32m%d passed\27[0m", failed, passed))
	end

	if opts.jsonOut ~= nil and opts.jsonOut ~= "" then
		local reported = 0
		for _ in specsSeen do
			reported += 1
		end
		local dir = string.match(opts.jsonOut :: string, "^(.*)/[^/]*$")
		if dir ~= nil and dir ~= "" and not fs.isDir(dir) then
			fs.writeDir(dir)
		end
		fs.writeFile(
			opts.jsonOut :: string,
			serde.encode("json", {
				schema = "facet-suite-results/1",
				tier = opts.tier or "full",
				startedAt = startedAt,
				durationMs = math.floor((os.clock() - runStart) * 1000000 + 0.5) / 1000,
				registeredSpecs = opts.registeredSpecs or 0,
				reportedSpecs = reported,
				suites = #suites,
				cases = cases,
				passed = passed,
				failed = failed,
			}, false)
		)
	end

	return failed == 0
end

function testkit.reset()
	suites = {}
	currentSuite = nil
end

return testkit
