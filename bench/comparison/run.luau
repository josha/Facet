--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Register = require("../../tests/native_bench_comparison.verify")
local Lute = require("../../tools/vendor/verify/src/lute")
local fs = require("@std/fs")
local process = require("@std/process")
local Workloads = require("./init")
local Measure = require("./measure")
local Report = require("../../tools/facet/lib/bench_compare_report")
local Run = require("../../tools/facet/lib/run")
local system = require("@std/system")
local Json = require("../../tools/facet/lib/json")
local Files = require("../../tools/facet/lib/files")

return function(arguments: { string }): number
	local out = "artifacts/facet-vs-plain"
	local filter: string? = nil
	local verify = false
	local index = 2
	while index <= #arguments do
		local option = arguments[index]
		if option == "--verify" then
			verify = true
		elseif option == "--out" or option == "--filter" then
			index += 1
			local value = assert(arguments[index], "missing value for " .. option)
			if option == "--out" then
				out = value
			else
				filter = value
			end
		else
			error("unknown comparison option " .. option)
		end
		index += 1
	end
	fs.createDirectory(out, { makeParents = true })
	local harness = Verify.createHarness({ now = os.clock })
	Register(harness)
	local report = harness:run({ executor = "facet-lute", selection = { nameContains = filter } })
	fs.writeStringToFile(out .. "/parity.json", Lute.encode(report) .. "\n")
	print(Verify.format(report))
	if report.failed > 0 or report.passed == 0 or report.passed ~= report.total then
		return 1
	end
	if verify then
		return 0
	end
	for _, name in { "report.json", "comparison.md", "failure.json" } do
		local path = out .. "/" .. name
		if fs.exists(path) then
			Files.remove(path)
		end
	end
	local rows: { Report.Row } = {}
	local descriptions: { { id: string, what: string } } = {}
	local measurements: { Measure.Evidence } = {}
	local revision = assert(Run.gitOutput({ "rev-parse", "HEAD" }))
	local cpus = system.cpus()
	local environment = {
		os = system.os,
		architecture = system.arch,
		threads = system.threadCount(),
		cpu = if #cpus > 0 then cpus[1].model else "unknown",
		runtime = Run.capture({ Run.lute(), "--version" }).stdout,
	}
	local dependencies = {
		compose = Json.stringField(Json.decode(fs.readFileToString("src/vendor/compose/UPSTREAM.lock")), "commit"),
		verify = Json.stringField(Json.decode(fs.readFileToString("tools/vendor/verify/UPSTREAM.lock")), "commit"),
	}
	local function save(complete: boolean)
		fs.writeStringToFile(out .. "/report.json", Lute.encode({
			schema = "facet-vs-plain/1",
			complete = complete,
			revision = revision,
			status = Run.gitOutput({ "status", "--porcelain" }),
			environment = environment,
			dependencies = dependencies,
			arguments = arguments,
			parity = report,
			measurements = measurements,
			rows = rows,
			missingMetrics = { "connectionsMade", "tasksDeferred" },
		}) .. "\n")
	end
	local selected = 0
	save(false)
	for position, workload in Workloads do
		if filter and not string.find(workload.id, filter, 1, true) then
			continue
		end
		selected += 1
		print("compare: measuring " .. workload.id)
		local ok, evidence = pcall(Measure, workload, position)
		if not ok then
			save(false)
			fs.writeStringToFile(
				out .. "/failure.json",
				Lute.encode({ workload = workload.id, error = tostring(evidence) }) .. "\n"
			)
			print("compare: measurement failed: " .. tostring(evidence))
			return 1
		end
		table.insert(measurements, evidence)
		if evidence.problem then
			save(false)
			print("compare: invalid measurement: " .. evidence.problem)
			return 1
		end
		for _, row in evidence.rows do
			table.insert(rows, row)
		end
		table.insert(descriptions, { id = workload.id, what = workload.what })
		save(false)
	end
	assert(selected > 0, "no comparison workload matches")
	save(true)
	local markdown = Report.markdown(rows, revision, descriptions)
	fs.writeStringToFile(out .. "/comparison.md", markdown)
	if filter == nil then
		fs.createDirectory("docs/performance", { makeParents = true })
		fs.writeStringToFile("docs/performance/facet-vs-plain.md", markdown)
	end
	local summary = process.env.GITHUB_STEP_SUMMARY
	if summary then
		fs.writeStringToFile(summary, (if fs.exists(summary) then fs.readFileToString(summary) else "") .. markdown)
	end
	print(`compare: {selected} pairs; reports in {out}`)
	return 0
end
