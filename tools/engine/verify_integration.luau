--!strict
local fs = require("@std/fs")
local json = require("@std/json")
local process = require("@std/process")
local task = require("@std/task")
local Lute = require("../vendor/verify/src/lute")
local Verify = require("../vendor/verify/src/core")
local Gate = require("../vendor/verify/src/gate")
local Files = require("../facet/lib/files")
local Run = require("../facet/lib/run")
local gate = require("../facet/lib/gate")
local Cli = require("../facet/lib/cli")
local Json = require("../facet/lib/json")

local harness = Verify.createHarness({ source = "facet-verify-integration", now = os.clock })
local directory = `artifacts/verify/integration-{os.time()}-{math.random(1, 1e9)}`
assert(not Files.isDirectory(directory), "the integration scratch directory already exists: " .. directory)
Files.makeDirectory(directory)
local VERIFY = "../../../tools/vendor/verify/src"
local LUTE = Run.lute()

local function source(name: string, text: string): string
	Files.write(`{directory}/{name}.luau`, text)
	return `{directory}/{name}.luau`
end

local function worker(name: string, body: string): string
	local path = `{directory}/{name}-worker.luau`
	Files.write(
		path,
		table.concat({
			'local fs = require("@std/fs")',
			'local process = require("@std/process")',
			`local Lute = require("{VERIFY}/lute")`,
			`local Verify = require("{VERIFY}/core")`,
			"local batch = Lute.decodeBatch(fs.readFileToString(process.args[2]))",
			"local output = process.args[3]",
			"local harness = Verify.createHarness({ now = os.clock, source = batch.units[1].locator, prefixIds = false })",
			'harness:case("ok", { id = "ok", run = function() end })',
			'local report = harness:run({ executor = "fixture", environment = { runtime = "lute" }, capabilities = { "local-luau" } })',
			body,
		}, "\n")
	)
	return path
end

local function tests(id: string, locators: { string }, cases: { string }?, custom: string?): gate.Entry
	return {
		id = id,
		tier = "fast",
		why = "an integration fixture",
		producer = {
			id = id,
			kind = "tests",
			worker = custom or "tests/worker.luau",
			locators = locators,
			cases = cases,
			isolate = true,
			workers = 4,
			deadlineSeconds = 60,
		},
	}
end

local function exiting(code: number): { string }
	local path = source(`exit-{code}`, `local process = require("@std/process")\nprocess.exit({code})`)
	return { LUTE, "run", path }
end

local function command(id: string, code: number, environment: string?, tier: string?): gate.Entry
	return {
		id = id,
		tier = tier or "fast",
		why = "an integration fixture",
		environment = environment,
		producer = { id = id, kind = "command", argv = exiting(code) },
	}
end

local function descendant(name: string, marker: string): string
	local child = source(
		`{name}-child`,
		table.concat({
			'local fs = require("@std/fs")',
			'local task = require("@std/task")',
			"task.wait(3)",
			`fs.writeStringToFile("{marker}", "survived")`,
		}, "\n")
	)
	return table.concat({
		'local process = require("@std/process")',
		'local task = require("@std/task")',
		`task.spawn(function() process.run(\{ "{LUTE}", "run", "{child}" \}) end)`,
		"task.wait(30)",
	}, "\n")
end

local function reporter(id: string, mode: string, expectation: Gate.ReportExpectation?): gate.Entry
	local path = `{directory}/reporter.luau`
	Files.write(
		path,
		table.concat({
			'local fs = require("@std/fs")',
			'local process = require("@std/process")',
			`local Lute = require("{VERIFY}/lute")`,
			`local Verify = require("{VERIFY}/core")`,
			"local mode, path, run = process.args[2], process.args[3], process.args[4]",
			'local harness = Verify.createHarness({ now = os.clock, source = "reporter", prefixIds = false })',
			'harness:case("one", { id = "one", requires = if mode == "unsupported" then { "native-hook" } else nil, run = function(context) context:expect(mode ~= "failing"):toBe(true) end })',
			'local report = harness:run({ executor = "fixture", environment = { runtime = "lute" } })',
			'if mode == "empty" then fs.writeStringToFile(path, "")',
			'elseif mode == "malformed" then fs.writeStringToFile(path, "{ not json")',
			'elseif mode == "stale" then Lute.gate.writeReport(path, "another-run", report)',
			'elseif mode ~= "missing" then Lute.gate.writeReport(path, run, report) end',
			'process.exit(if mode == "contradicts" then 1 else 0)',
		}, "\n")
	)
	return {
		id = id,
		tier = "fast",
		why = "an integration fixture",
		producer = {
			id = id,
			kind = "command",
			argv = { LUTE, "run", path, mode, "{report}", "{run}" },
			report = expectation or { minimum = 1 },
		},
	}
