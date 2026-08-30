--!strict
--[[ The shared word data the two word games run on.

	The word game used to ship six possible answers and thirty-four accepted
	guesses typed into its own source, so a player entering an ordinary English
	word was told it was not one. The replacement is generated from a pinned,
	hash-verified SCOWL release by `tools/build_word_lists.py`, and this file is
	what stops the generated half from drifting away from the recorded half.

	FINDING NOTHING IS A FAILURE HERE, NOT A PASS. Every count assertion below has
	a floor, and the drift case refuses a manifest that records no files at all —
	because the failure mode this file exists to catch is not "the data is wrong",
	it is "the data quietly became something else and every test about it still
	agreed with itself". ]]

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local words = require("../examples/gallery/examples/words")

local DATA_DIR = "examples/gallery/examples/words"

describe("example word data: provenance is recorded, not asserted", function()
	it("names a specific licensed archive, not just 'a dictionary'", function()
		local source = words.provenance.source
		expect(#source.name > 0).toBe(true)
		expect(string.find(source.name, "SCOWL", 1, true) ~= nil).toBe(true)
		-- A URL and a 64-character hex digest: the two facts that make the claim
		-- reproducible by someone who does not trust this repository.
		expect(string.sub(source.url, 1, 8)).toBe("https://")
		expect(#source.sha256).toBe(64)
		expect(string.match(source.sha256, "^[0-9a-f]+$") ~= nil).toBe(true)
	end)

	it("carries the licence notices the source requires", function()
		local prov = fs.readFile(DATA_DIR .. "/PROVENANCE.md")
		expect(string.find(prov, "Kevin Atkinson", 1, true) ~= nil).toBe(true)
		expect(string.find(prov, "Permission to use, copy, modify, distribute", 1, true) ~= nil).toBe(true)
		-- ...and the exact filters, so a reader can rebuild the same two sets
		expect(string.find(prov, "Transformations applied", 1, true) ~= nil).toBe(true)
		expect(string.find(prov, "tools/build_word_lists.py", 1, true) ~= nil).toBe(true)
	end)

	it("writes down the policy that produced the two sets", function()
		local policy = words.provenance.policy
		expect(policy.acceptedMaxTier > policy.solutionMaxTier).toBe(true)
		expect(policy.solutionLength).toBe(5)
		expect(#policy.droppedFromSolutions > 0).toBe(true)
	end)
end)

describe("example word data: the files on disk are the files that were generated", function()
	--[[ THE DRIFT CASE. A generated file edited by hand — to add a favourite
		word, or to remove an awkward one — changes what both games accept while
		every other test in this file keeps agreeing with the new data. The only
		thing that can notice is a hash recorded at generation time. ]]
	it("every generated file still hashes to what the manifest recorded", function()
		local files = words.provenance.files
		local checked = 0
		for name, recorded in files do
			local path = DATA_DIR .. "/" .. name
			expect(fs.isFile(path)).toBe(true)
			local actual = serde.hash("sha256", fs.readFile(path))
			if actual ~= recorded then
				error(
					`{name} has been edited since it was generated:\n`
						.. `      on disk   {actual}\n`
						.. `      recorded  {recorded}\n`
						.. `      Regenerate with: python3 tools/build_word_lists.py`,
					2
				)
			end
			checked += 1
		end
		-- Trap 4 from the manifest checker, applied here: a manifest that records
		-- nothing would pass a loop over its own emptiness.
		expect(checked >= 7).toBe(true)
	end)

	it("the manifest's counts are the counts the banks actually hold", function()
		local counts = words.provenance.counts
		local seen = 0
		for lengthKey, recorded in counts do
			local length = tonumber(lengthKey) :: number
			expect(words.bankCount(length)).toBe(recorded)
			seen += 1
		end
		expect(seen).toBe(6)
		expect(words.solutionCount).toBe(words.provenance.solutionCount)
	end)
end)

describe("example word data: the banks are searchable", function()
	--[[ THE INVARIANT THE LOOKUP DEPENDS ON. Each bank is one fixed-width run
		searched by bisection, so a single out-of-order entry does not make one
		word unfindable — it makes an arbitrary set of them unfindable, silently,
		with no error anywhere. Sortedness is therefore not a tidiness check. ]]
	it("every bank is strictly ascending and exactly divisible by its width", function()
		for length = words.MIN_LENGTH, words.MAX_LENGTH do
			local count = words.bankCount(length)
			expect(count > 0).toBe(true)
			local bank = require("../examples/gallery/examples/words/len" .. tostring(length)) :: any
			expect(#bank.packed).toBe(count * length)
			local previous = ""
			for i = 1, count do
				local at = (i - 1) * length + 1
				local word = string.sub(bank.packed, at, at + length - 1)
				if word <= previous then
					error(`length-{length} bank is out of order at entry {i}: "{previous}" then "{word}"`, 2)
				end
				previous = word
			end
		end
	end)

	it("the solution bank is ascending too, and every answer is an accepted guess", function()
		local previous = ""
		local notAccepted = {}
		for i = 1, words.solutionCount do
			local word = words.solutionAt(i)
			expect(word > previous).toBe(true)
			previous = word
			if not words.isWord(word) then
				table.insert(notAccepted, word)
			end
		end
		-- An answer the game would refuse as a guess makes the puzzle unwinnable,
		-- and neither list can see that on its own.
		if #notAccepted > 0 then
			error(`{#notAccepted} answer(s) are not accepted guesses, e.g. {notAccepted[1]}`, 2)
		end
	end)
end)

describe("example word data: it accepts what a player would type", function()
	it("is broad — thousands of five-letter guesses, and a smaller reviewed answer set", function()
		expect(words.bankCount(5) > 3000).toBe(true)
		expect(words.solutionCount > 1000).toBe(true)
		-- ...and the answers really are the smaller, more familiar half
		expect(words.solutionCount < words.bankCount(5)).toBe(true)
	end)

	it("accepts an ordinary word starting with every letter of the alphabet", function()
		local sample = {
			"angry",
			"brave",
			"cider",
			"dwell",
			"eager",
			"flint",
			"grasp",
			"hoard",
			"inept",
			"jolly",
			"knelt",
			"lunar",
			"mocha",
			"ninja",
			"onion",
			"pilot",
			"quilt",
			"risen",
			"sushi",
			"tiger",
			"usher",
			"vowel",
			"widen",
			"xenon",
			"yacht",
			"zebra",
		}
		expect(#sample).toBe(26)
		local refused = {}
		for _, word in sample do
			if not words.isWord(word) then
				table.insert(refused, word)
			end
		end
		if #refused > 0 then
			error(`refused ordinary words: {table.concat(refused, ", ")}`, 2)
		end
	end)

	it("accepts a guess in any dialect, while an answer keeps one spelling", function()
		--[[ FOUND BY THE CROSSWORD GAME, writing a test: `axe` was refused. SCOWL
			files it under `british-words`, and an American-only filter therefore
			refused `grey`, `colour`, `theatre`, `centre`, `favour`, `litre`,
			`cheque`, `kerb`, `tyre` and `pyjamas` too — the exact failure this data
			replaced, reappearing one dialect over.

			The two sets diverge on purpose: a puzzle whose ANSWER is `colour` is
			unfair to half its players and `color` to the other half, so answers keep
			one convention while guesses accept both. ]]
		local refused = {}
		for _, word in { "axe", "grey", "colour", "theatre", "centre", "favour", "litre", "cheque", "kerb", "tyre" } do
			if not words.isWord(word) then
				table.insert(refused, word)
			end
		end
		if #refused > 0 then
			error(`a dialect spelling is still refused: {table.concat(refused, ", ")}`, 2)
		end
		-- ...and the answer set did NOT widen with it
		expect(words.isSolution("color")).toBe(true)
		expect(words.isSolution("colour")).toBe(false)
		expect(words.provenance.policy.solutionDialects ~= nil).toBe(true)
		expect(#words.provenance.policy.acceptDialects > #words.provenance.policy.solutionDialects).toBe(true)
	end)

	it("accepts the words the old hand-written list rejected", function()
		--[[ The point of the whole replacement, stated as its own case. Every one
			of these is a word a player would reasonably try; the previous
			thirty-four-word list accepted none of them. ]]
		for _, word in { "adieu", "fjord", "salsa", "ramen", "mocha", "waltz", "nymph", "glyph", "zesty" } do
			if not words.isWord(word) then
				error(`"{word}" is still refused — the point of the new data was that it would not be`, 2)
			end
		end
	end)

	it("accepts the inflections the source policy keeps", function()
		-- SCOWL's `-words` classes carry plurals and past tenses; they stay
		-- ACCEPTED as guesses even though the answer set drops them.
		for _, word in { "cakes", "asked", "tacos", "boxes" } do
			expect(words.isWord(word)).toBe(true)
		end
		-- ...and the answer set really did drop that shape
		expect(words.isSolution("asked")).toBe(false)
		expect(words.isSolution("cakes")).toBe(false)
	end)

	it("refuses obvious nonwords, wrong lengths, and anything that is not plain letters", function()
		for _, notAWord in { "plztk", "qqqqq", "zzzzz", "xkcdq" } do
			expect(words.isWord(notAWord)).toBe(false)
		end
		expect(words.isWord("a")).toBe(false)
		expect(words.isWord("elephants")).toBe(false)
		expect(words.isWord("")).toBe(false)
		-- A bisection over a fixed-width run compares bytes, so a digit or a space
		-- would ORDER itself among the words rather than miss. The shape is
		-- rejected before the search, and this is the case that says so.
		expect(words.isWord("cr4ne")).toBe(false)
		expect(words.isWord("cr ne")).toBe(false)
		expect(words.isWord("CRANE-")).toBe(false)
	end)

	it("does not care what case the letters arrived in", function()
		expect(words.isWord("CRANE")).toBe(true)
		expect(words.isWord("CrAnE")).toBe(true)
		expect(words.isSolution(string.upper(words.solutionAt(1)))).toBe(true)
	end)
end)

describe("example word data: a seed is a puzzle, and always the same puzzle", function()
	it("the same seed always chooses the same answer", function()
		for _, seed in { 1, 2, 7, 41, 1000, 65535 } do
			expect(words.solutionForSeed(seed)).toBe(words.solutionForSeed(seed))
			expect(words.isSolution(words.solutionForSeed(seed))).toBe(true)
		end
	end)

	it("consecutive seeds are not consecutive words", function()
		--[[ `seed % count` over an alphabetical list gives "aback", "abate",
			"abbey" — a player who restarts twice gets two words beginning with the
			same two letters, which reads as a broken game. The mix is what stops
			that, so it is asserted rather than left as an implementation detail. ]]
		local first = words.solutionForSeed(1)
		local second = words.solutionForSeed(2)
		expect(string.sub(first, 1, 2) == string.sub(second, 1, 2)).toBe(false)
	end)

	it("every answer is reachable, and the mapping wraps rather than erroring", function()
		local seen: { [string]: boolean } = {}
		local distinct = 0
		for seed = 1, 20000 do
			local word = words.solutionForSeed(seed)
			if not seen[word] then
				seen[word] = true
				distinct += 1
			end
		end
		expect(distinct).toBe(words.solutionCount)
		-- a seed outside any sensible range is a wrap, not a crash
		expect(words.isSolution(words.solutionForSeed(0))).toBe(true)
		expect(words.isSolution(words.solutionForSeed(1e6))).toBe(true)
	end)

	it("an out-of-range index is refused rather than silently clamped", function()
		expect(function()
			words.solutionAt(0)
		end).toThrow()
		expect(function()
			words.solutionAt(words.solutionCount + 1)
		end).toThrow()
	end)
end)

describe("example word data: the lookup is cheap enough to sit under a keystroke", function()
	it("a hit and a miss both cost a bisection, not a scan", function()
		--[[ MEASURED, not asserted from the algorithm: the whole reason the data is
			a packed string is that a set of 36,601 entries costs its allocation on
			every device that loads it. If a change ever turns this into a scan, the
			game still works and only the phone notices — so the budget lives here.

			The bound is deliberately loose (a hundred times the measured 0.39 us)
			because this runs on whatever machine the suite runs on; it exists to
			catch an order-of-magnitude regression, not to police noise. ]]
		local reps = 20000
		local start = os.clock()
		local hits = 0
		for _ = 1, reps do
			if words.isWord("crane") then
				hits += 1
			end
			if words.isWord("plztk") then
				hits += 1
			end
		end
		local perLookupUs = (os.clock() - start) * 1e6 / (reps * 2)
		expect(hits).toBe(reps)
		if perLookupUs > 40 then
			error(`a word lookup costs {string.format("%.1f", perLookupUs)} us; the budget is 40`, 2)
		end
	end)
end)
