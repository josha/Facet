--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local Lune = require("../vendor/verify/src/lune")
local Verify = require("../vendor/verify/src/core")
local gate = require("./gate")
local suite = require("./suite")

local harness = Verify.createHarness({ source = "facet-verify-integration", now = os.clock })
local directory = "artifacts/verify/integration"
local VERIFY = "../../../tools/vendor/verify/src"
if fs.isDir(directory) then
	fs.removeDir(directory)
end
fs.writeDir(directory)

local function source(name: string, text: string): Verify.Plan
	fs.writeFile(`{directory}/{name}.luau`, text)
	return Verify.validatePlan({
		id = name,
		policy = { caseIdStyle = "bare" },
		units = { { id = name, locator = `{directory}/{name}.luau` } },
	})
end

local function run(plan: Verify.Plan, tier: string, worker: string?, deadline: number?): Verify.ExecutionReport
	return (
		suite.execute({
			tier = tier,
			plan = plan,
			worker = worker,
			directory = `{directory}/receipts`,
			deadlineSeconds = deadline or 60,
			jobs = 1,
		})
	)
end

local function inventory(plan: Verify.Plan, cases: { [string]: string | boolean }): suite.Inventory
	local rows = {}
	for id, tier in cases do
		table.insert(rows, { id = id, source = plan.units[1].id, tier = if type(tier) == "string" then tier else nil })
	end
	return { cases = rows }
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
			'local report = harness:run({ executor = "fixture", environment = { runtime = "lune", tier = "full" }, capabilities = { "local-luau" } })',
			"local function receipt(run, id) return Lune.encodeReceipt(Lune.runtime.json, run, id, report) end",
			body,
		}, "\n")
	)
	return path
end

local function command(id: string, script: string, environment: string?, tier: string?): gate.Entry
	return {
		id = id,
		argv = { "/bin/sh", "-c", script },
		tier = tier or "fast",
		environment = environment or "deterministic",
	}
end

local function reporter(id: string, mode: string, expectation: Verify.GateReportExpectation?): gate.Entry
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
		argv = { "lune", "run", path, mode, "{report}", "{run}" },
		tier = "fast",
		environment = "deterministic",
		report = expectation or { minimum = 1 },
	}
end

local sequence = 0
local function runGate(
	entries: { gate.Entry },
	options: { referenceHost: boolean?, tier: string?, rerun: string? }?
): Verify.GateOutcome
	sequence += 1
	local settings: { referenceHost: boolean?, tier: string?, rerun: string? } = options or {}
	local definition = gate.define(entries, settings.referenceHost == true, `fixture-{sequence}`)
	return Lune.gate.run(definition, {
		directory = `{directory}/gate`,
		selection = gate.selection(settings.tier or "release", settings.rerun),
	})
end

local function status(outcome: Verify.GateOutcome, id: string): string
	for _, record in outcome.producers do
		if record.id == id then
			return record.status
		end
	end
	error("no producer record: " .. id)
end

