--!strict

export type Allowlist = { allows: { string }, denies: { string } }

type Token = {
	kind: string,
	byte: number?,
	negated: boolean?,
	ranges: { { number } }?,
}

local Allowlist = {}

local compiled: { [string]: { Token } } = {}

function Allowlist.parse(text: string): Allowlist
	local allows: { string } = {}
	local denies: { string } = {}
	for _, raw in string.split(string.gsub(text, "\r\n", "\n"), "\n") do
		local line = string.match(raw, "^%s*(.-)%s*$") or ""
		if line == "" or string.sub(line, 1, 1) == "#" then
			continue
		end
		if string.sub(line, 1, 1) == "!" then
			local pattern = string.match(line, "^!+(.*)$") or ""
			table.insert(denies, pattern)
		else
			table.insert(allows, line)
		end
	end
	return { allows = allows, denies = denies }
end

local function compile(pattern: string): { Token }
	local cached = compiled[pattern]
	if cached ~= nil then
		return cached
	end
	local tokens: { Token } = {}
	local index = 1
	local length = #pattern
	while index <= length do
		local character = string.sub(pattern, index, index)
		if character == "*" then
			if #tokens == 0 or tokens[#tokens].kind ~= "star" then
				table.insert(tokens, { kind = "star" })
			end
			index += 1
		elseif character == "?" then
			table.insert(tokens, { kind = "any" })
			index += 1
		elseif character == "[" then
			local cursor = index + 1
			if string.sub(pattern, cursor, cursor) == "!" then
				cursor += 1
			end
			if string.sub(pattern, cursor, cursor) == "]" then
				cursor += 1
			end
			while cursor <= length and string.sub(pattern, cursor, cursor) ~= "]" do
				cursor += 1
			end
			if cursor > length then
				table.insert(tokens, { kind = "byte", byte = string.byte("[") })
				index += 1
			else
				local body = string.sub(pattern, index + 1, cursor - 1)
				local negated = string.sub(body, 1, 1) == "!"
				if negated then
					body = string.sub(body, 2)
				end
				local ranges: { { number } } = {}
				local position = 1
				while position <= #body do
					local low = string.byte(body, position) :: number
					if string.sub(body, position + 1, position + 1) == "-" and position + 2 <= #body then
						local high = string.byte(body, position + 2) :: number
						table.insert(ranges, { low, high })
						position += 3
					else
						table.insert(ranges, { low, low })
						position += 1
					end
				end
				table.insert(tokens, { kind = "set", negated = negated, ranges = ranges })
				index = cursor + 1
			end
		else
			table.insert(tokens, { kind = "byte", byte = string.byte(character) })
			index += 1
		end
	end
	compiled[pattern] = tokens
	return tokens
end

local function single(token: Token, byte: number): boolean
	if token.kind == "any" then
		return true
	elseif token.kind == "byte" then
		return token.byte == byte
	elseif token.kind == "set" then
		local inside = false
		local ranges: { { number } } = token.ranges or {}
		for _, range in ranges do
			if byte >= range[1] and byte <= range[2] then
				inside = true
				break
			end
		end
		return if token.negated then not inside else inside
	end
	return false
end

function Allowlist.glob(path: string, pattern: string): boolean
	local tokens = compile(pattern)
	local tokenIndex = 1
	local byteIndex = 1
	local starToken: number? = nil
	local starByte = 0
	local length = #path
	while byteIndex <= length do
		local token = tokens[tokenIndex]
		if token ~= nil and token.kind == "star" then
			starToken = tokenIndex
			starByte = byteIndex
			tokenIndex += 1
		elseif token ~= nil and single(token, string.byte(path, byteIndex) :: number) then
			tokenIndex += 1
			byteIndex += 1
		elseif starToken ~= nil then
			tokenIndex = starToken + 1
			starByte += 1
			byteIndex = starByte
		else
			return false
		end
	end
	while tokens[tokenIndex] ~= nil and tokens[tokenIndex].kind == "star" do
		tokenIndex += 1
	end
	return tokens[tokenIndex] == nil
end

function Allowlist.matches(path: string, pattern: string): boolean
	if string.sub(pattern, -1) == "/" then
		return string.sub(path, 1, #pattern) == pattern
	end
	if path == pattern then
		return true
	end
	return Allowlist.glob(path, pattern)
end

function Allowlist.allowed(list: Allowlist, path: string): boolean
	for _, pattern in list.allows do
		if Allowlist.matches(path, pattern) then
			return true
		end
	end
	return false
end

function Allowlist.denied(list: Allowlist, path: string): boolean
	for _, pattern in list.denies do
		if Allowlist.matches(path, pattern) then
			return true
		end
	end
	return false
end

function Allowlist.public(list: Allowlist, path: string): boolean
	return Allowlist.allowed(list, path) and not Allowlist.denied(list, path)
end

return table.freeze(Allowlist)
