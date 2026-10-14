--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local function world(options: { [string]: any }?, distant: boolean?)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		local T = engine.types
		gui.GetGuiInset = function()
			return T.Vector2.zero, T.Vector2.zero
		end
		input.MouseEnabled = not distant
		if distant then
			gui.ViewportDisplaySize = T.Enum.DisplaySize.Large
		end
		local config: { [string]: any } = {
			types = T,
			guiService = gui,
			userInputService = input,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {} :: { [string]: any }) do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config)
		local function dock(distant: boolean)
			gui.ViewportDisplaySize = if distant then T.Enum.DisplaySize.Large else T.Enum.DisplaySize.Medium
			input.MouseEnabled = not distant
		end
		local function mount(body: () -> any): any
			local root: any
			runtime.mount(function()
				root = body()
				return root
			end, engine.new("ScreenGui"))
			return root
		end
		return { engine = engine, runtime = runtime, UI = UI, T = T, dock = dock, mount = mount, gui = gui }
	end

	verifyHarness:suite("ten-foot controls follow the distance fact", function()
		verifyHarness:case("a control takes the ladder at ten feet, and follows a live preview of the distance", {
			id = "native_ten_foot::ten-foot controls follow the distance fact::a control takes the ladder at ten feet, and follows a live preview of the distance",
			run = function()
				local w = world({ theme = assert(themes.define({ identity = { id = "live" } } :: any)) })
				local button = w.mount(function()
					return w.UI.Button { label = "Play" }
				end)
				local stack = w.mount(function()
					return w.UI.VStack { gap = "m", w.UI.Text { text = "A" } }
				end)
				local list = stack:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(button.Size.Y.Offset):toBe(44)
				Verify.expect(list.Padding.Offset):toBe(16)
				w.runtime:dispose()
				local display = Compose.cell("Medium")
				local live = world({
					theme = Compose.cell(assert(themes.define({ identity = { id = "live-cell" } } :: any))),
					environment = { displaySize = display },
				})
				live.dock(true)
				display:set("Medium")
				local docked = live.mount(function()
					return live.UI.Button { label = "Play" }
				end)
				Verify.expect(docked.Size.Y.Offset):toBe(44)
				display:set("Large")
				Verify.expect(docked.Size.Y.Offset):toBe(66)
				display:set("Small")
				Verify.expect(docked.Size.Y.Offset):toBe(44)
				live.runtime:dispose()
				local bare = world(nil, true)
				local distant = bare.mount(function()
					return bare.UI.VStack { gap = "m", bare.UI.Button { label = "Play" } }
				end)
				Verify.expect(distant:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(24)
				Verify.expect(distant:FindFirstChildWhichIsA("TextButton").Size.Y.Offset):toBe(66)
				bare.runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("ten-foot overscan margins on a Screen", function()
		verifyHarness:case("insets a Screen by the console proportion at ten feet and not near", {
			id = "native_ten_foot::ten-foot overscan margins on a Screen::insets a Screen by the console proportion at ten feet and not near",
			run = function()
				local near = world()
				local screen = near.mount(function()
					return near.UI.Screen {}
				end)
				Verify.expect(screen:FindFirstChildWhichIsA("UIPadding").PaddingLeft):toBe(near.T.UDim.new(0, 16))
				near.runtime:dispose()
				local w = world(nil, true)
				local padding = w.mount(function()
					return w.UI.Screen {}
				end):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft):toBe(w.T.UDim.new(90 / 1920, 24))
				Verify.expect(padding.PaddingTop):toBe(w.T.UDim.new(60 / 1080, 24))
				w.runtime:dispose()
			end,
		})
	end)
end
