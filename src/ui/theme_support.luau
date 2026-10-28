--!strict
local ComposeTypes = require("../vendor/compose/core")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")

export type Paint = {
	color: (Engine.RobloxTypes, ThemeTypes.RGB | Color3?) -> Color3?,
	white: (Engine.RobloxTypes) -> Color3,
}

local function contrast(first: Color3, second: Color3): number
	local function luminance(value: Color3): number
		local function linear(channel: number): number
			return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * linear(value.R) + 0.7152 * linear(value.G) + 0.0722 * linear(value.B)
	end
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

local function readableTransparency(ink: Color3, background: Color3, requested: number): number
	local maximum = math.clamp(requested, 0, 1)
	if contrast(ink:Lerp(background, maximum), background) >= 4.5 then
		return maximum
	end
	local low, high = 0, maximum
	for _ = 1, 20 do
		local middle = (low + high) / 2
		if contrast(ink:Lerp(background, middle), background) >= 4.5 then
			low = middle
		else
			high = middle
		end
	end
	return low
end

local function copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out: { [unknown]: unknown } = {}
	for key, child in value :: { [unknown]: unknown } do
		out[key] = copy(child)
	end
	return (out :: unknown) :: T
end

local skinStates = { default = true, hover = true, pressed = true, selected = true, disabled = true }
local function stateMap(value: unknown): boolean
	if type(value) ~= "table" or next(value :: { [unknown]: unknown }) == nil then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if not skinStates[key :: string] then
			return false
		end
	end
	return true
end

local function merge<T>(base: T, overrides: unknown): T
	local out = (copy(base) :: unknown) :: { [unknown]: unknown }
	for key, value in (overrides or {}) :: { [unknown]: unknown } do
		if key ~= "base" then
			out[key] = if type(value) == "table"
					and type(out[key]) == "table"
					and #(value :: { unknown }) == 0
					and not stateMap(value)
				then merge(out[key], value)
				else copy(value)
		end
	end
	return (out :: unknown) :: T
end

local function read<T>(source: Engine.Input<T>, use: ComposeTypes.Use?): T
	if type(source) == "function" then
		return (source :: (ComposeTypes.Use) -> T)(use or function<U>(value: ComposeTypes.ReadOnlyValue<U>): U
			return value:peek()
		end)
	end
	if type(source) == "table" and type(source.peek) == "function" then
		local readable = source :: ComposeTypes.ReadOnlyValue<T>
		return if use then use(readable) else readable:peek()
	end
	return source :: T
end

local function frozen<T>(value: T): T
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, child in value :: { [unknown]: unknown } do
		frozen(child)
	end
	return (table.freeze(value) :: unknown) :: T
end

local shadowPresets: { [string]: ThemeTypes.Shadow } = {
	raised = { blurRadius = { offset = 14 }, transparency = 0.35, offset = { y = { offset = 3 } } },
	overlay = { blurRadius = { offset = 24 }, transparency = 0.45, offset = { y = { offset = 8 } } },
}

local function numericMetric(metrics: ThemeTypes.Metrics, path: unknown): number?
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local value: unknown = metrics
	for _, key in string.split(path, ".") do
		if key == "" or type(value) ~= "table" then
			return nil
		end
		value = (value :: { [string]: unknown })[key]
	end
	return if type(value) == "number" and value == value and math.abs(value) < math.huge then value else nil
end

local function paletteFor(package: ThemeTypes.ThemePackage, requested: string?): ThemeTypes.Palette
	local name = requested or package.style.defaultTheme
	for _, palette in package.style.themes do
		if palette.name == name then
			return palette
		end
	end
	return package.style.themes[1]
end

local function typesFor(options: { types: Engine.RobloxTypes? }): Engine.RobloxTypes
	return options.types or getfenv(0)
end

local function font(types: Engine.RobloxTypes, value: ThemeTypes.FontSpec | Font): Font
	if typeof(value) == "Font" then
		return value
	end
	local spec = value :: ThemeTypes.FontSpec
	local family = spec.family or "BuilderSans"
	if not string.find(family, "://", 1, true) then
		family = "rbxasset://fonts/families/" .. family .. ".json"
	end
	return types.Font.new(
		family,
		((types.Enum.FontWeight :: unknown) :: { [string]: Enum.FontWeight })[spec.weight or "Regular"],
		((types.Enum.FontStyle :: unknown) :: { [string]: Enum.FontStyle })[spec.style or "Normal"]
	)
end

local function sameProperties<T>(left: { [string]: T }, right: { [string]: T }): boolean
	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local WEAK_KEYS = table.freeze({ __mode = "k" })

local function weakKeys<K, V>(made: { [K]: V })
	setmetatable(made, WEAK_KEYS)
end

local PALETTES: { [unknown]: unknown } = { style = { themes = true } }

local function deeplySame(left: unknown, right: unknown, ignored: { [unknown]: unknown }?): boolean
	if rawequal(left, right) then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return left == right
	end
	local leftRecord, rightRecord = left :: { [unknown]: unknown }, right :: { [unknown]: unknown }
	for key, value in leftRecord do
		local skip = if ignored then ignored[key] else nil
		local nested = if type(skip) == "table" then skip :: { [unknown]: unknown } else nil
		if skip ~= true and not deeplySame(value, rightRecord[key], nested) then
			return false
		end
	end
	for key in rightRecord do
		if leftRecord[key] == nil then
			return false
		end
	end
	return true
