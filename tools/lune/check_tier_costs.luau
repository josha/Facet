--!nocheck
--[[ THE TIER RECORD, CHECKED AGAINST A MEASUREMENT (O-17, 2026-08-15).

	  lune run tools/lune/time_specs artifacts/spec-timings.json > /dev/null
	  lune run tools/lune/check_tier_costs [artifacts/spec-timings.json]

	WHY IT EXISTS. `tests/lib/tiers.luau` records a per-spec cost and a reason for
	every fast-tier exclusion, and both are TYPED. Nothing forced them to stay
	true, and by 2026-08-15 nothing had: `overflow_sweep.spec` was recorded at
	1036 ms and measured 16342, and two specs the list does not exclude had grown
	costlier than three it does. A number that can drift arbitrarily far from the
	thing it describes, with nothing noticing, is decoration — `tests/tier.spec`
	only ever asserted `ms > 250`, which any typed number satisfies.

	This is the smallest thing that makes the record honest without paying for it
	on every suite run. It cannot live IN the suite: the only way to know what a
	spec costs is to run every spec, and a check that costs 80 seconds does not
	belong between two keystrokes. It is a gate-tier check, run against the JSON
	`tools/lune/time_specs` already writes.

	WHAT IT ASSERTS, and each is a way the record rots:
	  1. every excluded spec was actually TIMED (a rename leaves a record
	     describing nothing — `tests/tier.spec` already catches this one against
	     run.luau, and this catches it against the measurement);
	  2. every recorded `ms` is within TOLERANCE of the measured median — the
	     record is a claim about cost, so a claim off by 15x is a lie, not a
	     rounding;
	  3. nothing measured above `tiers.THRESHOLD_MS` is left in the fast tier
	     unless it is a declared FAST_ANCHOR. This is the half a rank could never
	     hold: "the eleven costliest" is a claim about every file this list does
	     not name, and only a threshold can be checked from the outside.

	WHAT IT IS NOT. It is not a performance gate — a spec is allowed to get
	slower; it is a check that the RECORD still describes the run. And it reads
	whatever timings file it is given: pass a fresh one, or it is checking a
	measurement as stale as the record it is judging (it prints the file's own
	case count and wall time so that is visible rather than assumed).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local tiers = require("../../tests/lib/tiers")

-- How far a recorded number may sit from the measured one before the record is
-- fiction rather than round-off. Generous on purpose: this catches drift, not
-- noise (the measured per-spec spread over three runs was ~2-5%).
local TOLERANCE = 0.5

local path = process.args[1] or "artifacts/spec-timings.json"
if not fs.isFile(path) then
	print(
		`check_tier_costs: no timings at '{path}'. Produce one first:\n`
			.. `  lune run tools/lune/time_specs {path} > /dev/null`
	)
	process.exit(1)
end

local data = serde.decode("json", fs.readFile(path))
local measured: { [string]: number } = {}
for _, row in data.rows do
	measured[row.spec] = row.totalMs
end

local excluded: { [string]: boolean } = {}
for _, entry in tiers.SLOW do
	excluded[entry.spec] = true
end
local anchored: { [string]: boolean } = {}
for _, spec in tiers.FAST_ANCHORS do
	anchored[spec] = true
end

local problems: { string } = {}

-- 1 + 2: the record against the measurement, entry by entry
for _, entry in tiers.SLOW do
	local ms = measured[entry.spec]
	if ms == nil then
		table.insert(problems, `  {entry.spec}: excluded by tiers.SLOW but absent from {path} — was it renamed?`)
		continue
	end
	local drift = math.abs(ms - entry.ms) / math.max(ms, 1)
	if drift > TOLERANCE then
		table.insert(
			problems,
			string.format(
				"  %s: recorded %d ms, measured %.0f ms (%.0f%% off) — re-record it from this run",
				entry.spec,
				entry.ms,
				ms,
				drift * 100
			)
		)
	end
end

-- 3: nothing above the threshold may sit in the fast tier undeclared
local overs: { { spec: string, ms: number } } = {}
for spec, ms in measured do
	if ms > tiers.THRESHOLD_MS and not excluded[spec] and not anchored[spec] then
		table.insert(overs, { spec = spec, ms = ms })
	end
end
table.sort(overs, function(a, b)
	return a.ms > b.ms
end)
for _, over in overs do
	table.insert(
		problems,
		string.format(
			"  %s: %.0f ms is over tiers.THRESHOLD_MS (%d) and it is neither excluded nor a FAST_ANCHOR — "
				.. "the fast tier is carrying a workload it was built to leave out",
			over.spec,
			over.ms,
			tiers.THRESHOLD_MS
		)
	)
end

print(
	string.format(
		"check_tier_costs: %s — %d specs, %d cases, %.1f s wall; %d exclusions, threshold %d ms, tolerance %.0f%%",
		path,
		data.specs,
		data.cases,
		data.wallMs / 1000,
		#tiers.SLOW,
		tiers.THRESHOLD_MS,
		TOLERANCE * 100
	)
)

if #problems > 0 then
	print(`check_tier_costs: {#problems} problem(s) — the tier record no longer describes the run:`)
	for _, line in problems do
		print(line)
	end
	process.exit(1)
end

print(
	"check_tier_costs: every exclusion is timed, within tolerance, and nothing over the threshold is in the fast tier"
)
