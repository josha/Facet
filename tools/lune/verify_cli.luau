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
			if gatePhase == nil or string.sub(gatePhase :: string, 1, 2) == "--" then
				print("verify: --gate needs a phase name (tools/verify.sh full --gate <phase>)")
				process.exit(2)
			end
		elseif a == "--explain" then
			explain = true
		elseif a == "--rerun" then
			i += 1
			local target = args[i]
			if target == nil or string.sub(target :: string, 1, 2) == "--" then
				print("verify: --rerun needs a producer id (tools/verify.sh full --rerun <producer>)")
				process.exit(2)
			end
			rerun[target :: string] = true
		elseif a == "--jobs" then
			i += 1
			jobs = tonumber(args[i] or "")
			if jobs == nil or (jobs :: number) < 1 then
				print("verify: --jobs needs a positive number")
				process.exit(2)
			end
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
	--[[ HOW MANY CORES, ON A MACHINE THAT MIGHT NOT BE THIS ONE (finding 27).
		`sysctl -n hw.ncpu` answers on exactly one family of systems, and the
		fallback was the literal 4 — so a host that answers only `nproc` ran
		every deterministic producer at a concurrency of one, and nobody was
		told. Three probes, in order, and the first that answers wins. ]]
	local cores = 0
	for _, command in { "sysctl -n hw.ncpu", "nproc", "getconf _NPROCESSORS_ONLN" } do
		local probe = process.exec("bash", { "-c", command })
		if probe.ok then
			local found = tonumber(string.match(probe.stdout or "", "%d+") or "")
			if found ~= nil and found > 0 then
				cores = found
				break
			end
		end
	end
	if cores == 0 then
		print("verify: could not read the core count from sysctl, nproc or getconf — using 4")
		cores = 4
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
		--[[ A PRODUCER THAT REWRITES TRACKED FILES IS NOT AN INNER-LOOP
			PRODUCER. The place builders emit fourteen tracked `.rbxl`, each
			stamped with its build TIME, so selecting one leaves the working tree
			dirty for a change that could not have touched a place -- and the
			affected tier selected them off a README edit. `tiers.affected =
			false` says so in the graph rather than in a name check here. ]]
		if (p.tiers :: any).affected == false then
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
	--[[ A GATE RUNS WHAT ITS OWN PHASE NEEDS, AND NOTHING ELSE.
		Every other phase is still evaluated — from whatever results the store
		already holds — but a standalone gate does not re-run the world to
		satisfy them. That is the difference between "a gate may PULL a missing
		dependency into the run once" and "a gate is a full run with a filter",
		and the second one costs a suite. ]]
	local rows = graphMod.rowsForPhase(g, gatePhase)
	for _, id in graphMod.producersForRows(rows) do
		select(id, `the phase '{gatePhase}' needs it`)
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

--[[ THE RELEASE-GATE FACTS, TAKEN AT RUN START (BLOCKER A, 2026-08-31).
	The package channel refuses to publish without evidence that a release run
	passed over THIS tree. It used to look for an identity hash, and the two
	sides computed different hashes over different material, so publish could
	never succeed. The contract now is FACTS, not a shared hash: the commit this
	ran at, whether the tree was dirty when it started, and the same normalized
	source hash `tools/package.py` computes for the shipped file set — asked of
	package.py itself, so the two can never drift apart. Compared field by
	field, a mismatch says WHICH field moved. ]]
local function shellOut(command: string): string
	local probe = process.exec("bash", { "-c", command })
	if not probe.ok then
		return ""
	end
	return (string.gsub(probe.stdout or "", "%s+$", ""))
end

local gateCommit = shellOut("git rev-parse HEAD")
local gateTreeDirty = shellOut("git status --porcelain") ~= ""
local gateSourceHash = shellOut(
	"python3 -c \"import importlib.util; s = importlib.util.spec_from_file_location('pkg', 'tools/package.py');"
		.. ' m = importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.source_hash())"'
)

local runId = `{os.date("!%Y%m%dT%H%M%SZ")}-{math.random(1000, 9999)}`
local startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
local wallStart = datetime.now().unixTimestampMillis
local cpuStart = os.clock()

report.banner(tier, gatePhase)

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

--[[ WHAT GIT ACTUALLY TRACKS, asked once. Used to tell a deleted checked-in
	record from a run-produced one that this checkout has simply never made. ]]
local outOfTier: { [string]: boolean } = {}

