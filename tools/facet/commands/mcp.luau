--!strict

local io = require("@lute/io")
local Cli = require("../lib/cli")
local Mcp = require("../design/mcp")
local Support = require("../design/cli_support")

local USAGE = table.concat({
	"usage: lute run tools/facet mcp [--root=DIR] [--author=NAME]",
	"",
	"Serve the design registry to an agent with the Model Context Protocol over stdio.",
	"Each message is one line of JSON-RPC 2.0. The default author is agent:<client name>.",
}, "\n")

local function run(invocation: Cli.Invocation): number
	if invocation.positional[1] == "help" then
		print(USAGE)
		return 0
	end
	local root = Cli.flag(invocation, "root") or Support.root()
	root = string.gsub(root, "\\", "/")
	local session = Mcp.session({
		root = root,
		author = Cli.flag(invocation, "author"),
		schema = Support.schema(root),
		version = Support.version(root),
	})
	Mcp.serve(session, function(): string?
		local ok, chunk = pcall(io.read)
		if not ok or type(chunk) ~= "string" then
			return nil
		end
		return chunk :: string
	end, function(text: string)
		io.write(text)
	end)
	return 0
end

local command: Cli.Command = {
	name = "mcp",
	summary = "Serve the design registry to agents over the Model Context Protocol (stdio).",
	usage = USAGE,
	run = run,
}

return command
