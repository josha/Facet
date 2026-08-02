--!strict
-- CLI for the registration checker (design §17 Phase 4; UI-AGENT-001).
-- Usage: lune run tools/lune/check_registration_cli   (from the library root)
-- Exits nonzero listing every registration problem with an actionable hint.

local process = require("@lune/process")
local checker = require("./check_registration")

local result = checker.check()
if result.ok then
	print(
		`check_registration: PASS ({result.counts.controls} controls, {result.counts.exportsDocumented} exports documented, {result.counts.specs} specs registered, {result.counts.interactiveControls} interactive controls prove four-input, {result.counts.affordanceControls} prove the paradigm axis)`
	)
	process.exit(0)
end
print(`check_registration: FAIL [UI-AGENT-001] — {#result.problems} problem(s):`)
for _, problem in result.problems do
	print("  - " .. problem)
end
print("hint: docs/extending/ has the playbook for each extension class; tools/lune/scaffold stamps complete skeletons")
process.exit(1)
