--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Lune = require("../vendor/verify/src/lune")
local Verify = require("../vendor/verify/src/core")
local Gate = require("../vendor/verify/src/gate")
local gate = require("./gate")

local harness = Verify.createHarness({ source = "facet-verify-integration", now = os.clock })
local directory = "artifacts/verify/integration"
local VERIFY = "../../../tools/vendor/verify/src"
if fs.isDir(directory) then
	fs.removeDir(directory)
end
fs.writeDir(directory)

local function source(name: string, text: string): string
	fs.writeFile(`{directory}/{name}.luau`, text)
	return `{directory}/{name}.luau`
end

local function worker(name: string, body: string): string
	local path = `{directory}/{name}-worker.luau`
	fs.writeFile(
		path,
		table.concat({
			'local fs = require("@lune/fs")',
			'local process = require("@lune/process")',
			'local serde = require("@lune/serde")',
			`local Lune = require("{VERIFY}/lune")`,
			`local Verify = require("{VERIFY}/core")`,
			"local batch = Lune.decodeBatch(fs.readFile(process.args[1]))",
			"local output, runId = process.args[2], process.args[3]",
			"local harness = Verify.createHarness({ now = os.clock, source = batch.units[1].locator, prefixIds = false })",
			'harness:case("ok", { id = "ok", run = function() end })',
			'local report = harness:run({ executor = "fixture", environment = { runtime = "lune" }, capabilities = { "local-luau" } })',
			"local function receipt(run, id) return Lune.encodeReceipt(Lune.runtime.json, run, id, report) end",
			body,
		}, "\n")
	)
	return path
end

