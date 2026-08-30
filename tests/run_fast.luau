--!nocheck
-- Facet FAST TIER — the inner-loop runner.  Run with:  ./run-tests.sh --fast
--
-- ============================================================================
-- THIS IS NOT THE GATE SUITE. It runs tests/run.luau's spec list MINUS the
-- eleven measured-slowest files (tests/lib/tiers.luau names each one and why).
-- The gate runs `./run-tests.sh` with no arguments, and `tools/test.sh` REFUSES
-- a transcript carrying the FACET-FAST-TIER marker printed below.
-- ============================================================================
--
-- Nothing is skipped or weakened: every excluded file runs in full on the gate
-- suite. The tier exists so that the loop between two keystrokes is ~8 s rather
-- than ~43 s, and so that the ~35 s of workload mounts and source scanners are
-- paid once, on the gate, instead of on every save.

local process = require("@lune/process")
local testkit = require("./lib/testkit")
local tiers = require("./lib/tiers")

-- Measured at f476b63 by `lune run tools/lune/time_specs` (median of three
-- runs; whole-suite noise floor 2.3 % over six unchanged runs).
local FULL_SUITE_SECONDS = 42.7
local FAST_TIER_BUDGET = 0.25

local order = tiers.fastOrder()
local full = tiers.fullOrder()

print("")
print(
	string.format(
		"\27[1;33m=== FACET-FAST-TIER — %d of %d spec files — NOT THE GATE SUITE ===\27[0m",
		#order,
		#full
	)
)
print(string.format("\27[33m    excluded: %d measured-slowest files (tests/lib/tiers.luau)\27[0m", #tiers.SLOW))
print(string.format("\27[33m    the gate runs ./run-tests.sh with no arguments — all %d files\27[0m", #full))
print("")

local t0 = os.clock()
for _, rel in order do
	require("./" .. rel)
end

-- tier = "fast" in the structured result, which is what makes tools/verify.sh's
-- full/release reader REFUSE this run as suite evidence (D7): the banner is for
-- a human, the tier field is for the graph.
local ok = testkit.run({
	jsonOut = process.env.FACET_SUITE_JSON,
	tier = "fast",
	registeredSpecs = #order,
})
local elapsed = os.clock() - t0
local share = elapsed / FULL_SUITE_SECONDS

print("")
print(
	string.format(
		"\27[1;33m=== FACET-FAST-TIER: %.1fs = %.0f%% of the %.1fs full suite (%d of %d files) ===\27[0m",
		elapsed,
		share * 100,
		FULL_SUITE_SECONDS,
		#order,
		#full
	)
)
if share > FAST_TIER_BUDGET then
	print(
		string.format(
			"\27[1;31m    OVER BUDGET: the tier is meant to stay under %.0f%%. Re-measure with\27[0m",
			FAST_TIER_BUDGET * 100
		)
	)
	print("\27[1;31m    `lune run tools/lune/time_specs` and move the new heavyweight into tiers.SLOW.\27[0m")
end
print("\27[33m    A green fast tier is NOT a green suite. Run ./run-tests.sh before you claim one.\27[0m")
print("")

if not ok then
	process.exit(1)
end
