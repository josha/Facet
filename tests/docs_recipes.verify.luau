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
