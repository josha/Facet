--!strict

local Diagnostics = require "./diagnostics"
local Types = require "./reactive/types"

export type Size = Types.GeometrySize
export type Insets = Types.GeometryInsets
export type Anchor = Types.GeometryAnchor
export type Frame = Types.GeometryFrame
export type Bounds = Types.GeometryBounds
export type FitOptions = Types.GeometryFitOptions
export type ClearOptions<R> = Types.GeometryClearOptions<R>

local CENTER: Anchor = { x = 0.5, y = 0.5 }

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function number(value: unknown, name: string, minimum: number?): number
	if
		type(value) ~= "number"
		or value ~= value
		or value <= -math.huge
		or value >= math.huge
		or (minimum ~= nil and value < minimum)
	then
		return Diagnostics.raise("geometry/invalid-number", ("%s must be a finite number"):format(name), {
			actual = Diagnostics.describe(value),
			expected = if minimum ~= nil
				then ("a finite number of %s or more"):format(tostring(minimum))
				else "a finite number",
		})
	end
	return value
end

local function bounds(value: unknown, name: string): Bounds
	if type(value) ~= "table" then
		return Diagnostics.raise("geometry/invalid-rect", ("%s must be a rect"):format(name), {
			actual = Diagnostics.describe(value),
			expected = "{ left, top, right, bottom } with finite numbers",
		})
	end
	assert(type(value) == "table")
	local fields: { [string]: unknown } = {}
	for key, field in value do
		if type(key) == "string" then
			fields[key] = field
		end
	end
	local rect: Bounds = {
		left = number(fields.left, name .. ".left"),
		top = number(fields.top, name .. ".top"),
		right = number(fields.right, name .. ".right"),
		bottom = number(fields.bottom, name .. ".bottom"),
	}
	if rect.right < rect.left or rect.bottom < rect.top then
		return Diagnostics.raise("geometry/invalid-rect", ("%s has a negative extent"):format(name), {
			actual = ("left %s, right %s, top %s, bottom %s"):format(
				tostring(rect.left),
				tostring(rect.right),
				tostring(rect.top),
				tostring(rect.bottom)
			),
			expected = "right at or after left, and bottom at or after top",
			fix = "clamp a computed width or height at zero before building the rect",
		})
	end
	return rect
end

local function size(value: Size, name: string): Size
	if type(value) ~= "table" then
		return Diagnostics.raise("geometry/invalid-size", ("%s must be a size"):format(name), {
			actual = Diagnostics.describe(value),
			expected = "{ width, height } with finite numbers of zero or more",
		})
	end
	number(value.width, name .. ".width", 0)
	number(value.height, name .. ".height", 0)
	return value
end

local function build(left: number, top: number, width: number, height: number): Frame
	return { left = left, top = top, right = left + width, bottom = top + height, width = width, height = height }
end

local function safeArea(viewport: Size, insets: Insets?, margin: number?): Frame
	size(viewport, "viewport")
	local edge = if margin ~= nil then number(margin, "margin", 0) else 0
	local left, top, right, bottom = 0, 0, 0, 0
	if insets ~= nil then
		if type(insets) ~= "table" then
			return Diagnostics.raise("geometry/invalid-insets", "insets must be a table", {
				actual = Diagnostics.describe(insets),
				expected = "{ left?, top?, right?, bottom? } with numbers of zero or more",
			})
		end
		left = if insets.left ~= nil then number(insets.left, "insets.left", 0) else 0
		top = if insets.top ~= nil then number(insets.top, "insets.top", 0) else 0
		right = if insets.right ~= nil then number(insets.right, "insets.right", 0) else 0
		bottom = if insets.bottom ~= nil then number(insets.bottom, "insets.bottom", 0) else 0
	end
	return build(
		left + edge,
		top + edge,
		math.max(0, viewport.width - left - right - edge * 2),
		math.max(0, viewport.height - top - bottom - edge * 2)
	)
end

