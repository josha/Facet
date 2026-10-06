--!strict

local Binding = require "./binding"
local Bounded = require "./bounded"
local Files = require "./files"
local Host = require "./host"
local Verify = require "../core"
local Wire = require "./wire"

export type Options = {
	runId: string?,
	directory: string?,
	build: Verify.EvidenceBuild?,
	selection: Verify.GateSelection?,
	reuse: { [string]: Verify.GateReuse }?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	name: string?,
	logBytes: number?,
	pollSeconds: number?,
	observe: ((record: Verify.GateRecord) -> ())?,
	command: { string }?,
	now: (() -> number)?,
	wait: ((seconds: number) -> ())?,
	fixtures: { { name: string, acquire: () -> (), release: (() -> ())? } }?,
}

export type Gate = {
	run: (gate: Verify.Gate, options: Options?) -> Verify.GateOutcome,
	executor: (options: Options, directory: string, runId: string) -> Verify.GateExecutor,
	writeReport: (path: string, runId: string, report: Verify.Report) -> (),
}

local DEFAULT_CAPABILITIES = { "local-luau", "process" }

local sequence = 0

local function safeName(id: string): string
	return (string.gsub(id, "[^%w%-_]", "-"))
end

local function substitute(argv: { string }, reportPath: string, runId: string): { string }
	local result: { string } = {}
	for _, value in argv do
		local replaced = string.gsub(value, "{report}", function()
			return reportPath
		end)
		replaced = string.gsub(replaced, "{run}", function()
			return runId
		end)
		table.insert(result, replaced)
	end
	return result
end

local function create(runtime: Binding.Runtime, receipts: ("report" | "bound")?): Gate
	Binding.validate(runtime)
	local files = Files.create(runtime.fs)
	local wire = Wire.create(runtime.json)

	local function newRunId(): string
		sequence += 1
		return ("gate-%d-%d-%d"):format(os.time(), math.floor(runtime.time.clock() * 1e6) % 1000000, sequence)
	end

	local function writeReport(path: string, runId: string, report: Verify.Report)
		assert(runId ~= "", "a gate report needs the run id it was started with")
		runtime.fs.write(path, runtime.json.encode { runId = runId, report = Verify.decode(report) })
	end

	local function executor(options: Options, directory: string, runId: string): Verify.GateExecutor
		local now = options.now or runtime.time.clock
		local wait = options.wait or runtime.time.wait
		files.ensureDirectory(directory)

		local function start(job: Verify.GateJob): Verify.GateTask
			local stem = ("%s/%s"):format(directory, safeName(job.id))
			local result: Verify.GateJobOutcome? = nil
			local poll = function(): Verify.GateJobOutcome?
				return result
			end
			if job.kind == "tests" then
				local host = Host.create(runtime, {
					worker = job.worker :: string,
					command = options.command,
					directory = stem .. "-worker",
					deadlineSeconds = job.deadlineSeconds,
					name = "verify-gate-tests",
					receipts = receipts,
				})
				local units: { Verify.PlanUnit } = {}
				for _, locator in job.locators do
					table.insert(units, {
						id = job.id .. ":" .. locator,
						locator = locator,
						group = nil,
						tags = {},
						requires = {},
						deadlineSeconds = nil,
						weight = 1,
					})
				end
				local batch: Verify.PlanBatch =
					{ id = safeName(job.id), index = 1, units = units, deadlineSeconds = job.deadlineSeconds }
				runtime.time.spawn(function()
					local ran, outcome: unknown = pcall(host.runBatch, batch)
					if not ran then
						result = {
							started = false,
							exitcode = -1,
							timedOut = false,
							stdout = "",
							stderr = "",
							detail = tostring(outcome),
						}
						return
					end
					local batchOutcome = outcome :: Verify.BatchOutcome
					result = {
						started = true,
						exitcode = if batchOutcome.status == "returned" then 0 else 1,
						timedOut = batchOutcome.status == "timed_out",
						stdout = "",
						stderr = "",
						report = batchOutcome.report,
						detail = batchOutcome.detail,
					}
				end)
				return { poll = poll }
			end

			local reportPath = stem .. ".report.json"
			local logPath = stem .. ".log"
			files.removeIfPresent(reportPath)
			files.removeIfPresent(logPath)
			local argv = substitute(job.argv, reportPath, runId)
			runtime.time.spawn(function()
				local ran =
					Bounded.run(argv, job.deadlineSeconds, runtime.process.run, { env = job.env, cwd = job.cwd })
				local started = ran.exitcode ~= -1 or ran.stderr == ""
				local document: unknown = nil
				local detail: string? = if started then nil else ran.stderr
				if started and not ran.timedOut and runtime.fs.exists(reportPath) then
					local read, text: unknown = pcall(runtime.fs.read, reportPath)
					if read then
						local parsed, value: unknown = pcall(wire.parse, text :: string)
						if parsed then
							document = value
						else
							detail = "the report file is unreadable: " .. tostring(value)
						end
					else
						detail = "the report file could not be read: " .. tostring(text)
					end
				elseif started and job.expectsReport and not ran.timedOut then
					detail = "no report file was written"
				end
				local logged = pcall(
					runtime.fs.write,
					logPath,
					("$ %s\nexit %d%s\n--- stdout ---\n%s\n--- stderr ---\n%s\n"):format(
						table.concat(argv, " "),
						ran.exitcode,
						if ran.timedOut then " (deadline exceeded)" else "",
						ran.stdout,
						ran.stderr
					)
				)
				result = {
					started = started,
					exitcode = ran.exitcode,
					timedOut = ran.timedOut,
					stdout = ran.stdout,
					stderr = if started then ran.stderr else "",
					report = document,
					detail = detail,
					logReference = if logged then logPath else nil,
				}
			end)
			return { poll = poll }
		end

		return { now = now, wait = wait, start = start }
	end

	local function run(gate: Verify.Gate, options: Options?): Verify.GateOutcome
		local settings: Options = if options ~= nil then options else {}
		local runId = settings.runId or newRunId()
		local directory = ("%s/%s"):format(settings.directory or runtime.defaultDirectory .. "/gate", safeName(runId))
		local capabilities: { string } = table.clone(DEFAULT_CAPABILITIES)
		local extra: { string } = if settings.capabilities ~= nil then settings.capabilities else {}
		for _, capability in extra do
			table.insert(capabilities, capability)
		end
		local environment: { [string]: string } = { runtime = runtime.name }
		local supplied: { [string]: string } = if settings.environment ~= nil then settings.environment else {}
		for key, value in supplied do
			environment[key] = value
		end
		return Verify.runGate(gate, executor(settings, directory, runId), {
			runId = runId,
			build = settings.build,
			selection = settings.selection,
			reuse = settings.reuse,
			capabilities = capabilities,
			environment = environment,
			name = settings.name,
			logBytes = settings.logBytes,
			pollSeconds = settings.pollSeconds,
			observe = settings.observe,
			fixtures = settings.fixtures,
		})
	end

	return { run = run, executor = executor, writeReport = writeReport }
end

return {
	DEFAULT_CAPABILITIES = DEFAULT_CAPABILITIES,
	create = create,
}
