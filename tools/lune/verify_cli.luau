--!strict
--[[ THE ONE COORDINATOR (distribution-readiness D7/D8/D9).

	    tools/verify.sh {affected|fast|full|release} [--gate <phase>] [--explain]
	                    [--rerun <producerId>] [--jobs N]

	Verification is a directed acyclic graph, not a list of shell lines. This
	executes each unique producer AT MOST ONCE for an exact input identity, then
	evaluates every applicable gate row from that run's structured results.

	WHAT THIS REPLACES.

	  * 233 rows that each spent a cached suite transcript and grepped it for one
	    sentence. They are now case-id lookups against one structured result, so a
	    renamed case moves an id (loud) instead of breaking an unrelated gate
	    (silent), and the suite runs once.
	  * 16 `prior-gates-unregressed` rows that re-ran every earlier gate, which
	    re-ran every gate before THAT. Prior-phase regression is now what it always
	    meant: every earlier phase's rows, evaluated from this run.
	  * 266 scanner invocations of 124 distinct commands, many byte-identical.
	    Each distinct command is one producer.

	WHAT IT DOES NOT CHANGE. Every phase in phases.json is still a view;
	`artifacts/<phase>/gate.json` is still written in the `facet-gate/1` shape;
	every assertion, negative control and evidence pin survives — the conversion
	census at artifacts/distribution-readiness/verification/graph-census.md maps
	each one. ]]

local datetime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local graphMod = require("./verify/graph")
local identity = require("./verify/identity")
local report = require("./verify/report")
local results = require("./verify/results")
local runner = require("./verify/run")
local util = require("./verify/util")

local TIERS = { affected = true, fast = true, full = true, release = true }

-- ---- arguments --------------------------------------------------------------

local tier = "full"
local gatePhase: string? = nil
local explain = false
local rerun: { [string]: boolean } = {}
local jobs: number? = nil

do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if TIERS[a] then
			tier = a
		elseif a == "--gate" then
			i += 1
			gatePhase = args[i]
		elseif a == "--explain" then
			explain = true
		elseif a == "--rerun" then
			i += 1
			rerun[args[i]] = true
		elseif a == "--jobs" then
			i += 1
			jobs = tonumber(args[i])
		else
			print(`verify: unknown argument '{a}'`)
			process.exit(2)
		end
		i += 1
	end
end

-- Cap concurrency from measured machine capacity, as the binding plan requires:
-- faster scheduling must not create flaky timing results.
if jobs == nil then
	local cores = 4
	local probe = process.exec("sysctl", { "-n", "hw.ncpu" })
	if probe.ok then
		cores = tonumber(string.match(probe.stdout, "%d+") or "4") or 4
	end
	jobs = math.max(1, math.min(4, math.floor(cores / 4)))
end

local g = graphMod.load()
local producerIndex = graphMod.producerById(g)

if gatePhase ~= nil then
	local known = false
	for _, p in graphMod.phaseIds(g) do
		if p == gatePhase then
			known = true
		end
	end
	if not known then
		print(`verify: unknown phase '{gatePhase}'`)
		process.exit(2)
	end
end

-- ---- which producers run ----------------------------------------------------

local selected: { [string]: string } = {} -- producer id -> why

local function select(id: string, why: string)
	if producerIndex[id] ~= nil and selected[id] == nil then
		selected[id] = why
	end
end

local changedPaths: { string } = {}
local changedSpecs: { string } = {}

if tier == "affected" then
	local diff = process.exec("bash", {
		"-c",
		"git diff --name-only HEAD; git ls-files --others --exclude-standard",
	})
	for line in string.gmatch(diff.stdout or "", "[^\n]+") do
		local path = string.gsub(line, "%s+$", "")
		if path ~= "" then
			table.insert(changedPaths, path)
			local spec = string.match(path, "^tests/(.+)%.luau$")
			if spec ~= nil and (string.match(spec, "%.spec$") or string.match(spec, "_spec$")) then
				table.insert(changedSpecs, (string.gsub(spec, "%.spec$", "")))
			end
		end
	end
	for _, p in g.producers do
		if p.id == "suite" or p.id == "suite-fast" then
			continue
		end
		if not (p.tiers :: any).full then
			continue
		end
		for _, path in changedPaths do
			if util.matchesAny(path, p.inputs) then
				select(p.id, `an input matched a changed path ({path})`)
				break
			end
		end
	end
	if #changedPaths == 0 then
		print("verify: no changed paths against HEAD — nothing is affected")
	end
