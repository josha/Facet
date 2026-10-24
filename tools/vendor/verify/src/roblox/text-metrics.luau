--!strict

export type Row = {
	advances: { number },
	adjustments: { number },
	starts: { number }?,
	ends: { number }?,
	height: number?,
}
export type Face = { tokens: { string }, pairs: { { number } }, sizes: { Row } }
export type Model = {
	width: (text: string, size: number) -> number,
	height: (size: number) -> number,
	wrap: (text: string, size: number, limit: number) -> (number, number),
}

local function create(face: Face): Model
	local indices: { [string]: number } = {}
	local sequences: { [string]: { string } } = {}
	for index, token in face.tokens do
		indices[token] = index
		local first = token:sub(1, 1)
		local entries = sequences[first] or {}
		table.insert(entries, token)
		sequences[first] = entries
	end
	for _, entries in sequences do
		table.sort(entries, function(left, right): boolean
			return #left > #right
		end)
	end
	local pairs: { [number]: { [number]: number } } = {}
	for index, pair in face.pairs do
		local row = pairs[pair[1]] or {}
		row[pair[2]] = index
		pairs[pair[1]] = row
	end
	local function width(text: string, size: number): number
		local row = assert(face.sizes[math.clamp(math.floor(size), 1, 100)])
		local cursor, total = 1, 0
		local previous: number? = nil
		local first: number? = nil
		local latin = false
		local latinBoundary = 0
		while cursor <= #text do
			local token: string? = nil
			local entries: { string } = sequences[text:sub(cursor, cursor)] or {}
			for _, sequence in entries do
				if text:sub(cursor, cursor + #sequence - 1) == sequence then
					token = sequence
					break
				end
			end
			if token == nil then
				error("unsupported_text_metrics: character at byte " .. cursor, 0)
			end
			local matched = assert(token)
			local index = indices[matched]
			first = first or index
			total += row.advances[index]
			local startsLatin = not latin and matched:match "%a" ~= nil
			if startsLatin and previous and row.starts then
				latinBoundary = row.starts[index]
			end
			if previous and not startsLatin then
				local pair = (pairs[previous] or {})[index]
				if pair then
					total += row.adjustments[pair]
				end
			end
			latin = latin or startsLatin
			previous = index
			cursor += #matched
		end
		return math.ceil(
			total
				+ (if first and row.starts then row.starts[first] else 0)
				+ latinBoundary
				+ (if previous and row.ends then row.ends[previous] else 0)
				- (if previous and row.starts and face.tokens[previous]:match "%a" then row.starts[previous] else 0)
		)
	end
	local function wrap(text: string, size: number, limit: number): (number, number)
		local maximum, count = 0, 0
		for _, paragraph in string.split(text, "\n") do
			if limit <= 0 then
				maximum = math.max(maximum, width(paragraph, size))
				count += 1
				continue
			end
			local line = paragraph:match "^ *" or ""
			local function finish(trim: boolean)
				local measured = width(line, size)
				if (trim or measured > limit) and line:match "[^ ]" then
					measured = width(line:gsub(" +$", ""), size)
				end
				maximum = math.max(maximum, measured)
				count += 1
			end
			local cursor = #line + 1
			while cursor <= #paragraph do
				local word, spaces = paragraph:match("^([^ ]+)( *)", cursor)
				assert(word and spaces)
				if width(word, size) > limit then
					error("unsupported_text_metrics: word exceeds wrap width", 0)
				end
				if line ~= "" and width(line .. word, size) > limit then
					finish(true)
					line = ""
				end
				line ..= word .. spaces
				cursor += #word + #spaces
			end
			finish(false)
		end
		return maximum, count
	end
	local function height(size: number): number
		local index = math.clamp(math.floor(size), 1, 100)
		return face.sizes[index].height or index
	end
	return table.freeze { width = width, wrap = wrap, height = height }
end

return table.freeze { create = create }
