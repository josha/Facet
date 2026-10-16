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
	harness:case("every recipe and control card mounts through the public API", function(t)
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
			local app = Facet.app({ runtime = runtime, types = engine.types, parent = parent, motionLevel = "none" })
			local code = assert(string.match(item.body, "```luau\n(.-)\n```"), item.path)
			local environment: { [string]: unknown } = {
				UI = app.UI,
				Facet = Facet,
				app = app,
				Compose = Facet.Compose,
				Vector2 = engine.types.Vector2,
				Color3 = engine.types.Color3,
				Enum = engine.types.Enum,
				UDim2 = engine.types.UDim2,
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
