--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local rules = require("../../tools/facet/checks")
local Rule = require("../../tools/facet/lib/rule")
local Files = require("../../tools/facet/lib/files")
local Run = require("../../tools/facet/lib/run")
local Json = require("../../tools/facet/lib/json")

return function(harness: Verify.Harness)
	harness:case("Verify cleans a rule fixture after an assertion fails", {
		id = "tools/rules::fixtures::failed assertion cleanup",
		run = function()
			local root = ""
			local inner = Verify.createHarness({ now = os.clock })
			inner:case("planted assertion", {
				id = "planted assertion",
				run = function(test)
					local fixture = Rule.fixture(test, { ["src/probe.luau"] = "return {}" })
					root = fixture.root
					Verify.expect(Files.isFile(fixture.path("src/probe.luau"))):toBe(true)
					Verify.expect("actual"):toBe("planted failure")
				end,
			})
			local report = inner:run({ executor = "rule-fixture-regression" })
			Verify.expect(report.failed):toBe(1)
			Verify.expect(report.results[1].id):toBe("planted assertion")
			Verify.expect(report.results[1].failures[1].phase):toBe("case")
			Verify.expect(report.results[1].failures[1].message):toContain("planted failure")
			Verify.expect(root ~= ""):toBe(true)
			Verify.expect(Files.exists(root)):toBe(false)
		end,
	})
	harness:case("CLI selftests select the registered Verify cases and reject an empty selection", {
		id = "tools/rules::cli::registered selection",
		tags = { "tier:full" },
		run = function()
			local selected = Run.capture({ Run.lute(), "run", "tools/facet", "check", "source-size", "--selftest" })
			Verify.expect(selected.ok):toBeTrueWith(selected.stdout .. selected.stderr)
			local outcome = Json.decode(Files.read("artifacts/verify/native/gate-selftests/latest.json")) :: {
				execution: { report: Verify.Report },
			}
			local ids: { string } = {}
			for _, result in outcome.execution.report.results do
				if result.status == "passed" and string.sub(result.id, 1, 26) == "tools/rules::source-size::" then
					table.insert(ids, result.id)
				end
			end
			table.sort(ids)
			Verify.expect(ids):toEqual({
				"tools/rules::source-size::a source one character under the limit passes and one at the limit fails",
				"tools/rules::source-size::characters are code points and CRLF counts as one line break",
				"tools/rules::source-size::invalid UTF-8 is a finding",
			})
			local empty = Run.capture({ Run.lute(), "run", "tools/facet", "perf", "baseline", "--selftest" })
			Verify.expect(empty.ok):toBe(false)
			Verify.expect(empty.stdout):toContain("selected case(s) were not found")
		end,
	})
	for _, rule in rules do
		harness:suite(rule.name, function()
			harness:case("declares selftest cases", {
				id = "tools/rules::" .. rule.name .. "::declares selftest cases",
				run = function()
					local registrations = Verify.createHarness({ now = os.clock })
					rule.register(registrations, "registration-probe::")
					local report = registrations:run({
						executor = "registration-probe",
						selection = {
							account = true,
							predicate = function()
								return false
							end,
						},
					})
					Verify.expect(report.total > 0):toBe(true)
				end,
			})
			rule.register(harness, "tools/rules::" .. rule.name .. "::")
		end)
	end
end
