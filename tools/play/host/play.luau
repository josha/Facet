--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local task = require("@std/task")

local AgentEval = require("../../../tools/vendor/verify/src/agent-eval")
local Core = require("../../../tools/vendor/verify/src/core")
local Lute = require("../../../tools/vendor/verify/src/lute")

local Devices = require("./devices")
local Actions = require("./actions")
local QA = require("./qa")

export type CaseBody = (qa: QA.QA, context: Core.Context) -> ()

export type Case = {
	id: string,
	run: CaseBody,
	timeoutSeconds: number?,
	screen: string?,
	shot: string?,
	tier: ("universal" | "spec")?,
}

export type Session = { device: string, cases: { Case } }

export type Scenario = { sessions: { Session } }

export type HostOptions = {
	workspace: string,
	outputs: string,
	captures: string,
	project: string?,
	keep: boolean?,
	quiet: boolean?,
	compareMount: boolean?,
	performance: boolean?,
	reusePlay: boolean?,
	basePlace: string?,
	requireInterface: boolean?,
}

export type DevicePerf = {
	mountSeconds: number?,
	mount: { [string]: unknown }?,
	legacyMountSeconds: number?,
	idle: { [string]: unknown }?,
	screens: { [string]: { [string]: unknown } },
	final: { [string]: unknown }?,
	returned: boolean?,
	returnProblem: string?,
}

export type Host = {
	build: () -> (boolean, string?),
	enter: (device: string) -> QA.QA,
	measure: (device: string, screen: string, body: () -> ()) -> (),
	perf: { [string]: DevicePerf },
	close: () -> (),
	log: (line: string) -> (),
	lines: { string },
	timings: { [string]: number },
	shots: { QA.Shot },
}

type Arguments = {
	workspace: string,
	outputs: string,
	captures: string,
	report: string,
	run: string,
	scores: string?,
	devices: { [string]: boolean }?,
	keep: boolean,
	tier: "universal" | "spec",
}

local absolute = AgentEval.lute.absolute
local ROOT_NAME = "PlayProbe"

local function directoryOf(source: string): string
	local path = absolute((string.gsub(source, "^@", "")))
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local HERE = directoryOf(debug.info(1, "s"))
local PROBE = absolute(HERE .. "/../engine/probe.luau")

local function arguments(): Arguments
	local values: { [string]: string } = {}
	local keep = false
	local index = 2
	while index <= #process.args do
		local word = process.args[index]
		local name = string.match(word, "^%-%-([%w%-]+)$")
		if name == "keep" then
			keep = true
		elseif name ~= nil and process.args[index + 1] ~= nil then
			values[name] = process.args[index + 1]
			index += 1
		end
		index += 1
	end
	local function given(name: string): string
		local value = values[name]
		if value == nil then
			error("--" .. name .. " is required", 0)
		end
		return value
	end
	local function required(name: string): string
		return absolute(given(name))
	end
	local devices: { [string]: boolean }? = nil
	if values.devices ~= nil and values.devices ~= "" then
		local chosen: { [string]: boolean } = {}
		for id in string.gmatch(values.devices, "[^,]+") do
			Devices.get(id)
			chosen[id] = true
		end
		devices = chosen
	end
	local scores: string? = values.scores
	assert(values.tier == nil or values.tier == "universal" or values.tier == "spec", "invalid --tier")
	return {
		workspace = required("workspace"),
		outputs = required("outputs"),
		captures = required("captures"),
		report = required("report"),
		run = given("run"),
		scores = if scores ~= nil then absolute(scores) else nil,
		devices = devices,
		keep = keep,
		tier = if values.tier == "spec" then "spec" else "universal",
	}
end

local function ensure(path: string)
	if not fs.exists(path) then
		fs.createDirectory(path, { makeParents = true })
	end
end

