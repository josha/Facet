--!strict
-- THE canonical documentation command for the theme surface (stage
-- theme-packages-and-skinning, acceptance row TP-A12):
--
--   lune run tools/lune/check_docs_cli            (from the library root)
--   lune run tools/lune/check_docs_cli -- --list  (print the obligations it enforces)
--
-- READ-ONLY by default and always: this document set has no generated blocks —
-- every line is a human explanation — so `--write` has nothing to regenerate and
-- says so rather than rewriting prose. Exit 0 = the docs match the build; on
-- failure each problem names the document, the missing obligation, and the
-- command or manual action that fixes it.

local process = require("@lune/process")
local checker = require("./check_docs")

local wantWrite = false
local wantList = false
for _, arg in process.args do
	if arg == "--write" then
		wantWrite = true
	elseif arg == "--list" then
		wantList = true
	end
end

if wantList then
	print("check_docs enforces:")
	for index, obligation in checker.OBLIGATIONS do
		print(`  {index}. {obligation}`)
	end
	process.exit(0)
end

local result = checker.check()

if wantWrite then
	print(
		"check_docs: --write has nothing to do — this document set contains no generated blocks "
			.. "(guide prose, playbook prose and the API reference are human-written by design). "
			.. "Run without --write; fix any failure by editing the named document."
	)
end

if result.ok then
	print(
		`check_docs: PASS ({result.counts.documents} documents, {result.counts.anchors} surface anchors, `
			.. `{result.counts.citations} comparison citations, `
			.. `{result.counts.links} local links, {result.counts.themeExports} themes exports documented, `
			.. `{result.counts.scenarioSteps} scenario steps, {result.counts.examplePackages} example packages, `
			.. `{result.counts.assets} asset files, {result.counts.forbiddenPhrases} stale phrases absent)`
	)
	process.exit(0)
end

print(`check_docs: FAIL [UI-AGENT-001] — {#result.problems} problem(s):`)
for _, problem in result.problems do
	print("  - " .. problem)
end
print("hint: docs/guide/09-custom-themes.md is the walkthrough, docs/extending/new-theme.md the contributor playbook;")
print("      `lune run tools/lune/check_docs_cli -- --list` prints every obligation this command enforces.")
process.exit(1)
