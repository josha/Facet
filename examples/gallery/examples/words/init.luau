--!strict
--[[ The shared English word data both word games use.

	This is EXAMPLE DOMAIN CONTENT, not framework code. A user-interface library
	has no opinion about English, so nothing here reaches into `src/` and nothing
	in `src/` knows this exists. The word game asks "is this an accepted guess"
	and "what is today's answer"; the crossword asks "is this line a word" at
	several lengths; both questions are answered here and nowhere else.

	WHERE THE WORDS COME FROM: `PROVENANCE.md` beside this file — a pinned,
	hash-verified SCOWL release, the licence notices it requires, the exact
	filters applied, and the command that regenerates it. Nothing was typed by
	hand and nothing is fetched at runtime.

	WHY THE DATA IS A STRING AND NOT A TABLE. Each length is one sorted,
	fixed-width run of characters, and a lookup is a binary search over character
	offsets into it. 6,421 five-letter words cost 32 KB of string and zero table
	allocation at load; the same words as a set would be 6,421 table entries built
	on the first require, on a device where that allocation is the expensive part.
	The search is about thirteen five-character comparisons. Measured cost is in
	`PROVENANCE.md`.
]]

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

-- Keyed by length so a lookup never scans a bank it cannot match.
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

--[[ The one place a player's typing becomes a lookup key.

	Both games take letters from several routes — a hardware key, an on-screen
	key, a rack tile, a placement — and they do not all arrive in the same case.
	Normalising in one function is what stops "Crane" and "CRANE" from being two
	different answers to the same question. ]]
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

--[[ Is this an accepted guess?

	Deliberately generous — a player who types a real word and is told it is not
	one blames the game, and is right to. The set is every SCOWL word up to size
	70 at lengths two through seven: 36,601 of them. Anything outside the length
	range, or carrying a character that is not a plain lowercase letter, is not a
	word this game knows, and that is a different sentence from "that is not
	English". ]]
function words.isWord(raw: string): boolean
	local word = words.normalize(raw)
	local bank = BANKS[#word]
	if bank == nil then
		return false
	end
	-- A binary search over a fixed-width run compares BYTES, so one non-letter
	-- would silently order itself among the words rather than miss. Reject the
	-- shape first; the search then only ever sees keys the bank could contain.
	if string.match(word, "^%l+$") == nil then
		return false
	end
	return inBank(bank, word)
end

--[[ The answers the five-letter game may choose.

	A much smaller, more conservative set than the accepted guesses: familiar
	words only, minus simple plurals and past tenses, because an answer nobody
	knows is not a puzzle and "asked" is a poor one. Every entry here is also an
	accepted guess — the generator refuses to write these files when that is
	untrue, since such a puzzle cannot be won and neither list can see the problem
	alone. ]]
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

--[[ A seed picks an answer, and the same seed always picks the same one.

	The game's restart is a seed change, so this has to be a pure function of the
	seed rather than a draw from a running generator: a test that replays a seed
	has to get the puzzle it replayed.

	THE SEED IS MIXED, NOT INDEXED. `seed % count` reads well and plays badly: the
	list is alphabetical, so seed 1 is "aback", seed 2 is "abate", and a player who
	restarts twice gets two words beginning with the same two letters. The mix is
	one multiply-and-fold — deterministic, no state, and the same on every
	platform because both constants stay well inside a double's exact-integer
	range. ]]
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

-- The generated manifest: source identity, the filter policy, per-file hashes.
-- The drift spec reads this and re-hashes the files beside it, so word data
-- edited by hand fails a test instead of quietly changing what the games accept.
words.provenance = manifest

return table.freeze(words)
