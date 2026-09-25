--!strict

local rng = {}

local M = 2147483647
local A = 16807

function rng.new(seed: number?): any
	local state = math.floor(seed or 1) % M
	if state <= 0 then
		state += M - 1
	end

	for _ = 1, 5 do
		state = (state * A) % M
	end
	local self = {}

	function self.next(): number
		state = (state * A) % M
		return state / M
	end

	function self.int(lo: number, hi: number): number
		if hi <= lo then
			return lo
		end
		return lo + math.floor(self.next() * (hi - lo + 1))
	end

	function self.pick(list: { any }): any
		return list[self.int(1, #list)]
	end

	function self.state(): number
		return state
	end

	return self
end

return table.freeze(rng)
