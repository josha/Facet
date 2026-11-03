--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Lute = require("../../tools/vendor/verify/src/lute")
local Project = require("../../tools/facet/lib/live_project")

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
local LAB_CLIENT = "DataModel.ReplicatedStorage.Lab.client"

type Diagnostic = { kind: string, text: string, source: string }

local function unexpected(diagnostics: { Diagnostic }): { Diagnostic }
	local kept: { Diagnostic } = {}
	for _, diagnostic in diagnostics do
		if not (diagnostic.kind == "print" and diagnostic.source == LAB_CLIENT) then
			table.insert(kept, diagnostic)
		end
	end
	return kept
end
local RUN = [==[
local storage, suite, id, check, loadDrive, device, hooks = ...
local live = require(storage:FindFirstChild("FacetLive"))
if device then
 local simulator = game:GetService("StudioDeviceSimulatorService")
 simulator:SetDeviceAsync(device)
 simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
end
for _, case in live.cases(suite) do
 if case.id ~= id then continue end
 if case.run then
  return game:GetService("HttpService"):JSONEncode(live.report(suite, {ids = {id}, device = "keep"}))
 end
 return live.case(suite, id, function()
   local report = loadDrive()(live, suite, {
    only = id,
    device = "keep",
    connectGamepad = hooks.connectGamepad,
    disconnectGamepad = hooks.disconnectGamepad,
   })
   check:expect(#report.results > 0):toBe(true)
   for _, result in report.results do
    for _, step in result.steps or {} do
     check:expect(step.status == "passed"):toBeTrueWith(`{result.id}: {step.name}: {tostring(step.message)}`)
    end
    check:expect(result.status == "passed"):toBeTrueWith(`{result.id}: {result.status}`)
   end
 end)
end
error(`unknown live case {suite}/{id}`)
]==]

local function open(check: Verify.Context, suites: { string }, sources: { [string]: string }?, controller: boolean?)
	local project = Lute.encode(Project.build(suites))
	local roots: { Roblox.Instance } = {}
	local placed: Roblox.PlaceRuntime? = nil
	local snapshot = Lute.fixture.load()
	local bridge = Lute.fixture.bridge(snapshot, {
		handlerErrors = "raise",
		ui = { selection = "native" },
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
	bridge.environment.fake("ContentProvider.GetAssetFetchStatus", function()
		return library.Enum.AssetFetchStatus.None
	end)
	bridge.environment.fake("ScrollingFrame.GetScrollVelocity", function()
		return library.Vector2.zero
	end)
	check:defer(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local base = Lute.fixture.host
	local host: typeof(base) = {
		readFile = function(path: string): string
			return if path == PROJECT
				then project
				elseif sources and sources[path] then sources[path]
				else base.readFile(path)
		end,
		compile = base.compile,
		load = base.load,
		encodeJson = base.encodeJson,
		decodeJson = base.decodeJson,
	}
	local cache = if sources then Roblox.createPlaceCache(host) else CACHE
	local fixtureFiles = Lute.fixture.files
	local mounted = Roblox.buildPlaceTree(engine, PROJECT, {
		cache = cache,
		host = host,
		files = {
			exists = fixtureFiles.exists,
			fileType = fixtureFiles.fileType,
			listDirectory = fixtureFiles.listDirectory,
		},
	})
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
		virtualController = controller,
		read = assert(bridge.ui).styled,
	})
	check:defer(input.close)
	runtime.globals.version = function(): string
		return "verify-engine-double"
	end
	local storage = engine.service("ReplicatedStorage")
	if table.find(suites, "lab") then
		runtime.runScript(assert(assert(storage:FindFirstChild("Lab")):FindFirstChild("client")), "client")
	end
	for _, suite in suites do
		local suiteSource = Lute.fixture.host.readFile(`tools/studio/live/suites/{suite}.luau`)
		if
			string.find(suiteSource, "FacetShowcaseAPI", 1, true) or string.find(suiteSource, "FacetGallery", 1, true)
		then
			runtime.runScript(assert(storage:FindFirstChild("Gallery")), "client")
			break
		end
	end
	return { bridge = bridge, engine = engine, runtime = runtime, storage = storage, input = input }
end

local function run(
	check: Verify.Context,
	suite: string,
	id: string,
	sources: { [string]: string }?,
	controller: boolean?,
	device: string?
)
	local deadline = os.clock() + math.min(590, check:remainingSeconds())
	local host = open(check, { suite }, sources, controller)
	local bridge, engine, runtime, storage = host.bridge, host.engine, host.runtime, host.storage
	local hooks = { connectGamepad = host.input.connectGamepad, disconnectGamepad = host.input.disconnectGamepad }
	local report: Verify.Report? = nil
	local source = Lute.fixture.host.readFile("tools/studio/live/interactive.luau")
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = `live-double/{suite}/{id}` }, function()
		local encoded = Lute.chunk.load(RUN, { environment = runtime.globals })(storage, suite, id, check, function()
			return Lute.chunk.load(source, { environment = runtime.globals })()
		end, device, hooks)
		assert(type(encoded) == "string")
		report = Lute.decode(encoded)
	end)
	check:defer(function()
		scheduler.cancel(thread)
	end)
	while os.clock() < deadline do
		if report or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	check:expect(unexpected(engine.diagnostics)):toEqual({})
	check:expect(scheduler.failures):toEqual({})
	check
		:expect(report ~= nil)
		:toBeTrueWith(
			string.format("the case did not finish: %s %s", coroutine.status(thread), debug.traceback(thread))
		)
	local complete = assert(report)
	check:expect(complete.total == 1 and complete.results[1].id == id):toBe(true)
	for _, step in complete.results[1].steps do
		pcall(function()
			check:step(step.name, function()
				check:expect(step.status == "passed"):toBeTrueWith(`{step.name}: {step.message or step.status}`)
			end)
		end)
	end
	check:expect(complete.passed == 1):toBeTrueWith(if complete.passed == 1 then id else Verify.format(complete))
	for _, artifact in complete.results[1].artifacts do
		if artifact.content then
			check:attach(artifact.name, assert(artifact.mediaType), artifact.content)
		end
	end
