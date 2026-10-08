--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Shared = require("../src/ui/types")
local engineLib = require("./lib/native_engine")
local travelEngine = require("../src/ui/travel_engine")
local context = require("../src/ui/context")

return function(harness: Verify.Harness)
	harness:case("64 spring carriers share one clock and preserve interruption velocity", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local handles: { travelEngine.Handle } = {}
		local positions: { number } = {}
		local targets: { number } = {}
		local stop = runtime.mount(function()
			local ctx = context(C, runtime, { types = native.types })
			for index = 1, 64 do
				positions[index], targets[index] = index, index + 100
				handles[index] = travelEngine(ctx, {
					initial = { index },
					target = function()
						return { targets[index] }
					end,
					sample = function(values)
						positions[index] = values[1]
					end,
					reduced = function()
						return false
					end,
					motion = "spring" :: "spring",
					duration = ctx.metric("motion.durations.travel"),
					ease = ctx.motionEase("travel"),
					spring = ctx.motionSpring("travel"),
				})
			end
			return Host.Folder {}
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		t:expect(engineLib.connections(native.heartbeat)):toBe(1)
		local count = #native.made
		for _ = 1, 6 do
			local previous = table.clone(positions)
			native.heartbeat:Fire(1 / 120)
			for index = 1, 64 do
				t:expect(positions[index] >= previous[index] and positions[index] <= targets[index]):toBe(true)
			end
		end
		local position, velocity = positions[1], handles[1].velocity()[1]
		t:expect(velocity > 0):toBe(true)
		targets[1] += 100
		handles[1].retarget()
		t:expect(positions[1]):toBe(position)
		t:expect(handles[1].velocity()[1]):toBe(velocity)
		for _ = 1, 100 do
			native.heartbeat:Fire(1 / 120)
		end
		for index = 1, 64 do
			t:expect(positions[index]):toBe(targets[index])
		end
		t:expect(#native.made):toBe(count)
	end)

	harness:case("64 slots move in place without overlay parents or move allocations", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, board = native.new("ScreenGui"), native.new("Frame")
		screen.Parent = native.new("Folder")
		board.Parent = screen
		local slots: { Frame } = {}
		for index = 1, 128 do
			local slot = native.new("Frame")
			slot.Parent = board
			slot.AbsolutePosition = native.types.Vector2.new((index - 1) * 20, 0)
			slot.AbsoluteSize = native.types.Vector2.new(16, 16)
			slots[index] = slot
		end
		local cells: { Facet.Cell<GuiObject> } = {}
		local nodes: { Frame } = {}
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			local children: Shared.FrameProps = { BackgroundTransparency = 1 }
			for index = 1, 64 do
				cells[index] = C.cell(slots[index] :: GuiObject)
				children[#children + 1] = UI.Travel {
					destination = cells[index],
					motion = "spring" :: "spring",
					content = function(): GuiObject
						nodes[index] = Host.Frame {}
						return nodes[index]
					end,
				}
			end
			return Host.Frame(children)
		end, board)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local count = #native.made
		for index = 1, 64 do
			t:expect(nodes[index].Parent == board):toBe(true)
			cells[index]:set(slots[index + 64])
		end
		for _ = 1, 60 do
			local previous: { number } = {}
			for index = 1, 64 do
				previous[index] = nodes[index].Position.X.Offset
			end
			native.heartbeat:Fire(1 / 60)
			for index = 1, 64 do
				t:expect(nodes[index].Parent == board):toBe(true)
				t:expect(nodes[index].Position.X.Offset >= previous[index]):toBe(true)
			end
		end
		t:expect(#native.made):toBe(count)
	end)
end