local function simulatorCode(device: Devices.Device): string
	local orientation = if device.orientation == "portrait"
		then "Enum.ScreenOrientation.Portrait"
		elseif device.orientation == "landscape" then "Enum.ScreenOrientation.LandscapeLeft"
		else "nil"
	return table.concat({
		"local service = game:GetService('StudioDeviceSimulatorService')",
		("service:SetDeviceAsync(%q)"):format(device.preset),
		("local orientation = %s"):format(orientation),
		"if orientation ~= nil then service:SetOrientationAsync(orientation) end",
		"service:SetScalingModeAsync(Enum.DeviceSimulatorScalingMode.FitToWindow)",
		"return service:GetDeviceAsync()",
	}, "\n")
end

local function open(options: HostOptions): Host
	ensure(options.outputs)
	ensure(options.captures)
	local build = options.outputs .. "/build"
	ensure(build)
	local placePath = build .. "/play.rbxlx"
	local lines: { string } = {}
	local shots: { QA.Shot } = {}
	local built = false
	local timings: { [string]: number } = {}
	local buildProblem: string? = nil
	local launched: Lute.StudioLaunched? = nil
	local launchProblem: string? = nil
	local current: { device: string, qa: QA.QA }? = nil
	local playing = false
	local perf: { [string]: DevicePerf } = {}

	local function probe(qa: QA.QA, fields: { [string]: unknown }): { [string]: unknown }?
		local ok, value = pcall(function(): unknown
			return qa:call("perf", fields)
		end)
		return if ok and type(value) == "table" then value :: { [string]: unknown } else nil
	end

	local function finishDevice(): boolean
		if options.performance == false and not options.reusePlay then
			return false
		end
		local active = current
		if active ~= nil and perf[active.device] ~= nil then
			local record = perf[active.device]
			local ok, returned, detail = pcall(function()
				return Actions.returnToRoot(active.qa)
			end)
			record.returned = ok and returned == true
			record.returnProblem = if record.returned then nil else if ok then detail else tostring(returned)
			if ok and record.returned and options.performance ~= false then
				active.qa:sleep(5)
				record.final = probe(active.qa, { action = "idle", seconds = 2 })
			end
			return ok and record.returned == true
		end
		return false
	end
	local problems: { [string]: string } = {}

	local function log(line: string)
		if not options.quiet then
			print(line)
		end
		table.insert(lines, line)
	end

	local function session(): Lute.StudioSession
		return (launched :: Lute.StudioLaunched).session
	end

	local function stopPlay()
		local started = os.clock()
		if playing and launched ~= nil then
			local response = session().play(false)
			if not response.ok then
				log("play: stopping play failed: " .. tostring(response.detail))
			end
			playing = false
			if options.performance ~= false then
				task.wait(2)
			end
		end
		timings.stop = (timings.stop or 0) + os.clock() - started
	end

	local function buildPlace(): (boolean, string?)
		local started = os.clock()
		local project = options.workspace .. "/" .. (options.project or "default.project.json")
		local output = options.basePlace or build .. "/game.rbxlx"
		if options.basePlace == nil then
			local result = process.run({ "rojo", "build", project, "-o", output }, { cwd = options.workspace })
			if not result.ok then
				buildProblem = "rojo build failed: " .. result.stderr .. result.stdout
				return false, buildProblem
			end
		end
		local ok, problem = pcall(function(): boolean
			Lute.place.build({
				output = placePath,
				basePlace = output,
				roots = {},
				modules = { PROBE },
				rootName = ROOT_NAME,
			})
			return true
		end)
		if not ok then
			buildProblem = "the probe could not be mounted: " .. tostring(problem)
			return false, buildProblem
		end
		built = true
		timings.build = os.clock() - started
		return true, nil
	end

	local function start(device: Devices.Device): QA.QA
		if not built then
			error("blocked: the workspace did not build: " .. tostring(buildProblem), 0)
		end
		if launched == nil and launchProblem == nil then
			local started = os.clock()
			local opened, problem = Lute.studio.launch({
				place = placePath,
				directory = options.outputs .. "/studio",
				runSeconds = 3600,
				callSeconds = 120,
				launchSeconds = 240,
			})
			launched = opened
			timings.launch = os.clock() - started
			launchProblem = problem
			if opened ~= nil then
				log(("play: Studio %d opened %s"):format(opened.pid, opened.name))
			end
		end
		if launched == nil then
			error("blocked: Studio is not available: " .. tostring(launchProblem), 0)
		end
		local previous = current
		local resetStarted = os.clock()
		local returned = finishDevice()
		timings.reset = (timings.reset or 0) + os.clock() - resetStarted
		local reused = returned
			and options.reusePlay == true
			and playing
			and previous ~= nil
			and previous.qa.device.mode ~= "gamepad"
			and device.mode ~= "gamepad"
		if not reused then
			stopPlay()
		end
		current = nil
		local setupStarted = os.clock()
		local simulated = session().execute(if reused then "Client" else "Edit", simulatorCode(device))
		if not simulated.ok then
			error("the device simulator did not accept " .. device.preset .. ": " .. tostring(simulated.detail), 0)
		end
		timings.setup = (timings.setup or 0) + os.clock() - setupStarted
		if not reused then
			local playCall = os.clock()
			local started = session().play(true)
			timings.play = (timings.play or 0) + os.clock() - playCall
			if not started.ok then
				error("play did not start: " .. tostring(started.detail), 0)
			end
		end
		playing = true
		local playStarted = os.clock()
		local context: QA.Context = {
			session = session(),
			probe = Lute.place.moduleExpression(PROBE, ROOT_NAME),
			outputs = options.outputs,
			captures = options.captures,
			scratch = options.outputs .. "/raw-captures",
			shots = shots,
			log = log,
		}
		local qa = QA.create(context, device)
		local deadline = os.clock() + 120
		local ready: { [string]: unknown }? = nil
		local lastProblem = ""
		while os.clock() < deadline do
			local ok, value = pcall(function(): unknown
				return qa:call("ping")
			end)
			if ok and type(value) == "table" then
				ready = value :: { [string]: unknown }
				break
			end
			lastProblem = tostring(value)
			task.wait(1)
		end
		if ready == nil then
			error("the client did not become ready: " .. lastProblem, 0)
		end
		local settle = os.clock() + 20
		while os.clock() < settle do
			local value = qa:call("ping")
			if QA.interfaceMounted(value, options.requireInterface) then
				break
			end
			task.wait(0.5)
		end
		if options.performance ~= false then
			task.wait(2)
		end
		local final = qa:call("ping")
		local fields: { [string]: unknown } = if type(final) == "table" then final :: { [string]: unknown } else {}
		if options.requireInterface and not QA.interfaceMounted(fields, true) then
			local errors = if type(fields.errors) == "table" then fields.errors :: { unknown } else {}
			local first = errors[1]
			qa.mountProblem = "interface did not mount; dependent steps stopped"
				.. (if type(first) == "string" then "; client error: " .. first else "")
			current = { device = device.id, qa = qa }
			return qa
		end
		local viewport: { [string]: unknown } = if type(fields.viewport) == "table"
			then fields.viewport :: { [string]: unknown }
			else {}
		qa.viewport = {
			width = tonumber(viewport.screenWidth) or 0,
			height = tonumber(viewport.screenHeight) or 0,
		}
		log(
			("play: %s ready, screen %dx%d, inputs %s"):format(
				device.id,
				qa.viewport.width,
				qa.viewport.height,
				Lute.encode(fields.inputs)
			)
		)
		local portrait = qa.viewport.height > qa.viewport.width
		if device.orientation == "portrait" and not portrait then
			error("the screen is not in portrait; the game must allow portrait on phones", 0)
		elseif device.orientation == "landscape" and portrait then
			error("the screen is not in landscape", 0)
		end
		local settleCalled = os.clock()
		local settled = probe(qa, {
			action = "settle",
			quiet = if options.performance == false then 0.1 else 1,
			limit = 20,
			compareLegacy = options.compareMount == true,
		})
		local record: DevicePerf = { screens = {}, mount = settled }
		if settled ~= nil and type(settled.seconds) == "number" then
			record.mountSeconds = settleCalled - playStarted + (settled.seconds :: number)
			if type(settled.legacySeconds) == "number" then
				record.legacyMountSeconds = settleCalled - playStarted + (settled.legacySeconds :: number)
			end
			if settled.timedOut == true then
				log("play: " .. device.id .. " mount hit the 20-second settle limit")
			end
		end
		if options.performance ~= false then
			record.idle = probe(qa, { action = "idle", seconds = 2 })
		end
		timings.ready = (timings.ready or 0) + os.clock() - playStarted
		perf[device.id] = record
		current = { device = device.id, qa = qa }
		return qa
	end

	local function enter(id: string): QA.QA
		local active = current
		if active ~= nil and active.device == id then
			return active.qa
		end
		local known = problems[id]
		if known ~= nil then
			error("blocked: " .. known, 0)
		end
		local ok, result = pcall(start, Devices.get(id))
		if not ok then
			problems[id] = tostring(result)
			current = nil
			error(tostring(result), 0)
		end
		return result :: QA.QA
	end

	local function measure(device: string, screen: string, body: () -> ())
		local active = current
		local record = perf[device]
		if active == nil or active.device ~= device or record == nil then
			body()
			return
		end
		probe(active.qa, { action = "begin" })
		local ok, problem = pcall(function(): boolean
			body()
			return true
		end)
		local ended = probe(active.qa, { action = "end" })
		if ended ~= nil then
			record.screens[screen] = ended
		end
		if not ok then
			error(problem, 0)
		end
	end

	local function close()
		if options.performance ~= false then
			finishDevice()
		end
		stopPlay()
		local opened = launched
		if opened == nil then
			return
		end
		if options.keep then
			log("play: keeping Studio " .. opened.name)
			return
		end
		local closeStarted = os.clock()
		local closed = opened.close()
		timings.teardown = os.clock() - closeStarted
		if not closed.session.acknowledged then
			log("play: Studio cleanup was not acknowledged: " .. tostring(closed.session.detail))
		end
		if #closed.survivors > 0 then
			log("play: Studio processes survived cleanup: " .. table.concat(closed.survivors, ","))
		end
		launched = nil
	end

	return {
		build = buildPlace,
		enter = enter,
		close = close,
		log = log,
		lines = lines,
		timings = timings,
		shots = shots,
		measure = measure,
		perf = perf,
	}
