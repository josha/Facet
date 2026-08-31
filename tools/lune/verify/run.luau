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

--[[ Seeded ONCE, before anything runs, from whatever the file already holds, so
	the trace accumulates across runs without any writer ever having to read it
	back mid-flight. ]]
local traceLines: { string } = {}
local traceSeeded = false

local function seedTrace()
	if traceSeeded then
		return
	end
	traceSeeded = true
	if not fs.isFile(runner.TRACE) then
		return
	end
	for line in string.gmatch(fs.readFile(runner.TRACE), "[^\n]+") do
		table.insert(traceLines, line)
	end
end

local function trace(runId: string, producer: identity.Producer, id: string, action: string)
	local line = util.canonicalJson({
		runId = runId,
		at = nowIso(),
		producer = producer.id,
		identity = id,
		environmentClass = producer.environmentClass,
		action = action,
	})
	seedTrace()
	table.insert(traceLines, line)
	--[[ Written as it happens, so a killed run still leaves its trace behind —
		but as a WHOLE FILE by atomic rename, never read-modify-write. The first
		version read the file and appended to what it read, and Lune's file I/O
		yields: three parallel producers tracing at once interleaved a read
		against another's write and left a truncated line in the middle of the
		file. Found by a JSON decoder, on the file whose whole job is to be the
		record nobody has to trust. ]]
	local staging = `{runner.TRACE}.{math.random(1, 1e9)}.tmp`
	fs.writeFile(staging, table.concat(traceLines, "\n") .. "\n")
	fs.move(staging, runner.TRACE, { overwrite = true })
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

runner.declaredProducers = {} :: { { producer: string, class: string, files: number } }

--[[ Are the files a declared-evidence producer reads still on disk? One absent
	file is enough: a checker handed half its evidence answers a different
	question from the one its receipt recorded. ]]
local ARCHIVAL_ROOTS = { "artifacts/", "docs/plans/", "docs/handoff/", "docs/research/", ".superpowers/" }
-- …EXCEPT THE STORE ITSELF (finding 28). `artifacts/verify/` is this run's own
-- workspace, git-ignored and rebuilt every time. Counting it as archival made a
-- producer's evidence look present or absent depending on whether the LAST run
-- had left files behind.
local ARCHIVAL_EXCEPTIONS = { "artifacts/verify/", "artifacts/suite_cache/" }

