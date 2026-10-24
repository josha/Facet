--!strict
local Verify = require("../../vendor/verify/src/core")
local Index = require("../lib/docs_index")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	return Index.validate(Index.load(context.root))
end

local rule: Rule.Rule = {
	name = "docs-nodes",
	summary = "Documentation nodes fit byte budgets and are reachable through links from the map.",
	check = check,
	register = function(harness: Verify.Harness, prefix: string): ()
		harness:case(prefix .. "the reference is bounded and reachable", {
			id = prefix .. "the reference is bounded and reachable",
			run = function(test: Verify.Context)
				local findings = check(Rule.context("."))
				Verify.expect(if #findings == 0 then nil else table.concat(findings, "\n")):toBeNil()
			end,
		})
	end,
}

return rule
