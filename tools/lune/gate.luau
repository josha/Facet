--!strict
-- Facet canonical gate (design §16.1, §16.4). Runs the active phase's check
-- manifest, writes artifacts/<phaseDir>/gate.json, exits 0 only when the phase
-- passes. Usage: lune run tools/lune/gate [phase-gate-name]
-- Pass rule: every check PASS, or FAIL_OPTIONAL (capability removed), or
-- FAIL_ENVIRONMENT with releaseBlocking=false. PENDING or any failure fails.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local manifest = require("./gate_manifest")

local phaseName = process.args[1] or "phase-0-foundation"
local checks = manifest[phaseName]
if checks == nil then
	print(`gate: unknown phase '{phaseName}'`)
	process.exit(2)
end

local phasesDoc = serde.decode("json", fs.readFile("phases.json"))
local phaseInfo = nil
for _, p in phasesDoc.phases do
	if p.gate == phaseName then
		phaseInfo = p
	end
end
assert(phaseInfo ~= nil, "phase missing from phases.json: " .. phaseName)

local results = {}
local requirementSet: { [string]: boolean } = {}
local overallPass = true
local worst = "PASS"

local function severity(state: string): number
	local order = {
		PASS = 0,
		FAIL_OPTIONAL = 1,
		FAIL_ENVIRONMENT = 2,
		PENDING = 3,
		FAIL_RECOVERABLE = 4,
		BLOCKED_CRITICAL = 5,
	}
	return order[state] or 4
end

--[[ A FAILING CHECK MUST SAY WHICH PART FAILED (MAINT-2, 2026-08-17).

	`detail` was `stdout .. stderr` and arrived EMPTY for almost every failure,
	which reads like a bug in the capture and is not one. The manifest's 469
	commands are compound shell lines — `lune run … >/dev/null && grep -q "…" file
	&& out="$(tools/suite_transcript.sh)" && echo "$out" | grep -q "…"` — and they
	discard their own output ON PURPOSE, because the gate's verdict is the exit
	status. `grep -q` prints nothing at all, by definition. So a check with 2,270
	text pins in it failed with no localization whatsoever: "FAIL_RECOVERABLE" and
	a blank line, for a command up to 8,048 characters long.

	The fix is to record what the shell DID rather than what it printed. `set -x`
	writes an execution trace, and on a failure the last traced command IS the
	localization: the specific `grep -q` whose pin moved, named with its pattern.

	── AND IT IS A SECOND RUN, NOT THE FIRST ONE (review NEW-5, 2026-08-17) ─────

	The first attempt put `set -x` on the CHECK'S OWN RUN and sent the trace to
	`BASH_XTRACEFD` so it would not mix with real output. `BASH_XTRACEFD` arrived
	in bash **4.1**, and the only bash on this machine — and on every stock desktop
	— is 3.2.57, where that assignment is an inert variable and `set -x` writes to
	**stderr**. So the trace landed in `detail` for every check, PASSING ONES
	INCLUDED (`detail` is written into `gate.json` unconditionally), unbounded,
	while the file the tail-bound applied to stayed empty. Measured: a passing
	compound check carried an 87-character xtrace and the trace file was 0 bytes.
	The mechanism the report described was not the one doing the work.

	So the trace is now a DIAGNOSTIC RE-RUN: the check runs exactly as it always
	did — no `set -x`, no redirection, output byte-for-byte what it was — and only
	when it FAILS is the same command run once more under `bash -x` with stderr
	captured. The cost is paid where the gate has already stopped, and a passing
	check cannot be polluted by a mechanism that never touches it. The re-run is
	labelled in `detail` so nobody reads it as a single execution, and it is
	skipped when the first run already said something useful. ]]
local TRACE_TAIL_LINES = 40
local function traceTail(raw: string): string?
	local lines: { string } = {}
	for line in string.gmatch(raw, "[^\n]+") do
		-- xtrace lines are the only ones prefixed with the PS4 default; anything
		-- else in this stream is the command's own stderr on the re-run, which is
		-- already in `detail` from the first run
		if string.sub(line, 1, 1) == "+" then
			table.insert(lines, line)
		end
	end
	if #lines == 0 then
		return nil
	end
	local from = math.max(1, #lines - TRACE_TAIL_LINES + 1)
	local kept: { string } = {}
	for i = from, #lines do
		table.insert(kept, lines[i])
	end
	local elided = if from > 1 then `…{from - 1} earlier traced command(s) elided…\n` else ""
	return `[shell trace, from a diagnostic RE-RUN of the same command; the LAST line is the one that failed]\n{elided}{table.concat(
		kept,
		"\n"
	)}`
end

for _, check in checks do
	local state: string
	local detail = check.note or ""
	if check.run ~= nil then
		-- THE CHECK'S OWN RUN IS UNTOUCHED. Same command, same shell, no trace, no
		-- redirection — a passing check's `detail` is exactly what it was before
		-- any of this existed.
		local result = process.exec("bash", { "-c", `cd "$(pwd)" || exit 1; {check.run}` })
		state = if result.ok then "PASS" else "FAIL_RECOVERABLE"
		detail = string.gsub((result.stdout or "") .. (result.stderr or ""), "%s+$", "")
		if state ~= "PASS" then
			-- ...and only a FAILURE pays for the localization: one re-run under
			-- `bash -x`, whose stderr carries the trace on every bash there is. The
			-- gate has already stopped, so the second execution costs a run of a
			-- check nobody is going to trust anyway.
			local traced = process.exec("bash", { "-xc", `cd "$(pwd)" || exit 1; {check.run}` })
			local trace = traceTail((traced.stderr or "") .. "\n" .. (traced.stdout or ""))
			if trace ~= nil then
				detail = if #detail == 0 then trace else `{detail}\n\n{trace}`
			end
		end
		-- a passing run must leave its evidence artifact behind
		if state == "PASS" and check.evidence ~= nil and not fs.isFile(check.evidence) then
			state = "FAIL_RECOVERABLE"
			detail = detail .. ` [missing evidence artifact {check.evidence}]`
		end
	else
		state = check.state or "PENDING"
	end

	local passes = state == "PASS"
		or state == "FAIL_OPTIONAL"
		or (state == "FAIL_ENVIRONMENT" and check.releaseBlocking ~= true)
	if not passes then
		overallPass = false
	end
	if severity(state) > severity(worst) then
		worst = state
	end
	for _, r in check.requirements do
		requirementSet[r] = true
	end
	table.insert(results, {
		name = check.name,
		state = state,
		requirements = check.requirements,
		evidence = check.evidence,
		releaseBlocking = check.releaseBlocking or false,
		detail = detail,
	})
	print(`  {state}  {check.name}`)
end

local requirements = {}
for r in requirementSet do
	table.insert(requirements, r)
end
table.sort(requirements)

local gateJson = {
	schema = "facet-gate/1",
	gate = phaseName,
	status = if overallPass then "PASS" else worst,
	requirements = requirements,
	checks = results,
	next = if overallPass then phaseInfo.next else phaseName,
}

fs.writeDir(phaseInfo.artifactDir)
fs.writeFile(phaseInfo.gateArtifact, serde.encode("json", gateJson, true))
print(`gate: {gateJson.status} -> {phaseInfo.gateArtifact}`)
process.exit(if overallPass then 0 else 1)
