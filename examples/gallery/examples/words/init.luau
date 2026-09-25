--!strict

local len2 = require("@self/len2")
local len3 = require("@self/len3")
local len4 = require("@self/len4")
local len5 = require("@self/len5")
local len6 = require("@self/len6")
local len7 = require("@self/len7")
local solutions = require("@self/solutions")
local manifest = require("@self/manifest")

export type Bank = { length: number, count: number, packed: string }

local words = {}

local BANKS: { [number]: Bank } = table.freeze({
	[2] = len2,
	[3] = len3,
	[4] = len4,
	[5] = len5,
	[6] = len6,
	[7] = len7,
})

words.MIN_LENGTH = 2
words.MAX_LENGTH = 7
words.SOLUTION_LENGTH = 5

function words.normalize(raw: string): string
	return string.lower(raw)
end

local function inBank(bank: Bank, word: string): boolean
	local length, count, packed = bank.length, bank.count, bank.packed
	local lo, hi = 1, count
	while lo <= hi do
		local mid = (lo + hi) // 2
		local at = (mid - 1) * length + 1
		local candidate = string.sub(packed, at, at + length - 1)
		if candidate == word then
			return true
		elseif candidate < word then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return false
end

function words.isWord(raw: string): boolean
	local word = words.normalize(raw)
	local bank = BANKS[#word]
	if bank == nil then
		return false
	end

	if string.match(word, "^%l+$") == nil then
		return false
	end
	return inBank(bank, word)
end

words.solutionCount = solutions.count

function words.solutionAt(index: number): string
	local n = solutions.count
	assert(index == math.floor(index), "words.solutionAt: index must be a whole number")
	assert(index >= 1 and index <= n, `words.solutionAt: index {index} is outside 1..{n}`)
	local at = (index - 1) * solutions.length + 1
	return string.sub(solutions.packed, at, at + solutions.length - 1)
end

function words.isSolution(raw: string): boolean
	local word = words.normalize(raw)
	if #word ~= solutions.length or string.match(word, "^%l+$") == nil then
		return false
	end
	return inBank(solutions, word)
end

function words.solutionForSeed(seed: number): string
	local n = solutions.count
	local mixed = (math.floor(seed) % 1048576) * 2654435 % 16777213
	local index = mixed % n + 1
	return words.solutionAt(index)
end

function words.bankCount(length: number): number
	local bank = BANKS[length]
	return if bank == nil then 0 else bank.count
end

words.provenance = manifest

return table.freeze(words)
