--!strict
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Index = require("../lib/docs_index")
local Props = require("../lib/docs_props")
local Rule = require("../lib/rule")

local REGISTRY = "src/ui/icons.luau"

local function check(context: Rule.Context): { string }
	local findings = Index.validate(Index.load(context.root))
	for _, problem in Props.iconProblems(context.root) do
		table.insert(findings, problem)
	end
	return findings
end

local function writeIcons(context: Rule.Context)
	Files.write(context.path(Props.ICONS_NODE), Props.icons(context.root))
end

local function rewrite(context: Rule.Context, _invocation: Cli.Invocation): number
	writeIcons(context)
	local findings = check(context)
	print(("docs-nodes: wrote %s; %d findings"):format(Props.ICONS_NODE, #findings))
	for _, finding in findings do
		print("  " .. finding)
	end
	return if #findings == 0 then 0 else 1
end

local function registryEntry(name: string): string
	return ('\n\t["%s"] = table.freeze({ assetName = "facet_icon_x", contentId = "", tintRole = "content" }),'):format(
		name
	)
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
			{
				name = "the icon name node follows the icon registry",
				run = function()
					local registry = "--!strict\nlocal standard_icons = {}\nstandard_icons.ART = table.freeze({"
						.. registryEntry("star")
						.. registryEntry("coin")
						.. "\n})\n"
					return Rule.within({
						[REGISTRY] = registry,
						[Props.ICONS_NODE] = "# Icons.names\n",
					}, function(context: Rule.Context): string?
						local stale = Props.iconProblems(context.root)
						if not Rule.contains(stale, Props.ICONS_NODE .. " differs") then
							return "a stale node passed: " .. Rule.describe(stale)
						end
						writeIcons(context)
						local written = Files.text(context.path(Props.ICONS_NODE))
						if not string.find(written, "| `coin` | Coins or soft currency |", 1, true) then
							return "the written node has no coin row:\n" .. written
						end
						for _, problem in Props.iconProblems(context.root) do
							if string.find(problem, Props.ICONS_NODE, 1, true) then
								return "the written node is still stale: " .. problem
							end
						end
						Files.write(context.path(REGISTRY), registry .. registryEntry("unlisted"))
						local unlisted = Props.iconProblems(context.root)
						return Rule.expect(
							Rule.contains(unlisted, "unlisted has no use")
								and Rule.contains(unlisted, Props.ICONS_NODE .. " differs"),
							"a registry name without a use or a row passed: " .. Rule.describe(unlisted)
						)
					end)
				end,
			},
		}
	end,
	actions = {
		write = {
			summary = "Write docs/reference/nodes/Icons.names.md again from the icon registry.",
			run = rewrite,
		},
	},
}

return rule
