--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")

type Record = { id: number, label: string }

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local Compose = Facet.Compose

	local function setup()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		local root = engine.new("ScreenGui")
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 800, 600)
		end)
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				services = { GuiService = gui },
				inputParent = root,
				motionLevel = "none",
			} :: Facet.ControlOptions
		)
		return engine, runtime, UI, root, gui
	end

	local function records(count: number, base: number?): { Record }
		local values: { Record } = {}
		for index = 1, count do
			local id = (base or 0) + index
			values[index] = { id = id, label = `Item {id}` }
		end
		return values
	end

	local function key(item: Record): number
		return item.id
	end

	local function button(UI: Facet.Controls, current: Facet.ReadOnlyValue<Record>): GuiObject
		return UI.Button "Action" {
			label = function(use: Facet.Use): string
				return use(current).label
			end,
		}
	end

	describe("collection focus and windowing", function()
		it("keeps a windowed list's mounted rows bounded after a long scroll", {
			id = "native_collection_focus::collection focus and windowing::keeps a windowed list's mounted rows bounded after a long scroll",
			run = function()
				for _, recycle in { true, false } do
					local recycling: boolean? = if recycle then nil else false
					local engine, runtime, UI, target = setup()
					local stop, mounted = runtime.mount(function()
						local listSpec: Facet.KeyedCollectionSpec<Record, number> = {
							from = records(1000),
							key = key,
							itemSize = 40,
							recycle = recycling,
							render = function(current: Facet.ReadOnlyValue<Record>): GuiObject
								return button(UI, current)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					local node = (mounted :: unknown) :: ScrollingFrame
					local V2 = engine.types.Vector2
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(300, 400))
					local items = assert(node:FindFirstChild("Items", true))
					local function count(): number
						local total = 0
						for _, child in items:GetChildren() do
							if child:IsA("GuiObject") then
								total += 1
							end
						end
						return total
					end
					local start = count()
					for offset = 0, 20000, 400 do
						node.CanvasPosition = V2.new(0, offset)
					end
					expect(items:FindFirstChild("500") ~= nil or items:FindFirstChild("510") ~= nil):toBe(true)
					expect(count() <= start + 4):toBe(true)
					stop()
					runtime:dispose()
				end
			end,
		})

		it("credits a selection inside a nested list to the outer row and can leave restore off", {
			id = "native_collection_focus::collection focus and windowing::credits a selection inside a nested list to the outer row and can leave restore off",
			run = function()
				for _, restore in { true, false } do
					local keep: boolean? = if restore then nil else false
					local engine, runtime, UI, target, gui = setup()
					local outer: Facet.FocusControls<number> = {}
					local stop, mounted = runtime.mount(function()
						local listSpec: Facet.KeyedCollectionSpec<Record, number> = {
							from = records(3),
							key = key,
							itemSize = 60,
							focus = outer,
							restoreFocus = keep,
							render = function(current: Facet.ReadOnlyValue<Record>): GuiObject
								local shelf: Facet.KeyedCollectionSpec<Record, number> = {
									Name = "Shelf",
									from = records(4, current:peek().id * 10),
									key = key,
									itemSize = 40,
									direction = "horizontal",
									render = function(item: Facet.ReadOnlyValue<Record>): GuiObject
										return button(UI, item)
									end,
								}
								return UI.VirtualList(shelf)
							end,
						}
						return UI.VirtualList(listSpec)
					end, target)
					local node = (mounted :: unknown) :: ScrollingFrame
					local V2 = engine.types.Vector2
					engine.environment.poke(VerifyRoblox.assertInstance(node), "AbsoluteWindowSize", V2.new(300, 200))
					for _, shelf in node:GetDescendants() do
						if shelf.Name == "Shelf" then
							engine.environment.poke(
								VerifyRoblox.assertInstance(shelf),
								"AbsoluteWindowSize",
								V2.new(300, 60)
							)
						end
					end
					local row = assert(node:FindFirstChild("2", true))
					gui.SelectedObject =
						assert(assert(row:FindFirstChild("22", true)):FindFirstChild("Action", true)) :: GuiObject
					expect(assert(outer.current):peek()):toBe(2)
					gui.SelectedObject = nil
					assert(outer.focus)(1)
					expect(gui.SelectedObject ~= nil):toBe(restore)
					stop()
					runtime:dispose()
				end
			end,
		})
	end)
end
