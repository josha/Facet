--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Project = require("../lib/project")

local USAGE =
	"usage: lute run tools/facet project [directory]\nPrint project files without rg or Git. The default is a bounded application summary."

return {
	name = "project",
	summary = "Show the application files without rg or Git.",
	usage = USAGE,
	run = function(invocation: Cli.Invocation): number
		if Cli.unknownFlags(invocation, {}) ~= nil or #invocation.positional > 1 then
			print(USAGE)
			return 2
		end
		local directory = invocation.positional[1]
		if directory == nil or Files.absolute(directory) == Files.cwd() then
			print(Project.report())
		elseif Files.isDirectory(directory) then
			print(table.concat(Files.walk(directory, { skip = { vendor = true, [".git"] = true } }), "\n"))
		else
			print("facet project: no directory at " .. directory)
			return 1
		end
		return 0
	end,
} :: Cli.Command
