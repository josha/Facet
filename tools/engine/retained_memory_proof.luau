--!strict

local process = require("@std/process")
local Verify = require("../vendor/verify/src/core")
local Lute = require("../vendor/verify/src/lute")
local Paired = require("../facet/lib/perf_paired")
local Retained = require("../facet/lib/perf_retained")
local Json = require("../facet/lib/json")
local Files = require("../facet/lib/files")
local Run = require("../facet/lib/run")

local out = process.args[2] or "artifacts/perf-paired-retained-calibration"
Files.makeDirectory(out)
local harness = Verify.createHarness({ source = "retained-memory-calibration", now = os.clock })
for _, scene in Paired.SCENES do
	harness:case(scene, function(context)
		local reference: { Retained.Reading } = {}
		local unchanged: { Retained.Reading } = {}
		local planted: { Retained.Reading } = {}
		local arms = {
			{ name = "reference", bytes = 0, readings = reference },
			{ name = "unchanged", bytes = 0, readings = unchanged },
			{ name = "retained", bytes = 8 * 1024 * 1024, readings = planted },
		}
		for round = 1, 3 do
			for position = 1, #arms do
				local arm = arms[Paired.armIndex(round, position, #arms)]
				local result = Run.capture(
					{ Run.lute(), "run", "bench/paired_scene.luau", scene, "--memory-only", tostring(arm.bytes) },
					{ timeout = 120 }
				)
				local path = Files.join(out, `{scene}-{round}-{arm.name}`)
				Files.write(path .. ".log", result.stdout .. result.stderr)
				context
					:expect(result.ok)
					:toBeTrueWith(`{scene} {round} {arm.name}: measurement command failed; {path}.log`)
				local row = assert(Paired.sceneRow(result.stdout), "the memory measurement returned no scene row")
				Files.write(path .. ".json", Json.pretty(row))
				context:expect(Json.field(row, "status")):toBe("ok")
				local reading, problem = Retained.read(Json.field(row, "memory"))
				local measured = assert(reading, problem)
				table.insert(arm.readings, measured)
			end
		end
		local same = Retained.compare(reference, unchanged)
		local leaked = Retained.compare(reference, planted)
		context:attach(scene .. "-unchanged.json", "application/json", Json.encode(same))
		context:attach(scene .. "-planted.json", "application/json", Json.encode(leaked))
		for _, compared in same do
			context
				:expect(not compared.regressed)
				:toBeTrueWith(`{scene} {compared.metric}: unchanged arms must not flag growth`)
		end
		for _, compared in leaked do
			context
				:expect(compared.regressed)
				:toBeTrueWith(`{scene} {compared.metric}: a retained 8 MiB buffer must flag growth`)
		end
	end)
end
local report = harness:run({ executor = "lute", environment = { proof = "unchanged-and-retained-8MiB", rounds = "3" } })
print(Verify.format(report))
Lute.gate.writeReport(Files.join(out, "report.json"), `retained-memory-{os.time()}`, report)
if report.total ~= #Paired.SCENES or report.passed ~= report.total then
	process.exit(1)
end
