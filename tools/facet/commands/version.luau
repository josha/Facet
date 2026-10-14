--!strict

local fs = require("@std/fs")
local Cli = require("../lib/cli")

local function run(invocation: Cli.Invocation): number
	local source = fs.readFileToString("src/init.luau")
	local version = string.match(source, 'local VERSION = "([^"]+)"')
	local compose = string.match(source, 'local COMPOSE_COMMIT = "([^"]+)"')
	if version == nil or compose == nil then
		print("facet: src/init.luau does not declare VERSION and COMPOSE_COMMIT")
		return 1
	end
	Cli.emit(
		invocation,
		{ facet = version, compose = compose },
		("facet %s (compose %s)"):format(version, string.sub(compose, 1, 7))
	)
	return 0
end

local command: Cli.Command = {
	name = "version",
	summary = "Print the Facet version and the pinned Compose commit.",
	usage = "usage: lute run tools/facet version [--json]",
	run = run,
}

return command
