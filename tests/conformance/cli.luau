--!strict
-- Conformance CLI (design §17 Phase 0): runs the identical suite +
-- micro-screens against one named core candidate and writes the scorecard to
-- artifacts/conformance-<core>.json.
-- Usage: lune run tests/conformance/cli <custom|imperative> [--require-all-pass]
-- Exit 0 = run completed (and, with --require-all-pass, every check passed).
-- A fresh core instance is constructed per check: no cross-check state.
--
-- TWO ARMS, AND ONLY ONE OF THEM SHIPS. `custom` is the core Facet ships
-- (`Facet.newCore`, ADR-0002). `imperative` is the retained recompute-all
-- baseline, a development fixture that lives under `bench/cores/` precisely so
-- it stays out of the distributed Package — running the identical checks
-- against it is what keeps `contract.luau` an interface rather than a
-- description of one implementation.

local process = require("@lune/process")

local artifact = require("../../tools/lune/artifact")
local suite = require("./suite")
local microScreens = require("./micro_screens")
local a11yL10nCorpus = require("./a11y_l10n_corpus")

local factories: { [string]: any } = {
	custom = require("../../src/core/custom"),
	imperative = require("../../bench/cores/imperative"),
}

local coreName = process.args[1]
local requireAllPass = process.args[2] == "--require-all-pass"
local factory = factories[coreName or ""]
if factory == nil then
	print("conformance: usage: lune run tests/conformance/cli <custom|imperative> [--require-all-pass]")
	process.exit(2)
end

local allChecks: { any } = {}
for _, c in suite do
	table.insert(allChecks, c)
end
for _, c in microScreens do
	table.insert(allChecks, c)
end
-- Phase 4: accessibility/localization corpus (UI-ADAPT-001). Runs identically on
-- every core; corpus results land in artifacts/conformance-<core>.json alongside
-- the scheduler/lifetime checks.
for _, c in a11yL10nCorpus.checks do
	table.insert(allChecks, c)
end

local results = {}
local passed, failed = 0, 0
for _, check in allChecks do
	local core = factory.new()
	local ok, okOrErr, note = pcall(check.run, core)
	local checkPassed = ok and okOrErr == true
	local detail = if ok then note else `check raised: {tostring(okOrErr)}`
	if checkPassed then
		passed += 1
	else
		failed += 1
	end
	table.insert(results, {
		name = check.name,
		requirement = check.requirement,
		status = if checkPassed then "PASS" else "FAIL",
		note = detail,
	})
	print(`  {checkPassed and "PASS" or "FAIL"}  {check.name}{detail and ("  — " .. tostring(detail)) or ""}`)
end

-- claims honesty (verifier finding 4): a factory may not claim a semantic its
-- scorecard fails. Claiming false while passing is fine (conservative).
local claimChecks: { [string]: string } = {
	dynamicDependencies = "dynamic-dependencies-swap-atomically",
	cycleDetection = "cycle-reported-not-hung",
	writeDuringMemoError = "write-during-memo-is-error",
}
local claimsMismatches = {}
for claim, checkName in claimChecks do
	if (factory.claims :: any)[claim] == true then
		for _, r in results do
			if r.name == checkName and r.status == "FAIL" then
				table.insert(claimsMismatches, `{claim} claimed true but {checkName} FAILED`)
			end
		end
	end
end

artifact.writeJson(`artifacts/conformance-{coreName}.json`, {
	schema = "facet-conformance/1",
	core = coreName,
	claims = factory.claims,
	claimsMismatches = claimsMismatches,
	status = if failed == 0 and #claimsMismatches == 0 then "PASS" else "FAIL",
	passed = passed,
	failed = failed,
	total = #allChecks,
	checks = results,
})
print(`conformance[{coreName}]: {passed}/{#allChecks} passed -> artifacts/conformance-{coreName}.json`)

for _, m in claimsMismatches do
	print(`  CLAIMS-MISMATCH  {m}`)
end
if #claimsMismatches > 0 then
	process.exit(1) -- dishonest annotation always fails the run
end
if requireAllPass and failed > 0 then
	process.exit(1)
end
process.exit(0)