elseif gatePhase ~= nil then
	local rows = graphMod.rowsForPhase(g, gatePhase)
	for _, id in graphMod.producersForRows(rows) do
		select(id, `the phase '{gatePhase}' needs it`)
	end
	-- ...plus the tier's own producers, so `full --gate X` is still a full run
	-- and only `--gate X` on its own is the narrow pull.
	if tier ~= "fast" then
		for _, id in graphMod.producersForTier(g, tier) do
			select(id, `the {tier} tier runs it`)
		end
	end
else
	for _, id in graphMod.producersForTier(g, tier) do
		select(id, `the {tier} tier runs it`)
	end
end

local toRun: { identity.Producer } = {}
for id, _ in selected do
	table.insert(toRun, producerIndex[id])
end
table.sort(toRun, function(a, b)
	return a.id < b.id
end)

-- ---- run --------------------------------------------------------------------

local runId = `{os.date("!%Y%m%dT%H%M%SZ")}-{math.random(1000, 9999)}`
local startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
local wallStart = datetime.now().unixTimestampMillis
local cpuStart = os.clock()

report.banner(tier)

if not fs.isDir("artifacts/verify") then
	fs.writeDir("artifacts/verify")
end

local toolchain = identity.toolchain()
local ctx: runner.Context = {
	runId = runId,
	toolchain = toolchain,
	tier = tier,
	rerun = rerun,
}

local outcomes = runner.executeAll(toRun, ctx, jobs :: number)

-- Changed specs run alone in the affected tier. Their result is tier "one",
-- which the full/release reader refuses — that is the whole point.
local oneSpecResults: { { spec: string, ok: boolean } } = {}
if tier == "affected" then
	for _, spec in changedSpecs do
		local out = process.exec("bash", { "-c", `lune run tests/run_one {spec}` })
		table.insert(oneSpecResults, { spec = spec, ok = out.ok })
		if not out.ok then
			print(`{string.sub(out.stdout or "", -2000)}`)
		end
	end
end

-- ---- evidence ---------------------------------------------------------------

--[[ A producer's record, whether it ran in THIS run or is a stored result for
	this exact identity. A row outside the run's producer set is evaluated from
	"whatever results exist" and is NOT_EVALUATED when nothing does. ]]
local recordCache: { [string]: any } = {}
local recordMissReason: { [string]: string } = {}

local function recordFor(id: string): (any, string?)
	if recordCache[id] ~= nil then
		return recordCache[id], nil
	end
	if recordMissReason[id] ~= nil then
		return nil, recordMissReason[id]
	end
	local outcome = outcomes[id]
	if outcome ~= nil then
		if outcome.status == "PASS" and outcome.record ~= nil then
			recordCache[id] = outcome.record
			return outcome.record, nil
		end
		recordMissReason[id] = if outcome.status == "SKIP_MISSING"
			then "the producer is not present in this tree"
			else `the producer FAILED in this run ({outcome.reason})`
		return nil, recordMissReason[id]
	end
	local producer = producerIndex[id]
	if producer == nil then
		recordMissReason[id] = `unknown producer '{id}'`
		return nil, recordMissReason[id]
	end
	local computed = identity.compute(producer, toolchain)
	local record, reason = results.read(id, computed.hash, {
		requiredClass = producer.environmentClass,
		toolchain = identity.toolchainString(toolchain),
		suite = id == "suite",
	})
	if record == nil then
		recordMissReason[id] = reason or "no stored result"
		return nil, recordMissReason[id]
	end
	recordCache[id] = record
	return record, nil
