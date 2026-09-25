--!nocheck
local process = require("@lune/process")
local serde = require("@lune/serde")
local perf_runner = require("../../bench/perf_runner")
local perf_scenes = require("../../bench/perf_scenes")
local perf_profiles = require("../../bench/perf_profiles")

local name = process.args[1]
local scene
for _, candidate in perf_scenes do
	if candidate.name == name then
		scene = candidate
	end
end
if scene == nil then
	print("@@" .. serde.encode("json", { scene = name, status = "missing" }))
	process.exit(0)
end
local profile = perf_profiles.get(perf_profiles.REFERENCE)
local ok, record = pcall(perf_runner.runScene, scene, profile)
if not ok then
	print(
		"@@" .. serde.encode("json", { scene = name, status = "failed", error = string.sub(tostring(record), 1, 300) })
	)
	process.exit(0)
end
local total = record.phases.total
print("@@" .. serde.encode("json", {
	scene = name,
	status = "ok",
	profile = profile.name,
	p50 = total.p50_ms,
	p95 = total.p95_ms,
	p99 = total.p99_ms,
	samples = total.samples,
}))
process.exit(0)
