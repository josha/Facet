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

for _, check in checks do
	local state: string
	local detail = check.note or ""
	if check.run ~= nil then
		local result = process.exec("bash", { "-c", `cd "$(pwd)" && {check.run}` })
		state = if result.ok then "PASS" else "FAIL_RECOVERABLE"
		detail = string.gsub((result.stdout or "") .. (result.stderr or ""), "%s+$", "")
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
