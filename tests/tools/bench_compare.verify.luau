--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Cli = require("../../tools/facet/lib/cli")
local Command = require("../../tools/facet/commands/bench_compare")
local Files = require("../../tools/facet/lib/files")
local Json = require("../../tools/facet/lib/json")
local Report = require("../../tools/facet/lib/bench_compare_report")
local Run = require("../../tools/facet/lib/run")

return function(harness: Verify.Harness)
	harness:case("comparison ratios use bare and a zero heap has no ratio", function()
		local rows: { Report.Row } = {
			{
				workload = "sample",
				iterations = 20,
				lane = "bare",
				microseconds = 100,
				mountedKb = 0,
				teardownKb = 0,
				writes = 1,
				created = 2,
			},
			{
				workload = "sample",
				iterations = 20,
				lane = "facet",
				microseconds = 250,
				mountedKb = 10,
				teardownKb = 1,
				writes = 3,
				created = 4,
			},
		}
		local markdown = Report.markdown(rows, "revision", {})
		Verify.expect(string.find(markdown, "| sample | 20 | bare | 100.000 | 1.00x | 0.000 | — |", 1, true) ~= nil)
			:toBe(true)
		Verify.expect(string.find(markdown, "| sample | 20 | facet | 250.000 | 2.50x | 10.000 | — |", 1, true) ~= nil)
			:toBe(true)
		Verify.expect(string.find(markdown, "unavailable | unavailable", 1, true) ~= nil):toBe(true)
	end)
	harness:case("comparison rejects unknown options and missing flag values", function()
		for _, arguments in
			{ { "bench", "compare", "--unknown" }, { "bench", "compare", "--filter" }, { "bench", "compare", "extra" } }
		do
			Verify.expect(Command(Cli.parse(arguments, { "filter", "out" }))):toBe(2)
		end
	end)
	harness:case("verify filters parity cases and writes no timing report", function()
		local directory = Files.temporaryDirectory("facet-bare-parity-")
		local result = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"bench",
			"compare",
			"--verify",
			"--filter",
			"main-menu",
			"--out",
			directory,
		})
		Verify.expect(result.code):toBe(0)
		local parity = Json.decode(Files.read(Files.join(directory, "parity.json")))
		Verify.expect(Json.numberField(parity, "passed")):toBe(1)
		Verify.expect(Json.numberField(parity, "total")):toBe(1)
		Verify.expect(Files.isFile(Files.join(directory, "report.json"))):toBe(false)
		Verify.expect(Files.isFile(Files.join(directory, "comparison.md"))):toBe(false)
		Files.remove(directory)
	end)
	harness:case("an empty filter selection fails without measurements", function()
		local directory = Files.temporaryDirectory("facet-bare-empty-")
		local result = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"bench",
			"compare",
			"--filter",
			"no-such-workload",
			"--out",
			directory,
		})
		Verify.expect(result.code):toBe(1)
		Verify.expect(Files.isFile(Files.join(directory, "report.json"))):toBe(false)
		Files.remove(directory)
	end)
end
