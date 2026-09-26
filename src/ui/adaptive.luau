--!strict
local freeze = require("./freeze")
export type SizeClass = "compact" | "regular" | "wide"
export type HeightClass = "short" | "medium" | "tall"
export type Orientation = "landscape" | "portrait" | "square"
export type Breakpoints = { regular: number, wide: number }
export type AxisOptions = { stackAbove: number? }
export type NavPlacement = "topBar" | "sidebar" | "bottomBar" | "bottomBarCompact"
export type NavFacts = {
	sizeClass: string,
	heightClass: string,
	primary: string?,
	displaySize: string?,
	tenFoot: boolean?,
}
export type ViewingDistance = "automatic" | "near" | "ten-foot"
export type TenFootFacts = {
	displaySize: string?,
	touch: boolean?,
	mouse: boolean?,
	tenFootInterface: boolean?,
	viewingDistance: string?,
}
export type Insets = { top: number, left: number, bottom: number, right: number }
export type Adaptive = {
	BREAKPOINTS: Breakpoints,
	HEIGHT_BREAKPOINTS: Breakpoints,
	DEFAULT_STACK_ABOVE: number,
	sizeClass: (width: number?) -> SizeClass,
	heightClass: (height: number?) -> HeightClass,
	orientationFor: (width: number, height: number) -> Orientation,
	axisFor: (width: number?, options: AxisOptions?) -> "x" | "y",
	columnsFor: (available: number, minColumnWidth: number, gap: number?) -> number,
	sizeClassAtLeast: (value: string, target: string) -> boolean,
	navPlacement: (facts: NavFacts) -> NavPlacement,
	isTenFoot: (facts: TenFootFacts) -> boolean,
	TEN_FOOT_SCALE: number,
	overscanInsets: (width: number, height: number) -> Insets,
}

local BREAKPOINTS: Breakpoints = freeze({ regular = 600, wide = 1000 })
local RANK: { [string]: number } = { compact = 1, regular = 2, wide = 3 }

local function real(value: number?): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return value
end

local function sizeClass(width: number?): SizeClass
	local measured = real(width)
	if measured == nil or measured < BREAKPOINTS.regular then
		return "compact"
	end
	return if measured < BREAKPOINTS.wide then "regular" else "wide"
end

local function heightClass(height: number?): HeightClass
	local measured = real(height)
	if measured == nil or measured < BREAKPOINTS.regular then
		return "short"
	end
	return if measured < BREAKPOINTS.wide then "medium" else "tall"
end

local function orientationFor(width: number, height: number): Orientation
	if width > height then
		return "landscape"
	end
	return if height > width then "portrait" else "square"
end

local function axisFor(width: number?, options: AxisOptions?): "x" | "y"
	local above = if options and options.stackAbove then options.stackAbove else BREAKPOINTS.regular
	local measured = real(width)
	return if measured ~= nil and measured >= above then "x" else "y"
end

local function columnsFor(available: number, minColumnWidth: number, gap: number?): number
	assert(
		type(minColumnWidth) == "number" and minColumnWidth > 0,
		"Facet adaptive.columnsFor: minColumnWidth must be a positive number"
	)
	local spacing = math.max(0, gap or 0)
	local room = real(available)
	if room == nil or room <= minColumnWidth then
		return 1
	end
	return math.max(1, math.floor((room + spacing) / (minColumnWidth + spacing)))
end

local function sizeClassAtLeast(value: string, target: string): boolean
	local have, need = RANK[value], RANK[target]
	assert(have ~= nil and need ~= nil, "Facet adaptive.sizeClassAtLeast: expected compact, regular or wide")
	return have >= need
end

local function navPlacement(facts: NavFacts): NavPlacement
	if facts.tenFoot then
		return "topBar"
	end
	if facts.sizeClass == "compact" then
		return "bottomBar"
	end
	if facts.heightClass == "short" then
		return "bottomBarCompact"
	end
	if facts.primary == "pointer" then
		return "sidebar"
	end
	if facts.primary == "gamepad" and facts.displaySize == "Small" then
		return "bottomBar"
	end
	return "topBar"
end

local function isTenFoot(facts: TenFootFacts): boolean
	if facts.viewingDistance == "ten-foot" or facts.viewingDistance == "near" then
		return facts.viewingDistance == "ten-foot"
	end
	return facts.tenFootInterface == true
		or (facts.displaySize == "Large" and facts.touch ~= true and facts.mouse ~= true)
end

local function overscanInsets(width: number, height: number): Insets
	local x = math.floor((real(width) or 0) * 90 / 1920 + 0.5)
	local y = math.floor((real(height) or 0) * 60 / 1080 + 0.5)
	return freeze({ top = y, left = x, bottom = y, right = x })
end

local adaptive: Adaptive = freeze({
	BREAKPOINTS = BREAKPOINTS,
	HEIGHT_BREAKPOINTS = BREAKPOINTS,
	DEFAULT_STACK_ABOVE = BREAKPOINTS.regular,
	sizeClass = sizeClass,
	heightClass = heightClass,
	orientationFor = orientationFor,
	axisFor = axisFor,
	columnsFor = columnsFor,
	sizeClassAtLeast = sizeClassAtLeast,
	navPlacement = navPlacement,
	isTenFoot = isTenFoot,
	TEN_FOOT_SCALE = 1.5,
	overscanInsets = overscanInsets,
})
return adaptive
