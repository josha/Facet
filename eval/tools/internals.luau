--!strict

local fs = require("@std/fs")
local json = require("@std/json")
local AgentEval = require("../../tools/vendor/verify/src/agent-eval")
local process = require("@std/process")

local USAGE = [[usage: lute run eval/tools/internals.luau <run directory>...

Reads the transcript.jsonl of each finished run and lists every tool call that
opens Facet or author-tool source: Packages/Facet, tools/play, tools/vendor,
tools/studio, tools/facet/lib and tools/facet/commands. Each entry shows the
tool, the paths and the last text that the agent wrote before the call, which
is its stated reason. Running a tool, for example lute run tools/facet docs,
does not count. The command writes internals.json next to the transcript and
prints a summary per run.]]

local PATTERNS = {
	"Packages[/\\]Facet[^%s\"';|]*",
	"tools[/\\]play[^%s\"';|]*",
	"tools[/\\]vendor[^%s\"';|]*",
	"tools[/\\]studio[^%s\"';|]*",
	"tools[/\\]facet[/\\]lib[^%s\"';|]*",
	"tools[/\\]facet[/\\]commands[^%s\"';|]*",
}

type Entry = { tool: string, paths: { string }, reason: string }

local function text(value: unknown): string
	return if type(value) == "string" then value else ""
end

local function readable(command: string): string
	return (string.gsub(command, "lute run tools/facet%s+%S+", ""))
end

local function scan(directory: string): { Entry }
	local entries: { Entry } = {}
	local path = directory .. "/transcript.jsonl"
	if not fs.exists(path) then
		return entries
	end
	local reason = ""
	for line in string.gmatch(fs.readFileToString(path), "[^\n]+") do
		local tab = string.find(line, "\t", 1, true)
		local body = if tab then string.sub(line, tab + 1) else line
		local ok, event = pcall(json.deserialize, body)
		if not ok or type(event) ~= "table" then
			continue
		end
		local record = (event :: unknown) :: { [string]: unknown }
		local message = record.message
		if record.type ~= "assistant" or type(message) ~= "table" then
			continue
		end
		local content = (message :: { [string]: unknown }).content
		if type(content) ~= "table" then
			continue
		end
		for _, item in content :: { unknown } do
			if type(item) ~= "table" then
				continue
			end
			local block = item :: { [string]: unknown }
			if block.type == "text" and text(block.text) ~= "" then
				reason = string.sub((string.gsub(text(block.text), "%s+", " ")), 1, 240)
			elseif block.type == "tool_use" and type(block.input) == "table" then
				local input = block.input :: { [string]: unknown }
				local target = table.concat({
					text(input.file_path),
					text(input.path),
					text(input.pattern),
					readable(text(input.command)),
				}, " ")
				local seen: { [string]: boolean } = {}
				local paths: { string } = {}
				for _, pattern in PATTERNS do
					for found in string.gmatch(target, pattern) do
						if not seen[found] then
							seen[found] = true
							table.insert(paths, found)
						end
					end
				end
				if #paths > 0 then
					table.insert(entries, { tool = text(block.name), paths = paths, reason = reason })
				end
			end
		end
	end
	return entries
end

local runs = table.clone(process.args)
table.remove(runs, 1)
if #runs == 0 or runs[1] == "--help" then
	print(USAGE)
	process.exit(if #runs == 0 then 2 else 0)
end
for _, directory in runs do
	local entries = scan(directory)
	fs.writeStringToFile(directory .. "/internals.json", AgentEval.lute.encode(entries) .. "\n")
	print(`{directory}: {#entries} internals reads`)
	for _, entry in entries do
		print(`  [{entry.tool}] {table.concat(entry.paths, " ")}`)
		print(`    reason: {entry.reason}`)
	end
end
