--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Index = require("../tools/facet/lib/docs_index")
local Lute = require("../tools/vendor/verify/src/lute")
local Loader = require("./lib/loader")
type FacetModule = typeof(require("@repo/tools/typecheck/aliases").FacetModule)
type EngineLibrary = typeof(require("./lib/native_engine"))
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)

return function(harness: Verify.Harness)
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
		assert(open)()
		t:expect(sceneBuilds):toBe(1)
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
					assert(last, item.path)
					code = string.sub(code, 1, last - 1) .. "return " .. string.sub(code, last)
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
