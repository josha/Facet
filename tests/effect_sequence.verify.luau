--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local EffectTypes = require("../src/ui/effect_types")
local Shared = require("../src/ui/types")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	harness:case("sequence orders delays and parallel samples and retargets count-up", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local sequence: EffectTypes.Sequence
		local count: Facet.Readable<number>
		local score = C.cell(0)
		local reduced = C.cell("normal" :: Shared.MotionLevel)
		local events: { string } = {}
		local first, second, finished = 0, 0, 0
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, motionLevel = reduced })
			count = UI.countUp(score)
			sequence = UI.sequence {
				steps = {
					{
						onStart = function()
							table.insert(events, "lock1")
						end,
					},
					{
						delay = "travelStagger",
						onStart = function()
							table.insert(events, "lock2")
						end,
					},
					{
						parallel = {
							{
								duration = "sequence",
								sample = function(p)
									first = p
								end,
								onEnd = function()
									table.insert(events, "sweep")
								end,
							},
							{
								duration = "travelFade",
								sample = function(p)
									second = p
								end,
								onEnd = function()
									table.insert(events, "flash")
								end,
							},
						},
						onEnd = function()
							table.insert(events, "parallel")
						end,
					},
					{
						duration = "countUp",
						onStart = function()
							score:set(24)
							table.insert(events, "count")
						end,
					},
					{
						delay = "travelStagger",
						onEnd = function()
							table.insert(events, "refill")
						end,
					},
				},
				onCompleted = function()
					finished += 1
				end,
			}
			return Host.Frame {}
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		sequence.play()
		t:expect(events[1]):toBe("lock1")
		t:expect(events[2]):toBe(nil)
		local previousFirst, previousSecond, previousCount = 0, 0, 0
		for _ = 1, 100 do
			native.heartbeat:Fire(1 / 120)
			t:expect(first >= previousFirst and second >= previousSecond):toBe(true)
			t:expect(count:peek() >= previousCount and count:peek() <= 24):toBe(true)
			previousFirst, previousSecond, previousCount = first, second, count:peek()
		end
		t:expect(table.concat(events, ",")):toBe("lock1,lock2,flash,sweep,parallel,count,refill")
		t:expect(count:peek()):toBe(24)
		t:expect(first == 1 and second == 1 and sequence.completed:peek()):toBe(true)
		t:expect(finished):toBe(1)
		score:set(100)
		native.heartbeat:Fire(0.05)
		local current = count:peek()
		score:set(50)
		t:expect(count:peek()):toBe(current)
		for _ = 1, 60 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(count:peek()):toBe(50)
		table.clear(events)
		sequence.play()
		native.heartbeat:Fire(0.02)
		sequence.cancel()
		for _ = 1, 100 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(table.concat(events, ",")):toBe("lock1")
		t:expect(sequence.completed:peek()):toBe(false)
		sequence.play()
		native.heartbeat:Fire(0.02)
		sequence.play()
		sequence.finish()
		t:expect(finished):toBe(2)
		reduced:set("none")
		table.clear(events)
		sequence.play()
		t:expect(sequence.completed:peek() and not sequence.running:peek()):toBe(true)
		t:expect(events[#events]):toBe("refill")
		t:expect(count:peek()):toBe(24)
		t:expect(finished):toBe(3)
		reduced:set("normal")
		sequence.play()
		native.heartbeat:Fire(0.02)
		local heldEvents = #events
		stop()
		for _ = 1, 100 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
		t:expect(#events):toBe(heldEvents)
		t:expect(finished):toBe(3)
	end)

	harness:case("flash samples native overlay bounds without changing target paint", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(native)
		local C = Facet.Compose
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, target = native.new("ScreenGui"), native.new("Frame")
		screen.Parent = native.new("Folder")
		target.Parent = screen
		target.AbsolutePosition = native.types.Vector2.new(80, 40)
		target.AbsoluteSize = native.types.Vector2.new(200, 60)
		local progress = C.cell(0)
		local reduced = C.cell("normal" :: Shared.MotionLevel)
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen, motionLevel = reduced })
			return Host.Frame { UI.Flash { target = target, progress = progress, mode = "sweep" :: "sweep" } }
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local paint: Frame? = nil
		for _, node in native.made do
			if node.Name == "FlashPaint" then
				paint = node :: Frame
			end
		end
		local flash = assert(paint)
		local count = #native.made
		local color, transparency = target.BackgroundColor3, target.BackgroundTransparency
		for frame = 0, 60 do
			local p = frame / 60
			progress:set(p)
			t:expect(math.abs(flash.Size.X.Offset - 200 * p) <= 1):toBe(true)
			t:expect(flash.Position.X.Offset):toBe(80)
			t:expect(flash.Visible):toBe(frame > 0 and frame < 60)
			t:expect(math.abs(flash.BackgroundTransparency - (1 - 4 * p * (1 - p))) < 0.001):toBe(true)
		end
		t:expect(target.BackgroundColor3):toBe(color)
		t:expect(target.BackgroundTransparency):toBe(transparency)
		t:expect(#native.made):toBe(count)
		reduced:set("none")
		progress:set(0.5)
		t:expect(flash.Visible):toBe(false)
	end)
end
