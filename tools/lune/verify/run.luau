--!strict
--[[ RUNNING PRODUCERS: at most once per exact identity, and never overlapping
	something that measures.

	Everything here is about two failure modes.

	THE FIRST is doing the work twice. A producer is looked up in the store by
	identity before it is run, and the store's refusal reasons (results.luau) are
	the only thing allowed to turn a hit into a miss. A hit is recorded with its
	reason so the report can say WHY something was reused, not merely that it was.

	THE SECOND is making the answer depend on the schedule. Deterministic
	producers run in parallel with isolated TMPDIRs; anything that measures wall
	clock or memory, drives Studio, mutates a package, or touches external state
	runs strictly alone and never alongside the parallel batch. `prior_gates.sh`
	learned this the expensive way: phase-3-pilot failed in-batch 2/2 and passed
	standalone 2/2 with nothing in the tree changed, because tools/bench.sh was
	measuring the previous gate's tail. ]]

local datetime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local identity = require("./identity")
local results = require("./results")
local util = require("./util")

local runner = {}

runner.TMP_ROOT = "artifacts/verify/tmp"
runner.TRACE = "artifacts/verify/invocation-trace.json"

export type Outcome = {
	producer: string,
	identity: string,
	status: string, -- PASS | FAIL | SKIP_MISSING
	reused: boolean,
	reason: string,
	durationMs: number,
	exitCode: number,
	environmentClass: string,
	command: string,
	record: results.Record?,
	stdout: string?,
	stderr: string?,
}

local function stripAnsi(text: string): string
	return (string.gsub(text, "\27%[[0-9;]*m", ""))
end

local function nowIso(): string
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--[[ A producer that hangs must not hang the coordinator. bash 3.2 has no
	`timeout` and this platform ships no coreutils, so the watchdog is by hand:
	background the work, background a killer, wait for whichever finishes.

	THE WATCHDOG'S STDIO IS CLOSED, AND THAT IS THE WHOLE TRICK. Written the
	obvious way, the `( sleep N; kill … ) &` subshell INHERITS the pipe the
	caller reads the producer's output from, so the read does not see EOF until
	the sleep ends — and a producer with a 1200 s timeout hangs the coordinator
	for twenty minutes after finishing in eight seconds. Measured 2026-08-30, on
	the first run of this file. `pkill -P` then reaps the `sleep` itself, which
	`kill` on the subshell does not. ]]
local function withTimeout(command: string, timeoutS: number): string
	return table.concat({
		`( {command} ) & __facet_pid=$!`,
		`( sleep {timeoutS}; kill -TERM $__facet_pid 2>/dev/null; sleep 5; kill -KILL $__facet_pid 2>/dev/null ) >/dev/null 2>&1 </dev/null & __facet_watch=$!`,
		"wait $__facet_pid; __facet_rc=$?",
		"pkill -P $__facet_watch >/dev/null 2>&1; kill $__facet_watch >/dev/null 2>&1",
		"exit $__facet_rc",
	}, "\n")
end

local traceLines: { string } = {}

local function trace(runId: string, producer: identity.Producer, id: string, action: string)
	local line = util.canonicalJson({
		runId = runId,
		at = nowIso(),
		producer = producer.id,
		identity = id,
		environmentClass = producer.environmentClass,
		action = action,
	})
	table.insert(traceLines, line)
	-- appended as it happens, so a killed run still leaves its trace behind
	local existing = if fs.isFile(runner.TRACE) then fs.readFile(runner.TRACE) else ""
	fs.writeFile(runner.TRACE, existing .. line .. "\n")
end

export type Context = {
	runId: string,
	toolchain: identity.Toolchain,
	tier: string,
	suiteTranscript: string?,
	rrTranscript: string?,
	rerun: { [string]: boolean },
}

--[[ The command a producer actually runs, with its private temp directory and
	whatever extra environment its kind needs. ]]
local function buildCommand(producer: identity.Producer, tmp: string, suiteJson: string?): string
	local prefix = `mkdir -p "{tmp}" && TMPDIR="{tmp}" `
	if suiteJson ~= nil then
		prefix ..= `FACET_SUITE_JSON="{suiteJson}" `
	end
	return prefix .. producer.command
end

local function producerScriptExists(producer: identity.Producer): boolean
	local command = producer.command
	local script: string? = nil
	if string.sub(command, 1, 8) == "python3 " then
		script = string.match(command, "^python3%s+([^%s]+)")
	elseif string.sub(command, 1, 9) == "lune run " then
		local target = string.match(command, "^lune run%s+([^%s]+)")
		if target ~= nil then
			script = `{target}.luau`
		end
	elseif string.match(command, "^%.?/?tools/[%w_]+%.sh") then
		script = string.match(command, "^%.?/?(tools/[%w_]+%.sh)")
	elseif string.match(command, "^cd ([^%s]+) && ") then
		script = string.match(command, "^cd ([^%s]+) && ")
	end
	if script == nil then
		return true
	end
	return fs.isFile(script) or fs.isDir(script)
end

function runner.execute(producer: identity.Producer, ctx: Context): Outcome
	local computed = identity.compute(producer, ctx.toolchain)
	local id = computed.hash
	local base: Outcome = {
		producer = producer.id,
		identity = id,
		status = "PASS",
		reused = false,
		reason = "",
		durationMs = 0,
		exitCode = 0,
		environmentClass = producer.environmentClass,
		command = producer.command,
	}

	if not producerScriptExists(producer) then
		base.status = "SKIP_MISSING"
		base.reason = "the producer's command is not present in this tree"
		trace(ctx.runId, producer, id, "skip-missing")
		return base
	end

	if not ctx.rerun[producer.id] then
		local record, reason = results.read(producer.id, id, {
			requiredClass = producer.environmentClass,
			toolchain = identity.toolchainString(ctx.toolchain),
			suite = producer.kind == "suite" and producer.id == "suite",
		})
		if record ~= nil then
			base.reused = true
			base.reason = "stored result for this exact identity"
			base.durationMs = record.durationMs
			base.record = record
			trace(ctx.runId, producer, id, "reuse")
			return base
		end
		base.reason = reason or "no stored result"
	else
		base.reason = "--rerun was asked for this producer"
	end

	local tmp = `{runner.TMP_ROOT}/{producer.id}`
	local suiteJson: string? = nil
	if producer.id == "suite" or producer.id == "suite-fast" then
		suiteJson = `{tmp}/suite-results.json`
	end
	local command = buildCommand(producer, tmp, suiteJson)
	trace(ctx.runId, producer, id, "run")
	local startedAt = nowIso()
	-- WALL CLOCK, not os.clock(). os.clock() is THIS process's CPU time, and a
	-- coordinator that spends its time waiting on children accumulates almost
	-- none of it — every producer would report ~0 ms.
	local t0 = datetime.now().unixTimestampMillis
	local result = process.exec("bash", { "-c", withTimeout(command, producer.timeoutS or 600) })
	local elapsed = datetime.now().unixTimestampMillis - t0

	local stdout = result.stdout or ""
	local stderr = result.stderr or ""
	base.exitCode = result.code
	base.durationMs = elapsed
	base.stdout = stdout
	base.stderr = stderr

	local payload: { [string]: any } = {
		toolchain = identity.toolchainString(ctx.toolchain),
		stdoutTail = string.sub(stripAnsi(stdout), -4000),
		stderrTail = string.sub(stripAnsi(stderr), -4000),
	}
	local complete = true

	if suiteJson ~= nil then
		if fs.isFile(suiteJson) then
			payload.results = serde.decode("json", fs.readFile(suiteJson))
		else
			complete = false
			base.reason = "the suite produced no structured results file"
		end
		-- the human transcript, recorded once, for the handful of manifest greps
		-- whose case no longer exists (graph-census.md names every one)
		local transcriptPath = `{results.ROOT}/{producer.id}/{id}.transcript.txt`
		if not fs.isDir(`{results.ROOT}/{producer.id}`) then
			fs.writeDir(`{results.ROOT}/{producer.id}`)
		end
		fs.writeFile(transcriptPath, stripAnsi(stdout))
		payload.transcript = transcriptPath
	elseif producer.id == "rascalrally-suite" then
		local transcriptPath = `{results.ROOT}/{producer.id}/{id}.transcript.txt`
		if not fs.isDir(`{results.ROOT}/{producer.id}`) then
			fs.writeDir(`{results.ROOT}/{producer.id}`)
		end
		fs.writeFile(transcriptPath, stripAnsi(stdout))
		payload.transcript = transcriptPath
	end

	local status = if result.ok and complete then "PASS" else "FAIL"
	local record: results.Record = {
		schema = "facet-producer-result/1",
		producer = producer.id,
		identity = id,
		environmentClass = producer.environmentClass,
		command = producer.command,
		startedAt = startedAt,
		durationMs = elapsed,
		exitCode = result.code,
		status = status,
		complete = complete,
		payload = payload,
	}
	if status == "PASS" and producer.id == "suite" then
		local refusal = results.suiteRefusal(record)
		if refusal ~= nil then
			status = "FAIL"
			record.status = "FAIL"
			base.reason = refusal
		end
	end
	base.status = status
	base.record = record
	-- A FAILED producer is reported, never stored: rerunning it is how a
	-- producer that failed for an environmental reason stops failing.
	if status == "PASS" then
		results.write(record)
	end
	return base
end

--[[ Run a list of producers, deterministic ones in parallel and the serialized
	ones strictly alone. Returns outcomes keyed by producer id. ]]
function runner.executeAll(producers: { identity.Producer }, ctx: Context, jobs: number): { [string]: Outcome }
	local outcomes: { [string]: Outcome } = {}
	local parallel: { identity.Producer } = {}
	local serial: { identity.Producer } = {}
	for _, p in producers do
		if p.serialize then
			table.insert(serial, p)
		else
			table.insert(parallel, p)
		end
	end

	local index = 1
	local active = 0
	local finished = 0
	while finished < #parallel do
		while active < jobs and index <= #parallel do
			local p = parallel[index]
			index += 1
			active += 1
			task.spawn(function()
				local ok, outcome = pcall(runner.execute, p, ctx)
				if ok then
					outcomes[p.id] = outcome
				else
					outcomes[p.id] = {
						producer = p.id,
						identity = "unknown",
						status = "FAIL",
						reused = false,
						reason = `the coordinator failed to run it: {tostring(outcome)}`,
						durationMs = 0,
						exitCode = 1,
						environmentClass = p.environmentClass,
						command = p.command,
					}
				end
				active -= 1
				finished += 1
			end)
		end
		task.wait(0.02)
	end

	--[[ ...and only now the ones that run alone, in DEPENDENCY ORDER — with the
		machine given a chance to go quiet first where the answer depends on it.

		The settle is prior_gates.sh's, narrowed to the producers that can
		actually answer differently on a busy machine (class `perf`) instead of
		charged to all thirty-three gates.

		The ordering matters for a measured reason: two of these reach the suite
		through its old front door on purpose, and run before it they each start
		a suite of their own (351 s and 333 s in one run that had already spent
		285 s running it once). Declared dependencies, satisfied first, turn both
		into a read of the recorded transcript. ]]
	local ordered: { identity.Producer } = {}
	local placed: { [string]: boolean } = {}
	local function place(p: identity.Producer, depth: number)
		if placed[p.id] or depth > 8 then
			return
		end
		placed[p.id] = true
		for _, dep in p.dependsOn or {} do
			for _, other in serial do
				if other.id == dep then
					place(other, depth + 1)
				end
			end
		end
		table.insert(ordered, p)
	end
	for _, p in serial do
		local blocked = false
		for _, dep in p.dependsOn or {} do
			for _, other in serial do
				if other.id == dep then
					blocked = true
				end
			end
		end
		if not blocked then
			place(p, 0)
		end
	end
	for _, p in serial do
		place(p, 0)
	end

	for _, p in ordered do
		if p.environmentClass == "perf" then
			runner.settle()
		end
		outcomes[p.id] = runner.execute(p, ctx)
	end
	return outcomes
end

--[[ Wait for the one-minute load average to fall, capped so a genuinely busy
	machine still finishes. Measured cause: `phase-3-pilot` failed in-batch 2/2
	and passed standalone 2/2 with nothing in the tree changed, because
	tools/bench.sh was measuring the previous gate's tail. It is a mitigation,
	not a fix, and it is now paid ONLY before a perf-class producer. ]]
function runner.settle()
	local maxWait = tonumber(process.env.FACET_VERIFY_SETTLE_MAX or "") or 45
	local threshold = tonumber(process.env.FACET_VERIFY_SETTLE_LOAD or "") or 2
	local waited = 0
	while waited < maxWait do
		local probe =
			process.exec("bash", { "-c", "uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ','" })
		local load = tonumber(string.match(probe.stdout or "", "[%d%.]+") or "") or 0
		if load < threshold then
			return
		end
		task.wait(3)
		waited += 3
	end
	print(`  verify: load did not settle within {maxWait}s — measuring anyway (recorded)`)
end

function runner.traceLines(): { string }
	return traceLines
end

return runner