end

--[[ THE PRIVATE EVIDENCE ARCHIVE, when it is beside this checkout.

	Recorded evidence — a Studio drive, a device or performance capture, an
	engine-feasibility probe — is pinned by content hash in a RECEIPT rather than
	by a raw path and a literal grep, because a hash is the stronger pin and
	because the path may name a stage this library does not want to publish. The
	receipt is verified against the file on disk when it is still there, and
	against the archive's own manifest when the archive is present. When neither
	is available the receipt stands as DECLARED evidence and is reported
	separately, which is what the plan requires of every evidence class a
	headless run cannot re-take. ]]
local archiveDigests: { [string]: string } = {}
local archivePresent = false
do
	local manifest = "../Facet-private-archive/MANIFEST.json"
	if fs.isFile(manifest) then
		local ok, decoded = pcall(function()
			return serde.decode("json", fs.readFile(manifest))
		end)
		if ok and type(decoded) == "table" and type((decoded :: any).files) == "table" then
			archivePresent = true
			for _, entry in (decoded :: any).files do
				archiveDigests[entry.path] = entry.sha256
			end
		end
	end
end

local declaredEvidenceRows: { { row: string, class: string, items: number } } = {}

local function checkReceipt(row: graphMod.Row): (string, string)
	local path = (row.check :: any).receipt
	if not fs.isFile(path) then
		return "FAIL_RECOVERABLE", `evidence receipt {path} is missing`
	end
	local ok, receipt = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	if not ok or type(receipt) ~= "table" then
		return "FAIL_RECOVERABLE", `evidence receipt {path} is not readable JSON`
	end
	local r = receipt :: any
	if r.schema ~= "facet-evidence-receipt/1" then
		return "FAIL_RECOVERABLE", `evidence receipt has schema '{tostring(r.schema)}'`
	end
	if r.row ~= row.id then
		return "FAIL_RECOVERABLE", "evidence receipt names a different row than the one holding it"
	end
	local declared = 0
	local mismatched: { string } = {}
	for _, item in r.evidence do
		local verified = false
		if item.archivedPath ~= nil and fs.isFile(item.archivedPath) then
			local digest = util.sha256(fs.readFile(item.archivedPath))
			verified = true
			if digest ~= item.sha256 then
				table.insert(mismatched, `{item.label} no longer hashes to what was recorded`)
			end
		end
		if not verified and archivePresent and item.archivedPath ~= nil then
			local archived = archiveDigests[item.archivedPath]
			if archived ~= nil then
				verified = true
				if archived ~= item.sha256 then
					table.insert(mismatched, `{item.label} disagrees with the archive's manifest`)
				end
			end
		end
		if not verified then
			declared += 1
		end
	end
	if #mismatched > 0 then
		return "FAIL_RECOVERABLE",
			`recorded evidence changed after it was recorded:\n  {table.concat(mismatched, "\n  ")}`
	end
	if declared > 0 then
		table.insert(declaredEvidenceRows, { row = row.id, class = r.class, items = declared })
	end
	return "PASS", `{#r.evidence} recorded {r.class} file(s) still hash to what was recorded`
end

local suiteCases: { [string]: string }? = nil
local suiteTranscript: string? = nil
local rrTranscript: string? = nil
do
	local record = recordFor("suite")
	if record ~= nil then
		suiteCases = results.caseIndex(record.payload.results)
		suiteTranscript = record.payload.transcript
		--[[ THE PARITY-PERIOD BRIDGE. Two rows assert that a sweep leaves the
			legacy transcript cache WARM (`tools/test.sh --status` = hit) — the
			D0 sweep-economy claim, which is still true and still worth
			asserting. The graph runs `./run-tests.sh` directly, so nothing
			would populate that cache; one call to the legacy front door does,
			and it is served FROM this store rather than by a second suite run.
			It goes when the manifest does. ]]
		process.exec("bash", { "-c", "tools/test.sh --ensure-cache >/dev/null 2>&1 || true" })
	end
	local rr = recordFor("rascalrally-suite")
	if rr ~= nil then
		rrTranscript = rr.payload.transcript
	end
