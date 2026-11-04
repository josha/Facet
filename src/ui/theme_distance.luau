--!strict
local ThemeTypes = require("./theme_types")
local adaptive = require("./adaptive")
local frozen = require("./theme_support").frozen

type Origin = { base: ThemeTypes.ReadOnlyThemePackage, distant: boolean, scale: number }

local origins: { [ThemeTypes.ReadOnlyThemePackage]: Origin } = setmetatable({}, { __mode = "k" })
local cache: { [ThemeTypes.ReadOnlyThemePackage]: { [string]: ThemeTypes.ReadOnlyThemePackage } } = setmetatable(
	{},
	{ __mode = "k" }
)
local UNSCALED =
	{ "TextSize$", "Lines$", "Count$", "Duration$", "Seconds$", "Ratio$", "Fraction$", "Scale$", "Opacity$", "Weight$" }

local function isLength(name: string): boolean
	for _, pattern in UNSCALED do
		if string.find(name, pattern) then
			return false
		end
	end
	return true
end

local function scaleTable(values: { [string]: number }, factor: number, rounded: boolean?): { [string]: number }
	local result: { [string]: number } = {}
	for key, value in values do
		result[key] = if rounded then math.floor(value * factor + 0.5) else value * factor
	end
	return result
end

local function insets(source: ThemeTypes.Insets?, factor: number): ThemeTypes.Insets?
	if source == nil then
		return nil
	end
	return {
		top = if source.top then source.top * factor else nil,
		right = if source.right then source.right * factor else nil,
		bottom = if source.bottom then source.bottom * factor else nil,
		left = if source.left then source.left * factor else nil,
	}
end

local function axis(source: ThemeTypes.ShadowAxis?, factor: number): ThemeTypes.ShadowAxis?
	return if source
		then { scale = source.scale, offset = if source.offset then source.offset * factor else nil }
		else nil
end

local function pair(source: ThemeTypes.ShadowPair?, factor: number): ThemeTypes.ShadowPair?
	return if source then { x = axis(source.x, factor), y = axis(source.y, factor) } else nil
end

local function layer(source: ThemeTypes.SkinLayer, factor: number): ThemeTypes.SkinLayer
	local result = table.clone(source)
	result.contentInsets = insets(source.contentInsets, factor)
	result.textInsets = insets(source.textInsets, factor)
	result.thickness = if source.thickness then source.thickness * factor else nil
	result.margin = if source.margin then source.margin * factor else nil
	result.tile = if source.tile then source.tile * factor else nil
	result.overhang = if source.overhang then source.overhang * factor else nil
	result.outset = if source.outset then source.outset * factor else nil
	result.sliceScale = if source.sliceScale then source.sliceScale * factor else nil
	result.blurRadius = axis(source.blurRadius, factor)
	if source.tileSize then
		result.tileSize = { w = source.tileSize.w * factor, h = source.tileSize.h * factor }
	end
	local size = source.size
	if type(size) == "number" then
		result.size = size * factor
	elseif size then
		result.size = { w = size.w * factor, h = size.h * factor }
	end
	local shadow = source.shadow
	if type(shadow) == "table" then
		local scaled = table.clone(shadow)
		scaled.blurRadius = axis(shadow.blurRadius, factor)
		scaled.offset = pair(shadow.offset, factor)
		scaled.spread = pair(shadow.spread, factor)
		result.shadow = scaled
	end
	if source.layers then
		local layers: { ThemeTypes.SkinLayer } = {}
		for _, child in source.layers do
			table.insert(layers, layer(child, factor))
		end
		result.layers = layers
	end
	return result
end

