--!strict

local Cst = require("./cst")

export type Span = { start: number, finish: number }

export type SourceMap = {
	source: string,
	result: Cst.ParseResult,
	tokens: { [Cst.Token]: Span },
	exprs: { [Cst.Expr]: Span },
	literals: { Span },
	lines: { number },
	printed: string,
}

local SourceMap = {}

local WHITESPACE: { [number]: boolean } =
	{ [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [32] = true }

local function longLevel(source: string, at: number): number?
	if string.byte(source, at + 1) ~= 91 then
		return nil
	end
	local index = at + 2
	local level = 0
	while string.byte(source, index) == 61 do
		level += 1
		index += 1
	end
	if string.byte(source, index) == 91 then
		return level
	end
	return nil
end

local function longEnd(source: string, at: number, level: number): number
	local closing = "]" .. string.rep("=", level) .. "]"
	local found = string.find(source, closing, at + 1, true)
	if found == nil then
		return #source
	end
	return found - 1 + #closing
end

function SourceMap.skipTrivia(source: string, at: number, literals: { Span }?, statements: boolean?): number
	local index = at
	local length = #source
	if index == 0 and string.sub(source, 1, 2) == "#!" then
		local newline = string.find(source, "\n", 1, true)
		index = if newline then newline else length
	end
	while index < length do
		local byte = string.byte(source, index + 1)
		if WHITESPACE[byte] or (statements and byte == 59) then
			index += 1
		elseif byte == 45 and string.byte(source, index + 2) == 45 then
			local level = longLevel(source, index + 2)
			if level ~= nil then
				local finish = longEnd(source, index + 2, level)
				if literals ~= nil and string.find(string.sub(source, index + 1, finish), "\n", 1, true) then
					table.insert(literals, { start = index, finish = finish })
				end
				index = finish
			else
				local newline = string.find(source, "\n", index + 1, true)
				index = if newline then newline - 1 else length
			end
		else
			break
		end
	end
	return index
end

function SourceMap.lineEnd(source: string, at: number): number
	local index = at
	local length = #source
	while index < length do
		local byte = string.byte(source, index + 1)
		if byte == 10 then
			return index + 1
		elseif byte == 32 or byte == 9 or byte == 13 then
			index += 1
		elseif byte == 45 and string.byte(source, index + 2) == 45 then
			local level = longLevel(source, index + 2)
			if level ~= nil then
				local finish = longEnd(source, index + 2, level)
				if string.find(string.sub(source, index + 1, finish), "\n", 1, true) then
					return at
				end
				index = finish
			else
				local newline = string.find(source, "\n", index + 1, true)
				return if newline then newline else length
			end
		else
			return at
		end
	end
	return index
end

local function quoted(style: string, depth: number, text: string): string
	if style == "single" then
		return "'" .. text .. "'"
	elseif style == "double" then
		return '"' .. text .. '"'
	elseif style == "block" then
		local equals = string.rep("=", depth)
		return "[" .. equals .. "[" .. text .. "]" .. equals .. "]"
	end
	return "`" .. text .. "`"
end

function SourceMap.build(source: string, result: Cst.ParseResult): SourceMap
	local tokens: { [Cst.Token]: Span } = {}
	local exprs: { [Cst.Expr]: Span } = {}
	local literals: { Span } = {}
	local cursor = 0
	local lastFinish = 0
	local open: { Cst.Expr } = {}
	local starts: { [Cst.Expr]: number } = {}
	local pending = 1
	local pieces: { string } = {}

	local function expect(token: Cst.Token, text: string)
		local start = SourceMap.skipTrivia(source, cursor, literals, string.byte(text, 1) ~= 59)
		if string.sub(source, start + 1, start + #text) ~= text then
			local line = 1
			for _ in string.gmatch(string.sub(source, 1, start), "\n") do
				line += 1
			end
			error(
				string.format(
					"the syntax tree does not match the source at line %d: expected %q, found %q",
					line,
					text,
					string.sub(source, start + 1, start + math.max(#text, 12))
				),
				0
			)
		end
		table.insert(pieces, string.sub(source, cursor + 1, start))
		table.insert(pieces, text)
		local span = { start = start, finish = start + #text }
		tokens[token] = span
		if string.find(text, "\n", 1, true) then
			table.insert(literals, span)
		end
		for index = pending, #open do
			starts[open[index]] = start
		end
		pending = #open + 1
		cursor = span.finish
		lastFinish = span.finish
	end

	local walker = Cst.walker()
	walker.visitToken = function(token: Cst.Token): boolean
		expect(token, token.text)
		return false
	end
	walker.visitExprConstantString = function(node: Cst.String): boolean
		expect(node.value, quoted(node.quoteStyle, node.blockDepth, node.value.text))
		return false
	end
	walker.visitTypeSingletonString = function(node): boolean
		expect(node.value, quoted(node.quoteStyle, 0, node.value.text))
		return false
	end
	walker.visitExprInterpString = function(node: Cst.Interpolated): boolean
		local count = #node.strings
		for index = 1, count do
			local prefix = if index == 1 then "`" else "}"
			local suffix = if index == count then "`" else "{"
			expect(node.strings[index], prefix .. node.strings[index].text .. suffix)
			if index < count then
				Cst.visitExpression(node.expressions[index], walker)
			end
		end
		return false
	end
	walker.visitTableTypeItem = function(node: Cst.TypeTableEntry): boolean
		local access = node.access
		if access then
			expect(access, access.text)
		end
		local opening = node.indexerOpen
		if opening then
			expect(opening, opening.text)
		end
		if node.kind == "indexer" then
			Cst.visitType(node.key :: Cst.Type, walker)
		else
			local key = node.key :: Cst.Token
			local quote = if node.quoteStyle == "single" then "'" elseif node.quoteStyle == "double" then '"' else ""
			expect(key, quote .. key.text .. quote)
		end
		local closing = node.indexerClose
		if closing then
			expect(closing, closing.text)
		end
		expect(node.colon, node.colon.text)
		Cst.visitType(node.value, walker)
		local separator = node.separator
		if separator then
			expect(separator, separator.text)
		end
		return false
	end
	walker.visitExpr = function(node: Cst.Expr): boolean
		table.insert(open, node)
		pending = math.min(pending, #open)
		return true
	end
	walker.visitExprEnd = function(node: Cst.Expr)
		local top = table.remove(open)
		assert(top == node, "the syntax walk lost its expression stack")
		exprs[node] = { start = starts[node] or lastFinish, finish = lastFinish }
		starts[node] = nil
		pending = math.min(pending, #open + 1)
	end

	Cst.visitBlock(result.root, walker)
	expect(result.eof, "")
	if cursor ~= #source then
		error(string.format("the syntax tree covers %d of %d bytes", cursor, #source), 0)
	end
	local lines = { 0 }
	local index = 1
	while true do
		local found = string.find(source, "\n", index, true)
		if found == nil then
			break
		end
		table.insert(lines, found)
		index = found + 1
	end
	return {
		source = source,
		result = result,
		tokens = tokens,
		exprs = exprs,
		literals = literals,
		printed = table.concat(pieces),
		lines = lines,
	}
end

function SourceMap.parse(source: string): (SourceMap?, string?)
	local parsed, result = pcall(Cst.parse, source)
	if not parsed then
		return nil, (string.gsub(tostring(result), "^.-parsing failed:%s*", ""))
	end
	local mapped, map = pcall(SourceMap.build, source, result :: Cst.ParseResult)
	if not mapped then
		return nil, tostring(map)
	end
	return map :: SourceMap, nil
end

function SourceMap.token(map: SourceMap, token: Cst.Token): Span
	return assert(map.tokens[token], "the token has no source position")
end

function SourceMap.expr(map: SourceMap, node: Cst.Expr): Span
	return assert(map.exprs[node], "the expression has no source position")
end

function SourceMap.slice(map: SourceMap, span: Span): string
	return string.sub(map.source, span.start + 1, span.finish)
end

function SourceMap.item(map: SourceMap, item: Cst.TableItem): Span
	local start: number
	if item.kind == "record" then
		start = SourceMap.token(map, item.key).start
	elseif item.kind == "general" then
		start = SourceMap.token(map, item.indexerOpen).start
	else
		start = SourceMap.expr(map, item.value).start
	end
	local finish = if item.separator
		then SourceMap.token(map, item.separator).finish
		else SourceMap.expr(map, item.value).finish
	return { start = start, finish = finish }
end

function SourceMap.core(map: SourceMap, item: Cst.TableItem): Span
	local whole = SourceMap.item(map, item)
	return { start = whole.start, finish = SourceMap.expr(map, item.value).finish }
end

function SourceMap.line(map: SourceMap, offset: number): (number, number)
	local starts = map.lines
	local low, high = 1, #starts
	while low < high do
		local middle = (low + high + 1) // 2
		if starts[middle] <= offset then
			low = middle
		else
			high = middle - 1
		end
	end
	return low, offset - starts[low] + 1
end

function SourceMap.protected(map: SourceMap, start: number, finish: number): { Span }
	local inside: { Span } = {}
	for _, span in map.literals do
		if span.finish > start and span.start < finish then
			table.insert(inside, span)
		end
	end
	return inside
end

return table.freeze(SourceMap)
