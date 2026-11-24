--!strict

local Cli = require("../lib/cli")
local Snapshot = require("../lib/snapshot")
local SnapshotCases = require("../lib/snapshot_cases")

local USAGE = [[usage: lute run tools/facet sync compose [--check] [--content]

Copy the Compose package that lute pkg installed (.lpm/compose@<locked rev>) into src/vendor/compose and
its skill guide into skills/compose. The copy is tracked, generated and read-only. Run lute pkg install --vendor first.
  --check    fail when the copy differs from the installed package or a file is not mode 100644; never write
  --content  with --check, compare file contents only and ignore file modes]]

local function run(invocation: Cli.Invocation): number
	local target = invocation.positional[1]
	if target ~= "compose" then
		print(USAGE)
		return 2
	end
	local unknown = Cli.unknownFlags(invocation, { "check", "content" })
	if unknown ~= nil then
		print("facet sync: unknown option " .. unknown)
		return 2
	end
	local code, message = Snapshot.sync(Snapshot.config(".", target), {
		check = Cli.switch(invocation, "check"),
		contentOnly = Cli.switch(invocation, "content"),
	})
	print(message)
	return code
end

local command: Cli.Command = {
	name = "sync",
	summary = "Copy or check the Compose package that lute pkg installed.",
	usage = USAGE,
	register = SnapshotCases.register,
	run = run,
}

return command
