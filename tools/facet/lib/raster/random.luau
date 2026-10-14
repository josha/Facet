--!strict

local Numeric = require("./numeric")

local mul32 = Numeric.mul32

local INIT_A = 0x43B0D7E5
local MULT_A = 0x931E8875
local INIT_B = 0x8B51F9DD
local MULT_B = 0x58F38DED
local MIX_MULT_L = 0xCA01F9DD
local MIX_MULT_R = 0x4973F715
local TWO32 = 4294967296

local MULTIPLIER = { 0xF645, 0x9FCC, 0xDF64, 0x4385, 0x5DA4, 0x1FC6, 0xED05, 0x2360 }

export type Generator = {
	random: (self: Generator) -> number,
	randomArray: (self: Generator, count: number) -> { number },
	integers: (self: Generator, low: number, high: number, count: number) -> { number },
}

type State = {
	state: { number },
	increment: { number },
	cached: number?,
}

local function seedWords(seed: number): { number }
	if seed < 0 or seed ~= math.floor(seed) then
		error("seed must be a nonnegative integer", 3)
	end
	local words: { number } = {}
	local remaining = seed
	repeat
		table.insert(words, remaining % TWO32)
		remaining = remaining // TWO32
	until remaining == 0
	return words
end

local function hashMix(value: number, constant: { number }): number
	value = bit32.bxor(value, constant[1])
	constant[1] = mul32(constant[1], MULT_A)
	value = mul32(value, constant[1])
	return bit32.bxor(value, bit32.rshift(value, 16))
end

local function mix(x: number, y: number): number
	local result = (mul32(MIX_MULT_L, x) - mul32(MIX_MULT_R, y)) % TWO32
	return bit32.bxor(result, bit32.rshift(result, 16))
end

local function seedSequenceState(seed: number, words: number): { number }
	local entropy = seedWords(seed)
	local pool = table.create(4, 0)
	local constant = { INIT_A }
	for index = 1, 4 do
		pool[index] = hashMix(entropy[index] or 0, constant)
	end
	for source = 1, 4 do
		for target = 1, 4 do
			if source ~= target then
				pool[target] = mix(pool[target], hashMix(pool[source], constant))
			end
		end
	end
	for index = 5, #entropy do
		for target = 1, 4 do
			pool[target] = mix(pool[target], hashMix(entropy[index], constant))
		end
	end
	local out = table.create(words, 0)
	local hashConstant = INIT_B
	for index = 1, words do
		local value = pool[(index - 1) % 4 + 1]
		value = bit32.bxor(value, hashConstant)
		hashConstant = mul32(hashConstant, MULT_B)
		value = mul32(value, hashConstant)
		out[index] = bit32.bxor(value, bit32.rshift(value, 16))
	end
	return out
end

local function limbs(high: number, highLow: number, lowHigh: number, low: number): { number }
	return {
		low % 65536,
		low // 65536,
		lowHigh % 65536,
		lowHigh // 65536,
		highLow % 65536,
		highLow // 65536,
		high % 65536,
		high // 65536,
	}
end

local function add128(a: { number }, b: { number }): { number }
	local out = table.create(8, 0)
	local carry = 0
	for index = 1, 8 do
		local sum = a[index] + b[index] + carry
		out[index] = sum % 65536
		carry = sum // 65536
	end
	return out
end

local function mul128(a: { number }, b: { number }): { number }
	local out = table.create(8, 0)
	for i = 1, 8 do
		local ai = a[i]
		if ai ~= 0 then
			for j = 1, 9 - i do
				out[i + j - 1] += ai * b[j]
			end
		end
	end
	local carry = 0
	for index = 1, 8 do
		local sum = out[index] + carry
		out[index] = sum % 65536
		carry = sum // 65536
	end
	return out
end

local function step(state: State)
	state.state = add128(mul128(state.state, MULTIPLIER), state.increment)
end

local function next64(state: State): (number, number)
	step(state)
	local s = state.state
	local high = bit32.bxor(s[8] * 65536 + s[7], s[4] * 65536 + s[3])
	local low = bit32.bxor(s[6] * 65536 + s[5], s[2] * 65536 + s[1])
	local rotation = s[8] // 1024
	if rotation == 0 then
		return high, low
	elseif rotation < 32 then
		return bit32.bor(bit32.rshift(high, rotation), bit32.lshift(low, 32 - rotation)),
			bit32.bor(bit32.rshift(low, rotation), bit32.lshift(high, 32 - rotation))
	elseif rotation == 32 then
		return low, high
	end
	local shift = rotation - 32
	return bit32.bor(bit32.rshift(low, shift), bit32.lshift(high, 32 - shift)),
		bit32.bor(bit32.rshift(high, shift), bit32.lshift(low, 32 - shift))
end

local function nextDouble(state: State): number
	local high, low = next64(state)
	return (high * 2097152 + bit32.rshift(low, 11)) * (1.0 / 9007199254740992.0)
end

local function next32(state: State): number
	local cached = state.cached
	if cached ~= nil then
		state.cached = nil
		return cached
	end
	local high, low = next64(state)
	state.cached = high
	return low
end

local Random = {}

function Random.new(seed: number): Generator
	local words = seedSequenceState(seed, 8)
	local seedHigh = limbs(words[2], words[1], words[4], words[3])
	local increment = limbs(words[6], words[5], words[8], words[7])
	local shifted = table.create(8, 0)
	local carry = 1
	for index = 1, 8 do
		local doubled = increment[index] * 2 + carry
		shifted[index] = doubled % 65536
		carry = doubled // 65536
	end
	local state: State = { state = table.create(8, 0), increment = shifted, cached = nil }
	step(state)
	state.state = add128(state.state, seedHigh)
	step(state)

	local generator = {}

	function generator.random(_self: Generator): number
		return nextDouble(state)
	end

	function generator.randomArray(_self: Generator, count: number): { number }
		local out = table.create(count, 0)
		for index = 1, count do
			out[index] = nextDouble(state)
		end
		return out
	end

	function generator.integers(_self: Generator, low: number, high: number, count: number): { number }
		local range = high - low
		if range < 1 or range > 2097152 then
			error("integers supports ranges from 1 to 2^21", 2)
		end
		local out = table.create(count, 0)
		local threshold = (TWO32 - 1 - (range - 1)) % range
		for index = 1, count do
			local product = next32(state) * range
			local leftover = product % TWO32
			if leftover < range then
				while leftover < threshold do
					product = next32(state) * range
					leftover = product % TWO32
				end
			end
			out[index] = low + product // TWO32
		end
		return out
	end

	return generator :: Generator
end

return table.freeze(Random)
