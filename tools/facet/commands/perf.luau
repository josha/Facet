--!strict
local Gate = require("../lib/gate")
local Verify = require("../../vendor/verify/src/core")

local fs = require("@std/fs")
local system = require("@std/system")
local Base64 = require("../../vendor/verify/src/codec/base64")
local Cli = require("../lib/cli")
local Evidence = require("../lib/perf_evidence")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Lute = require("../../vendor/verify/src/lute")
local Microprofiler = require("../lib/microprofiler")
local Memory = require("../checks/perf_memory")
local Footprint = require("../checks/perf_footprint")
local Paired = require("../lib/perf_paired")
local Retained = require("../lib/perf_retained")
local Inputs = require("../lib/perf_inputs")
local Place = require("../lib/perf_place")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet perf <subcommand> [options]

subcommands:
  run [baseline]                run every scene on each profile and check the trend budgets (exit 2 on a
                                host timing failure); baseline rewrites bench/perf_budgets.json instead
  baseline SCENE...             rebaseline only the named scenes in bench/perf_budgets.json
  prove-gate                    inject a regression, prove that run fails, then rerun it clean
  budgets                       check bench/perf_budgets.json and the last perf run's skipped device budgets
  metrics                       check the metric rows of artifacts/phase-4/perf.json (exit 2 when it is absent)
  memory [REPORT.json]          gate exact teardown counts and report resource growth during churn
  footprint [REPORT.json]       measure control resources and check the committed ceilings
  capture --workspace DIR --out DIR [--devices a,b] [--tap TEXT]...
                                capture a built game in owned Studio sessions, without an agent
  profile SCENE [TRACE.json]    sample the unchanged scene with the Lute profiler
  prove-memory-gate             plant native and Compose leaks and prove that the teardown gate fails
  prove-retained-memory [--out DIR]
                                compare unchanged and retained-allocation controls for every paired scene
  affected BASE                 run paired performance when its code, fixtures or toolchain change; exit 3 when unchanged
  scenes [--themes]             check that each production (or theme-swap) scene did its work
  place [--no-build]            build examples/performance.project.json and check the place
  paired run --out DIR [--rounds N] [--scenes a,b] [--skip-bench] [--gate] [--summary FILE] LABEL=WORKTREE...
                                run the paired scenes and the bench in each worktree, round by round
                                --gate requires two arms and six full rounds; pass after three or continue all measurements through six; invalid evidence exits 2, invalid CPU calibration exits 75
  paired report DIR FIRST SECOND --rounds N [--scenes a,b] [--skip-bench] [--gate] [--summary FILE]
                                require complete timing and retained heap measurements; invalid evidence exits 2; --gate exits 1 for a consistent latency or retained heap regression; --summary appends the summary and tables as Markdown
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

local function memory(recorded: string?): number
	local path = recorded or Evidence.PERF
	if not Files.isFile(path) then
		print("perf memory: FAIL - run lute run tools/facet perf run first")
		return 1
	end
	local report = readJson(path)
	for _, trend in Memory.growth(report) do
		print("TREND " .. trend)
	end
	local errors = Memory.check(report)
	if #errors > 0 then
		return failLines(errors)
	end
	print("perf memory: PASS - exact resource counts return to zero after teardown; churn growth is a trend")
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

local function footprint(path: string?): number
	local output = path or "artifacts/perf-footprint.json"
	if Files.isFile(output) then
		Files.remove(output)
	end
	local result = Run.inherit({ Run.lute(), "run", "tools/engine/perf_footprint.luau", output })
	if not result.ok or not Files.isFile(output) then
		print("perf footprint: failed to produce a control census")
		return 1
	end
	local errors = Footprint.check(readJson(output), readJson("bench/footprint_budgets.json"))
	if #errors > 0 then
		return failLines(errors)
	end
	print("perf footprint: PASS - all control counts fit their ceilings and teardown counts are zero")
	return 0
end

local function profile(scene: string?, output: string?): number
	if scene == nil then
		print(USAGE)
		return 2
	end
	local trace = output or `artifacts/{scene}-profile.json`
	Files.makeDirectory(Files.parent(trace))
	return Run.inherit({
		Run.lute(),
		"run",
		"--profile",
		"--profile-output",
		trace,
		"tools/engine/perf_profile.luau",
		scene,
	}).code
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
		table.insert(parts, 1, current)
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
			tree, order = Place.index(Lute.model.read(Files.read(xmlPath)))
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

local function benchmarkCommand(): { string }
	return { Run.lute(), "run", Files.absolute("tools/facet"), "bench" }
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