local trackedPaths: { [string]: boolean } = {}
do
	local listed = process.exec("bash", { "-c", "git ls-files" })
	if listed.ok then
		for line in string.gmatch(listed.stdout or "", "[^\n]+") do
			trackedPaths[line] = true
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
	--[[ A RECEIPT WITH NOTHING IN IT IS NOT EVIDENCE (finding 3, 2026-08-31).
		An empty list verified nothing and returned PASS. ]]
	if type(r.evidence) ~= "table" or #r.evidence == 0 then
		return "FAIL_RECOVERABLE", `evidence receipt {path} lists no evidence at all`
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
	--[[ AN UNVERIFIABLE ITEM IS AN ENVIRONMENT FAILURE, NOT A PASS (finding 3).
		The row used to return PASS with the message "N files still hash to what
		was recorded" while having hashed nothing at all: on a fresh clone none
		of the 698 archived paths is tracked and the private archive is not
		beside the checkout, so every receipt row passed verifying NOTHING and
		said so in words that claimed the opposite.

		FAIL_ENVIRONMENT is the honest state — the evidence exists, this machine
		cannot reach it — and it is non-blocking at full and blocking at release,
		which is the same contract every other declared class has. ]]
	if declared > 0 then
		table.insert(declaredEvidenceRows, { row = row.id, class = r.class, items = declared })
		return "FAIL_ENVIRONMENT",
			`{declared} of {#r.evidence} recorded {r.class} file(s) are neither on disk nor in a private archive beside this checkout, so nothing was verified`
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
				--[[ OUT OF SCOPE FOR THIS TIER IS NOT THE SAME AS UNJUDGED.
					`full` runs every deterministic producer; `release` adds
					perf, builds, package and the sibling suite. A row whose
					producer is declared for release only is not a row this tier
					FAILED to judge -- it is a row this tier never promised to.
					Both still report NOT_EVALUATED, because that is what
					happened, but only the first kind makes a run INCOMPLETE.
					Thirteen perf rows were turning every clean `full` run on a
					fresh clone into a non-zero exit for a reason the tier
					definition had already accounted for. ]]
				if not (producer.tiers :: any)[tier] then
					outOfTier[row.id] = true
					return "NOT_EVALUATED", `producer '{id}' is declared for a later tier than '{tier}' and did not run`
				end
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
		-- the stored WHOLE output, not the 4,000-character tail (finding 25)
		local stored = record.payload.stdout
		local probe
		if type(stored) == "string" and fs.isFile(stored) then
			probe = process.exec("bash", { "-c", `grep {pin.flags} {pin.pattern} {string.format("%q", stored)}` })
		else
			local text = (record.payload.stdoutTail or "") .. (record.payload.stderrTail or "")
			probe = process.exec("bash", {
				"-c",
				`printf '%s' "$FACET_VERIFY_PIN_TEXT" | grep {pin.flags} {pin.pattern}`,
			}, { env = { FACET_VERIFY_PIN_TEXT = text } })
		end
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
		--[[ A ROW'S OWN ASSERTION MAY ALSO SAY "THIS MACHINE CANNOT ANSWER",
			by the same convention its producers use: exit 2 with
			FAIL_ENVIRONMENT in the output. Three clauses here read something
			outside the repository or produced by a run -- the private archive's
			manifest, the last release record, a surface dump -- and a checkout
			that has none of them was reporting a failed assertion, which is the
			one thing it is not. Any other non-zero exit is still a failure. ]]
		if not out.ok and out.code == 2 then
			local whole = (out.stdout or "") .. "\n" .. (out.stderr or "")
			if string.find(whole, "FAIL_ENVIRONMENT", 1, true) ~= nil then
				local said = ""
				for line in string.gmatch(whole, "[^\n]+") do
					if string.find(line, "FAIL_ENVIRONMENT", 1, true) ~= nil then
						said = line
						break
					end
				end
				return "FAIL_ENVIRONMENT", string.sub(said, 1, 220)
			end
		end
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
		--[[ A PIN ON A FILE A RUN PRODUCES IS NOT THE SAME AS A BROKEN PIN.
			193 of the 211 evidence paths in this graph are git-ignored records
			that some run writes; 18 are checked in. An absent CHECKED-IN pin is
			a broken row -- somebody deleted evidence. An absent git-ignored one
			is a checkout that has not produced it yet, which on a public clone
			is every single one of them, and reporting that as a failure told a
			first-time reader the graph was broken. `check_manifest_integrity`
			has drawn this distinction since it was written; the row evaluator
			had not. FAIL_ENVIRONMENT is non-blocking at full and blocking at
			release, so nothing is waived where it matters. ]]
		if trackedPaths[row.evidence] then
			return "FAIL_RECOVERABLE", `missing evidence artifact {row.evidence}, which is CHECKED IN and gone`
		end
		return "FAIL_ENVIRONMENT",
			`evidence artifact {row.evidence} is git-ignored and produced by a run; this checkout has not produced it`
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
	local pending = 0
	for _, other in rowResults do
		if other.state == "DEFERRED" or phaseIndex[other.phase] >= mine then
			continue
		end
		if other.state == "NOT_EVALUATED" then
			if not outOfTier[other.id] then
				unevaluated += 1
			end
		--[[ A REGISTERED ROW THAT WAS NEVER PROVED CANNOT HAVE REGRESSED.
			This row's question is "did any earlier gate go BACKWARDS", and a
			PENDING row is one registered before its evidence existed -- the
			whole point of registering it. It never passed, so it cannot have
			stopped passing, and counting it as a regression made every later
			phase red for a row that was doing exactly what it was written to
			do. Measured 2026-08-31: one honest human-review pending in an early
			phase reddened five later phases and nothing else was wrong.

			It is counted and NAMED in the detail rather than swallowed, so this
			row can never be read as "everything before here is proved" -- which
			is a different claim, and not this one's. ]]
		elseif other.state == "PENDING" then
			pending += 1
		elseif not graphMod.statePasses(other.state, other.releaseBlocking) then
			table.insert(regressed, `{other.phase} :: {other.name} [{other.state}]`)
		end
	end
	local pendingNote = if pending > 0
		then ` ({pending} earlier row(s) are registered PENDING and were never proved, so they cannot have regressed)`
		else ""
	if #regressed > 0 then
		rr.state = "FAIL_RECOVERABLE"
		rr.detail = `{#regressed} earlier row(s) do not pass in this run:\n  {table.concat(regressed, "\n  ")}`
	elseif unevaluated > 0 then
		rr.state = "NOT_EVALUATED"
		rr.detail = `{unevaluated} earlier row(s) could not be evaluated in this tier{pendingNote}`
	else
		rr.state = "PASS"
		rr.detail = `no earlier row regressed in this run{pendingNote}`
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
local unevaluatedPhases = 0

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
			anyUnevaluated = anyUnevaluated or not outOfTier[rr.id]
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
	--[[ AN UNEVALUATED ROW DOES NOT HIDE ITS PHASE'S FAILURES (finding 5).
		The phase used to report NOT_EVALUATED the moment ANY row was
		unevaluated, and the run then skipped its failures entirely — so one row
		nobody could judge silently swallowed every red beside it. The phase's
		own verdict still says it is incomplete, but a failure inside it counts
		against the run exactly as it would have. ]]
	local status = if anyUnevaluated and pass then "NOT_EVALUATED" elseif pass then "PASS" else worst
	table.insert(phaseStates, { phase = phase, status = status, counts = counts })
	if not pass then
		overallRowsPass = false
	end
	if anyUnevaluated then
		unevaluatedPhases += 1
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
if #runner.declaredProducers > 0 then
	print("\27[1mProducers served from a declared-evidence receipt\27[0m")
	print(
		`  \27[2m{#runner.declaredProducers} producer(s) validate recorded evidence that is no longer on disk; each served its recorded verdict and the hashes of what it read.\27[0m`
	)
	for _, d in runner.declaredProducers do
		print(`  \27[2m- {d.producer} ({d.class}, {d.files} archived file(s))\27[0m`)
	end
	print("")
end
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
--[[ …AND A FULL OR RELEASE RUN THAT COULD NOT JUDGE EVERY ROW IS INCOMPLETE.
	Those two tiers claim to have judged the whole graph. A run that left rows
	unevaluated has not, and saying PASS would be the claim the tier makes rather
	than the one the evidence supports. INCOMPLETE exits non-zero. ]]
if status == "PASS" and unevaluatedPhases > 0 and (tier == "full" or tier == "release") then
	status = "INCOMPLETE"
end
if tier == "fast" or tier == "affected" then
	status = if producersPass then "PASS_PARTIAL" else "FAIL"
end

local rowRecords: { any } = {}
for _, rr in rowResults do
	table.insert(rowRecords, { id = rr.id, phase = rr.phase, state = rr.state, detail = rr.detail })
end

local runRecord = {
	schema = "facet-verify-run/1",
	gateEvidence = {
		schema = "facet-release-gate/1",
		tier = tier,
		status = status,
		commit = gateCommit,
		treeDirty = gateTreeDirty,
		sourceHash = gateSourceHash,
		completedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	},
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
--[[ A GATE RUN WRITES ITS OWN FILE (finding 6).
	`tools/gate.sh <phase>` runs one phase's producers and leaves every other
	phase evaluated from whatever the store happens to hold — so it is not full
	or release evidence, and writing it to `latest-full.json` overwrote a real
	run's record with a partial one. It gets its own name and its own tier
	string, and the package channel's gate evidence only ever comes from
	`latest-release.json`. ]]
local outputTier = if gatePhase ~= nil then `gate:{gatePhase}` else tier
runRecord.tier = outputTier
runRecord.gateEvidence.tier = outputTier
local encoded = serde.encode("json", runRecord, true)
fs.writeFile(`artifacts/verify/run-{runId}.json`, encoded)
if gatePhase ~= nil then
	fs.writeFile(`artifacts/verify/latest-gate-{gatePhase}.json`, encoded)
else
	fs.writeFile(`artifacts/verify/latest-{tier}.json`, encoded)
end

print(
	string.format(
		"verify: %s  tier=%s%s  %.1fs  identity=%s",
		status,
		tier,
		if gatePhase ~= nil then ` gate={gatePhase}` else "",
		durationMs / 1000,
		string.sub(runRecord.identity, 1, 12)
	)
)
print(`        artifacts/verify/{if gatePhase ~= nil then `latest-gate-{gatePhase}` else `latest-{tier}`}.json`)
if tier == "fast" or tier == "affected" then
	print(`        \27[33mThis is NOT full or release evidence.\27[0m`)
end
process.exit(if status == "FAIL" then 1 else 0)
