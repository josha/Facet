--!strict

local json = require("@std/json")

export type Flags = { [string]: string | boolean }

export type Invocation = {
	command: string,
	positional: { string },
	flags: Flags,
}

export type Command = {
	name: string,
	summary: string,
	usage: string,
	run: (Invocation) -> number,
}

local Cli = {}

function Cli.parse(arguments: { string }): Invocation
	local positional: { string } = {}
	local flags: Flags = {}
	local command = "help"
	local first = true
	for _, argument in arguments do
		local name, value = string.match(argument, "^%-%-([%w%-]+)=(.*)$")
		if name ~= nil and value ~= nil then
			flags[name] = value
		else
			local switch = string.match(argument, "^%-%-([%w%-]+)$")
			if switch ~= nil then
				flags[switch] = true
			elseif first then
				command = argument
				first = false
			else
				table.insert(positional, argument)
			end
		end
	end
	return { command = command, positional = positional, flags = flags }
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
	local invocation = Cli.parse(arguments)
	if invocation.command == "help" then
		local target = invocation.positional[1]
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
		if command.name == invocation.command then
			return command.run(invocation)
		end
	end
	print(("facet: unknown command '%s'\n\n%s"):format(invocation.command, helpText(commands)))
	return 2
end

return table.freeze(Cli)
