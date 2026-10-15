--!strict
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local support = require("./theme_support")

local merge, paletteFor, font = support.merge, support.paletteFor, support.font

export type NativeRule = {
	id: string,
	selector: string,
	properties: ThemeTypes.RuleProperties,
	priority: number,
	tokens: { [string]: Color3? }?,
}
export type RuleKit = {
	extra: ThemeTypes.PaletteExtra,
	source: (string) -> ThemeTypes.RGB?,
	c: (string) -> string?,
	resolved: (string) -> Color3?,
	f: (ThemeTypes.FontSpec | Font) -> Font,
	rule: (string, ThemeTypes.RuleProperties, boolean?) -> (),
	finish: () -> { NativeRule },
}

return function(
	package: ThemeTypes.ThemePackage,
	selected: string?,
	types: Engine.RobloxTypes,
	neutral: ThemeTypes.ThemePackage,
	paint: support.Paint
): RuleKit
	local color = paint.color
	local palette = paletteFor(package, selected)
	local colors = merge(neutral.style.themes[1].colors, palette.colors)
	local extra = merge(neutral.style.themes[1].extra :: ThemeTypes.PaletteExtra, palette.extra)
	local tokens: { [string]: Color3? }, typefaces: { [string]: Font? } = {}, {}
	local fallbacks: { [string]: string } = {
		selection = "accent",
		onSelection = "onAccent",
		inverseSurface = "contentStrong",
		onInverse = "surface",
		tableHeader = "control",
		tableRow = "control",
		tableRowAlternate = "controlHover",
	}
	local function source(role: string): ThemeTypes.RGB?
		local value = (colors[role] or extra[role]) :: ThemeTypes.RGB?
		local fallback = fallbacks[role]
		if value == nil and fallback then
			value = (colors[fallback] or extra[fallback]) :: ThemeTypes.RGB?
		end
		return value
	end
	local function c(role: string): string?
		local token = "FacetColor_" .. role
		if tokens[token] == nil then
			local value = color(types, source(role))
			if value == nil and role == "voice" then
				value = (color(types, source("warning")) :: Color3):Lerp(color(types, source("danger")) :: Color3, 0.5)
			end
			tokens[token] = value
		end
		return if tokens[token] ~= nil then "$" .. token else nil
	end
	local function f(value: ThemeTypes.FontSpec | Font): Font
		if typeof(value) == "Font" then
			return value
		end
		local spec = value :: ThemeTypes.FontSpec
		local key = (spec.family or "BuilderSans")
			.. ":"
			.. (spec.weight or "Regular")
			.. ":"
			.. (spec.style or "Normal")
		if typefaces[key] == nil then
			typefaces[key] = font(types, value)
		end
		return typefaces[key] :: Font
	end
	local rules: { NativeRule } = {}
	local occurrences: { [string]: number } = {}
	local function add(selector: string, properties: ThemeTypes.RuleProperties)
		local occurrence = (occurrences[selector] or 0) + 1
		occurrences[selector] = occurrence
		table.insert(rules, {
			id = selector .. ":" .. tostring(occurrence),
			selector = selector,
			properties = properties,
			priority = #rules * 10,
			tokens = tokens,
		})
	end
	local function rule(selector: string, properties: ThemeTypes.RuleProperties, authored: boolean?)
		if string.sub(selector, -10) == "::UIStroke" then
			properties = table.clone(properties)
			properties.ApplyStrokeMode = properties.ApplyStrokeMode or types.Enum.ApplyStrokeMode.Border
			if not authored and properties.ApplyStrokeMode == types.Enum.ApplyStrokeMode.Border then
				properties.BorderStrokePosition = properties.BorderStrokePosition
					or types.Enum.BorderStrokePosition.Inner
			end
		end
		if string.sub(selector, -10) == "::UIStroke" then
			add(selector .. ", " .. string.sub(selector, 1, -11) .. " > .facet-fade-stroke", properties)
		elseif string.sub(selector, -11) == "::UIPadding" then
			add(selector .. ", " .. string.sub(selector, 1, -12) .. " > UIPadding", properties)
		else
			add(selector, properties)
		end
	end
	add(".facet-fade-stroke", { Enabled = false, Transparency = 1 })
	local function finish(): { NativeRule }
		add(".facet-fading::UIStroke", {
			Enabled = false,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
			BorderStrokePosition = types.Enum.BorderStrokePosition.Inner,
		})
		add(".facet-fading > .facet-fade-stroke", { Enabled = true })
		for _, definition in (package.rules or {}) :: { ThemeTypes.Rule } do
			local properties: ThemeTypes.RuleProperties = {}
			for key, value in (definition.properties or definition.props or {}) :: ThemeTypes.AuthoredRuleProperties do
				if type(value) == "table" and type((value :: { role: string }).role) == "string" then
					properties[key] = c((value :: { role: string }).role)
				elseif type(value) == "table" and ((value :: unknown) :: { metric: unknown }).metric ~= nil then
					local path = ((value :: unknown) :: { metric: unknown }).metric
					properties[key] = assert(
						support.numericMetric(package.metrics, path),
						`Facet theme rule: invalid numeric metric {tostring(path)}`
					)
				else
					properties[key] = value :: ThemeTypes.StyleValue?
				end
			end
			rule(definition.selector, properties, true)
		end
		local present: { [string]: boolean } = {}
		local presence: { NativeRule } = {}
		for _, definition in rules do
			local selector = string.match(definition.selector, ", (.+)$") or definition.selector
			if
				string.sub(selector, -21) == " > .facet-fade-stroke"
				and selector ~= ".facet-fading > .facet-fade-stroke"
				and not present[selector]
			then
				present[selector] = true
				table.insert(presence, {
					id = selector .. ":presence",
					selector = selector,
					properties = { Transparency = 0 },
					priority = #presence,
				})
			end
		end
		local ordered = { rules[1] }
		table.move(presence, 1, #presence, 2, ordered)
		table.move(rules, 2, #rules, #ordered + 1, ordered)
		local compact: { NativeRule } = {}
		local function state(selector: string): string
			return if string.find(selector, ":Press", 1, true)
				then "press"
				elseif string.find(selector, ":Hover", 1, true) then "hover"
				else "normal"
		end
		for _, definition in ordered do
			local merged = false
			for index = #compact, 1, -1 do
				local previous = compact[index]
				if
					support.sameProperties(previous.properties, definition.properties)
					and state(previous.selector) == state(definition.selector)
				then
					previous.selector ..= ", " .. definition.selector
					merged = true
					break
				end
				local conflict = false
				for property in definition.properties do
					if previous.properties[property] ~= nil then
						conflict = true
						break
					end
				end
				if conflict then
					break
				end
			end
			if not merged then
				table.insert(compact, definition)
			end
		end
		for index, definition in compact do
			definition.priority = (index - 1) * 10
		end
		return compact
	end
	return {
		extra = extra,
		source = source,
		c = c,
		resolved = function(role: string): Color3?
			local token = c(role)
			return if token then tokens[string.sub(token, 2)] else nil
		end,
		f = f,
		rule = rule,
		finish = finish,
	}
end
