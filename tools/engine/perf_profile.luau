--!strict

local process = require("@std/process")
local Loader = require("../../tests/lib/loader")

local loader = Loader.new()
local runner = loader.require("bench/perf_runner.luau") :: typeof(require("../../bench/perf_runner"))
local scenes = loader.require("bench/perf_scenes.luau") :: typeof(require("../../bench/perf_scenes"))
local profiles = loader.require("bench/perf_profiles.luau") :: typeof(require("../../bench/perf_profiles"))

local name = assert(process.args[2], "expected a scene name")
for _, scene in scenes do
	if scene.name == name then
		local result = runner.runScene(scene, profiles.get(profiles.REFERENCE))
		print(result.phases.total.p95_ms)
		return
	end
end
error(`unknown scene {name}`)
