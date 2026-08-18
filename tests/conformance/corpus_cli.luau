--!strict
-- Accessibility / localization CORPUS runner (design §8.4, §17 Phase 4).
-- Runs the corpus against the reference (custom) core, writes the deterministic
-- corpus dump + per-check results to artifacts/phase-4/a11y-l10n-corpus.json,
-- and exits nonzero on any failure (UI-AGENT-001: stable command, structured
-- artifact, names the failing requirement + fixture + actionable hint).
-- Usage: lune run tests/conformance/corpus_cli
--   exit 0 = every corpus check PASSED; exit 1 = at least one FAILED.

local process = require("@lune/process")

local artifact = require("../../tools/lune/artifact")
local corpus = require("./a11y_l10n_corpus")
local customFactory = require("../../src/core/custom")

local results = {}
local passed, failed = 0, 0
for _, check in corpus.checks do
	local core = customFactory.new()
	local ok, okOrErr, note = pcall(check.run, core)
	local checkPassed = ok and okOrErr == true
	local detail = if ok then note else `check raised: {tostring(okOrErr)}`
	if checkPassed then
		passed += 1
	else
		failed += 1
	end
	results[#results + 1] = {
		name = check.name,
		requirement = check.requirement,
		status = if checkPassed then "PASS" else "FAIL",
		note = detail,
	}
	print(`  {checkPassed and "PASS" or "FAIL"}  {check.name}{detail and ("  — " .. tostring(detail)) or ""}`)
end

-- unrepresentable-fact ledger: the script facts the headless text provider cannot
-- model, surfaced for the phase gate (each still asserted via its declared fallback).
local fallbacks = {}
local fx = require("../fixtures/a11y_l10n_fixtures")
for _, f in fx.localization do
	if f.declaredFallback ~= nil then
		fallbacks[#fallbacks + 1] = {
			fixture = f.id,
			unrepresentable = f.unrepresentable,
			declaredFallback = f.declaredFallback,
		}
	end
end

artifact.writeJson("artifacts/phase-4/a11y-l10n-corpus.json", {
	schema = "facet-a11y-l10n-corpus/1",
	requirement = "UI-ADAPT-001",
	core = "custom",
	status = if failed == 0 then "PASS" else "FAIL",
	passed = passed,
	failed = failed,
	total = #corpus.checks,
	checks = results,
	declaredFallbacks = fallbacks,
	dump = corpus.dump(customFactory.new()),
})
print(`a11y-l10n-corpus: {passed}/{#corpus.checks} passed -> artifacts/phase-4/a11y-l10n-corpus.json`)

if failed > 0 then
	print("a11y-l10n-corpus: FAIL (UI-ADAPT-001) — see notes above for fixture + hint")
	process.exit(1)
end
process.exit(0)
