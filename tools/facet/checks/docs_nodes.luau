--!strict
local Case = require("../lib/case")
local Index = require("../lib/docs_index")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	return Index.validate(Index.load(context.root))
end

local rule: Rule.Rule = {
	name = "docs-nodes",
	summary = "Documentation nodes fit byte budgets and are reachable through links from the map.",
	check = check,
	cases = function(): { Case.Case }
		return {
			{
				name = "the reference is bounded and reachable",
				run = function()
					local findings = check(Rule.context("."))
					return if #findings == 0 then nil else table.concat(findings, "\n")
				end,
			},
		}
	end,
}

return rule
