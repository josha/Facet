--!strict
-- CLI wrapper for the theme DRIFT lint. Exit 0 only with zero violations.
--
-- WHY IT IS A SEPARATE FILE (and why this one exists as of 2026-08-21): the
-- checker's own header claimed "CLI: run this file directly", and it was not
-- true — `check_theme_drift.luau` ends in `return checker`, so `lune run
-- tools/lune/check_theme_drift` builds the module, returns it, and exits 0
-- WHATEVER the tree says. A gate row spelled that way is a check that proves
-- nothing. Its sibling `check_example_drift` had already solved this with a
-- `_cli` wrapper; this is the same shape, so both lints now have exactly one
-- way to be run for an exit code.
local process = require("@lune/process")
local checker = require("./check_theme_drift")

local result = checker.check()
if result.ok then
	print(
		`theme drift: clean — framework {result.counts.files} files / {result.counts.lines} lines `
			.. `({result.counts.allowlisted} allowlisted); examples {result.counts.exampleFiles} files / `
			.. `{result.counts.exampleLines} lines ({result.counts.optedOut} marked THEME-OPT-OUT, `
			.. `{result.counts.probeSuppressed} PROBE-EXEMPT across {result.counts.probeExemptFiles} listed files)`
	)
	process.exit(0)
end
for _, problem in result.problems do
	print(problem)
end
local framework, examples = 0, 0
for _, v in result.violations do
	if v.scope == "example" then
		examples += 1
	else
		framework += 1
	end
end
print(`theme drift: {#result.violations} violation(s) — {framework} framework, {examples} example`)
process.exit(1)
