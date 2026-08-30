--!strict
-- testkit — a tiny, dependency-free test framework for pure Luau modules.
-- Runs under Lune from the terminal (fast CI loop, no Play Solo needed).
-- Specs register with describe()/it(); tests/run.luau executes the registry.
-- Chosen over TestEZ because TestEZ needs the Roblox runtime; our deterministic
-- modules are plain Luau, so a native Lune runner gives a single-command loop.
-- (See /docs/DECISIONS.md.)

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local testkit = {}

--[[ RESULT IDENTITY (distribution-readiness D7/D8, 2026-08-30).

	Every case carries a STABLE ID — `<spec path under tests/, without the
	.spec suffix>::<describe name>::<it name>` — and `testkit.run{ jsonOut = … }`
	writes the whole run out as structured JSON. That is what the verification
	graph queries: `tools/lune/verify/*` looks a case up by id instead of
	grepping the human transcript for `✓.*<sentence>`, which is how 233 gate rows
	used to spend one cached transcript and how a renamed case used to break a
	gate that had nothing to do with it.

	The spec half of the id is taken from `debug.info` at describe() time rather
	than passed in, because there is exactly one list of specs in this repo (the
	require() calls in tests/run.luau) and a second hand-kept list of names would
	be wrong the first time a file moved. `it(name, fn, { id = "…" })` overrides
	the derived id, so a human name may still improve without moving the id a
	gate row pins.

	THE TRANSCRIPT IS UNCHANGED. The `✓`/`✗` lines and the `N passed` summary are
	byte-for-byte what they were: tools/test.sh re-derives its verdict from them,
	tools/suite_transcript.sh serves them, and several recorded lessons read them.
	The JSON is an ADDITION, written only when a caller asks for it. ]]

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

--[[ Which spec file is calling? `debug.info(level, "s")` returns the chunk's
	source — under Lune an absolute path with the extension already stripped
	(`/…/Facet/tests/layout.spec`). Walk out of testkit until the first frame
	that lives under `tests/`, so a describe() issued from a shared fixture
	helper is still attributed to the spec that pulled the helper in. ]]
local function callerSpec(): string
	for level = 2, 16 do
		local ok, src = pcall(debug.info, level, "s")
		if not ok or src == nil or src == "" then
			break
		end
		local rel = string.match(src, "/tests/(.+)$") or string.match(src, "^tests/(.+)$")
		if rel ~= nil and string.find(rel, "^lib/") == nil then
			-- `tests/layout.spec.luau` -> `layout`; `tests/reference/x_spec.luau`
			-- keeps its name, exactly as tests/lib/tiers.luau lists it.
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

function testkit.it(name: string, fn: () -> (), options: CaseOptions?)
	assert(currentSuite, "it() must be called inside describe()")
	table.insert((currentSuite :: Suite).cases, { name = name, fn = fn, id = if options then options.id else nil })
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

--[[ How many spec modules does a runner register? The require() list in
	tests/run.luau is the single source of truth for which specs exist (see
	tests/lib/tiers.luau), and the structured result records the count so a
	reader can refuse a run that reported fewer specs than were registered —
	the truncated-suite shape, where a main-thread yield ends the run early AND
	STILL EXITS 0.

	Parsed here rather than in the runner so that tests/run.luau's require list
	stays exactly one list of require lines and nothing else. ]]
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
			local ok, err = pcall(case.fn)
			-- ROUNDED, because a raw double here is a hash's problem later: the
			-- structured result is hashed, and a value whose shortest decimal
			-- form does not parse back to the same double makes that hash a coin
			-- toss. Microseconds are more precision than a case timing has.
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
