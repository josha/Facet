--!strict

local Rule = require("./lib/rule")

local rules: { Rule.Rule } = {
	require("@self/plan"),
}

return table.freeze(rules)