end

local function number(value: unknown, ...: string): number?
	local cursor = value
	for _, key in { ... } do
		if type(cursor) ~= "table" then
			return nil
		end
		cursor = (cursor :: { [string]: unknown })[key]
	end
	return if type(cursor) == "number" then cursor else nil
end

local function perfScores(perf: { [string]: DevicePerf }, scores: { [string]: number })
	for device, record in perf do
		local function put(name: string, value: number?)
			if value ~= nil then
				scores[("perf.%s.%s"):format(device, name)] = value
			end
		end
		put("mountSeconds", if record.mount and record.mount.timedOut == true then nil else record.mountSeconds)
		put("mountTimedOut", if record.mount and record.mount.timedOut == true then 1 else 0)
		put("idleFrameP50Ms", number(record.idle, "frames", "p50"))
		put("idleFrameP95Ms", number(record.idle, "frames", "p95"))
		put("baseGuiObjects", number(record.idle, "census", "gui"))
		put("baseComponents", number(record.idle, "census", "components"))
		put("baseInstances", number(record.idle, "census", "instances"))
		put("returned", if record.returned then 1 else 0)
		if record.returned then
			local finalMetrics: { [string]: string } = { finalHeapKb = "luaHeapKb", finalGuiMb = "guiMb" }
			for metric, property in finalMetrics do
				local value = number(record.final, "memory", property)
				if value ~= nil and value > 0 and value < math.huge then
					put(metric, value)
				end
			end
		end
		local returnMetrics: { [string]: string } = { heapReturnRatio = "luaHeapKb", guiReturnRatio = "guiMb" }
		for metric, property in returnMetrics do
			local before, after = number(record.idle, "memory", property), number(record.final, "memory", property)
			if before ~= nil and after ~= nil and before > 0 then
				put(metric, after / before)
			end
		end
		local peakGui, peakComponents, p50Sum, p50Count, p95Max = nil :: number?, nil :: number?, 0, 0, nil :: number?
		for _, screen in record.screens do
			local gui, components = number(screen, "census", "gui"), number(screen, "census", "components")
			local p50, p95 = number(screen, "frames", "p50"), number(screen, "frames", "p95")
			if gui ~= nil then
				peakGui = math.max(peakGui or 0, gui)
			end
			if components ~= nil then
				peakComponents = math.max(peakComponents or 0, components)
			end
			if p50 ~= nil then
				p50Sum += p50
				p50Count += 1
			end
			if p95 ~= nil then
				p95Max = math.max(p95Max or 0, p95)
			end
		end
		put("peakGuiObjects", peakGui)
		put("peakComponents", peakComponents)
		put("activeFrameP50Ms", if p50Count > 0 then p50Sum / p50Count else nil)
		put("activeFrameP95Ms", p95Max)
		local function delta(...: string): number?
			local before, after = number(record.idle, ...), number(record.final, ...)
			return if before ~= nil and after ~= nil then after - before else nil
		end
		put("heapDeltaKb", delta("memory", "luaHeapKb"))
		put("instanceDelta", delta("memory", "instances"))
		put("guiMbDelta", delta("memory", "guiMb"))
		put("guiObjectDelta", delta("census", "gui"))
	end
