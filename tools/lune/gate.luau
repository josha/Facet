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
	writes an execution trace, and `BASH_XTRACEFD` sends that trace to its own
	file descriptor so it never mixes with the check's real stdout/stderr — a
	passing check's output is byte-for-byte what it was. On a failure the last
	traced command IS the localization: the specific `grep -q` whose pin moved,
	named with its pattern.

	Degrades cleanly: the whole enabling group is `; `-sequenced and silenced, so
	an environment that refuses the descriptor simply runs without a trace and
	reports exactly what it reported before. ]]
local TRACE_TAIL_LINES = 40
local function traceTail(path: string): string?
	if not fs.isFile(path) then
		return nil
	end
	local lines: { string } = {}
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		table.insert(lines, line)
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
	return `[shell trace; the LAST line is the command that failed]\n{elided}{table.concat(kept, "\n")}`
end

for index, check in checks do
	local state: string
	local detail = check.note or ""
	if check.run ~= nil then
		local tracePath = `{process.env.TMPDIR or "/tmp"}/facet-gate-trace-{index}.log`
		pcall(fs.removeFile, tracePath)
		-- built by concatenation, not interpolation: the shell group's own braces
		-- are not an escaping puzzle worth solving twice
		local script = 'cd "$(pwd)" || exit 1; { exec 9>"'
			.. tracePath
			.. '"; BASH_XTRACEFD=9; set -x; } 2>/dev/null; '
			.. check.run
		local result = process.exec("bash", { "-c", script })
		state = if result.ok then "PASS" else "FAIL_RECOVERABLE"
		detail = string.gsub((result.stdout or "") .. (result.stderr or ""), "%s+$", "")
		if state ~= "PASS" then
			local trace = traceTail(tracePath)
			if trace ~= nil then
				detail = if #detail == 0 then trace else `{detail}\n\n{trace}`
			end
		end
		pcall(fs.removeFile, tracePath)
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