local function tests(id: string, locators: { string }, cases: { string }?, custom: string?): gate.Entry
	return {
		id = id,
		tier = "fast",
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

local function command(id: string, script: string, environment: string?, tier: string?): gate.Entry
	return {
		id = id,
		tier = tier or "fast",
		environment = environment,
		producer = { id = id, kind = "command", argv = { "/bin/sh", "-c", script } },
	}
end

local function reporter(id: string, mode: string, expectation: Gate.ReportExpectation?): gate.Entry
	local path = `{directory}/reporter.luau`
	fs.writeFile(
		path,
		table.concat({
			'local fs = require("@lune/fs")',
			'local process = require("@lune/process")',
			`local Lune = require("{VERIFY}/lune")`,
			`local Verify = require("{VERIFY}/core")`,
			"local mode, path, run = process.args[1], process.args[2], process.args[3]",
			'local harness = Verify.createHarness({ now = os.clock, source = "reporter", prefixIds = false })',
			'harness:case("one", { id = "one", run = function(context) context:expect(mode ~= "failing"):toBe(true) end })',
			'local report = harness:run({ executor = "fixture", environment = { runtime = "lune" } })',
			'if mode == "empty" then fs.writeFile(path, "")',
			'elseif mode == "malformed" then fs.writeFile(path, "{ not json")',
			'elseif mode == "stale" then Lune.gate.writeReport(path, "another-run", report)',
			'elseif mode ~= "missing" then Lune.gate.writeReport(path, run, report) end',
			'process.exit(if mode == "contradicts" then 1 else 0)',
		}, "\n")
	)
	return {
		id = id,
		tier = "fast",
		producer = {
			id = id,
			kind = "command",
			argv = { "lune", "run", path, mode, "{report}", "{run}" },
			report = expectation or { minimum = 1 },
		},
	}
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
	if settings.rerun then
		chosen = { ids = { settings.rerun }, tiers = if #tiers > 0 then tiers else nil }
	end
	return Lune.gate.run(definition, { directory = `{directory}/gate`, selection = chosen })
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
	harness:case(
		"rejects missing, empty, malformed, foreign, stale and contradictory worker receipts",
		function(context)
			local locator = source("receipt", "return function() end")
			local faults: { [string]: string } = {
				silent = "",
				empty = 'fs.writeFile(output, "")',
				malformed = 'fs.writeFile(output, "{ not json")',
				foreign = 'fs.writeFile(output, receipt(runId, "another-batch"))',
				stale = 'fs.writeFile(output, receipt("another-run", batch.id))',
				invalid = 'fs.writeFile(output, serde.encode("json", { receiptVersion = 1, runId = runId, batchId = batch.id, report = { total = 5 } }))',
				contradictory = "fs.writeFile(output, receipt(runId, batch.id)) process.exit(1)",
			}
			local entries = {
				tests(
					"accepted",
					{ locator },
					nil,
					worker("accepted", "fs.writeFile(output, receipt(runId, batch.id))")
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
		end
	)
	harness:case("stops a timed-out worker and its descendants", function(context)
		local marker = `{directory}/descendant-survived`
		local hung = tests(
			"hang",
			{ source("hang", "return function() end") },
			nil,
			worker("hang", `process.exec("/bin/sh", \{ "-c", "(sleep 3; touch {marker}) & sleep 30" })`)
		)
		assert(hung.producer).deadlineSeconds = 1
		local outcome = runGate({ hung })
		context:expect(status(outcome, "hang") ~= "passed"):toBe(true)
		context:expect(outcome.execution.report.timedOut + outcome.execution.report.failed > 0):toBe(true)
		task.wait(4)
		context:expect(fs.isFile(marker)):toBe(false)
	end)
end)

harness:suite("Facet gate through Verify", function()
	harness:case("classifies pass, failure and environment deferral by producer class", function(context)
		local entries = {
			command("pass", "exit 0"),
			command("failure", "exit 1"),
			command("unclassified", "exit 2"),
			command("live", "exit 2", "studio"),
			command("device", "exit 2", "device"),
			command("timing", "exit 2", "perf"),
			command("live-broken", "exit 1", "studio"),
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
			command("fast", "exit 0"),
			command("full", "exit 0", nil, "full"),
			command("gate", "exit 0", nil, "release"),
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
		context:expect(gate.releasable(0, "release", full)):toBe(1)
		local focused = runGate(clean, { tier = "full", rerun = "fast" })
		context:expect(completeTier(focused)):toBe(false)
		context:expect(focused.acceptance.verdict):toBe("selected")
		local deferred = { command("fast", "exit 0"), command("live", "exit 2", "studio", "full") }
		local lower = runGate(deferred, { tier = "full" })
		context:expect(lower.acceptance.deferred):toEqual({ "live" })
		context:expect(lower.acceptance.verdict ~= "failed"):toBe(true)
		local blocked = runGate(deferred, { tier = "release" })
		context:expect(blocked.acceptance.verdict):toBe("deferred")
		context:expect(blocked.acceptance.releasable):toBe(false)
		context:expect(gate.releasable(0, "release", blocked)):toBe(1)
		local failed = runGate({ command("fast", "exit 1") }, { tier = "fast" })
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
			reporter("contradicts", "contradicts"),
		})
		context:expect(status(outcome, "accepted")):toBe("passed")
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
		local hung = command("hung", `(sleep 3; touch {marker}) & sleep 30`)
		assert(hung.producer).deadlineSeconds = 1
		local dependent = command("dependent", "exit 0")
		dependent.after = { "hung" }
		local outcome = runGate({ hung, dependent })
		context:expect(status(outcome, "hung")):toBe("timed_out")
		context:expect(status(outcome, "dependent")):toBe("blocked")
		context:expect(outcome.acceptance.verdict):toBe("failed")
		task.wait(4)
		context:expect(fs.isFile(marker)):toBe(false)
	end)
	harness:case("declares every committed producer once with its tier and suite census", function(context)
		local tiers = { fast = 0, full = 0, release = 0 }
		local seen = {}
		local definition = gate.draft(false)
		for _, producer in definition.producers do
			context:expect(seen[producer.id]):toBeNil()
			seen[producer.id] = producer
			tiers[producer.tier :: string] += 1
		end
		context:expect(tiers):toEqual({ fast = 19, full = 59, release = 2 })
		context:expect(seen["perf"].tier):toBe("full")
		context:expect(seen["prove-perf-gate"].tier):toBe("release")
		local plan = serde.decode("json", fs.readFile("tests/plan.json"))
		local planned, expected = {}, 0
		for _, unit in plan.units do
			planned[unit.id] = true
		end
		for _, entry in serde.decode("json", fs.readFile("tests/case_inventory.json")).cases do
			expected += if planned[entry.source] then 1 else 0
		end
		context:expect(expected > 3700):toBe(true)
		context:expect(#assert(seen["suite"].cases)):toBe(expected)
		context:expect(#assert(seen["suite"].locators)):toBe(#plan.units)
		context:expect(seen["suite"].isolate):toBe(true)
		context:expect(seen["suite"].sourceDeadlineSeconds):toBe(600)
		local deferrals = assert(assert(definition.policy).deferrals)
		context:expect(deferrals["live-evidence"] ~= nil):toBe(true)
		context:expect(deferrals["bench"] ~= nil):toBe(true)
		context:expect(assert(assert(gate.draft(true).policy).deferrals)["bench"]):toBeNil()
		context:expect(deferrals["suite"]):toBeNil()
		local order = {}
		for index, producer in definition.producers do
			order[producer.id] = index
		end
		context:expect(order["suite"] < order["replacement-cases"]):toBe(true)
		context:expect(seen["replacement-cases"].after):toEqual({ "suite" })
		for _, reader in { "perf-budgets", "perf-metrics", "perf-scenes", "perf-gate-evidence-budgets" } do
			context:expect(order["perf"] < order[reader]):toBe(true)
		end
		context:expect(order["model-build"] < order["package-verify"]):toBe(true)
		context:expect(seen["perf-gate-evidence-falsifiable"].tier):toBe("release")
		context:expect(order["perf-gate-evidence-perf-gate"] < order["prove-perf-gate"]):toBe(true)
		context:expect(order["prove-perf-gate"] < order["perf-gate-evidence-falsifiable"]):toBe(true)
	end)
	harness:case("binds the gate to the commit, tree, clean state and package source hash", function(context)
		local build = gate.build()
		context:expect(string.match(build.commit, "^%x+$") ~= nil and #build.commit == 40):toBe(true)
		context:expect(string.match(build.tree, "^%x+$") ~= nil and #build.tree == 40):toBe(true)
		context:expect(type(build.clean)):toBe("boolean")
		context:expect(string.match(build.digest, "^%x+$") ~= nil and #build.digest == 64):toBe(true)
		local bound = Lune.gate.run(
			Gate.define(gate.define({ command("fast", "exit 0") }, false, "fixture-build")),
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
		context:expect((Verify.reassembleSegments(pieces))):toBe("a report payload")
		local changed = table.clone(pieces)
		changed[1] = table.clone(changed[1])
		changed[1].payload = "bad bytes"
		context:expect((Verify.reassembleSegments(changed))):toBeNil()
		local absent = table.clone(pieces)
		table.remove(absent)
		context:expect((Verify.reassembleSegments(absent))):toBeNil()
	end)
end)

harness:suite("Native fixture", function()
	harness:case("delegates native fixture hierarchy, clone and UI storage to Verify", function(context)
		local NativeEngine = require("../../tests/lib/native_engine")
		local engine = NativeEngine.new()
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
		local clonedPart = assert(copy:FindFirstChildWhichIsA("BasePart", true))
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
		for _, node in engine.made do
			node:Destroy()
		end
		context:expect(engine.census().connections):toBe(0)
	end)
end)

local report = harness:run({ executor = "facet-lune", environment = { tier = "full" } })
print(Verify.format(report))
fs.writeFile(`{directory}/selftest.json`, serde.encode("json", report, true))
if report.total == 0 or report.passed ~= report.total then
	process.exit(1)
end
