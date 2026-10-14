--!strict
local json = require("@std/json")
local process = require("@std/process")
local Loader = require("../tests/lib/loader")

local loader = Loader.new()
local perf_runner = loader.require("bench/perf_runner.luau") :: typeof(require("./perf_runner"))
local perf_scenes = loader.require("bench/perf_scenes.luau") :: typeof(require("./perf_scenes"))
local perf_profiles = loader.require("bench/perf_profiles.luau") :: typeof(require("./perf_profiles"))

local function emit(fields: { [string]: json.Value })
	print("@@" .. json.serialize(fields))
end

local name = process.args[2]
local scene = nil
for _, candidate in perf_scenes do
	if candidate.name == name then
		scene = candidate
	end
end
if scene == nil then
	emit({ scene = name, status = "missing" })
	process.exit(0)
end
local profile = perf_profiles.get(perf_profiles.REFERENCE)
local ok, record = pcall(perf_runner.runScene, scene, profile)
if not ok then
	emit({ scene = name, status = "failed", error = string.sub(tostring(record), 1, 300) })
	process.exit(0)
end
local total = record.phases.total
emit({
	scene = name,
	status = "ok",
	profile = profile.name,
	p50 = total.p50_ms,
	p95 = total.p95_ms,
	p99 = total.p99_ms,
	samples = total.samples,
})
process.exit(0)
