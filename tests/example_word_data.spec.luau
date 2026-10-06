--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local expect = Verify.expect

	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local words = require("../examples/gallery/examples/words")

	local DATA_DIR = "examples/gallery/examples/words"

	verifyHarness:suite("example word data: provenance is recorded, not asserted", function()
		verifyHarness:case("names a specific licensed archive, not just 'a dictionary'", {
			id = "example_word_data::example word data: provenance is recorded, not asserted::names a specific licensed archive, not just 'a dictionary'",
			run = function()
				local source = words.provenance.source
				expect(#source.name > 0):toBe(true)
				expect(string.find(source.name, "SCOWL", 1, true) ~= nil):toBe(true)

				expect((string.sub(source.url, 1, 8))):toBe("https://")
				expect(#source.sha256):toBe(64)
				expect(string.match(source.sha256, "^[0-9a-f]+$") ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("carries the licence notices the source requires", {
			id = "example_word_data::example word data: provenance is recorded, not asserted::carries the licence notices the source requires",
			run = function()
				local prov = fs.readFile(DATA_DIR .. "/PROVENANCE.md")
				expect(string.find(prov, "Kevin Atkinson", 1, true) ~= nil):toBe(true)
				expect(string.find(prov, "Permission to use, copy, modify, distribute", 1, true) ~= nil):toBe(true)

				expect(string.find(prov, "Transformations applied", 1, true) ~= nil):toBe(true)
				expect(string.find(prov, "tools/build_word_lists.py", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("writes down the policy that produced the two sets", {
			id = "example_word_data::example word data: provenance is recorded, not asserted::writes down the policy that produced the two sets",
			run = function()
				local policy = words.provenance.policy
				expect(policy.acceptedMaxTier > policy.solutionMaxTier):toBe(true)
				expect(policy.solutionLength):toBe(6)
				expect(#policy.droppedFromSolutions > 0):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("example word data: the files on disk are the files that were generated", function()
		verifyHarness:case("every generated file still hashes to what the manifest recorded", {
			id = "example_word_data::example word data: the files on disk are the files that were generated::every generated file still hashes to what the manifest recorded",
			run = function()
				local files: { [string]: string } = words.provenance.files
				local checked = 0
				for name, recorded in files do
					local path = DATA_DIR .. "/" .. name
					expect((fs.isFile(path))):toBe(true)
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

				expect(checked >= 7):toBe(true)
			end,
		})

		verifyHarness:case("the manifest's counts are the counts the banks actually hold", {
			id = "example_word_data::example word data: the files on disk are the files that were generated::the manifest's counts are the counts the banks actually hold",
			run = function()
				local counts = words.provenance.counts
				local seen = 0
				for lengthKey, recorded in counts do
					local length = tonumber(lengthKey) :: number
					expect((words.bankCount(length))):toBe(recorded)
					seen += 1
				end
				expect(seen):toBe(6)
				expect(words.solutionCount):toBe(words.provenance.solutionCount)
			end,
		})
	end)

	verifyHarness:suite("example word data: the banks are searchable", function()
		verifyHarness:case("every bank is strictly ascending and exactly divisible by its width", {
			id = "example_word_data::example word data: the banks are searchable::every bank is strictly ascending and exactly divisible by its width",
			run = function()
				for length = words.MIN_LENGTH, words.MAX_LENGTH do
					local count = words.bankCount(length)
					expect(count > 0):toBe(true)
					local bank = require("../examples/gallery/examples/words/len" .. tostring(length)) :: any
					expect(#bank.packed):toBe(count * length)
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
			end,
		})

		verifyHarness:case("the solution bank is ascending too, and every answer is an accepted guess", {
			id = "example_word_data::example word data: the banks are searchable::the solution bank is ascending too, and every answer is an accepted guess",
			run = function()
				local previous = ""
				local notAccepted = {}
				for i = 1, words.solutionCount do
					local word = words.solutionAt(i)
					expect(word > previous):toBe(true)
					previous = word
					if not words.isWord(word) then
						table.insert(notAccepted, word)
					end
				end

				if #notAccepted > 0 then
					error(`{#notAccepted} answer(s) are not accepted guesses, e.g. {notAccepted[1]}`, 2)
				end
			end,
		})
	end)

	verifyHarness:suite("example word data: it accepts what a player would type", function()
		verifyHarness:case("is broad — thousands of six-letter guesses, and a smaller reviewed answer set", {
			id = "example_word_data::example word data: it accepts what a player would type::is broad — thousands of six-letter guesses, and a smaller reviewed answer set",
			run = function()
				expect(words.bankCount(6) > 3000):toBe(true)
				expect(words.solutionCount > 1000):toBe(true)

				expect(words.solutionCount < words.bankCount(6)):toBe(true)
			end,
		})

		verifyHarness:case("accepts an ordinary word starting with every letter of the alphabet", {
			id = "example_word_data::example word data: it accepts what a player would type::accepts an ordinary word starting with every letter of the alphabet",
			run = function()
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
				expect(#sample):toBe(26)
				local refused = {}
				for _, word in sample do
					if not words.isWord(word) then
						table.insert(refused, word)
					end
				end
				if #refused > 0 then
					error(`refused ordinary words: {table.concat(refused, ", ")}`, 2)
				end
			end,
		})

		verifyHarness:case("accepts a guess in any dialect, while an answer keeps one spelling", {
			id = "example_word_data::example word data: it accepts what a player would type::accepts a guess in any dialect, while an answer keeps one spelling",
			run = function()
				local refused = {}
				for _, word in
					{ "axe", "grey", "colour", "theatre", "centre", "favour", "litre", "cheque", "kerb", "tyre" }
				do
					if not words.isWord(word) then
						table.insert(refused, word)
					end
				end
				if #refused > 0 then
					error(`a dialect spelling is still refused: {table.concat(refused, ", ")}`, 2)
				end

				expect((words.isSolution("center"))):toBe(true)
				expect((words.isSolution("centre"))):toBe(false)
				expect(words.provenance.policy.solutionDialects ~= nil):toBe(true)
				expect(#words.provenance.policy.acceptDialects > #words.provenance.policy.solutionDialects):toBe(true)
			end,
		})

		verifyHarness:case("accepts the words the old hand-written list rejected", {
			id = "example_word_data::example word data: it accepts what a player would type::accepts the words the old hand-written list rejected",
			run = function()
				for _, word in { "adieu", "fjord", "salsa", "ramen", "mocha", "waltz", "nymph", "glyph", "zesty" } do
					if not words.isWord(word) then
						error(`"{word}" is still refused — the point of the new data was that it would not be`, 2)
					end
				end
			end,
		})

		verifyHarness:case("accepts the inflections the source policy keeps", {
			id = "example_word_data::example word data: it accepts what a player would type::accepts the inflections the source policy keeps",
			run = function()
				for _, word in { "cakes", "asked", "tacos", "boxes" } do
					expect((words.isWord(word))):toBe(true)
				end

				expect((words.isSolution("asked"))):toBe(false)
				expect((words.isSolution("cakes"))):toBe(false)
			end,
		})

		verifyHarness:case("refuses obvious nonwords, wrong lengths, and anything that is not plain letters", {
			id = "example_word_data::example word data: it accepts what a player would type::refuses obvious nonwords, wrong lengths, and anything that is not plain letters",
			run = function()
				for _, notAWord in { "plztk", "qqqqq", "zzzzz", "xkcdq" } do
					expect((words.isWord(notAWord))):toBe(false)
				end
				expect((words.isWord("a"))):toBe(false)
				expect((words.isWord("elephants"))):toBe(false)
				expect((words.isWord(""))):toBe(false)

				expect((words.isWord("cr4ne"))):toBe(false)
				expect((words.isWord("cr ne"))):toBe(false)
				expect((words.isWord("CRANE-"))):toBe(false)
			end,
		})

		verifyHarness:case("does not care what case the letters arrived in", {
			id = "example_word_data::example word data: it accepts what a player would type::does not care what case the letters arrived in",
			run = function()
				expect((words.isWord("CRANE"))):toBe(true)
				expect((words.isWord("CrAnE"))):toBe(true)
				expect((words.isSolution(string.upper(words.solutionAt(1))))):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("example word data: a seed is a puzzle, and always the same puzzle", function()
		verifyHarness:case("the same seed always chooses the same answer", {
			id = "example_word_data::example word data: a seed is a puzzle, and always the same puzzle::the same seed always chooses the same answer",
			run = function()
				for _, seed in { 1, 2, 7, 41, 1000, 65535 } do
					expect((words.solutionForSeed(seed))):toBe(words.solutionForSeed(seed))
					expect((words.isSolution(words.solutionForSeed(seed)))):toBe(true)
				end
			end,
		})

		verifyHarness:case("consecutive seeds are not consecutive words", {
			id = "example_word_data::example word data: a seed is a puzzle, and always the same puzzle::consecutive seeds are not consecutive words",
			run = function()
				local first = words.solutionForSeed(1)
				local second = words.solutionForSeed(2)
				expect(string.sub(first, 1, 2) == string.sub(second, 1, 2)):toBe(false)
			end,
		})

		verifyHarness:case("every answer is reachable, and the mapping wraps rather than erroring", {
			id = "example_word_data::example word data: a seed is a puzzle, and always the same puzzle::every answer is reachable, and the mapping wraps rather than erroring",
			run = function()
				local seen: { [string]: boolean } = {}
				local distinct = 0
				for seed = 1, 1048576 do
					local word = words.solutionForSeed(seed)
					if not seen[word] then
						seen[word] = true
						distinct += 1
						if distinct == words.solutionCount then
							break
						end
					end
				end
				expect(distinct):toBe(words.solutionCount)

				expect((words.isSolution(words.solutionForSeed(0)))):toBe(true)
				expect((words.isSolution(words.solutionForSeed(1e6)))):toBe(true)
			end,
		})

		verifyHarness:case("an out-of-range index is refused rather than silently clamped", {
			id = "example_word_data::example word data: a seed is a puzzle, and always the same puzzle::an out-of-range index is refused rather than silently clamped",
			run = function()
				expect(function()
					words.solutionAt(0)
				end):toThrow()
				expect(function()
					words.solutionAt(words.solutionCount + 1)
				end):toThrow()
			end,
		})
	end)

	verifyHarness:suite("example word data: the lookup is cheap enough to sit under a keystroke", function()
		verifyHarness:case("a hit and a miss both cost a bisection, not a scan", {
			id = "example_word_data::example word data: the lookup is cheap enough to sit under a keystroke::a hit and a miss both cost a bisection, not a scan",
			run = function()
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
				expect(hits):toBe(reps)
				if perLookupUs > 40 then
					error(`a word lookup costs {string.format("%.1f", perLookupUs)} us; the budget is 40`, 2)
				end
			end,
		})
	end)
end
