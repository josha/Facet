--!strict

local process = require("@std/process")
local Cli = require("@self/lib/cli")
local commands = require("@self/commands")

local arguments = table.clone(process.args)
table.remove(arguments, 1)
local ok, result = xpcall(Cli.main, function(problem: unknown): string
	return debug.traceback(tostring(problem))
end, commands, arguments)
if not ok then
	print(`facet: {result}`)
	process.exit(1)
end
process.exit(result :: number)
