--!strict

local Cli = require("../lib/cli")
local Registry = require("../design/registry")
local Support = require("../design/cli_support")
local Wire = require("../design/wire")

local USAGE = table.concat({
	"usage: lute run tools/facet tool <list|describe|call> [arguments]",
	"",
	"  list [--json]                       List the operations of the design registry.",
	"  describe <name>                     Print the input schema, mutation and capability of one operation.",
	"  call <name> <json|@file> [--author=NAME]",
	"                                      Call one operation with a JSON object input.",
}, "\n")

local function run(invocation: Cli.Invocation): number
	local action = invocation.positional[1]
	if action == "list" then
		local tools = Registry.list()
		if Cli.switch(invocation, "json") then
			local described: { unknown } = {}
			for _, tool in tools do
				table.insert(described, Registry.describe(tool))
			end
			print(Wire.encode({ tools = described }, true))
			return 0
		end
		local width = 0
		for _, tool in tools do
			width = math.max(width, #tool.name)
		end
		for _, tool in tools do
			print(
				("%s%s  %-8s %-7s %s"):format(
					tool.name,
					string.rep(" ", width - #tool.name),
					tool.mutation,
					tool.capability,
					tool.summary
				)
			)
		end
		return 0
	elseif action == "describe" then
		local name = invocation.positional[2]
		local tool = if name then Registry.get(name) else nil
		if tool == nil or tool.internal then
			print("facet: not_found: unknown tool " .. tostring(name))
			return 1
		end
		print(Wire.encode(Registry.describe(tool), true))
		return 0
	elseif action == "call" then
		local name = invocation.positional[2]
		local argument = invocation.positional[3] or "{}"
		if name == nil then
			print(USAGE)
			return 2
		end
		local ok, input = Support.readJson(argument)
		if not ok then
			print("facet: invalid: the input is not JSON: " .. tostring(input))
			return 1
		end
		local root = Support.root()
		local context: Registry.Context = {
			author = Support.author(Cli.flag(invocation, "author"), "human"),
			root = Support.cwd(),
			docs = root,
			schema = Support.schema(root),
		}
		local result, failure = Registry.call(context, name, input)
		if result == nil then
			local problem = failure or { code = "internal", message = "the tool failed" }
			print(Wire.encode({ ok = false, error = { code = problem.code, message = problem.message } }, true))
			return 1
		end
		print(Wire.encode({ ok = true, result = result }, true))
		return 0
	end
	print(USAGE)
	return if action == nil then 2 else 2
end

local command: Cli.Command = {
	name = "tool",
	summary = "List, describe and call the operations of the design registry.",
	usage = USAGE,
	run = run,
}

return command
