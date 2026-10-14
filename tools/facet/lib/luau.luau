--!strict

local parser = require("@std/syntax/parser")

export type Location = {
	beginLine: number,
	beginColumn: number,
	endLine: number,
	endColumn: number,
}

export type Node = { [string]: unknown }

export type Trivia = { tag: string, text: string, location: Location }

export type Parsed = {
	root: Node,
	eof: Node,
	lines: number,
	lineOffsets: { number },
}

export type Comment = {
	start: number,
	finish: number,
	line: number,
	text: string,
	block: boolean,
}

export type StringLiteral = {
	start: number,
	finish: number,
	line: number,
	value: string,
	style: string,
}

export type Require = {
	path: string,
	dynamic: boolean,
	line: number,
	column: number,
}

export type Call = {
	node: Node,
	callee: string?,
	method: boolean,
	arguments: { Node },
	line: number,
}

local SKIPPED: { [string]: boolean } = { ["local"] = true, shadows = true }

local Luau = {}

function Luau.parse(source: string): (Parsed?, string?)
	local ok, result = pcall(parser.parse, source)
	if not ok then
		local message = string.gsub(tostring(result), "^.-parsing failed:%s*", "")
		return nil, message
	end
	return (result :: unknown) :: Parsed, nil
end

function Luau.offset(parsed: Parsed, line: number, column: number): number
	local base = parsed.lineOffsets[line]
	if base == nil then
		local last = parsed.lineOffsets[#parsed.lineOffsets] or 1
		return last + column - 1
	end
	return base + column - 1
end

function Luau.node(value: unknown): Node?
	if type(value) == "table" then
		return value :: Node
	end
	return nil
end

function Luau.tag(node: Node): string
	local tag = node.tag
	if type(tag) == "string" then
		return tag
	end
	local kind = node.kind
	return if type(kind) == "string" then kind else ""
end

function Luau.kind(node: Node): string
	local kind = node.kind
	return if type(kind) == "string" then kind else ""
end

function Luau.child(node: Node, key: string): Node?
	return Luau.node(node[key])
end

function Luau.items(node: Node, key: string): { Node }
	local value = node[key]
	local found: { Node } = {}
	if type(value) ~= "table" then
		return found
	end
	local list = (value :: unknown) :: { unknown }
	local index = 1
	while true do
		local item = Luau.node(list[index])
		if item == nil then
			break
		end
		table.insert(found, item)
		index += 1
	end
	return found
end

function Luau.text(node: Node?): string?
	if node == nil then
		return nil
	end
	local text = node.text
	return if type(text) == "string" then text else nil
end

function Luau.tokenText(node: Node, key: string): string?
	return Luau.text(Luau.child(node, key))
end

function Luau.location(node: Node): Location
	local location = node.location
	if type(location) == "table" then
		return location :: Location
	end
	return { beginLine = 0, beginColumn = 0, endLine = 0, endColumn = 0 }
end

function Luau.line(node: Node): number
	return Luau.location(node).beginLine
end

function Luau.walk(root: Node, visit: (Node) -> boolean)
	local seen: { [Node]: boolean } = {}
	local function descend(node: Node)
		if seen[node] then
			return
		end
		seen[node] = true
		if Luau.kind(node) ~= "" and not visit(node) then
			return
		end
		local keys: { string } = {}
		local numbered: { Node } = {}
		for key, value in node do
			if type(value) == "table" then
				if type(key) == "string" then
					if
						not SKIPPED[key]
						and key ~= "location"
						and key ~= "leadingTrivia"
						and key ~= "trailingTrivia"
					then
						table.insert(keys, key)
					end
				elseif type(key) == "number" then
					numbered[key] = value :: Node
				end
			end
		end
		local index = 1
		while numbered[index] ~= nil do
			descend(numbered[index])
			index += 1
		end
		table.sort(keys)
		for _, key in keys do
			local child = Luau.node(node[key])
			if child ~= nil then
				descend(child)
			end
		end
	end
	descend(root)
end

function Luau.tokens(parsed: Parsed): { Node }
	local found: { Node } = {}
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "token" then
			table.insert(found, node)
		end
		return true
	end)
	table.insert(found, parsed.eof)
	return found
end

local function triviaOf(node: Node, key: string): { Trivia }
	local list = node[key]
	if type(list) ~= "table" then
		return {}
	end
	return list :: { Trivia }
end

function Luau.comments(parsed: Parsed): { Comment }
	local found: { Comment } = {}
	local seen: { [string]: boolean } = {}
	for _, token in Luau.tokens(parsed) do
		for _, key in { "leadingTrivia", "trailingTrivia" } do
			for _, item in triviaOf(token, key) do
				if item.tag == "comment" or item.tag == "blockcomment" then
					local location = item.location
					local start = Luau.offset(parsed, location.beginLine, location.beginColumn)
					local identity = tostring(start)
					if not seen[identity] then
						seen[identity] = true
						table.insert(found, {
							start = start,
							finish = start + #item.text - 1,
							line = location.beginLine,
							text = item.text,
							block = item.tag == "blockcomment",
						})
					end
				end
			end
		end
	end
	table.sort(found, function(left: Comment, right: Comment): boolean
		return left.start < right.start
	end)
	return found
end

function Luau.stringValue(node: Node): string?
	if Luau.tag(node) ~= "string" then
		return nil
	end
	return Luau.tokenText(node, "value")
