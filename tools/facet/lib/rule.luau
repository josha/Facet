--!strict

local Cli = require("./cli")
local Files = require("./files")

export type Context = {
	root: string,
	path: (relative: string) -> string,
}

export type Case = {
	name: string,
	run: () -> string?,
}

export type Action = {
	summary: string,
	run: (Context, Cli.Invocation) -> number,
}

export type Rule = {
	name: string,
	summary: string,
	check: (Context) -> { string },
	cases: (() -> { Case })?,
	actions: { [string]: Action }?,
	values: { string }?,
}

export type CaseResult = { name: string, failure: string? }

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

function Rule.fixture(files: { [string]: string }): Context
	local root = Files.temporaryDirectory("facet-rule-")
	for relative, contents in files do
		Files.write(Files.join(root, relative), contents)
	end
	return Rule.context(root)
end

function Rule.dispose(context: Context)
	Files.remove(context.root)
end

function Rule.within(files: { [string]: string }, body: (Context) -> string?): string?
	local context = Rule.fixture(files)
	local ok, result = pcall(body, context)
	Rule.dispose(context)
	if not ok then
		return "raised: " .. tostring(result)
	end
	return result
end

function Rule.expect(condition: boolean, message: string): string?
	if condition then
		return nil
	end
	return message
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

function Rule.runCases(rule: Rule): { CaseResult }
	local results: { CaseResult } = {}
	if rule.cases == nil then
		return results
	end
	local built, cases = pcall(rule.cases)
	if not built then
		table.insert(results, { name = "cases", failure = "could not build cases: " .. tostring(cases) })
		return results
	end
	for _, case in cases :: { Case } do
		local ok, failure = pcall(case.run)
		if not ok then
			table.insert(results, { name = case.name, failure = "raised: " .. tostring(failure) })
		else
			table.insert(results, { name = case.name, failure = failure })
		end
	end
	return results
end

function Rule.report(rule: Rule, findings: { string }): number
	print(("%s: %d findings"):format(rule.name, #findings))
	for _, finding in findings do
		print("  " .. finding)
	end
	return if #findings == 0 then 0 else 1
end

function Rule.selftest(rule: Rule): number
	local results = Rule.runCases(rule)
	local failed = 0
	for _, result in results do
		if result.failure ~= nil then
			failed += 1
			print(("  [FAIL] %s: %s"):format(result.name, result.failure))
		else
			print(("  [ ok ] %s"):format(result.name))
		end
	end
	if #results == 0 then
		print(("%s selftest: FAIL (no cases)"):format(rule.name))
		return 1
	end
	print(("%s selftest: %s (%d cases)"):format(rule.name, if failed == 0 then "PASS" else "FAIL", #results))
	return if failed == 0 then 0 else 1
end

function Rule.safeCheck(rule: Rule, context: Context): { string }
	local ok, findings = pcall(rule.check, context)
	if not ok then
		return { "the check raised: " .. tostring(findings) }
	end
	return findings :: { string }
end

return table.freeze(Rule)