local function build(
	package: ThemeTypes.ReadOnlyThemePackage,
	neutral: ThemeTypes.ReadOnlyThemePackage,
	distant: boolean,
	resolution: number
): ThemeTypes.ReadOnlyThemePackage
	local distance = if distant then adaptive.TEN_FOOT_SCALE else 1
	local factor = distance * resolution
	local metrics = package.metrics
	local scaled = table.clone(metrics)
	scaled.space = scaleTable(metrics.space, factor)
	scaled.strokes = scaleTable(metrics.strokes, factor)
	scaled.targetSizes = scaleTable(metrics.targetSizes, factor)
	scaled.iconSizes = scaleTable(metrics.iconSizes, factor)
	scaled.radii = scaleTable(metrics.radii, factor, true)
	local controlSizes: { [string]: ThemeTypes.ControlSize } = {}
	for step, entry in metrics.controlSizes do
		controlSizes[step] = {
			height = math.floor(entry.height * factor + 0.5),
			paddingX = math.floor(entry.paddingX * factor + 0.5),
			iconSize = math.floor(entry.iconSize * factor + 0.5),
		}
	end
	scaled.controlSizes = controlSizes
	local controls: { [string]: { [string]: number } } = {}
	for family, values in metrics.controls do
		local entry: { [string]: number } = {}
		for name, value in values do
			entry[name] = if isLength(name)
				then math.floor(value * factor + 0.5)
				elseif string.find(name, "TextSize$") then math.floor(value * resolution + 0.5)
				else value
		end
		controls[family] = entry
	end
	scaled.controls = controls
	local typography = table.clone(neutral.metrics.typography)
	for role, entry in metrics.typography do
		typography[role] = entry
	end
	local sizes: { number } = {}
	for _, entry in typography do
		if not table.find(sizes, entry.size) then
			table.insert(sizes, entry.size)
		end
	end
	table.sort(sizes)
	local ramp: { [number]: number } = {}
	local previous = 0
	for index, size in sizes do
		if distant then
			local floor = if index == 1 then 24 else 28
			previous = math.max(math.floor(size * distance + 0.5), floor, previous + 1)
		else
			previous = math.max(14, size)
		end
		ramp[size] = math.floor(previous * resolution + 0.5)
	end
	for role, entry in typography do
		local copy = table.clone(entry)
		copy.size = ramp[entry.size]
		typography[role] = copy
	end
	scaled.typography = typography
	local chrome = package.chrome
	local assets = package.assets
	if resolution ~= 1 then
		if chrome then
			local layers: { [string]: ThemeTypes.SkinLayer } = {}
			for name, entry in chrome do
				layers[name] = layer(entry, resolution)
			end
			chrome = layers
		end
		if assets then
			local entries: { [string]: ThemeTypes.Asset } = {}
			for name, entry in assets do
				local copy = table.clone(entry)
				copy.sliceScale = (entry.sliceScale or 1) * resolution
				entries[name] = copy
			end
			assets = entries
		end
	end
	local result: ThemeTypes.ThemePackage = {
		schema = package.schema,
		identity = package.identity,
		style = package.style,
		metrics = scaled,
		chrome = chrome,
		assets = assets,
		icons = package.icons,
		rules = package.rules,
	}
	return if table.isfrozen(package) then frozen(result) else result
end

local function create(neutral: ThemeTypes.ReadOnlyThemePackage)
	local function derive(
		package: ThemeTypes.ReadOnlyThemePackage,
		distant: boolean,
		scale: number
	): ThemeTypes.ReadOnlyThemePackage
		local origin = origins[package]
		local base = if origin then origin.base else package
		if not distant and scale == 1 then
			return base
		end
		local key = (if distant then "far:" else "near:") .. tostring(scale)
		local variants = cache[base]
		if variants == nil then
			variants = setmetatable({}, { __mode = "v" })
			cache[base] = variants
		end
		local known = if table.isfrozen(base) then variants[key] else nil
		if known then
			return known
		end
		local result = build(base, neutral, distant, scale)
		origins[result] = { base = base, distant = distant, scale = scale }
		if table.isfrozen(base) then
			variants[key] = result
		end
		return result
	end
	return {
		forDistance = function(
			package: ThemeTypes.ReadOnlyThemePackage,
			distance: string?
		): ThemeTypes.ReadOnlyThemePackage
			assert(
				distance == "near" or distance == "ten-foot",
				"Facet themes.forDistance: distance must be near or ten-foot"
			)
			local origin = origins[package]
			return derive(package, distance == "ten-foot", if origin then origin.scale else 1)
		end,
		forResolution = function(
			package: ThemeTypes.ReadOnlyThemePackage,
			width: number,
			height: number
		): ThemeTypes.ReadOnlyThemePackage
			local origin = origins[package]
			return derive(package, origin ~= nil and origin.distant, adaptive.resolutionScale(width, height))
		end,
	}
end

local function resolutionScale(package: ThemeTypes.ReadOnlyThemePackage?): number
	local origin = if package then origins[package] else nil
	return if origin then origin.scale else 1
end

return { create = create, resolutionScale = resolutionScale }