end

-- ---- evaluate rows ----------------------------------------------------------

export type RowResult = {
	id: string,
	phase: string,
	name: string,
	state: string,
	detail: string,
	requirements: { string },
	evidence: string?,
	releaseBlocking: boolean,
}

local rowResults: { RowResult } = {}
local rowByPhase: { [string]: { RowResult } } = {}
local failures: { report.Failure } = {}

--[[ THE ROW'S SHELL IS PASSED AS AN ARGUMENT, NEVER INTERPOLATED.

	The first version wrapped it as `bash -c "<quoted>"` inside another
	`bash -c`, and the OUTER shell expanded every `$f` before the inner one ever
	saw the assignment — so `f=artifacts/… && test -f "$f"` became `test -f ''`
	and fifty rows failed for a reason that had nothing to do with them.
	Measured 2026-08-30. One shell, one expansion. ]]
--[[ ...AND THE PATHS IN IT ARE ABSOLUTE. Several converted rows `cd` into the
	sibling game checkout before grepping the recorded transcript, and a path
	relative to the library root does not survive that: `grep … "$VAR"` found
	nothing and thirteen rows failed for a reason that had nothing to do with
	them. Measured 2026-08-30. ]]
local function absolute(path: string): string
	if string.sub(path, 1, 1) == "/" then
		return path
	end
	return `{process.cwd}/{path}`
end

local function shellEnv(): { [string]: string }
	local env: { [string]: string } = {}
	if suiteTranscript ~= nil then
		env.FACET_VERIFY_SUITE_TRANSCRIPT = absolute(suiteTranscript)
	end
	if rrTranscript ~= nil then
		env.FACET_VERIFY_RR_TRANSCRIPT = absolute(rrTranscript)
	end
	return env
end

local function isEmptyCheck(check: graphMod.Check): boolean
	return check.producers == nil
		and check.resultIds == nil
		and check.stdoutPins == nil
		and check.shell == nil
		and (check :: any).receipt == nil
		and check.priorPhases ~= true
end

