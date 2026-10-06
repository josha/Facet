--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Verify = require("../vendor/verify/src/core")
local runner = require("../../tests/runner")
local harness = Verify.createHarness({ source = "facet-verify-integration", now = os.clock })
local directory = "artifacts/verify/integration"
fs.writeDir(directory)

local function fixture(name: string, source: string)
	fs.writeFile(`{directory}/{name}.luau`, source)
	return Verify.validatePlan({
		id = name,
		policy = { caseIdStyle = "bare" },
		units = { { id = name, locator = `{directory}/{name}.luau` } },
	})
end

harness:suite("Verify cutover boundaries", function()
	harness:case("accounts for load, registration and empty-source failures", function(context)
		local missing = Verify.validatePlan({
			id = "missing",
			units = { { id = "missing", locator = `{directory}/missing.luau` } },
		})
		local broken = fixture("broken", 'error("broken source")')
		local registration = fixture("registration", 'return function() error("broken registration") end')
		local empty = fixture("empty", "return function() end")
		fs.writeFile(directory .. "/broken-plan.json", serde.encode("json", broken, true))
		local brokenResult = process.exec("lune", {
			"run",
			"tools/lune/verify_plan",
			directory .. "/broken-plan.json",
			"full",
			directory .. "/broken-report.json",
		})
		context:expect(brokenResult.code):toBe(1)
		local brokenReceipt = serde.decode("json", fs.readFile(directory .. "/broken-report.json"))
		context:expect(Verify.decode(brokenReceipt.report).failed):toBe(1)
		for _, plan in { missing, registration, empty } do
			local execution = runner.execute(plan, "full", nil)
			context:expect(runner.accept(execution, "full")):toBe(false)
			context:expect(execution.report.failed):toBeGreaterThan(0)
		end
	end)
	harness:case("preserves case and cleanup failures independently", function(context)
		local plan = fixture(
			"cleanup",
			'return function(h) h:case("fails", { id="fails", run=function(c) c:defer(function() error("cleanup failure") end) error("body failure") end }) end'
		)
		local execution = runner.execute(plan, "full", nil)
		local result = execution.report.results[1]
		context:expect(result.status):toBe("failed")
		context:expect(#result.failures):toBe(2)
		context:expect(result.failures[1].phase):toBe("case")
		context:expect(result.failures[2].phase):toBe("cleanup")
	end)
	harness:case("rejects duplicate IDs and unapproved skips", function(context)
		local duplicate = fixture(
			"duplicate",
			'return function(h) h:case("one",{id="same",run=function() end}) h:case("two",{id="same",run=function() end}) end'
		)
		local skipped = fixture("skipped", 'return function(h) h:skip("absent", "no setup") end')
		for _, plan in { duplicate, skipped } do
			context:expect(runner.accept(runner.execute(plan, "full", nil), "full")):toBe(false)
		end
	end)
	harness:case("keeps the release-only case out of lower tiers", function(context)
		local plan = fixture(
			"release",
			'return function(h,tier) h:case("ramp",{id="ramp",run=function(c) if tier ~= "release" then c:skip("tier:release") end c:expect(true):toBe(true) end}) end'
		)
		local lower = runner.execute(plan, "full", nil)
		local release = runner.execute(plan, "release", nil)
		context:expect(lower.report.skipped):toBe(1)
		context:expect(release.report.passed):toBe(1)
		context:expect(runner.accept(lower, "full")):toBe(true)
		context:expect(runner.accept(release, "release")):toBe(true)
		context:expect(runner.accept(lower, "release")):toBe(false)
	end)
	harness:case("rejects malformed reports and conflicting transport segments", function(context)
		context
			:expect(function()
				Verify.decode({})
			end)
			:toThrow()
		local pieces = Verify.segment("a report payload", 4)
		local whole = Verify.reassembleSegments(pieces)
		context:expect(whole):toBe("a report payload")
		local changed = table.clone(pieces)
		changed[1] = table.clone(changed[1])
		changed[1].payload = "bad bytes"
		context:expect((Verify.reassembleSegments(changed))):toBeNil()
		local absent = table.clone(pieces)
		table.remove(absent)
		context:expect((Verify.reassembleSegments(absent))):toBeNil()
	end)
	harness:case("the command host accounts for pass, failure and missing live capability", function(context)
		local input = `{directory}/commands.json`
		local output = `{directory}/commands-report.json`
		fs.writeFile(
			input,
			serde.encode("json", {
				tier = "full",
				producers = {
					{
						id = "pass",
						command = { "python3", "-c", "pass" },
						environment = "deterministic",
						replaces = {},
					},
					{
						id = "failure",
						command = { "python3", "-c", "raise SystemExit(1)" },
						environment = "deterministic",
						replaces = {},
					},
					{
						id = "live",
						command = { "python3", "-c", "raise SystemExit(2)" },
						environment = "studio",
						replaces = {},
					},
				},
			}, true)
		)
		local result = process.exec("lune", { "run", "tools/lune/verify_producers", input, output })
		context:expect(result.code):toBe(0)
		local receipt = serde.decode("json", fs.readFile(output))
		local report = Verify.decode(receipt.execution.report)
		context:expect(receipt.execution.provenance.complete):toBe(true)
		context:expect(report.total):toBe(3)
		context:expect(report.passed):toBe(1)
		context:expect(report.failed):toBe(1)
		context:expect(report.skipped):toBe(1)
	end)
end)
local report = harness:run({ executor = "facet-lune", environment = { tier = "full" } })
print(Verify.format(report))
fs.writeFile(`{directory}/selftest.json`, serde.encode("json", report, true))
if report.total == 0 or report.passed ~= report.total then
	process.exit(1)
end
