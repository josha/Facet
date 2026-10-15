--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Roblox = require("../src/vendor/compose/roblox")
local Hud = require("../src/ui/hud_types")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("timer ticks at displayed seconds retargets and releases its clock", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime((native :: unknown) :: Roblox.Engine)
		local C = Facet.Compose
		local deadline = C.cell(103.25)
		local at, calls, writes, refs = 100, 0, 0, 0
		local controls: Hud.TimerControls = {}
		local label: TextLabel
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types })
			label = UI.Timer "Round" {
				ref = function()
					refs += 1
				end,
				deadline = deadline,
				now = function()
					return at
				end,
				controls = controls,
				onComplete = function()
					calls += 1
				end,
			}
			return label
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local completed = assert(controls.completed)
		t:expect(refs):toBe(1)
		native.onWrite(function(object, key)
			if object == label and key == "Text" then
				writes += 1
			end
		end)
		local function step(seconds: number)
			at += seconds
			native.heartbeat:Fire(seconds)
		end
		t:expect(label.Text):toBe("0:04")
		step(0.2)
		t:expect(writes):toBe(0)
		step(0.05)
		t:expect(label.Text):toBe("0:03")
		t:expect(writes):toBe(1)
		step(0.5)
		t:expect(writes):toBe(1)
		deadline:set(at + 2)
		t:expect(label.Text):toBe("0:02")
		step(1)
		t:expect(label.Text):toBe("0:01")
		step(1)
		t:expect(label.Text):toBe("0:00")
		t:expect(completed:peek()):toBe(true)
		t:expect(calls):toBe(1)
		step(10)
		t:expect(calls):toBe(1)
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
		deadline:set(at + 5)
		t:expect(completed:peek()):toBe(false)
		step(5)
		t:expect(calls):toBe(2)
		deadline:set(at + 10)
		stop()
		t:expect(controls.completed):toBe(nil)
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
		step(20)
		t:expect(calls):toBe(2)
	end)
	harness:case("elapsed timer uses the runtime clock and supports future starts", function(t)
		local native = engineLib.new()
		local now = 0
		native.clock = function(): number
			return now
		end
		local runtime = Facet.Roblox.createRuntime((native :: unknown) :: Roblox.Engine)
		local start = Facet.Compose.cell(native.clock() + 1)
		local label: TextLabel
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types })
			label = UI.Timer "Elapsed" { start = start, hours = true }
			return label
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		t:expect(label.Text):toBe("0:00:00")
		now = 2
		native.heartbeat:Fire(2)
		t:expect(label.Text):toBe("0:00:01")
		start:set(native.clock() - 3600)
		t:expect(label.Text):toBe("1:00:00")
	end)
end
