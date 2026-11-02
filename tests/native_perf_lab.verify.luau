--!strict
local NativeEngine = require("./lib/native_engine")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
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
		local hapticCalls: { [string]: number } = {}
		local hapticCapture = world.engine.environment.onCreate(function(effect)
			if effect:IsA("HapticEffect") then
				for _, method in { "Play", "Stop" } do
					world.engine.environment.fakeOn(effect, method, function()
						hapticCalls[method] = (hapticCalls[method] or 0) + 1
					end)
				end
			end
		end)
		world.hapticCalls = hapticCalls
		local dispose = world.dispose
		world.dispose = function()
			hapticCapture:Disconnect()
			dispose()
		end
		local probe: lab.Probe? = nil
		world.heartbeat = world.engine.heartbeat
		world.captureFacts = function()
			return {
				evidenceClass = "lute",
				capturedAtIso = "2026-09-23T00:00:00Z",
				sourceStamp = "test",
				placeName = "headless",
				viewport = "800x600",
				orientation = "landscape" :: "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lute",
				thermalNote = "n/a",
			}
		end
		world.probe = function(value: lab.Probe): ()
			probe = value
		end
		world.runtime.mount(function()
			return world.Host.ScreenGui { lab.build(world, modules) }
		end, world.target)
		return world, assert(probe)
	end

	describe("native performance lab", function()
		it("keeps the original dense row controls and keyed edits through virtual eviction", {
			id = "native_perf_lab::native performance lab::keeps the original dense row controls and keyed edits through virtual eviction",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 200)
				local active = assert(probe.state().active)
				local item = active.rows:peek()[1]
				local row = active.list:FindFirstChild(tostring(item.id), true)
				expect(row ~= nil):toBe(true)
				expect(row:FindFirstChild("Portrait", true).ClassName):toBe("Frame")
				expect(row:FindFirstChild("Title", true).Text):toBe(item.name)
				expect(row:FindFirstChild("Detail", true).Text):toBe(item.detail)
				local value = active.rowModels.values[item.id]
				local checked = active.rowModels.toggles[item.id]
				value:set(0.2)
				local previous = checked:peek()
				row:FindFirstChild("Ready", true).Activated:Fire()
				row:FindFirstChild("Rate", true):FindFirstChild("Increase", true).Activated:Fire()
				expect((checked:peek())):toBe(not previous)
				expect((value:peek())):toBe(0.25)
				row:FindFirstChild("Open", true).Activated:Fire()
				local close = world.target:FindFirstChild("close", true)
				expect(close ~= nil):toBe(true)
				local disclosure = world.target:FindFirstChild("AlertContent", true)
				expect(disclosure:FindFirstChild("Title", true).Text):toBe(item.name)
				expect(disclosure:FindFirstChild("Message", true).Text):toBe(item.detail)
				close.Activated:Fire()
				active.list.CanvasPosition = world.types.Vector2.new(0, 10000)
				active.list.CanvasPosition = world.types.Vector2.zero
				row = active.list:FindFirstChild(tostring(item.id), true)
				expect(active.rowModels.values[item.id]):toBe(value)
				expect(active.rowModels.toggles[item.id]):toBe(checked)
				expect(row:FindFirstChild("Rate", true):FindFirstChild("Value", true).Text):toBe("25%")
				expect((checked:peek())):toBe(not previous)
				world.dispose()
			end,
		})

		it("runs bounded row windows and releases the previous workload on selection", {
			id = "native_perf_lab::native performance lab::runs bounded row windows and releases the previous workload on selection",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 20000)
				local previous = assert(probe.state().active).list
				expect(assert(probe.state().active).status:peek().retained < 30):toBe(true)
				for _ = 1, 12 do
					probe.step(1 / 60)
				end
				expect(assert(probe.state().active).status:peek().retained < 30):toBe(true)
				probe.select("table-unified", 100)
				expect((previous:isDestroyed())):toBe(true)
				probe.reset()
				expect(probe.state().selected):toBe("idle-baseline")
				expect(probe.state().playing):toBe(false)
				world.dispose()
				expect((NativeEngine.connections(world.engine.heartbeat))):toBe(0)
			end,
		})
		it("keeps the mounted workload when the capture mode or the theme changes", {
			id = "native_perf_lab::native performance lab::keeps the mounted workload when the capture mode or the theme changes",
			run = function()
				local world, probe = fixture()
				world.setTheme = function() end
				probe.select("dense-scroll-native", 300)
				local active = assert(probe.state().active)
				for _ = 1, 5 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				expect(probe.state().ready):toBe(true)
				probe.clean(true)
				expect(probe.state().active):toBe(active)
				expect(probe.state().ready):toBe(true)
				probe.theme("facet-neutral")
				expect(probe.state().active):toBe(active)
				probe.step(1 / 60)
				expect(probe.state().iterations):toBe(1)
				probe.select("dense-scroll-native", 300)
				expect(probe.state().active ~= active):toBe(true)
				world.dispose()
			end,
		})

		it("exports conditioned captures and refuses missing or relabelled device facts", {
			id = "native_perf_lab::native performance lab::exports conditioned captures and refuses missing or relabelled device facts",
			run = function()
				local world, probe = fixture()
				probe.select("dense-scroll", 100)
				probe.step(1 / 60)
				local row = probe.capture()
				expect(#modules.capture.problems(row)):toBe(0)
				expect(row.rows):toBe(100)
				expect(row.datasetDigest):toBe(modules.dataset.digest(modules.dataset.build({ count = 100, seed = 1 })))
				row.viewport = nil
				expect(#modules.capture.problems(row) > 0):toBe(true)
				row.evidenceClass = "phone-physical"
				row.studioVersion = "0.732"
				expect(string.find(table.concat(modules.capture.problems(row), ";"), "retail client has none") ~= nil):toBe(
					true
				)
				world.dispose()
			end,
		})
		it("sweeps every workload and stops a ramp between iterations", {
			id = "native_perf_lab::native performance lab::sweeps every workload and stops a ramp between iterations",
			run = function()
				local world, probe = fixture()
				probe.select("idle-baseline", 20)
				probe.select("table-unified", 20)
				for _ = 1, 40 do
					probe.step(1 / 60)
				end
				local seen = {}
				for _, row in assert(probe.state().active).rows:peek() do
					expect(seen[row.id]):toBe(nil)
					seen[row.id] = true
				end
				expect(#assert(probe.state().active).rows:peek()):toBe(20)
				probe.sweep()
				for _ = 1, #lab.WORKLOADS do
					world.frame()
				end
				expect(probe.state().queued):toBe(0)
				expect(probe.state().captures):toBe(#lab.WORKLOADS)
				expect(probe.state().playing):toBe(false)
				probe.ramp()
				world.frame()
				expect(probe.state().rows):toBe(100)
				probe.stop()
				world.frame()
				expect(probe.state().rows):toBe(100)
				expect(probe.state().queued):toBe(0)
				world.dispose()
			end,
		})
		it("measures variable row extents and changes only the edited row model", {
			id = "native_perf_lab::native performance lab::measures variable row extents and changes only the edited row model",
			run = function()
				local world, probe = fixture()
				probe.select("variable-extents", 100)
				local before = assert(probe.state().active).status:peek().extent
				probe.step(1 / 60)
				expect(assert(probe.state().active).status:peek().extent > before):toBe(true)
				probe.select("edit-locality", 100)
				probe.step(1 / 60)
				local edited = 0
				for _, value in assert(probe.state().active).values do
					if value:peek() == "Edited 1" then
						edited += 1
					end
				end
				expect(edited):toBe(1)
				world.dispose()
			end,
		})
		it("drives all four native feedback arms and constructs nothing while disabled", {
			id = "native_perf_lab::native performance lab::drives all four native feedback arms and constructs nothing while disabled",
			run = function()
				local world, probe = fixture()
				probe.select("sensory-cascade", 120)
				local active = assert(probe.state().active)
				active.step()
				expect(active.counters.built):toBe(0)
				expect(active.counters.requests):toBe(0)
				expect(active.counters.presses):toBe(32)
				active.setEnabled(true)
				active.step()
				expect(active.counters.built):toBe(121)
				expect(active.counters.requests):toBe(16)
				expect(world.hapticCalls.Play):toBe(16)
				expect(world.hapticCalls.Stop):toBe(121)
				for _, arm in active.counters.arms do
					expect(arm.rows):toBe(120)
					expect(arm.pressesDriven):toBe(8)
				end
				expect(active.counters.arms.sharedEffect.effectsBuilt):toBe(1)
				expect(active.counters.arms.perLeafEffect.effectsBuilt):toBe(120)
				expect(active.counters.physicalOutputMeasured):toBe(false)
				active.setEnabled(false)
				active.step()
				expect(active.counters.requests):toBe(0)
				expect(active.counters.built):toBe(0)
				world.dispose()
			end,
		})
	end)
end
