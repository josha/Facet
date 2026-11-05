--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Index = require("../tools/facet/lib/docs_index")
local Lute = require("../tools/vendor/verify/src/lute")
local Loader = require("./lib/loader")
local Roblox = require("../tools/vendor/verify/src/roblox")
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type EngineLibrary = typeof(require("./lib/native_engine"))
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type ThemePackage = typeof(require("@repo/tools/typecheck/aliases").ThemePackage)

return function(harness: Verify.Harness)
	harness:case("collection recipe bounds long detail and retains selection across device sizes", function(t)
		local loader = Loader.new()
		local Facet = (loader.require("src") :: unknown) :: FacetModule
		local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
		local roots: { Roblox.Instance } = {}
		local viewport = { X = 1440, Y = 900 }
		local engine, bridge = engines.new({
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return viewport
				end,
			},
		})
		t:defer(function()
			bridge.close()
		end)
		local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
		local runtime = createRuntime(engine)
		t:defer(function()
			runtime:dispose()
		end)
		local player: PlayerGui = engine.new("PlayerGui")
		player.Parent = engine.new("DataModel")
		table.insert(roots, Roblox.assertInstance(player))
		local input: UserInputService = engine.new("UserInputService")
		local gui: GuiService = engine.new("GuiService")
		input.Parent, gui.Parent = player.Parent, player.Parent
		engine.environment.fakeOn(gui, "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, viewport.X, viewport.Y)
		end)
		engine.environment.poke(Roblox.assertInstance(input), "TouchEnabled", true)
		engine.environment.poke(Roblox.assertInstance(input), "MouseEnabled", false)
		local app = Facet.app({
			runtime = runtime,
			types = engine.types,
			parent = player,
			motionLevel = "none",
			services = { GuiService = gui, UserInputService = input },
		})
		t:defer(app.dispose)
		local backend = Roblox.inputHost.simulated(engine.environment, {
			playerGui = Roblox.assertInstance(player),
			inputService = Roblox.assertInstance(input),
			layout = assert(bridge.layout),
			inset = function()
				return { X = 0, Y = 0 }
			end,
			library = Roblox.reflectionSnapshot.library(Lute.fixture.load()),
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		t:defer(backend.close)
		local C, UI = Facet.Compose, app.UI
		local selected = C.cell({ record = true })
		local body = assert(Index.find(Index.load("."), "Tasks.collection-detail")).body
		local code = assert(string.match(body, "```luau\n(.-)\n```"))
		code = string.gsub(code, "local Facet = require%([^\n]+%)\n", "")
		local build = Lute.chunk.load(code .. "\n" .. [[
return function(app, selected)
  return browse(app, {{id = "record", name = "Archive record", terms = string.rep("Supporting detail. ", 2000)}},
    selected, function() return app.UI.ZStack { width = "fill", height = "fill" } end,
    "Record selection", function() end, Facet.Compose.cell(false))
end
]], { name = "bounded-collection-recipe", environment = { Facet = Facet, UDim2 = engine.types.UDim2 } })()
		app.mount(function()
			return UI.Screen {
				UI.Text { text = "Archive", textRole = "heading" },
				(build :: (unknown, unknown) -> Frame)(app, selected),
			}
		end)
		for _, size in
			{
				{ X = 1440, Y = 900 },
				{ X = 1024, Y = 768 },
				{ X = 844, Y = 390 },
				{ X = 740, Y = 280 },
				{ X = 390, Y = 844 },
				{ X = 1440, Y = 900 },
			}
		do
			viewport.X, viewport.Y = size.X, size.Y
			for _ = 1, 12 do
				assert(bridge.layout).step()
				engine.environment.step(1 / 60)
				engine.heartbeat:Fire(1 / 60)
			end
			local row = player:FindFirstChild("RowHit", true)
			assert(row and row:IsA("TextButton"))
			local point = row.AbsolutePosition + row.AbsoluteSize / 2
			backend.pointer({ x = point.X, y = point.Y, button = "left", down = true })
			backend.pointer({ x = point.X, y = point.Y, button = "left", down = false })
			assert(bridge.layout).step()
			local detail = player:FindFirstChild("SelectedDetail", true)
			assert(detail and detail:IsA("ScrollingFrame"))
			local geometry =
				`{viewport.X}x{viewport.Y}: position {detail.AbsolutePosition}, size {detail.AbsoluteSize}, canvas {detail.AbsoluteCanvasSize}, window {detail.AbsoluteWindowSize}`
			t:expect(detail.AbsoluteSize.Y > 0):toBeTrueWith(geometry)
			t:expect(detail.AbsolutePosition.Y >= 0):toBeTrueWith(geometry)
			t:expect(detail.AbsolutePosition.Y + detail.AbsoluteSize.Y <= viewport.Y):toBeTrueWith(geometry)
			t:expect(detail.AbsoluteCanvasSize.Y > detail.AbsoluteWindowSize.Y):toBeTrueWith(geometry)
			local preview = assert(detail:FindFirstChild("Preview", true))
			assert(preview:IsA("Frame"))
			t:expect(preview.AbsoluteSize.Y <= detail.AbsoluteWindowSize.Y * 0.36):toBeTrueWith(geometry)
			detail.CanvasPosition = engine.types.Vector2.new(0, detail.AbsoluteCanvasSize.Y)
			assert(bridge.layout).step()
			t:expect(detail.CanvasPosition.Y > 0):toBe(true)
			local action = detail:FindFirstChildWhichIsA("TextButton", true)
			assert(action)
			t:expect(
				action.AbsolutePosition.Y + action.AbsoluteSize.Y
					<= detail.AbsolutePosition.Y + detail.AbsoluteWindowSize.Y
			):toBeTrueWith(geometry)
			t:expect(selected:peek().record):toBe(true)
		end
	end)
	harness:case("HUD recipe omits resources unless the current task requests them", function(t)
		local loader = Loader.new()
		local Facet = (loader.require("src") :: unknown) :: FacetModule
		local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
		local engine = engines.new()
		local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
		local runtime = createRuntime(engine)
		t:defer(function()
			runtime:dispose()
		end)
		local app = Facet.app({ runtime = runtime, types = engine.types, parent = engine.new("Folder") })
		t:defer(app.dispose)
		local body = assert(Index.find(Index.load("."), "Tasks.hud")).body
		local code = assert(string.match(body, "```luau\n(.-)\n```"))
		code = string.gsub(code, "local Facet = require%([^\n]+%)\n", "")
		local build = Lute.chunk.load(code .. "\n" .. [[
return function(app, show)
  local state = Facet.Compose.cell("Ready")
  return hud(app, state, state, if show then state else nil, "Use", command, function() end)
end
]], { name = "minimal-hud", environment = { Facet = Facet, command = engine.new("InputAction") } })() :: (unknown, boolean) -> Frame
		for _, show in { false, true } do
			local stop, screen = app.mount(function()
				return build(app, show)
			end)
			t:expect(screen:FindFirstChild("Resource", true) ~= nil):toBe(show)
			t:expect(screen:FindFirstChild("Objective", true) ~= nil):toBe(true)
			t:expect(screen:FindFirstChild("Command", true) ~= nil):toBe(true)
			stop()
		end
	end)
	harness:case("appearance recipe shrinks the subject and scrolls the palette in short room", function(t)
		local loader = Loader.new()
		local Facet = (loader.require("src") :: unknown) :: FacetModule
		local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
		local roots: { Roblox.Instance } = {}
		local viewport = { X = 740, Y = 280 }
		local engine, bridge = engines.new({
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return viewport
				end,
			},
		})
		t:defer(function()
			bridge.close()
		end)
		local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
		local runtime = createRuntime(engine)
		t:defer(function()
			runtime:dispose()
		end)
		local player: PlayerGui = engine.new("PlayerGui")
		table.insert(roots, Roblox.assertInstance(player))
		local app = Facet.app({ runtime = runtime, types = engine.types, parent = player, motionLevel = "none" })
		t:defer(app.dispose)
		local body = assert(Index.find(Index.load("."), "Tasks.appearance")).body
		local code = assert(string.match(body, "```luau\n(.-)\n```"))
		code = string.gsub(code, "local Facet = require%([^\n]+%)\n", "")
		local build = Lute.chunk.load(code .. "\n" .. [[
return function(app)
  return appearance(app, Facet.Compose.cell(Color3.new(1, 0, 0)), {
    {label = "Red", color = Color3.new(1, 0, 0)},
    {label = "Blue", color = Color3.new(0, 0, 1)},
  })
end
]], {
			name = "short-appearance",
			environment = {
				Facet = Facet,
				UDim2 = engine.types.UDim2,
				Color3 = engine.types.Color3,
				Vector3 = engine.types.Vector3,
				CFrame = engine.types.CFrame,
			},
		})()
		app.mount(function()
			return (build :: (unknown) -> Frame)(app)
		end)
		for _, size in { { X = 740, Y = 280 }, { X = 390, Y = 600 }, { X = 390, Y = 180 } } do
			viewport.X, viewport.Y = size.X, size.Y
			for _ = 1, 12 do
				assert(bridge.layout).step()
			end
			local stage = assert(player:FindFirstChild("Subject", true))
			assert(stage:IsA("ViewportFrame"))
			t:expect(stage.AbsoluteSize.Y <= viewport.Y * 0.36):toBe(true)
			local scroll = assert(player:FindFirstChildWhichIsA("ScrollingFrame", true))
			t:expect(scroll.AbsoluteSize.Y <= viewport.Y):toBe(true)
			scroll.CanvasPosition = engine.types.Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
			assert(bridge.layout).step()
			local picker = assert(scroll:FindFirstChild("ColorPicker", true))
			assert(picker:IsA("GuiObject"))
			t:expect(picker.AbsolutePosition.Y + picker.AbsoluteSize.Y <= viewport.Y):toBe(true)
		end
	end)
end
