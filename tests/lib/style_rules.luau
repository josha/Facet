--!strict
type Compound = { class: string?, tags: { string }, state: string? }
type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

local function compound(text: string): Compound
	local tags = {}
	for tag in string.gmatch(text, "%.([%w%-]+)") do
		table.insert(tags, tag)
	end
	return { class = string.match(text, "^(%a%w*)"), tags = tags, state = string.match(text, ":(%a+)$") }
end

local function parse(selector: string): Selector
	local pseudo = string.match(selector, "::(%a+)$")
	local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
	local parts, combinators = {}, {}
	while true do
		local first, last, combinator = string.find(rest, " (>>?) ")
		if not first then
			table.insert(parts, compound(rest))
			break
		end
		table.insert(parts, compound(string.sub(rest, 1, first - 1)))
		table.insert(combinators, combinator :: string)
		rest = string.sub(rest, (last :: number) + 1)
	end
	return { parts = parts, combinators = combinators, pseudo = pseudo }
end

local function matchesPart(part: Compound, node: any): boolean
	if part.class and not node:IsA(part.class) then
		return false
	end
	for _, tag in part.tags do
		if not node:HasTag(tag) then
			return false
		end
	end
	if part.state then
		local ok, state = pcall(function()
			return node.GuiState
		end)
		if not ok or state == nil or state.Name ~= part.state then
			return false
		end
	end
	return true
end

local function matchesAt(selector: Selector, index: number, node: any): boolean
	if not matchesPart(selector.parts[index], node) then
		return false
	end
	if index == 1 then
		return true
	end
	local parent = node.Parent
	if selector.combinators[index - 1] == ">" then
		return parent ~= nil and matchesAt(selector, index - 1, parent)
	end
	while parent do
		if matchesAt(selector, index - 1, parent) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function resolve(sheet: any, node: any, property: string, pseudo: string?): any
	local best, value = -math.huge, nil
	for _, rule in sheet:GetChildren() do
		local selector = parse(rule.Selector)
		if selector.pseudo == pseudo and matchesAt(selector, #selector.parts, node) then
			local candidate = rule:GetProperties()[property]
			if candidate ~= nil and rule.Priority > best then
				best, value = rule.Priority, candidate
			end
		end
	end
	return value
end

return { resolve = resolve }
