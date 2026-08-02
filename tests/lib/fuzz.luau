--!strict
-- Seeded, replayable property-fuzz harness (design §15.2, §17 Phase 4).
-- fuzz.run derives one seed per case from a base seed, runs the case under
-- pcall, and returns a report with every failure's replayable seed and a
-- deterministic run fingerprint (same base seed => same fingerprint), so a
-- green run is provably the same run tomorrow. fuzz.replayCase re-runs one
-- case seed WITHOUT pcall so the raw error surfaces for debugging.
-- Shared by the spec suite (small case counts) and tools/lune/fuzz (scaled).

local prng = require("./prng")

local fuzz = {}

export type Failure = { seed: number, case: number, error: string }
export type Report = {
	name: string,
	baseSeed: number,
	cases: number,
	failures: { Failure },
	fingerprint: number,
}

type RunOpts = {
	name: string,
	baseSeed: number,
	cases: number,
	case: (rng: prng.Prng) -> (),
}

local function mix(h: number, v: number): number
	-- FNV-ish 32-bit rolling combine, bit32-safe
	h = bit32.bxor(h, v % 4294967296)
	local lo = h % 65536
	local hi = math.floor(h / 65536)
	return (lo * 16777619 + hi * 40503) % 4294967296
end

function fuzz.run(opts: RunOpts): Report
	local seeder = prng.new(opts.baseSeed)
	local failures: { Failure } = {}
	local fingerprint = 2166136261
	for i = 1, opts.cases do
		local caseSeed = seeder:next()
		local rng = prng.new(caseSeed)
		local ok, err = pcall(opts.case, rng)
		fingerprint = mix(fingerprint, caseSeed)
		fingerprint = mix(fingerprint, (rng :: any).state)
		fingerprint = mix(fingerprint, if ok then 1 else 0)
		if not ok then
			table.insert(failures, { seed = caseSeed, case = i, error = tostring(err) })
		end
	end
	return {
		name = opts.name,
		baseSeed = opts.baseSeed,
		cases = opts.cases,
		failures = failures,
		fingerprint = fingerprint,
	}
end

-- replay one case seed with no pcall: the raw error (with stack) surfaces
function fuzz.replayCase(caseSeed: number, case: (rng: prng.Prng) -> ())
	case(prng.new(caseSeed))
end

return fuzz
