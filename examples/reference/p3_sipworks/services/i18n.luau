--!strict

local strings = require("../content/strings")

local i18n = {}

i18n.LOCALES = strings.LOCALES

function i18n.localeOf(fact: any): string
	if type(fact) ~= "string" then
		return "en"
	end
	local lowered = string.lower(fact)
	if string.find(lowered, "^xa") ~= nil or string.find(lowered, "^qps") ~= nil then
		return "xa"
	end
	return "en"
end

local function substitute(template: string, params: any): string
	if params == nil then
		return template
	end
	return (
		string.gsub(template, "{([%w_]+)}", function(name: string): string
			local value = params[name]
			if value == nil then
				return "{" .. name .. "}"
			end
			return tostring(value)
		end)
	)
end

local function pluralForm(entry: any, n: number?): string
	if n == 0 and entry.zero ~= nil then
		return entry.zero
	end
	if n == 1 and entry.one ~= nil then
		return entry.one
	end
	return entry.other or entry.one or entry.zero
end

function i18n.new(opts: any)
	local Compose = opts.Compose

	local locale = Compose.cell(opts.locale or "en")

	local nameCache: { [string]: string } = {}

	local self = {}
	self.locale = locale

	function self.setLocale(id: string): boolean
		local table_ = strings.byLocale[id]
		if table_ == nil then
			return false
		end
		locale:set(id)
		return true
	end

	function self.at(localeId: string, key: string, params: any?): string
		local tableForLocale = strings.byLocale[localeId] or strings.byLocale.en
		local entry = tableForLocale[key]
		if entry == nil then
			return "?" .. key
		end
		if type(entry) == "table" then
			local n = if params ~= nil then params.n else nil
			return substitute(pluralForm(entry, n), params)
		end
		return substitute(entry, params)
	end

	function self.t(key: string, params: any?): string
		return self.at(locale:peek(), key, params)
	end

	function self.has(key: string): boolean
		return strings.byLocale.en[key] ~= nil
	end

	function self.nameAt(localeId: string, kind: string, id: string, text: string): string
		if localeId == "en" then
			return text
		end
		local cacheKey = localeId .. "/" .. kind .. "/" .. id
		local hit = nameCache[cacheKey]
		if hit == nil then
			hit = strings.expand(text)
			nameCache[cacheKey] = hit
		end
		return hit
	end

	function self.name(kind: string, id: string, text: string): string
		return self.nameAt(locale:peek(), kind, id, text)
	end

	function self.numberAt(localeId: string, value: number): string
		local text: string
		if math.abs(value - math.floor(value + 0.5)) < 1e-6 then
			text = tostring(math.floor(value + 0.5))
		else
			text = string.format("%.2f", value)
			text = string.gsub(text, "0+$", "")
			text = string.gsub(text, "%.$", "")
		end
		if localeId ~= "en" then
			text = string.gsub(text, "%.", ",")
		end
		return text
	end

	function self.measureAt(localeId: string, value: number, unit: string): string
		return self.at(localeId, "measure.value", { value = self.numberAt(localeId, value), unit = unit })
	end

	function self.measure(value: number, unit: string): string
		return self.measureAt(locale:peek(), value, unit)
	end

	function self.listAt(localeId: string, items: { string }): string
		local n = #items
		if n == 0 then
			return ""
		end
		if n == 1 then
			return items[1]
		end
		if n == 2 then
			return self.at(localeId, "list.pair", { a = items[1], b = items[2] })
		end
		local head = items[1]
		for i = 2, n - 1 do
			head = self.at(localeId, "list.two", { a = head, b = items[i] })
		end
		return self.at(localeId, "list.last", { head = head, tail = items[n] })
	end

	function self.list(items: { string }): string
		return self.listAt(locale:peek(), items)
	end

	function self.sortKey(localeId: string, text: string): string
		return string.lower(text)
	end

	function self.reset()
		locale:set(opts.locale or "en")
	end

	return self
end

return i18n
