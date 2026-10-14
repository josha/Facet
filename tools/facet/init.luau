--!strict

local process = require("@std/process")
local Cli = require("@self/lib/cli")
local commands = require("@self/commands")

local arguments = table.clone(process.args)
table.remove(arguments, 1)
process.exit(Cli.main(commands, arguments))
