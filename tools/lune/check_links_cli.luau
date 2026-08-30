--!strict
-- Link checker for Facet's public documents. Run from the library root:
--
--   lune run tools/lune/check_links_cli              check every public document
--   lune run tools/lune/check_links_cli -- --selftest prove the check can fail
--
-- Read-only. Exit 0 = every relative link and heading anchor resolves, and none
-- of them points into material that stays in the private archive. On failure
-- each line names the document, the line number, the link, and what is wrong.

local process = require("@lune/process")
local checker = require("./check_links")

local wantSelftest = false
for _, arg in process.args do
	if arg == "--selftest" then
		wantSelftest = true
	end
end

if wantSelftest then
	local result = checker.selftest()
	if result.ok then
		print("check_links --selftest: PASS — a dead link and an archived-material link are both reported,")
		print("                        and the tree itself still passes")
		process.exit(0)
	end
	print("check_links --selftest: FAIL — the check cannot report a fault it should:")
	for _, problem in result.problems do
		print("  - " .. problem)
	end
	process.exit(1)
end

local result = checker.check()

if result.ok then
	print(
		`check_links: PASS ({result.counts.documents} documents, {result.counts.links} relative links, `
			.. `{result.counts.anchors} heading anchors)`
	)
	process.exit(0)
end

print(`check_links: FAIL — {#result.problems} problem(s):`)
for _, problem in result.problems do
	print("  - " .. problem)
end
print("hint: a link into docs/plans, docs/handoff, docs/research, artifacts/ or a retired reference document")
print("      must become plain text; `python3 tools/relink_archived.py --fix` does that for docs/adr and docs/lessons.")
process.exit(1)