local function isArchival(path: string): boolean
	for _, exception in ARCHIVAL_EXCEPTIONS do
		if string.sub(path, 1, #exception) == exception then
			return false
		end
	end
	for _, root in ARCHIVAL_ROOTS do
		if string.sub(path, 1, #root) == root then
			return true
		end
	end
	return path == "ui_todo.md"
end

--[[ …AND THE RECEIPT'S OWN FILE LIST IS PART OF THE ANSWER. A glob whose root
	directory survives says "present" even when the specific files the checker
	reads have been archived out from under it: `artifacts/<stage>/**` is still a
	directory long after the roll-up inside it has gone. So the receipt, which
	names those files one by one, is consulted too. ]]
local function receiptFilesPresent(pid: string): boolean
	local path = `tools/lune/verify/evidence/producer--{pid}.json`
	if not fs.isFile(path) then
		return true
	end
	local ok, decoded = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	if not ok or type(decoded) ~= "table" then
		return true
	end
	for _, item in ((decoded :: any).evidence or {}) do
		local p = item.archivedPath
		if p ~= nil and not fs.isFile(p) then
			return false
		end
	end
	return true
end

local function evidencePresent(producer: identity.Producer): boolean
	if not receiptFilesPresent(producer.id) then
		return false
	end
	local declared = 0
	local function consider(path: string): boolean
		if not isArchival(path) then
			return true
		end
		declared += 1
		local star = string.find(path, "*", 1, true)
		if star ~= nil then
			-- A GLOB IS PRESENT WHEN THE TREE IT WALKS IS. Skipping globs
			-- entirely left every producer whose only archival input is a `**`
			-- with nothing to count, so it degraded to its receipt while the
			-- evidence was still sitting on disk: 21 producers served a recorded
			-- verdict they could have re-earned. Measured 2026-08-30.
			local root = string.gsub(string.sub(path, 1, star - 1), "/+$", "")
			return root == "" or fs.isDir(root)
		end
		return fs.isFile(path) or fs.isDir(path)
	end
	for _, path in producer.fixtures or {} do
		if not consider(path) then
			return false
		end
	end
	for _, path in producer.inputs do
		if not consider(path) then
			return false
		end
	end
	-- NOTHING ARCHIVAL DECLARED MEANS NOTHING CAN BE MISSING, so it runs. The
	-- inverse — treating an empty declaration as "the subject is gone" — served a
	-- recorded verdict for seven producers whose evidence was never in a tree
	-- this knows how to miss. Fail towards running.
	return true
end

local function readProducerReceipt(pid: string): any
	local path = `tools/lune/verify/evidence/producer--{pid}.json`
	if not fs.isFile(path) then
		return nil
	end
	local ok, decoded = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	if not ok or type(decoded) ~= "table" or (decoded :: any).schema ~= "facet-producer-receipt/1" then
		return nil
	end
	return decoded
end

export type ReceiptStanding = { verified: number, declared: number, mismatched: { string } }

local ARCHIVE_ROOT = "../Facet-private-archive"

--[[ WHAT A PRODUCER RECEIPT IS WORTH (finding 4, 2026-08-31).

	It used to be trusted on its schema and its recorded verdict alone, which
	made it the "checked-in old PASS" the plan refuses: the hashes it carried
	were decoration. Every listed file is now hashed and compared.

	AND THE ARCHIVED FILE IS HASHED, NOT THE MANIFEST'S OPINION OF IT. Reading
	the digest out of `MANIFEST.json` proves only that the manifest still says
	what it said; hashing `../Facet-private-archive/<path>` proves the bytes are
	there and unchanged. The manifest's own integrity is a separate producer
	(`archive-integrity`), which is where that claim belongs. ]]
local function receiptStanding(receipt: any): ReceiptStanding
	local standing: ReceiptStanding = { verified = 0, declared = 0, mismatched = {} }
	for _, item in receipt.evidence or {} do
		local candidates = {}
		if item.archivedPath ~= nil then
			table.insert(candidates, item.archivedPath)
			table.insert(candidates, `{ARCHIVE_ROOT}/{item.archivedPath}`)
		end
		local hashed: string? = nil
		for _, candidate in candidates do
			if fs.isFile(candidate) then
				hashed = util.sha256(fs.readFile(candidate))
				break
			end
		end
		if hashed == nil then
			standing.declared += 1
		elseif hashed ~= item.sha256 then
			table.insert(standing.mismatched, `{item.label} no longer hashes to what was recorded`)
		else
			standing.verified += 1
		end
	end
	return standing
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

	--[[ A DECLARED-EVIDENCE PRODUCER WHOSE SUBJECT HAS BEEN ARCHIVED.
		Its whole input is the stage record. While the record is on disk it runs
		like anything else; once the director archives it, it serves the receipt
		the converter took — the verdict AND the sha256 of every file it read —
		verified against the private archive's manifest when that archive is
		beside the checkout, and reported separately when it is not. A recorded
		PASS on its own would be exactly the "checked-in old PASS" the plan
		refuses; a recorded PASS beside the hashes of what produced it is the
		same declared-evidence contract Studio and device results have always
		had. ]]
	if (producer :: any).declaredEvidence and not evidencePresent(producer) then
		local receipt = readProducerReceipt(producer.id)
		if receipt == nil then
			base.status = "SKIP_MISSING"
			base.reason = "its evidence is archived and it has no receipt"
			trace(ctx.runId, producer, id, "skip-missing")
			return base
		end
		if receipt.verdict ~= "PASS" then
			base.status = "FAIL"
			base.reason = `its recorded verdict was {tostring(receipt.verdict)}`
			trace(ctx.runId, producer, id, "declared")
			return base
		end
		if type(receipt.evidence) ~= "table" or #receipt.evidence == 0 then
			base.status = "SKIP_MISSING"
			base.reason = "its receipt lists no evidence at all"
			trace(ctx.runId, producer, id, "skip-missing")
			return base
		end
		local standing = receiptStanding(receipt)
		if #standing.mismatched > 0 then
			base.status = "FAIL"
			base.reason = `recorded evidence changed after it was recorded: {table.concat(standing.mismatched, "; ")}`
			trace(ctx.runId, producer, id, "declared")
			return base
		end
		if standing.verified == 0 then
			base.status = "SKIP_MISSING"
			base.reason =
				`none of its {standing.declared} recorded file(s) is reachable, on disk or in an archive beside this checkout`
			trace(ctx.runId, producer, id, "skip-missing")
			return base
		end
		base.reused = true
		base.reason =
			`declared evidence: {standing.verified} of {#receipt.evidence} archived file(s) hash to what was recorded ({receipt.recordedAt})`
		-- …AND IT CARRIES A RECORD. A reader asks for the producer's RESULT, not
		-- for its outcome line: without one the row sees "no result" and reports
		-- the producer as failed, which is how a declared PASS reads as a red.
		base.record = {
			schema = "facet-producer-result/1",
			producer = producer.id,
			identity = id,
			environmentClass = producer.environmentClass,
			command = producer.command,
			startedAt = receipt.recordedAt,
			durationMs = 0,
			exitCode = 0,
			status = "PASS",
			complete = true,
			payload = {
				toolchain = identity.toolchainString(ctx.toolchain),
				declaredEvidence = receipt,
				stdoutTail = `declared evidence receipt recorded {receipt.recordedAt}`,
				stderrTail = "",
			},
		}
		table.insert(
			runner.declaredProducers,
			{ producer = producer.id, class = receipt.class, files = #receipt.evidence }
		)
		trace(ctx.runId, producer, id, "declared")
		return base
	end

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

	--[[ THE SETTLE IS PAID ONLY BY A PRODUCER THAT IS ABOUT TO RUN. Waiting for
		a quiet machine in front of a REUSED perf result costs forty-five seconds
		and buys nothing: measured 502 s for a warm release run whose producers
		did 62 s of work between them. It belongs after the reuse decision, not
		before it. ]]
	if producer.environmentClass == "perf" then
		runner.settle()
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

	--[[ THE WHOLE OUTPUT IS KEPT, NOT A TAIL (finding 25). A row that pins a
		sentence in a producer's report was grepping the last 4,000 characters,
		so a pin on anything a chatty checker said early silently could not
		match. The tails stay for the report, which wants a snippet; the pins
		read the file. ]]
	local outDir = `{results.ROOT}/{producer.id}`
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end
	local stdoutPath = `{outDir}/{id}.stdout.txt`
	fs.writeFile(stdoutPath, stripAnsi(stdout) .. "\n" .. stripAnsi(stderr))
	local payload: { [string]: any } = {
		toolchain = identity.toolchainString(ctx.toolchain),
		stdout = stdoutPath,
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
	--[[ A FAILING PRODUCER SAYS WHAT HAPPENED (finding 16). The reason field
		still held "no stored result for this identity" — the reason it RAN, not
		the reason it failed — so every failure read as a cache miss. ]]
	if status == "FAIL" then
		local lastLine = ""
		for line in string.gmatch(stripAnsi(stderr) .. "\n" .. stripAnsi(stdout), "[^\n]+") do
			if string.match(line, "%S") ~= nil then
				lastLine = line
			end
		end
		base.reason = `exited {result.code}: {string.sub(lastLine, -220)}`
	end
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

	--[[ WARM THE LEGACY FRONT DOOR BEFORE ANYTHING ELSE RUNS ALONE.

		`tools/suite_cache_selftest.sh` proves the transcript cache can refuse a
		stale, red, truncated or fast-tier entry, and to do that honestly it needs
		a real cached run to start from — so on a cold cache it runs the suite
		itself. Measured: 280 s inside a run that had ALREADY spent 285 s running
		the same suite. One call to the legacy front door here, served out of the
		result store this run just filled, turns that into a cache read. The
		selftest's assertions are untouched; only its starting condition is.

		This goes away with the manifest. ]]
	local suiteOutcome = outcomes["suite"]
	if suiteOutcome ~= nil and suiteOutcome.status == "PASS" then
		process.exec("bash", { "-c", "tools/test.sh --ensure-cache >/dev/null 2>&1 || true" })
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
		outcomes[p.id] = runner.execute(p, ctx)
	end
	return outcomes
end

--[[ Wait for the one-minute load average to fall, capped so a genuinely busy
	machine still finishes. Measured cause: `phase-3-pilot` failed in-batch 2/2
	and passed standalone 2/2 with nothing in the tree changed, because
	tools/bench.sh was measuring the previous gate's tail. It is a mitigation,
	not a fix, and it is now paid ONLY before a perf-class producer. ]]

function runner.traceLines(): { string }
	return traceLines
end

return runner
