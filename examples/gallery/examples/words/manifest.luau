--!strict

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
		["len2.luau"] = "e9422b21dd41957734edde588a31552db31d5b81f0edcaf73cc845b08c73386b",
		["len3.luau"] = "15053f7578af2a144c266829ef02d3e74d7c4ec195921ff6d4363ad1f12523cb",
		["len4.luau"] = "1053eec74121822dc9e55f8c8ae8face768c11ab7f8b9d3e0f5bd7c1fb423ecd",
		["len5.luau"] = "295c7558f167cb85ee1446e152b3489dc1ec36dd0a0cdee936da3000ca3a53c9",
		["len6.luau"] = "2f20608ab7d00128af82877942a346f76c79720e1c2d787c6cddabcc0f3e1f8a",
		["len7.luau"] = "264c7d3216391f9d86ddcf63f2edb6ef4168f01fe5baaf40acaece6a958546c6",
		["solutions.luau"] = "77ac85fe390a391d118a61a0ade7546296854f8719ffb0e51e8cde322fc86f02",
	},
})
