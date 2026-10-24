--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Lute = require("../../tools/vendor/verify/src/lute")

type Check = { name: string, ok: boolean, detail: unknown? }
type Record = { checks: { Check }, notes: { [string]: unknown } }
type Context = { cleanup: () -> () }
type Case = { id: string, run: ((Context) -> ())? }
type Live = {
	context: (unknown, { unknown }, Record, Verify.Context?) -> Context,
	cases: (string) -> { Case },
}

local PROJECT = "build/live-double.project.json"
local project = Lute.encode({
	tree = {
		["$className"] = "DataModel",
		ReplicatedStorage = {
			["$className"] = "ReplicatedStorage",
			Facet = { ["$path"] = "../src" },
			FacetLive = { ["$path"] = "../tools/studio/live" },
			FacetVerify = { ["$path"] = "../tools/vendor/verify/src" },
		},
	},
})

local function run(check: Verify.Context, suite: string, id: string, sources: { [string]: string }?)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		handlerErrors = "raise",
		ui = {
			methods = {
				["GuiService.GetGuiInset"] = function()
					return Roblox.datatypes.Vector2.zero, Roblox.datatypes.Vector2.zero
				end,
			},
		},
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	check:defer(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local host = table.clone(Lute.fixture.host)
	host.readFile = function(path: string): string
		return if path == PROJECT
			then project
			elseif sources and sources[path] then sources[path]
			else Lute.fixture.host.readFile(path)
	end
	local cache = Roblox.createPlaceCache(host)
	local mounted = Roblox.buildPlaceTree(engine, PROJECT, { cache = cache, host = host, files = Lute.fixture.files })
	local runtime = Roblox.createPlaceRuntime(engine, mounted, {
		aliases = { repo = "" },
		cache = cache,
		host = host,
		client = { name = "LiveDouble", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	check:defer(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	local playerGui = assert(runtime.localPlayer):FindFirstChild("PlayerGui")
	table.insert(roots, assert(playerGui))
	runtime.globals.version = function(): string
		return "verify-engine-double"
	end
	local storage = engine.service("ReplicatedStorage")
	local record: Record = { checks = {}, notes = {} }
	local context: Context? = nil
	local done = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = `live-double/{suite}/{id}` }, function()
		local live = runtime.requireInstance(storage:FindFirstChild("FacetLive")) :: Live
		local facet = runtime.requireInstance(storage:FindFirstChild("Facet")) :: {
			themes: { define: (unknown) -> unknown, neutralPackage: () -> unknown },
		}
		context = live.context(
			facet,
			{ { name = "Neutral", package = facet.themes.define(facet.themes.neutralPackage()) } },
			record,
			check
		)
		local found = false
		for _, case in live.cases(suite) do
			if case.id == id then
				found = true
				assert(case.run, "interactive cases require a modeled input host")(assert(context))
			end
		end
		assert(found, `unknown live case {suite}/{id}`)
		done = true
	end)
	check:defer(function()
		scheduler.cancel(thread)
		if context then
			context.cleanup()
		end
	end)
	for _ = 1, 240 do
		if done or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	check:expect(engine.diagnostics):toEqual({})
	check:expect(scheduler.failures):toEqual({})
	check:expect(done):toBe(true)
	check:expect(#record.checks > 0):toBe(true)
	for _, result in record.checks do
		check:expect(result.ok):toBeTrueWith(result.name)
	end
end

return { run = run }
