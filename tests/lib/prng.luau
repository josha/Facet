--!strict
-- Deterministic seeded PRNG for the Phase 4 property-fuzz harness (design
-- §15.2). xorshift32 over bit32: identical sequences for identical seeds on
-- every platform Lune runs on — no math.random, no clock. Every fuzz failure
-- is replayable from its recorded seed alone.

local prng = {}

export type Prng = {
	state: number,
	next: (self: Prng) -> number,
	range: (self: Prng, low: number, high: number) -> number,
	float: (self: Prng) -> number,
	bool: (self: Prng, probability: number?) -> boolean,
	pick: <T>(self: Prng, list: { T }) -> T,
	fork: (self: Prng) -> Prng,
}

local Prng = {}
Prng.__index = Prng

function prng.new(seed: number): Prng
	local state = math.floor(seed) % 4294967296
	if state == 0 then
		state = 2463534242 -- xorshift must never sit at 0
	end
	return setmetatable({ state = state }, Prng) :: any
end

function Prng.next(self: any): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- inclusive integer range
function Prng.range(self: any, low: number, high: number): number
	assert(high >= low, "prng:range(low, high) needs high >= low")
	return low + self:next() % (high - low + 1)
end

function Prng.float(self: any): number
	return self:next() / 4294967296
end

function Prng.bool(self: any, probability: number?): boolean
	return self:float() < (probability or 0.5)
end

function Prng.pick<T>(self: any, list: { T }): T
	assert(#list > 0, "prng:pick on an empty list")
	return list[self:range(1, #list)]
end

-- independent child stream (derives from, then advances, this stream)
function Prng.fork(self: any): Prng
	return prng.new(bit32.bxor(self:next(), 2654435769))
end

return prng
