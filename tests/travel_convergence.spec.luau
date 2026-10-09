--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Shared = require("../src/ui/types")
local engineLib = require("./lib/native_engine")
local travelEngine = require("../src/ui/travel_engine")
local context = require("../src/ui/context")

return function(harness: Verify.Harness)
	harness:case("Travel keeps automatic text at the slot size throughout motion", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(native)
		local screen = native.new("ScreenGui")
		local first, second = native.new("Frame"), native.new("Frame")
		first.Parent, second.Parent = screen, screen
		first.AbsoluteSize, second.AbsoluteSize = native.types.Vector2.new(48, 48), native.types.Vector2.new(64, 64)
		second.AbsolutePosition = native.types.Vector2.new(200, 100)
		local destination = Facet.Compose.cell(first :: GuiObject)
		local visual: GuiObject? = nil
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			return UI.Travel {
				destination = destination,
				content = function(): GuiObject
					local text = UI.Text { text = "E" }
					visual = text
					return text
				end,
			}
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		destination:set(second)
		for _ = 1, 60 do
			native.heartbeat:Fire(1 / 60)
			t:expect(assert(visual).AutomaticSize):toBe(native.types.Enum.AutomaticSize.None)
			t:expect(assert(visual).Size.Y.Offset >= 48):toBe(true)
		end
	end)
	harness:case("segmented controls reserve the native wrapped line extent", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(native)
		local stop, root = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types })
			return UI.Picker {
				style = "segmented" :: "segmented",
				selected = Facet.Compose.cell("a"),
				Size = native.types.UDim2.fromOffset(341, 44),
				options = {
					{ value = "a", label = "Swatches" },
					{ value = "b", label = "Spectrum" },
					{ value = "c", label = "Sliders" },
					{ value = "d", label = "Bricks" },
				},
			}
		end, native.new("ScreenGui"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local picker = root :: Frame
		local layout = assert(picker:FindFirstChildWhichIsA("UIListLayout")) :: UIListLayout
		local measured = (layout :: unknown) :: { AbsoluteContentSize: Vector2 }
		for _, height in { 92, 140, 44 } do
			measured.AbsoluteContentSize = native.types.Vector2.new(341, height)
			t:expect(picker.Size.Y.Offset >= height):toBe(true)
			t:expect(picker.Size.Y.Offset < height + 20):toBe(true)
		end
	end)
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
	harness:case("seven shuffled slots stagger arcs and lift and retarget without allocations", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, row = native.new("ScreenGui"), native.new("Frame")
		screen.Parent, row.Parent = native.new("Folder"), screen
		local slots: { Frame } = {}
		local nodes: { Frame } = {}
		local cells: { Facet.Cell<GuiObject> } = {}
		local starts: { number } = {}
		local lands = 0
		local lifted: { boolean } = {}
		local arced: { boolean } = {}
		local reduced: Facet.Cell<Shared.MotionLevel>
		for index = 1, 7 do
			slots[index] = native.new("Frame")
			slots[index].Parent = row
			slots[index].AbsolutePosition = native.types.Vector2.new((index - 1) * 56, 70)
			slots[index].AbsoluteSize = native.types.Vector2.new(44, 44)
		end
		local step = 0
		local stop = runtime.mount(function()
			reduced = C.cell("normal" :: Shared.MotionLevel)
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen, motionLevel = reduced })
			step = context(C, runtime, { types = native.types }).metric("motion.durations.travelStagger")
			local children: Shared.FrameProps = {}
			for index = 1, 7 do
				cells[index] = C.cell(slots[index] :: GuiObject)
				children[#children + 1] = UI.Travel {
					destination = cells[index],
					path = "arc" :: "arc",
					lift = true,
					stagger = function()
						return index - 1
					end,
					onStarted = function()
						table.insert(starts, index)
					end,
					onLanded = function()
						lands += 1
					end,
					content = function(): GuiObject
						nodes[index] = Host.Frame { ZIndex = 1 }
						return nodes[index]
					end,
				}
			end
			return Host.Frame(children)
		end, row)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local count = #native.made
		local function shuffle(offset: number)
			for index = 1, 7 do
				cells[index]:set(slots[(index - 1 + offset) % 7 + 1])
			end
		end
		shuffle(3)
		for frame = 1, 18 do
			native.heartbeat:Fire(1 / 120)
			local elapsed = frame / 120
			for order, index in starts do
				t:expect(index):toBe(order)
				t:expect(elapsed + 0.000001 >= (index - 1) * step):toBe(true)
			end
			for index = 1, 7 do
				local node = nodes[index]
				t:expect(node.Parent == row):toBe(true)
				local scale = node:FindFirstChild("TravelLift") :: UIScale
				lifted[index] = lifted[index] or scale.Scale > 1
				arced[index] = arced[index] or node.Position.Y.Offset < 70
				for other = index + 1, 7 do
					local neighbor = nodes[other]
					if math.abs(node.Position.X.Offset - neighbor.Position.X.Offset) < 44 then
						t:expect(node.ZIndex ~= neighbor.ZIndex):toBe(true)
					end
				end
			end
		end
		local positions: { UDim2 } = {}
		local scales: { number } = {}
		for index = 1, 7 do
			positions[index] = nodes[index].Position
			scales[index] = (nodes[index]:FindFirstChild("TravelLift") :: UIScale).Scale
		end
		shuffle(5)
		for index = 1, 7 do
			t:expect(nodes[index].Position):toBe(positions[index])
			t:expect((nodes[index]:FindFirstChild("TravelLift") :: UIScale).Scale):toBe(scales[index])
		end
		for _ = 1, 90 do
			native.heartbeat:Fire(1 / 120)
			for index = 1, 7 do
				lifted[index] = lifted[index] or (nodes[index]:FindFirstChild("TravelLift") :: UIScale).Scale > 1
				arced[index] = arced[index] or nodes[index].Position.Y.Offset < 70
				for other = index + 1, 7 do
					if math.abs(nodes[index].Position.X.Offset - nodes[other].Position.X.Offset) < 44 then
						t:expect(nodes[index].ZIndex ~= nodes[other].ZIndex):toBe(true)
					end
				end
			end
		end
		for index = 1, 7 do
			t:expect(nodes[index].Position.X.Offset):toBe(slots[(index - 1 + 5) % 7 + 1].AbsolutePosition.X)
			t:expect(nodes[index].Position.Y.Offset):toBe(70)
			t:expect(nodes[index].ZIndex):toBe(1)
			t:expect((nodes[index]:FindFirstChild("TravelLift") :: UIScale).Scale):toBe(1)
			t:expect(lifted[index] and arced[index]):toBe(true)
		end
		t:expect(lands):toBe(14)
		t:expect(#native.made):toBe(count)
		reduced:set("none")
		shuffle(0)
		t:expect(lands):toBe(21)
		for index = 1, 7 do
			t:expect(nodes[index].Position.X.Offset):toBe(slots[index].AbsolutePosition.X)
		end
	end)
	harness:case("landed content stays above the slot button", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, board, slot = native.new("ScreenGui"), native.new("Frame"), native.new("Frame")
		screen.Parent, board.Parent, slot.Parent = native.new("Folder"), screen, board
		slot.AbsoluteSize = native.types.Vector2.new(44, 44)
		local button = native.new("TextButton")
		button.Parent, button.ZIndex = slot, 2
		local node: TextLabel
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			return UI.Travel {
				destination = slot,
				content = function(): GuiObject
					node = Host.TextLabel { Text = "E", ZIndex = 1 }
					return node
				end,
			}
		end, board)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		t:expect(node.Parent == board):toBe(true)
		t:expect(node.ZIndex > button.ZIndex):toBe(true)
	end)
	harness:case("cross-container handoff compensates effective slot padding", function(t)
		local native = engineLib.new({
			getStyled = function(node: Instance, property: string): unknown
				if node:IsA("UIPadding") and property == "PaddingLeft" then
					return require("@lune/roblox").UDim.new(0, 12)
				end
				if node:IsA("UIPadding") and property == "PaddingTop" then
					return require("@lune/roblox").UDim.new(0, 1)
				end
				return ((node :: unknown) :: { [string]: unknown })[property]
			end,
		})
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, source, target = native.new("ScreenGui"), native.new("Frame"), native.new("Frame")
		screen.Parent, source.Parent, target.Parent = native.new("Folder"), screen, screen
		source.ClipsDescendants, target.ClipsDescendants = true, true
		source.AbsolutePosition, target.AbsolutePosition =
			native.types.Vector2.new(20, 30), native.types.Vector2.new(143, 539)
		source.AbsoluteSize, target.AbsoluteSize = native.types.Vector2.new(44, 44), native.types.Vector2.new(44, 44)
		local padding = native.new("UIPadding")
		padding.Parent = target
		local stroke = native.new("UIStroke")
		stroke.Parent, stroke.Thickness = target, 3
		padding.PaddingLeft, padding.PaddingTop = native.types.UDim.new(0, 0), native.types.UDim.new(0, 0)
		local destination: Facet.Cell<GuiObject>
		local node: Frame
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			destination = C.cell(source :: GuiObject)
			return UI.Travel {
				destination = destination,
				content = function(): GuiObject
					node = Host.Frame {}
					return node
				end,
			}
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		destination:set(target)
		local previous: Vector2? = nil
		local contentPoint = target.AbsolutePosition + native.types.Vector2.new(12, 1)
		local lastOverlayPoint = source.AbsolutePosition
		local observation = native.onWrite(function(object: unknown, property: string, _value: unknown)
			if object == (node :: unknown) and property == "Size" and node.Parent ~= target then
				local container = node.Parent :: GuiBase2d
				local point = container.AbsolutePosition
					+ native.types.Vector2.new(node.Position.X.Offset, node.Position.Y.Offset)
				if point.X >= source.AbsolutePosition.X and point.Y >= source.AbsolutePosition.Y then
					lastOverlayPoint = point
				end
			end
		end)
		t:defer(function()
			observation:Disconnect()
		end)
		local handoff = 0
		for _ = 1, 3000 do
			local oldParent = node.Parent
			native.heartbeat:Fire(1 / 6000)
			local container = node.Parent :: GuiBase2d
			local inset = if container == target then native.types.Vector2.new(12, 1) else native.types.Vector2.zero
			local screenPoint = container.AbsolutePosition
				+ inset
				+ native.types.Vector2.new(node.Position.X.Offset, node.Position.Y.Offset)
			if previous then
				t:expect(screenPoint.X >= previous.X and screenPoint.X <= contentPoint.X)
					:toBeTrueWith(`X {screenPoint.X}, previous {previous.X}, target {contentPoint.X}`)
				t:expect(screenPoint.Y >= previous.Y and screenPoint.Y <= contentPoint.Y)
					:toBeTrueWith(`Y {screenPoint.Y}, previous {previous.Y}, target {contentPoint.Y}`)
			end
			if previous and oldParent ~= node.Parent then
				handoff = (screenPoint - lastOverlayPoint).Magnitude
			end
			previous = screenPoint
		end
		t:expect(handoff <= 1):toBeTrueWith(`handoff {handoff}`)
		t:expect(node.Size.X.Offset):toBe(32)
		t:expect(node.Size.Y.Offset):toBe(43)
		t:expect(node.Parent == target):toBe(true)
		t:expect(target.AbsolutePosition.X + 12 + node.Position.X.Offset):toBe(155)
		t:expect(target.AbsolutePosition.Y + 1 + node.Position.Y.Offset):toBe(540)
	end)
	harness:case("native gamepad drivers select controls and run every required checkpoint", function(t)
		local native = engineLib.new()
		local root, slot, tile = native.new("Frame"), native.new("Frame"), native.new("TextButton")
		slot.Parent, tile.Parent = root, slot
		local send, back, view = native.new("TextButton"), native.new("TextButton"), native.new("ScrollingFrame")
		send.Name, back.Name, send.Parent, back.Parent = "Send", "Return", root, root
		local selected: GuiObject? = nil
		local events: { string } = {}
		local drivers = require("../tools/studio/live/zoom_travel_drivers")(function(name)
			table.insert(events, name)
		end, function(_, keys, frames)
			t:expect(selected ~= nil):toBe(true)
			table.insert(events, keys[1])
			if keys[1] == "Stick2Right" then
				t:expect(frames):toBe(30)
			end
		end, function(frames)
			t:expect(frames >= 30):toBe(true)
		end, function(node)
			selected = node
		end)
		drivers["zoom-gamepad"](nil, { view = view })
		t:expect(table.concat(events, ",")):toBe("ButtonR1,afterTrigger,Stick2Right,afterStick,ButtonY,afterFit")
		table.clear(events)
		drivers["travel-gamepad"](nil, { content = tile })
		t:expect(selected == back):toBe(true)
		t:expect(table.concat(events, ",")):toBe("ButtonA,afterSend,ButtonA,afterReturn")
	end)
	harness:case("F-030 virtual target replacement and removal end Travel ownership", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen = native.new("ScreenGui")
		screen.Parent = native.new("Folder")
		local slots: { [number]: GuiObject } = {}
		local rows: Facet.Cell<{ number }>
		local destination: Facet.Cell<GuiObject>
		local node: Frame
		local root: Frame
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			rows = C.cell({ 1, 2 })
			local grid = UI.VirtualGrid {
				from = rows,
				key = function(value: number): number
					return value
				end,
				columns = 2,
				itemSize = 60,
				mode = "all" :: "all",
				render = function(current: Shared.Readable<number>): GuiObject
					local id = current:peek()
					local slot = Host.Frame { Name = `Target{id}`, ClipsDescendants = true }
					slot.AbsolutePosition = native.types.Vector2.new(id * 60, 60)
					slot.AbsoluteSize = native.types.Vector2.new(44, 44)
					slots[id] = slot
					return slot
				end,
			}
			destination = C.cell(assert(slots[1]))
			local travel = UI.Travel {
				destination = destination,
				content = function(): GuiObject
					node = Host.Frame { Name = "Tile40" }
					return node
				end,
			}
			root = Host.Frame { grid :: unknown, travel :: unknown }
			return root
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		for _ = 1, 20 do
			native.heartbeat:Fire(1 / 60)
		end
		t:expect(node.Parent == slots[1]):toBe(true)
		rows:set({ 3, 4 })
		destination:set(assert(slots[3]))
		for _ = 1, 5 do
			native.heartbeat:Fire(1 / 60)
		end
		rows:set({})
		for _ = 1, 30 do
			native.heartbeat:Fire(1 / 60)
		end
		t:expect(node.Parent == nil):toBe(true)
		stop()
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
	end)
	harness:case("F-030 shared stepper drops externally destroyed carriers", function(t)
		local native = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local node: Frame
		local handle: travelEngine.Handle
		local samples = 0
		local stop = runtime.mount(function()
			local ctx = context(Facet.Compose, runtime, { types = native.types })
			node = Host.Frame {}
			handle = travelEngine(ctx, {
				initial = { 0 },
				carrier = node,
				target = function()
					return { 100 }
				end,
				sample = function()
					samples += 1
					node.Parent = native.new("Folder")
				end,
				reduced = function()
					return false
				end,
				motion = "ease" :: "ease",
				duration = ctx.metric("motion.durations.travel"),
				ease = ctx.motionEase("travel"),
				spring = ctx.motionSpring("travel"),
			})
			return node
		end, native.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		handle.retarget()
		native.heartbeat:Fire(1 / 120)
		node:Destroy()
		local count = samples
		for _ = 1, 30 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(samples):toBe(count)
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
		handle.retarget()
		handle.snap({ 100 })
		t:expect(samples):toBe(count)
	end)
	harness:case("F-030 removal cancels an overlay carrier before it lands", function(t)
		local native = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen, source, target = native.new("ScreenGui"), native.new("Frame"), native.new("Frame")
		screen.Parent, source.Parent, target.Parent = native.new("Folder"), screen, screen
		source.ClipsDescendants, target.ClipsDescendants = true, true
		source.AbsoluteSize, target.AbsoluteSize = native.types.Vector2.new(44, 44), native.types.Vector2.new(44, 44)
		target.AbsolutePosition = native.types.Vector2.new(200, 200)
		local destination: Facet.Cell<GuiObject>
		local node: Frame
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			destination = C.cell(source :: GuiObject)
			return UI.Travel {
				destination = destination,
				content = function(): GuiObject
					node = Host.Frame {}
					return node
				end,
			}
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		destination:set(target)
		native.heartbeat:Fire(1 / 120)
		t:expect(node.Parent ~= target):toBe(true)
		target:Destroy()
		for _ = 1, 30 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(node.Parent == nil):toBe(true)
		t:expect(engineLib.connections(native.heartbeat)):toBe(0)
	end)
	harness:case("onLanded can request the next slot during initial placement", function(t)
		local native = engineLib.new({ lenientProperties = true })
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(native)
		local Host = (runtime.constructors :: unknown) :: Shared.Host
		local screen = native.new("ScreenGui")
		local a, b = native.new("Frame"), native.new("Frame")
		a.Parent, b.Parent = screen, screen
		a.AbsolutePosition, b.AbsolutePosition = native.types.Vector2.new(100, 50), native.types.Vector2.new(20, 200)
		a.AbsoluteSize, b.AbsoluteSize = native.types.Vector2.new(52, 52), native.types.Vector2.new(52, 52)
		a.ClipsDescendants, b.ClipsDescendants = true, true
		local destination = C.cell(a :: GuiObject)
		local anchor: Frame
		local items = C.cell({} :: { number })
		local visits: { GuiObject } = {}
		local stop = runtime.mount(function()
			local UI = Facet.controls(runtime, { types = native.types, overlayParent = screen })
			return Host.Frame {
				C.keyed {
					from = items,
					key = function(id: number): number
						return id
					end,
					render = function()
						anchor = UI.Travel {
							destination = destination,
							content = function(): GuiObject
								return Host.Frame {}
							end,
							onLanded = function(slot: GuiObject)
								table.insert(visits, slot)
								if slot == a then
									destination:set(b)
								end
							end,
						}
						return anchor
					end,
				} :: unknown,
			}
		end, screen)
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		items:set({ 1 })
		t:expect(anchor:GetAttribute("FacetTravelMoving") == true)
			:toBeTrueWith(`parent={tostring(anchor.Parent)}, visits={#visits}`)
		t:expect(#visits):toBe(1)
		for _ = 1, 60 do
			native.heartbeat:Fire(1 / 120)
		end
		t:expect(visits):toEqual({ a, b })
	end)
end
