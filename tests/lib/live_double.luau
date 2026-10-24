--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Lute = require("../../tools/vendor/verify/src/lute")
local Project = require("../../tools/facet/lib/live_project")

type Check = { name: string, ok: boolean, detail: unknown? }
type Record = { checks: { Check }, notes: { [string]: unknown } }
type Context = { cleanup: () -> () }
type Case = { id: string, run: ((Context) -> ())?, probe: boolean? }
type Live = {
	context: (unknown, { unknown }, Record, Verify.Context?) -> Context,
	themes: (unknown) -> { unknown },
	cases: (string) -> { Case },
}
export type Descriptor = { id: string, automatic: boolean, interactive: boolean, probe: boolean }
export type Catalog = {
	sources: { { id: string, cases: { Descriptor } } },
	total: number,
	automatic: number,
	interactive: number,
	probes: number,
}

local PROJECT = "examples/.live-double.project.json"
local CACHE = Roblox.createPlaceCache(Lute.fixture.host)

local function open(check: Verify.Context, suites: { string }, sources: { [string]: string }?)
	local project = Lute.encode(Project.build(suites))
	local roots: { Roblox.Instance } = {}
	local snapshot = Lute.fixture.load()
	local bridge = Lute.fixture.bridge(snapshot, {
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
	local cache = if sources then Roblox.createPlaceCache(host) else CACHE
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
	local playerGui = assert(assert(runtime.localPlayer):FindFirstChild("PlayerGui"))
	table.insert(roots, playerGui)
	local input = Roblox.inputHost.simulated(bridge.environment, {
		playerGui = playerGui,
		inputService = engine.service("UserInputService"),
		layout = assert(bridge.layout),
		inset = function()
			return { X = 0, Y = 0 }
		end,
		library = Roblox.reflectionSnapshot.library(snapshot),
		activationWindowSeconds = 0.5,
		read = assert(bridge.ui).styled,
	})
	check:defer(input.close)
	runtime.globals.version = function(): string
		return "verify-engine-double"
	end
	local storage = engine.service("ReplicatedStorage")
	return { bridge = bridge, engine = engine, runtime = runtime, storage = storage }
end

local function run(check: Verify.Context, suite: string, id: string, sources: { [string]: string }?)
	local host = open(check, { suite }, sources)
	local bridge, engine, runtime, storage = host.bridge, host.engine, host.runtime, host.storage
	local record: Record = { checks = {}, notes = {} }
	local context: Context? = nil
	local done = false
	local probe = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = `live-double/{suite}/{id}` }, function()
		local live = runtime.requireInstance(storage:FindFirstChild("FacetLive")) :: Live
		local facet = runtime.requireInstance(storage:FindFirstChild("Facet")) :: {
			themes: { define: (unknown) -> unknown, neutralPackage: () -> unknown },
		}
		context = live.context(facet, live.themes(facet), record, check)
		local found = false
		for _, case in live.cases(suite) do
			if case.id == id then
				found = true
				probe = case.probe == true
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
	for _ = 1, 3600 do
		if done or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	check:expect(engine.diagnostics):toEqual({})
	check:expect(scheduler.failures):toEqual({})
	check:expect(done):toBe(true)
	check:expect(if probe then next(record.notes) ~= nil else #record.checks > 0):toBe(true)
	for _, result in record.checks do
		check:expect(result.ok):toBeTrueWith(result.name)
	end
end

local function catalog(check: Verify.Context): Catalog
	local plan = Lute.parse(Lute.fixture.host.readFile("tools/studio/live/plan.json")) :: {
		units: { { id: string, locator: string } },
	}
	local suites: { string } = {}
	for _, unit in plan.units do
		table.insert(suites, unit.id)
	end
	local host = open(check, suites)
	local live = host.runtime.requireInstance(host.storage:FindFirstChild("FacetLive")) :: {
		cases: (string) -> { { id: string, run: unknown?, setup: unknown?, probe: boolean? } },
	}
	local result: Catalog = { sources = {}, total = 0, automatic = 0, interactive = 0, probes = 0 }
	for _, unit in plan.units do
		local entries: { Descriptor } = {}
		for _, case in live.cases(unit.id) do
			result.total += 1
			result.automatic += if case.run then 1 else 0
			result.interactive += if case.setup then 1 else 0
			result.probes += if case.probe then 1 else 0
			table.insert(entries, {
				id = case.id,
				automatic = case.run ~= nil,
				interactive = case.setup ~= nil,
				probe = case.probe == true,
			})
		end
		check:expect(#entries > 0):toBeTrueWith(unit.id)
		table.insert(result.sources, { id = unit.id, cases = entries })
	end
	check:expect(host.engine.diagnostics):toEqual({})
	return result
end

return { run = run, open = open, catalog = catalog }
