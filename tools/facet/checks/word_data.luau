--!strict

local Rule = require("../lib/rule")
local WordLists = require("../lib/word_lists")

local rule: Rule.Rule = {
	name = "word-data",
	summary = "The generated example word data matches the hashes in its manifest.luau.",
	check = function(context: Rule.Context): { string }
		return WordLists.findings(context.root)
	end,
	cases = WordLists.cases,
}

return rule
