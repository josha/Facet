--!strict

local Cli = require("../lib/cli")
local Rule = require("../lib/rule")
local rules = require("../checks")

local USAGE = [[usage: lute run tools/facet check <rule>... [--selftest] [--root DIR] [--<action>]
       lute run tools/facet check --all [--selftest]
       lute run tools/facet check --list

Each rule reads the tree and prints its findings. A rule exits 1 when it has findings.
--selftest runs the cases of each named rule against planted faults.
--all runs every rule. --list prints each rule, its summary and its actions.]]

local function find(name: string): Rule.Rule?
	for _, rule in rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

local function list(): number
	local width = 0
	for _, rule in rules do
		width = math.max(width, #rule.name)
	end
	for _, rule in rules do
		print(("%s%s  %s"):format(rule.name, string.rep(" ", width - #rule.name), rule.summary))
		if rule.actions ~= nil then
			local names: { string } = {}
			for action in rule.actions do
				table.insert(names, action)
			end
			table.sort(names)
			for _, action in names do
				print(("%s    --%s  %s"):format(string.rep(" ", width), action, rule.actions[action].summary))
			end
		end
	end
	return 0
end

local function runAll(invocation: Cli.Invocation, context: Rule.Context): number
	local selftest = Cli.switch(invocation, "selftest")
	local failed: { string } = {}
	for _, rule in rules do
		local code = if selftest then Rule.selftest(rule) else Rule.report(rule, Rule.safeCheck(rule, context))
		if code ~= 0 then
			table.insert(failed, rule.name)
		end
	end
	print("")
	if #failed == 0 then
		print(("check --all%s: PASS (%d rules)"):format(if selftest then " --selftest" else "", #rules))
		return 0
	end
	print(("check --all%s: FAIL (%s)"):format(if selftest then " --selftest" else "", table.concat(failed, ", ")))
	return 1
end

local function run(invocation: Cli.Invocation): number
	if Cli.switch(invocation, "list") then
		return list()
	end
	local context = Rule.context(Cli.flag(invocation, "root"))
	if Cli.switch(invocation, "all") then
		return runAll(invocation, context)
	end
	if #invocation.positional == 0 then
		print(USAGE)
		return 2
	end
	local selected: { Rule.Rule } = {}
	for _, name in invocation.positional do
		local rule = find(name)
		if rule == nil then
			print(("facet check: unknown rule '%s'. Run `lute run tools/facet check --list`."):format(name))
			return 2
		end
		table.insert(selected, rule)
	end
	local code = 0
	for _, rule in selected do
		local acted = false
		if rule.actions ~= nil then
			for name, action in rule.actions do
				if Cli.switch(invocation, name) then
					acted = true
					code = math.max(code, action.run(context, invocation))
				end
			end
		end
		if not acted then
			local result = if Cli.switch(invocation, "selftest")
				then Rule.selftest(rule)
				else Rule.report(rule, Rule.safeCheck(rule, context))
			code = math.max(code, result)
		end
	end
	return code
end

local function values(): { string }
	local names: { string } = { "root" }
	for _, rule in rules do
		local declared = rule.values
		if declared ~= nil then
			for _, name in declared do
				table.insert(names, name)
			end
		end
	end
	return names
end

local command: Cli.Command = {
	name = "check",
	summary = "Run the repository rules, or their selftests.",
	usage = USAGE,
	values = values(),
	run = run,
}

return command
