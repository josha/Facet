--!strict
local Bdd = require("../../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")
local Compose = require("../../src/vendor/compose/core")
local FixtureCollectionProps = require("../../src/ui/collection_props")
local FixtureEnvironmentTypes = require("../../src/ui/environment_types")
local FixtureComposeTypes = require("../../src/vendor/compose/core")
local SharedTypes = require("../../src/ui/control_types")
local Types = require("../../src/ui/types")
local engineLib = require("./native_engine")
local nativeDrag = require("./native_drag")

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Record = { id: number, label: string }
type Setup = () -> (engineLib.Engine, ComposeRuntime, SharedTypes.Controls, Instance, GuiService, Types.Context)

return function(test: Bdd.Bdd, setup: Setup, records: (number) -> { Record })
	local describe, it, expect = test.describe, test.it, test.expect
	describe("reorder review regressions", function()
		for _, registration in { "position", "access" } do
			local name = `keeps the replacement row's {registration} registration after retirement`
			it(name, {
				id = `native_collections::reorder review regressions::{name}`,
				run = function()
					local engine, runtime, UI, target, _, ctx = setup()
					local all = records(4)
					local rows = Compose.cell({ all[1], all[2], all[3] })
					local mounted: ScrollingFrame? = nil
					local stop = runtime.mount(function(): ScrollingFrame
						local spec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
							from = rows,
							key = function(item: Record): number
								return item.id
							end,
							mode = "all",
							recycle = false,
							itemSize = 20,
							reorderable = true,
							movable = function(item: Record): boolean
								return item.label ~= "Locked"
							end,
							onReorder = function() end,
							render = function(): GuiObject
								return UI.Button { label = "Row" }
							end,
						}
						local node = UI.VirtualList(spec)
						mounted = node
						return node
					end, target)
					local node = assert(mounted)
					local V2 = engine.types.Vector2
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 200))
					nativeDrag.measure(node, engine.environment)
					local items = assert(node:FindFirstChild("Items"))
					local function paint()
						for _, child in items:GetDescendants() do
							if child:IsA("GuiObject") then
								engine.environment.poke(
									VerifyRoblox.assertInstance(child),
									"AbsoluteSize",
									V2.new(200, 20)
								)
								if child:IsA("TextLabel") or child:IsA("TextButton") then
									engine.environment.poke(
										VerifyRoblox.assertInstance(child),
										"TextBounds",
										V2.new(40, 20)
									)
								end
							end
						end
						for _ = 1, 4 do
							engine.heartbeat:Fire(1 / 60)
						end
					end
					paint()
					local old = assert(items:FindFirstChild("2"))
					rows:set({ all[1], all[3], all[4] })
					expect(old.Parent):toBe(items)
					rows:set(all)
					local replacement: GuiObject? = nil
					for _, child in items:GetChildren() do
						if child.Name == "2" and child ~= old and child:IsA("GuiObject") then
							replacement = child
						end
					end
					local current = assert(replacement)
					paint()
					expect(old.Parent):toBeNil()
					if registration == "position" then
						local first = assert(items:FindFirstChild("1"))
						assert(first:IsA("GuiObject"))
						local detector = VerifyRoblox.assertInstance(
							assert(first:FindFirstChild("Move", true)):FindFirstChildWhichIsA("UIDragDetector")
						)
						engine.environment.fire(detector, "DragStart", V2.new(10, 10))
						engine.environment.fire(detector, "DragContinue", V2.new(10, 35))
						expect(current.Position.Y.Offset):toBe(0)
						require("../../src/ui/drag_session")(ctx).finish(false)
					else
						local handle = assert(current:FindFirstChild("Move", true))
						assert(handle:IsA("TextButton"))
						local detector = assert(current:FindFirstChild("FacetCollectionDrag", true))
						assert(detector:IsA("UIDragDetector"))
						expect(handle.Interactable and detector.Enabled):toBe(true)
						rows:set({ all[1], { id = 2, label = "Locked" }, all[3], all[4] })
						expect(handle.Interactable):toBe(false)
						expect(detector.Enabled):toBe(false)
						rows:set(all)
						expect(handle.Interactable and detector.Enabled):toBe(true)
					end
					stop()
					runtime:dispose()
				end,
			})
		end
		for _, grid in { false, true } do
			for _, horizontal in { false, true } do
				local name = `refreshes keyboard feedback after insertion in a {if horizontal
					then "horizontal"
					else "vertical"} {if grid then "grid" else "list"}`
				it(name, {
					id = `native_collections::spatial grid reordering::{name}`,
					run = function()
						local engine, runtime, UI, target = setup()
						local rows = Compose.cell(records(5))
						local controls: FixtureComposeTypes.OrderedCollectionControls<number> = {}
						local mounted: ScrollingFrame? = nil
						local stop = runtime.mount(function(): ScrollingFrame
							local spec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
								from = rows,
								key = function(item: Record): number
									return item.id
								end,
								controls = controls,
								mode = "all",
								columns = if grid then 2 else nil,
								direction = if horizontal then "horizontal" else "vertical",
								itemSize = 20,
								reorderable = true,
								onReorder = function() end,
								render = function(): GuiObject
									return UI.Button { label = "Row" }
								end,
							}
							local node = if grid then UI.VirtualGrid(spec) else UI.VirtualList(spec)
							mounted = node
							return node
						end, target)
						local node = assert(mounted)
						local V2 = engine.types.Vector2
						engine.environment.poke(
							VerifyRoblox.assertInstance(node),
							"AbsoluteWindowSize",
							V2.new(200, 200)
						)
						local handle = assert(assert(node:FindFirstChild("3", true)):FindFirstChild("Move", true))
						engine.environment.fire(VerifyRoblox.assertInstance(handle), "Activated")
						local line = assert(node:FindFirstChild("DropLine", true))
						local image = assert(node:FindFirstChild("DragImage", true))
						assert(line:IsA("GuiObject") and image:IsA("GuiObject"))
						local before = line.Position
						local changed = table.clone(rows:peek())
						table.insert(changed, 1, { id = 9, label = "New" })
						rows:set(changed)
						local at = assert(controls.placementOf)(assert(assert(controls.indexOfKey)(2)))
						local expected = if horizontal
							then engine.types.UDim2.fromOffset(at.offset, at.crossOffset)
							else engine.types.UDim2.fromOffset(at.crossOffset, at.offset)
						expect(expected == before):toBe(false)
						expect(line.Position):toBe(expected)
						expect(image.Position):toBe(expected)
						expect(if horizontal then line.Size.X.Offset else line.Size.Y.Offset):toBe(
							if grid then at.size else 2
						)
						stop()
						runtime:dispose()
					end,
				})
			end
		end
		it("moves a forward neighbour across an empty reserved slot", {
			id = "native_collections::live pointer reorder displacement::moves a forward neighbour across an empty reserved slot",
			run = function()
				local engine, runtime, UI, target = setup()
				local all = records(5)
				local mounted: ScrollingFrame? = nil
				local stop = runtime.mount(function(): ScrollingFrame
					local spec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = { all[1], all[2], all[4], all[5] },
						key = function(item: Record): number
							return item.id
						end,
						slots = { 1, 2, 3, 4, 5 },
						itemSize = 20,
						reorderable = true,
						drag = function(): FixtureEnvironmentTypes.DraggableSpec
							return { payload = "row", operations = { "move" } }
						end,
						drop = {
							onDrop = function(): boolean
								return true
							end,
						},
						onReorder = function() end,
						render = function(): GuiObject
							return UI.Button { label = "Row" }
						end,
					}
					local node = UI.VirtualList(spec)
					mounted = node
					return node
				end, target)
				local node = assert(mounted)
				local V2 = engine.types.Vector2
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 200))
				nativeDrag.measure(node, engine.environment)
				local fourth = assert(node:FindFirstChild("4", true))
				local fifth = assert(node:FindFirstChild("5", true))
				assert(fourth:IsA("GuiObject") and fifth:IsA("GuiObject"))
				local fourthRest, fifthRest = fourth.Position, fifth.Position
				local detector = VerifyRoblox.assertInstance(
					assert(fourth:FindFirstChild("Move", true)):FindFirstChildWhichIsA("UIDragDetector")
				)
				engine.environment.fire(detector, "DragStart", V2.new(10, fourthRest.Y.Offset + 10))
				engine.environment.fire(detector, "DragContinue", V2.new(10, fifthRest.Y.Offset + 15))
				expect(fifth.Position):toBe(fourthRest)
				engine.environment.fire(detector, "DragEnd")
				stop()
				runtime:dispose()
			end,
		})
		it("resolves external insertion neighbours once for all positioned rows", {
			id = "native_collections::collection transfer sessions::resolves external insertion neighbours once for all positioned rows",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local calls = 0
				local mounted: ScrollingFrame? = nil
				local stop = runtime.mount(function(): ScrollingFrame
					local spec: FixtureCollectionProps.KeyedCollectionSpec<Record, number> = {
						from = records(200),
						key = function(item: Record): number
							calls += 1
							return item.id
						end,
						mode = "all",
						itemSize = 20,
						drop = {
							operation = "copy",
							onDrop = function(): boolean
								return true
							end,
						},
						render = function(): GuiObject
							return UI.Button { label = "Row" }
						end,
					}
					local node = UI.VirtualList(spec)
					mounted = node
					return node
				end, target)
				local node = assert(mounted)
				local V2 = engine.types.Vector2
				engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(200, 4000))
				nativeDrag.measure(node, engine.environment)
				local session = require("../../src/ui/drag_session")(ctx)
				local source = engine.new("TextButton")
				source.Parent = target
				session.begin(source, { payload = "new", operations = { "copy" } }, "pointer", nil, false)
				for _, y in { 3965, 3945 } do
					calls = 0
					session.update(V2.new(100, y))
					expect(calls):toBeLessThanOrEqual(600)
					local last = assert(node:FindFirstChild("200", true))
					assert(last:IsA("GuiObject"))
					expect(last.Position.Y.Offset):toBe(4000)
				end
				session.finish(false)
				source:Destroy()
				stop()
				runtime:dispose()
			end,
		})
	end)
end
