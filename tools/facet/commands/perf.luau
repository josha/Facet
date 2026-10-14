--!strict

local fs = require("@std/fs")
local system = require("@std/system")
local Base64 = require("../../vendor/verify/src/codec/base64")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Evidence = require("../lib/perf_evidence")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Microprofiler = require("../lib/microprofiler")
local Paired = require("../lib/perf_paired")
local Place = require("../lib/perf_place")
local Run = require("../lib/run")
local Xml = require("../lib/xml")

local USAGE = [[usage: lute run tools/facet perf <subcommand> [options]

subcommands:
  run [baseline]                run every scene on each profile and check the trend budgets (exit 2 on a
                                host timing failure); baseline rewrites bench/perf_budgets.json instead
  baseline SCENE...             rebaseline only the named scenes in bench/perf_budgets.json
  prove-gate                    inject a regression, prove that run fails, then rerun it clean
  budgets                       check bench/perf_budgets.json and the last perf run's skipped device budgets
  metrics                       check the metric rows of artifacts/phase-4/perf.json (exit 2 when it is absent)
  scenes [--themes]             check that each production (or theme-swap) scene did its work
  place [--no-build]            build examples/performance.project.json and check the place
  paired run --out DIR [--rounds N] [--scenes a,b] [--skip-bench] LABEL=WORKTREE...
                                run the paired scenes and the bench in each worktree, round by round
  paired report DIR FIRST SECOND
                                print the paired scene and microbenchmark tables
  aggregate [--all] [--layout] DUMP.html...
                                read a MicroProfiler HTML dump's aggregate timer table
  spec-timings [OUTCOME.json] [OUTPUT.tsv]
                                write per-spec case timings from the last gate outcome

Every subcommand accepts --selftest to run its cases against fixture data.

aggregate reads a reader, not a check: it has no pass/fail. WINDOW=0 means the
MicroProfiler accumulator collected no frames, so the capture has no timings.
On a healthy Facet capture Facet/tick equals the frame window (tick==window).
--all prints every scope, not only Facet/* and LuauUI/*. --layout prints the
engine's Relayout/Update/Resize records from the name blob.]]

local AGGREGATE_USAGE = [[usage: lute run tools/facet perf aggregate <dump.html> [<dump.html> ...]
       lute run tools/facet perf aggregate --all <dump.html>     every scope, not just Facet/*
       lute run tools/facet perf aggregate --layout <dump.html>  the Relayout/Update/Resize records]]

local function failLines(errors: { string }): number
	for _, message in errors do
		print("FAIL " .. message)
	end
	return 1
end

local function readJson(path: string): unknown
	return Json.decode(Files.read(path))
end

local function deviceDocuments(directory: string): { unknown }
	local documents: { unknown } = {}
	for _, entry in Files.list(directory) do
		if string.sub(entry.name, -5) == ".json" then
			local ok, contents = pcall(Files.read, Files.join(directory, entry.name))
			if ok then
				local value, problem = Json.tryDecode(contents)
				if problem == nil then
					table.insert(documents, value)
				end
			end
		end
	end
	return documents
end

local function budgets(): number
	if not Files.isFile(Evidence.BUDGETS) then
		print(("perf budgets: FAIL - %s is missing"):format(Evidence.BUDGETS))
		return 1
	end
	if not Files.isFile(Evidence.PERF) then
		print(("perf budgets: FAIL - %s is missing; run lute run tools/facet perf run first"):format(Evidence.PERF))
		return 1
	end
	local outcome = Evidence.budgets(
		readJson(Evidence.BUDGETS),
		readJson(Evidence.PERF),
		Evidence.deviceRowCounter(deviceDocuments(Evidence.DEVICE_DIRECTORY))
	)
	if #outcome.errors > 0 then
		return failLines(outcome.errors)
	end
	print(outcome.summary)
	return 0
end

local function metrics(): number
	if not Files.isFile(Evidence.PERF) then
		print(
			("perf metrics: FAIL_ENVIRONMENT — recorded evidence %s is not in this checkout (git-ignored, produced by a run); its row carries the content-hash receipt that stands for it"):format(
				Evidence.PERF
			)
		)
		return 2
	end
	local outcome = Evidence.metrics(readJson(Evidence.PERF))
	for _, note in outcome.notes do
		print(note)
	end
	if #outcome.errors > 0 then
		return failLines(outcome.errors)
	end
	print(outcome.summary)
	return 0
end

local function scenes(themes: boolean): number
	if not Files.isFile(Evidence.PERF) then
		print(("perf scenes: FAIL - %s is missing; run lute run tools/facet perf run first"):format(Evidence.PERF))
		return 1
	end
	local outcome = Evidence.scenes(readJson(Evidence.PERF), themes)
	if #outcome.errors > 0 then
		failLines(outcome.errors)
		for _, note in outcome.notes do
			print(note)
		end
		return 1
	end
	print(outcome.summary)
	return 0
end

local function toolEnvironment(extra: { string }, onlyExisting: boolean): { [string]: string }
	local environment = Run.environment()
	local key = "PATH"
	for name in environment do
		if string.upper(name) == "PATH" then
			key = name
			break
		end
	end
	local separator = if system.win32 then ";" else ":"
	local parts: { string } = {}
	for _, directory in extra do
		if not onlyExisting or Files.isDirectory(directory) then
			table.insert(parts, directory)
		end
	end
	local current = environment[key]
	if current ~= nil then
		table.insert(parts, current)
	else
		table.insert(parts, "")
	end
	environment[key] = table.concat(parts, separator)
	return environment
end

local function home(): string
	return Run.env("HOME") or Run.env("USERPROFILE") or "~"
end

local function rokitDirectories(): { string }
	return { Files.join(home(), ".rokit", "bin"), "/opt/homebrew/bin", "/usr/local/bin" }
end

local function place(invocation: Cli.Invocation): number
	local build = not Cli.switch(invocation, "no-build")
	local problems: { string } = {}
	local notes: { string } = {}
	if not Files.isFile(Place.PROJECT) then
		print(("perf place: FAIL - missing %s"):format(Place.PROJECT))
		return 1
	end
	local environment = toolEnvironment(rokitDirectories(), true)
	local scratch = Files.temporaryDirectory("facet-perf-place-")
	local xmlPath = Files.join(scratch, "perflab.rbxlx")
	local tree: Place.Tree? = nil
	local order: { string } = {}
	local built, failure = pcall(function()
		if build then
			Files.makeDirectory(Files.parent(Place.BUILT))
			local binary = Run.capture({ "rojo", "build", Place.PROJECT, "-o", Place.BUILT }, { env = environment })
			if not binary.ok then
				table.insert(problems, ("rojo build (.rbxl) failed: %s"):format(Place.trim(binary.stderr)))
			end
		end
		local xml = Run.capture({ "rojo", "build", Place.PROJECT, "-o", xmlPath }, { env = environment })
		if not xml.ok then
			table.insert(problems, ("rojo build (.rbxlx) failed: %s"):format(Place.trim(xml.stderr)))
		else
			tree, order = Place.index(Xml.parse(Files.read(xmlPath)))
		end
	end)
	Files.remove(scratch)
	if not built then
		print(("perf place: FAIL - %s"):format(tostring(failure)))
		return 1
	end
	if tree ~= nil then
		local found, foundNotes = Place.inspectTree(tree, order, function(module: string): string?
			local path = Files.join(Place.LAB, module .. ".luau")
			if not Files.isFile(path) then
				return nil
			end
			return Files.text(path)
		end)
		table.move(found, 1, #found, #problems + 1, problems)
		table.move(foundNotes, 1, #foundNotes, #notes + 1, notes)
	end
	local size: number? = nil
	local magic: string? = nil
	if Files.isFile(Place.BUILT) then
		size = Files.size(Place.BUILT)
		magic = string.sub(Files.read(Place.BUILT), 1, 8)
	end
	local builtProblems, builtNotes = Place.inspectBuilt(Place.BUILT, size, magic)
	table.move(builtProblems, 1, #builtProblems, #problems + 1, problems)
	table.move(builtNotes, 1, #builtNotes, #notes + 1, notes)
	local result = Json.object()
	Json.set(result, "schema", "facet-perf-place/2")
	Json.set(result, "status", if #problems == 0 then "PASS" else "FAIL")
	Json.set(result, "project", Place.PROJECT)
	Json.set(result, "built", Place.BUILT)
	Json.set(result, "rebuiltFromSource", build)
	Json.set(result, "requiredInstances", #Place.REQUIRED)
	Json.set(result, "versionMarkers", #Place.VERSION_MARKERS)
	Json.set(result, "problems", Json.array(problems))
	Json.set(result, "notes", Json.array(notes))
	Files.write(Place.ARTIFACT, Json.pretty(result))
	if #problems > 0 then
		print(("perf place: FAIL - %d problem(s)"):format(#problems))
		for _, problem in problems do
			print("  " .. problem)
		end
		return 1
	end
	print(
		("perf place: PASS - %d required instances, %d version markers, publish-safe -> %s"):format(
			#Place.REQUIRED,
			#Place.VERSION_MARKERS,
			Place.ARTIFACT
		)
	)
	return 0
end

local function append(path: string, text: string)
	Files.makeDirectory(Files.parent(path))
	local handle = fs.open(path, "a")
	fs.write(handle, text)
	fs.close(handle)
end

local function loadAverage(): string
	local values: { number } = {}
	if Files.isFile("/proc/loadavg") then
		for token in string.gmatch(Files.read("/proc/loadavg"), "%S+") do
			local value = tonumber(token)
			if value ~= nil and #values < 3 then
				table.insert(values, value)
			end
		end
	elseif not system.win32 then
		local output = Run.output({ "sysctl", "-n", "vm.loadavg" })
		if output ~= nil then
			for token in string.gmatch(output, "[%d%.]+") do
				local value = tonumber(token)
				if value ~= nil and #values < 3 then
					table.insert(values, value)
				end
			end
		end
	end
	if #values < 3 then
		return "unknown"
	end
	return ("%.2f %.2f %.2f"):format(values[1], values[2], values[3])
end

local function samePath(left: string, right: string): boolean
	local a = Files.absolute(left)
	local b = Files.absolute(right)
	if system.win32 then
		return string.lower(a) == string.lower(b)
	end
	return a == b
end

local function pairedRun(invocation: Cli.Invocation): number
	local out = Cli.flag(invocation, "out")
	local trees: { { label: string, tree: string } } = {}
	for index = 3, #invocation.positional do
		local pair = invocation.positional[index]
		local label, tree = string.match(pair, "^([^=]*)=(.*)$")
		table.insert(trees, { label = label or pair, tree = Files.absolute(tree or "") })
	end
	local rounds = tonumber(Cli.flag(invocation, "rounds") or "5")
	if out == nil or #trees == 0 or rounds == nil then
		print(USAGE)
		return 2
	end
	local selected = Cli.flag(invocation, "scenes")
	local sceneList: { string } = if selected ~= nil and selected ~= ""
		then string.split(selected, ",")
		else Paired.SCENES
	local skipBench = Cli.switch(invocation, "skip-bench")
	local environment = toolEnvironment(rokitDirectories(), false)
	local runner = Files.absolute("bench/paired_scene.luau")
	local log = Files.join(out, "log.txt")
	local rows = Files.join(out, "scenes.jsonl")
	Files.makeDirectory(out)
	for round = 1, rounds do
		for _, entry in trees do
			local target = Files.join(entry.tree, "bench/paired_scene.luau")
			if not samePath(target, runner) then
				Files.write(target, Files.read(runner))
			end
			append(
				log,
				("round %d %s start %s load %s\n"):format(round, entry.label, os.date("%H:%M:%S"), loadAverage())
			)
			for _, scene in sceneList do
				local result = Run.capture(
					{ Run.lute(), "run", "bench/paired_scene.luau", scene },
					{ cwd = entry.tree, env = environment }
				)
				local row = Paired.sceneRow(result.stdout)
				if row == nil then
					local crashed = Json.object()
					Json.set(crashed, "scene", scene)
					Json.set(crashed, "status", "crashed")
					row = crashed
				end
				local record = Json.object()
				Json.set(record, "label", entry.label)
				Json.set(record, "round", round)
				Json.set(record, "row", row)
				append(rows, Json.encode(record) .. "\n")
			end
			if not skipBench then
				local bench = Run.capture(
					{ Run.lute(), "run", "tools/facet", "bench" },
					{ cwd = entry.tree, env = environment }
				)
				Files.write(
					Files.join(out, ("bench-%s-%d.log"):format(entry.label, round)),
					bench.stdout .. bench.stderr
				)
				Files.write(
					Files.join(out, ("bench-%s-%d.json"):format(entry.label, round)),
					Files.read(Files.join(entry.tree, "artifacts", "bench.json"))
				)
			end
			append(log, ("round %d %s end %s\n"):format(round, entry.label, os.date("%H:%M:%S")))
		end
	end
	append(log, "DONE\n")
	return 0
end

local function benchesFor(out: string, label: string): { Paired.Bench }
	local benches: { Paired.Bench } = {}
	for _, entry in Files.list(out) do
		local round = Paired.benchRound(entry.name, label)
		if round ~= nil then
			local path = Files.join(out, entry.name)
			table.insert(
				benches,
				{ path = path, round = round, document = Json.asObject(readJson(path)) or Json.object() }
			)
		end
	end
	return benches
end

local function pairedReport(invocation: Cli.Invocation): number
	local out, first, second = invocation.positional[3], invocation.positional[4], invocation.positional[5]
	if out == nil or first == nil or second == nil then
		print(USAGE)
		return 2
	end
	local entries: { Json.Object } = {}
	for _, line in Files.lines(Files.read(Files.join(out, "scenes.jsonl"))) do
		if string.find(line, "%S") ~= nil then
			table.insert(entries, Json.asObject(Json.decode(line)) or Json.object())
		end
	end
	for _, line in Paired.sceneTable(entries, first, second) do
		print(line)
	end
	for _, line in Paired.benchTables(benchesFor(out, first), benchesFor(out, second), first, second) do
		print(line)
	end
	return 0
end

local function aggregate(invocation: Cli.Invocation): number
	local paths: { string } = {}
	for index = 2, #invocation.positional do
		table.insert(paths, invocation.positional[index])
	end
	if #paths == 0 then
		print(AGGREGATE_USAGE)
		return 1
	end
	local options: Microprofiler.Options = {
		all = Cli.switch(invocation, "all"),
		layout = Cli.switch(invocation, "layout"),
	}
	for _, path in paths do
		local ok, lines = pcall(function(): { string }
			local body = Microprofiler.load(path, Files.read(path))
			return Microprofiler.render(path, Microprofiler.parse(body), options)
		end)
		if not ok then
			print(tostring(lines))
			return 1
		end
		for _, line in lines :: { string } do
			print(line)
		end
	end
	return 0
end

export type SpecRow = { spec: string, cases: number, casesMs: number }

local function specRows(outcome: unknown): { SpecRow }
	local results = Json.arrayField(Json.objectField(Json.objectField(outcome, "execution"), "report"), "results")
	if results == nil then
		error("the gate outcome has no execution.report.results", 0)
	end
	local rows: { SpecRow } = {}
	local bySource: { [string]: SpecRow } = {}
	for _, result in results do
		local value = Json.field(result, "source")
		local source = if value == nil then "unknown" else tostring(value)
		local row = bySource[source]
		if row == nil then
			row = { spec = source, cases = 0, casesMs = 0 }
			bySource[source] = row
			table.insert(rows, row)
		end
		row.cases += 1
		row.casesMs += (Json.numberField(result, "durationMicros") or 0) / 1000
	end
	return rows
end

local function specTable(rows: { SpecRow }): string
	local lines = { "spec\tcases\tcases_ms" }
	for _, row in rows do
		table.insert(lines, `{row.spec}\t{row.cases}\t{row.casesMs}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

local function specTimings(invocation: Cli.Invocation): number
	local source = invocation.positional[2] or "artifacts/verify/native/gate/latest.json"
	local output = invocation.positional[3] or "artifacts/spec-timings.tsv"
	if not Files.isFile(source) then
		print(("perf spec-timings: FAIL - %s is missing; run the gate first"):format(source))
		return 1
	end
	local ok, rows = pcall(specRows, readJson(source))
	if not ok then
		print(("perf spec-timings: FAIL - %s"):format(tostring(rows)))
		return 1
	end
	Files.write(output, specTable(rows :: { SpecRow }))
	print(`spec timings from the last gate outcome: {output}`)
	return 0
end

local function decode(text: string): unknown
	return Json.decode(text)
end

local function budgetFixture(): string
	local scenes: { string } = {}
	for index = 1, 15 do
		table.insert(
			scenes,
			('"scene-%02d": {"observed_p95_ms": 0.5, "frameTargetHz": 30, "ceilingMs": 8.3, "hint": "profile it"}'):format(
				index
			)
		)
	end
	return ([[{
		"schema": "facet-perf-budgets/2",
		"evidenceClass": "lute",
		"frameCeiling": {"uiShare": 0.25, "directionality": "one-way", "note": "Passing it proves NOTHING about a device."},
		"scenes": {%s},
		"deviceBudgets": {
			"console-physical": {"budgetMs": 4.1, "frameTargetHz": 60, "measured": false},
			"desktop-retail": {"budgetMs": 4.1, "frameTargetHz": 60, "measured": false},
			"phone-physical": {"budgetMs": 8.3, "frameTargetHz": 30, "measured": false}
		}
	}]]):format(table.concat(scenes, ", "))
end

local function noRows(_class: string): number
	return 0
end

local function contains(list: { string }, fragment: string): boolean
	for _, item in list do
		if string.find(item, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function expectContains(list: { string }, fragment: string): string?
	if contains(list, fragment) then
		return nil
	end
	return ("expected a line containing '%s', got: %s"):format(fragment, table.concat(list, " | "))
end

local HEADLESS_METRICS = [[{
	"frameWorkMs": {"measured": false, "reason": "headless"},
	"updateMs": {"measured": true, "p95_ms": 0.1},
	"instances": {"measured": true, "count": 4},
	"connections": {"measured": true, "count": 2},
	"memoryKb": {"measured": true, "kb": 12},
	"inputToVisibleMs": {"measured": true, "p95_ms": 0.2},
	"themeSwap": {"measured": false, "reason": "not a theme scene"}
}]]

local EVIDENCE_CLASSES = [=[[
	{"id": "lute", "level": "E1", "instrument": "os.clock", "proves": "trend", "cannotProve": "device"},
	{"id": "desktop-retail", "level": "E4", "instrument": "MicroProfiler", "proves": "device", "cannotProve": "other devices", "rows": 0},
	{"id": "phone-physical", "level": "E4", "instrument": "MicroProfiler", "proves": "device", "cannotProve": "other devices", "rows": 0},
	{"id": "console-physical", "level": "E4", "instrument": "MicroProfiler", "proves": "device", "cannotProve": "other devices", "rows": 0}
]]=]

local function metricsReport(runs: string, extra: string?): string
	return ([[{"evidenceClasses": %s, "runs": [%s]%s}]]):format(EVIDENCE_CLASSES, runs, extra or "")
end

local function headlessRun(scene: string, metricsText: string?): string
	return ([[{"scene": "%s", "device": "floorAndroid", "evidenceClass": "lute", "evidenceLevel": "E1", "authoritative": false, "deviceRun": false, "metrics": %s}]]):format(
		scene,
		metricsText or HEADLESS_METRICS
	)
end

local PRODUCTION_EXTRAS: { [string]: string } = {
	["virtual-list-scroll"] = [[{"logicalRows": 1000, "windowedRows": 24}]],
	["native-scroll-drag"] = [[{"dragMoves": 4, "drops": 1}]],
	["dense-hud"] = [[{"activationCount": 5, "activationText": "Boost x5"}]],
	["stylesheet-state-churn"] = [[{"tagsPerPass": 3}]],
	["async-image-grid"] = [[{}]],
	["screen-lifecycle-churn"] = [[{}]],
	["alert-present-dismiss"] = [[{"opens": 4, "surfaceItems": 3, "settled": 4}]],
	["picker-menu-open-close"] = [[{"opens": 4, "surfaceItems": 6, "presentation": "picker", "settled": 4}]],
	["picker-segmented-textsize"] = [[{"segmented": {"segments": 3, "textSizeBefore": 14, "textSizeAfter": 18}}]],
	["radial-menu-open-close"] = [[{"opens": 2, "surfaceItems": 6, "settled": 2}]],
	["dense-motion"] = [[{"springs": 20, "springsMoving": 20, "beats": 1, "beatCallbacks": 1, "windowedRows": 10, "logicalRows": 100, "motionSteps": 3}]],
	["control-motion"] = [[{"rekeys": 1, "flips": 1, "pulses": 1, "pops": 1, "staggerHeld": 1, "flipsSeen": 1, "shakesSeen": 1, "popsSeen": 1, "motionSteps": 2, "motionTransactions": 2}]],
	["theme-swap-flat"] = [[{"themeSwap": {"measured": true, "controlsRetained": true, "metricChanges": 0, "imageChanges": 0, "paintChanges": 9}}]],
	["theme-swap-metrics"] = [[{"themeSwap": {"measured": true, "controlsRetained": true, "metricChanges": 4}}]],
	["theme-swap-assets"] = [[{"themeSwap": {"measured": true, "controlsRetained": true, "metricChanges": 4, "imageChanges": 2}}]],
}

local function scenesReport(overrides: { [string]: string }?): string
	local runs: { string } = {}
	local names = table.clone(Evidence.PRODUCTION_ORDER)
	table.move(Evidence.THEME_ORDER, 1, #Evidence.THEME_ORDER, #names + 1, names)
	for _, scene in names do
		local extras = if overrides ~= nil and overrides[scene] ~= nil
			then overrides[scene]
			else PRODUCTION_EXTRAS[scene]
		local async = if scene == "async-image-grid" then [[, "async": {"completed": 12}]] else ""
		table.insert(
			runs,
			([[{"scene": "%s", "device": "floorAndroid", "evidenceClass": "lute", "dataset": "perf-dataset/1", "extras": %s%s}]]):format(
				scene,
				extras,
				async
			)
		)
	end
	table.insert(runs, [[{"scene": "dense-hud", "device": "consoleTenFoot", "evidenceClass": "lute"}]])
	return ([[{"schema": "facet-perf/2", "generatedAt": "2026-10-14T09:00:00Z", "runs": [%s]}]]):format(
		table.concat(runs, ", ")
	)
end

local PLACE_XML = [==[<roblox version="4">
	<Item class="ReplicatedStorage" referent="1">
		<Properties><string name="Name">ReplicatedStorage</string></Properties>
		<Item class="ModuleScript" referent="2">
			<Properties>
				<string name="Name">FacetScenarios</string>
				<ProtectedString name="Source"><![CDATA[return {}]]></ProtectedString>
			</Properties>
			<Item class="ModuleScript" referent="3">
				<Properties>
					<string name="Name">dataset</string>
					<ProtectedString name="Source"><![CDATA[local dataset = {}
dataset.VERSION = "perf-dataset/3"
return dataset
]]></ProtectedString>
				</Properties>
			</Item>
			<Item class="Script" referent="4">
				<Properties>
					<string name="Name">rows</string>
					<ProtectedString name="Source"><![CDATA[print("plugin:Install") return {}]]></ProtectedString>
				</Properties>
			</Item>
		</Item>
	</Item>
</roblox>]==]

local function pairedEntries(lines: { string }): { Json.Object }
	local entries: { Json.Object } = {}
	for _, line in lines do
		table.insert(entries, Json.asObject(Json.decode(line)) or Json.object())
	end
	return entries
end

local function benchDocument(round: number, label: string, p50: number, p95: number): Paired.Bench
	return {
		path = ("out/bench-%s-%d.json"):format(label, round),
		round = round,
		document = Json.asObject(
			decode(
				([[{"yardstickP95Ms": 0.5, "yardstickDriftPct": 1.26, "results": [{"name": "row-build", "p50_ms": %s, "p95_ms": %s}, {"name": "zz-yardstick-cpu", "p50_ms": %s, "p95_ms": %s}, {"name": "skipped", "p50_ms": null}]}]]):format(
					tostring(p50),
					tostring(p95),
					tostring(p50),
					tostring(p95)
				)
			)
		) or Json.object(),
	}
end

local CASES: { [string]: () -> { Case.Case } } = {}

CASES.budgets = function(): { Case.Case }
	return {
		{
			name = "budgets: a complete budget file passes while the run did not check device budgets",
			run = function(): string?
				local outcome = Evidence.budgets(decode(budgetFixture()), decode("{}"), noRows)
				return Case.first(
					Case.same(outcome.errors, {}, "errors"),
					Case.equal(
						outcome.summary,
						"perf budgets ok: 15 scene budgets carry baseline+frame target; 3 device budget(s) declared and unmeasured (PENDING_PHYSICAL: console-physical, desktop-retail, phone-physical)",
						"summary"
					)
				)
			end,
		},
		{
			name = "budgets: a measured device budget without a stored capture is a fabricated claim",
			run = function(): string?
				local fixture = string.gsub(
					budgetFixture(),
					'"phone%-physical": {"budgetMs": 8.3, "frameTargetHz": 30, "measured": false}',
					'"phone-physical": {"budgetMs": 8.3, "frameTargetHz": 30, "measured": true}'
				)
				local refused = Evidence.budgets(decode(fixture), decode("{}"), noRows)
				local counted = Evidence.budgets(
					decode(fixture),
					decode("{}"),
					Evidence.deviceRowCounter({ decode([[{"evidenceClass": "phone-physical", "rows": [{}, {}]}]]) })
				)
				return Case.first(
					expectContains(refused.errors, "device budget phone-physical claims measured=true"),
					Case.same(counted.errors, {}, "with a capture"),
					expectContains({ counted.summary }, "1 MEASURED and enforced (phone-physical)")
				)
			end,
		},
		{
			name = "budgets: an unreported device-budget skip in the last run fails",
			run = function(): string?
				local report =
					decode([[{"budget": {"checked": true, "skippedDeviceBudgets": [{"class": "phone-physical"}]}}]])
				local outcome = Evidence.budgets(decode(budgetFixture()), report, noRows)
				return expectContains(
					outcome.errors,
					"the last perf run recorded skipped device budgets ['phone-physical'] but ['console-physical', 'desktop-retail', 'phone-physical'] are declared unmeasured"
				)
			end,
		},
		{
			name = "budgets: schema, ceiling, scene and device faults are each reported",
			run = function(): string?
				local outcome = Evidence.budgets(
					decode(
						[[{"schema": "facet-perf-budgets/1", "frameCeiling": {"uiShare": 2}, "scenes": {"a": {"ceilingMs": 0}}, "deviceBudgets": {"phone-physical": {"measured": "yes", "budgetMs": 0}}}]]
					),
					decode("{}"),
					noRows
				)
				return Case.first(
					expectContains(outcome.errors, "unexpected schema 'facet-perf-budgets/1'"),
					expectContains(outcome.errors, "the scene budgets must be labelled"),
					expectContains(outcome.errors, "frameCeiling.uiShare is not a fraction: 2"),
					expectContains(outcome.errors, "frameCeiling must declare its one-way directionality"),
					expectContains(outcome.errors, "only 1 scene budgets"),
					expectContains(outcome.errors, "a: non-positive frame ceiling"),
					expectContains(outcome.errors, "a: no actionable hint"),
					expectContains(outcome.errors, "device budgets missing for ['console-physical', 'desktop-retail']"),
					expectContains(
						outcome.errors,
						"device budget phone-physical: measured must be true or false, not 'yes'"
					),
					expectContains(outcome.errors, "device budget phone-physical: no positive budgetMs")
				)
			end,
		},
	}
end

CASES.metrics = function(): { Case.Case }
	return {
		{
			name = "metrics: a headless record with all metric rows passes",
			run = function(): string?
				local outcome = Evidence.metrics(decode(metricsReport(headlessRun("dense-hud"))))
				return Case.first(
					Case.same(outcome.errors, {}, "errors"),
					Case.equal(
						outcome.summary,
						"perf metrics ok: 1 headless record(s) carry all 7 metric rows; 0 ingested device rows; M6 measured in 1 scene(s)",
						"summary"
					)
				)
			end,
		},
		{
			name = "metrics: absent, unexplained and unblinded metrics fail",
			run = function(): string?
				local metricsText =
					[[{"frameWorkMs": {"measured": true}, "updateMs": {"measured": false}, "connections": {"measured": false}, "memoryKb": {"measured": true}}]]
				local outcome = Evidence.metrics(
					decode(metricsReport(headlessRun("dense-hud", metricsText), [[, "injectedRegression": "x"]]))
				)
				return Case.first(
					expectContains(outcome.errors, "injectedRegression stamp"),
					expectContains(outcome.errors, "dense-hud@floorAndroid: metric instances missing entirely"),
					expectContains(
						outcome.errors,
						"dense-hud@floorAndroid: metric updateMs is unmeasured but gives no reason"
					),
					expectContains(outcome.errors, "frameWorkMs must be explicitly blind"),
					expectContains(outcome.errors, "updateMs must be measured"),
					expectContains(outcome.errors, "connections require a measurement"),
					expectContains(outcome.errors, "no scene measures input-to-visible latency (M6)")
				)
			end,
		},
		{
			name = "metrics: a device row is held to the device contract",
			run = function(): string?
				local device =
					[[{"scene": "dense-hud", "device": {"name": "Pixel 4a", "live": {"deviceId": "sim", "scalingMode": "DeviceSimulator"}}, "evidenceClass": "phone-physical", "evidenceLevel": "E1", "identity": {"studioVersion": "0.700"}, "metrics": {"frameWorkMs": {"measured": true, "p95_ms": -1}}, "provenance": {"isStudio": true, "clientKind": "studio", "instrument": "MicroProfiler", "deviceModel": "Pixel 7", "capturedAt": "2026-10-01", "attestedBy": ""}}]]
				local outcome = Evidence.metrics(
					decode(
						metricsReport(
							headlessRun("dense-hud") .. ", " .. device,
							[=[, "rejectedDeviceRows": [{"scene": "a", "fileClass": "x", "rowClass": "y"}]]=]
						)
					)
				)
				return Case.first(
					expectContains(outcome.notes, "NOTE rejected row a: file 'x' vs row 'y'"),
					expectContains(outcome.errors, "a phone-physical row must carry E4, not 'E1'"),
					expectContains(outcome.errors, "M1 p95_ms is -1"),
					expectContains(outcome.errors, "is missing metric memoryKb"),
					expectContains(outcome.errors, "carries identity.studioVersion"),
					expectContains(outcome.errors, "carries a Studio device-simulator preset id"),
					expectContains(outcome.errors, "carries a Studio device-simulator scaling mode"),
					expectContains(outcome.errors, "provenance.isStudio must be the boolean false"),
					expectContains(outcome.errors, "provenance.clientKind is 'studio', expected 'retail'"),
					expectContains(outcome.errors, "provenance.attestedBy is missing or empty"),
					expectContains(
						outcome.errors,
						"provenance.deviceModel 'Pixel 7' disagrees with device.name 'Pixel 4a'"
					),
					expectContains(outcome.errors, "dense-hud@{'name': 'Pixel 4a', 'live':")
				)
			end,
		},
		{
			name = "metrics: device-class rows must have been ingested",
			run = function(): string?
				local classes = [=[[
					{"id": "desktop-retail", "level": "E4", "instrument": "i", "proves": "p", "cannotProve": "c", "rows": 3},
					{"id": "phone-physical", "level": "E4", "instrument": "i", "proves": "p", "cannotProve": "c", "rows": 2},
					{"id": "console-physical", "level": "E4", "instrument": "i", "proves": "p", "cannotProve": "c"}
				]]=]
				local report = ([[{"evidenceClasses": %s, "ingestedDeviceRows": ["phone-physical:capture.json#1"], "runs": [%s]}]]):format(
					classes,
					headlessRun("dense-hud")
				)
				local outcome = Evidence.metrics(decode(report))
				return Case.first(
					expectContains(outcome.errors, "class desktop-retail claims 3 rows that were never ingested"),
					Case.expect(not contains(outcome.errors, "phone-physical claims"), "an ingested class was refused"),
					Case.expect(
						not contains(outcome.errors, "console-physical claims"),
						"an absent row count was refused"
					)
				)
			end,
		},
	}
end

CASES.scenes = function(): { Case.Case }
	return {
		{
			name = "scenes: every production scene doing its work passes",
			run = function(): string?
				local outcome = Evidence.scenes(decode(scenesReport()), false)
				return Case.first(
					Case.same(outcome.errors, {}, "errors"),
					Case.equal(outcome.summary, "perf scenes ok: 12 production scenes did their work at floorAndroid")
				)
			end,
		},
		{
			name = "scenes: idle production workloads fail with their recorded extras",
			run = function(): string?
				local outcome = Evidence.scenes(
					decode(scenesReport({
						["virtual-list-scroll"] = [[{"logicalRows": 10, "windowedRows": 10}]],
						["dense-hud"] = [[{"activationCount": 5, "activationText": "Boost x4"}]],
					})),
					false
				)
				return Case.first(
					expectContains(
						outcome.errors,
						"virtual-list-scroll: windowing looks wrong: {'logicalRows': 10, 'windowedRows': 10} (expect a small window over >=1000 rows)"
					),
					expectContains(outcome.errors, "dense-hud: the activate chain did not reach the mounted text"),
					expectContains(
						outcome.notes,
						"note: read artifacts/phase-4/perf.json, recorded 2026-10-14T09:00:00Z"
					)
				)
			end,
		},
		{
			name = "scenes: theme swaps must retain controls and change the right rules",
			run = function(): string?
				local passing = Evidence.scenes(decode(scenesReport()), true)
				local failing = Evidence.scenes(
					decode(scenesReport({
						["theme-swap-flat"] = [[{"themeSwap": {"measured": true, "controlsRetained": false, "metricChanges": 1, "imageChanges": 0, "paintChanges": 9}}]],
						["theme-swap-assets"] = [[{}]],
					})),
					true
				)
				return Case.first(
					Case.same(passing.errors, {}, "passing"),
					Case.equal(passing.summary, "perf scenes ok: 3 theme-swap scenes did their work at floorAndroid"),
					expectContains(failing.errors, "theme-swap-flat: the swap rebuilt the mounted controls"),
					expectContains(failing.errors, "theme-swap-flat: a palette-only swap must change paint rules"),
					expectContains(failing.errors, "theme-swap-assets: no measured themeSwap in extras ({})")
				)
			end,
		},
		{
			name = "scenes: the schema, the console profile and async completion are required",
			run = function(): string?
				local outcome = Evidence.scenes(
					decode(
						[[{"schema": "facet-perf/1", "runs": [{"scene": "async-image-grid", "device": "floorAndroid", "evidenceClass": "lute", "dataset": "d", "extras": {}, "async": {"completed": 0}}]}]]
					),
					false
				)
				return Case.first(
					expectContains(outcome.errors, "unexpected schema 'facet-perf/1'; expected facet-perf/2"),
					expectContains(outcome.errors, "no consoleTenFoot runs"),
					expectContains(outcome.errors, "dense-hud: no floorAndroid run recorded"),
					expectContains(
						outcome.errors,
						"async-image-grid: the provider completed nothing ({'completed': 0})"
					),
					expectContains(outcome.notes, "recorded unknown")
				)
			end,
		},
	}
end

CASES.place = function(): { Case.Case }
	return {
		{
			name = "place: the built place index joins names and reads protected sources",
			run = function(): string?
				local tree, order = Place.index(Xml.parse(PLACE_XML))
				local dataset = tree["ReplicatedStorage/FacetScenarios/dataset"]
				return Case.first(
					Case.same(order, {
						"ReplicatedStorage",
						"ReplicatedStorage/FacetScenarios",
						"ReplicatedStorage/FacetScenarios/dataset",
						"ReplicatedStorage/FacetScenarios/rows",
					}, "paths"),
					Case.equal(dataset and dataset.class, "ModuleScript", "class"),
					Case.expect(
						dataset ~= nil
							and string.find(dataset.source, 'dataset.VERSION = "perf-dataset/', 1, true) ~= nil,
						"the dataset source lost its version marker"
					)
				)
			end,
		},
		{
			name = "place: missing instances, wrong classes, drifted workloads and plugin use fail",
			run = function(): string?
				local tree, order = Place.index(Xml.parse(PLACE_XML))
				local problems, notes = Place.inspectTree(tree, order, function(module: string): string?
					if module == "dataset" then
						return '\nlocal dataset = {}\ndataset.VERSION = "perf-dataset/3"\nreturn dataset\n\n'
					end
					return nil
				end)
				return Case.first(
					expectContains(problems, "the built place has no ReplicatedStorage/Facet/ui"),
					expectContains(problems, "ReplicatedStorage/FacetScenarios/rows is a Script, expected ModuleScript"),
					expectContains(
						problems,
						"FacetScenarios/workloads differs from examples/performance/lab/workloads.luau"
					),
					Case.expect(
						not contains(problems, "FacetScenarios/dataset differs"),
						"surrounding whitespace made the dataset differ"
					),
					expectContains(problems, "does not carry the version marker 'VERSION = \"native-perf-rows/'"),
					expectContains(problems, "the built place source contains 'plugin:'"),
					expectContains(notes, "4 workload modules are byte-identical")
				)
			end,
		},
		{
			name = "place: the built binary must carry the Roblox magic and a plausible size",
			run = function(): string?
				local missing = Place.inspectBuilt("place.rbxl", nil, nil)
				local wrong = Place.inspectBuilt("place.rbxl", 12, "<roblox ")
				local good, goodNotes = Place.inspectBuilt("place.rbxl", 300000, "<roblox!")
				return Case.first(
					Case.same(missing, { "missing built place place.rbxl" }, "missing"),
					expectContains(wrong, "is not a Roblox binary place"),
					expectContains(wrong, "is only 12 bytes"),
					Case.same(good, {}, "good"),
					Case.same(goodNotes, { "place.rbxl: 300000 bytes, binary place" }, "notes")
				)
			end,
		},
	}
end

CASES.paired = function(): { Case.Case }
	return {
		{
			name = "paired: medians, formatting and the consistent-slower rule",
			run = function(): string?
				return Case.first(
					Case.equal(Paired.median({ 3, 1, 2 }), 2, "odd median"),
					Case.equal(Paired.median({ 4, 1, 3, 2 }), 2.5, "even median"),
					Case.equal(Paired.median({}), nil, "empty median"),
					Case.equal(Paired.number(nil), "n/a", "missing"),
					Case.equal(Paired.number(1 / 3, 3), "0.333", "digits"),
					Case.equal(Paired.consistentSlower(1.2, { 1.1, 1.3 }), true, "slower"),
					Case.equal(Paired.consistentSlower(1.2, { 0.9, 1.3 }), false, "one round faster"),
					Case.equal(Paired.consistentSlower(1.04, { 1.1 }), false, "within noise"),
					Case.equal(Paired.consistentSlower(1.2, {}), false, "no pairs")
				)
			end,
		},
		{
			name = "paired: the scene runner's marked row is read from its output",
			run = function(): string?
				local row = Paired.sceneRow('loading\r\n@@{"scene": "dense-hud", "status": "ok", "p50": 0.5}\r\n')
				return Case.first(
					Case.equal(row and Json.field(row, "status"), "ok", "status"),
					Case.equal(Paired.sceneRow("no marker\n"), nil, "unmarked"),
					Case.equal(Paired.benchRound("bench-base-12.json", "base"), 12, "round"),
					Case.equal(Paired.benchRound("bench-cand-1.json", "base"), nil, "other label"),
					Case.equal(Paired.benchRound("bench-base-1.log", "base"), nil, "log")
				)
			end,
		},
		{
			name = "paired: the scene table flags consistent slowdowns and unavailable trees",
			run = function(): string?
				local entries = pairedEntries({
					[[{"label": "base", "round": 1, "row": {"scene": "dense-hud", "status": "ok", "p50": 1.0, "p95": 2.0}}]],
					[[{"label": "cand", "round": 1, "row": {"scene": "dense-hud", "status": "ok", "p50": 1.5, "p95": 2.0}}]],
					[[{"label": "base", "round": 2, "row": {"scene": "dense-hud", "status": "ok", "p50": 1.0, "p95": 2.2}}]],
					[[{"label": "cand", "round": 2, "row": {"scene": "dense-hud", "status": "ok", "p50": 1.25, "p95": 2.2}}]],
					[[{"label": "base", "round": 1, "row": {"scene": "shadow-storm", "status": "missing"}}]],
					[[{"label": "base", "round": 2, "row": {"scene": "shadow-storm", "status": "crashed"}}]],
					[[{"label": "cand", "round": 1, "row": {"scene": "shadow-storm", "status": "ok", "p50": 1, "p95": 1}}]],
				})
				local lines = Paired.sceneTable(entries, "base", "cand")
				return Case.first(
					Case.equal(#lines, 4, "rows"),
					Case.equal(
						lines[3],
						"| dense-hud | 1.0000 | 1.3750 | 1.375 | 1.25-1.50 | 2.1000 | 2.1000 | 1.000 | 1.00-1.00 | 2.0000-2.2000 | 2.0000-2.2000 | cand slower (p50) |",
						"dense-hud"
					),
					Case.equal(
						lines[4],
						"| shadow-storm | n/a | 1.0000 | n/a | n/a | n/a | 1.0000 | n/a | n/a | n/a | 1.0000-1.0000 | base unavailable (crashed/missing) |",
						"shadow-storm"
					)
				)
			end,
		},
		{
			name = "paired: the microbenchmark table skips the yardstick flag and lists each bench run",
			run = function(): string?
				local lines = Paired.benchTables(
					{ benchDocument(2, "base", 1, 2), benchDocument(1, "base", 1, 2) },
					{ benchDocument(1, "cand", 2, 4), benchDocument(2, "cand", 2, 4) },
					"base",
					"cand"
				)
				return Case.first(
					expectContains(
						lines,
						"| row-build | 1.0000 | 2.0000 | 2.000 | 2.00-2.00 | 2.0000 | 4.0000 | 2.000 | cand slower (p50, p95) |"
					),
					expectContains(
						lines,
						"| zz-yardstick-cpu | 1.0000 | 2.0000 | 2.000 | 2.00-2.00 | 2.0000 | 4.0000 | 2.000 |  |"
					),
					Case.expect(not contains(lines, "| skipped |"), "a result without p50_ms was tabled"),
					Case.equal(lines[#lines - 3], "| base-1 | 0.5000 | 1.3 |", "first bench run"),
					Case.equal(lines[#lines], "| cand-2 | 0.5000 | 1.3 |", "last bench run"),
					Case.same(Paired.benchTables({}, {}, "base", "cand"), {}, "no benches")
				)
			end,
		},
	}
end

CASES.aggregate = function(): { Case.Case }
	return {
		{
			name = "aggregate: a dump whose base64 wraps across lines still loads",
			run = function(): string?
				local packed = Microprofiler.pack("payload")
				local close = string.find(packed, "-->", 5, true) :: number
				local encoded = string.sub(packed, 5, close - 1)
				local wrapped = string.gsub(encoded, "(" .. string.rep(".", 8) .. ")", "%1\r\n")
				local raw = "<!--" .. wrapped .. string.sub(packed, close)
				return Case.equal(Microprofiler.load("wrapped.html", raw), "payload", "wrapped dump")
			end,
		},
		{
			name = "aggregate: the synthetic dump decodes its container, header, records and layout record",
			run = function(): string?
				local body = Microprofiler.load("synthetic.html", Microprofiler.pack(Microprofiler.synthetic()))
				local dump = Microprofiler.parse(body)
				local byName: { [string]: Microprofiler.Row } = {}
				for _, row in dump.rows do
					byName[row.name] = row
				end
				local kept: { string } = {}
				for _, row in dump.rows do
					if Microprofiler.isFramework(row.name) then
						table.insert(kept, row.name)
					end
				end
				table.sort(kept)
				local records = Microprofiler.layoutRecords(dump.raw)
				return Case.first(
					Case.equal(dump.frames, 2, "frame window"),
					Case.equal(dump.frequency, 1000000000, "frequency"),
					Case.equal(#dump.rows, 3, "records"),
					Case.equal(byName["Facet/tick"] and byName["Facet/tick"].count, 2, "Facet/tick count"),
					Case.equal(
						byName["LuauUI/arrange"] and byName["LuauUI/arrange"].total,
						20000000,
						"LuauUI/arrange total"
					),
					Case.expect(byName.Sleep ~= nil, "the decoder lost the scope Sleep"),
					Case.same(kept, { "Facet/tick", "LuauUI/arrange" }, "framework filter"),
					Case.equal(#records, 1, "layout records"),
					Case.equal(records[1] and records[1].relayouts, 3, "relayouts"),
					Case.equal(records[1] and records[1].resizes, 5, "resizes")
				)
			end,
		},
		{
			name = "aggregate: the report prints the tick cross-check, the legacy note and the layout total",
			run = function(): string?
				local dump = Microprofiler.parse(Microprofiler.synthetic())
				local lines = Microprofiler.render("synthetic.html", dump, { all = false, layout = true })
				local all = Microprofiler.render("synthetic.html", dump, { all = true, layout = false })
				return Case.first(
					Case.equal(lines[2], "=== synthetic.html ===", "title"),
					Case.equal(lines[3], "  window=2 frames  freq=1000000000  tick==2 (OK)", "window"),
					expectContains(lines, "NOTE: 1 of these scopes carry the pre-rename `LuauUI/` prefix"),
					Case.equal(
						lines[6],
						"  LuauUI/arrange                  6    3.00      20.00   3.3333    10.000   12.000",
						"first scope"
					),
					expectContains(
						lines,
						"  TOTAL                                                          3        4        5"
					),
					Case.expect(not contains(lines, "Sleep"), "a non-framework scope was printed"),
					expectContains(all, "  Sleep ")
				)
			end,
		},
		{
			name = "aggregate: an empty aggregate window is announced",
			run = function(): string?
				local dump = Microprofiler.parse(Microprofiler.synthetic())
				dump.frames = 0
				local lines = Microprofiler.render("empty.html", dump, { all = false, layout = false })
				return Case.equal(lines[3], "  WINDOW=0 - NO AGGREGATE, THIS CAPTURE HAS NO TIMINGS.", "window")
			end,
		},
		{
			name = "aggregate: files that are not MicroProfiler dumps are refused",
			run = function(): string?
				local function refusal(raw: string): string
					local ok, failure = pcall(Microprofiler.load, "dump.html", raw)
					return if ok then "decoded" else tostring(failure)
				end
				local packed = Microprofiler.pack("payload")
				local damaged = "<!--"
					.. Base64.encode("GAK\7\0\0\0\0\0\0\0" .. "\x78\x01\x01\x07\x00\xf8\xffpayload\0\0\0\0")
					.. "-->"
				return Case.first(
					expectContains({ refusal("<html></html>") }, "no leading HTML comment"),
					expectContains({ refusal("<!--" .. Base64.encode("ZIP0000000000") .. "-->") }, "bad magic"),
					expectContains({ refusal(damaged) }, "Adler-32 checksum does not match"),
					expectContains({ refusal(packed) }, "decoded")
				)
			end,
		},
	}
end

CASES["spec-timings"] = function(): { Case.Case }
	return {
		{
			name = "spec-timings: cases are grouped by spec in first-seen order",
			run = function(): string?
				local outcome = decode(
					[[{"execution": {"report": {"results": [{"source": "tests/a.spec.luau", "durationMicros": 1500}, {"source": null, "durationMicros": 10}, {"source": "tests/a.spec.luau", "durationMicros": 500}]}}}]]
				)
				return Case.equal(
					specTable(specRows(outcome)),
					"spec\tcases\tcases_ms\ntests/a.spec.luau\t2\t2\nunknown\t1\t0.01\n",
					"table"
				)
			end,
		},
		{
			name = "spec-timings: an outcome without results is refused",
			run = function(): string?
				local ok = pcall(specRows, decode([[{"execution": {}}]]))
				return Case.expect(not ok, "an outcome without results was accepted")
			end,
		},
	}
end

local function noCases(): { Case.Case }
	return {}
end
CASES.run = noCases
CASES.baseline = noCases
CASES["prove-gate"] = noCases

local ORDER = { "budgets", "metrics", "scenes", "place", "paired", "aggregate", "spec-timings" }

local function allCases(): { Case.Case }
	local cases: { Case.Case } = {}
	for _, name in ORDER do
		for _, case in CASES[name]() do
			table.insert(cases, case)
		end
	end
	return cases
end

local VALUES = { "out", "rounds", "scenes" }

local KNOWN = { "selftest", "themes", "no-build", "out", "rounds", "scenes", "skip-bench", "all", "layout" }

local function run(invocation: Cli.Invocation): number
	local subcommand = invocation.positional[1]
	if subcommand == nil or CASES[subcommand] == nil then
		print(USAGE)
		return 2
	end
	local unknown = Cli.unknownFlags(invocation, KNOWN)
	if unknown ~= nil then
		print(("facet perf: unknown option %s\n\n%s"):format(unknown, USAGE))
		return 2
	end
	if Cli.switch(invocation, "selftest") then
		return Case.report("perf " .. subcommand, CASES[subcommand])
	end
	if subcommand == "run" or subcommand == "baseline" or subcommand == "prove-gate" then
		local PerfRun = require("../lib/perf_run")
		if subcommand == "run" then
			return PerfRun.run(invocation.positional[2] == "baseline")
		elseif subcommand == "baseline" then
			return PerfRun.baselineScenes(table.move(invocation.positional, 2, #invocation.positional, 1, {}))
		end
		return PerfRun.proveGate()
	end
	local ok, code = pcall(function(): number
		if subcommand == "budgets" then
			return budgets()
		elseif subcommand == "metrics" then
			return metrics()
		elseif subcommand == "scenes" then
			return scenes(Cli.switch(invocation, "themes"))
		elseif subcommand == "place" then
			return place(invocation)
		elseif subcommand == "paired" then
			local action = invocation.positional[2]
			if action == "run" then
				return pairedRun(invocation)
			elseif action == "report" then
				return pairedReport(invocation)
			end
			print(USAGE)
			return 2
		elseif subcommand == "aggregate" then
			return aggregate(invocation)
		end
		return specTimings(invocation)
	end)
	if not ok then
		print(("facet perf %s: FAIL - %s"):format(subcommand, tostring(code)))
		return 1
	end
	return code :: number
end

local command: Cli.Command = {
	name = "perf",
	summary = "Check perf budgets, metrics, scenes and the place; run paired perf; read MicroProfiler dumps.",
	usage = USAGE,
	values = VALUES,
	cases = allCases,
	run = run,
}

return command