harness:suite("Suite execution through the Verify Lune host", function()
	harness:case("accounts for missing, load, registration, non-function and empty sources", function(context)
		local missing = Verify.validatePlan({
			id = "missing",
			policy = { caseIdStyle = "bare" },
			units = { { id = "missing", locator = `{directory}/missing.luau` } },
		})
		local plans: { [string]: Verify.Plan } = {
			missing = missing,
			broken = source("broken", 'error("broken source")'),
			registration = source("registration", 'return function() error("broken registration") end'),
			value = source("value", "return {}"),
			empty = source("empty", "return function() end"),
		}
		local accepted = {}
		for name, plan in plans do
			local execution = run(plan, "full")
			if #suite.findings(execution, plan, "full", { cases = {} }) == 0 or execution.report.passed > 0 then
				table.insert(accepted, name)
			end
		end
		context:expect(accepted):toEqual({})
		context:expect(run(plans.broken, "full").report.results[1].id):toBe("unit:broken:faulted")
		context:expect(run(plans.value, "full").report.results[1].id):toBe("unit:value:load")
		context:expect(run(plans.registration, "full").report.results[1].id):toBe("unit:registration:registration")
		context:expect(run(plans.empty, "full").report.failed > 0):toBe(true)
	end)
	harness:case("preserves case and cleanup failures independently", function(context)
		local plan = source(
			"cleanup",
			'return function(h) h:case("fails", { id="fails", run=function(c) c:defer(function() error("cleanup failure") end) error("body failure") end }) end'
		)
		local execution = run(plan, "full")
		local result = execution.report.results[1]
		context:expect(result.status):toBe("failed")
		context:expect(#result.failures):toBe(2)
		context:expect(result.failures[1].phase):toBe("case")
		context:expect(result.failures[2].phase):toBe("cleanup")
		context:expect(#suite.findings(execution, plan, "full", inventory(plan, { fails = true })) > 0):toBe(true)
	end)
	harness:case("rejects duplicate IDs, unapproved skips and census drift", function(context)
		local duplicate = source(
			"duplicate",
			'return function(h) h:case("one",{id="same",run=function() end}) h:case("two",{id="same",run=function() end}) end'
		)
		context
			:expect(
				#suite.findings(run(duplicate, "full"), duplicate, "full", inventory(duplicate, { same = true })) > 0
			)
			:toBe(true)
		local skipped = source("skipped", 'return function(h) h:skip("absent", "no setup") end')
		context:expect(#suite.findings(run(skipped, "full"), skipped, "full", inventory(skipped, {})) > 0):toBe(true)
		local passing =
			source("passing", 'return function(h) h:case("one",{id="one",run=function(c) c:expect(1):toBe(1) end}) end')
		local execution = run(passing, "full")
		context:expect(suite.findings(execution, passing, "full", inventory(passing, { one = true }))):toEqual({})
		context:expect(#suite.findings(execution, passing, "full", inventory(passing, {})) > 0):toBe(true)
		context
			:expect(#suite.findings(execution, passing, "full", inventory(passing, { one = true, two = true })) > 0)
			:toBe(true)
		context:expect(#suite.findings(execution, passing, "fast", inventory(passing, { one = true })) > 0):toBe(true)
	end)
	harness:case("keeps the release-only case out of lower tiers and requires it at release", function(context)
		local plan = source(
			"release",
			'return function(h,tier) h:case("always",{id="always",run=function() end}) h:case("ramp",{id="ramp",run=function(c) if tier ~= "release" then c:skip("tier:release") end c:expect(true):toBe(true) end}) end'
		)
		local committed = inventory(plan, { always = true, ramp = "release" })
		local lower = run(plan, "full")
		local release = run(plan, "release")
		context:expect(lower.report.skipped):toBe(1)
		context:expect(release.report.passed):toBe(2)
		context:expect(suite.findings(lower, plan, "full", committed)):toEqual({})
		context:expect(suite.findings(release, plan, "release", committed)):toEqual({})
		context:expect(#suite.findings(lower, plan, "release", committed) > 0):toBe(true)
		context
			:expect(#suite.findings(lower, plan, "full", inventory(plan, { always = true, ramp = true })) > 0)
			:toBe(true)
		local adopted = suite.tierReport(lower, "full")
		context:expect(adopted.total):toBe(1)
		context:expect(adopted.passed):toBe(1)
		context:expect(adopted.skipped):toBe(0)
		context:expect(suite.tierReport(release, "release").total):toBe(2)
	end)
	harness:case(
		"rejects missing, empty, malformed, foreign, stale and contradictory worker receipts",
		function(context)
			local plan = source("receipt", "return function() end")
			local faults: { [string]: string } = {
				silent = "",
				empty = 'fs.writeFile(output, "")',
				malformed = 'fs.writeFile(output, "{ not json")',
				foreign = 'fs.writeFile(output, receipt(runId, "another-batch"))',
				stale = 'fs.writeFile(output, receipt("another-run", batch.id))',
				invalid = 'fs.writeFile(output, serde.encode("json", { receiptVersion = 1, runId = runId, batchId = batch.id, report = { total = 5 } }))',
				contradictory = "fs.writeFile(output, receipt(runId, batch.id)) process.exit(1)",
			}
			local unnoticed = {}
			for name, body in faults do
				local execution = run(plan, "full", worker(name, body))
				if execution.report.passed > 0 or #suite.findings(execution, plan, "full", { cases = {} }) == 0 then
					table.insert(unnoticed, name)
				end
			end
			context:expect(unnoticed):toEqual({})
			local accepted = run(plan, "full", worker("accepted", "fs.writeFile(output, receipt(runId, batch.id))"))
			context:expect(accepted.report.passed):toBe(1)
		end
	)
	harness:case("stops a timed-out worker and its descendants", function(context)
		local marker = `{directory}/descendant-survived`
		local plan = source("hang", "return function() end")
		local execution = run(
			plan,
			"full",
			worker("hang", `process.exec("/bin/sh", \{ "-c", "(sleep 3; touch {marker}) & sleep 30" })`),
			1
		)
		context:expect(execution.report.timedOut):toBe(1)
		context:expect(#suite.findings(execution, plan, "full", { cases = {} }) > 0):toBe(true)
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
		context:expect(select(2, gate.conclusion(release, "release", nil))):toBe(0)
		local full = runGate(clean, { tier = "full" })
		context:expect(full.acceptance.verdict):toBe("selected")
		context:expect(full.acceptance.releasable):toBe(false)
		context:expect(gate.tierComplete(full, "full", nil)):toBe(true)
		context:expect(status(full, "gate")):toBe("not_selected")
		context:expect((gate.conclusion(full, "full", nil))):toContain("complete full tier")
		local focused = runGate(clean, { tier = "full", rerun = "fast" })
		context:expect(gate.tierComplete(focused, "full", "fast")):toBe(false)
		context:expect((gate.conclusion(focused, "full", "fast"))):toContain("PASS_SELECTED")
		local fast = runGate(clean, { tier = "fast" })
		context:expect((gate.conclusion(fast, "fast", nil))):toContain("PASS_PARTIAL")
		local deferred = { command("fast", "exit 0"), command("live", "exit 2", "studio", "full") }
		local lower = runGate(deferred, { tier = "full" })
		context:expect(lower.acceptance.deferred):toEqual({ "live" })
		context:expect(select(2, gate.conclusion(lower, "full", nil))):toBe(0)
		local blocked = runGate(deferred, { tier = "release" })
		context:expect(blocked.acceptance.verdict):toBe("deferred")
		context:expect(blocked.acceptance.releasable):toBe(false)
		context:expect(select(2, gate.conclusion(blocked, "release", nil))):toBe(1)
		local failed = runGate({ command("fast", "exit 1") }, { tier = "fast" })
		context:expect(select(2, gate.conclusion(failed, "fast", nil))):toBe(1)
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
		hung.deadlineSeconds = 1
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
		local entries = gate.catalog("full")
		for _, entry in entries do
			context:expect(seen[entry.id]):toBeNil()
			seen[entry.id] = entry
			tiers[entry.tier] += 1
		end
		context:expect(tiers):toEqual({ fast = 19, full = 59, release = 2 })
		context:expect(seen["perf"].tier):toBe("full")
		context:expect(seen["prove-perf-gate"].tier):toBe("release")
		context:expect(#assert(assert(seen["suite"].report).cases)):toBe(3730)
		context:expect(#assert(assert(gate.catalog("release")[12].report).cases)):toBe(3731)
		local definition = gate.define(entries, false)
		context:expect(definition.policy.deferrals["live-evidence"] ~= nil):toBe(true)
		context:expect(definition.policy.deferrals["bench"] ~= nil):toBe(true)
		context:expect(gate.define(entries, true).policy.deferrals["bench"]):toBeNil()
		context:expect(definition.policy.deferrals["suite"]):toBeNil()
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
