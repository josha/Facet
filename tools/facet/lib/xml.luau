--!strict

export type Element = {
	tag: string,
	attributes: { [string]: string },
	children: { Element },
	text: string,
	content: string,
}

local Xml = {}

local ENTITIES: { [string]: string } = {
	lt = "<",
	gt = ">",
	amp = "&",
	quot = '"',
	apos = "'",
}

function Xml.decode(text: string): string
	if string.find(text, "&", 1, true) == nil then
		return text
	end
	local decoded = string.gsub(text, "&(#?[%w]+);", function(entity: string): string
		local original = "&" .. entity .. ";"
		if string.sub(entity, 1, 2) == "#x" or string.sub(entity, 1, 2) == "#X" then
			local code = tonumber(string.sub(entity, 3), 16)
			return if code then utf8.char(code) else original
		elseif string.sub(entity, 1, 1) == "#" then
			local code = tonumber(string.sub(entity, 2))
			return if code then utf8.char(code) else original
		end
		return ENTITIES[entity] or original
	end)
	return decoded
end

local function newElement(tag: string): Element
	return { tag = tag, attributes = {}, children = {}, text = "", content = "" }
end

local function parseAttributes(element: Element, source: string)
	for name, _quote, value in string.gmatch(source, "([%w_:%.%-]+)%s*=%s*(['\"])(.-)%2") do
		if name ~= nil and value ~= nil then
			element.attributes[name] = Xml.decode(value)
		end
	end
end

function Xml.parse(source: string): Element
	local text = string.gsub(string.gsub(source, "\r\n", "\n"), "\r", "\n")
	local document = newElement("#document")
	local stack: { Element } = { document }
	local first: { string } = {}
	local pieces: { { string } } = { first }
	local index = 1
	local length = #text
	local function append(value: string)
		local current = stack[#stack]
		local buffer = pieces[#pieces]
		table.insert(buffer, value)
		if #current.children == 0 then
			current.text ..= value
		end
	end
	while index <= length do
		local open = string.find(text, "<", index, true)
		if open == nil then
			append(Xml.decode(string.sub(text, index)))
			break
		end
		if open > index then
			append(Xml.decode(string.sub(text, index, open - 1)))
		end
		if string.sub(text, open, open + 8) == "<![CDATA[" then
			local close = string.find(text, "]]>", open + 9, true)
			if close == nil then
				error("unterminated CDATA section", 0)
			end
			append(string.sub(text, open + 9, close - 1))
			index = close + 3
		elseif string.sub(text, open, open + 3) == "<!--" then
			local close = string.find(text, "-->", open + 4, true)
			if close == nil then
				error("unterminated XML comment", 0)
			end
			index = close + 3
		elseif string.sub(text, open, open + 1) == "<?" then
			local close = string.find(text, "?>", open + 2, true)
			if close == nil then
				error("unterminated processing instruction", 0)
			end
			index = close + 2
		elseif string.sub(text, open, open + 1) == "<!" then
			local close = string.find(text, ">", open + 2, true)
			if close == nil then
				error("unterminated declaration", 0)
			end
			index = close + 1
		elseif string.sub(text, open, open + 1) == "</" then
			local close = string.find(text, ">", open + 2, true)
			if close == nil then
				error("unterminated closing tag", 0)
			end
			local name = string.match(string.sub(text, open + 2, close - 1), "^%s*([^%s>]+)")
			local current = stack[#stack]
			if #stack == 1 or name ~= current.tag then
				error(("mismatched closing tag </%s>"):format(tostring(name)), 0)
			end
			current.content = table.concat(pieces[#pieces])
			table.remove(stack)
			table.remove(pieces)
			index = close + 1
		else
			local close = open + 1
			local quote: string? = nil
			while close <= length do
				local char = string.sub(text, close, close)
				if quote ~= nil then
					if char == quote then
						quote = nil
					end
				elseif char == '"' or char == "'" then
					quote = char
				elseif char == ">" then
					break
				end
				close += 1
			end
			if close > length then
				error("unterminated tag", 0)
			end
			local body = string.sub(text, open + 1, close - 1)
			local selfClosing = string.sub(body, -1) == "/"
			if selfClosing then
				body = string.sub(body, 1, -2)
			end
			local name = string.match(body, "^([^%s/>]+)")
			if name == nil then
				error("malformed tag", 0)
			end
			local element = newElement(name)
			parseAttributes(element, string.sub(body, #name + 1))
			table.insert(stack[#stack].children, element)
			if not selfClosing then
				table.insert(stack, element)
				local fresh: { string } = {}
				table.insert(pieces, fresh)
			end
			index = close + 1
		end
	end
	if #stack ~= 1 then
		error(("unclosed element <%s>"):format(stack[#stack].tag), 0)
	end
	document.content = table.concat(pieces[1])
	local root = nil
	for _, child in document.children do
		root = child
		break
	end
	if root == nil then
		error("the document has no root element", 0)
	end
	return root
end

function Xml.children(element: Element, tag: string): { Element }
	local found: { Element } = {}
	for _, child in element.children do
		if child.tag == tag then
			table.insert(found, child)
		end
	end
	return found
end

function Xml.first(element: Element, tag: string): Element?
	for _, child in element.children do
		if child.tag == tag then
			return child
		end
	end
	return nil
end

function Xml.descendants(element: Element, tag: string): { Element }
	local found: { Element } = {}
	local function visit(node: Element)
		for _, child in node.children do
			if child.tag == tag then
				table.insert(found, child)
			end
			visit(child)
		end
	end
	visit(element)
	return found
end

return table.freeze(Xml)
