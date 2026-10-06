--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeApp = require("../bench/native_app")
	local lab = require("../examples/performance/lab/perf_lab")
	local modules = {
		sensory = require("../examples/performance/lab/sensory"),
		dataset = require("../examples/performance/lab/dataset"),
		rows = require("../examples/performance/lab/rows"),
		capture = require("../examples/performance/lab/capture"),
		workloads = require("../examples/performance/lab/workloads"),
	}
	local function fixture()
		local world = nativeApp()
		local probe
		world.heartbeat = world.engine.heartbeat
		world.captureFacts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-09-23T00:00:00Z",
				sourceStamp = "test",
				placeName = "headless",
				viewport = "800x600",
				orientation = "landscape" :: "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune",
				thermalNote = "n/a",
			}
		end
		world.probe = function(value)
			probe = value
		end
		world.runtime.mount(function()
			return world.Host.ScreenGui({ lab.build(world, modules) })
		end, world.target)
		return world, probe
	end

	verifyHarness:suite("native performance lab", function()
		verifyHarness:case("keeps the original dense row controls and keyed edits through virtual eviction", {
			id = "native_perf_lab::native performance lab::keeps the original dense row controls and keyed edits through virtual eviction",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 200)
				local active = probe.state().active
				local item = active.rows:peek()[1]
				local row = active.list:FindFirstChild(tostring(item.id), true)
				Verify.expect(row ~= nil):toBe(true)
				Verify.expect(row:FindFirstChild("Portrait", true).ClassName):toBe("Frame")
				Verify.expect(row:FindFirstChild("Title", true).Text):toBe(item.name)
				Verify.expect(row:FindFirstChild("Detail", true).Text):toBe(item.detail)
				local value = active.rowModels.values[item.id]
				local checked = active.rowModels.toggles[item.id]
				value:set(0.2)
				local previous = checked:peek()
				row:FindFirstChild("Ready", true).Activated.fire()
				row:FindFirstChild("Rate", true):FindFirstChild("Increase", true).Activated.fire()
				Verify.expect((checked:peek())):toBe(not previous)
				Verify.expect((value:peek())):toBe(0.25)
				row:FindFirstChild("Open", true).Activated.fire()
				local close = world.target:FindFirstChild("close", true)
				Verify.expect(close ~= nil):toBe(true)
				local disclosure = world.target:FindFirstChild("AlertContent", true)
				Verify.expect(disclosure:FindFirstChild("Title", true).Text):toBe(item.name)
				Verify.expect(disclosure:FindFirstChild("Message", true).Text):toBe(item.detail)
				close.Activated.fire()
				active.list.CanvasPosition = world.types.Vector2.new(0, 10000)
				active.list.CanvasPosition = world.types.Vector2.zero
				row = active.list:FindFirstChild(tostring(item.id), true)
				Verify.expect(active.rowModels.values[item.id]):toBe(value)
				Verify.expect(active.rowModels.toggles[item.id]):toBe(checked)
				Verify.expect(row:FindFirstChild("Rate", true):FindFirstChild("Value", true).Text):toBe("25%")
				Verify.expect((checked:peek())):toBe(not previous)
				world.dispose()
			end,
		})

		verifyHarness:case("runs bounded row windows and releases the previous workload on selection", {
			id = "native_perf_lab::native performance lab::runs bounded row windows and releases the previous workload on selection",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 20000)
				local previous = probe.state().active.list
				Verify.expect(probe.state().active.status:peek().retained < 30):toBe(true)
				for _ = 1, 12 do
					probe.step(1 / 60)
				end
				Verify.expect(probe.state().active.status:peek().retained < 30):toBe(true)
				probe.select("table-unified", 100)
				Verify.expect((previous.isDestroyed())):toBe(true)
				probe.reset()
				Verify.expect(probe.state().selected):toBe("idle-baseline")
				Verify.expect(probe.state().playing):toBe(false)
				world.dispose()
				Verify.expect((world.engine.heartbeat.count())):toBe(0)
			end,
		})
		verifyHarness:case("keeps the mounted workload when the capture mode or the theme changes", {
			id = "native_perf_lab::native performance lab::keeps the mounted workload when the capture mode or the theme changes",
			run = function()
				local world, probe = fixture()
				world.setTheme = function() end
				probe.select("dense-scroll-native", 300)
				local active = probe.state().active
				for _ = 1, 5 do
					world.engine.heartbeat.fire(1 / 60)
				end
				Verify.expect(probe.state().ready):toBe(true)
				probe.clean(true)
				Verify.expect(probe.state().active):toBe(active)
				Verify.expect(probe.state().ready):toBe(true)
				probe.theme("facet-neutral")
				Verify.expect(probe.state().active):toBe(active)
				probe.step(1 / 60)
				Verify.expect(probe.state().iterations):toBe(1)
				probe.select("dense-scroll-native", 300)
				Verify.expect(probe.state().active ~= active):toBe(true)
				world.dispose()
			end,
		})

		verifyHarness:case("exports conditioned captures and refuses missing or relabelled device facts", {
			id = "native_perf_lab::native performance lab::exports conditioned captures and refuses missing or relabelled device facts",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 100)
				probe.step(1 / 60)
				local row = probe.capture()
				Verify.expect(#modules.capture.problems(row)):toBe(0)
				Verify.expect(row.rows):toBe(100)
				Verify.expect(row.datasetDigest)
					:toBe(modules.dataset.digest(modules.dataset.build({ count = 100, seed = 1 })))
				row.viewport = nil
				Verify.expect(#modules.capture.problems(row) > 0):toBe(true)
				row.evidenceClass = "phone-physical"
				row.studioVersion = "0.732"
				Verify.expect(
					string.find(table.concat(modules.capture.problems(row), ";"), "retail client has none") ~= nil
				)
					:toBe(true)
				world.dispose()
			end,
		})
		verifyHarness:case("sweeps every workload and stops a ramp between iterations", {
			id = "native_perf_lab::native performance lab::sweeps every workload and stops a ramp between iterations",
			run = function()
				local world, probe = fixture()
				probe.select("idle-baseline", 20)
				probe.select("table-unified", 20)
				for _ = 1, 40 do
					probe.step(1 / 60)
				end
				local seen = {}
				for _, row in probe.state().active.rows:peek() do
					Verify.expect(seen[row.id]):toBe(nil)
					seen[row.id] = true
				end
				Verify.expect(#probe.state().active.rows:peek()):toBe(20)
				probe.sweep()
				for _ = 1, #lab.WORKLOADS do
					world.frame()
				end
				Verify.expect(probe.state().queued):toBe(0)
				Verify.expect(probe.state().captures):toBe(#lab.WORKLOADS)
				Verify.expect(probe.state().playing):toBe(false)
				probe.ramp()
				world.frame()
				Verify.expect(probe.state().rows):toBe(100)
				probe.stop()
				world.frame()
				Verify.expect(probe.state().rows):toBe(100)
				Verify.expect(probe.state().queued):toBe(0)
				world.dispose()
			end,
		})
		verifyHarness:case("measures variable row extents and changes only the edited row model", {
			id = "native_perf_lab::native performance lab::measures variable row extents and changes only the edited row model",
			run = function()
				local world, probe = fixture()
				probe.select("variable-extents", 100)
				local before = probe.state().active.status:peek().extent
				probe.step(1 / 60)
				Verify.expect(probe.state().active.status:peek().extent > before):toBe(true)
				probe.select("edit-locality", 100)
				probe.step(1 / 60)
				local edited = 0
				for _, value in probe.state().active.values do
					if value:peek() == "Edited 1" then
						edited += 1
					end
				end
				Verify.expect(edited):toBe(1)
				world.dispose()
			end,
		})
		verifyHarness:case("drives all four native feedback arms and constructs nothing while disabled", {
			id = "native_perf_lab::native performance lab::drives all four native feedback arms and constructs nothing while disabled",
			run = function()
				local world, probe = fixture()
				probe.select("sensory-cascade", 120)
				local active = probe.state().active
				active.step()
				Verify.expect(active.counters.built):toBe(0)
				Verify.expect(active.counters.requests):toBe(0)
				Verify.expect(active.counters.presses):toBe(32)
				active.setEnabled(true)
				active.step()
				Verify.expect(active.counters.built):toBe(121)
				Verify.expect(active.counters.requests):toBe(16)
				for _, arm in active.counters.arms do
					Verify.expect(arm.rows):toBe(120)
					Verify.expect(arm.pressesDriven):toBe(8)
				end
				Verify.expect(active.counters.arms.sharedEffect.effectsBuilt):toBe(1)
				Verify.expect(active.counters.arms.perLeafEffect.effectsBuilt):toBe(120)
				Verify.expect(active.counters.physicalOutputMeasured):toBe(false)
				active.setEnabled(false)
				active.step()
				Verify.expect(active.counters.requests):toBe(0)
				Verify.expect(active.counters.built):toBe(0)
				world.dispose()
			end,
		})
	end)
end
