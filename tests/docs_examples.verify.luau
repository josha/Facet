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
	harness:case(
		"the neon theme keeps repeated panels quiet while selected action emphasis follows one key",
		function(t)
			local loader = Loader.new()
			local Facet = (loader.require("src") :: unknown) :: FacetModule
			local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
			local source = string.gsub(
				Lute.fixture.host.readFile("skills/use-facet/assets/neon-circuit-theme.luau"),
				"local Facet = require%([^\n]+%)\n",
				""
			)
			local theme =
				Lute.chunk.load(source, { environment = { Facet = Facet }, name = "neon-theme" })() :: ThemePackage
			local engine = engines.new()
			local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
			local runtime = createRuntime(engine)
			t:defer(function()
				runtime:dispose()
			end)
			local app = Facet.app({
				runtime = runtime,
				types = engine.types,
				parent = engine.new("Folder"),
				theme = theme,
				motionLevel = "none",
			})
			t:defer(app.dispose)
			local UI, C = app.UI, Facet.Compose
			local selected = C.cell("first")
			local rows: { Frame } = {}
			local function row(key: string): Frame
				local frame = UI.VStack {
					surface = "panel",
					UI.Button(key) {
						label = key,
						selected = function(use)
							return use(selected) == key
						end,
						appearance = function(use): string
							return if use(selected) == key then "emphasis" else "utility"
						end,
					},
				}
				table.insert(rows, frame)
				return frame
			end
			app.mount(function()
				return UI.VStack { row("first"), row("second"), row("third") }
			end)
			for _, key in { "first", "third" } do
				selected:set(key)
				local accents = 0
				for _, frame in rows do
					for _, node in frame:GetDescendants() do
						if node:IsA("UIShadow") then
							t:expect(node.Enabled):toBe(false)
						end
						if node:HasTag("facet-accent") then
							accents += 1
							t:expect(node.Name):toBe(key)
						end
					end
				end
				t:expect(accents):toBe(1)
			end
		end
	)
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
	harness:case("hub pages and inspector execute together with a bounded Stage and cleanup", function(t)
		local loader = Loader.new()
		local Facet = (loader.require("src") :: unknown) :: FacetModule
		local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
		local engine = engines.new()
		local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
		local runtime = createRuntime(engine)
		local parent = engine.new("Folder")
		local app = Facet.app({
			runtime = runtime,
			types = engine.types,
			parent = parent,
			motionLevel = "none",
			suspendGameplay = true,
		})
		t:defer(function()
			app.dispose()
			runtime:dispose()
		end)
		local nodes = Index.load(".")
		local fragments: { string } = {}
		for _, name in { "Tasks.hub", "Tasks.pages", "Tasks.inspect" } do
			local body = assert(Index.find(nodes, name)).body
			local code = assert(string.match(body, "```luau\n(.-)\n```"))
			table.insert(fragments, (string.gsub(code, "local Facet = require%([^\n]+%)\n", "")))
		end
		local open: (() -> ())? = nil
		local sceneBuilds = 0
		local environment: { [string]: unknown } = {
			Facet = Facet,
			app = app,
			Enum = engine.types.Enum,
			UDim2 = engine.types.UDim2,
			Vector3 = engine.types.Vector3,
			CFrame = engine.types.CFrame,
			command = engine.new("InputAction"),
			saveOpen = function(callback: () -> ())
				open = callback
			end,
			sceneBuilt = function()
				sceneBuilds += 1
			end,
		}
		table.insert(
			fragments,
			[[
return function()
  local UI = app.UI
  return pages(app, "Workbench", function(openTasks)
    saveOpen(openTasks)
    return hub(app, "North ridge", "Pack equipped", "Begin expedition", command, function() end, openTasks)
  end, function()
    return inspect(app, function()
      return UI.Stage {
        Size = UDim2.fromScale(1, 1),
        camera = CFrame.lookAt(Vector3.new(0, 2, 6), Vector3.new(0, 0, 0)), fieldOfView = 35,
        content = function(runtime, world)
          sceneBuilt()
          local Host = Facet.host(runtime)
          Host.Part { Parent = Facet.Compose.static(world), Anchored = true, Size = Vector3.new(2, 2, 2) }
          return nil
        end,
      }
    end, function() return UI.Text { text = "Hard volcanic rock", wrap = true } end,
      "Basalt specimen", "Record in your journal", "Record specimen", function() end)
  end)
end
]]
		)
		local component = Lute.chunk.load(
			table.concat(fragments, "\n"),
			{ environment = environment, name = "composition-recipes" }
		)()
		app.mount(component :: () -> Child)
		t:expect(sceneBuilds):toBe(0)
		local actions = parent:FindFirstChild("Actions", true)
		assert(actions and actions.Parent)
		t:expect(actions.Parent.Name):toBe("BottomRight")
		local labels: { [string]: boolean } = {}
		for _, node in parent:GetDescendants() do
			if node:IsA("TextLabel") or node:IsA("TextButton") then
				labels[node.Text] = true
			end
		end
		t:expect(labels["Pack equipped"]):toBe(true)
		t:expect(labels["Begin expedition"]):toBe(true)
		t:expect(labels["Back"]):toBe(nil)
		assert(open)()
		t:expect(sceneBuilds):toBe(1)
		local terms = false
		for _, node in parent:GetDescendants() do
			if node:IsA("TextLabel") and node.Text == "Record in your journal" then
				terms = true
			end
		end
		t:expect(terms):toBe(true)
		app.dispose()
		t:expect(#parent:GetChildren()):toBe(0)
	end)

	harness:case("recipe declarations and control cards load through the public API", function(t)
		local loader = Loader.new()
		local Facet = (loader.require("src") :: unknown) :: FacetModule
		local engines = (loader.require("tests/lib/native_engine.luau") :: unknown) :: EngineLibrary
		local failures: { string } = {}
		for _, item in Index.load(".") do
			if item.kind ~= "card" and item.kind ~= "recipe" then
				continue
			end
			local engine = engines.new()
			local parent = engine.new("Folder")
			local createRuntime = (Facet.Roblox.createRuntime :: unknown) :: (unknown) -> Runtime
			local runtime = createRuntime(engine)
			local storage = engine.new("Folder")
			local purchase = engine.new("RemoteFunction")
			purchase.Name = "Purchase"
			purchase.Parent = storage
			local app = Facet.app({ runtime = runtime, types = engine.types, parent = parent, motionLevel = "none" })
			local code = assert(string.match(item.body, "```luau\n(.-)\n```"), item.path)
			local environment: { [string]: unknown } = {
				UI = app.UI,
				Facet = Facet,
				app = app,
				Compose = Facet.Compose,
				Vector2 = engine.types.Vector2,
				Vector3 = engine.types.Vector3,
				CFrame = engine.types.CFrame,
				Color3 = engine.types.Color3,
				Enum = engine.types.Enum,
				UDim2 = engine.types.UDim2,
				game = { ReplicatedStorage = storage },
			}
			local ok, failure = pcall(function()
				if item.kind == "card" then
					local last: number? = nil
					local cursor = 1
					while true do
						local at = string.find("\n" .. code, "\nUI%.", cursor)
						if at == nil then
							break
						end
						last = at
						cursor = at + 1
					end
					local tail = string.match(code, "[^\n]*$") or ""
					local start = last or #code - #tail + 1
					code = string.sub(code, 1, start - 1) .. "return " .. string.sub(code, start)
					local component = Lute.chunk.load(
						"return function()\n" .. code .. "\nend",
						{ environment = environment, name = item.path }
					)()
					app.mount(component :: () -> Child)
				else
					code = string.gsub(code, "local Facet = require%([^\n]+%)\n", "")
					code = string.gsub(code, "local app = Facet%.app%([^\n]+%)\n", "")
					code = string.gsub(code, "script%.Destroying:Connect%(app%.dispose%)", "")
					Lute.chunk.load(code, { environment = environment, name = item.path })()
				end
			end)
			app.dispose()
			runtime:dispose()
			if not ok then
				table.insert(failures, item.path .. ": " .. tostring(failure))
			end
		end
		t:expect(table.concat(failures, "\n")):toBe("")
	end)
end