local function fit(available: Bounds, desired: Size, options: FitOptions?): Frame
	bounds(available, "available")
	size(desired, "desired")
	local settings: FitOptions = if options ~= nil then options else {}
	local minimum = if settings.min ~= nil then size(settings.min, "min") else nil
	local maximum = if settings.max ~= nil then size(settings.max, "max") else nil
	if minimum ~= nil and maximum ~= nil and (minimum.width > maximum.width or minimum.height > maximum.height) then
		return Diagnostics.raise("geometry/invalid-limits", "the minimum size exceeds the maximum size", {
			actual = ("min %sx%s, max %sx%s"):format(
				tostring(minimum.width),
				tostring(minimum.height),
				tostring(maximum.width),
				tostring(maximum.height)
			),
			expected = "a minimum no larger than the maximum on both axes",
		})
	end
	local anchor = CENTER
	if settings.anchor ~= nil then
		anchor = settings.anchor
		if
			type(anchor) ~= "table"
			or not finite(anchor.x)
			or not finite(anchor.y)
			or anchor.x < 0
			or anchor.x > 1
			or anchor.y < 0
			or anchor.y > 1
		then
			return Diagnostics.raise("geometry/invalid-anchor", "an anchor needs x and y fractions between 0 and 1", {
				actual = Diagnostics.describe(settings.anchor),
				expected = "{ x = 0.5, y = 0.5 } centers; { x = 0, y = 0 } is the top left",
			})
		end
	end
	local room = { width = available.right - available.left, height = available.bottom - available.top }
	local width = desired.width
	local height = desired.height
	if maximum ~= nil then
		width = math.min(width, maximum.width)
		height = math.min(height, maximum.height)
	end
	if minimum ~= nil then
		width = math.max(width, minimum.width)
		height = math.max(height, minimum.height)
	end
	width = math.min(width, room.width)
	height = math.min(height, room.height)
	return build(
		available.left + (room.width - width) * anchor.x,
		available.top + (room.height - height) * anchor.y,
		width,
		height
	)
end

local function intersects(a: Bounds, b: Bounds): boolean
	return a.left < b.right and a.right > b.left and a.top < b.bottom and a.bottom > b.top
end

local function encloses(outer: Bounds, inner: Bounds): boolean
	return inner.left >= outer.left
		and inner.right <= outer.right
		and inner.top >= outer.top
		and inner.bottom <= outer.bottom
end

local function overlaps(a: Bounds, b: Bounds): boolean
	return intersects(bounds(a, "a"), bounds(b, "b"))
end

local function contains(outer: Bounds, inner: Bounds): boolean
	return encloses(bounds(outer, "outer"), bounds(inner, "inner"))
end

local function firstClear<T, R>(candidates: { T }, options: ClearOptions<R>?): (T?, number?)
	if type(candidates) ~= "table" then
		return Diagnostics.raise("geometry/invalid-candidates", "candidates must be a list of rects", {
			actual = Diagnostics.describe(candidates),
			expected = "an array of { left, top, right, bottom } in preference order",
		})
	end
	local settings: ClearOptions<R> = if options ~= nil then options else {}
	local within = if settings.within ~= nil then bounds(settings.within, "within") else nil
	local reserved: { R } = if settings.reserved ~= nil then settings.reserved else {}
	local regions: { Bounds } = {}
	for index, region in reserved do
		regions[index] = bounds(region, ("reserved[%d]"):format(index))
	end
	for index, candidate in candidates do
		local rect = bounds(candidate, ("candidates[%d]"):format(index))
		local clear = within == nil or encloses(within, rect)
		if clear then
			for _, region in regions do
				if intersects(rect, region) then
					clear = false
					break
				end
			end
		end
		if clear then
			return candidate, index
		end
	end
	return nil, nil
end

return table.freeze {
	safeArea = safeArea,
	fit = fit,
	overlaps = overlaps,
	contains = contains,
	firstClear = firstClear,
}
