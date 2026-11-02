--!strict

local json = require("@std/json")
local Verify = require("../../vendor/verify/src/core")
local Gate = require("./gate")

export type Flags = { [string]: string | boolean }

export type Invocation = {
	command: string,
	positional: { string },
	flags: Flags,
	repeated: { [string]: { string } },
	arguments: { string },
}

export type Command = {
	name: string,
	summary: string,
	usage: string,
	values: { string }?,
	register: ((Verify.Harness, string) -> ())?,
	run: (Invocation) -> number,
}

local Cli = {}

function Cli.parse(arguments: { string }, values: { string }?): Invocation
	local positional: { string } = {}
	local flags: Flags = {}
	local repeated: { [string]: { string } } = {}
	local takes: { [string]: boolean } = {}
	if values ~= nil then
		for _, name in values do
			takes[name] = true
		end
	end
	local function record(name: string, value: string)
		flags[name] = value
		local list = repeated[name]
		if list == nil then
			list = {}
			repeated[name] = list
		end
		table.insert(list, value)
	end
	local command = "help"
	local commandIndex = #arguments
	local first = true
	local literal = false
	local index = 1
	while index <= #arguments do
		local argument = arguments[index]
		local name, value = string.match(argument, "^%-%-([%w%-]+)=(.*)$")
		if literal then
			table.insert(positional, argument)
		elseif argument == "--" then
			literal = true
		elseif name ~= nil and value ~= nil then
			record(name, value)
		else
			local switch = string.match(argument, "^%-%-([%w%-]+)$")
			if switch ~= nil and takes[switch] and arguments[index + 1] ~= nil then
				record(switch, arguments[index + 1])
				index += 1
			elseif switch ~= nil then
				flags[switch] = true
			elseif first then
				command = argument
				commandIndex = index
				first = false
			else
				table.insert(positional, argument)
			end
		end
		index += 1
	end
	return {
		command = command,
		positional = positional,
		flags = flags,
		repeated = repeated,
		arguments = table.move(arguments, commandIndex + 1, #arguments, 1, {}),
	}
end

function Cli.flag(invocation: Invocation, name: string): string?
	local value = invocation.flags[name]
	if type(value) == "string" then
		return value
	end
	return nil
end

function Cli.switch(invocation: Invocation, name: string): boolean
	return invocation.flags[name] ~= nil
end

function Cli.emit(invocation: Invocation, value: json.Value, text: string)
	if Cli.switch(invocation, "json") then
		print(json.serialize(value, true))
	else
		print(text)
	end
end

function Cli.unknownFlags(invocation: Invocation, known: { string }): string?
	local allowed: { [string]: boolean } = { json = true }
	for _, name in known do
		allowed[name] = true
	end
	local unknown: { string } = {}
	for name in invocation.flags do
		if not allowed[name] then
			table.insert(unknown, "--" .. name)
		end
	end
	table.sort(unknown)
	if #unknown == 0 then
		return nil
	end
	return table.concat(unknown, ", ")
end

local function helpText(commands: { Command }): string
	local lines = { "usage: lute run tools/facet <command> [arguments] [--json]", "", "commands:" }
	local width = 0
	for _, command in commands do
		width = math.max(width, #command.name)
	end
	for _, command in commands do
		table.insert(
			lines,
			("  %s%s  %s"):format(command.name, string.rep(" ", width - #command.name), command.summary)
		)
	end
	return table.concat(lines, "\n")
end

function Cli.main(commands: { Command }, arguments: { string }): number
	local name: string = arguments[1] or "help"
	if name == "help" or name == "--help" or name == "-h" then
		local target = arguments[2]
		for _, command in commands do
			if command.name == target then
				print(command.usage)
				return 0
			end
		end
		print(helpText(commands))
		return if target == nil then 0 else 2
	end
	for _, command in commands do
		if command.name == name then
			if table.find(arguments, "--help", 2) ~= nil then
				print(command.usage)
				return 0
			end
			if command.register ~= nil and #arguments == 2 and arguments[2] == "--selftest" then
				return Gate.selftest("tools/commands", "tools/commands::" .. command.name .. "::")
			end
			local invocation = Cli.parse(arguments, command.values)
			return command.run(invocation)
		end
	end
	print(("facet: unknown command '%s'\n\n%s"):format(name, helpText(commands)))
	return 2
end

return table.freeze(Cli)