local function pairedReport(invocation: Cli.Invocation, canContinue: boolean?): number
	local out, first, second = invocation.positional[3], invocation.positional[4], invocation.positional[5]
	local rounds = tonumber(Cli.flag(invocation, "rounds") or "")
	if
		out == nil
		or first == nil
		or second == nil
		or first == second
		or rounds == nil
		or rounds < 1
		or rounds == math.huge
		or rounds % 1 ~= 0
	then
		print(USAGE)
		return 2
	end
	local valid, loaded = pcall(function()
		local entries: { Json.Object } = {}
		for _, line in Files.lines(Files.read(Files.join(out, "scenes.jsonl"))) do
			if string.find(line, "%S") ~= nil then
				table.insert(entries, Json.asObject(Json.decode(line)) or Json.object())
			end
		end
		return { entries = entries, first = benchesFor(out, first), second = benchesFor(out, second) }
	end)
	if not valid then
		print("paired report: evidence is unreadable: " .. tostring(loaded))
		return 2
	end
	local selected = Cli.flag(invocation, "scenes")
	local sceneList = if selected ~= nil and selected ~= "" then string.split(selected, ",") else Paired.SCENES
	local scope: Paired.Scope =
		{ rounds = rounds, scenes = sceneList, bench = not Cli.switch(invocation, "skip-bench") }
	local errors = Paired.validate(scope, loaded.entries, loaded.first, loaded.second, first, second)
	print(
		`paired scope: {rounds} rounds, {#sceneList} scenes; microbenchmarks {if scope.bench
			then "required"
			else "unselected"}`
	)
	if #errors > 0 then
		for _, detail in errors do
			print("paired report: invalid evidence: " .. detail)
		end
		return 2
	end
	local entries = loaded.entries
	local lines = Paired.sceneTable(entries, first, second)
	for _, line in Paired.benchTables(loaded.first, loaded.second, first, second) do
		table.insert(lines, line)
	end
	local slower: { string } = {}
	for _, line in lines do
		if string.find(line, second .. " slower (", 1, true) then
			table.insert(slower, (string.match(line, "^| ([^|]+) |") or line))
		end
	end
	local summary = Paired.summary(lines, first, second)
	local memoryLines, memoryFlags = Paired.memoryTable(entries, first, second)
	if #memoryFlags > 0 then
		summary[1] = "### Paired performance: FAIL"
	end
	table.insert(summary, "")
	table.insert(
		summary,
		`Retained Luau heap: {if #memoryFlags == 0 then "PASS" else "FAIL"}. Growth must exceed 5% and 64 KiB in the median and every paired round, for mounted or teardown retention.`
	)
	for _, flag in memoryFlags do
		table.insert(summary, "- " .. flag)
	end
	table.move(memoryLines, 1, #memoryLines, #lines + 1, lines)
	table.move(memoryFlags, 1, #memoryFlags, #slower + 1, slower)
	summary[1] ..= ` ({rounds} rounds{if canContinue == true
			and Cli.switch(invocation, "gate")
			and #slower > 0
		then ", provisional; continuing"
		elseif canContinue ~= nil then ", final"
		else ""})`
	for _, line in summary do
		print(line)
	end
	print("")
	for _, line in lines do
		print(line)
	end
	local target = Cli.flag(invocation, "summary")
	if target ~= nil then
		local page = table.clone(summary)
		table.insert(page, "")
		table.insert(page, "<details><summary>Full paired tables</summary>")
		table.insert(page, "")
		table.move(lines, 1, #lines, #page + 1, page)
		table.insert(page, "")
		table.insert(page, "</details>")
		table.insert(page, "")
		local existing = if Files.isFile(target) then Files.read(target) else ""
		Files.write(target, existing .. table.concat(page, "\n") .. "\n")
	end
	if Cli.switch(invocation, "gate") and #slower > 0 then
		print(("paired gate: FAIL - %s regresses in %s"):format(second, table.concat(slower, ", ")))
		return 1
	end
	return 0
end

local function pairedRun(invocation: Cli.Invocation, capture: typeof(Run.capture)?): number
	local out = Cli.flag(invocation, "out")
	local trees: { { label: string, tree: string } } = {}
	for index = 3, #invocation.positional do
		local pair = invocation.positional[index]
		local label, tree = string.match(pair, "^([^=]*)=(.*)$")
		table.insert(trees, { label = label or pair, tree = Files.absolute(tree or "") })
	end
	local rounds = tonumber(Cli.flag(invocation, "rounds") or "5")
	if out == nil or #trees < 2 or rounds == nil or rounds < 1 or rounds == math.huge or rounds % 1 ~= 0 then
		print(USAGE)
		return 2
	end
	local selected = Cli.flag(invocation, "scenes")
	local sceneList: { string } = if selected ~= nil and selected ~= ""
		then string.split(selected, ",")
		else Paired.SCENES
	local skipBench = Cli.switch(invocation, "skip-bench")
	local gate = Cli.switch(invocation, "gate")
	if gate and (#trees ~= 2 or trees[1].label == trees[2].label or rounds ~= 6 or selected ~= nil or skipBench) then
		print("paired run: --gate requires two distinct arms, --rounds 6, every scene and the bench")
		return 2
	end
	local execute = capture or Run.capture
	local environment = toolEnvironment(rokitDirectories(), false)
	local benchCommand = benchmarkCommand()
	local log = Files.join(out, "log.txt")
	local rows = Files.join(out, "scenes.jsonl")
	if Files.isDirectory(out) and #Files.list(out) > 0 then
		print("paired run: output directory must be empty")
		return 2
	end
	Files.makeDirectory(out)
	for _, entry in trees do
		for _, path in { "bench/paired_scene.luau", "bench/paired_workload.luau" } do
			local source = Files.absolute(path)
			local target = Files.join(entry.tree, path)
			if not samePath(target, source) then
				Files.write(target, Files.read(source))
			end
		end
	end
	for round = 1, rounds do
		append(log, ("round %d start %s load %s\n"):format(round, os.date("%H:%M:%S"), loadAverage()))
		for _, scene in sceneList do
			for position = 1, #trees do
				local entry = trees[Paired.armIndex(round, position, #trees)]
				local result = execute(
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
				if not result.ok or Json.field(row, "status") ~= "ok" then
					print(`paired run: {entry.label} scene {scene} failed or was unavailable`)
					return 2
				end
			end
		end
		if not skipBench then
			for position = 1, #trees do
				local entry = trees[Paired.armIndex(round, position, #trees)]
				append(log, ("round %d %s bench start %s\n"):format(round, entry.label, os.date("%H:%M:%S")))
				local artifact = Files.join(entry.tree, "artifacts", "bench.json")
				if Files.isFile(artifact) then
					Files.remove(artifact)
				end
				local bench = execute(benchCommand, { cwd = entry.tree, env = environment })
				Files.write(
					Files.join(out, ("bench-%s-%d.log"):format(entry.label, round)),
					bench.stdout .. bench.stderr
				)
				local document: unknown = nil
				if Files.isFile(artifact) then
					local bytes = Files.read(artifact)
					Files.write(Files.join(out, ("bench-%s-%d.json"):format(entry.label, round)), bytes)
					local valid, decoded = pcall(Json.decode, bytes)
					if valid then
						document = decoded
					end
				end
				local errors, calibration = Paired.benchOutcome(bench.code, document)
				if #errors > 0 then
					for _, detail in errors do
						print(`paired run: {entry.label} round {round}: {detail}`)
					end
					return if calibration then 75 else 2
				end
				append(log, ("round %d %s bench end %s\n"):format(round, entry.label, os.date("%H:%M:%S")))
			end
		end
		append(log, ("round %d end %s\n"):format(round, os.date("%H:%M:%S")))
		if gate and (round == 3 or round == rounds) then
			local report = table.clone(invocation)
			report.positional = { "paired", "report", out, trees[1].label, trees[2].label }
			report.flags = table.clone(invocation.flags)
			report.flags.rounds = tostring(round)
			local status = pairedReport(report, round < rounds)
			if status ~= 1 or round == rounds then
				append(log, if status == 0 then "DONE\n" else `GATE FAILED {status}\n`)
				return status
			end
			append(
				log,
				"Statistical slowdown after three rounds; retaining every measurement and continuing through six.\n"
			)
		end
	end
	append(log, "DONE\n")
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

local function expectContains(list: { string }, fragment: string)
	Verify.expect(table.concat(list, "\n")):toContain(fragment)
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

local function memoryFixture(mounted: number?, teardown: number?): Json.Object
	local result = Json.object()
	local fields: { [string]: string | number } = {
		method = Lute.memory.METHOD,
		cycles = Retained.CYCLES,
		baselineKb = 1000,
		baselineAllocations = 10,
		mountedAllocations = 10,
		teardownAllocations = 10,
	}
	for key, value in fields do
		Json.set(result, key, value)
	end
	Json.set(result, "mountedKb", 1000 + (mounted or 1000))
	Json.set(result, "teardownKb", 1000 + (teardown or 0))
	Json.set(result, "mountedRetainedKb", mounted or 1000)
	Json.set(result, "teardownRetainedKb", teardown or 0)
	return result
end

local function pairedEntries(lines: { string }): { Json.Object }
	local entries: { Json.Object } = {}
	for _, line in lines do
		local entry = Json.asObject(Json.decode(line)) or Json.object()
		local row = Json.asObject(Json.field(entry, "row"))
		if row ~= nil and Json.field(row, "memory") == nil then
			Json.set(row, "memory", memoryFixture())
		end
		table.insert(entries, entry)
	end
	return entries
end

local function benchDocument(round: number, label: string, p50: number, p95: number): Paired.Bench
	return {
		path = ("out/bench-%s-%d.json"):format(label, round),
		round = round,
		document = Json.asObject(
			decode(
				([[{"yardstickP95Ms": 0.5, "yardstickDriftPct": 1.26, "yardstickMedianDriftPct": 0.4, "results": [{"name": "row-build", "p50_ms": %s, "p95_ms": %s}, {"name": "zz-yardstick-cpu", "p50_ms": %s, "p95_ms": %s}, {"name": "skipped", "p50_ms": null}]}]]):format(
					tostring(p50),
					tostring(p95),
					tostring(p50),
					tostring(p95)
				)
			)
		) or Json.object(),
	}
end

local function requiredBench(round: number, label: string): Paired.Bench
	return {
		path = `out/bench-{label}-{round}.json`,
		round = round,
		document = assert(Json.asObject(decode([[{
			"schema": "facet-bench/1", "status": "PASS", "proofStatus": "stable-cpu-rate-trend",
			"yardstickP95Ms": 0.5, "yardstickDriftPct": 1.2, "yardstickMedianDriftPct": 1.2,
			"results": [{"name": "table-resize-drag", "p50_ms": 1, "p95_ms": 2, "p99_ms": 3, "samples": 1500}]
		}]]))),
	}
end

local function requiredPairs(): (Paired.Scope, { Json.Object }, { Paired.Bench }, { Paired.Bench })
	local entries: { Json.Object } = {}
	local first, second = {}, {}
	for round = 1, 2 do
		for _, label in { "base", "cand" } do
			table.insert(
				entries,
				assert(
					Json.asObject(
						decode(
							([[{"label":"%s","round":%d,"row":{"scene":"dense-hud","status":"ok","p50":1,"p95":2}}]]):format(
								label,
								round
							)
						)
					)
				)
			)
		end
		table.insert(first, requiredBench(round, "base"))
		table.insert(second, requiredBench(round, "cand"))
	end
	for _, entry in entries do
		Json.set(assert(Json.asObject(Json.field(entry, "row"))), "memory", memoryFixture())
	end
	return { rounds = 2, scenes = { "dense-hud" }, bench = true }, entries, first, second
end

local function pairedRunFixture(test: Verify.Context, mode: string): ()
	local root = Files.temporaryDirectory("facet-paired-checkpoint-")
	test:defer(function()
		Files.remove(root)
	end)
	local out = Files.join(root, "out")
	local counts: { [string]: number } = { base = 0, cand = 0 }
	local arms: { string } = {}
	local calls: { string } = {}
	local summary = Files.join(root, "summary.md")
	local arguments = { "perf", "paired", "run", "--out", out, "--rounds", "6", "--summary", summary }
	if mode ~= "manual" then
		table.insert(arguments, "--gate")
	end
	for _, label in { "base", "cand" } do
		table.insert(arguments, label .. "=" .. Files.join(root, label))
	end
	local status = pairedRun(Cli.parse(arguments, { "out", "rounds", "summary" }), function(argv, options): Run.Result
		local tree = assert(options and options.cwd)
		local label = if tree == Files.join(root, "base") then "base" else "cand"
		local round = counts[label] + 1
		local output = ""
		if argv[3] == "bench/paired_scene.luau" then
			table.insert(calls, label .. ":" .. argv[4])
			local row = Json.object()
			Json.set(row, "scene", argv[4])
			Json.set(row, "status", "ok")
			local slower = label == "cand" and (mode == "fail" or (mode == "continue" and round <= 3))
			Json.set(row, "p50", if slower then 2 else 1)
			Json.set(row, "p95", if slower then 4 else 2)
			local retained = label == "cand" and (mode == "memory" or (mode == "memory-continue" and round <= 3))
			Json.set(row, "memory", memoryFixture(if retained then 2000 else 1000, if retained then 1000 else 0))
			if mode == "memory-invalid" and label == "cand" and round == 3 then
				Json.set(row, "memory", nil)
			end
			if mode == "invalid" and label == "cand" and round == 3 then
				Json.set(row, "scene", "unselected-scene")
			end
			output = "@@" .. Json.encode(row)
		else
			table.insert(calls, label .. ":bench")
			counts[label] = round
			table.insert(arms, label)
			local document = requiredBench(round, label).document
			if mode == "calibration" then
				Json.set(document, "status", "FAIL")
				Json.set(document, "proofStatus", "unstable-cpu-rate")
				Json.set(document, "failureKind", "calibration")
				Json.set(document, "expectedMeasurements", 1)
				Json.set(document, "yardstickMedianDriftPct", 30)
			end
			Files.write(Files.join(tree, "artifacts/bench.json"), Json.encode(document))
		end
		local code = if mode == "calibration" and output == "" then 2 else 0
		return { ok = code == 0, code = code, stdout = output, stderr = "", timedOut = false }
	end)
	local rounds = if mode == "continue"
			or mode == "fail"
			or mode == "manual"
			or mode == "memory"
			or mode == "memory-continue"
		then 6
		else 3
	if mode == "calibration" then
		Verify.expect(status):toBe(75)
		Verify.expect(#arms):toBe(1)
		return
	end
	local entries = pairedEntries(Files.lines(Files.read(Files.join(out, "scenes.jsonl"))))
	local expected = if rounds == 6
		then "base,cand,cand,base,base,cand,cand,base,base,cand,cand,base"
		else "base,cand,cand,base,base,cand"
	local order = string.split(expected, ",")
	local expectedCalls: { string } = {}
	for round = 1, rounds do
		for _, scene in Paired.SCENES do
			for position = 1, 2 do
				table.insert(expectedCalls, order[(round - 1) * 2 + position] .. ":" .. scene)
			end
		end
		for position = 1, 2 do
			table.insert(expectedCalls, order[(round - 1) * 2 + position] .. ":bench")
		end
	end
	local summaryCount = 0
	local summaryText = ""
	if Files.isFile(summary) then
		summaryText = Files.read(summary)
		for _ in string.gmatch(summaryText, "### Paired performance:") do
			summaryCount += 1
		end
	end
	local invalid = mode == "invalid" or mode == "memory-invalid"
	local failed = mode == "fail" or mode == "memory"
	local final = if failed then "FAIL" else "PASS"
	Verify.expect(status):toBe(if invalid then 2 elseif failed then 1 else 0)
	Verify.expect(summaryCount):toBe(if mode == "manual" or invalid then 0 elseif rounds == 6 then 2 else 1)
	Verify.expect(table.concat(arms, ",")):toBe(expected)
	Verify.expect(calls):toEqual(expectedCalls)
	if summaryCount > 0 then
		Verify.expect(string.find(summaryText, `{final} ({rounds} rounds, final)`, 1, true) ~= nil):toBe(true)
	end
	if summaryCount == 2 then
		Verify.expect(string.find(summaryText, "FAIL (3 rounds, provisional; continuing)", 1, true) ~= nil):toBe(true)
	end
	Verify.expect(#entries):toBe(rounds * 2 * #Paired.SCENES)
	Verify.expect(#benchesFor(out, "base") + #benchesFor(out, "cand")):toBe(rounds * 2)
end

local REGISTRATIONS: { [string]: (Verify.Harness, string) -> () } = {}

REGISTRATIONS.budgets = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "budgets::"
	harness:case(prefix .. "budgets: a complete budget file passes while the run did not check device budgets", {
		id = idPrefix .. "budgets: a complete budget file passes while the run did not check device budgets",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.budgets(decode(budgetFixture()), decode("{}"), noRows)
			Verify.expect(outcome.errors):toEqual({})
			Verify.expect(outcome.summary):toBe(
				"perf budgets ok: 15 scene budgets carry baseline+frame target; 3 device budget(s) declared and unmeasured (PENDING_PHYSICAL: console-physical, desktop-retail, phone-physical)"
			)
		end,
	})
	harness:case(prefix .. "budgets: a measured device budget without a stored capture is a fabricated claim", {
		id = idPrefix .. "budgets: a measured device budget without a stored capture is a fabricated claim",
		run = function(test: Verify.Context): ()
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
			expectContains(refused.errors, "device budget phone-physical claims measured=true")
			Verify.expect(counted.errors):toEqual({})
			expectContains({ counted.summary }, "1 MEASURED and enforced (phone-physical)")
		end,
	})
	harness:case(prefix .. "budgets: an unreported device-budget skip in the last run fails", {
		id = idPrefix .. "budgets: an unreported device-budget skip in the last run fails",
		run = function(test: Verify.Context): ()
			local report =
				decode([[{"budget": {"checked": true, "skippedDeviceBudgets": [{"class": "phone-physical"}]}}]])
			local outcome = Evidence.budgets(decode(budgetFixture()), report, noRows)
			expectContains(
				outcome.errors,
				"the last perf run recorded skipped device budgets ['phone-physical'] but ['console-physical', 'desktop-retail', 'phone-physical'] are declared unmeasured"
			)
		end,
	})
	harness:case(prefix .. "budgets: schema, ceiling, scene and device faults are each reported", {
		id = idPrefix .. "budgets: schema, ceiling, scene and device faults are each reported",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.budgets(
				decode(
					[[{"schema": "facet-perf-budgets/1", "frameCeiling": {"uiShare": 2}, "scenes": {"a": {"ceilingMs": 0}}, "deviceBudgets": {"phone-physical": {"measured": "yes", "budgetMs": 0}}}]]
				),
				decode("{}"),
				noRows
			)
			expectContains(outcome.errors, "unexpected schema 'facet-perf-budgets/1'")
			expectContains(outcome.errors, "the scene budgets must be labelled")
			expectContains(outcome.errors, "frameCeiling.uiShare is not a fraction: 2")
			expectContains(outcome.errors, "frameCeiling must declare its one-way directionality")
			expectContains(outcome.errors, "only 1 scene budgets")
			expectContains(outcome.errors, "a: non-positive frame ceiling")
			expectContains(outcome.errors, "a: no actionable hint")
			expectContains(outcome.errors, "device budgets missing for ['console-physical', 'desktop-retail']")
			expectContains(outcome.errors, "device budget phone-physical: measured must be true or false, not 'yes'")
			expectContains(outcome.errors, "device budget phone-physical: no positive budgetMs")
		end,
	})
end

REGISTRATIONS.metrics = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "metrics::"
	harness:case(prefix .. "metrics: a headless record with all metric rows passes", {
		id = idPrefix .. "metrics: a headless record with all metric rows passes",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.metrics(decode(metricsReport(headlessRun("dense-hud"))))
			Verify.expect(outcome.errors):toEqual({})
			Verify.expect(outcome.summary):toBe(
				"perf metrics ok: 1 headless record(s) carry all 7 metric rows; 0 ingested device rows; M6 measured in 1 scene(s)"
			)
		end,
	})
	harness:case(prefix .. "metrics: absent, unexplained and unblinded metrics fail", {
		id = idPrefix .. "metrics: absent, unexplained and unblinded metrics fail",
		run = function(test: Verify.Context): ()
			local metricsText =
				[[{"frameWorkMs": {"measured": true}, "updateMs": {"measured": false}, "connections": {"measured": false}, "memoryKb": {"measured": true}}]]
			local outcome = Evidence.metrics(
				decode(metricsReport(headlessRun("dense-hud", metricsText), [[, "injectedRegression": "x"]]))
			)
			expectContains(outcome.errors, "injectedRegression stamp")
			expectContains(outcome.errors, "dense-hud@floorAndroid: metric instances missing entirely")
			expectContains(outcome.errors, "dense-hud@floorAndroid: metric updateMs is unmeasured but gives no reason")
			expectContains(outcome.errors, "frameWorkMs must be explicitly blind")
			expectContains(outcome.errors, "updateMs must be measured")
			expectContains(outcome.errors, "connections require a measurement")
			expectContains(outcome.errors, "no scene measures input-to-visible latency (M6)")
		end,
	})
	harness:case(prefix .. "metrics: a device row is held to the device contract", {
		id = idPrefix .. "metrics: a device row is held to the device contract",
		run = function(test: Verify.Context): ()
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
			expectContains(outcome.notes, "NOTE rejected row a: file 'x' vs row 'y'")
			expectContains(outcome.errors, "a phone-physical row must carry E4, not 'E1'")
			expectContains(outcome.errors, "M1 p95_ms is -1")
			expectContains(outcome.errors, "is missing metric memoryKb")
			expectContains(outcome.errors, "carries identity.studioVersion")
			expectContains(outcome.errors, "carries a Studio device-simulator preset id")
			expectContains(outcome.errors, "carries a Studio device-simulator scaling mode")
			expectContains(outcome.errors, "provenance.isStudio must be the boolean false")
			expectContains(outcome.errors, "provenance.clientKind is 'studio', expected 'retail'")
			expectContains(outcome.errors, "provenance.attestedBy is missing or empty")
			expectContains(outcome.errors, "provenance.deviceModel 'Pixel 7' disagrees with device.name 'Pixel 4a'")
			expectContains(outcome.errors, "dense-hud@{'name': 'Pixel 4a', 'live':")
		end,
	})
	harness:case(prefix .. "metrics: device-class rows must have been ingested", {
		id = idPrefix .. "metrics: device-class rows must have been ingested",
		run = function(test: Verify.Context): ()
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
			expectContains(outcome.errors, "class desktop-retail claims 3 rows that were never ingested")
			Verify.expect(not contains(outcome.errors, "phone-physical claims"))
				:toBeTrueWith("an ingested class was refused")
			Verify.expect(not contains(outcome.errors, "console-physical claims"))
				:toBeTrueWith("an absent row count was refused")
		end,
	})
end

REGISTRATIONS.scenes = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "scenes::"
	harness:case(prefix .. "scenes: every production scene doing its work passes", {
		id = idPrefix .. "scenes: every production scene doing its work passes",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.scenes(decode(scenesReport()), false)
			Verify.expect(outcome.errors):toEqual({})
			Verify.expect(outcome.summary):toBe("perf scenes ok: 12 production scenes did their work at floorAndroid")
		end,
	})
	harness:case(prefix .. "scenes: idle production workloads fail with their recorded extras", {
		id = idPrefix .. "scenes: idle production workloads fail with their recorded extras",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.scenes(
				decode(scenesReport({
					["virtual-list-scroll"] = [[{"logicalRows": 10, "windowedRows": 10}]],
					["dense-hud"] = [[{"activationCount": 5, "activationText": "Boost x4"}]],
				})),
				false
			)
			expectContains(
				outcome.errors,
				"virtual-list-scroll: windowing looks wrong: {'logicalRows': 10, 'windowedRows': 10} (expect a small window over >=1000 rows)"
			)
			expectContains(outcome.errors, "dense-hud: the activate chain did not reach the mounted text")
			expectContains(outcome.notes, "note: read artifacts/phase-4/perf.json, recorded 2026-10-14T09:00:00Z")
		end,
	})
	harness:case(prefix .. "scenes: theme swaps must retain controls and change the right rules", {
		id = idPrefix .. "scenes: theme swaps must retain controls and change the right rules",
		run = function(test: Verify.Context): ()
			local passing = Evidence.scenes(decode(scenesReport()), true)
			local failing = Evidence.scenes(
				decode(scenesReport({
					["theme-swap-flat"] = [[{"themeSwap": {"measured": true, "controlsRetained": false, "metricChanges": 1, "imageChanges": 0, "paintChanges": 9}}]],
					["theme-swap-assets"] = [[{}]],
				})),
				true
			)
			Verify.expect(passing.errors):toEqual({})
			Verify.expect(passing.summary):toBe("perf scenes ok: 3 theme-swap scenes did their work at floorAndroid")
			expectContains(failing.errors, "theme-swap-flat: the swap rebuilt the mounted controls")
			expectContains(failing.errors, "theme-swap-flat: a palette-only swap must change paint rules")
			expectContains(failing.errors, "theme-swap-assets: no measured themeSwap in extras ({})")
		end,
	})
	harness:case(prefix .. "scenes: the schema, the console profile and async completion are required", {
		id = idPrefix .. "scenes: the schema, the console profile and async completion are required",
		run = function(test: Verify.Context): ()
			local outcome = Evidence.scenes(
				decode(
					[[{"schema": "facet-perf/1", "runs": [{"scene": "async-image-grid", "device": "floorAndroid", "evidenceClass": "lute", "dataset": "d", "extras": {}, "async": {"completed": 0}}]}]]
				),
				false
			)
			expectContains(outcome.errors, "unexpected schema 'facet-perf/1'; expected facet-perf/2")
			expectContains(outcome.errors, "no consoleTenFoot runs")
			expectContains(outcome.errors, "dense-hud: no floorAndroid run recorded")
			expectContains(outcome.errors, "async-image-grid: the provider completed nothing ({'completed': 0})")
			expectContains(outcome.notes, "recorded unknown")
		end,
	})
end

REGISTRATIONS.place = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "place::"
	harness:case(prefix .. "place: the built place index joins names and reads protected sources", {
		id = idPrefix .. "place: the built place index joins names and reads protected sources",
		run = function(test: Verify.Context): ()
			local tree, order = Place.index(Lute.model.read(PLACE_XML))
			local dataset = tree["ReplicatedStorage/FacetScenarios/dataset"]
			Verify.expect(order):toEqual({
				"ReplicatedStorage",
				"ReplicatedStorage/FacetScenarios",
				"ReplicatedStorage/FacetScenarios/dataset",
				"ReplicatedStorage/FacetScenarios/rows",
			})
			Verify.expect(dataset and dataset.class):toBe("ModuleScript")
			Verify.expect(
				dataset ~= nil and string.find(dataset.source, 'dataset.VERSION = "perf-dataset/', 1, true) ~= nil
			)
				:toBeTrueWith("the dataset source lost its version marker")
		end,
	})
	harness:case(prefix .. "place: missing instances, wrong classes, drifted workloads and plugin use fail", {
		id = idPrefix .. "place: missing instances, wrong classes, drifted workloads and plugin use fail",
		run = function(test: Verify.Context): ()
			local tree, order = Place.index(Lute.model.read(PLACE_XML))
			local problems, notes = Place.inspectTree(tree, order, function(module: string): string?
				if module == "dataset" then
					return '\nlocal dataset = {}\ndataset.VERSION = "perf-dataset/3"\nreturn dataset\n\n'
				end
				return nil
			end)
			expectContains(problems, "the built place has no ReplicatedStorage/Facet/ui")
			expectContains(problems, "ReplicatedStorage/FacetScenarios/rows is a Script, expected ModuleScript")
			expectContains(problems, "FacetScenarios/workloads differs from examples/performance/lab/workloads.luau")
			Verify.expect(not contains(problems, "FacetScenarios/dataset differs"))
				:toBeTrueWith("surrounding whitespace made the dataset differ")
			expectContains(problems, "does not carry the version marker 'VERSION = \"native-perf-rows/'")
			expectContains(problems, "the built place source contains 'plugin:'")
			expectContains(notes, "4 workload modules are byte-identical")
		end,
	})
	harness:case(prefix .. "place: the built binary must carry the Roblox magic and a plausible size", {
		id = idPrefix .. "place: the built binary must carry the Roblox magic and a plausible size",
		run = function(test: Verify.Context): ()
			local missing = Place.inspectBuilt("place.rbxl", nil, nil)
			local wrong = Place.inspectBuilt("place.rbxl", 12, "<roblox ")
			local good, goodNotes = Place.inspectBuilt("place.rbxl", 300000, "<roblox!")
			Verify.expect(missing):toEqual({ "missing built place place.rbxl" })
			expectContains(wrong, "is not a Roblox binary place")
			expectContains(wrong, "is only 12 bytes")
			Verify.expect(good):toEqual({})
			Verify.expect(goodNotes):toEqual({ "place.rbxl: 300000 bytes, binary place" })
		end,
	})
end

REGISTRATIONS.paired = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "paired::"
	for _, mode in { "memory", "memory-continue", "memory-invalid" } do
		harness:case(prefix .. "retained memory checkpoint " .. mode, function(test)
			pairedRunFixture(test, mode)
		end)
	end
	harness:case(prefix .. "retained memory requires both growth bounds and every paired round", function(test)
		local function readings(mounted: number, teardown: number): { Retained.Reading }
			return {
				{ mounted = mounted, teardown = teardown },
				{ mounted = mounted, teardown = teardown },
				{ mounted = mounted, teardown = teardown },
			}
		end
		test:expect(Retained.compare(readings(1000, 0), readings(1064, 64))[1].regressed):toBe(false)
		test:expect(Retained.compare(readings(1000, 0), readings(1065, 65))[1].regressed):toBe(true)
		test:expect(Retained.compare(readings(10000, 0), readings(10065, 1))[1].regressed):toBe(false)
		test:expect(Retained.compare(readings(1000, 0), readings(1000, 65))[2].regressed):toBe(true)
		local noisy = readings(1100, 100)
		noisy[3] = { mounted = 1040, teardown = 40 }
		test:expect(Retained.compare(readings(1000, 0), noisy)[1].regressed):toBe(false)
		test:expect(Retained.compare(readings(1000, 0), noisy)[2].regressed):toBe(false)
	end)
	harness:case(prefix .. "retained memory rejects missing malformed and contradictory measurements", function(test)
		for _, key in
			{
				"method",
				"cycles",
				"baselineKb",
				"mountedKb",
				"teardownKb",
				"mountedRetainedKb",
				"teardownRetainedKb",
				"baselineAllocations",
				"mountedAllocations",
				"teardownAllocations",
			}
		do
			local value = memoryFixture()
			Json.set(value, key, nil)
			local reading = Retained.read(value)
			test:expect(reading):toBe(nil)
		end
		for _, bad in { -1, math.huge, math.huge - math.huge } do
			local value = memoryFixture()
			Json.set(value, "mountedKb", bad)
			test:expect((Retained.read(value))):toBe(nil)
		end
		local mismatched = memoryFixture()
		Json.set(mismatched, "mountedRetainedKb", 2000)
		test:expect((Retained.read(mismatched))):toBe(nil)
		local scope, entries, first, second = requiredPairs()
		Json.set(assert(Json.asObject(Json.field(entries[1], "row"))), "memory", nil)
		test:expect(#Paired.validate(scope, entries, first, second, "base", "cand") > 0):toBe(true)
	end)
	harness:case(prefix .. "paired: a valid full-scope pass ends after three rounds", {
		id = idPrefix .. "paired: a valid full-scope pass ends after three rounds",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "pass")
		end,
	})
	harness:case(prefix .. "paired: a statistical slowdown retains all six counterbalanced rounds", {
		id = idPrefix .. "paired: a statistical slowdown retains all six counterbalanced rounds",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "continue")
		end,
	})
	harness:case(prefix .. "paired: invalid checkpoint evidence cannot pass or continue", {
		id = idPrefix .. "paired: invalid checkpoint evidence cannot pass or continue",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "invalid")
		end,
	})
	harness:case(prefix .. "paired: a persistent slowdown fails after every six-round measurement", {
		id = idPrefix .. "paired: a persistent slowdown fails after every six-round measurement",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "fail")
		end,
	})
	harness:case(prefix .. "paired: invalid calibration stops before the checkpoint", {
		id = idPrefix .. "paired: invalid calibration stops before the checkpoint",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "calibration")
		end,
	})
	harness:case(prefix .. "paired: an ungated manual run keeps its requested six rounds", {
		id = idPrefix .. "paired: an ungated manual run keeps its requested six rounds",
		run = function(test: Verify.Context): ()
			pairedRunFixture(test, "manual")
		end,
	})
	harness:case(prefix .. "paired: consecutive rounds counterbalance every arm without dropping measurements", {
		id = idPrefix .. "paired: consecutive rounds counterbalance every arm without dropping measurements",
		run = function(test: Verify.Context): ()
			local sequence = {}
			for round = 1, 6 do
				for position = 1, 2 do
					table.insert(sequence, tostring(Paired.armIndex(round, position, 2)))
				end
			end
			Verify.expect(table.concat(sequence) == "122112211221")
				:toBeTrueWith("paired arms must alternate AB/BA for all six rounds")
		end,
	})
	harness:case(prefix .. "paired: only complete calibration failures permit an infrastructure retry", {
		id = idPrefix .. "paired: only complete calibration failures permit an infrastructure retry",
		run = function(test: Verify.Context): ()
			local document = requiredBench(1, "base").document
			Json.set(document, "status", "FAIL")
			Json.set(document, "proofStatus", "unstable-cpu-rate")
			Json.set(document, "failureKind", "calibration")
			Json.set(document, "expectedMeasurements", 1)
			Json.set(document, "yardstickMedianDriftPct", 26)
			local errors, retry = Paired.benchOutcome(2, document)
			local _, crashed = Paired.benchOutcome(1, document)
			Json.set(document, "failureKind", "execution")
			local _, execution = Paired.benchOutcome(2, document)
			Json.set(document, "failureKind", "regression")
			local _, regression = Paired.benchOutcome(2, document)
			Json.set(document, "failureKind", "calibration")
			Json.set(document, "expectedMeasurements", 2)
			local _, incomplete = Paired.benchOutcome(2, document)
			Json.set(document, "expectedMeasurements", 1)
			local rows = assert(Json.arrayField(document, "results"))
			Json.set(assert(Json.asObject(rows[1])), "p95_ms", 0)
			local _, malformed = Paired.benchOutcome(2, document)
			Verify.expect(#errors > 0 and retry):toBeTrueWith("calibration failure must remain invalid and retryable")
			Verify.expect(not crashed and not execution and not regression)
				:toBeTrueWith("non-calibration failure retried")
			Verify.expect(not incomplete and not malformed):toBeTrueWith("invalid measurements retried")
		end,
	})
	harness:case(prefix .. "paired: one benchmark command loads each tree's own source", {
		id = idPrefix .. "paired: one benchmark command loads each tree's own source",
		run = function(test: Verify.Context): ()
			local root = Files.temporaryDirectory("facet-paired-source-")
			test:defer(function()
				Files.remove(root)
			end)
			local command = benchmarkCommand()
			for _, label in { "base", "candidate" } do
				local tree = Files.join(root, label)
				Files.write(Files.join(tree, "src/init.luau"), `return "{label}"`)
				Files.write(Files.join(tree, "tools/facet/init.luau"), "return nil")
				Files.write(
					Files.join(tree, "bench/scenarios.luau"),
					[[
local source = require("../src")
local function setup() return {} end
local function run()
	local total = 0
	for index = 1, 10000 do total += index % 17 end
	assert(total > 0)
end
return {
	{ name = "source-" .. source, requirement = "source", samples = 3, warmup = 0, setup = setup, run = run },
	{ name = "zz-yardstick-cpu", requirement = "source", samples = 8, warmup = 0, setup = setup, run = run },
}
]]
				)
				local result = Run.capture(command, { cwd = tree, timeout = 30 })
				local artifact = Files.join(tree, "artifacts/bench.json")
				if not Files.isFile(artifact) then
					error("benchmark did not load " .. label .. ": " .. result.stdout .. result.stderr, 0)
				end
				local document = Json.decode(Files.read(artifact))
				local rows = assert(Json.arrayField(document, "results"))
				Verify.expect(Json.stringField(rows[1], "name")):toBe("source-" .. label)
				Verify.expect(Json.numberField(document, "yardstickMedianDriftPct") ~= nil)
					:toBeTrueWith("target ran its own harness")
				Verify.expect(result.code == 0 or result.code == 2):toBeTrueWith("benchmark execution failed")
			end
		end,
	})
	harness:case(prefix .. "paired: CPU median drift rejects invalid calibration without hiding workload tails", {
		id = idPrefix .. "paired: CPU median drift rejects invalid calibration without hiding workload tails",
		run = function(test: Verify.Context): ()
			local old = requiredBench(1, "base").document
			Json.set(old, "yardstickMedianDriftPct", nil)
			local boundary = requiredBench(1, "base").document
			Json.set(boundary, "yardstickMedianDriftPct", 25)
			local drifted = requiredBench(1, "base").document
			Json.set(drifted, "yardstickMedianDriftPct", 25.01)
			local first, second = {}, {}
			for round = 1, 3 do
				local base, candidate = requiredBench(round, "base"), requiredBench(round, "cand")
				for _, bench in { base, candidate } do
					Json.set(bench.document, "yardstickDriftPct", 80)
				end
				local row = assert(Json.asObject(assert(Json.arrayField(candidate.document, "results"))[1]))
				Json.set(row, "p95_ms", 2.12)
				table.insert(first, base)
				table.insert(second, candidate)
			end
			local lines = Paired.benchTables(first, second, "base", "cand")
			Verify.expect(#Paired.benchOutcome(0, old) > 0):toBeTrueWith("missing median calibration accepted")
			Verify.expect((Paired.benchOutcome(0, boundary))):toEqual({})
			Verify.expect(#Paired.benchOutcome(0, drifted) > 0):toBeTrueWith("median drift above 25% accepted")
			Verify.expect((Paired.benchOutcome(0, second[1].document))):toEqual({})
			expectContains(
				lines,
				"| table-resize-drag | 1.0000 | 1.0000 | 1.000 | 1.00-1.00 | 2.0000 | 2.1200 | 1.060 | cand slower (p95) |"
			)
			Verify.expect(Paired.summary(lines, "base", "cand")[1]):toBe("### Paired performance: FAIL")
		end,
	})
	harness:case(prefix .. "paired: complete expected rounds and measurements pass without changing thresholds", {
		id = idPrefix .. "paired: complete expected rounds and measurements pass without changing thresholds",
		run = function(test: Verify.Context): ()
			local scope, entries, first, second = requiredPairs()
			Verify.expect(Paired.validate(scope, entries, first, second, "base", "cand")):toEqual({})
			Verify.expect((Paired.benchOutcome(0, first[1].document))):toEqual({})
		end,
	})
	harness:case(prefix .. "paired: failed commands and missing or unstable benchmark reports cannot pass", {
		id = idPrefix .. "paired: failed commands and missing or unstable benchmark reports cannot pass",
		run = function(test: Verify.Context): ()
			local successful = requiredBench(1, "base").document
			local failed = requiredBench(1, "base").document
			Json.set(failed, "status", "FAIL")
			local unstable = requiredBench(1, "base").document
			Json.set(unstable, "proofStatus", "unstable-cpu-rate")
			local drifted = requiredBench(1, "base").document
			Json.set(drifted, "yardstickMedianDriftPct", 26)
			Verify.expect(#Paired.benchOutcome(1, successful) > 0)
				:toBeTrueWith("failed command accepted a leftover report")
			Verify.expect(#Paired.benchOutcome(2, successful) > 0):toBeTrueWith("environment failure accepted")
			Verify.expect(#Paired.benchOutcome(0, nil) > 0):toBeTrueWith("missing report accepted")
			Verify.expect(#Paired.benchOutcome(0, failed) > 0):toBeTrueWith("failed report accepted")
			Verify.expect(#Paired.benchOutcome(0, unstable) > 0):toBeTrueWith("unstable report accepted")
			Verify.expect(#Paired.benchOutcome(0, drifted) > 0):toBeTrueWith("invalid yardstick accepted")
		end,
	})
	harness:case(
		prefix .. "paired: missing final rounds and individual benchmark measurements cannot disappear from coverage",
		{
			id = idPrefix
				.. "paired: missing final rounds and individual benchmark measurements cannot disappear from coverage",
			run = function(test: Verify.Context): ()
				local scope, entries, first, second = requiredPairs()
				local missing = Paired.validate(scope, entries, { first[1] }, { second[1] }, "base", "cand")
				Json.set(second[2].document, "results", Json.array())
				local empty = Paired.validate(scope, entries, first, second, "base", "cand")
				second[2] = requiredBench(2, "cand")
				local row = assert(Json.arrayField(second[2].document, "results"))[1]
				Json.set(assert(Json.asObject(row)), "name", "other-workload")
				expectContains(missing, "base benchmark round 2 is missing")
				expectContains(missing, "cand benchmark round 2 is missing")
				Verify.expect(#empty > 0):toBeTrueWith("empty measurements accepted")
				Verify.expect(#Paired.validate(scope, entries, first, second, "base", "cand") > 0)
					:toBeTrueWith("mismatched measurements accepted")
			end,
		}
	)
	harness:case(prefix .. "paired: nonempty incomplete and malformed measurements cannot masquerade as a faster run", {
		id = idPrefix .. "paired: nonempty incomplete and malformed measurements cannot masquerade as a faster run",
		run = function(test: Verify.Context): ()
			local scope, entries, first, second = requiredPairs()
			for _, benches in { first, second } do
				for _, bench in benches do
					local rows = assert(Json.arrayField(bench.document, "results"))
					local extra = table.clone(assert(Json.asObject(rows[1])))
					Json.set(extra, "name", "other-workload")
					table.insert(rows, extra)
				end
			end
			table.remove(assert(Json.arrayField(second[2].document, "results")), 1)
			local incomplete = Paired.validate(scope, entries, first, second, "base", "cand")
			local malformed = requiredBench(1, "base").document
			local row = assert(Json.asObject(assert(Json.arrayField(malformed, "results"))[1]))
			Json.set(row, "p95_ms", 0)
			expectContains(incomplete, "cand round 2: benchmark table-resize-drag is missing")
			Verify.expect(#Paired.benchOutcome(0, malformed) > 0):toBeTrueWith("invalid percentile accepted")
		end,
	})
	harness:case(
		prefix .. "paired: unavailable and missing scene rounds are failures even without statistical slowdowns",
		{
			id = idPrefix
				.. "paired: unavailable and missing scene rounds are failures even without statistical slowdowns",
			run = function(test: Verify.Context): ()
				local scope, entries, first, second = requiredPairs()
				local row = assert(Json.asObject(Json.field(entries[1], "row")))
				Json.set(row, "status", "missing")
				local unavailable = Paired.validate(scope, entries, first, second, "base", "cand")
				table.remove(entries, 4)
				table.remove(entries, 3)
				local missing = Paired.validate(scope, entries, first, second, "base", "cand")
				Verify.expect(#unavailable > 0):toBeTrueWith("unavailable scene accepted")
				expectContains(missing, "base round 2 scene dense-hud is missing")
				expectContains(missing, "cand round 2 scene dense-hud is missing")
			end,
		}
	)
	harness:case(
		prefix
			.. "paired: within-tolerance rounds cannot confirm a noisy tail, while a stable six-percent slowdown fails",
		{
			id = idPrefix
				.. "paired: within-tolerance rounds cannot confirm a noisy tail, while a stable six-percent slowdown fails",
			run = function(test: Verify.Context): ()
				Verify.expect(
					Paired.consistentSlower(1.087, { 1.028123, 1.385600, 1.016810, 1.031591, 1.141473, 1.071815 })
				)
					:toBe(false)
				Verify.expect(Paired.consistentSlower(1.06, { 1.06, 1.06, 1.06, 1.06, 1.06, 1.06 })):toBe(true)
				Verify.expect(Paired.consistentSlower(1.2, { 1.05, 1.3 })):toBe(false)
			end,
		}
	)
	harness:case(prefix .. "paired: medians, formatting and the consistent-slower rule", {
		id = idPrefix .. "paired: medians, formatting and the consistent-slower rule",
		run = function(test: Verify.Context): ()
			Verify.expect(Paired.median({ 3, 1, 2 })):toBe(2)
			Verify.expect(Paired.median({ 4, 1, 3, 2 })):toBe(2.5)
			Verify.expect(Paired.median({})):toBe(nil)
			Verify.expect(Paired.number(nil)):toBe("n/a")
			Verify.expect(Paired.number(1 / 3, 3)):toBe("0.333")
			Verify.expect(Paired.consistentSlower(1.2, { 1.1, 1.3 })):toBe(true)
			Verify.expect(Paired.consistentSlower(1.2, { 0.9, 1.3 })):toBe(false)
			Verify.expect(Paired.consistentSlower(1.04, { 1.1 })):toBe(false)
			Verify.expect(Paired.consistentSlower(1.2, {})):toBe(false)
		end,
	})
	harness:case(prefix .. "paired: the scene runner's marked row is read from its output", {
		id = idPrefix .. "paired: the scene runner's marked row is read from its output",
		run = function(test: Verify.Context): ()
			local row = Paired.sceneRow('loading\r\n@@{"scene": "dense-hud", "status": "ok", "p50": 0.5}\r\n')
			Verify.expect(row and Json.field(row, "status")):toBe("ok")
			Verify.expect(Paired.sceneRow("no marker\n")):toBe(nil)
			Verify.expect(Paired.benchRound("bench-base-12.json", "base")):toBe(12)
			Verify.expect(Paired.benchRound("bench-cand-1.json", "base")):toBe(nil)
			Verify.expect(Paired.benchRound("bench-base-1.log", "base")):toBe(nil)
		end,
	})
	harness:case(prefix .. "paired: the scene table flags consistent slowdowns and unavailable trees", {
		id = idPrefix .. "paired: the scene table flags consistent slowdowns and unavailable trees",
		run = function(test: Verify.Context): ()
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
			Verify.expect(#lines):toBe(4)
			Verify.expect(lines[3]):toBe(
				"| dense-hud | 1.0000 | 1.3750 | 1.375 | 1.25-1.50 | 2.1000 | 2.1000 | 1.000 | 1.00-1.00 | 2.0000-2.2000 | 2.0000-2.2000 | cand slower (p50) |"
			)
			Verify.expect(lines[4]):toBe(
				"| shadow-storm | n/a | 1.0000 | n/a | n/a | n/a | 1.0000 | n/a | n/a | n/a | 1.0000-1.0000 | base unavailable (crashed/missing) |"
			)
		end,
	})
	harness:case(prefix .. "paired: the summary states the verdict and lists slower scenes as percent changes", {
		id = idPrefix .. "paired: the summary states the verdict and lists slower scenes as percent changes",
		run = function(test: Verify.Context): ()
			local lines = {
				"| Scene | base p50 | cand p50 | p50 ratio | p50 paired range | base p95 | cand p95 | p95 ratio | p95 paired range | base p95 spread | cand p95 spread | Flag |",
				"|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|",
				"| dense-hud | 1.0000 | 1.3750 | 1.375 | 1.25-1.50 | 2.1000 | 2.1000 | 1.000 | 1.00-1.00 | 2.0000-2.2000 | 2.0000-2.2000 | cand slower (p50) |",
				"| calm | 1.0000 | 0.9000 | 0.900 | 0.85-0.95 | 2.0000 | 1.9000 | 0.950 | 0.90-1.00 | 2.0000-2.0000 | 1.9000-1.9000 |  |",
				"| shadow-storm | n/a | 1.0000 | n/a | n/a | n/a | 1.0000 | n/a | n/a | n/a | 1.0000-1.0000 | base unavailable (crashed) |",
			}
			local failing = Paired.summary(lines, "base", "cand")
			local passing = Paired.summary({ lines[1], lines[2], lines[4] }, "base", "cand")
			Verify.expect(failing[1]):toBe("### Paired performance: FAIL")
			Verify.expect(failing[3]):toBe("cand is consistently slower than base in 1 of 3 scenes.")
			Verify.expect(failing[7]):toBe("| dense-hud | +37.5% | +0.0% | p50 |")
			Verify.expect(failing[9]):toBe("1 measurements were unavailable; see the full table.")
			Verify.expect(passing[1]):toBe("### Paired performance: PASS")
			Verify.expect(passing[3]):toBe("cand is not consistently slower than base in any of 1 scenes.")
		end,
	})
	harness:case(prefix .. "paired: the microbenchmark table skips the yardstick flag and lists each bench run", {
		id = idPrefix .. "paired: the microbenchmark table skips the yardstick flag and lists each bench run",
		run = function(test: Verify.Context): ()
			local lines = Paired.benchTables(
				{ benchDocument(2, "base", 1, 2), benchDocument(1, "base", 1, 2) },
				{ benchDocument(1, "cand", 2, 4), benchDocument(2, "cand", 2, 4) },
				"base",
				"cand"
			)
			expectContains(
				lines,
				"| row-build | 1.0000 | 2.0000 | 2.000 | 2.00-2.00 | 2.0000 | 4.0000 | 2.000 | cand slower (p50, p95) |"
			)
			expectContains(
				lines,
				"| zz-yardstick-cpu | 1.0000 | 2.0000 | 2.000 | 2.00-2.00 | 2.0000 | 4.0000 | 2.000 |  |"
			)
			Verify.expect(not contains(lines, "| skipped |")):toBeTrueWith("a result without p50_ms was tabled")
			Verify.expect(lines[#lines - 3]):toBe("| base-1 | 0.5000 | 1.3 | 0.4 |")
			Verify.expect(lines[#lines]):toBe("| cand-2 | 0.5000 | 1.3 | 0.4 |")
			Verify.expect(Paired.benchTables({}, {}, "base", "cand")):toEqual({})
		end,
	})
end

REGISTRATIONS.aggregate = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "aggregate::"
	harness:case(prefix .. "aggregate: a dump whose base64 wraps across lines still loads", {
		id = idPrefix .. "aggregate: a dump whose base64 wraps across lines still loads",
		run = function(test: Verify.Context): ()
			local packed = Microprofiler.pack("payload")
			local close = string.find(packed, "-->", 5, true) :: number
			local encoded = string.sub(packed, 5, close - 1)
			local wrapped = string.gsub(encoded, "(" .. string.rep(".", 8) .. ")", "%1\r\n")
			local raw = "<!--" .. wrapped .. string.sub(packed, close)
			Verify.expect(Microprofiler.load("wrapped.html", raw)):toBe("payload")
		end,
	})
	harness:case(prefix .. "aggregate: the synthetic dump decodes its container, header, records and layout record", {
		id = idPrefix .. "aggregate: the synthetic dump decodes its container, header, records and layout record",
		run = function(test: Verify.Context): ()
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
			Verify.expect(dump.frames):toBe(2)
			Verify.expect(dump.frequency):toBe(1000000000)
			Verify.expect(#dump.rows):toBe(3)
			Verify.expect(byName["Facet/tick"] and byName["Facet/tick"].count):toBe(2)
			Verify.expect(byName["LuauUI/arrange"] and byName["LuauUI/arrange"].total):toBe(20000000)
			Verify.expect(byName.Sleep ~= nil):toBeTrueWith("the decoder lost the scope Sleep")
			Verify.expect(kept):toEqual({ "Facet/tick", "LuauUI/arrange" })
			Verify.expect(#records):toBe(1)
			Verify.expect(records[1] and records[1].relayouts):toBe(3)
			Verify.expect(records[1] and records[1].resizes):toBe(5)
		end,
	})
	harness:case(prefix .. "aggregate: the report prints the tick cross-check, the legacy note and the layout total", {
		id = idPrefix .. "aggregate: the report prints the tick cross-check, the legacy note and the layout total",
		run = function(test: Verify.Context): ()
			local dump = Microprofiler.parse(Microprofiler.synthetic())
			local lines = Microprofiler.render("synthetic.html", dump, { all = false, layout = true })
			local all = Microprofiler.render("synthetic.html", dump, { all = true, layout = false })
			Verify.expect(lines[2]):toBe("=== synthetic.html ===")
			Verify.expect(lines[3]):toBe("  window=2 frames  freq=1000000000  tick==2 (OK)")
			expectContains(lines, "NOTE: 1 of these scopes carry the pre-rename `LuauUI/` prefix")
			Verify.expect(lines[6])
				:toBe("  LuauUI/arrange                  6    3.00      20.00   3.3333    10.000   12.000")
			expectContains(
				lines,
				"  TOTAL                                                          3        4        5"
			)
			Verify.expect(not contains(lines, "Sleep")):toBeTrueWith("a non-framework scope was printed")
			expectContains(all, "  Sleep ")
		end,
	})
	harness:case(prefix .. "aggregate: an empty aggregate window is announced", {
		id = idPrefix .. "aggregate: an empty aggregate window is announced",
		run = function(test: Verify.Context): ()
			local dump = Microprofiler.parse(Microprofiler.synthetic())
			dump.frames = 0
			local lines = Microprofiler.render("empty.html", dump, { all = false, layout = false })
			Verify.expect(lines[3]):toBe("  WINDOW=0 - NO AGGREGATE, THIS CAPTURE HAS NO TIMINGS.")
		end,
	})
	harness:case(prefix .. "aggregate: files that are not MicroProfiler dumps are refused", {
		id = idPrefix .. "aggregate: files that are not MicroProfiler dumps are refused",
		run = function(test: Verify.Context): ()
			local function refusal(raw: string): string
				local ok, failure = pcall(Microprofiler.load, "dump.html", raw)
				return if ok then "decoded" else tostring(failure)
			end
			local packed = Microprofiler.pack("payload")
			local damaged = "<!--"
				.. Base64.encode("GAK\7\0\0\0\0\0\0\0" .. "\x78\x01\x01\x07\x00\xf8\xffpayload\0\0\0\0")
				.. "-->"
			expectContains({ refusal("<html></html>") }, "no leading HTML comment")
			expectContains({ refusal("<!--" .. Base64.encode("ZIP0000000000") .. "-->") }, "bad magic")
			expectContains({ refusal(damaged) }, "Adler-32 checksum does not match")
			expectContains({ refusal(packed) }, "decoded")
		end,
	})
end

REGISTRATIONS["spec-timings"] = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "spec-timings::"
	harness:case(prefix .. "spec-timings: cases are grouped by spec in first-seen order", {
		id = idPrefix .. "spec-timings: cases are grouped by spec in first-seen order",
		run = function(test: Verify.Context): ()
			local outcome = decode(
				[[{"execution": {"report": {"results": [{"source": "tests/a.verify.luau", "durationMicros": 1500}, {"source": null, "durationMicros": 10}, {"source": "tests/a.verify.luau", "durationMicros": 500}]}}}]]
			)
			Verify.expect(specTable(specRows(outcome)))
				:toBe("spec\tcases\tcases_ms\ntests/a.verify.luau\t2\t2\nunknown\t1\t0.01\n")
		end,
	})
	harness:case(prefix .. "spec-timings: an outcome without results is refused", {
		id = idPrefix .. "spec-timings: an outcome without results is refused",
		run = function(test: Verify.Context): ()
			local ok = pcall(specRows, decode([[{"execution": {}}]]))
			Verify.expect(not ok):toBeTrueWith("an outcome without results was accepted")
		end,
	})
end

local function registerNone(harness: Verify.Harness, prefix: string): () end
REGISTRATIONS.run = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "run::"
	harness:case(prefix .. "run: an invalid internal timing policy fails before workloads start", {
		id = idPrefix .. "run: an invalid internal timing policy fails before workloads start",
		run = function(test: Verify.Context): ()
			local environment = Run.environment()
			environment.FACET_PERF_TIMING = "invalid"
			local result = Run.capture({ Run.lute(), "run", "tools/facet", "perf", "run" }, { env = environment })
			Verify.expect(result.code):toBe(1)
			expectContains({ result.stdout }, "FACET_PERF_TIMING must be true or false")
		end,
	})
end
REGISTRATIONS.baseline = registerNone
REGISTRATIONS["prove-gate"] = registerNone
REGISTRATIONS.memory = registerNone
REGISTRATIONS.profile = registerNone
REGISTRATIONS.footprint = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "footprint::"
	local counts = [[{"instances":1,"connections":2,"holdings":3}]]
	local report = Json.decode(
		[[{"schema":"facet-perf-footprint/1","samples":[{"name":"Button","idle":]]
			.. counts
			.. [[,"active":]]
			.. counts
			.. [[,"teardown":{"instances":0,"connections":0,"holdings":0}}]}]]
	)
	harness:case(prefix .. "footprint: counts must be complete, bounded and released", {
		id = idPrefix .. "footprint: counts must be complete, bounded and released",
		run = function(test: Verify.Context): ()
			Verify.expect(Footprint.check(report, Json.decode([[{"Button":]] .. counts .. "}"))):toEqual({})
			Verify.expect(
				#Footprint.check(report, Json.decode([[{"Button":{"instances":0,"connections":2,"holdings":3}}]])) > 0
			)
				:toBeTrueWith("resource growth passed")
			Verify.expect(#Footprint.check(report, Json.decode([[{"Missing":]] .. counts .. "}")) > 0)
				:toBeTrueWith("missing control passed")
			Verify.expect(#Footprint.check(Json.decode("{}"), Json.decode("{}")) > 0)
				:toBeTrueWith("empty report passed")
		end,
	})
end
REGISTRATIONS["prove-memory-gate"] = registerNone
REGISTRATIONS["prove-retained-memory"] = registerNone
REGISTRATIONS.affected = function(harness: Verify.Harness, prefix: string)
	prefix ..= "affected::"
	harness:case(prefix .. "paired performance input coverage", function(context)
		for _, path in
			{
				"src/ui/control.luau",
				"bench/scenarios.luau",
				"bench/paired_workload.luau",
				"examples/themes/data.json",
				"tests/lib/native_engine.luau",
				"tests/behavior.verify.luau",
				"tools/vendor/verify/src/lute/memory.luau",
				"tools/facet/lib/perf_retained.luau",
				"tools/engine/retained_memory_proof.luau",
				"eval/data.json",
				"rokit.toml",
				".luaurc",
				"default.project.json",
				".github/workflows/ci.yml",
				"future/code.luau",
			}
		do
			context:expect(Inputs.affects(path)):toBeTrueWith(path)
		end
		for _, path in { "README.md", "docs/guide/components.md", "skills/use-facet/SKILL.md", "AGENTS.md" } do
			context:expect(not Inputs.affects(path)):toBeTrueWith(path)
		end
	end)
end

local ORDER =
	{ "budgets", "metrics", "scenes", "place", "paired", "aggregate", "spec-timings", "footprint", "run", "affected" }

local function registerAll(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the memory gate rejects planted native and Compose leaks", {
		id = prefix .. "the memory gate rejects planted native and Compose leaks",
		run = function(test: Verify.Context): ()
			local PerfRun = require("../lib/perf_run")
			Verify.expect(PerfRun.proveMemoryGate()):toBe(0)
		end,
	})
	for _, name in ORDER do
		REGISTRATIONS[name](harness, prefix)
	end
end

local VALUES = { "out", "rounds", "scenes", "workspace", "devices", "tap", "summary" }

local KNOWN = {
	"selftest",
	"themes",
	"no-build",
	"out",
	"rounds",
	"scenes",
	"skip-bench",
	"all",
	"layout",
	"workspace",
	"devices",
	"tap",
	"gate",
	"summary",
}

local function run(invocation: Cli.Invocation): number
	local subcommand = invocation.positional[1]
	if subcommand == nil or (REGISTRATIONS[subcommand] == nil and subcommand ~= "capture") then
		print(USAGE)
		return 2
	end
	local unknown = Cli.unknownFlags(invocation, KNOWN)
	if unknown ~= nil then
		print(("facet perf: unknown option %s\n\n%s"):format(unknown, USAGE))
		return 2
	end
	if subcommand == "capture" then
		return require("./perf_capture")(invocation)
	end
	if Cli.switch(invocation, "selftest") then
		return Gate.selftest("tools/commands", "tools/commands::perf::" .. subcommand .. "::")
	end
	if subcommand == "affected" then
		return Inputs.run(invocation.positional[2])
	elseif subcommand == "prove-retained-memory" then
		return Run.inherit({
			Run.lute(),
			"run",
			"tools/engine/retained_memory_proof.luau",
			Cli.flag(invocation, "out") or "artifacts/perf-paired-retained-calibration",
		}).code
	end
	if
		subcommand == "run"
		or subcommand == "baseline"
		or subcommand == "prove-gate"
		or subcommand == "prove-memory-gate"
	then
		local PerfRun = require("../lib/perf_run")
		if subcommand == "run" then
			local timing = Run.env("FACET_PERF_TIMING")
			if timing ~= nil and timing ~= "true" and timing ~= "false" then
				print("perf: FACET_PERF_TIMING must be true or false")
				return 1
			end
			local code = PerfRun.run(invocation.positional[2] == "baseline", timing ~= "false")
			if invocation.positional[2] ~= "baseline" then
				print("perf budgets")
				local budgetCode = budgets()
				print("perf metrics")
				local metricsCode = metrics()
				if code == 1 or budgetCode == 1 or metricsCode == 1 then
					return 1
				end
				code = math.max(code, budgetCode, metricsCode)
			end
			return code
		elseif subcommand == "baseline" then
			return PerfRun.baselineScenes(table.move(invocation.positional, 2, #invocation.positional, 1, {}))
		elseif subcommand == "prove-memory-gate" then
			return PerfRun.proveMemoryGate()
		end
		return PerfRun.proveGate()
	end
	local ok, code = pcall(function(): number
		if subcommand == "budgets" then
			return budgets()
		elseif subcommand == "metrics" then
			return metrics()
		elseif subcommand == "memory" then
			return memory(invocation.positional[2])
		elseif subcommand == "footprint" then
			return footprint(invocation.positional[2])
		elseif subcommand == "profile" then
			return profile(invocation.positional[2], invocation.positional[3])
		elseif subcommand == "scenes" then
			if Cli.switch(invocation, "themes") then
				return scenes(true)
			end
			print("perf scenes")
			local code = scenes(false)
			print("perf scenes --themes")
			return math.max(code, scenes(true))
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
		return if subcommand == "paired" then 2 else 1
	end
	return code :: number
end

local command: Cli.Command = {
	name = "perf",
	summary = "Check perf budgets, metrics, scenes and the place; run paired perf; read MicroProfiler dumps.",
	usage = USAGE,
	values = VALUES,
	register = registerAll,
	run = run,
}

return command
