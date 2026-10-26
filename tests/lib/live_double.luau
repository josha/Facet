--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Lute = require("../../tools/vendor/verify/src/lute")
local Project = require("../../tools/facet/lib/live_project")

type Check = { name: string, ok: boolean, detail: unknown? }
type Record = { checks: { Check }, notes: { [string]: unknown } }
type Context = { cleanup: () -> () }
type InteractiveStep = { name: string, status: string, message: string? }
type InteractiveResult = { id: string, status: string, failures: unknown?, steps: { InteractiveStep }? }
type InteractiveReport = { results: { InteractiveResult } }
type Drive = (unknown, string, { [string]: unknown }) -> InteractiveReport
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
	local placed: Roblox.PlaceRuntime? = nil
	local snapshot = Lute.fixture.load()
	local bridge = Lute.fixture.bridge(snapshot, {
		handlerErrors = "raise",
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				local viewport = assert(placed).device().viewport
				return { X = viewport[1], Y = viewport[2] }
			end,
			screenArea = function(screen: Roblox.Instance)
				return assert(placed).screenArea(screen)
			end,
		},
	})
	local library = Roblox.reflectionSnapshot.library(snapshot)
	bridge.environment.fake("ScrollingFrame.GetScrollVelocity", function()
		return library.Vector2.zero
	end)
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
	placed = runtime
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
			local inset = runtime.device().guiInset
			return { X = inset[1], Y = inset[2] }
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
	for _, suite in suites do
		local suiteSource = Lute.fixture.host.readFile(`tools/studio/live/suites/{suite}.luau`)
		if
			string.find(suiteSource, "FacetShowcaseAPI", 1, true) or string.find(suiteSource, "FacetGallery", 1, true)
		then
			runtime.runScript(assert(storage:FindFirstChild("Gallery")), "client")
			break
		end
	end
	return { bridge = bridge, engine = engine, runtime = runtime, storage = storage }
end

local function run(check: Verify.Context, suite: string, id: string, sources: { [string]: string }?)
	local host = open(check, { suite }, sources)
	local bridge, engine, runtime, storage = host.bridge, host.engine, host.runtime, host.storage
	local record: Record = { checks = {}, notes = {} }
	local context: Context? = nil
	local done = false
	local probe = false
	local interactive: InteractiveReport? = nil
	local source = Lute.fixture.host.readFile("tools/studio/live/interactive.luau")
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
				if case.run then
					case.run(assert(context))
				else
					local drive = Lute.chunk.load(source, { environment = runtime.globals })() :: Drive
					local options: { [string]: unknown } = { only = id, device = "keep" }
					local ok, result = xpcall(drive, debug.traceback, live, suite, options)
					check:expect(ok):toBeTrueWith(tostring(result))
					interactive = if ok then result :: InteractiveReport else nil
				end
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
	check
		:expect(done)
		:toBeTrueWith(
			string.format("the case did not finish: %s %s", coroutine.status(thread), debug.traceback(thread))
		)
	if interactive then
		check:expect(#interactive.results > 0):toBeTrueWith(string.sub(Lute.encode(interactive), 1, 1500))
		for _, result in interactive.results do
			local steps: { InteractiveStep } = result.steps or {}
			for _, step in steps do
				check:expect(step.status == "passed"):toBeTrueWith(`{result.id}: {step.name}: {tostring(step.message)}`)
			end
			check:expect(result.status == "passed"):toBeTrueWith(`{result.id}: {result.status}`)
		end
		return
	end
	check:expect(if probe then next(record.notes) ~= nil else #record.checks > 0):toBe(true)
	for _, result in record.checks do
		check
			:expect(result.ok)
			:toBeTrueWith(if result.detail == nil then result.name else `{result.name}: {Lute.encode(result.detail)}`)
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