end

local function validateResults(expected: { [string]: boolean }, report: Core.Report)
	assert(next(expected) ~= nil, "harness error: no device play cases were selected")
	local seen: { [string]: boolean } = {}
	for _, result in report.results do
		if result.id == "workspace/builds" then
			continue
		end
		assert(expected[result.id], "harness error: unexpected play case " .. result.id)
		assert(not seen[result.id], "harness error: repeated play result " .. result.id)
		seen[result.id] = true
		for _, failure in result.failures do
			assert(string.find(failure.message, "harness error:", 1, true) == nil, failure.message)
		end
	end
	for id in expected do
		assert(seen[id], "harness error: no recorded result for " .. id)
	end
end

local function main(scenario: Scenario, entrySource: string, universal: Scenario?)
	local args = arguments()
	if args.scores ~= nil and fs.exists(args.scores) then
		fs.remove(args.scores)
	end
	local tiers: { [string]: string } = { ["workspace/builds"] = args.tier }
	if universal ~= nil and args.tier == "universal" then
		scenario = universal
	end
	local taskDirectory = absolute(directoryOf(entrySource) .. "/..")
	local taskName = string.match(taskDirectory, "([^/]+)$") or "task"
	local host = open({
		workspace = args.workspace,
		outputs = args.outputs,
		captures = args.captures,
		keep = args.keep,
	})

	local harness = Core.createHarness({ now = os.clock })
	local expected: { [string]: boolean } = {}
	harness:suite(taskName, function()
		harness:case("workspace/builds", {
			id = "workspace/builds",
			timeoutSeconds = 300,
			run = function(context: Core.Context)
				local ok, problem = host.build()
				if not ok then
					context:expect(false):toBeTrueWith(tostring(problem))
				end
			end,
		})
		for _, entry in scenario.sessions do
			if args.devices ~= nil and not (args.devices :: { [string]: boolean })[entry.device] then
				continue
			end
			for _, case in entry.cases do
				local id = entry.device .. "/" .. case.id
				assert(not expected[id], "harness error: duplicate play case " .. id)
				expected[id] = true
				tiers[id] = case.tier or "spec"
				harness:case(id, {
					id = id,
					timeoutSeconds = case.timeoutSeconds or 240,
					run = function(context: Core.Context)
						host.log("case: " .. id .. " started")
						local qa = host.enter(entry.device)
						local screen = case.screen
						if screen == nil then
							case.run(qa, context)
							return
						end
						local ok, problem = pcall(function(): boolean
							host.measure(entry.device, screen, function()
								case.run(qa, context)
							end)
							return true
						end)
						if
							not ok and not fs.exists(("%s/dumps/%s/%s.json"):format(args.outputs, entry.device, screen))
						then
							pcall(function()
								qa:capture(case.shot or screen)
								qa:dump(screen)
							end)
						end
						if not ok then
							error(problem, 0)
						end
					end,
				})
			end
		end
	end)

	local report = harness:run({
		executor = "play",
		environment = { task = taskName, workspace = args.workspace },
	})
	host.close()
	Lute.gate.writeReport(args.report, args.run, report)
	host.log(Core.format(report))
	fs.writeStringToFile(args.outputs .. "/play.log", table.concat(host.lines, "\n") .. "\n")
	validateResults(expected, report)
	for id in expected do
		local device = string.match(id, "^([^/]+)/") :: string
		assert(host.perf[device] ~= nil, "harness error: device setup did not complete for " .. device)
	end
	local passed, total = 0, 0
	local byDevice: { [string]: { passed: number, total: number } } = {}
	local byTier: { [string]: { passed: number, total: number } } = {}
	for _, result in report.results do
		total += 1
		local device = string.match(result.id, "^([^/]+)/") or "workspace"
		local tier = tiers[result.id]
		assert(tier ~= nil, "every play case must declare a tier")
		for _, key in { tier, tier .. "." .. device } do
			local count = byTier[key] or { passed = 0, total = 0 }
			byTier[key] = count
			count.total += 1
			count.passed += if result.status == "passed" then 1 else 0
		end
		local tally = byDevice[device] or { passed = 0, total = 0 }
		byDevice[device] = tally
		tally.total += 1
		if result.status == "passed" then
			passed += 1
			tally.passed += 1
		end
	end
	local kept, blank, missing = 0, 0, 0
	for _, shot in host.shots do
		if shot.path ~= nil then
			kept += 1
		elseif shot.blank then
			blank += 1
		else
			missing += 1
		end
	end
	if args.scores ~= nil then
		local scores: { [string]: number } = {
			casesPassed = passed,
			casesTotal = total,
			caseFraction = if total > 0 then passed / total else 0,
			capturesKept = kept,
			capturesBlank = blank,
			capturesMissing = missing,
		}
		for device, tally in byDevice do
			if device ~= "workspace" then
				scores["fraction." .. device] = if tally.total > 0 then tally.passed / tally.total else 0
			end
		end
		for tier, tally in byTier do
			scores[tier .. ".passed"] = tally.passed
			scores[tier .. ".total"] = tally.total
			scores[tier .. ".fraction"] = tally.passed / tally.total
		end
		perfScores(host.perf, scores)
		fs.writeStringToFile(args.scores :: string, Lute.encode(scores))
	end
	fs.writeStringToFile(args.outputs .. "/captures.json", Lute.encode(host.shots))
	fs.writeStringToFile(args.outputs .. "/perf.json", Lute.encode(host.perf))
	fs.writeStringToFile(args.outputs .. "/tiers.json", Lute.encode(tiers))
	fs.writeStringToFile(args.outputs .. "/play.log", table.concat(host.lines, "\n") .. "\n")
	if passed ~= total then
		process.exit(1)
	end
end

return {
	main = main,
	open = open,
	validateResults = validateResults,
	perfScores = perfScores,
}
