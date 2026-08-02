--!strict
-- testkit — a tiny, dependency-free test framework for pure Luau modules.
-- Runs under Lune from the terminal (fast CI loop, no Play Solo needed).
-- Specs register with describe()/it(); tests/run.luau executes the registry.
-- Chosen over TestEZ because TestEZ needs the Roblox runtime; our deterministic
-- modules are plain Luau, so a native Lune runner gives a single-command loop.
-- (See /docs/DECISIONS.md.)

local testkit = {}

type Case = { name: string, fn: () -> () }
type Suite = { name: string, cases: { Case } }

local suites: { Suite } = {}
local currentSuite: Suite? = nil

function testkit.describe(name: string, body: () -> ())
	local suite: Suite = { name = name, cases = {} }
	table.insert(suites, suite)
	local prev = currentSuite
	currentSuite = suite
	body()
	currentSuite = prev
end

function testkit.it(name: string, fn: () -> ())
	assert(currentSuite, "it() must be called inside describe()")
	table.insert((currentSuite :: Suite).cases, { name = name, fn = fn })
end

-- ---- assertions --------------------------------------------------------------
-- Fluent, dot-call API: expect(x).toBe(y), expect(x).never().toBe(y).
-- Each expect() returns a fresh table of closures bound to `value`, so dot
-- calls work (a metatable/colon approach would mis-bind `self`).

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

-- ---- runner ------------------------------------------------------------------

function testkit.run(): boolean
	local passed, failed = 0, 0
	local failures: { string } = {}

	for _, suite in suites do
		print("\27[1m" .. suite.name .. "\27[0m")
		for _, case in suite.cases do
			local ok, err = pcall(case.fn)
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
	return failed == 0
end

function testkit.reset()
	suites = {}
	currentSuite = nil
end

return testkit
