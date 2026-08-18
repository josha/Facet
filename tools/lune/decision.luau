--!strict
-- Facet decision command (design §16.1): evaluates a declared rubric file and
-- writes the ADR + artifacts/decision-<name>.json.
-- Usage: lune run tools/lune/decision <rubric.json>
-- Rubric schema (facet-rubric/1):
-- { "name": str, "adrSlug": str, "question": str,
--   "criteria": [{ "id": str, "weight": number, "higherIsBetter": bool? }],
--   "candidates": [{ "id": str, "summary": str,
--                    "scores": { criterionId: number }, -- 0..5, evidence-backed
--                    "evidence": { criterionId: str } }],
--   "context": str, "consequences": str? }
-- Scores must be filled from measured artifacts by the caller; this command
-- computes weighted totals, picks the winner, and renders the ADR.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local artifact = require("./artifact")

local rubricPath = process.args[1]
if rubricPath == nil or not fs.isFile(rubricPath) then
	print("decision: FAIL - usage: tools/decision.sh <rubric.json> (file must exist)")
	process.exit(2)
end
local rubric = serde.decode("json", fs.readFile(rubricPath))

local totals = {}
for _, candidate in rubric.candidates do
	local total = 0
	for _, criterion in rubric.criteria do
		local score = candidate.scores[criterion.id]
		if score == nil then
			print(`decision: FAIL - candidate {candidate.id} missing score for {criterion.id}`)
			process.exit(1)
		end
		local normalized = if criterion.higherIsBetter == false then 5 - score else score
		total += normalized * criterion.weight
	end
	table.insert(totals, { id = candidate.id, total = total })
end
table.sort(totals, function(a, b)
	return a.total > b.total
end)
local winner = totals[1]

-- next ADR number
local maxN = 0
for _, name in fs.readDir("docs/adr") do
	local n = tonumber(string.match(name, "^ADR%-(%d+)") or "")
	if n ~= nil and n > maxN then
		maxN = n
	end
end
local adrPath = string.format("docs/adr/ADR-%04d-%s.md", maxN + 1, rubric.adrSlug)

local lines = {
	`# ADR-{string.format("%04d", maxN + 1)}: {rubric.question}`,
	"",
	`- **Status:** Accepted ({os.date("%Y-%m-%d")})`,
	`- **Decision:** \`{winner.id}\` (weighted {string.format("%.2f", winner.total)})`,
	`- **Context:** {rubric.context}`,
	"",
	"## Scores (0-5, weighted; evidence per cell)",
	"",
}
local header = "| criterion (weight) |"
local sep = "|---|"
for _, c in rubric.candidates do
	header ..= ` {c.id} |`
	sep ..= "---|"
end
table.insert(lines, header)
table.insert(lines, sep)
for _, criterion in rubric.criteria do
	local row = `| {criterion.id} ({criterion.weight}) |`
	for _, c in rubric.candidates do
		local ev = (c.evidence or {})[criterion.id]
		row ..= ` {c.scores[criterion.id]}{ev and " — " .. ev or ""} |`
	end
	table.insert(lines, row)
end
table.insert(lines, "")
table.insert(lines, "## Totals")
table.insert(lines, "")
for _, t in totals do
	table.insert(lines, `- {t.id}: {string.format("%.2f", t.total)}`)
end
for _, c in rubric.candidates do
	table.insert(lines, "")
	table.insert(lines, `**{c.id}:** {c.summary}`)
end
if rubric.consequences ~= nil then
	table.insert(lines, "")
	table.insert(lines, `- **Consequences:** {rubric.consequences}`)
end
table.insert(lines, "")
fs.writeFile(adrPath, table.concat(lines, "\n"))

artifact.writeJson(`artifacts/decision-{rubric.name}.json`, {
	schema = "facet-decision/1",
	status = "PASS",
	rubric = rubricPath,
	winner = winner.id,
	totals = totals,
	adr = adrPath,
})
print(`decision: {winner.id} wins -> {adrPath} + artifacts/decision-{rubric.name}.json`)
process.exit(0)
