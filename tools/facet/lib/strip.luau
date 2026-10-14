--!strict

local Files = require("./files")
local Luau = require("./luau")
local Run = require("./run")
local Shell = require("./shell")

export type Span = Shell.Span

export type Edit = { start: number, stop: number, replacement: string }

local Strip = {}

local LUAU_DIRECTIVES = { "strict", "nonstrict", "nocheck", "native", "optimize", "nolint" }
local TOOL_DIRECTIVES = { "stylua:", "selene:", "luacheck:" }
local SHELL_DIRECTIVES = { "shfmt:", "fmt:", "isort:", "type:", "pyright:", "mypy:", "ruff:", "pylint:" }
local SHELL_WORD_DIRECTIVES = { "shellcheck", "noqa" }

local LEGAL_PHRASES = {
	"spdx-license-identifier:",
	"permission is hereby granted",
	"licensed under the",
	"licence and required notices:",
}

local NOTICE = "Licence and required notices:"

local function wordByte(byte: number?): boolean
	if byte == nil then
		return false
	end
	return byte >= 0x80
		or byte == 0x5F
		or (byte >= 0x30 and byte <= 0x39)
		or (byte >= 0x41 and byte <= 0x5A)
		or (byte >= 0x61 and byte <= 0x7A)
end

local function startsWord(text: string, at: number, word: string): boolean
	return string.sub(text, at, at + #word - 1) == word and not wordByte(string.byte(text, at + #word))
end

local function startsWith(text: string, at: number, prefix: string): boolean
	return string.sub(text, at, at + #prefix - 1) == prefix
end

function Strip.directive(text: string): boolean
	if startsWith(text, 1, "--!") then
		for _, word in LUAU_DIRECTIVES do
			if startsWord(text, 4, word) then
				return true
			end
		end
	end
	if startsWith(text, 1, "--") then
		local at = string.find(text, "[^%s]", 3) or #text + 1
		for _, prefix in TOOL_DIRECTIVES do
			if startsWith(text, at, prefix) then
				return true
			end
		end
		if startsWord(text, at, "theme_sync:begin") or startsWord(text, at, "theme_sync:end") then
			return true
		end
	end
	if startsWith(text, 1, "#!") then
		return true
	end
	if startsWith(text, 1, "#") then
		local at = string.find(text, "[^%s]", 2) or #text + 1
		for _, prefix in SHELL_DIRECTIVES do
			if startsWith(text, at, prefix) then
				return true
			end
		end
		for _, word in SHELL_WORD_DIRECTIVES do
			if startsWord(text, at, word) then
				return true
			end
		end
		if string.find(text, "^pragma:%s*no cover", at) ~= nil then
			return true
		end
		if string.find(text, "coding[:=]", 2) ~= nil then
			return true
		end
	end
	return false
end

function Strip.legal(text: string): boolean
	local lowered = string.lower(text)
	if string.find(lowered, "copyright%s+%(c%)") ~= nil or string.find(lowered, "copyright%s+%d%d%d%d") ~= nil then
		return true
	end
	for _, phrase in LEGAL_PHRASES do
		if string.find(lowered, phrase, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function blank(text: string): boolean
	return string.find(text, "^%s*$") ~= nil
end

local function newlines(text: string): number
	local _, count = string.gsub(text, "\n", "")
	return count
end

function Strip.edits(source: string, spans: { Span }): { Edit }
	local function slice(span: Span): string
		return string.sub(source, span.start, span.stop - 1)
	end
	local function gap(left: number, right: number): string
		return string.sub(source, spans[left].stop, spans[right].start - 1)
	end
	local protected: { [number]: boolean } = {}
	for index, span in spans do
		local text = slice(span)
		if not Strip.legal(text) then
			continue
		end
		protected[index] = true
		if string.find(text, NOTICE, 1, true) ~= nil then
			for before = index - 1, math.max(1, index - 3), -1 do
				if not blank(gap(before, before + 1)) then
					break
				end
				protected[before] = true
			end
			continue
		end
		local before = index - 1
		while before >= 1 and blank(gap(before, before + 1)) do
			if newlines(gap(before, before + 1)) > 1 then
				break
			end
			protected[before] = true
			before -= 1
		end
		local after = index + 1
		while after <= #spans and blank(gap(after - 1, after)) do
			if newlines(gap(after - 1, after)) > 1 then
				break
			end
			protected[after] = true
			after += 1
		end
	end
	local edits: { Edit } = {}
	local length = #source
	for index, span in spans do
		if protected[index] or Strip.directive(slice(span)) then
			continue
		end
		local start, stop = span.start, span.stop
		local lineStart = 1
		local cursor = start - 1
		while cursor >= 1 do
			if string.byte(source, cursor) == 0x0A then
				lineStart = cursor + 1
				break
			end
			cursor -= 1
		end
		local following = string.sub(source, stop, stop)
		local endsLine = stop > length or following == "\r" or following == "\n"
		if blank(string.sub(source, lineStart, start - 1)) then
			start = lineStart
		elseif endsLine then
			local leading = start
			while leading > lineStart do
				local previous = string.sub(source, leading - 1, leading - 1)
				if previous ~= " " and previous ~= "\t" then
					break
				end
				leading -= 1
			end
			if leading == lineStart or string.sub(source, leading - 1, leading - 1) ~= "\\" then
				start = leading
			end
		end
		local replacement = string.gsub(string.sub(source, start, stop - 1), "[^\r\n]", "")
		if not endsLine and replacement == "" then
			replacement = " "
		end
		table.insert(edits, { start = start, stop = stop, replacement = replacement })
	end
	return edits
end

function Strip.apply(source: string, edits: { Edit }): string
	local ordered = table.clone(edits)
	table.sort(ordered, function(left: Edit, right: Edit): boolean
		if left.start ~= right.start then
			return left.start < right.start
		end
		return left.stop < right.stop
	end)
	local parts: { string } = {}
	local cursor = 1
	for _, edit in ordered do
		if edit.start < cursor then
			error("overlapping source edits", 0)
		end
		table.insert(parts, string.sub(source, cursor, edit.start - 1))
		table.insert(parts, edit.replacement)
		cursor = edit.stop
	end
	table.insert(parts, string.sub(source, cursor))
	return table.concat(parts)
end

local function luauSpans(source: string): ({ Span }?, string?)
	local parsed, problem = Luau.parse(source)
	if parsed == nil then
		local first = string.match(problem or "", "^[^\n]*") or ""
		return nil, "cannot parse Luau: " .. first
	end
	local spans: { Span } = {}
	for _, comment in Luau.comments(parsed) do
		table.insert(spans, { start = comment.start, stop = comment.finish + 1 })
	end
	return spans, nil
end

local function stripWith(source: string, spans: { Span }): (string, number)
	local edits = Strip.edits(source, spans)
	local first = math.huge
	for _, edit in edits do
		first = math.min(first, edit.start)
	end
	local line = if first == math.huge then 0 else Luau.lineOf(source, first)
	return Strip.apply(source, edits), line
end

function Strip.luau(source: string): (string?, string?, number)
	local spans, problem = luauSpans(source)
	if spans == nil then
		return nil, problem, 0
	end
	local result, line = stripWith(source, spans)
	return result, nil, line
end

local function shellSyntax(text: string): string?
	local directory = Files.temporaryDirectory("facet-comments-")
	local script = Files.join(directory, "script.sh")
	Files.write(script, (string.gsub(text, "\r\n", "\n")))
	local result = Run.capture({ "bash", "-n", script }, { timeout = 60 })
	Files.remove(directory)
	if result.ok then
		return nil
	end
	local message = string.gsub(result.stderr, "%s+$", "")
	return if message == "" then ("bash -n exited %d"):format(result.code) else message
end

function Strip.shell(source: string): (string?, string?, number)
	local spans, problem = Shell.comments(source)
	if spans == nil then
		return nil, problem, 0
	end
	local result, line = stripWith(source, spans)
	local invalid = shellSyntax(result)
	if invalid ~= nil then
		return nil, invalid, 0
	end
	return result, nil, line
end

return table.freeze(Strip)
