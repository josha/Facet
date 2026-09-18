--!strict

export type Fields = {
	component: string?,
	node: string?,
	kind: string?,
	key: string?,
	event: string?,
	index: number?,
	expected: string?,
	actual: string?,
	contract: string?,
	fix: string?,
	detail: string?,
}

local function format(code: string, summary: string, fields: Fields?): string
	local lines = { ("Compose[%s]: %s"):format(code, summary) }

	if fields ~= nil then
		local function line(name: string, value: (string | number)?)
			if value ~= nil then
				table.insert(lines, ("  %s: %s"):format(name, tostring(value)))
			end
		end
		line("component", fields.component)
		line("node", fields.node)
		line("kind", fields.kind)
		line("key", fields.key)
		line("event", fields.event)
		line("index", fields.index)
		line("expected", fields.expected)
		line("actual", fields.actual)
		line("detail", fields.detail)
		line("contract", fields.contract)
		line("fix", fields.fix)
	end

	table.insert(lines, ("  see: docs/troubleshooting.md#%s"):format((string.gsub(code, "/", "-"))))
	return table.concat(lines, "\n")
end

local function raise(code: string, summary: string, fields: Fields?, level: number?): never
	return error(format(code, summary, fields), if level ~= nil then level else 0) :: never
end

local function describe(value: unknown): string
	local kind = typeof(value)
	if kind == "string" then
		return ("string %q"):format(value :: string)
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return ("%s %s"):format(kind, tostring(value))
	end
	return kind
end

export type Parsed = {
	code: string,
	summary: string,
	fields: { [string]: string },
}

local function parse(message: string): Parsed?
	local at = string.find(message, "Compose[", 1, true)
	if at == nil then
		return nil
	end
	local body = string.sub(message, at)

	local code, summary = string.match(body, "^Compose%[([^%]]+)%]:%s*([^\n]*)")
	if code == nil then
		return nil
	end

	local fields: { [string]: string } = {}
	for line in string.gmatch(body, "\n([^\n]*)") do
		local name, value = string.match(line, "^%s%s([%w_]+):%s(.*)$")
		if name ~= nil then
			fields[name :: string] = value :: string
		end
	end

	return { code = code :: string, summary = summary :: string, fields = fields }
end

return {
	format = format,
	raise = raise,
	describe = describe,
	parse = parse,
}
