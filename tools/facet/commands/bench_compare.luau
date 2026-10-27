--!strict

local Cli = require("../lib/cli")
local Run = require("../lib/run")

return function(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "verify", "filter", "out" })
	if unknown then
		print("bench compare: unknown option " .. unknown)
		return 2
	end
	if #invocation.positional ~= 1 then
		print("bench compare: unexpected positional argument")
		return 2
	end
	local arguments = { Run.lute(), "run", "tools/engine/bench_compare.luau" }
	if Cli.switch(invocation, "verify") then
		table.insert(arguments, "--verify")
	end
	for _, option in { "filter", "out" } do
		local value = Cli.flag(invocation, option)
		if invocation.flags[option] == true or value == "" then
			print("bench compare: --" .. option .. " needs a value")
			return 2
		end
		if value then
			table.insert(arguments, "--" .. option)
			table.insert(arguments, value)
		end
	end
	return Run.inherit(arguments).code
end
