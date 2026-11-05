--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Roblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	local function mount(nested: boolean)
		local roots: { Roblox.Instance } = {}
		local viewport = { X = 390, Y = 844 }
		local engine, bridge = engineLib.new({
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return viewport
				end,
			},
		})
		local T, C = engine.types, Facet.Compose
		local player: PlayerGui = engine.new("PlayerGui")
		player.Parent = engine.new("DataModel")
		table.insert(roots, Roblox.assertInstance(player))
		local input: UserInputService = engine.new("UserInputService")
		local gui: GuiService = engine.new("GuiService")
		input.Parent, gui.Parent = player.Parent, player.Parent
		engine.environment.poke(Roblox.assertInstance(input), "TouchEnabled", true)
		gui.TouchControlsEnabled = false
		engine.environment.fakeOn(gui, "GetInsetArea", function()
			return T.Rect.new(0, 0, viewport.X, viewport.Y)
		end)
		local native: ScreenGui = engine.new("ScreenGui")
		native.Name, native.Enabled, native.Parent = "TouchGui", false, player
		local runtime = Facet.Roblox.createRuntime(engine)
		local Host = runtime.constructors
		local reservations = C.cell<<{ Facet.TouchReservation }>>({})
		local capture = C.cell<<(Rect | GuiObject)?>>(nil)
		local app = Facet.app({
			runtime = runtime,
			types = T,
			parent = player,
			motionLevel = "none",
			touchReservations = reservations,
			services = { UserInputService = input, GuiService = gui },
		})
		local UI = app.UI
		local stick: GuiObject? = nil
		local chat: GuiObject? = nil
		local prompt: GuiObject? = nil
		local screen: GuiObject? = nil
		app.mount(function()
			stick = UI.Button "HostStick" {
				label = "Move",
				Size = T.UDim2.fromOffset(140, 140),
				Position = T.UDim2.new(0, 12, 1, -152),
			}
			chat = UI.Text { text = "Chat ready", textRole = "body" }
			prompt = UI.Button { label = "Interact" }
			local composition = UI.Composition "HUD" {
				padding = 8,
				topbar = false,
				UI.Region "Chat" { zone = "bottomLeft", rank = 1, chat },
				UI.Region "Prompt" { zone = "bottomRight", rank = 1, prompt },
			}
			local surface: GuiObject = composition
			if nested then
				screen = UI.Screen { padding = 0, composition }
				surface = assert(screen)
			end
			return Host.Frame { Size = T.UDim2.fromScale(1, 1), stick, surface }
		end)
		local function settle()
			for _ = 1, 12 do
				assert(bridge.layout).step()
				engine.environment.step(1 / 60)
				engine.heartbeat:Fire(1 / 60)
			end
		end
		local function bottom(node: GuiObject): number
			return node.AbsolutePosition.Y + node.AbsoluteSize.Y
		end
		return {
			engine = engine,
			T = T,
			player = player,
			input = input,
			gui = gui,
			native = native,
			viewport = viewport,
			reservations = reservations,
			capture = capture,
			stick = assert(stick),
			chat = assert(chat),
			prompt = assert(prompt),
			screen = screen,
			settle = settle,
			bottom = bottom,
			close = function()
				app.dispose()
				runtime:dispose()
				player:Destroy()
				bridge.close()
			end,
		}
	end

	for _, nested in { false, true } do
		harness:case(`host GuiObject reservations clear chat and prompts with nested Screen {nested}`, function(t)
			local w = mount(nested)
			t:defer(w.close)
			w.reservations:set({ w.stick })
			for _, size in { { X = 390, Y = 844 }, { X = 844, Y = 390 } } do
				w.viewport.X, w.viewport.Y = size.X, size.Y
				for _, textSize in { w.T.Enum.PreferredTextSize.Medium, w.T.Enum.PreferredTextSize.Largest } do
					w.engine.environment.poke(Roblox.assertInstance(w.gui), "PreferredTextSize", textSize)
					w.settle()
					t:expect(w.chat.AbsoluteSize.Y > 0):toBe(true)
					t:expect(w.prompt.AbsoluteSize.Y > 0):toBe(true)
					t:expect(w.bottom(w.chat) <= w.stick.AbsolutePosition.Y):toBe(true)
					t:expect(w.bottom(w.prompt) <= w.stick.AbsolutePosition.Y):toBe(true)
					if w.screen then
						local padding = w.screen:FindFirstChildWhichIsA("UIPadding")
						assert(padding)
						t:expect(padding.PaddingBottom.Offset):toBe(152)
						t:expect(w.stick.AbsolutePosition.Y - w.bottom(w.prompt) < 24):toBe(true)
					end
				end
			end
			w.stick.Size = w.T.UDim2.fromOffset(140, 180)
			w.stick.Position = w.T.UDim2.new(0, 12, 1, -192)
			w.settle()
			t:expect(w.bottom(w.prompt) <= w.stick.AbsolutePosition.Y):toBe(true)
			w.reservations:set({})
			w.settle()
			t:expect(w.bottom(w.prompt) > w.stick.AbsolutePosition.Y):toBe(true)
		end)
	end

	harness:case("reactive Rect reservations resize, disappear and combine with native controls", function(t)
		local w = mount(false)
		t:defer(w.close)
		w.reservations:set({ w.capture })
		for _, size in { { X = 390, Y = 844 }, { X = 844, Y = 390 } } do
			w.viewport.X, w.viewport.Y = size.X, size.Y
			w.capture:set(w.T.Rect.new(12, size.Y - 200, 152, size.Y - 12))
			w.settle()
			t:expect(w.bottom(w.chat) <= size.Y - 200):toBe(true)
			t:expect(w.bottom(w.prompt) <= size.Y - 200):toBe(true)
			w.capture:set(w.T.Rect.new(12, size.Y - 100, 152, size.Y - 12))
			w.settle()
			t:expect(w.bottom(w.prompt) > size.Y - 200):toBe(true)
			t:expect(w.bottom(w.prompt) <= size.Y - 100):toBe(true)
		end
		w.native.Enabled, w.gui.TouchControlsEnabled = true, true
		local jump: TextButton = w.engine.new("TextButton")
		jump.Name, jump.Size, jump.Position, jump.Parent =
			"JumpButton", w.T.UDim2.fromOffset(70, 70), w.T.UDim2.new(1, -90, 1, -160), w.native
		w.settle()
		t:expect(w.bottom(w.prompt) <= jump.AbsolutePosition.Y):toBe(true)
		w.capture:set(w.T.Rect.new(12, w.viewport.Y - 240, 152, w.viewport.Y - 12))
		w.settle()
		t:expect(w.bottom(w.prompt) <= w.viewport.Y - 240):toBe(true)
		w.capture:set(nil)
		w.settle()
		t:expect(w.bottom(w.prompt) > w.viewport.Y - 240):toBe(true)
		t:expect(w.bottom(w.prompt) <= jump.AbsolutePosition.Y):toBe(true)
	end)

	harness:case("GuiObject reservations follow visibility, ancestry, layer state and touch availability", function(t)
		local w = mount(false)
		t:defer(w.close)
		w.reservations:set({ w.stick })
		w.settle()
		local reservedBottom = w.bottom(w.prompt)
		local parent = assert(w.stick.Parent)
		w.stick.Visible = false
		w.settle()
		t:expect(w.bottom(w.prompt) > reservedBottom):toBe(true)
		w.stick.Visible = true
		w.settle()
		t:expect(w.bottom(w.prompt)):toBe(reservedBottom)
		w.stick.Parent = nil
		w.settle()
		t:expect(w.bottom(w.prompt) > reservedBottom):toBe(true)
		w.stick.Parent = parent
		w.settle()
		t:expect(w.bottom(w.prompt)):toBe(reservedBottom)
		w.engine.environment.poke(Roblox.assertInstance(w.input), "TouchEnabled", false)
		w.settle()
		t:expect(w.bottom(w.prompt) > reservedBottom):toBe(true)
		w.engine.environment.poke(Roblox.assertInstance(w.input), "TouchEnabled", true)
		w.settle()
		t:expect(w.bottom(w.prompt)):toBe(reservedBottom)
		local layer: ScreenGui = w.engine.new("ScreenGui")
		layer.IgnoreGuiInset, layer.Parent = true, w.player
		w.stick.Parent = layer
		w.settle()
		t:expect(w.bottom(w.prompt)):toBe(reservedBottom)
		layer.Enabled = false
		w.settle()
		t:expect(w.bottom(w.prompt) > reservedBottom):toBe(true)
		layer.Enabled = true
		w.settle()
		t:expect(w.bottom(w.prompt)):toBe(reservedBottom)
		w.stick:Destroy()
		w.settle()
		t:expect(w.bottom(w.prompt) > reservedBottom):toBe(true)
	end)
end
