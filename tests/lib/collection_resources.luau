--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")
local Facet = require("../../src")
local Collections = require("../../src/ui/collection_types")
local Props = require("../../src/ui/collection_props")
local EngineTypes = require("../../src/ui/engine_types")
local engineLib = require("./native_engine")
local Compose = Facet.Compose

local function setup()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local Host = (runtime.constructors :: unknown) :: EngineTypes.Host
	local target = (engine.new("ScreenGui") :: unknown) :: ScreenGui
	local gui = (engine.new("GuiService") :: unknown) :: GuiService
	local input = (engine.new("UserInputService") :: unknown) :: UserInputService
	for _, name in { "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState", "GetNavigationGamepads" } do
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), name, function()
			return {}
		end)
	end
	engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "IsGamepadButtonDown", function()
		return false
	end)
	engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetLastInputType", function()
		return engine.types.Enum.UserInputType.Keyboard
	end)
	local UI = Facet.controls(runtime, {
		types = engine.types,
		guiService = gui,
		userInputService = input,
		inputParent = target,
		services = { GuiService = gui, UserInputService = input },
		motionLevel = "none",
	})
	return engine, runtime, Host, UI, target, gui, input
end

return function(harness: Verify.Harness)
	harness:case("native_collections::native selection captures a child added after the row mounts", function(t)
		local engine, runtime, Host, UI, target, gui = setup()
		t:defer(function()
			runtime:dispose()
		end)
		local shown = Compose.cell(false)
		local focus: Collections.FocusControls<number> = {}
		local otherUI = Facet.controls(runtime, { types = engine.types, guiService = gui, inputParent = target })
		local stop, mounted = runtime.mount(function()
			local first: Props.KeyedCollectionSpec<number, number> = {
				from = {},
				key = function(item: number): number
					return item
				end,
				render = function(): GuiObject
					return Host.Frame {}
				end,
			}
			local empty = UI.VirtualList(first)
			local spec: Props.KeyedCollectionSpec<number, number> = {
				from = { 1, 2, 3 },
				key = function(item: number): number
					return item
				end,
				mode = "all",
				measure = false,
				focus = focus,
				render = function(): GuiObject
					return Host.Frame {
						Size = engine.types.UDim2.fromScale(1, 1),
						Compose.show(shown, function(): TextButton
							return Host.TextButton "LateAction" { Selectable = true }
						end),
					}
				end,
			}
			return Host.Frame { empty, otherUI.VirtualList(spec) }
		end, target)
		local list = (mounted :: unknown) :: Instance
		shown:set(true)
		local second = assert(assert(list:FindFirstChild("2", true)):FindFirstChild("LateAction", true))
		assert(second:IsA("GuiObject"))
		t:expect(engine.environment.signalOf(VerifyRoblox.assertInstance(second), "SelectionGained").connections())
			:toBe(0)
		gui.SelectedObject = second
		t:expect(assert(focus.current):peek()):toBe(2)
		assert(focus.next)()
		local third = assert(list:FindFirstChild("3", true)):FindFirstChild("LateAction", true)
		t:expect(gui.SelectedObject):toBe(third)
		stop()
		runtime:dispose()
		t:expect(engine.census().connections):toBe(0)
	end)
	harness:case(
		"native_collections::fixed table columns keep bounded widths without duplicate native modifiers",
		function(t)
			local engine, runtime, Host, UI, target = setup()
			t:defer(function()
				runtime:dispose()
			end)
			local widths = Compose.cell({} :: { [string]: number })
			local stop, mounted = runtime.mount(function()
				local spec: Props.KeyedTableSpec<number, number> = {
					from = { 1, 2 },
					key = function(item: number): number
						return item
					end,
					mode = "all",
					widths = widths,
					columns = {
						{
							id = "label",
							width = 120,
							render = function(current): GuiObject
								return Host.TextLabel { Text = tostring(current:peek()) }
							end,
						},
					},
				}
				return UI.Table(spec)
			end, target)
			local tableNode = (mounted :: unknown) :: Instance
			local header = assert(tableNode:FindFirstChild("Header"))
			local cell = assert(assert(tableNode:FindFirstChild("Row", true)):FindFirstChild("label"))
			local heading = assert(header:FindFirstChild("label"))
			assert(cell:IsA("GuiObject") and heading:IsA("GuiObject"))
			for _, node in { heading, cell } do
				t:expect(node:FindFirstChildWhichIsA("UISizeConstraint")):toBeNil()
				t:expect(node:FindFirstChildWhichIsA("UIFlexItem")):toBeNil()
				t:expect(node.Size.X.Offset):toBe(120)
			end
			widths:set({ label = 20 })
			t:expect(cell.Size.X.Offset):toBe(48)
			t:expect(heading.Size):toBe(cell.Size)
			widths:set({ label = 200 })
			t:expect(cell.Size.X.Offset):toBe(200)
			t:expect(heading.Size):toBe(cell.Size)
			stop()
			runtime:dispose()
			t:expect(engine.census().connections):toBe(0)
		end
	)
	harness:case("native_collections::touch hold connections follow the pending contact", function(t)
		local engine, runtime, Host, UI, target, _, input = setup()
		t:defer(function()
			runtime:dispose()
		end)
		local E, V3 = engine.types.Enum, engine.types.Vector3
		engine.environment.poke(VerifyRoblox.assertInstance(input), "PreferredInput", E.PreferredInput.Touch)
		local stop, mounted = runtime.mount(function()
			local spec: Props.KeyedCollectionSpec<number, number> = {
				from = { 1, 2, 3 },
				key = function(item: number): number
					return item
				end,
				mode = "all",
				reorderable = true,
				editing = false,
				onReorder = function() end,
				render = function(): GuiObject
					return Host.Frame { Size = engine.types.UDim2.fromScale(1, 1) }
				end,
			}
			return UI.VirtualList(spec)
		end, target)
		local list = (mounted :: unknown) :: Instance
		local second = assert(list:FindFirstChild("2", true))
		local row = assert(second:FindFirstChild("Reorderable", true))
		local other = assert(assert(list:FindFirstChild("3", true)):FindFirstChild("Reorderable", true))
		local signal = engine.environment.signalOf(VerifyRoblox.assertInstance(row), "TouchLongPress")
		local idle = engine.environment.signalOf(VerifyRoblox.assertInstance(other), "TouchLongPress")
		t:expect(signal.connections()):toBe(0)
		t:expect(idle.connections()):toBe(0)
		local hit = VerifyRoblox.assertInstance(assert(second:FindFirstChild("RowHit", true)))
		local contact = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) }
		engine.environment.fire(hit, "InputBegan", contact)
		t:expect(signal.connections()):toBe(1)
		t:expect(idle.connections()):toBe(0)
		engine.environment.fire(VerifyRoblox.assertInstance(input), "InputEnded", contact)
		t:expect(signal.connections()):toBe(0)
		engine.environment.fire(hit, "InputBegan", contact)
		t:expect(signal.connections()):toBe(1)
		stop()
		t:expect(signal.connections()):toBe(0)
	end)
end