end

local function catalog(check: Verify.Context): Catalog
	local plan = Lute.parse(Lute.fixture.host.readFile("tools/studio/live/plan.json"))
	assert(type(plan) == "table" and type(plan.units) == "table")
	local suites: { string } = {}
	for _, unit in plan.units do
		assert(type(unit) == "table" and type(unit.id) == "string")
		table.insert(suites, unit.id)
	end
	local host = open(check, suites)
	local live = host.runtime.requireInstance(host.storage:FindFirstChild("FacetLive"))
	assert(type(live) == "table")
	local casesFor = live.cases
	assert(type(casesFor) == "function")
	local result: Catalog = { sources = {}, total = 0, automatic = 0, interactive = 0, probes = 0 }
	for _, id in suites do
		local entries: { Descriptor } = {}
		local cases = casesFor(id)
		assert(type(cases) == "table")
		for _, case in cases do
			assert(type(case) == "table")
			local caseId = case.id
			assert(type(caseId) == "string")
			result.total += 1
			result.automatic += if case.run then 1 else 0
			result.interactive += if case.setup then 1 else 0
			result.probes += if case.probe then 1 else 0
			table.insert(entries, {
				id = caseId,
				automatic = case.run ~= nil,
				interactive = case.setup ~= nil,
				probe = case.probe == true,
			})
		end
		check:expect(#entries > 0):toBeTrueWith(id)
		table.insert(result.sources, { id = id, cases = entries })
	end
	check:expect(unexpected(host.engine.diagnostics)):toEqual({})
	return result
end

return { run = run, open = open, catalog = catalog }
