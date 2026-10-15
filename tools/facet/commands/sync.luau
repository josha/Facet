--!strict

local Cli = require("../lib/cli")
local Snapshot = require("../lib/snapshot")
local SnapshotCases = require("../lib/snapshot_cases")

local USAGE = [[usage: lute run tools/facet sync <compose|verify|all> [--check] [--bump COMMIT] [--source REPOSITORY]

Materialize the exact pinned snapshot of a vendored dependency. The snapshot is tracked, generated and read-only.
  --check            fail when a file differs from the pin; never fetch
  --bump COMMIT      move the pin to this full commit and materialize it
  --source DIRECTORY use a local Git repository that contains the pinned commit]]

local function run(invocation: Cli.Invocation): number
	local target = invocation.positional[1]
	if target == "all" and Cli.switch(invocation, "check") and Cli.unknownFlags(invocation, { "check" }) == nil then
		local function report(name: Snapshot.Name): number
			local passed, message = Snapshot.check(".", name)
			print(`vendor {name}: {message}`)
			return if passed then 0 else 1
		end
		return math.max(report("compose"), report("verify"))
	end
	if target ~= "compose" and target ~= "verify" then
		print(USAGE)
		return 2
	end
	local unknown = Cli.unknownFlags(invocation, { "check", "bump", "source" })
	if unknown ~= nil then
		print("facet sync: unknown option " .. unknown)
		return 2
	end
	local bump = invocation.flags.bump
	if bump == true then
		print("facet sync: --bump needs a commit")
		return 2
	end
	local code, message = Snapshot.sync(Snapshot.config(".", target), {
		check = Cli.switch(invocation, "check"),
		bump = Cli.flag(invocation, "bump"),
		source = Cli.flag(invocation, "source"),
	})
	print(message)
	return code
end

local command: Cli.Command = {
	name = "sync",
	summary = "Verify or materialize the pinned Compose and Verify snapshots.",
	usage = USAGE,
	values = { "bump", "source" },
	cases = SnapshotCases.cases,
	run = run,
}

return command
