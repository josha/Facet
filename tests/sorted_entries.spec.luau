--!strict
--[[ `UI.sortedEntries` — DETERMINISTIC DICTIONARY ITERATION (fusion-comparison.md
	§5 gap G-3).

	`UI.ForEach` takes an ARRAY. A consumer holding a dictionary — a player-id →
	score map, a settings table — has to flatten it first, and the obvious flatten
	is wrong: Luau's `pairs` order is a function of the table's hash layout, and
	the hash layout is a function of the table's CONSTRUCTION HISTORY. Two
	dictionaries with identical contents, built in different orders, iterate
	differently. The row order of a leaderboard then depends on the order the
	players happened to join.

	WHY THIS FILE IS SHAPED THE WAY IT IS, AND WHAT MAKES IT ABLE TO FAIL. The
	single-run check the gap note proposed — "the same dictionary yields the same
	order twice" — PASSES WITH `pairs`. It is in this file as a named case
	(`the naive determinism check would pass with pairs`) precisely so nobody
	rebuilds it as the whole test: Luau's string hash is content-based and has no
	per-process seed, so two identical constructions iterate identically in every
	run of every process. Repetition is not the axis instability lives on.

	AND THE SIZE IS NOT ARBITRARY EITHER. Measured 2026-08-15, four constructions
	of the same twelve-key map:

	  insert ascending  player_1021,player_1014,player_1042,player_1028,player_1056,…
	  insert descending player_1070,player_1014,player_1042,player_1028,player_1056,…
	  insert shuffled   player_1021,player_1014,player_1042,player_1028,player_1077,…
	  after churn       player_1021,player_1014,player_1042,player_1035,player_1007,…

	At SIX keys the first three of those are byte-identical — only the churn case
	moves — so a six-element version of this file would have proved almost
	nothing, in exactly the way `tests/geometry_solve_coalescing.spec.luau`'s
	creation-order case had to be rebuilt from six memos to twelve for the same
	reason. The negative control below asserts the four orders really do disagree,
	so if a future Luau makes them agree this file says so out loud instead of
	going quietly green. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")

-- twelve player ids, the shape a score map actually has
local KEYS: { string } = {}
for i = 1, 12 do
	table.insert(KEYS, string.format("player_%d", 1000 + i * 7))
end

local ASCENDING, DESCENDING = {}, {}
for i = 1, 12 do
	table.insert(ASCENDING, i)
	table.insert(DESCENDING, 13 - i)
end
local SHUFFLED = { 5, 12, 1, 9, 3, 7, 11, 2, 8, 4, 10, 6 }

-- the same twelve pairs, reached four different ways
local function byInsertionOrder(order: { number }): { [string]: number }
	local d: { [string]: number } = {}
	for _, i in order do
		d[KEYS[i]] = i * 10
	end
	return d
end

local function byChurn(): { [string]: number }
	local d: { [string]: number } = {}
	for i = 1, 12 do
		d[KEYS[i]] = i * 10
		d["ghost_" .. i] = -1
	end
	for i = 1, 12 do
		d["ghost_" .. i] = nil
	end
	return d
end

local function constructions(): { { name: string, dict: { [string]: number } } }
	return {
		{ name = "ascending", dict = byInsertionOrder(ASCENDING) },
		{ name = "descending", dict = byInsertionOrder(DESCENDING) },
		{ name = "shuffled", dict = byInsertionOrder(SHUFFLED) },
		{ name = "churn", dict = byChurn() },
	}
end

local function rawOrder(dict: { [string]: any }): string
	local out: { string } = {}
	for k in dict do
		table.insert(out, tostring(k))
	end
	return table.concat(out, ",")
end

local function keyOrder(entries: { { key: any, value: any } }): string
	local out: { string } = {}
	for _, e in entries do
		table.insert(out, tostring(e.key))
	end
	return table.concat(out, ",")
end

describe("sortedEntries: the hazard it exists for", function()
	it("THE NEGATIVE CONTROL — the same twelve pairs iterate in DIFFERENT orders", function()
		-- If this ever goes green-by-agreement, every determinism assertion below
		-- became unfalsifiable and this file needs rebuilding, not celebrating.
		local seen: { [string]: string } = {}
		local distinct = 0
		for _, c in constructions() do
			local order = rawOrder(c.dict)
			if seen[order] == nil then
				seen[order] = c.name
				distinct += 1
			end
		end
		expect(distinct > 1).toBe(true)
		expect(distinct).toBe(4) -- measured 2026-08-15: all four disagree
	end)

	it("the naive determinism check would PASS with pairs — repetition is the wrong axis", function()
		--[[ This case asserts the BUG's behaviour deliberately. "Build it twice,
			compare" is what a determinism test looks like when nobody measured
			first, and it cannot fail: the hash is content-based with no process
			seed. The axis that moves is construction history, not repetition. ]]
		expect(rawOrder(byInsertionOrder(ASCENDING))).toBe(rawOrder(byInsertionOrder(ASCENDING)))
		expect(rawOrder(byChurn())).toBe(rawOrder(byChurn()))
	end)

	it("at SIX keys three of the four constructions agree — which is why this file uses twelve", function()
		local small: { string } = {}
		for i = 1, 6 do
			local d: { [string]: number } = {}
			local order = ({ { 1, 2, 3, 4, 5, 6 }, { 6, 5, 4, 3, 2, 1 }, { 5, 1, 3, 6, 2, 4 } })[math.min(i, 3)]
			for _, j in order do
				d[KEYS[j]] = j
			end
			table.insert(small, rawOrder(d))
		end
		expect(small[1]).toBe(small[2]) -- ascending == descending at this size
		expect(small[1]).toBe(small[3]) -- ...and == shuffled
	end)
end)

describe("sortedEntries: what it guarantees", function()
	it("every construction of the same dictionary yields ONE order", function()
		local expected: string? = nil
		for _, c in constructions() do
			local order = keyOrder(UI.sortedEntries(c.dict))
			if expected == nil then
				expected = order
			end
			expect(order).toBe(expected :: string)
		end
		-- and it is the order a reader can predict: ascending by key
		local sorted = table.clone(KEYS)
		table.sort(sorted)
		expect(expected).toBe(table.concat(sorted, ","))
	end)

	it("the values ride along, unchanged and not copied", function()
		local marker = { tag = "same table" }
		local entries = UI.sortedEntries({ a = marker, b = 2 })
		expect(#entries).toBe(2)
		expect(entries[1].key).toBe("a")
		expect(entries[1].value).toBe(marker) -- identity, not a clone
		expect(entries[2].value).toBe(2)
	end)

	it("numeric keys order NUMERICALLY, not lexicographically", function()
		local entries = UI.sortedEntries({ [9] = "nine", [10] = "ten", [100] = "hundred", [2] = "two" })
		expect(keyOrder(entries)).toBe("2,9,10,100")
	end)

	it("mixed number and string keys get one total order, deterministically", function()
		-- `1 < "a"` is an ERROR in Luau, so a default comparator that only wrote
		-- `a < b` would throw on the mixed map rather than order it. Numbers first,
		-- then strings; within a type, the natural order.
		local mixed: { [any]: any } = {}
		mixed[2] = "two"
		mixed.beta = "b"
		mixed[1] = "one"
		mixed.alpha = "a"
		expect(keyOrder(UI.sortedEntries(mixed))).toBe("1,2,alpha,beta")

		local other: { [any]: any } = {}
		other.alpha = "a"
		other[1] = "one"
		other.beta = "b"
		other[2] = "two"
		expect(keyOrder(UI.sortedEntries(other))).toBe("1,2,alpha,beta")
	end)

	it("an empty dictionary is an empty array, and the input is never mutated", function()
		local d = { a = 1 }
		expect(#UI.sortedEntries({})).toBe(0)
		UI.sortedEntries(d)
		expect(rawOrder(d)).toBe("a")
		expect(d.a).toBe(1)
	end)

	it("each call returns a FRESH array — a caller may sort or splice it", function()
		local d = { a = 1, b = 2 }
		local first, second = UI.sortedEntries(d), UI.sortedEntries(d)
		expect(first).never().toBe(second)
		table.remove(first, 1)
		expect(#second).toBe(2)
	end)
end)

describe("sortedEntries: the comparator", function()
	it("a caller-supplied key comparator is honoured, and stays deterministic", function()
		-- settings in a designed order rather than an alphabetical one
		local RANK = { music = 1, sfx = 2, haptics = 3, subtitles = 4, contrast = 5 }
		local function byRank(a: string, b: string): boolean
			return RANK[a] < RANK[b]
		end
		local expected: string? = nil
		for _, order in { { "music", "sfx", "haptics", "subtitles", "contrast" }, { "contrast", "haptics", "music", "subtitles", "sfx" } } do
			local d: { [string]: boolean } = {}
			for _, k in order do
				d[k] = true
			end
			local got = keyOrder(UI.sortedEntries(d, byRank))
			if expected == nil then
				expected = got
			end
			expect(got).toBe(expected :: string)
		end
		expect(expected).toBe("music,sfx,haptics,subtitles,contrast")
	end)

	it("the comparator receives KEYS, which is what makes the guarantee unconditional", function()
		local sawOnly: { [string]: boolean } = {}
		UI.sortedEntries({ a = 1, b = 2, c = 3 }, function(x, y)
			sawOnly[type(x)] = true
			sawOnly[type(y)] = true
			return x < y
		end)
		expect(sawOnly.string).toBe(true)
		expect(sawOnly.table).toBeNil() -- never handed the entry, so never the VALUE
	end)

	it("a key type with no natural order is REFUSED at construction, naming the comparator", function()
		local weird: { [any]: any } = {}
		weird[{ id = "a" }] = 1
		weird[{ id = "b" }] = 2
		local ok, err = pcall(UI.sortedEntries, weird)
		expect(ok).toBe(false)
		local message = tostring(err)
		expect(string.find(message, "sortedEntries", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "table", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "compare", 1, true) ~= nil).toBe(true)
	end)

	it("...and is accepted once the caller supplies one", function()
		local weird: { [any]: any } = {}
		local a, b = { id = "a" }, { id = "b" }
		weird[b] = 2
		weird[a] = 1
		local entries = UI.sortedEntries(weird, function(x, y)
			return x.id < y.id
		end)
		expect(entries[1].key).toBe(a)
		expect(entries[2].key).toBe(b)
	end)

	it("a non-table dictionary and a non-function comparator are refused BY NAME", function()
		-- All three of these would blow up anyway (you cannot iterate a string or
		-- call a string), so "it errored" proves nothing about the guards. What the
		-- guards buy is a message that says which helper and which argument, and
		-- that is what is asserted.
		for _, case in
			{
				{ dict = nil :: any, compare = nil :: any },
				{ dict = "not a table" :: any, compare = nil :: any },
				{ dict = { a = 1 } :: any, compare = "nope" :: any },
			}
		do
			local ok, err = pcall(UI.sortedEntries, case.dict, case.compare)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "LuauUI sortedEntries", 1, true) ~= nil).toBe(true)
		end
	end)
end)

describe("sortedEntries: through UI.ForEach", function()
	it("a dictionary signal drives a keyed region in one order whatever built it", function()
		--[[ The composition the helper is FOR: a memo flattens, `ForEach` keys off
			the entry key. The helper is pure on purpose — the reactive half is the
			`core:memo` a consumer already writes for every derived value, and making
			the helper build one would have forced it to take a core and a scope it
			has no other use for. ]]
		local rendered: { string } = {}
		for _, c in constructions() do
			local core = customFactory.new()
			local scores = core:signal(c.dict)
			local root = mountLib.mount(
				core,
				UI.ForEach({
					id = "Board",
					items = core:memo(function(use)
						return UI.sortedEntries(use(scores))
					end),
					key = function(entry)
						return entry.key
					end,
					row = function(entry)
						return UI.Text({ id = "Row", text = `{entry.key}: {entry.value}` })
					end,
				})
			)
			local paths: { string } = {}
			for _, child in root.node.children do
				table.insert(paths, child.path)
			end
			table.insert(rendered, table.concat(paths, "|"))
			root.dispose()
		end
		expect(rendered[2]).toBe(rendered[1])
		expect(rendered[3]).toBe(rendered[1])
		expect(rendered[4]).toBe(rendered[1])
		-- and the mounted paths really are the sorted keys, not an accident
		expect(string.find(rendered[1], "player_1007", 1, true) ~= nil).toBe(true)
		expect(string.sub(rendered[1], 1, #"/Board/[player_1007]")).toBe("/Board/[player_1007]")
	end)
end)
