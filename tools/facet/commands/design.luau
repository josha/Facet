--!strict

local process = require("@std/process")
local task = require("@std/task")
local Cli = require("../lib/cli")
local Registry = require("../design/registry")
local Server = require("../design/server")
local Support = require("../design/cli_support")
local Wire = require("../design/wire")

local USAGE = table.concat({
	"usage: lute run tools/facet design <subcommand> [arguments]",
	"",
	"  tree <file> [--depth=N] [--json]           Print the node tree of a view module.",
	"  apply <file> <ops.json> [--base=HASH]      Apply an atomic batch of operations.",
	"  undo <file> [--entry=ID]                   Undo your latest edit, or one of your entries.",
	"  redo <file>                                Redo your latest undo.",
	"  history <file> [--limit=N]                 List recent history entries.",
	"  serve [paths...] [--port=7878] [--host=H]  Serve view modules over HTTP and WebSocket.",
	"",
	"  --author=NAME sets the history author. The default is human:<user>.",
}, "\n")

local function report(
	invocation: Cli.Invocation,
	result: { [string]: unknown }?,
	failure: Registry.Failure?,
	text: (({
		[string]: unknown,
	}) -> string)?
): number
	if result == nil then
		local problem = failure or { code = "internal", message = "the command failed" }
		if Cli.switch(invocation, "json") then
			print(Wire.encode({ ok = false, error = { code = problem.code, message = problem.message } }, true))
		else
			print(("facet: %s: %s"):format(problem.code, problem.message))
		end
		return 1
	end
	if Cli.switch(invocation, "json") then
		print(Wire.encode(result, true))
	elseif text then
		print(text(result :: { [string]: unknown }))
	end
	return 0
end

local function appliedText(result: { [string]: unknown }): string
	if result.changed == false then
		return "no change; hash " .. tostring(result.hash)
	end
	return ("applied; hash %s; history entry %s"):format(tostring(result.hash), tostring(result.entry))
end

local function context(invocation: Cli.Invocation, root: string): Registry.Context
	return {
		author = Support.author(Cli.flag(invocation, "author"), "human"),
		root = root,
		schema = Support.schema(root),
	}
end

local function number(invocation: Cli.Invocation, name: string): number?
	local value = Cli.flag(invocation, name)
	return if value then tonumber(value) else nil
end

local function serve(invocation: Cli.Invocation, root: string): number
	local roots: { string } = {}
	for index = 2, #invocation.positional do
		table.insert(roots, invocation.positional[index])
	end
	if #roots == 0 then
		table.insert(roots, root)
	end
	local port = number(invocation, "port") or 7878
	local host = Cli.flag(invocation, "host") or "127.0.0.1"
	local running = Server.start({
		root = root,
		roots = roots,
		hostname = host,
		port = port,
		schema = Support.schema(root),
		version = Support.version(root),
	})
	local count = 0
	for _ in running.hub.files do
		count += 1
	end
	print(
		("Facet Design server on http://%s:%d (WebSocket ws://%s:%d/ws)"):format(
			host,
			running.server.port,
			host,
			running.server.port
		)
	)
	print(("Watching %d view modules. Press Ctrl+C to stop."):format(count))
	local stopped = false
	process.onSignal("SIGINT", function()
		stopped = true
	end)
	while not stopped do
		task.wait(0.25)
	end
	running.stop()
	return 0
end

local function run(invocation: Cli.Invocation): number
	local subcommand = invocation.positional[1]
	local root = Support.root()
	if subcommand == nil or subcommand == "help" then
		print(USAGE)
		return if subcommand == nil then 2 else 0
	end
	if subcommand == "serve" then
		return serve(invocation, root)
	end
	local file = invocation.positional[2]
	if file == nil then
		print(USAGE)
		return 2
	end
	local ctx = context(invocation, root)
	if subcommand == "tree" then
		local input: { [string]: unknown } = { file = file }
		local depth = number(invocation, "depth")
		if depth then
			input.depth = depth
		end
		local result, failure = Registry.call(ctx, "query_tree", input)
		return report(invocation, result, failure, function(tree: { [string]: unknown }): string
			local lines: { string } = {}
			local rootNode = tree.root
			if type(rootNode) == "table" then
				Support.treeText(rootNode :: { [string]: unknown }, 0, lines)
			end
			for _, problem in (tree.problems or {}) :: { string } do
				table.insert(lines, "problem: " .. problem)
			end
			if tree.error then
				table.insert(lines, "error: " .. tostring(tree.error))
			end
			table.insert(lines, "hash " .. tostring(tree.hash))
			return table.concat(lines, "\n")
		end)
	elseif subcommand == "apply" then
		local source = invocation.positional[3]
		if source == nil then
			print(USAGE)
			return 2
		end
		local ok, decoded = Support.readJson(source)
		if not ok then
			print("facet: invalid: the operations file is not JSON: " .. tostring(decoded))
			return 1
		end
		local ops = decoded
		local base = Cli.flag(invocation, "base")
		if type(decoded) == "table" and not Wire.isArray(decoded) then
			local object = decoded :: { [string]: unknown }
			ops = object.ops
			if base == nil and type(object.base) == "string" then
				base = object.base :: string
			end
		end
		local result, failure = Registry.call(ctx, "apply", { file = file, ops = ops, base = base })
		return report(invocation, result, failure, appliedText)
	elseif subcommand == "undo" or subcommand == "redo" then
		local input: { [string]: unknown } = { file = file, base = Cli.flag(invocation, "base") }
		local entry = number(invocation, "entry")
		if entry and subcommand == "undo" then
			input.entry = entry
		end
		local result, failure = Registry.call(ctx, subcommand, input)
		return report(invocation, result, failure, appliedText)
	elseif subcommand == "history" then
		local input: { [string]: unknown } = { file = file }
		local limit = number(invocation, "limit")
		if limit then
			input.limit = limit
		end
		local result, failure = Registry.call(ctx, "history", input)
		return report(invocation, result, failure, function(history: { [string]: unknown }): string
			local lines: { string } = {}
			for _, entry in (history.entries or {}) :: { { [string]: unknown } } do
				table.insert(
					lines,
					("%s  %-6s %-24s %s%s"):format(
						tostring(entry.id),
						tostring(entry.kind),
						tostring(entry.author),
						table.concat((entry.ops or {}) :: { string }, ", "),
						if entry.undone then "  (undone)" else ""
					)
				)
			end
			if #lines == 0 then
				return "no history"
			end
			return table.concat(lines, "\n")
		end)
	end
	print(("facet: unknown design subcommand '%s'\n\n%s"):format(subcommand, USAGE))
	return 2
end

local command: Cli.Command = {
	name = "design",
	summary = "Read and edit view modules, undo edits, and serve them to the builder.",
	usage = USAGE,
	run = run,
}

return command
