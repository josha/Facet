--!strict
-- The proof's seeded pseudo-random source. `math.random` is FORBIDDEN in proof
-- domain logic (responsibility ledger) for one reason: a scenario reset has to
-- reproduce a byte-identical dump, and a shared global generator cannot promise
-- that when two services draw from it in a different order.
--
-- So this is a Lehmer / Park-Miller generator with its own state per instance:
-- pure, tiny, and deterministic in both the number it answers and the number of
-- draws it takes to answer it.
local rng = {}

local M = 2147483647
local A = 16807

function rng.new(seed: number?): any
	local state = math.floor(seed or 1) % M
	if state <= 0 then
		state += M - 1
	end
	-- WARM-UP, and it is load-bearing. A Lehmer generator's first output is
	-- state * A / M, so two seeds one apart answer two numbers 0.0000078 apart —
	-- and `seed * 31 + index` per potion gave seventeen potions the SAME
	-- "random" popularity (measured, 2026-08-08). Five discarded draws spread
	-- adjacent seeds across the whole range before anyone reads one.
	for _ = 1, 5 do
		state = (state * A) % M
	end
	local self = {}

	-- a float in (0, 1)
	function self.next(): number
		state = (state * A) % M
		return state / M
	end

	-- an integer in [lo, hi], both inclusive
	function self.int(lo: number, hi: number): number
		if hi <= lo then
			return lo
		end
		return lo + math.floor(self.next() * (hi - lo + 1))
	end

	-- an element of `list`
	function self.pick(list: { any }): any
		return list[self.int(1, #list)]
	end

	function self.state(): number
		return state
	end

	return self
end

return table.freeze(rng)
