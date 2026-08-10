--!strict
-- I18nService (spec §3, §13) — the proof's own localization layer.
--
-- Roblox exposes no `ListFormatter` and no `MeasurementFormatter`, and
-- `Translator:FormatByKey` is the production mapping (responsibility ledger), so
-- the fake owns four jobs and every one of them is a CALL rather than a
-- concatenation at a call site:
--
--   t(key, params)      one template, placeholders substituted
--   plural fixtures     zero / one / other picked by the service, never by a
--                       caller's `if n == 1`
--   list(items)         "Assam, ginger, and clove"
--   measure(value,unit) "1.5 tsp" — and "1,5 tsp" in a locale with a comma
--
-- Plus `name`, which routes CONTENT (blend and botanical proper nouns) through
-- the same expansion the copy takes, so the pseudo-locale actually stresses the
-- list rows and tiles instead of only the chrome.

local strings = require("../content/strings")

local i18n = {}

i18n.LOCALES = strings.LOCALES

-- localeOf: the environment fact is a platform string ("en-us"), and the proof
-- speaks two locales. Anything that is not the pseudo-locale is `en`, which is
-- the honest fallback rather than an error on a device the proof never saw.
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

-- the plural rule. Two locales, one rule: `zero` only when the fixture declares
-- it, `one` at exactly one, `other` everywhere else. A fixture without a `zero`
-- form falls to `other` at zero, which is what "1 of 10 stamps" needs.
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
	local core = opts.core
	local scope = opts.scope

	local locale = core:signal(opts.locale or "en")
	scope:own(function()
		locale:dispose()
	end)

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

	-- at(locale, key, params) — the pure lookup every reactive label is built on
	function self.at(localeId: string, key: string, params: any?): string
		local tableForLocale = strings.byLocale[localeId] or strings.byLocale.en
		local entry = tableForLocale[key]
		if entry == nil then
			-- a missing key is VISIBLE, never blank: a blank label is a defect
			-- that survives review, and a key on screen names its own fix
			return "?" .. key
		end
		if type(entry) == "table" then
			local n = if params ~= nil then params.n else nil
			return substitute(pluralForm(entry, n), params)
		end
		return substitute(entry, params)
	end

	function self.t(key: string, params: any?): string
		return self.at(locale:get(), key, params)
	end

	function self.has(key: string): boolean
		return strings.byLocale.en[key] ~= nil
	end

	-- NAMES. Content proper nouns take the same expansion the copy does, so a
	-- pseudo-localized menu row is as long as a translated one.
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
		return self.nameAt(locale:get(), kind, id, text)
	end

	-- NUMBERS. The decimal separator is a locale fact, which is exactly the kind
	-- of thing a call site must never assume.
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
		return self.measureAt(locale:get(), value, unit)
	end

	-- LISTS. "A", "A and B", "A, B, and C" — one place, so no screen ever
	-- assembles a sentence out of commas.
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
		return self.listAt(locale:get(), items)
	end

	-- COLLATION. The sort key is taken from the SOURCE title on purpose: the
	-- pseudo-locale brackets every string, so collating the displayed form would
	-- sort the whole menu by one bracket and prove nothing. A real translation
	-- layer would carry its own collation table; this is the fake's, and it is
	-- the one place the order is decided.
	function self.sortKey(localeId: string, text: string): string
		return string.lower(text)
	end

	function self.reset()
		locale:set(opts.locale or "en")
	end

	return self
end

return i18n
