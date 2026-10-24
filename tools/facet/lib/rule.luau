--!strict

local Verify = require("../../vendor/verify/src/core")
local Cli = require("./cli")
local Files = require("./files")

export type Context = {
	root: string,
	path: (relative: string) -> string,
}

export type Action = {
	summary: string,
	run: (Context, Cli.Invocation) -> number,
}

export type Rule = {
	name: string,
	summary: string,
	check: (Context) -> { string },
	register: (Verify.Harness, string) -> (),
	actions: { [string]: Action }?,
	values: { string }?,
}

local Rule = {}

function Rule.context(root: string?): Context
	local base = Files.normalize(root or ".")
	return {
		root = base,
		path = function(relative: string): string
			return Files.join(base, relative)
		end,
	}
end

function Rule.fixture(test: Verify.Context, files: { [string]: string }): Context
	local root = Files.temporaryDirectory("facet-rule-")
	test:defer(function()
		Files.remove(root)
	end)
	for relative, contents in files do
		Files.write(Files.join(root, relative), contents)
	end
	return Rule.context(root)
end

function Rule.within(test: Verify.Context, files: { [string]: string }, body: (Context) -> ())
	body(Rule.fixture(test, files))
end

function Rule.contains(findings: { string }, fragment: string): boolean
	for _, finding in findings do
		if string.find(finding, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

function Rule.describe(findings: { string }): string
	if #findings == 0 then
		return "no findings"
	end
	return table.concat(findings, "; ")
end

function Rule.report(rule: Rule, findings: { string }): number
	print(("%s: %d findings"):format(rule.name, #findings))
	for _, finding in findings do
		print("  " .. finding)
	end
	return if #findings == 0 then 0 else 1
end

function Rule.safeCheck(rule: Rule, context: Context): { string }
	local ok, findings = pcall(rule.check, context)
	if not ok then
		return { "the check raised: " .. tostring(findings) }
	end
	return findings :: { string }
end

return table.freeze(Rule)