local function evaluate(row: graphMod.Row): (string, string)
	if row.state ~= nil then
		--[[ A DECLARED STATE MAY NOT BE `PASS`. A literal state in the graph is
			for work that has not landed (PENDING), for a capability that is gone
			(FAIL_OPTIONAL), for something externally blocked (FAIL_ENVIRONMENT)
			or for a row whose subject left the tree (RETIRED). A row that simply
			SAYS it passes, with no producer, no case id, no receipt and no
			assertion behind it, is the purest form of a check that cannot fail —
			and flipping one is the cheapest way to fake a gate. ]]
		if row.state == "PASS" and isEmptyCheck(row.check) then
			return "FAIL_RECOVERABLE",
				"this row declares PASS with no producer, case id, receipt or assertion behind it"
		end
		return row.state, if row.class == "retired" then (row.retiredReason or "retired") else row.note
	end
	if row.check.priorPhases then
		return "DEFERRED", "evaluated after every other row"
	end

	for _, id in row.check.producers or {} do
		local record, reason = recordFor(id)
		if record == nil then
			local producer = producerIndex[id]
			if producer ~= nil and outcomes[id] ~= nil and outcomes[id].status == "SKIP_MISSING" then
				return "FAIL_ENVIRONMENT", `producer '{id}' is not available in this tree`
			end
			if producer ~= nil and outcomes[id] == nil then
				return "NOT_EVALUATED", `producer '{id}' did not run in this tier: {reason}`
			end
			return "FAIL_RECOVERABLE", `producer '{id}': {reason}`
		end
	end

	if row.check.resultIds ~= nil then
		if suiteCases == nil then
			return "NOT_EVALUATED", `no usable suite result: {recordMissReason["suite"] or "not run"}`
		end
		local missing: { string } = {}
		local failed: { string } = {}
		for _, id in row.check.resultIds do
			local status = (suiteCases :: any)[id]
			if status == nil then
				table.insert(missing, id)
			elseif status ~= "pass" then
				table.insert(failed, id)
			end
		end
		if #missing > 0 then
			return "FAIL_RECOVERABLE",
				`{#missing} case id(s) no longer exist in the suite (a renamed or deleted case):\n  {table.concat(
					missing,
					"\n  "
				)}`
		end
		if #failed > 0 then
			return "FAIL_RECOVERABLE", `{#failed} case(s) failed:\n  {table.concat(failed, "\n  ")}`
		end
	end

	for _, pin in row.check.stdoutPins or {} do
		local record = recordFor(pin.producer)
		if record == nil then
			return "NOT_EVALUATED", `producer '{pin.producer}' has no result to pin against`
		end
		local text = (record.payload.stdoutTail or "") .. (record.payload.stderrTail or "")
		local probe = process.exec("bash", {
			"-c",
			`printf '%s' "$FACET_VERIFY_PIN_TEXT" | grep {pin.flags} {pin.pattern}`,
		}, { env = { FACET_VERIFY_PIN_TEXT = text } })
		if not probe.ok then
			return "FAIL_RECOVERABLE", `producer '{pin.producer}' output does not carry {pin.pattern}`
		end
	end

	if (row.check :: any).receipt ~= nil then
		local state, detail = checkReceipt(row)
		if state ~= "PASS" then
			return state, detail
		end
	end

	if row.check.shell ~= nil then
		local env = shellEnv()
		local out = process.exec("bash", { "-c", row.check.shell }, { env = env })
		if not out.ok then
			local traced = process.exec("bash", { "-xc", row.check.shell }, { env = env })
			local lines: { string } = {}
			for line in string.gmatch((traced.stderr or ""), "[^\n]+") do
				if string.sub(line, 1, 1) == "+" then
					table.insert(lines, line)
				end
			end
			local tail = ""
			if #lines > 0 then
				tail = `\n[shell trace from a diagnostic re-run; the LAST line is the one that failed]\n{lines[math.max(
					1,
					#lines - 6
				)]}`
				for i = math.max(1, #lines - 5), #lines do
					tail ..= `\n{lines[i]}`
				end
			end
			return "FAIL_RECOVERABLE", `residual assertion failed{tail}`
		end
	end

	if row.evidence ~= nil and not fs.isFile(row.evidence) then
		return "FAIL_RECOVERABLE", `missing evidence artifact {row.evidence}`
	end

	return "PASS", row.note
end

for _, phase in graphMod.phaseIds(g) do
	rowByPhase[phase] = {}
end
for _, row in g.rows do
	local state, detail = evaluate(row)
	local rr: RowResult = {
		id = row.id,
		phase = row.phase,
		name = row.name,
		state = state,
		detail = detail,
		requirements = row.requirements,
		evidence = row.evidence,
		releaseBlocking = row.releaseBlocking,
	}
	table.insert(rowResults, rr)
	table.insert(rowByPhase[row.phase], rr)
end

--[[ prior-gates, re-derived rather than replayed. `prior-gates-unregressed` in
	phase P asked "does every gate before P still pass?" and answered it by
	RUNNING them all again, recursively. Every one of those rows is already
	evaluated in this same run, so the question is now a lookup. ]]
local phaseIndex: { [string]: number } = {}
for i, phase in graphMod.phaseIds(g) do
	phaseIndex[phase] = i
end
for _, rr in rowResults do
	if rr.state ~= "DEFERRED" then
		continue
	end
	local mine = phaseIndex[rr.phase]
	local regressed: { string } = {}
	local unevaluated = 0
	for _, other in rowResults do
		if other.state == "DEFERRED" or phaseIndex[other.phase] >= mine then
			continue
		end
		if other.state == "NOT_EVALUATED" then
			unevaluated += 1
		elseif not graphMod.statePasses(other.state, other.releaseBlocking) then
			table.insert(regressed, `{other.phase} :: {other.name} [{other.state}]`)
		end
	end
	if #regressed > 0 then
		rr.state = "FAIL_RECOVERABLE"
		rr.detail = `{#regressed} earlier row(s) do not pass in this run:\n  {table.concat(regressed, "\n  ")}`
	elseif unevaluated > 0 then
		rr.state = "NOT_EVALUATED"
		rr.detail = `{unevaluated} earlier row(s) could not be evaluated in this tier`
	else
		rr.state = "PASS"
		rr.detail = "every row of every earlier phase passes in this run"
	end
end

-- ---- phase verdicts + legacy gate.json --------------------------------------

--[[ THE PHASE VIEW'S OWN RECORD, out of the graph rather than phases.json.
	A phase id is a PUBLIC name — it is the argument to tools/gate.sh and the
	directory the compat gate.json is written into — so the graph carries the
	neutral id and the paths derived from it. graph-census.md records what each
	one was called before. ]]
local phaseInfo = graphMod.phaseById(g)

local phaseStates: { { phase: string, status: string, counts: { [string]: number } } } = {}
local overallRowsPass = true

for _, phase in graphMod.phaseIds(g) do
	local rows = rowByPhase[phase]
	local counts: { [string]: number } = {}
	local worst = "PASS"
	local pass = true
	local anyUnevaluated = false
	local requirementSet: { [string]: boolean } = {}
	local checks: { any } = {}
	for _, rr in rows do
		counts[rr.state] = (counts[rr.state] or 0) + 1
		if rr.state == "NOT_EVALUATED" then
			anyUnevaluated = true
		elseif not graphMod.statePasses(rr.state, rr.releaseBlocking) then
			pass = false
		end
		if graphMod.severity(rr.state) > graphMod.severity(worst) and rr.state ~= "NOT_EVALUATED" then
			worst = rr.state
		end
		for _, req in rr.requirements do
			requirementSet[req] = true
		end
		table.insert(checks, {
			name = rr.name,
			state = rr.state,
			requirements = rr.requirements,
			evidence = rr.evidence,
			releaseBlocking = rr.releaseBlocking,
			detail = rr.detail,
		})
	end
	local status = if anyUnevaluated then "NOT_EVALUATED" elseif pass then "PASS" else worst
	table.insert(phaseStates, { phase = phase, status = status, counts = counts })
	if not anyUnevaluated and not pass then
		overallRowsPass = false
	end
	-- A phase whose rows could not all be judged does NOT get a gate.json: a
	-- stale-but-honest artifact beats a fresh-but-partial one.
	if not anyUnevaluated then
		local info = phaseInfo[phase]
		local requirements: { string } = {}
		for req in requirementSet do
			table.insert(requirements, req)
		end
		table.sort(requirements)
		if not fs.isDir(info.artifactDir) then
			fs.writeDir(info.artifactDir)
		end
		fs.writeFile(
			info.gateArtifact,
			serde.encode("json", {
				schema = "facet-gate/1",
				gate = phase,
				status = status,
				requirements = requirements,
				checks = checks,
				next = if status == "PASS" then info.next else phase,
			}, true)
		)
	end
end

-- ---- report -----------------------------------------------------------------

local producerLines: { report.ProducerLine } = {}
local producersPass = true
for id, outcome in outcomes do
	table.insert(producerLines, {
		id = id,
		environmentClass = outcome.environmentClass,
		status = outcome.status,
		reused = outcome.reused,
		reason = outcome.reason,
		durationMs = outcome.durationMs,
		selectedBecause = selected[id] or "",
	})
	if outcome.status == "FAIL" then
		producersPass = false
		table.insert(failures, {
			kind = "producer",
			subject = id,
			detail = string.sub(
				((outcome.record and outcome.record.payload.stdoutTail) or "")
					.. ((outcome.record and outcome.record.payload.stderrTail) or ""),
				-1200
			),
			rerun = `tools/verify.sh {tier} --rerun {id}`,
		})
	elseif outcome.status == "SKIP_MISSING" and tier == "release" then
		producersPass = false
		table.insert(failures, {
			kind = "producer missing",
			subject = id,
			detail = outcome.reason,
			rerun = `(release requires it) {outcome.command}`,
		})
	end
end

report.producers(producerLines, explain)
report.slowest(producerLines)

for _, rr in rowResults do
	if rr.state == "FAIL_RECOVERABLE" or rr.state == "BLOCKED_CRITICAL" then
		local rerunCmd = `tools/verify.sh full --gate {rr.phase}`
		local spec = string.match(rr.detail, "\n  ([%w_/]+)::")
		if spec ~= nil then
			rerunCmd = `lune run tests/run_one {spec}`
		end
		table.insert(failures, {
			kind = "row",
			subject = rr.id,
			detail = rr.detail,
			rerun = rerunCmd,
		})
	end
end

report.phases(phaseStates)
if #declaredEvidenceRows > 0 then
	print("\27[1mRecorded evidence, reported separately\27[0m")
	print(
		`  \27[2m{#declaredEvidenceRows} row(s) stand on declared Studio/device/performance receipts whose files are neither on disk nor in a private archive beside this checkout.\27[0m`
	)
	for _, d in declaredEvidenceRows do
		print(`  \27[2m- {d.row} ({d.class}, {d.items} declared file(s))\27[0m`)
	end
	print("")
end
report.failures(failures)

for _, one in oneSpecResults do
	print(`  {if one.ok then "✓" else "✗"} run_one {one.spec}`)
end

-- ---- run record --------------------------------------------------------------

local durationMs = datetime.now().unixTimestampMillis - wallStart
local identityParts: { string } = {}
local producerRecords: { any } = {}
for _, line in producerLines do
	local outcome = outcomes[line.id]
	table.insert(identityParts, `{line.id}={outcome.identity}`)
	table.insert(producerRecords, {
		id = line.id,
		identity = outcome.identity,
		reused = outcome.reused,
		reason = outcome.reason,
		durationMs = outcome.durationMs,
		status = outcome.status,
		environmentClass = outcome.environmentClass,
		selectedBecause = line.selectedBecause,
	})
end
table.sort(identityParts)
table.sort(producerRecords, function(a, b)
	return a.id < b.id
end)

local status = if producersPass and overallRowsPass then "PASS" else "FAIL"
if tier == "fast" or tier == "affected" then
	status = if producersPass then "PASS_PARTIAL" else "FAIL"
end

local rowRecords: { any } = {}
for _, rr in rowResults do
	table.insert(rowRecords, { id = rr.id, phase = rr.phase, state = rr.state, detail = rr.detail })
end

local runRecord = {
	schema = "facet-verify-run/1",
	tier = tier,
	gate = gatePhase,
	identity = util.sha256(table.concat(identityParts, "\n")),
	status = status,
	startedAt = startedAt,
	durationMs = durationMs,
	cpuMs = (os.clock() - cpuStart) * 1000,
	jobs = jobs,
	toolchain = identity.toolchainString(toolchain),
	producers = producerRecords,
	rows = rowRecords,
	phases = phaseStates,
}
local encoded = serde.encode("json", runRecord, true)
fs.writeFile(`artifacts/verify/run-{runId}.json`, encoded)
fs.writeFile(`artifacts/verify/latest-{tier}.json`, encoded)

print(
	string.format(
		"verify: %s  tier=%s%s  %.1fs  identity=%s",
		status,
		tier,
		if gatePhase ~= nil then ` gate=${gatePhase}` else "",
		durationMs / 1000,
		string.sub(runRecord.identity, 1, 12)
	)
)
print(`        artifacts/verify/latest-{tier}.json`)
if tier == "fast" or tier == "affected" then
	print(`        \27[33mThis is NOT full or release evidence.\27[0m`)
end
process.exit(if status == "FAIL" then 1 else 0)
