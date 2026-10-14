--!strict

local Rule = require("../lib/rule")

local rule: Rule.Rule = {
	name = "comments",
	summary = "Not ported yet.",
	check = function(_context: Rule.Context): { string }
		return { "not ported yet" }
	end,
}

return rule
