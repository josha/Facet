--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local document = require("./document")
local library = require("./library")

local source = {}

local function tokenize(code: string): { any }
	assert(#code <= 250000, "Component source exceeds 250 KB")
	local tokens: { any } = {}
	local index = 1
	while index <= #code do
		local char = string.sub(code, index, index)
		if string.match(char, "%s") then
			index += 1
		elseif string.sub(code, index, index + 1) == "--" then
			local finish = string.find(code, "\n", index + 2, true)
			index = if finish then finish + 1 else #code + 1
		elseif char == '"' or char == "'" then
			local quote, pieces, closed = char, {}, false
			index += 1
			while index <= #code do
				local current: string = string.sub(code, index, index)
				index += 1
				if current == quote then
					closed = true
					break
				end
				if current == "\\" then
					local escaped = string.sub(code, index, index)
					index += 1
					local escapes = {
						n = "\n",
						r = "\r",
						t = "\t",
						a = "\a",
						b = "\b",
						f = "\f",
						v = "\v",
						['"'] = '"',
						["'"] = "'",
						["\\"] = "\\",
						["\n"] = "\n",
					}
					if escapes[escaped] then
						current = escapes[escaped]
					elseif string.match(escaped, "%d") then
						local digits = escaped
						for _ = 1, 2 do
							local digit = string.sub(code, index, index)
							if not string.match(digit, "%d") then
								break
							end
							digits ..= digit
							index += 1
						end
						local value = assert(tonumber(digits))
						assert(value <= 255, "Invalid byte escape")
						current = string.char(value)
					else
						error("Unsupported string escape in component source")
					end
				end
				table.insert(pieces, current)
			end
			assert(closed, "Unclosed string in component source")
			table.insert(tokens, { kind = "literal" :: "literal", value = table.concat(pieces) })
		elseif string.match(char, "[%a_]") then
			local value = assert(string.match(string.sub(code, index), "^[%a_][%w_]*"))
			table.insert(tokens, { kind = "word" :: "word", value = value })
			index += #value
		elseif
			string.match(char, "%d") or (char == "-" and string.match(string.sub(code, index + 1, index + 1), "%d"))
		then
			local value = assert(string.match(string.sub(code, index), "^%-?%d+%.?%d*[eE]?[%+%-]?%d*"))
			table.insert(tokens, { kind = "literal" :: "literal", value = assert(tonumber(value), "Invalid number") })
			index += #value
		else
			table.insert(tokens, { kind = "symbol" :: "symbol", value = char })
			index += 1
		end
	end
	return tokens
end

function source.parse(code: string, name: string): document.Document
	local tokens = tokenize(code)
	local cursor = 1
	local states: { [string]: any } = {}
	local anchors: { [string]: any } = {}
	local function peek(offset: number?): any
		return tokens[cursor + (offset or 0)] and tokens[cursor + (offset or 0)].value
	end
	local function take(value: any?)
		local token = assert(tokens[cursor], "Unexpected end of component source")
		assert(
			value == nil or token.value == value,
			`Expected {tostring(value)}, got {tostring(token.value)}. Custom expressions need a code adapter.`
		)
		cursor += 1
		return token
	end
	local function sequence(items: { any })
		for _, item in items do
			take(item)
		end
	end
	sequence({
		"local",
		"Facet",
		"=",
		"require",
		"(",
		"game",
		".",
		"ReplicatedStorage",
		".",
		"Facet",
		")",
		"local",
		"Compose",
		"=",
		"Facet",
		".",
		"Compose",
		"return",
		"function",
		"(",
		"UI",
	})
	if peek() == ":" then
		sequence({ ":", "Facet", ".", "Controls" })
	end
	take(")")
	if peek() == ":" then
		sequence({ ":", "GuiObject" })
	end
	local expression: any
	local node: any
	local function callback(): any
		local start, nesting = cursor, 0
		repeat
			local word = take().value
			if word == "function" then
				nesting += 1
			elseif word == "end" then
				nesting -= 1
			end
		until nesting == 0
		local actual = {}
		for index = start, cursor - 1 do
			table.insert(actual, tokens[index])
		end
		local function matches(text: string): boolean
			local expected = tokenize(text)
			if #expected ~= #actual then
				return false
			end
			for index, token in expected do
				if actual[index].kind ~= token.kind or actual[index].value ~= token.value then
					return false
				end
			end
			return true
		end
		local allowed = matches("function() end")
			or matches("function(value) return true, value end")
			or matches(
				'function(current) return UI.Text "RowLabel" { text = function(use) local row = use(current) return tostring(row.label or row.name or row.id or "Item") end, TextWrapped = true } end'
			)
		if
			not allowed
			and #actual == 10
			and actual[2].value == "("
			and actual[3].value == "row"
			and actual[5].value == "return"
			and actual[6].value == "row"
		then
			allowed = matches("function(row) return row[" .. string.format("%q", tostring(actual[8].value)) .. "] end")
		end
		if not allowed then
			for identifier in states do
				for _, constant in { "value", "true", "false" } do
					if matches("function(value) " .. identifier .. ":set(" .. constant .. ") end") then
						allowed = true
					end
				end
			end
		end
		assert(allowed, "Custom callbacks are retained in source; this component cannot be rewritten visually")
		return { __facetCallback = true }
	end
	expression = function(depth: number?): any
		local level = depth or 0
		assert(level <= 40, "Component expressions exceed 40 levels")
		if peek() == "function" then
			if peek(1) == "(" and peek(2) == ")" and peek(3) == "return" and peek(4) == "UI" then
				sequence({ "function", "(", ")", "return" })
				local body = node(level + 1)
				take("end")
				return { __facetContent = if body.name == "__FacetDesignContent" then body.children else { body } }
			end
			return callback()
		elseif peek() == "{" then
			take("{")
			local result, index = {}, 1
			while peek() ~= "}" do
				local key
				if peek() == "[" then
					take("[")
					key = expression(level + 1)
					sequence({ "]", "=" })
				elseif peek(1) == "=" then
					key = take().value
					take("=")
				else
					key = index
					index += 1
				end
				assert(type(key) == "string" or type(key) == "number", "Table keys must be literal")
				assert(result[key] == nil, "Duplicate table key")
				result[key] = expression(level + 1)
				if peek() == "," then
					take(",")
				elseif peek() ~= "}" then
					error("Expected a comma in a table")
				end
			end
			take("}")
			return result
		elseif peek() == "UDim2" then
			sequence({ "UDim2", ".", "fromOffset", "(" })
			local width = expression()
			take(",")
			local height = expression()
			take(")")
			return { __facetSize = true, width = width, height = height }
		elseif peek() == "Color3" then
			sequence({ "Color3", ".", "fromRGB", "(" })
			local r = expression()
			take(",")
			local g = expression()
			take(",")
			local b = expression()
			take(")")
			assert(
				type(r) == "number"
					and type(g) == "number"
					and type(b) == "number"
					and r >= 0
					and r <= 255
					and g >= 0
					and g <= 255
					and b >= 0
					and b <= 255,
				"Invalid RGB color"
			)
			return string.format("#%02X%02X%02X", r, g, b)
		end
		local token = take()
		if token.kind == "literal" then
			return token.value
		end
		if token.value == "true" then
			return true
		elseif token.value == "false" then
			return false
		end
		if token.value == "Compose" then
			sequence({ ".", "cell", "(" })
			local result = expression(level + 1)
			take(")")
			return result
		end
		if anchors[token.value] then
			return { __facetAnchor = anchors[token.value] }
		end
		assert(
			states[token.value] ~= nil,
			`Cannot visually edit expression {tostring(token.value)}. The source is retained.`
		)
		return states[token.value]
	end
	local count = 0
	node = function(depth: number): any
		assert(depth <= 40, "Component nesting exceeds 40 levels")
		count += 1
		assert(count <= 1500, "Component exceeds 1500 expressions")
		sequence({ "UI", "." })
		local kind = take().value
		assert(library.definitions[kind], `No design adapter for {kind}`)
		local label = take()
		assert(label.kind == "literal" and type(label.value) == "string", "Use a literal control name")
		local result = { id = "pending", kind = kind, name = label.value, props = {}, children = {} }
		local function collect(item: any): any
			if type(item) ~= "table" then
				return item
			end
			if item.__facetContent then
				for _, child in item.__facetContent do
					table.insert(result.children, child)
				end
				return nil
			end
			if item.__facetCallback then
				return nil
			end
			if item.__facetAnchor then
				result.props.anchorLabel = item.__facetAnchor.props.label
				return nil
			end
			if item.__facetSize then
				result.props.width, result.props.height = item.width, item.height
				return nil
			end
			local cleaned = {}
			local keys: { any } = {}
			for key in item do
				table.insert(keys, key)
			end
			table.sort(keys, function(a, b)
				if type(a) == type(b) then
					return a < b
				end
				return type(a) == "number"
			end)
			for _, key in keys do
				cleaned[key] = collect(item[key])
			end
			return cleaned
		end
		take("{")
		while peek() ~= "}" do
			if peek() == "UI" then
				table.insert(result.children, node(depth + 1))
			elseif string.match(tostring(peek()), "^anchor_n%d+$") then
				expression()
			else
				local key = take().value
				take("=")
				local property = collect(expression(depth + 1))
				if property ~= nil and not (kind == "NumberInput" and key == "value") then
					assert(result.props[key] == nil, "Duplicate component property")
					result.props[key] = library.parse(
						assert(library.descriptor(kind, key), `No visual editor for {kind}.{key}`),
						property
					)
				end
			end
			if peek() == "," then
				take(",")
			elseif peek() ~= "}" then
				error("Expected a comma between component properties")
			end
		end
		take("}")
		if string.match(result.name, "^__FacetDesignHost_n%d+$") then
			return assert(result.children[#result.children])
		end
		return result
	end
	while peek() == "local" do
		take("local")
		local identifier = take().value
		take("=")
		if string.match(identifier, "^anchor_n%d+$") then
			anchors[identifier] = node(1)
		else
			assert(
				string.match(identifier, "^state_n%d+_?%w*$"),
				"Only generated state and anchor declarations are supported"
			)
			states[identifier] = expression()
		end
	end
	take("return")
	local result = document.new(name)
	result.root = node(1)
	local nextId = 1
	local function assign(item)
		item.id = `n{nextId}`
		nextId += 1
		for _, child in item.children do
			assign(child)
		end
	end
	assign(result.root)
	result.nextId = nextId
	take("end")
	assert(cursor > #tokens, "Extra source cannot be rewritten by the visual editor")
	return document.validate(result)
end

return source
