--!strict
-- GENERATED — do not edit by hand. Regenerate with:
--     python3 tools/build_word_lists.py
--
-- What each generated file hashed to when it was produced. The word-data spec
-- re-hashes the files on disk and compares, so data edited by hand — or a
-- partial regeneration that left one length behind — fails the suite rather
-- than quietly changing which words the games accept.

return table.freeze({
	["schema"] = "facet-word-data/1",
	["source"] = {
		["name"] = "SCOWL (Spell Checker Oriented Word Lists) 2020.12.07",
		["url"] = "https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz",
		["sha256"] = "5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc",
		["version"] = "2020.12.07",
		["home"] = "http://wordlist.aspell.net/",
	},
	["policy"] = {
		["acceptedMaxTier"] = 70,
		["acceptedLengths"] = {
			2,
			7,
		},
		["solutionMaxTier"] = 35,
		["solutionLength"] = 5,
		["dialects"] = {
			"english",
			"american",
		},
		["droppedFromSolutions"] = {
			"simple plurals",
			"simple past tenses",
		},
	},
	["counts"] = {
		["2"] = 93,
		["3"] = 792,
		["4"] = 3168,
		["5"] = 6421,
		["6"] = 10742,
		["7"] = 15385,
	},
	["solutionCount"] = 2096,
	["files"] = {
		["len2.luau"] = "15c11fd5b38cdf07dbdf458878c3f101627fb3413d83adf07585c6c17ddb6277",
		["len3.luau"] = "57aad2e02978ccd503c8b5c9e177eb8e485bff5e6927bc1563df246ac437dec1",
		["len4.luau"] = "f6e974cea9a908d674bda9b1874e1ae1087e5f44a04491c489f0c7d506cd9fe9",
		["len5.luau"] = "f9e4430dad65d0942e48194288492a738012f8b4583d7eb5fce159701359a687",
		["len6.luau"] = "2dc9c9c6b11cc46799c83e07482d1e57f640d4c687942fabb01f2090ae0183e8",
		["len7.luau"] = "d627ac8b37edae4622ff108da6fcd60dc36b6779ceb1a46f77c37a58ec6b4128",
		["solutions.luau"] = "92ab13bfab2791c62af28f36dbceca85ed88d95fc765eb27ca1cbb4351a56c37",
	},
})
