--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local context = require("../src/ui/context")
local Environment = require("../src/ui/environment_types")
local registerDrag = require("../src/ui/drag")
local activation = require("../src/ui/activation")
local DragTypes = require("../src/ui/drag_types")
local sessionOf = require("../src/ui/drag_session")
local gestureOf = require("../src/ui/gesture_service")
local engineLib = require("./lib/native_engine")
local ComposeTypes = require("../src/vendor/compose/core")

return function(harness: Verify.Harness)
	local function fixture()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local playerGui, screen = engine.new("PlayerGui"), engine.new("ScreenGui")
		screen.Parent = playerGui
		local source, target = engine.new("TextButton"), engine.new("TextButton")
		source.Parent, target.Parent = screen, screen
		source.AbsolutePosition, source.AbsoluteSize =
			engine.types.Vector2.new(20, 50), engine.types.Vector2.new(80, 60)
		target.AbsolutePosition, target.AbsoluteSize =
			engine.types.Vector2.new(240, 160), engine.types.Vector2.new(60, 60)
		local hits = { target }
		playerGui.GetGuiObjectsAtPosition = function()
			return hits
		end
		local input = engine.new("UserInputService")
		local ctx = context(
			Facet.Compose,
			runtime,
			{ types = engine.types, userInputService = input, services = { TweenService = engine.new("TweenService") } }
		)
		local service = sessionOf(ctx)
		local owner = Facet.Compose.createRootOwner(function() end, runtime.reactor)
		Facet.Compose.withOwner(owner.owner, function()
			service.own(source)
		end)
		return {
			engine = engine,
			input = input,
			bind = function(spec: Facet.DraggableSpec)
				Facet.Compose.withOwner(owner.owner, function()
					local UI = ({} :: unknown) :: Environment.EnvironmentControls
					registerDrag(ctx, UI)
					UI.draggable(source, spec)
				end)
			end,
			arbiter = gestureOf(ctx),
			useMeasuredHits = function(nodes: { GuiObject })
				playerGui.GetGuiObjectsAtPosition = function(_playerGui: PlayerGui, x: number, y: number)
					local measured: { GuiObject } = {}
					for _, node in nodes do
						local at, size = node.AbsolutePosition, node.AbsoluteSize
						if x >= at.X and y >= at.Y and x < at.X + size.X and y < at.Y + size.Y then
							table.insert(measured, node)
						end
					end
					return measured
				end
			end,
			registerAt = function(node: GuiObject, spec: Facet.DropTargetSpec)
				Facet.Compose.withOwner(owner.owner, function()
					service.register(node, (spec :: unknown) :: DragTypes.TargetSpec)
				end)
			end,
			runtime = runtime,
			service = service,
			source = source,
			target = target,
			screen = screen,
			register = function(spec: Facet.DropTargetSpec)
				Facet.Compose.withOwner(owner.owner, function()
					service.register(target, (spec :: unknown) :: DragTypes.TargetSpec)
				end)
			end,
			begin = function(spec: Facet.DraggableSpec?)
				service.begin(
					source,
					(spec or { payload = "tile", returnTravel = true }) :: DragTypes.SourceSpec,
					"pointer",
					nil,
					nil,
					{ position = engine.types.Vector2.new(28, 95), source = source }
				)
			end,
			stop = function()
				service.finish(false)
				owner.dispose()
				runtime:dispose()
			end,
		}
	end
	harness:suite("container travel", function()
		harness:case("F-026 reserved collection keys retain gaps, recall and release", function()
			local engine = engineLib.new()
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local UI = Facet.controls(runtime, { types = engine.types, motionLevel = "none" })
			local rows = C.cell({ { id = 1 }, { id = 2 }, { id = 3 } })
			local slots = C.cell({ 1, 2, 3 })
			local anchors: Facet.SlotControls<number> = {}
			local controls: { indexOfKey: ((number) -> number?)?, placementOf: ((number) -> ComposeTypes.Placement)? } =
				{}
			local stop, rack = runtime.mount(function()
				local spec = {
					from = rows,
					key = function(item: { id: number }): number
						return item.id
					end,
					slots = slots,
					slotControls = anchors,
					mode = "all" :: "all",
					columns = 3,
					itemSize = 40,
					controls = controls,
					render = function(current: Facet.Readable<{ id: number }>): GuiObject
						return UI.Button { label = tostring(current:peek().id) }
					end,
				}
				return UI.VirtualGrid((spec :: unknown) :: Facet.KeyedCollectionSpec<{ id: number }, number>)
			end, engine.new("ScreenGui"))
			local body = rack :: ScrollingFrame
			local function recessFor(key: number): GuiObject
				for _, child in body:GetDescendants() do
					if child:GetAttribute("FacetReservedKey") == tostring(key) then
						return child :: GuiObject
					end
				end
				error("missing reserved slot " .. key)
			end
			local original = assert(controls.placementOf)(3)
			rows:set({ { id = 1 }, { id = 3 } })
			Verify.expect(assert(controls.indexOfKey)(3)):toBe(3)
			Verify.expect(assert(controls.placementOf)(3).crossOffset):toBe(original.crossOffset)
			Verify.expect(recessFor(2).Visible):toBe(true)
			Verify.expect(assert(anchors.nodeOfKey)(2)):toBe(recessFor(2))
			rows:set({ { id = 1 }, { id = 3 }, { id = 2 } })
			engine.heartbeat:Fire(0.016)
			Verify.expect(assert(controls.indexOfKey)(2)):toBe(2)
			Verify.expect(recessFor(2).Visible):toBe(false)
			rows:set({ { id = 1 }, { id = 3 } })
			slots:set({ 1, 3 })
			Verify.expect(assert(controls.indexOfKey)(3)):toBe(2)
			Verify.expect(assert(controls.indexOfKey)(2)):toBe(nil)
			Verify.expect(assert(anchors.nodeOfKey)(2)):toBe(nil)
			stop()
			Verify.expect(anchors.nodeOfKey):toBe(nil)
			runtime:dispose()
		end)
		harness:case("F-026 reserved slots reflow on frames and provide zoomed recall landing", function()
			local engine = engineLib.new()
			local C, V2 = Facet.Compose, engine.types.Vector2
			local runtime = Facet.Roblox.createRuntime(engine)
			local screen = engine.new("ScreenGui")
			local rows = C.cell({ { id = 1 }, { id = 3 } })
			local slots = C.cell({ 1, 2, 3 })
			local controls: ComposeTypes.OrderedCollectionControls<number> = {}
			local UI = table.clone(Facet.controls(runtime, { types = engine.types }))
			local ctx = context(C, runtime, { types = engine.types })
			require("../src/ui/collections")(ctx, UI)
			local commits = 0
			local stop, mounted = runtime.mount(function()
				return UI.VirtualGrid {
					from = rows,
					key = function(item: { id: number }): number
						return item.id
					end,
					slots = slots,
					mode = "all" :: "all",
					columns = 3,
					itemSize = 40,
					controls = controls,
					drop = {
						travel = true,
						onDrop = function()
							commits += 1
							rows:set({ { id = 1 }, { id = 3 }, { id = 2 } })
							return true
						end,
					},
					render = function(current: Facet.Readable<{ id: number }>): GuiObject
						return UI.Button { label = tostring(current:peek().id) }
					end,
				}
			end, screen)
			local rack = mounted :: ScrollingFrame
			rack.AbsoluteSize, rack.AbsoluteWindowSize = V2.new(300, 80), V2.new(300, 80)
			local items = assert(rack:FindFirstChild("Items")) :: Frame
			items.AbsolutePosition = V2.new(100, 200)
			local unit = assert(rack:FindFirstChild("LayoutUnit")) :: Frame
			unit.AbsoluteSize = V2.new(2, 2)
			rack.CanvasPosition = V2.new(40, 20)
			local source: GuiObject = engine.new("TextButton")
			source.Parent, source.AbsolutePosition, source.AbsoluteSize = screen, V2.new(10, 10), V2.new(40, 40)
			local session = sessionOf(ctx)
			session.begin(
				source,
				{ payload = { keys = { 2 } } },
				"pointer",
				nil,
				nil,
				{ position = V2.new(30, 30), source = source }
			)
			session.hover(rack, nil)
			Verify.expect(session.commit(rack)):toBe(true)
			Verify.expect(commits):toBe(0)
			local ghost = assert(assert(session.state:peek()).ghost)
			local start = ghost.Position.X.Offset
			local changed = 0
			for _ = 1, 90 do
				engine.heartbeat:Fire(1 / 60)
				if ghost.Position.X.Offset ~= start then
					changed += 1
				end
				Verify.expect(ghost.Position.X.Offset >= start):toBe(true)
			end
			assert(changed > 1, "return needs multiple position samples")
			Verify.expect(commits):toBe(1)
			Verify.expect(assert(controls.indexOfKey)(2)):toBe(2)
			assert(math.abs(ghost.Position.X.Offset - 250) < 1, "landing x " .. ghost.Position.X.Offset)
			local third = assert(rack:FindFirstChild("3", true)) :: Frame
			local before = third.Position.X.Offset
			rows:set({ { id = 1 }, { id = 3 } })
			slots:set({ 1, 3 })
			Verify.expect(third.Position.X.Offset):toBe(before)
			local samples = 0
			for _ = 1, 120 do
				engine.heartbeat:Fire(1 / 60)
				if third.Position.X.Offset < before then
					samples += 1
				end
			end
			assert(samples > 1, "release needs multiple reflow samples")
			Verify.expect(math.abs(third.Position.X.Offset - assert(controls.placementOf)(2).crossOffset) < 1)
				:toBe(true)
			stop()
			runtime:dispose()
		end)
		harness:case("F-026 windowed reservations keep extent without mounting absent item content", function()
			local engine = engineLib.new()
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local UI = Facet.controls(runtime, { types = engine.types })
			local slots: { number } = {}
			for index = 1, 25 do
				table.insert(slots, index)
			end
			local rendered = 0
			local stop, mounted = runtime.mount(function()
				return UI.VirtualList {
					from = {} :: { { id: number } },
					slots = slots,
					key = function(item: { id: number }): number
						return item.id
					end,
					itemSize = 40,
					overscan = 0,
					render = function(): GuiObject
						rendered += 1
						return UI.Button { label = "Item" }
					end,
				}
			end, engine.new("ScreenGui"))
			local list = mounted :: ScrollingFrame
			list.AbsoluteWindowSize, list.AbsoluteSize =
				engine.types.Vector2.new(100, 80), engine.types.Vector2.new(100, 80)
			Verify.expect(list.CanvasSize.Y.Offset):toBe(1000)
			Verify.expect(rendered):toBe(0)
			list.CanvasPosition = engine.types.Vector2.new(0, 800)
			Verify.expect(list:FindFirstChild("ReservedSlot", true) ~= nil):toBe(true)
			stop()
			runtime:dispose()
		end)
		harness:case("F-027 collection factory immediate touch starts the existing transfer at six pixels", function()
			local engine = engineLib.new()
			local C, V2, V3, E = Facet.Compose, engine.types.Vector2, engine.types.Vector3, engine.types.Enum
			local runtime = Facet.Roblox.createRuntime(engine)
			local input = engine.new("UserInputService")
			input.PreferredInput = E.PreferredInput.Touch
			local playerGui, screen = engine.new("PlayerGui"), engine.new("ScreenGui")
			screen.Parent = playerGui
			local hits: { GuiObject } = {}
			playerGui.GetGuiObjectsAtPosition = function()
				return hits
			end
			local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, motionLevel = "none" })
			local starts, ends, factories, drops = 0, 0, 0, 0
			local touchAxis: "X" | "Y" | "XY" = "XY"
			local carried: unknown = nil
			local stop, rack = runtime.mount(function()
				return UI.VirtualGrid {
					from = { { id = 1 }, { id = 2 }, { id = 3 } },
					key = "id",
					mode = "all" :: "all",
					columns = 3,
					itemSize = 40,
					reorderable = true,
					onReorder = function() end,
					drag = function(items: { { id: number } }, _keys: { number }): Facet.DraggableSpec
						factories += 1
						return {
							payload = items[1].id,
							touchPickup = "immediate",
							touchDragAxis = touchAxis,
							onStart = function(value)
								starts += 1
								carried = value
							end,
							onEnd = function()
								ends += 1
							end,
						}
					end,
					render = function(current: Facet.Readable<{ id: number }>): GuiObject
						return UI.Button "Tile" {
							label = function(use: Facet.Use)
								return tostring(use(current).id)
							end,
						}
					end,
				}
			end, screen)
			local body = rack :: ScrollingFrame
			body.AbsoluteWindowSize, body.AbsoluteSize = V2.new(120, 80), V2.new(120, 80)
			local cell = assert(body:FindFirstChild("1", true))
			local row = assert(cell:FindFirstChild("Reorderable", true)) :: Frame
			row.AbsoluteSize = V2.new(40, 40)
			local hit = assert(row:FindFirstChild("Tile", true)) :: GuiObject
			local pointer = (
				{
					UserInputType = E.UserInputType.Touch,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(10, 10, 0),
				} :: unknown
			) :: InputObject
			local hitInput = (hit.InputBegan :: unknown) :: { Fire: (unknown, InputObject) -> () }
			hitInput:Fire(pointer)
			pointer.Position = V3.new(15, 10, 0)
			input.InputChanged:Fire(pointer)
			Verify.expect(starts):toBe(0)
			local neighbor = assert(assert(body:FindFirstChild("2", true)):FindFirstChild("Tile", true)) :: GuiObject
			local neighborInput = (neighbor.InputBegan :: unknown) :: { Fire: (unknown, InputObject) -> () }
			neighborInput:Fire(pointer)
			pointer.Position = V3.new(16, 10, 0)
			input.InputChanged:Fire(pointer)
			Verify.expect(starts):toBe(1)
			Verify.expect(carried):toBe(1)
			Verify.expect(body.ScrollingEnabled):toBe(false)
			Verify.expect((assert(row:FindFirstChild("Cells")) :: GuiObject).Visible):toBe(false)
			Verify.expect(body:FindFirstChild("DragImage", true) ~= nil):toBe(true)
			local ghost = assert(screen:FindFirstChild("DragGhost")) :: GuiObject
			local dropLine = assert(body:FindFirstChild("DropLine", true)) :: GuiObject
			local initialSlot = dropLine.Position
			for frame = 1, 30 do
				pointer.Position = V3.new(18 + frame * 2, 10, 0)
				input.InputChanged:Fire(pointer)
				Verify.expect(math.abs(ghost.Position.X.Offset - pointer.Position.X) <= 1):toBe(true)
				engine.heartbeat:Fire(1 / 120)
				Verify.expect(math.abs(ghost.Position.X.Offset - pointer.Position.X) <= 1):toBe(true)
			end
			Verify.expect(dropLine.Position ~= initialSlot):toBe(true)
			pointer.UserInputState = E.UserInputState.Cancel
			input.InputEnded:Fire(pointer)
			Verify.expect(ends):toBe(1)
			Verify.expect(body.ScrollingEnabled):toBe(true)
			Verify.expect(factories):toBe(1)
			touchAxis = "X"
			local scrollPointer = (
				{
					UserInputType = E.UserInputType.Touch,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(10, 10, 0),
				} :: unknown
			) :: InputObject
			hitInput:Fire(scrollPointer)
			scrollPointer.Position = V3.new(10, 18, 0)
			input.InputChanged:Fire(scrollPointer)
			local longPress = (
				row.TouchLongPress :: unknown
			) :: { Fire: (unknown, { Vector2 }, Enum.UserInputState) -> () }
			longPress:Fire({ V2.new(10, 18) }, E.UserInputState.Begin)
			Verify.expect(starts):toBe(1)
			Verify.expect(body.ScrollingEnabled):toBe(true)
			scrollPointer.Position = V3.new(50, 18, 0)
			input.InputChanged:Fire(scrollPointer)
			Verify.expect(starts):toBe(1)
			scrollPointer.UserInputState = E.UserInputState.End
			input.InputEnded:Fire(scrollPointer)
			touchAxis = "XY"
			local stopTarget, target = runtime.mount(function()
				local target = UI.Button "Destination" { label = "Place here" }
				UI.dropTarget(target, {
					onDrop = function(value)
						Verify.expect(value):toBe(1)
						drops += 1
					end,
				})
				return target
			end, screen)
			hits = { target :: GuiObject }
			local dropPointer = (
				{
					UserInputType = E.UserInputType.Touch,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(10, 10, 0),
				} :: unknown
			) :: InputObject
			hitInput:Fire(dropPointer)
			dropPointer.Position = V3.new(18, 10, 0)
			input.InputChanged:Fire(dropPointer)
			dropPointer.Position = V3.new(300, 200, 0)
			input.InputChanged:Fire(dropPointer)
			dropPointer.UserInputState = E.UserInputState.End
			input.InputEnded:Fire(dropPointer)
			Verify.expect(starts):toBe(2)
			Verify.expect(ends):toBe(2)
			Verify.expect(drops):toBe(1)
			Verify.expect(factories):toBe(3)
			Verify.expect(body.ScrollingEnabled):toBe(true)
			stopTarget()
			stop()
			runtime:dispose()
		end)
		harness:case("default return and accepted shrink sample the shared engine without native tweens", function()
			local w = fixture()
			w.begin({ payload = "tile" })
			w.service.update(w.engine.types.Vector2.new(300, 400))
			local ghost = assert(w.screen:FindFirstChild("DragGhost")) :: GuiObject
			w.service.finish(false)
			Verify.expect(w.service.state:peek()):toBeNil()
			local previous = ghost.Position
			for _ = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				Verify.expect(ghost.Position.X.Offset <= previous.X.Offset):toBe(true)
				Verify.expect(ghost.Position.Y.Offset <= previous.Y.Offset):toBe(true)
				previous = ghost.Position
			end
			Verify.expect(ghost.Position):toBe(w.engine.types.UDim2.fromOffset(28, 95))
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			local commits = 0
			w.register({
				onDrop = function()
					commits += 1
				end,
			})
			w.begin({ payload = "tile" })
			ghost = assert(w.screen:FindFirstChild("DragGhost")) :: GuiObject
			w.service.commit(w.target)
			Verify.expect(commits):toBe(1)
			local scale = assert(ghost:FindFirstChildWhichIsA("UIScale"))
			local previousScale = scale.Scale
			for _ = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				Verify.expect(scale.Scale >= 0 and scale.Scale <= previousScale):toBe(true)
				previousScale = scale.Scale
			end
			Verify.expect(scale.Scale):toBe(0)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			w.stop()
		end)
		harness:case("capture scope and each frame refresh targets through a moving camera", function()
			local w = fixture()
			local V2 = w.engine.types.Vector2
			local second: GuiObject = w.engine.new("TextButton")
			second.Parent = w.screen
			second.AbsoluteSize = V2.new(60, 60)
			second.AbsolutePosition = V2.new(400, 160)
			local placed: Instance? = nil
			w.register({
				onDrop = function()
					placed = w.target
				end,
			})
			w.registerAt(second, {
				onDrop = function()
					placed = second
				end,
			})
			w.useMeasuredHits({ w.target, second })
			w.begin({
				payload = "tile",
				onStart = function()
					Verify.expect(w.arbiter.claimCamera(second)):toBe(false)
					Verify.expect(w.arbiter.claimCamera(w.source)):toBe(true)
				end,
			})
			w.service.update(V2.new(270, 180))
			for frame = 1, 60 do
				w.target.AbsolutePosition = V2.new(240 - frame, 160)
				second.AbsolutePosition = V2.new(380 - frame * 2, 160)
				w.engine.heartbeat:Fire(1 / 120)
				local expected = if frame < 30 then w.target elseif frame < 55 then nil else second
				Verify.expect(assert(w.service.state:peek()).target):toBe(expected)
				Verify.expect(w.arbiter.claimCamera(w.source)):toBe(false)
			end
			second.AbsolutePosition = V2.new(400, 160)
			w.target.AbsolutePosition = V2.new(240, 160)
			w.service.commit(nil)
			Verify.expect(placed):toBe(w.target)
			w.stop()
		end)
		harness:case("writes contact before every frame without a tween or layout settle", function()
			local w = fixture()
			w.register({ onDrop = function() end })
			w.begin()
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			for frame = 1, 120 do
				local point = w.engine.types.Vector2.new(30 + frame * 1.3, 100 + math.sin(frame) * 10)
				w.service.update(point)
				Verify.expect(math.abs(ghost.Position.X.Offset - point.X) <= 1):toBe(true)
				Verify.expect(math.abs(ghost.Position.Y.Offset - point.Y) <= 1):toBe(true)
				w.engine.heartbeat:Fire(1 / 60)
				Verify.expect(math.abs(ghost.Position.X.Offset - point.X) <= 1):toBe(true)
				Verify.expect(ghost.AnchorPoint):toEqual(w.engine.types.Vector2.new(0.1, 0.75))
			end
			w.stop()
		end)
		harness:case("travels continuously and commits only at arrival", function()
			local w = fixture()
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
					return true
				end,
			})
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			Verify.expect(w.service.commit(w.target)):toBe(true)
			Verify.expect(commits):toBe(0)
			local previous = ghost.Position.X.Offset
			local moved = false
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.service.state:peek() then
					Verify.expect(ghost.Position.X.Offset >= previous):toBe(true)
					Verify.expect(ghost.Position.X.Offset <= 246):toBe(true)
					moved = moved or ghost.Position.X.Offset > previous
					previous = ghost.Position.X.Offset
					Verify.expect(commits):toBe(0)
				end
			end
			Verify.expect(moved):toBe(true)
			Verify.expect(commits):toBe(1)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			w.stop()
		end)
		harness:case("touch pickup locks all scroll ancestors and rejects late long press", function()
			for _, pickup in { "immediate", "longPress" } do
				local w = fixture()
				local outer, inner = w.engine.new("ScrollingFrame"), w.engine.new("ScrollingFrame")
				outer.Parent, inner.Parent, w.source.Parent = w.screen, outer, inner
				outer.ScrollingEnabled, inner.ScrollingEnabled = true, false
				w.bind({ payload = "tile", returnTravel = true, touchPickup = pickup :: "immediate" | "longPress" })
				local event = {
					Position = w.engine.types.Vector3.new(28, 95, 0),
					UserInputType = w.engine.types.Enum.UserInputType.Touch,
					UserInputState = w.engine.types.Enum.UserInputState.Begin,
				}
				w.source.InputBegan:Fire(event)
				event.Position = w.engine.types.Vector3.new(36, 95, 0)
				w.input.InputChanged:Fire(event)
				if pickup == "immediate" then
					Verify.expect(assert(w.service.state:peek()).source):toBe(w.source)
					Verify.expect(outer.ScrollingEnabled):toBe(false)
					Verify.expect(inner.ScrollingEnabled):toBe(false)
				else
					w.source.TouchLongPress:Fire(
						{ w.engine.types.Vector2.new(36, 95) },
						w.engine.types.Enum.UserInputState.Begin
					)
					Verify.expect(w.service.state:peek()):toBeNil()
					Verify.expect(outer.ScrollingEnabled):toBe(true)
				end
				w.stop()
				Verify.expect(outer.ScrollingEnabled):toBe(true)
				Verify.expect(inner.ScrollingEnabled):toBe(false)
			end
		end)
		harness:case("paint outside a bounded hit area cannot start a native mouse drag", function()
			local w = fixture()
			local hit = w.engine.new("Frame")
			hit.Parent = w.source
			hit.AbsolutePosition = w.engine.types.Vector2.new(20, 50)
			hit.AbsoluteSize = w.engine.types.Vector2.new(40, 60)
			w.bind({ payload = "tile", hitArea = hit })
			local at = w.engine.types.Vector2.new(60, 95)
			w.source.InputBegan:Fire({
				Position = w.engine.types.Vector3.new(at.X, at.Y, 0),
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.Begin,
			})
			local detector = assert(w.source:FindFirstChildWhichIsA("UIDragDetector"))
			detector.DragStart:Fire(at)
			detector.DragContinue:Fire(at + w.engine.types.Vector2.new(30, 0))
			Verify.expect(w.service.state:peek()):toBeNil()
			w.stop()
		end)
		harness:case("a mouse tap calls the source press once without a drag", function()
			local w = fixture()
			local presses = 0
			local disconnect = activation.provide(w.source, function()
				presses += 1
			end)
			w.bind({ payload = "tile" })
			local at = w.engine.types.Vector2.new(28, 95)
			w.source.InputBegan:Fire({
				Position = w.engine.types.Vector3.new(at.X, at.Y, 0),
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.Begin,
			})
			local detector = assert(w.source:FindFirstChildWhichIsA("UIDragDetector"))
			detector.DragStart:Fire(at)
			detector.DragEnd:Fire(at)
			Verify.expect(presses):toBe(1)
			Verify.expect(w.service.state:peek()):toBeNil()
			disconnect()
			w.stop()
		end)
		harness:case("a second source cannot replace the captured tile", function()
			local w = fixture()
			w.begin()
			local first = assert(w.service.state:peek())
			w.service.begin(w.target, { payload = "neighbour" }, "pointer", nil, nil)
			Verify.expect(assert(w.service.state:peek()).source):toBe(first.source)
			Verify.expect(assert(w.service.state:peek()).payload):toBe("tile")
			w.stop()
		end)
		harness:case("cancel returns along a sampled path and holds the recess until arrival", function()
			local w = fixture()
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			w.service.finish(false, "Cancelled")
			Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBe(true)
			local previous = ghost.Position.X.Offset
			local moved = false
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.screen:FindFirstChild("DragGhost") then
					Verify.expect(ghost.Position.X.Offset <= previous):toBe(true)
					Verify.expect(ghost.Position.X.Offset >= 28):toBe(true)
					moved = moved or ghost.Position.X.Offset < previous
					previous = ghost.Position.X.Offset
					Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBe(true)
				end
			end
			Verify.expect(moved):toBe(true)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBeNil()
			w.stop()
		end)
		harness:case("scaled screen coordinates remain exact while a scroll parent moves", function()
			local w = fixture()
			local scale = w.engine.new("UIScale")
			scale.Scale, scale.Parent = 0.75, w.screen
			w.screen.AbsolutePosition = w.engine.types.Vector2.new(4, 18)
			local scroll = w.engine.new("ScrollingFrame")
			scroll.Parent, w.source.Parent = w.screen, scroll
			w.begin()
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			for frame = 1, 120 do
				local point = w.engine.types.Vector2.new(30 + frame, 95 + frame * 0.5)
				scroll.CanvasPosition = w.engine.types.Vector2.new(frame, frame * 2)
				w.service.update(point)
				w.engine.heartbeat:Fire(1 / 60)
				local contact = w.screen.AbsolutePosition
					+ w.engine.types.Vector2.new(ghost.Position.X.Offset, ghost.Position.Y.Offset) * 0.75
				Verify.expect((contact - point).Magnitude <= 1):toBe(true)
			end
			w.stop()
		end)
		harness:case("landing removes source zoom from the whole preview on every sample", function()
			local w = fixture()
			local zoom = w.engine.new("Frame")
			zoom.Parent, w.source.Parent = w.screen, zoom
			local sourceScale = w.engine.new("UIScale")
			sourceScale.Scale, sourceScale.Parent = 3, zoom
			w.source.AbsoluteSize = w.engine.types.Vector2.new(240, 180)
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
				end,
			})
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			local scale = assert(ghost:FindFirstChildWhichIsA("UIScale"))
			Verify.expect(scale.Scale):toBe(3)
			w.service.commit(w.target)
			local previous = scale.Scale
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.service.state:peek() then
					Verify.expect(scale.Scale <= previous and scale.Scale >= 1):toBe(true)
					Verify.expect(ghost.Size.X.Offset * scale.Scale >= 59):toBe(true)
					Verify.expect(ghost.Size.X.Offset * scale.Scale <= 240):toBe(true)
					Verify.expect(ghost.Size.Y.Offset * scale.Scale >= 59):toBe(true)
					Verify.expect(ghost.Size.Y.Offset * scale.Scale <= 180):toBe(true)
					previous = scale.Scale
				end
			end
			Verify.expect(scale.Scale):toBe(1)
			Verify.expect(commits):toBe(1)
			w.stop()
		end)
		harness:case("cancellation during travel prevents a model commit", function()
			local w = fixture()
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
				end,
			})
			w.begin()
			w.service.commit(w.target)
			w.engine.heartbeat:Fire(1 / 60)
			w.service.finish(false, "Cancelled")
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 60)
			end
			Verify.expect(commits):toBe(0)
			Verify.expect(w.service.state:peek()):toBeNil()
			w.stop()
		end)
	end)
end