end

local function widen<T>(list: { T }): { unknown }
	local out: { unknown } = {}
	for _, item in list do
		table.insert(out, item)
	end
	return out
end

local sequence = 0
local function runGate(
	entries: { gate.Entry },
	options: { referenceHost: boolean?, tier: string?, rerun: string? }?
): Gate.Outcome
	sequence += 1
	local settings: { referenceHost: boolean?, tier: string?, rerun: string? } = options or {}
	local definition = Gate.define(gate.define(entries, settings.referenceHost == true, `fixture-{sequence}`))
	local tiers = gate.tiers[settings.tier or "release"]
	local chosen: Gate.Selection? = if #tiers > 0 then { tiers = tiers } else nil
	local rerun = settings.rerun
	if rerun then
		local rerunSelection: Gate.Selection = if #tiers > 0
			then { ids = { rerun }, tiers = tiers }
			else { ids = { rerun } }
		chosen = rerunSelection
	end
	return Lute.gate.run(definition, { directory = `{directory}/gate`, selection = chosen })
end

local function completeTier(outcome: Gate.Outcome): boolean
	return #outcome.scope.ids == 0 and #outcome.scope.notSelected == #outcome.scope.skippedByTier
end

local function record(outcome: Gate.Outcome, id: string): Gate.Record
	for _, entry in outcome.producers do
		if entry.id == id then
			return entry
		end
	end
	error("no producer record: " .. id)
end

local function status(outcome: Gate.Outcome, id: string): string
	return record(outcome, id).status
end

local function case(outcome: Gate.Outcome, id: string): Verify.CaseResult
	for _, result in outcome.execution.report.results do
		if result.id == id then
			return result
		end
	end
	error("no case result: " .. id)
end

