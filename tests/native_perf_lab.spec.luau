--!strict
local t = require("./lib/testkit")
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
			orientation = "landscape",
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

t.describe("native performance lab", function()
	t.it("keeps the original dense row controls and keyed edits through virtual eviction", function()
		local world, probe = fixture()
		probe.select("dense-scroll", 200)
		local active = probe.state().active
		local item = active.rows:peek()[1]
		local row = active.list:FindFirstChild(tostring(item.id), true)
		t.expect(row ~= nil).toBe(true)
		t.expect(row:FindFirstChild("Portrait", true).ClassName).toBe("Frame")
		t.expect(row:FindFirstChild("Title", true).Text).toBe(item.name)
		t.expect(row:FindFirstChild("Detail", true).Text).toBe(item.detail)
		local value = active.rowModels.values[item.id]
		local checked = active.rowModels.toggles[item.id]
		value:set(0.2)
		local previous = checked:peek()
		row:FindFirstChild("Ready", true).Activated.fire()
		row:FindFirstChild("Rate", true):FindFirstChild("Increase", true).Activated.fire()
		t.expect(checked:peek()).toBe(not previous)
		t.expect(value:peek()).toBe(0.25)
		row:FindFirstChild("Open", true).Activated.fire()
		local close = world.target:FindFirstChild("close", true)
		t.expect(close ~= nil).toBe(true)
		local disclosure = world.target:FindFirstChild("AlertContent", true)
		t.expect(disclosure:FindFirstChild("Title", true).Text).toBe(item.name)
		t.expect(disclosure:FindFirstChild("Message", true).Text).toBe(item.detail)
		close.Activated.fire()
		active.list.CanvasPosition = world.types.Vector2.new(0, 10000)
		active.list.CanvasPosition = world.types.Vector2.zero
		row = active.list:FindFirstChild(tostring(item.id), true)
		t.expect(active.rowModels.values[item.id]).toBe(value)
		t.expect(active.rowModels.toggles[item.id]).toBe(checked)
		t.expect(row:FindFirstChild("Rate", true):FindFirstChild("Value", true).Text).toBe("25%")
		t.expect(checked:peek()).toBe(not previous)
		world.dispose()
	end)

	t.it("runs bounded row windows and releases the previous workload on selection", function()
		local world, probe = fixture()
		probe.select("dense-scroll", 20000)
		local previous = probe.state().active.list
		t.expect(probe.state().active.status:peek().retained < 30).toBe(true)
		for _ = 1, 12 do
			probe.step(1 / 60)
		end
		t.expect(probe.state().active.status:peek().retained < 30).toBe(true)
		probe.select("table-unified", 100)
		t.expect(previous.isDestroyed()).toBe(true)
		probe.reset()
		t.expect(probe.state().selected).toBe("idle-baseline")
		t.expect(probe.state().playing).toBe(false)
		world.dispose()
		t.expect(world.engine.heartbeat.count()).toBe(0)
	end)
	t.it("keeps the mounted workload when the capture mode or the theme changes", function()
		local world, probe = fixture()
		world.setTheme = function() end
		probe.select("dense-scroll-native", 300)
		local active = probe.state().active
		for _ = 1, 5 do
			world.engine.heartbeat.fire(1 / 60)
		end
		t.expect(probe.state().ready).toBe(true)
		probe.clean(true)
		t.expect(probe.state().active).toBe(active)
		t.expect(probe.state().ready).toBe(true)
		probe.theme("facet-neutral")
		t.expect(probe.state().active).toBe(active)
		probe.step(1 / 60)
		t.expect(probe.state().iterations).toBe(1)
		probe.select("dense-scroll-native", 300)
		t.expect(probe.state().active ~= active).toBe(true)
		world.dispose()
	end)

	t.it("exports conditioned captures and refuses missing or relabelled device facts", function()
		local world, probe = fixture()
		probe.select("dense-scroll", 100)
		probe.step(1 / 60)
		local row = probe.capture()
		t.expect(#modules.capture.problems(row)).toBe(0)
		t.expect(row.rows).toBe(100)
		t.expect(row.datasetDigest).toBe(modules.dataset.digest(modules.dataset.build({ count = 100, seed = 1 })))
		row.viewport = nil
		t.expect(#modules.capture.problems(row) > 0).toBe(true)
		row.evidenceClass = "phone-physical"
		row.studioVersion = "0.732"
		t.expect(string.find(table.concat(modules.capture.problems(row), ";"), "retail client has none") ~= nil)
			.toBe(true)
		world.dispose()
	end)
	t.it("sweeps every workload and stops a ramp between iterations", function()
		local world, probe = fixture()
		probe.select("idle-baseline", 20)
		probe.select("table-unified", 20)
		for _ = 1, 40 do
			probe.step(1 / 60)
		end
		local seen = {}
		for _, row in probe.state().active.rows:peek() do
			t.expect(seen[row.id]).toBe(nil)
			seen[row.id] = true
		end
		t.expect(#probe.state().active.rows:peek()).toBe(20)
		probe.sweep()
		for _ = 1, #lab.WORKLOADS do
			world.frame()
		end
		t.expect(probe.state().queued).toBe(0)
		t.expect(probe.state().captures).toBe(#lab.WORKLOADS)
		t.expect(probe.state().playing).toBe(false)
		probe.ramp()
		world.frame()
		t.expect(probe.state().rows).toBe(100)
		probe.stop()
		world.frame()
		t.expect(probe.state().rows).toBe(100)
		t.expect(probe.state().queued).toBe(0)
		world.dispose()
	end)
	t.it("measures variable row extents and changes only the edited row model", function()
		local world, probe = fixture()
		probe.select("variable-extents", 100)
		local before = probe.state().active.status:peek().extent
		probe.step(1 / 60)
		t.expect(probe.state().active.status:peek().extent > before).toBe(true)
		probe.select("edit-locality", 100)
		probe.step(1 / 60)
		local edited = 0
		for _, value in probe.state().active.values do
			if value:peek() == "Edited 1" then
				edited += 1
			end
		end
		t.expect(edited).toBe(1)
		world.dispose()
	end)
	t.it("drives all four native feedback arms and constructs nothing while disabled", function()
		local world, probe = fixture()
		probe.select("sensory-cascade", 120)
		local active = probe.state().active
		active.step()
		t.expect(active.counters.built).toBe(0)
		t.expect(active.counters.requests).toBe(0)
		t.expect(active.counters.presses).toBe(32)
		active.setEnabled(true)
		active.step()
		t.expect(active.counters.built).toBe(121)
		t.expect(active.counters.requests).toBe(16)
		for _, arm in active.counters.arms do
			t.expect(arm.rows).toBe(120)
			t.expect(arm.pressesDriven).toBe(8)
		end
		t.expect(active.counters.arms.sharedEffect.effectsBuilt).toBe(1)
		t.expect(active.counters.arms.perLeafEffect.effectsBuilt).toBe(120)
		t.expect(active.counters.physicalOutputMeasured).toBe(false)
		active.setEnabled(false)
		active.step()
		t.expect(active.counters.requests).toBe(0)
		t.expect(active.counters.built).toBe(0)
		world.dispose()
	end)
end)
