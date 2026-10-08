--!strict
local ThemeTypes = require("./theme_types")
local adaptive = require("./adaptive")

local UNSCALED =
	{ "TextSize$", "Lines$", "Count$", "Duration$", "Seconds$", "Ratio$", "Fraction$", "Scale$", "Opacity$", "Weight$" }
local LENGTHS: { "space" | "strokes" | "targetSizes" | "iconSizes" } =
	{ "space", "strokes", "targetSizes", "iconSizes" }

local scaledFrom = setmetatable({} :: { [ThemeTypes.ThemePackage]: ThemeTypes.ThemePackage }, { __mode = "k" })
local cache = setmetatable({} :: { [ThemeTypes.ThemePackage]: ThemeTypes.ThemePackage }, { __mode = "k" })

local function isLength(name: string): boolean
	for _, pattern in UNSCALED do
		if string.find(name, pattern) then
			return false
		end
	end
	return true
end

local function scaleTable(values: { [string]: number }?, factor: number, round: boolean?): { [string]: number }
	local result: { [string]: number } = {}
	local source: { [string]: number } = values or {}
	for key, value in source do
		if type(value) == "number" then
			result[key] = if round then math.floor(value * factor + 0.5) else value * factor
		else
			result[key] = value
		end
	end
	return result
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in (value :: unknown) :: { [unknown]: unknown } do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

local function tenFoot(
	package: ThemeTypes.ThemePackage,
	neutral: ThemeTypes.ThemePackage,
	sealed: boolean
): ThemeTypes.ThemePackage
	local factor = adaptive.TEN_FOOT_SCALE
	local metrics = package.metrics
	local scaled = table.clone(metrics)
	for _, group in LENGTHS do
		scaled[group] = scaleTable(metrics[group], factor)
	end
	scaled.radii = scaleTable(metrics.radii, factor, true)
	local sizes: { [string]: ThemeTypes.ControlSize } = {}
	for step, entry in metrics.controlSizes do
		sizes[step] = (scaleTable(entry :: { [string]: number }, factor, true) :: unknown) :: ThemeTypes.ControlSize
	end
	scaled.controlSizes = sizes
	local controls: { [string]: { [string]: number } } = {}
	for family, values in metrics.controls do
		local entry: { [string]: number } = {}
		for name, value in values do
			entry[name] = if type(value) == "number" and isLength(name) then math.floor(value * factor + 0.5) else value
		end
		controls[family] = entry
	end
	scaled.controls = controls
	local typography: { [string]: ThemeTypes.Typography } = {}
	for role, entry in neutral.metrics.typography do
		typography[role] = entry
	end
	for role, entry in metrics.typography do
		typography[role] = entry
	end
	for role, entry in typography do
		local copy = table.clone(entry)
		copy.size = math.floor(entry.size * factor + 0.5)
		typography[role] = copy
	end
	scaled.typography = typography
	local result = table.clone(package)
	result.metrics = scaled
	return if sealed then deepFreeze(result) else result
end

return function(neutral: ThemeTypes.ThemePackage)
	return function(package: ThemeTypes.ThemePackage, distance: string?): ThemeTypes.ThemePackage
		assert(
			distance == "near" or distance == "ten-foot",
			"Facet themes.forDistance: distance must be near or ten-foot"
		)
		local base = scaledFrom[package] or package
		if distance == "near" then
			return base
		end
		if not table.isfrozen(base) then
			return tenFoot(base, neutral, false)
		end
		local found = cache[base]
		if found == nil then
			found = tenFoot(base, neutral, true)
			cache[base] = found
			scaledFrom[found :: ThemeTypes.ThemePackage] = base
		end
		return found :: ThemeTypes.ThemePackage
	end
end
