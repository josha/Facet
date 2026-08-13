--!nocheck
-- Per-spec-file timing harness (parity round 2, Phase 6 step 1).
--
-- WHAT IT MEASURES, exactly:
--   * `load`  — wall clock (os.clock) around each `require("<spec>")`, taken in
--     the SAME ORDER `tests/run.luau` requires them. That covers the module's
--     own body: its transitive first-time requires of `src/`, and every fixture
--     built at `describe()` scope, because a describe body runs at require time.
--   * `cases` — wall clock summed over each registered case function, attributed
--     to whichever spec file was being required when `it()` registered it.
--     Collected by wrapping `testkit.it` BEFORE any spec is required, so the
--     `local it = testkit.it` capture every spec does picks up the wrapper.
--   * `total` = load + cases.
--
-- WHAT IT CANNOT SEE:
--   * First-toucher bias. A `src/` module is loaded once; whichever spec
--     requires it first pays its whole load. That cost is real but it is not
--     that spec's fault, and deleting that spec would not return the time.
--   * GC skew. Luau's collector runs where it runs; a spec that allocates
--     heavily can be charged inside a later spec's case.
--   * testkit's own printing (~4.5k lines) and process startup/teardown, which
--     show up only in the `unattributed` remainder line.
--   * Anything below case granularity: a slow case is not decomposed.
--
-- It does NOT change what runs: same specs, same order, one process, same
-- `testkit.run()`. Output is TSV on stdout plus a JSON blob to a file, so the
-- suite's own output can be discarded.
--
-- Usage (from the library root):
--   lune run tools/lune/time_specs [outfile.json] > /dev/null

local fs = require("@lune/fs")
local process = require("@lune/process")
local testkit = require("../../tests/lib/testkit")

local outPath = process.args[1] or "artifacts/spec-timings.json"

-- The require list is parsed out of tests/run.luau so this harness can never
-- silently time a different set of specs than the suite runs.
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

-- ...and the thirty slowest individual CASES, because a file's total says
-- nothing about whether the cost is one workload or fifty.
table.sort(cases, function(a, b)
	return a.ms > b.ms
end)
table.insert(lines, "")
table.insert(lines, "rank\tcase_ms\tspec\tcase")
for i = 1, math.min(30, #cases) do
	local c = cases[i]
	table.insert(lines, string.format("%d\t%.1f\t%s\t%s", i, c.ms, c.owner, c.name))
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
		'{\n  "schema": "luauui-spec-timings/1",\n  "green": %s,\n  "specs": %d,\n  "cases": %d,\n  "wallMs": %.2f,\n  "attributedMs": %.2f,\n  "rows": [\n%s\n  ]\n}\n',
		tostring(ok),
		#order,
		sumCount,
		wall * 1000,
		(sumLoad + sumCases) * 1000,
		table.concat(json, ",\n")
	)
)

-- The table goes to a FILE next to the JSON, so the caller can send the suite's
-- own 4.5k pass lines to /dev/null and still read the result.
fs.writeFile(outPath .. ".tsv", table.concat(lines, "\n") .. "\n")
print(string.format("spec timings: %s and %s.tsv", outPath, outPath))
if not ok then
	process.exit(1)
end