harness:suite("Suite execution through the Verify gate", function()
	harness:case("fails missing, load, registration, non-function and empty sources by name", function(context)
		local outcome = runGate({
			tests("missing", { `{directory}/missing.luau` }),
			tests("broken", { source("broken", 'error("broken source")') }),
			tests("registration", { source("registration", 'return function() error("broken registration") end') }),
			tests("value", { source("value", "return {}") }),
			tests("empty", { source("empty", "return function() end") }),
			tests(
				"passing",
				{ source("passing", 'return function(h) h:case("one",{id="one",run=function() end}) end') }
			),
		})
		for _, id in { "missing", "broken", "registration", "value", "empty" } do
			context:expect(`{id}: {status(outcome, id)}`):toBe(`{id}: failed`)
		end
		context:expect(status(outcome, "passing")):toBe("passed")
		context:expect(outcome.acceptance.verdict):toBe("failed")
	end)
	harness:case("preserves case and cleanup failures independently", function(context)
		local outcome = runGate({
			tests("cleanup", {
				source(
					"cleanup",
					'return function(h) h:case("fails", { id="fails", run=function(c) c:defer(function() error("cleanup failure") end) error("body failure") end }) end'
				),
			}),
		})
		local result = case(outcome, "fails")
		context:expect(status(outcome, "cleanup")):toBe("failed")
		context:expect(result.status):toBe("failed")
		context:expect(#result.failures):toBe(2)
		context:expect(result.failures[1].phase):toBe("case")
		context:expect(result.failures[2].phase):toBe("cleanup")
	end)
	harness:case("rejects duplicate IDs, unapproved skips and census drift", function(context)
		local one = 'return function(h) h:case("one",{id="one",run=function(c) c:expect(1):toBe(1) end}) end'
		local outcome = runGate({
			tests("duplicate", {
				source(
					"duplicate",
					'return function(h) h:case("one",{id="same",run=function() end}) h:case("two",{id="same",run=function() end}) end'
				),
			}),
			tests("skipped", { source("skipped", 'return function(h) h:skip("absent", "no setup") end') }),
			tests("exact", { source("exact", one) }, { "one" }),
			tests("unexpected", {
				source(
					"unexpected",
					'return function(h) h:case("one",{id="one",run=function() end}) h:case("extra",{id="extra",run=function() end}) end'
				),
			}, { "one" }),
			tests("absent", { source("absent", one) }, { "one", "two" }),
		})
		context:expect(status(outcome, "exact")):toBe("passed")
		for _, id in { "duplicate", "skipped", "unexpected", "absent" } do
			context:expect(`{id}: {status(outcome, id)}`):toBe(`{id}: failed`)
		end
	end)
	harness:case("keeps the release-only case out of lower tiers and requires it at release", function(context)
		local entries = {
			tests("tiered", {
				source(
					"tiered",
					'return function(h) h:case("always",{id="always",run=function() end}) h:case("ramp",{id="ramp",tags={"tier:release"},run=function(c) c:expect(true):toBe(true) end}) end'
				),
			}, { "always", "ramp" }),
		}
		local lower = runGate(entries, { tier = "fast" })
		context:expect(status(lower, "tiered")):toBe("passed")
		context:expect(record(lower, "tiered").deselected):toEqual({ "ramp" })
		context:expect(case(lower, "ramp").status):toBe("skipped")
		context:expect(lower.scope.complete):toBe(false)
		context:expect(lower.acceptance.releasable):toBe(false)
		local release = runGate(entries, { tier = "release" })
		context:expect(case(release, "ramp").status):toBe("passed")
		context:expect(record(release, "tiered").deselected):toEqual({})
		context:expect(release.acceptance.releasable):toBe(true)
		local broken = runGate({
			tests("tiered", {
				source(
					"failing-ramp",
					'return function(h) h:case("ramp",{id="ramp",tags={"tier:release"},run=function() error("ramp failed") end}) h:case("always",{id="always",run=function() end}) end'
				),
			}, { "always", "ramp" }),
		}, { tier = "release" })
		context:expect(status(broken, "tiered")):toBe("failed")
		local inBody = runGate({
			tests("tiered", {
				source(
					"in-body",
					'return function(h) h:case("ramp",{id="ramp",run=function(c) c:skip("tier:release") end}) end'
				),
			}, { "ramp" }),
		}, { tier = "fast" })
		context:expect(status(inBody, "tiered")):toBe("failed")
	end)
	harness:case("rejects missing, empty, malformed and invalid worker reports", function(context)
		local locator = source("receipt", "return function() end")
		local faults: { [string]: string } = {
			silent = "",
			empty = 'fs.writeStringToFile(output, "")',
			malformed = 'fs.writeStringToFile(output, "{ not json")',
			invalid = "fs.writeStringToFile(output, Lute.encode({ total = 5 }))",
		}
		local entries = {
			tests(
				"accepted",
				{ locator },
				nil,
				worker("accepted", "fs.writeStringToFile(output, Lute.encode(report))")
			),
		}
		for name, body in faults do
			table.insert(entries, tests(name, { locator }, nil, worker(name, body)))
		end
		local outcome = runGate(entries)
		context:expect(status(outcome, "accepted")):toBe("passed")
		for name in faults do
			context:expect(`{name}: {status(outcome, name)}`):toBe(`{name}: failed`)
		end
	end)
	harness:case("stops a timed-out worker and its descendants", function(context)
		local marker = `{directory}/descendant-survived`
		local hung =
			tests("hang", { source("hang", "return function() end") }, nil, worker("hang", descendant("hang", marker)))
		assert(hung.producer).deadlineSeconds = 1
		local outcome = runGate({ hung })
		context:expect(status(outcome, "hang") ~= "passed"):toBe(true)
		context:expect(outcome.execution.report.timedOut + outcome.execution.report.failed > 0):toBe(true)
		task.wait(4)
		context:expect(fs.exists(marker)):toBe(false)
	end)
end)

harness:suite("Facet live CI policy", function()
	harness:case("required complete gates reject queries and focused runs before execution", function(context)
		for _, arguments in
			{
				{ "full", "--require-complete", "--list" },
				{ "full", "--require-complete", "--only", "studio-live" },
				{ "full", "--require-complete", "--rerun" },
				{ "fast", "--require-complete" },
				{ "spec", "native", "--require-complete" },
			}
		do
			context:expect(gate.main(arguments)):toBe(2)
		end
	end)
	local function studioCommand(report: Verify.Report, onRun: ((string) -> ())?, sourcePlan: string?): Cli.Command
		local native = (table.clone(Lute) :: unknown) :: { [string]: unknown }
		native.studio = {
			run = function(options: { code: string })
				if onRun then
					onRun(options.code)
				end
				return { status = "returned", report = report }
			end,
		}
		local environment: { [string]: unknown }
		environment = {
			print = function() end,
			require = function(module: string): unknown
				if module == "@std/fs" then
					return {
						readFileToString = function(path: string): string
							return if sourcePlan and path == "tools/studio/live/plan.json"
								then sourcePlan
								else fs.readFileToString(path)
						end,
						exists = function()
							return true
						end,
						listDirectory = function()
							return {}
						end,
						writeStringToFile = function() end,
						remove = function() end,
					}
				elseif module == "@std/process" then
					return {
						pid = function()
							return 1
						end,
						run = function()
							return { ok = true, stdout = "revision", stderr = "" }
						end,
					}
				elseif module == "@std/json" then
					return json
				elseif module == "../lib/json" or module == "./json" then
					return Json
				elseif module == "../../vendor/verify/src/lute" then
					return native
				elseif module == "../../vendor/verify/src/core" then
					return Verify
				elseif module == "../lib/live_project" then
					return (
						Lute.chunk.load(fs.readFileToString("tools/facet/lib/live_project.luau"), {
							environment = environment,
						})()
					)
				elseif module == "../../studio/live/attachment_limits" then
					return {}
				end
				return {}
			end,
		}
		return Lute.chunk.load(
				fs.readFileToString("tools/facet/commands/studio.luau"),
				{ environment = environment }
			)() :: Cli.Command
	end
	harness:case("all mode runs the committed source plan and keeps haptics in one session", function(context)
		local cases = Verify.createHarness({ source = "fixture", now = os.clock, prefixIds = false })
		cases:case("passed", { id = "passed", run = function() end })
		local report = cases:run({ executor = "fixture", environment = {} })
		local codes: { string } = {}
		local command = studioCommand(
			report,
			function(code)
				table.insert(codes, code)
			end,
			Lute.encode({
				units = {
					{ id = "included", locator = "tools/studio/live/suites/included.luau" },
					{ id = "haptics_setup", locator = "tools/studio/live/suites/haptics_setup.luau" },
					{ id = "haptics_verify", locator = "tools/studio/live/suites/haptics_verify.luau" },
				},
			})
		)
		context:expect(command.run(Cli.parse({ "studio", "live", "--all", "--complete" }))):toBe(0)
		context:expect(#codes):toBe(2)
		context:expect(string.find(codes[1], 'drive(live, "haptics_pair"', 1, true) ~= nil):toBe(true)
		context:expect(string.find(codes[2], 'drive(live, "included"', 1, true) ~= nil):toBe(true)
	end)
	harness:case("complete commands fail unsupported and empty reports and reject narrowing", function(context)
		local cases = Verify.createHarness({ source = "command-fixture", now = os.clock, prefixIds = false })
		cases:case("passed", { id = "passed", run = function() end })
		cases:case("hook", { id = "hook", requires = { "native-hook" }, run = function() end })
		local report = cases:run({ executor = "fixture", environment = {} })
		context:expect(studioCommand(report).run(Cli.parse({ "studio", "live", "mixed", "--complete" }))):toBe(1)
		context:expect(studioCommand(report).run(Cli.parse({ "studio", "live", "mixed" }))):toBe(0)
		local empty = Verify.createHarness({ source = "empty", now = os.clock })
			:run({ executor = "fixture", environment = {} })
		context:expect(studioCommand(empty).run(Cli.parse({ "studio", "live", "empty", "--complete" }))):toBe(1)
		for _, filter in { { "--only", "part" }, { "--case", "passed" }, { "--resume-run", "old" }, { "--place" } } do
			local arguments = { "studio", "live", "mixed", "--complete" }
			for _, argument in filter do
				table.insert(arguments, argument)
			end
			context
				:expect(function()
					studioCommand(report).run(Cli.parse(arguments))
				end)
				:toThrow()
		end
	end)
	local function driver(): (unknown, string, { [string]: unknown }) -> Verify.Report
		local storage: { [string]: unknown } = { FacetLive = { zoom_travel_drivers = "travel" } }
		storage.WaitForChild = function(_: unknown, name: string): unknown
			return if name == "core" then "verify" else storage
		end
		local services: { [string]: unknown } = {
			Players = {},
			GuiService = {},
			RunService = {},
			UserInputService = { KeyboardEnabled = true, MouseEnabled = true, PreferredInput = "keyboard" },
			HttpService = {},
		}
		local environment: { [string]: unknown } = {
			game = {
				ReplicatedStorage = storage,
				GetService = function(_: unknown, name: string): unknown
					return assert(services[name], name)
				end,
			},
			Enum = { PreferredInput = { Gamepad = "gamepad" } },
			require = function(module: unknown): unknown
				return if module == "verify"
					then Verify
					else function(): { [string]: unknown }
						return {}
					end
			end,
		}
		local load =
			Lute.chunk.load(fs.readFileToString("tools/studio/live/interactive.luau"), { environment = environment })
		return load() :: (unknown, string, { [string]: unknown }) -> Verify.Report
	end
	harness:case("complete mixed suites retain automatic and unsupported interactive registrations", function(context)
		local selected: unknown = nil
		local automatic = Verify.createHarness({ source = "mixed", now = os.clock, prefixIds = false })
		automatic:case("automatic", { id = "automatic", run = function() end })
		local report = driver()({
			cases = function(): { unknown }
				return {
					{ id = "automatic", run = function() end },
					{ id = "tray-grows-with-text-size", setup = function() end },
				}
			end,
			report = function(_: string, options: { ids: { string } })
				selected = options.ids
				return automatic:run({ executor = "fixture", environment = {} })
			end,
		}, "mixed", { complete = true, device = "keep" })
		context:expect(selected):toEqual({ "automatic" })
		context:expect(report.total):toBe(2)
		context:expect(report.passed):toBe(1)
		context:expect(report.unsupported):toBe(1)
		context:expect(report.results[2].id):toBe("tray-grows-with-text-size")
	end)
	harness:case("complete mode rejects a suite with no registrations", function(context)
		context
			:expect(function()
				driver()({
					cases = function()
						return {}
					end,
				}, "empty", { complete = true, device = "keep" })
			end)
			:toThrow()
	end)
	harness:case("portable hosts defer declared Studio coverage without running it", function(context)
		local entry = command("native", 1, "studio")
		entry.capabilities = { "native-studio" }
		local outcome = runGate({ entry })
		context:expect(status(outcome, "native")):toBe("deferred")
		context:expect(outcome.acceptance.releasable):toBe(false)
	end)
end)

harness:suite("Facet gate through Verify", function()
	harness:case("classifies pass, failure and environment deferral by producer class", function(context)
		local entries = {
			command("pass", 0),
			command("failure", 1),
			command("unclassified", 2),
			command("live", 2, "studio"),
			command("device", 2, "device"),
			command("timing", 2, "perf"),
			command("live-broken", 1, "studio"),
		}
		local outcome = runGate(entries)
		context:expect(status(outcome, "pass")):toBe("passed")
		context:expect(status(outcome, "failure")):toBe("failed")
		context:expect(status(outcome, "unclassified")):toBe("failed")
		context:expect(status(outcome, "live")):toBe("deferred")
		context:expect(status(outcome, "device")):toBe("deferred")
		context:expect(status(outcome, "timing")):toBe("deferred")
		context:expect(status(outcome, "live-broken")):toBe("failed")
		context:expect(outcome.acceptance.verdict):toBe("failed")
		local reference = runGate(entries, { referenceHost = true })
		context:expect(status(reference, "timing")):toBe("failed")
		context:expect(status(reference, "live")):toBe("deferred")
	end)
	harness:case("separates focused, complete, deferred and releasable outcomes", function(context)
		local clean = {
			command("fast", 0),
			command("full", 0, nil, "full"),
			command("gate", 0, nil, "release"),
		}
		local release = runGate(clean, { tier = "release" })
		context:expect(release.acceptance.releasable):toBe(true)
		context:expect(gate.releasable(0, "release", release)):toBe(0)
		local full = runGate(clean, { tier = "full" })
		context:expect(full.acceptance.verdict):toBe("selected")
		context:expect(full.acceptance.releasable):toBe(false)
		context:expect(completeTier(full)):toBe(true)
		context:expect(status(full, "gate")):toBe("not_selected")
		context:expect(gate.releasable(0, "full", full)):toBe(0)
		context:expect(gate.releasable(0, "full", full, true)):toBe(0)
		context:expect(gate.releasable(0, "release", full)):toBe(1)
		local focused = runGate(clean, { tier = "full", rerun = "fast" })
		context:expect(completeTier(focused)):toBe(false)
		context:expect(focused.acceptance.verdict):toBe("selected")
		context:expect(gate.releasable(0, "full", focused, true)):toBe(1)
		local deferred = { command("fast", 0), command("live", 2, "studio", "full") }
		local lower = runGate(deferred, { tier = "full" })
		context:expect(lower.acceptance.deferred):toEqual({ "live" })
		context:expect(lower.acceptance.verdict ~= "failed"):toBe(true)
		context:expect(gate.releasable(0, "full", lower, true)):toBe(1)
		context:expect(gate.releasable(0, "full", nil, true)):toBe(1)
		local blocked = runGate(deferred, { tier = "release" })
		context:expect(blocked.acceptance.verdict):toBe("deferred")
		context:expect(blocked.acceptance.releasable):toBe(false)
		context:expect(gate.releasable(0, "release", blocked)):toBe(1)
		local failed = runGate({ command("fast", 1) }, { tier = "fast" })
		context:expect(failed.acceptance.verdict):toBe("failed")
		context
			:expect(function()
				runGate(clean, { tier = "full", rerun = "absent" })
			end)
			:toThrow()
	end)
	harness:case("rejects missing, empty, malformed, stale, short and contradictory producer reports", function(context)
		local outcome = runGate({
			reporter("accepted", "valid", { minimum = 1, cases = { "one" } }),
			reporter("missing", "missing"),
			reporter("empty", "empty"),
			reporter("malformed", "malformed"),
			reporter("stale", "stale"),
			reporter("short", "valid", { minimum = 2 }),
			reporter("absent-case", "valid", { cases = { "one", "two" } }),
			reporter("failing", "failing"),
			reporter("unsupported", "unsupported"),
			reporter("contradicts", "contradicts"),
		})
		context:expect(status(outcome, "accepted")):toBe("passed")
		context:expect(status(outcome, "unsupported") ~= "passed"):toBe(true)
		for _, id in { "missing", "empty", "malformed", "stale", "short", "absent-case", "failing", "contradicts" } do
			context:expect(`{id}: {status(outcome, id)}`):toBe(`{id}: failed`)
		end
		local ids = {}
		for _, result in outcome.execution.report.results do
			ids[result.id] = result.status
		end
		context:expect(ids["accepted:one"]):toBe("passed")
		context:expect(ids["failing:one"]):toBe("failed")
	end)
	harness:case("blocks dependents and stops a timed-out producer with its descendants", function(context)
		local marker = `{directory}/gate-descendant-survived`
		local hung = command("hung", 0)
		assert(hung.producer).argv = { LUTE, "run", source("gate-hung", descendant("gate-hung", marker)) }
		assert(hung.producer).deadlineSeconds = 1
		local dependent = command("dependent", 0)
		dependent.after = { "hung" }
		local outcome = runGate({ hung, dependent })
		context:expect(status(outcome, "hung")):toBe("timed_out")
		context:expect(status(outcome, "dependent")):toBe("blocked")
		context:expect(outcome.acceptance.verdict):toBe("failed")
		task.wait(4)
		context:expect(fs.exists(marker)):toBe(false)
	end)
	harness:case("overlaps independent checks before starting an exclusive producer", function(context)
		local entries: { gate.Entry } = {}
		for _, id in { "types", "suite" } do
			local other = if id == "types" then "suite" else "types"
			local path = source(
				"parallel-" .. id,
				table.concat({
					'local fs = require("@std/fs")',
					'local task = require("@std/task")',
					`fs.writeStringToFile("{directory}/{id}.started", "started")`,
					"local deadline = os.clock() + 30",
					`while not fs.exists("{directory}/{other}.started") and os.clock() < deadline do task.wait(0.01) end`,
					`assert(fs.exists("{directory}/{other}.started"), "the independent producer did not start")`,
					`fs.writeStringToFile("{directory}/{id}.done", "done")`,
				}, "\n")
			)
			local entry: gate.Entry = {
				id = id,
				tier = "fast",
				why = "independent producer concurrency",
				exclusive = false,
				producer = { id = id, kind = "command", argv = { LUTE, "run", path } },
			}
			table.insert(entries, entry)
		end
		local path = source(
			"exclusive",
			table.concat({
				'local fs = require("@std/fs")',
				`assert(fs.exists("{directory}/types.done"), "types is still running")`,
				`assert(fs.exists("{directory}/suite.done"), "suite is still running")`,
			}, "\n")
		)
		local exclusive: gate.Entry = {
			id = "exclusive",
			tier = "fast",
			why = "exclusive producer isolation",
			producer = { id = "exclusive", kind = "command", argv = { LUTE, "run", path } },
		}
		table.insert(entries, exclusive)
		local outcome = runGate(entries)
		for _, id in { "types", "suite", "exclusive" } do
			context:expect(status(outcome, id)):toBe("passed")
		end
	end)
	harness:case("declares every committed producer once with its tier and suite plan", function(context)
		local tiers: { [string]: number } = { fast = 0, full = 0, release = 0 }
		local seen: { [string]: Gate.ProducerDraft } = {}
		local definition = gate.draft(false)
		for _, producer in definition.producers do
			context:expect(seen[producer.id]):toBeNil()
			seen[producer.id] = producer
			tiers[producer.tier :: string] += 1
		end
		context:expect(tiers):toEqual({ fast = 16, full = 24, release = 3 })
		context:expect(seen["studio-live"].requires):toEqual({ "native-studio" })
		context:expect(seen["studio-live"].report):toEqual({ minimum = 1 })
		context:expect(seen["run-comparison"].tier):toBe("release")
		context:expect(seen["docs-nodes"].tier):toBe("fast")
		context:expect(seen["text-encoding"].tier):toBe("fast")
		context:expect(seen["perf"].tier):toBe("full")
		context:expect(seen["perf-memory"].tier):toBe("full")
		context:expect(seen["perf-footprint"].tier):toBe("full")
		context:expect(seen["perf-memory"].after):toEqual({ "perf" })
		local order: { [string]: number } = {}
		for index, producer in definition.producers do
			order[producer.id] = index
		end
		context:expect(order["perf"] < order["perf-memory"]):toBe(true)
		context:expect(assert(definition.policy).concurrency):toBe(2)
		context:expect(order["types"] + 1):toBe(order["suite"])
		for id, producer in seen do
			context:expect(producer.exclusive):toBe(id ~= "suite" and id ~= "types")
		end
		for _, removed in
			{
				"types-selftest",
				"public-surface-selftest",
				"prove-perf-memory-gate",
				"verify-vendor",
				"reference-builds",
				"consumer-build",
				"gallery-build",
				"monitors-build",
				"performance-build",
				"theme-builds",
				"model-build",
				"package-verify",
				"package-purity",
				"plate-samples",
				"perf-scenes-themes",
				"perf-budgets",
				"perf-metrics",
				"doctor",
				"experiment-markers",
			}
		do
			context:expect(seen[removed]):toBeNil()
		end
		context:expect(seen["prove-perf-gate"].tier):toBe("release")
		context:expect(seen["prove-retained-memory"].tier):toBe("release")
		context
			:expect(seen["prove-retained-memory"].argv)
			:toEqual({ "lute", "run", "tools/facet", "perf", "prove-retained-memory" })
		context:expect(seen["facetbench"].tier):toBe("fast")
		local plan =
			Lute.parse(fs.readFileToString("tests/plan.json")) :: { units: { { locator: string, requires: { string }? } } }
		local locators = {}
		local toolLocators = {}
		for _, unit in plan.units do
			local lute = unit.requires ~= nil and table.find(unit.requires, "lute") ~= nil
			table.insert(if lute then toolLocators else locators, unit.locator)
		end
		context:expect(#locators > 0):toBe(true)
		context:expect(#toolLocators > 0):toBe(true)
		context:expect(seen["suite"].locators):toEqual(locators)
		context:expect(seen["suite"].worker):toBe("tests/worker.luau")
		context:expect(seen["tool-specs"].locators):toEqual(toolLocators)
		context:expect(seen["tool-specs"].worker):toBe("tests/lute/worker.luau")
		context:expect(seen["tool-specs"].command):toBeNil()
		context:expect(seen["suite"].cases):toBeNil()
		context:expect(seen["suite"].isolate):toBe(true)
		context:expect(seen["suite"].sourceDeadlineSeconds):toBe(600)
		local deferrals = assert(assert(definition.policy).deferrals)
		context:expect(deferrals["perf-place"] ~= nil):toBe(true)
		context:expect(deferrals["bench"] ~= nil):toBe(true)
		context:expect(assert(assert(gate.draft(true).policy).deferrals)["bench"]):toBeNil()
		context:expect(deferrals["suite"]):toBeNil()
		local order = {}
		for index, producer in definition.producers do
			order[producer.id] = index
		end
		context:expect(seen["plan"].argv):toEqual({ "lute", "run", "tools/facet", "check", "plan" })
		for _, producer in definition.producers do
			context:expect(table.find(producer.argv or {}, "python3")):toBeNil()
		end
		for _, reader in { "perf-scenes" } do
			context:expect(order["perf"] < order[reader]):toBe(true)
		end
		context:expect(order["package-build"] < order["package-canary"]):toBe(true)
		context:expect(seen["vendor"].argv):toEqual({ "lute", "run", "tools/facet", "check", "vendor" })
		context:expect(seen["standalone-builds"].argv):toEqual({ "lute", "run", "tools/facet", "build", "standalone" })
		context
			:expect(seen["package-build"].argv)
			:toEqual({ "lute", "run", "tools/facet", "package", "build", "--verify" })
	end)
	harness:case("binds the gate to the commit, tree, clean state and package source hash", function(context)
		local build = gate.build()
		context:expect(string.match(build.commit, "^%x+$") ~= nil and #build.commit == 40):toBe(true)
		context:expect(string.match(build.tree, "^%x+$") ~= nil and #build.tree == 40):toBe(true)
		context:expect(type(build.clean)):toBe("boolean")
		context:expect(string.match(build.digest, "^%x+$") ~= nil and #build.digest == 64):toBe(true)
		local bound = Lute.gate.run(
			Gate.define(gate.define({ command("fast", 0) }, false, "fixture-build")),
			{ directory = `{directory}/gate`, build = build }
		)
		context:expect(assert(bound.build).commit):toBe(build.commit)
		context:expect(assert(bound.build).digest):toBe(build.digest)
		context:expect(assert(bound.build).clean):toBe(build.clean)
	end)
	harness:case("rejects malformed reports and conflicting transport segments", function(context)
		context
			:expect(function()
				Verify.decode({})
			end)
			:toThrow()
		local pieces = Verify.segment("a report payload", 4)
		local whole = widen(pieces)
		context:expect((Verify.reassembleSegments(whole))):toBe("a report payload")
		local changed = table.clone(pieces)
		changed[1] = table.clone(changed[1])
		changed[1].payload = "bad bytes"
		local altered = widen(changed)
		context:expect((Verify.reassembleSegments(altered))):toBeNil()
		local absent = table.clone(pieces)
		table.remove(absent)
		local missing = widen(absent)
		context:expect((Verify.reassembleSegments(missing))):toBeNil()
	end)
end)

harness:suite("Native fixture", function()
	harness:case("delegates native fixture hierarchy, clone and UI storage to Verify", function(context)
		local NativeEngine = require("../../tests/lib/native_engine")
		local engine, bridge = NativeEngine.new()
		local tracking = bridge.track()
		context:defer(tracking.stop)
		local model = engine.new("Model")
		local part = engine.new("Part")
		part.Parent = model
		model.PrimaryPart = part
		part:AddTag("fixture")
		part:SetAttribute("ordinal", 7)
		local excluded = engine.new("Folder")
		excluded.Parent = model
		excluded.Archivable = false
		local copy = assert(model:Clone())
		local clonedPart: BasePart = copy:FindFirstChildWhichIsA("BasePart", true)
		assert(clonedPart)
		context:expect(copy.PrimaryPart):toBe(clonedPart)
		context:expect(clonedPart:FindFirstAncestorWhichIsA("Model")):toBe(copy)
		context:expect(clonedPart:HasTag("fixture")):toBe(true)
		context:expect(clonedPart:GetAttribute("ordinal")):toBe(7)
		context:expect(#copy:GetChildren()):toBe(1)
		context:expect(clonedPart.Size):toBe(part.Size)
		local field = engine.new("TextBox")
		field.ClearTextOnFocus = false
		field.Text = "retained"
		field:CaptureFocus()
		context:expect(field:IsFocused()):toBe(true)
		context:expect(field.Text):toBe("retained")
		field:ReleaseFocus(true)
		context:expect(field:IsFocused()):toBe(false)
		local rule = engine.new("StyleRule")
		rule:SetProperties({ BackgroundTransparency = 0.25 })
		local values = rule:GetProperties()
		values.BackgroundTransparency = 1
		context:expect(rule:GetProperties().BackgroundTransparency):toBe(0.25)
		local clonedRule = assert(rule:Clone())
		context:expect(clonedRule:GetProperties().BackgroundTransparency):toBe(0.25)
		clonedRule:SetProperties({ BackgroundTransparency = 0.75 })
		context:expect(rule:GetProperties().BackgroundTransparency):toBe(0.25)
		local path = engine.new("Path2D")
		path:SetControlPoints({ engine.types.Path2DControlPoint.new(engine.types.UDim2.new()) })
		context:expect(#path:GetControlPoints()):toBe(1)
		local clonedPath = assert(path:Clone())
		context:expect(#clonedPath:GetControlPoints()):toBe(1)
		local viewport = engine.new("ViewportFrame")
		viewport.CurrentCamera = engine.new("Camera")
		context:expect(assert(viewport:Clone()).CurrentCamera):toBe(nil)
		for _, node in tracking.created do
			if node:IsA("Instance") then
				((node :: unknown) :: Instance):Destroy()
			end
		end
		context:expect(engine.census().connections):toBe(0)
	end)
end)

local report = harness:run({ executor = "facet-lute", environment = { tier = "full" } })
print(Verify.format(report))
Files.write(`{directory}/selftest.json`, json.serialize(report :: any, true))
if report.total == 0 or report.passed ~= report.total then
	process.exit(1)
end
