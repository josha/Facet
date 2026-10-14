--!strict

export type Span = { start: number, stop: number }

type Heredoc = { delimiter: string, stripTabs: boolean }

local Shell = {}

local WORD_BREAKS: { [string]: boolean } = {
	[" "] = true,
	["\t"] = true,
	["\r"] = true,
	[";"] = true,
	["|"] = true,
	["&"] = true,
	["("] = true,
	[")"] = true,
	["<"] = true,
	[">"] = true,
}

local DELIMITER_BREAKS: { [string]: boolean } = table.clone(WORD_BREAKS)
DELIMITER_BREAKS["\n"] = true

local function fail(message: string): never
	error(message, 0)
end

function Shell.comments(source: string): ({ Span }?, string?)
	local length = #source
	local found: { Span } = {}

	local function at(index: number): string
		return string.sub(source, index, index)
	end

	local function startsWith(index: number, prefix: string): boolean
		return string.sub(source, index, index + #prefix - 1) == prefix
	end

	local code: (number, string?) -> number
	local expansion: (number) -> number?

	local function singleQuote(start: number, escaped: boolean): number
		local index = start + 1
		while index <= length do
			local char = at(index)
			if escaped and char == "\\" then
				index += 2
			elseif char == "'" then
				return index + 1
			else
				index += 1
			end
		end
		return fail("unterminated shell single quote")
	end

	local function doubleQuote(start: number): number
		local index = start + 1
		while index <= length do
			local char = at(index)
			if char == "\\" then
				index += 2
			elseif char == '"' then
				return index + 1
			else
				index = expansion(index) or index + 1
			end
		end
		return fail("unterminated shell double quote")
	end

	local function balanced(start: number, opener: string, closer: string): number
		local depth = 1
		local index = start
		while index <= length do
			local char = at(index)
			if char == "\\" then
				index += 2
			elseif char == "'" then
				index = singleQuote(index, false)
			elseif char == '"' then
				index = doubleQuote(index)
			else
				local expanded = expansion(index)
				if expanded ~= nil then
					index = expanded
				elseif char == closer then
					depth -= 1
					index += 1
					if depth == 0 then
						return index
					end
				else
					if char == opener then
						depth += 1
					end
					index += 1
				end
			end
		end
		return fail("unterminated shell expansion")
	end

	expansion = function(index: number): number?
		if startsWith(index, "$((") then
			return balanced(index + 2, "(", ")")
		elseif startsWith(index, "$(") then
			return code(index + 2, ")")
		elseif startsWith(index, "${") then
			return balanced(index + 2, "{", "}")
		elseif startsWith(index, "$'") then
			return singleQuote(index + 1, true)
		elseif at(index) == "`" then
			return code(index + 1, "`")
		end
		return nil
	end

	local function heredoc(start: number): (number, Heredoc)
		local index = start
		local stripTabs = at(index) == "-"
		if stripTabs then
			index += 1
		end
		while at(index) == " " or at(index) == "\t" do
			index += 1
		end
		local parts: { string } = {}
		while index <= length and not DELIMITER_BREAKS[at(index)] do
			local char = at(index)
			if char == '"' or char == "'" then
				local closing: number = string.find(source, char, index + 1, true)
					or fail("unterminated heredoc delimiter")
				table.insert(parts, string.sub(source, index + 1, closing - 1))
				index = closing + 1
			elseif char == "\\" then
				table.insert(parts, string.sub(source, index + 1, index + 1))
				index += 2
			else
				table.insert(parts, char)
				index += 1
			end
		end
		if #parts == 0 then
			fail("missing heredoc delimiter")
		end
		return index, { delimiter = table.concat(parts), stripTabs = stripTabs }
	end

	local function skipHeredocs(start: number, pending: { Heredoc }): number
		local index = start
		for _, document in pending do
			local closed = false
			while index <= length do
				local newline = string.find(source, "\n", index, true)
				local stop = if newline == nil then length + 1 else newline + 1
				local line = string.gsub(string.sub(source, index, stop - 1), "[\r\n]+$", "")
				if document.stripTabs then
					line = string.gsub(line, "^\t+", "")
				end
				index = stop
				if line == document.delimiter then
					closed = true
					break
				end
			end
			if not closed then
				fail("unterminated shell heredoc")
			end
		end
		return index
	end

	code = function(start: number, terminator: string?): number
		local wordStart = true
		local pending: { Heredoc } = {}
		local depth = 0
		local index = start
		while index <= length do
			local char = at(index)
			if terminator ~= nil and char == terminator and depth == 0 then
				return index + 1
			end
			if char == "#" and wordStart then
				local newline = string.find(source, "\n", index, true)
				local stop = if newline == nil then length + 1 else newline
				table.insert(found, { start = index, stop = stop })
				index = stop
			elseif char == "\\" then
				if at(index + 1) ~= "\n" then
					wordStart = false
				end
				index += 2
			elseif char == "'" then
				index = singleQuote(index, false)
				wordStart = false
			elseif char == '"' then
				index = doubleQuote(index)
				wordStart = false
			else
				local expanded = expansion(index)
				if expanded ~= nil then
					index = expanded
					wordStart = false
				elseif startsWith(index, "((") then
					index = balanced(index + 1, "(", ")")
					wordStart = true
				elseif startsWith(index, "<<<") then
					index += 3
					wordStart = true
				elseif startsWith(index, "<<") then
					local after, document = heredoc(index + 2)
					index = after
					table.insert(pending, document)
					wordStart = true
				elseif char == "\n" then
					index = skipHeredocs(index + 1, pending)
					table.clear(pending)
					wordStart = true
				else
					if terminator == ")" then
						if char == "(" then
							depth += 1
						elseif char == ")" and depth > 0 then
							depth -= 1
						end
					end
					wordStart = WORD_BREAKS[char] == true
					index += 1
				end
			end
		end
		if terminator ~= nil or #pending > 0 then
			fail("unterminated shell command substitution or heredoc")
		end
		return index
	end

	local ok, problem = pcall(code, 1, nil)
	if not ok then
		return nil, tostring(problem)
	end
	return found, nil
end

return table.freeze(Shell)
