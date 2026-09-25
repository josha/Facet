--!nocheck

local fs = require("@lune/fs")
local process = require("@lune/process")
local testkit = require("../../tests/lib/testkit")

local outPath = process.args[1] or "artifacts/spec-timings.json"

local runSrc = fs.readFile("tests/run.luau")
local order: { string } = {}
for line in string.gmatch(runSrc, "[^\n]+") do
	local rel = string.match(line, '^%s*require%("%./([%w_/%.]+)"%)')
	if rel then
		table.insert(order, rel)
	end
end
assert(#order > 0, "parsed no requires out of tests/run.luau")

local loadClock: { [string]: number } = {}
local caseClock: { [string]: number } = {}
local caseCount: { [string]: number } = {}
local current = "<preload>"

local cases: { { owner: string, name: string, ms: number } } = {}

local progress: { { i: number, atMs: number, heapKb: number, owner: string } } = {}
local caseOrdinal = 0

local originalIt = testkit.it
testkit.it = function(name: string, fn: () -> ())
	local owner = current
	caseCount[owner] = (caseCount[owner] or 0) + 1
	local record = { owner = owner, name = name, ms = 0 }
	table.insert(cases, record)
	originalIt(name, function()
		local t0 = os.clock()
		local ok, err = pcall(fn)
		local dt = os.clock() - t0
		record.ms = dt * 1000
		caseClock[owner] = (caseClock[owner] or 0) + dt
		caseOrdinal += 1

		if caseOrdinal % 25 == 0 then
			table.insert(progress, {
				i = caseOrdinal,
				atMs = os.clock() * 1000,
				heapKb = collectgarbage("count"),
				owner = owner,
			})
		end
		if not ok then
			error(err, 0)
		end
	end)
end

local wallStart = os.clock()
for _, rel in order do
	current = rel
	local t0 = os.clock()
	require("../../tests/" .. rel)
	loadClock[rel] = os.clock() - t0
end
current = "<run>"

local ok = testkit.run()
local wall = os.clock() - wallStart

local rows: { { rel: string, load: number, cases: number, total: number, count: number } } = {}
local sumLoad, sumCases, sumCount = 0, 0, 0
for _, rel in order do
	local l = loadClock[rel] or 0
	local c = caseClock[rel] or 0
	sumLoad += l
	sumCases += c
	sumCount += caseCount[rel] or 0
	table.insert(rows, { rel = rel, load = l, cases = c, total = l + c, count = caseCount[rel] or 0 })
end
table.sort(rows, function(a, b)
	return a.total > b.total
end)

local lines: { string } = {}
table.insert(lines, "rank\tspec\ttotal_ms\tload_ms\tcases_ms\tcases")
for i, r in rows do
	table.insert(
		lines,
		string.format("%d\t%s\t%.1f\t%.1f\t%.1f\t%d", i, r.rel, r.total * 1000, r.load * 1000, r.cases * 1000, r.count)
	)
end
table.insert(
	lines,
	string.format(
		"--\tTOTAL attributed\t%.1f\t%.1f\t%.1f\t%d",
		(sumLoad + sumCases) * 1000,
		sumLoad * 1000,
		sumCases * 1000,
		sumCount
	)
)
table.insert(
	lines,
	string.format("--\tunattributed (print/GC/startup)\t%.1f\t\t\t", (wall - sumLoad - sumCases) * 1000)
)
table.insert(lines, string.format("--\tharness wall\t%.1f\t\t\t", wall * 1000))

table.sort(cases, function(a, b)
	return a.ms > b.ms
end)
table.insert(lines, "")
table.insert(lines, "rank\tcase_ms\tspec\tcase")
for i = 1, math.min(30, #cases) do
	local c = cases[i]
	table.insert(lines, string.format("%d\t%.1f\t%s\t%s", i, c.ms, c.owner, c.name))
end

table.insert(lines, "")
table.insert(lines, "case_index\telapsed_ms\theap_kb\tms_per_case\tspec_at_sample")
local prevAt, prevI = wallStart * 1000, 0
for _, p in progress do
	local span = p.atMs - prevAt
	local n = p.i - prevI
	table.insert(
		lines,
		string.format(
			"%d\t%.0f\t%.0f\t%.1f\t%s",
			p.i,
			p.atMs - wallStart * 1000,
			p.heapKb,
			span / math.max(1, n),
			p.owner
		)
	)
	prevAt, prevI = p.atMs, p.i
end

local json: { string } = {}
for _, r in rows do
	table.insert(
		json,
		string.format(
			'    { "spec": "%s", "totalMs": %.2f, "loadMs": %.2f, "casesMs": %.2f, "cases": %d }',
			r.rel,
			r.total * 1000,
			r.load * 1000,
			r.cases * 1000,
			r.count
		)
	)
end
fs.writeFile(
	outPath,
	string.format(
		'{\n  "schema": "facet-spec-timings/1",\n  "green": %s,\n  "specs": %d,\n  "cases": %d,\n  "wallMs": %.2f,\n  "attributedMs": %.2f,\n  "rows": [\n%s\n  ]\n}\n',
		tostring(ok),
		#order,
		sumCount,
		wall * 1000,
		(sumLoad + sumCases) * 1000,
		table.concat(json, ",\n")
	)
)

fs.writeFile(outPath .. ".tsv", table.concat(lines, "\n") .. "\n")
print(string.format("spec timings: %s and %s.tsv", outPath, outPath))
if not ok then
	process.exit(1)
end
