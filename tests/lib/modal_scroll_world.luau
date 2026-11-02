--!strict
local Facet = require("../../src")
local Compose = require("../../src/vendor/compose/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Lute = require("../../tools/vendor/verify/src/lute")
local engines = require("./native_engine")

type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

return function(kind: "Dialog" | "Sheet")
	local roots: { Roblox.Instance } = {}
	local engine, bridge = engines.new({
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	local data: DataModel = engine.new("DataModel")
	local player: PlayerGui = engine.new("PlayerGui")
	local input: UserInputService = engine.new("UserInputService")
	local gui: GuiService = engine.new("GuiService")
	player.Parent, input.Parent, gui.Parent = data, data, data
	table.insert(roots, Roblox.assertInstance(player))
	local env, T = engine.environment, engine.types
	env.fakeOn(gui, "GetInsetArea", function()
		return T.Rect.new(0, 0, 800, 600)
	end)
	local runtime: Runtime = Facet.Roblox.createRuntime(engine)
	local Host = Facet.host(runtime)
	local UI = Facet.controls(runtime, {
		types = T,
		motionLevel = "none",
		services = { UserInputService = input, GuiService = gui },
	})
	local open = Compose.cell(false)
	local list: ScrollingFrame? = nil
	local page: ScrollingFrame? = nil
	local stop = runtime.mount(function()
		local rows: Facet.ScrollViewProps = {
			Size = T.UDim2.fromOffset(180, 500),
			CanvasSize = T.UDim2.fromOffset(0, 1200),
			AutomaticCanvasSize = T.Enum.AutomaticSize.None,
			ScrollBarThickness = 0,
		}
		for index = 1, 18 do
			rows[index] = Host.TextLabel {
				Text = `Row {index}`,
				Size = T.UDim2.fromOffset(160, 60),
				Position = T.UDim2.fromOffset(0, (index - 1) * 64),
			}
		end
		list = UI.ScrollView "List"(rows)
		page = UI.ScrollView "Page" {
			Size = T.UDim2.fromScale(1, 1),
			CanvasSize = T.UDim2.fromOffset(0, 1200),
			AutomaticCanvasSize = T.Enum.AutomaticSize.None,
			ScrollBarThickness = 0,
			assert(list),
		}
		local spec = {
			isPresented = open,
			onPresentedChange = function() end,
			title = "Details",
			content = function()
				return UI.Text { text = "Details for the selected row" }
			end,
		}
		return Host.ScreenGui {
			ScreenInsets = T.Enum.ScreenInsets.None,
			ZIndexBehavior = T.Enum.ZIndexBehavior.Sibling,
			assert(page),
			if kind == "Dialog" then UI.Dialog(spec) else UI.Sheet(spec),
		}
	end, player)
	local backend = Roblox.inputHost.simulated(env, {
		playerGui = Roblox.assertInstance(player),
		inputService = Roblox.assertInstance(input),
		layout = assert(bridge.layout),
		inset = function()
			return { X = 0, Y = 0 }
		end,
		library = Roblox.reflectionSnapshot.library(Lute.fixture.load()),
		activationWindowSeconds = 0.5,
	})
	local inputObject = Roblox.assertInstance(input)
	local device = env.method(inputObject, "CreateVirtualInput")(inputObject)
	local virtual = env.assertObject(device)
	local function settle()
		for _ = 1, 60 do
			assert(bridge.layout).step()
			env.step(1 / 60)
		end
	end
	settle()
	return {
		open = open,
		list = assert(list),
		page = assert(page),
		settle = settle,
		scroll = function(touch: boolean)
			env.poke(inputObject, "TouchEnabled", touch)
			env.poke(inputObject, "MouseEnabled", not touch)
			if touch then
				local start, finish = T.Vector2.new(40, 400), T.Vector2.new(40, 220)
				env.method(virtual, "SendMousePosition")(virtual, start)
				env.method(virtual, "SendMouseButton")(virtual, start, T.Enum.UserInputType.MouseButton1, true)
				env.method(virtual, "SendMousePosition")(virtual, finish)
				env.method(virtual, "SendMouseButton")(virtual, finish, T.Enum.UserInputType.MouseButton1, false)
			else
				env.method(virtual, "SendPointerAction")(virtual, T.Vector2.new(40, 400), { Wheel = -1 })
			end
			settle()
		end,
		stop = function()
			backend.close()
			stop()
			runtime:dispose()
			bridge.close()
		end,
	}
end