end

local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown
local function deeplyFrozen(value: unknown, visited: { [unknown]: boolean }): boolean
	if type(value) ~= "table" then
		return true
	end
	if metatableOf(value) ~= nil then
		return false
	end
	local record = value :: { [unknown]: unknown }
	if not table.isfrozen(record) then
		return false
	end
	if visited[record] then
		return true
	end
	visited[record] = true
	for key, child in record do
		if not deeplyFrozen(key, visited) or not deeplyFrozen(child, visited) then
			return false
		end
	end
	return true
end

local frozenPackages = setmetatable({} :: { [ThemeTypes.ThemePackage]: boolean }, { __mode = "k" })
local fingerprints: { [ThemeTypes.ThemePackage]: string } = {}
weakKeys(fingerprints)

local function keyOrder(left: unknown, right: unknown): boolean
	local leftType, rightType = type(left), type(right)
	if leftType ~= rightType then
		return leftType < rightType
	end
	return tostring(left) < tostring(right)
end

local function describe(value: unknown, ignored: { [unknown]: unknown }?, parts: { string })
	if type(value) ~= "table" then
		table.insert(parts, typeof(value))
		table.insert(parts, ":")
		table.insert(parts, tostring(value))
		table.insert(parts, ";")
		return
	end
	local record = value :: { [unknown]: unknown }
	local keys: { unknown } = {}
	for key in record do
		if not (ignored and ignored[key] == true) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, keyOrder)
	table.insert(parts, "{")
	for _, key in keys do
		table.insert(parts, tostring(key))
		table.insert(parts, "=")
		local skip = if ignored then ignored[key] else nil
		describe(record[key], if type(skip) == "table" then skip :: { [unknown]: unknown } else nil, parts)
	end
	table.insert(parts, "}")
end

local function sealed(package: ThemeTypes.ThemePackage): boolean
	local known = frozenPackages[package]
	if known == nil then
		known = deeplyFrozen(package, {})
		frozenPackages[package] = known
		if known then
			local parts: { string } = {}
			describe(package, PALETTES, parts)
			fingerprints[package] = table.concat(parts)
		end
	end
	return known
end

local function sameBesidesPalettes(left: ThemeTypes.ThemePackage?, right: ThemeTypes.ThemePackage?): boolean
	if left == right then
		return true
	end
	if left == nil or right == nil then
		return false
	end
	if not sealed(left) or not sealed(right) then
		return deeplySame(left, right, PALETTES)
	end
	return fingerprints[left] == fingerprints[right]
end

local function neutralBase(neutral: ThemeTypes.ThemePackage, colors: { [string]: unknown }?): ThemeTypes.Palette
	local surface = if colors then colors.surface else nil
	local base = neutral.style.themes[1]
	if type(surface) == "table" then
		local rgb = surface :: ThemeTypes.RGB
		local function linear(channel: number): number
			return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
		end
		if 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b) > 0.18 then
			for _, entry in neutral.style.themes do
				if entry.name == "Light" then
					base = entry
				end
			end
		end
	end
	return base
end

local function plateReach(package: ThemeTypes.ThemePackage?): number
	if package == nil then
		return 0
	end
	local reach = 0
	local chrome = package.chrome or {}
	for _, slot in { "panel", "control" } do
		local recipe = chrome[slot]
		local declared: unknown = if recipe then recipe.shadow else nil
		local shadow: ThemeTypes.Shadow? = if type(declared) == "string"
			then (package.style.shadows or {})[declared] or shadowPresets[declared]
			elseif type(declared) == "table" then declared :: ThemeTypes.Shadow
			else nil
		if shadow and shadow.enabled ~= false then
			local function offsetOf(value: ThemeTypes.ShadowAxis?): number
				return if value and value.offset then value.offset else 0
			end
			local offset, spread = shadow.offset, shadow.spread
			local dx = math.abs(offsetOf(offset and offset.x)) + offsetOf(spread and spread.x)
			local dy = math.abs(offsetOf(offset and offset.y)) + offsetOf(spread and spread.y)
			reach = math.max(reach, offsetOf(shadow.blurRadius) + math.max(dx, dy))
		end
	end
	local rules: { ThemeTypes.Rule } = package.rules or {}
	for _, rule in rules do
		local selector = rule.selector
		local properties = rule.properties or rule.props
		if type(selector) == "string" and string.find(selector, "::UIStroke", 1, true) and properties then
			local thickness = properties.Thickness
			if type(thickness) == "number" then
				reach = math.max(reach, thickness)
			end
		end
	end
	return math.ceil(math.max(0, reach))
end

return {
	neutralBase = neutralBase,
	contrast = contrast,
	readableTransparency = readableTransparency,
	copy = copy,
	merge = merge,
	read = read,
	frozen = frozen,
	shadowPresets = shadowPresets,
	plateReach = plateReach,
	numericMetric = numericMetric,
	paletteFor = paletteFor,
	typesFor = typesFor,
	font = font,
	sameProperties = sameProperties,
	deeplyFrozen = deeplyFrozen,
	sameBesidesPalettes = sameBesidesPalettes,
	sealed = sealed,
	weakKeys = weakKeys,
}
