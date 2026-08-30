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
		["acceptDialects"] = {
			"english",
			"american",
			"british",
			"british_z",
			"canadian",
			"australian",
			"variant_1",
			"variant_2",
			"variant_3",
		},
		["solutionDialects"] = {
			"english",
			"american",
		},
		["droppedFromSolutions"] = {
			"simple plurals",
			"simple past tenses",
		},
	},
	["counts"] = {
		["2"] = 94,
		["3"] = 808,
		["4"] = 3284,
		["5"] = 6727,
		["6"] = 11249,
		["7"] = 16018,
	},
	["solutionCount"] = 2095,
	["files"] = {
		["len2.luau"] = "ad3b917681bd7226024e73a9b23e23a20b7b8302098e744c007487386aecc56f",
		["len3.luau"] = "bd1cd30641dc57eb980f56b78a76b58af3d440a205672d2e3ad80b773ecc122d",
		["len4.luau"] = "4b419826ed64ca3e0ea2b25abd02399233a24c8982fb697b566f21c69eb42aa9",
		["len5.luau"] = "3b957038cfb3cca85b8ba8ff3d8203e7a428b3c7e57d6fd304d6988fc765320b",
		["len6.luau"] = "b44eb3c56356419922cb2428a5b81f8d30af45d7200ca72e5ae1091b7cf3bd0a",
		["len7.luau"] = "0419be11868f4381327dda413495ac95e091c6ebd22c000045a274f1cbc320ba",
		["solutions.luau"] = "52a4241b25b7cafd743f235507acb50f38d4e96a528b0f5ebb524aaeee9632c7",
	},
})