end

function Luau.strings(parsed: Parsed): { StringLiteral }
	local found: { StringLiteral } = {}
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "expr" and Luau.tag(node) == "string" then
			local location = Luau.location(node)
			local style = node.quoteStyle
			table.insert(found, {
				start = Luau.offset(parsed, location.beginLine, location.beginColumn),
				finish = Luau.offset(parsed, location.endLine, location.endColumn) - 1,
				line = location.beginLine,
				value = Luau.stringValue(node) or "",
				style = if type(style) == "string" then style else "",
			})
		elseif Luau.kind(node) == "expr" and Luau.tag(node) == "interpolatedstring" then
			for _, piece in Luau.items(node, "strings") do
				local text = Luau.text(piece)
				if text ~= nil then
					table.insert(found, {
						start = 0,
						finish = 0,
						line = Luau.line(piece),
						value = text,
						style = "interp",
					})
				end
			end
		end
		return true
	end)
	return found
end

function Luau.dotted(expression: Node?): string?
	if expression == nil then
		return nil
	end
	local tag = Luau.tag(expression)
	if tag == "global" then
		return Luau.tokenText(expression, "name")
	elseif tag == "local" then
		return Luau.tokenText(expression, "token")
	elseif tag == "indexname" then
		local base = Luau.dotted(Luau.child(expression, "expression"))
		local index = Luau.tokenText(expression, "index")
		if base == nil or index == nil then
			return nil
		end
		local accessor = Luau.tokenText(expression, "accessor") or "."
		return base .. accessor .. index
	elseif tag == "group" then
		return Luau.dotted(Luau.child(expression, "expression"))
	end
	return nil
end

function Luau.calls(parsed: Parsed): { Call }
	local found: { Call } = {}
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "expr" and Luau.tag(node) == "call" then
			table.insert(found, {
				node = node,
				callee = Luau.dotted(Luau.child(node, "func")),
				method = node.self == true,
				arguments = Luau.items(node, "arguments"),
				line = Luau.line(node),
			})
		end
		return true
	end)
	return found
end

local function requireAliases(parsed: Parsed): { [string]: boolean }
	local aliases: { [string]: boolean } = { require = true }
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "stat" and Luau.tag(node) == "local" then
			local values = Luau.items(node, "values")
			for index, variable in Luau.items(node, "variables") do
				local value = values[index]
				if value ~= nil and Luau.tag(value) == "cast" then
					local operand = Luau.child(value, "operand")
					if
						operand ~= nil
						and Luau.tag(operand) == "global"
						and Luau.tokenText(operand, "name") == "require"
					then
						local name = Luau.tokenText(variable, "name")
						if name ~= nil then
							aliases[name] = true
						end
					end
				end
			end
		end
		return true
	end)
	return aliases
end

local function requiredPath(argument: Node): (string?, boolean)
	local tag = Luau.tag(argument)
	if tag == "string" then
		return Luau.stringValue(argument), false
	elseif tag == "binary" and Luau.tokenText(argument, "operator") == ".." then
		local left = Luau.child(argument, "lhsOperand")
		if left ~= nil and Luau.tag(left) == "string" then
			return Luau.stringValue(left), true
		end
	elseif tag == "group" then
		local inner = Luau.child(argument, "expression")
		if inner ~= nil then
			return requiredPath(inner)
		end
	end
	return nil, false
end

function Luau.requires(parsed: Parsed): { Require }
	local aliases = requireAliases(parsed)
	local found: { Require } = {}
	Luau.walk(parsed.root, function(node)
		if Luau.kind(node) == "type" and Luau.tag(node) == "typeof" then
			return false
		end
		if Luau.kind(node) == "expr" and Luau.tag(node) == "call" then
			local func = Luau.child(node, "func")
			local tag = if func then Luau.tag(func) else ""
			local name = if func == nil
				then nil
				elseif tag == "global" then Luau.tokenText(func, "name")
				elseif tag == "local" then Luau.tokenText(func, "token")
				else nil
			if name ~= nil and aliases[name] then
				local argument = Luau.items(node, "arguments")[1]
				if argument ~= nil then
					local requested, dynamic = requiredPath(argument)
					if requested ~= nil then
						local location = Luau.location(node)
						table.insert(found, {
							path = requested,
							dynamic = dynamic,
							line = location.beginLine,
							column = location.beginColumn,
						})
					end
				end
			end
		end
		return true
	end)
	table.sort(found, function(left: Require, right: Require): boolean
		if left.line ~= right.line then
			return left.line < right.line
		end
		return left.column < right.column
	end)
	return found
end

function Luau.code(source: string, parsed: Parsed): string
	local parts: { string } = {}
	local cursor = 1
	for _, comment in Luau.comments(parsed) do
		table.insert(parts, string.sub(source, cursor, comment.start - 1))
		local blanked = string.gsub(string.sub(source, comment.start, comment.finish), "[^\n]", " ")
		table.insert(parts, blanked)
		cursor = comment.finish + 1
	end
	table.insert(parts, string.sub(source, cursor))
	return table.concat(parts)
end

function Luau.lineOf(source: string, offset: number): number
	local _, count = string.gsub(string.sub(source, 1, offset - 1), "\n", "")
	return count + 1
end

return table.freeze(Luau)
