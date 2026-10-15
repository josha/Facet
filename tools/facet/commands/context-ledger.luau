--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")

local USAGE = "usage: lute run tools/facet context-ledger RUN_DIRECTORY --out FILE"

local function category(command: string): string
	if string.find(command, "tools/facet docs", 1, true) then
		return "docs and recipes (including batched reads)"
	elseif string.find(command, "SKILL.md", 1, true) or string.find(command, "AGENTS.md", 1, true) then
		return "instructions and skills (including batched reads)"
	elseif string.find(command, "Set-Content", 1, true) or string.find(command, "WriteAllText", 1, true) then
		return "code edits and checks"
	elseif string.find(command, "Get-Content", 1, true) then
		return "file reads"
	elseif string.find(command, "tools/facet", 1, true) then
		return "Facet CLI"
	end
	return "other shell"
end

local function run(invocation: Cli.Invocation): number
	local directory = invocation.positional[1]
	local out = Cli.flag(invocation, "out")
	if directory == nil or out == nil or #invocation.positional ~= 1 then
		print(USAGE)
		return 2
	end
	local events: { Json.Object } = {}
	local calls = 0
	local usage: unknown = nil
	for _, line in Files.lines(Files.read(Files.join(directory, "transcript.jsonl"))) do
		local stamp, body = string.match(line, "^([^\t]+)\t(.*)$")
		if body == nil then
			continue
		end
		local event = Json.decode(body)
		local kind = Json.stringField(event, "type")
		if kind == "item.started" then
			calls += 1
		elseif kind == "turn.completed" then
			usage = Json.field(event, "usage")
		elseif kind == "item.completed" then
			local item = Json.objectField(event, "item")
			if item ~= nil then
				table.insert(events, { item = item, call = calls, seconds = tonumber(stamp or "") or 0 })
			end
		end
	end
	local rows: { Json.Object } = {}
	local totals: { [string]: Json.Object } = {}
	local function add(
		at: number,
		seconds: number,
		id: string,
		group: string,
		part: string,
		text: string,
		images: number?,
		base64: number?
	)
		local remaining = calls - at
		local bytes = #text
		local weighted = bytes * remaining
		table.insert(rows, {
			call = at,
			seconds = seconds,
			id = id,
			category = group,
			part = part,
			bytes = bytes,
			textTokensEstimate = bytes / 4,
			laterCalls = remaining,
			replayedTextTokensEstimate = weighted / 4,
			images = images or 0,
			imageBase64Bytes = base64 or 0,
			label = string.sub(text, 1, if part == "command" then 1000 else 240),
		})
		local total = totals[group]
			or { bytes = 0, weightedBytes = 0, entries = 0, images = 0, imageBase64Bytes = 0, replayedImages = 0 }
		for key, value in
			{
				bytes = bytes,
				weightedBytes = weighted,
				entries = 1,
				images = images or 0,
				imageBase64Bytes = base64 or 0,
				replayedImages = (images or 0) * remaining,
			}
		do
			total[key] = (Json.asNumber(total[key]) or 0) + value
		end
		totals[group] = total
	end
	for _, name in { "prompt.md", "workspace/AGENTS.md" } do
		local path = Files.join(directory, name)
		if Files.isFile(path) then
			add(0, 0, name, "initial prompt and arm instructions", "initial", Files.read(path))
		end
	end
	for _, event in events do
		local item = Json.objectField(event, "item") :: Json.Object
		local at = Json.numberField(event, "call") or 0
		local seconds = Json.numberField(event, "seconds") or 0
		local id = Json.stringField(item, "id") or ""
		local kind = Json.stringField(item, "type")
		if kind == "command_execution" then
			local command = Json.stringField(item, "command") or ""
			local group = category(command)
			add(at, seconds, id, group, "command", command)
			add(at, seconds, id, group, "output", Json.stringField(item, "aggregated_output") or "")
		elseif kind == "mcp_tool_call" then
			local tool = Json.stringField(item, "tool") or "unknown"
			local args = Json.field(item, "arguments")
			local code = Json.stringField(args, "code") or ""
			local group = "Studio " .. tool
			if tool == "execute_luau" and string.find(code, "%.Source%s*=") then
				group = "Studio source transfer"
			end
			add(at, seconds, id, group, "arguments", Json.encode(args))
			local images, base64 = 0, 0
			local texts: { string } = {}
			local result = Json.field(item, "result")
			for _, block in Json.arrayField(result, "content") or {} do
				if Json.stringField(block, "type") == "image" then
					images += 1
					base64 += #(Json.stringField(block, "data") or "")
				else
					table.insert(texts, Json.stringField(block, "text") or Json.encode(block))
				end
			end
			local structured = Json.field(result, "structured_content")
			if structured ~= nil then
				table.insert(texts, Json.encode(structured))
			end
			local failure = Json.field(item, "error")
			if failure ~= nil then
				table.insert(texts, Json.encode(failure))
			end
			add(at, seconds, id, group, "result", table.concat(texts, "\n"), images, base64)
		else
			add(at, seconds, id, kind or "unknown", "text", Json.stringField(item, "text") or Json.encode(item))
		end
	end
	Files.write(
		out,
		Json.encode({
			calls = calls,
			usage = usage,
			rows = rows,
			totals = totals,
			method = "UTF-8 bytes / 4; replay assumes retained history at each later tool call. Images are counted separately, never tokenized as base64. No per-request usage, hidden instructions, reasoning or truncation boundary is available in this transcript. Initial AGENTS.md is taken from the saved workspace. Command and result enter on the same numbered call; only subsequent calls count as replays.",
		})
	)
	print("Context ledger: " .. out)
	return 0
end

return {
	name = "context-ledger",
	summary = "Measure observable transcript context and later-call exposure.",
	usage = USAGE,
	values = { "out" },
	run = run,
} :: Cli.Command
