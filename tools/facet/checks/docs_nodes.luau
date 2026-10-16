--!strict
local Files = require("../lib/files")
local Case = require("../lib/case")
local Index = require("../lib/docs_index")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	local nodes = Index.load(context.root)
	local findings = Index.validate(nodes)
	local files: { [string]: boolean } = {}
	for _, node in nodes do
		files[node.file] = true
	end
	for _, relative in Files.walk(context.path("docs/reference/nodes")) do
		local file = "docs/reference/nodes/" .. relative
		if Files.extension(file) == ".md" and not files[file] then
			table.insert(findings, file .. ": not indexed")
		end
	end
	return findings
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
