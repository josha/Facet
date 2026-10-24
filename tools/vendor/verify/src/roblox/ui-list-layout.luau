--!strict

local Environment = require "./environment"
local Values = require "./ui-values"

type Instance = Environment.Instance
type Vector = { X: number, Y: number }
type Dimension = { Scale: number, Offset: number }
export type Rectangle = { x: number, y: number, width: number, height: number, scale: number }
export type Item = { object: Instance, rectangle: Rectangle, index: number }
export type Result = { items: { Item }, width: number, height: number }
type Flex = { basis: number, value: number, grow: number, shrink: number, minimum: number, maximum: number }

local function alignment(value: string, available: number, used: number): number
	return if value == "Center"
		then (available - used) / 2
		elseif value == "Right" or value == "Bottom" or value == "End" then available - used
		else 0
end

local function distribute(items: { Flex }, available: number): boolean
	local total = 0
	for _, item in items do
		total += item.value
	end
	local growing = available > total
	local active: { Flex } = {}
	for _, item in items do
		table.insert(active, item)
	end
	local changed = false
	while #active > 0 do
		local remaining, weight = available, 0
		for _, item in items do
			remaining -= item.value
		end
		for _, item in active do
			weight += if growing then item.grow else item.shrink * item.basis
		end
		if weight == 0 or math.abs(remaining) < 0.000001 then
			break
		end
		local clamped = false
		for index = #active, 1, -1 do
			local item = active[index]
			local ratio = if growing then item.grow else item.shrink * item.basis
			local value = item.value + remaining * ratio / weight
			local bounded = math.clamp(value, item.minimum, item.maximum)
			if bounded ~= value then
				changed = changed or bounded ~= item.value
				item.value = bounded
				table.remove(active, index)
				clamped = true
			end
		end
		if not clamped then
			for _, item in active do
				local ratio = if growing then item.grow else item.shrink * item.basis
				local value = item.value + remaining * ratio / weight
				changed = changed or value ~= item.value
				item.value = value
			end
			break
		end
	end
	return changed
end

local function measure(
	list: Instance,
	content: Rectangle,
	read: (Instance, string) -> unknown,
	size: (Instance, Rectangle) -> Rectangle,
	reflow: ((Instance, Rectangle, number) -> Rectangle)?
): Result
	local function enum(object: Instance, property: string, fallback: string): string
		local value = read(object, property)
		return if value == nil then fallback else tostring(value):match "([^%.]+)$" or fallback
	end
	local function number(object: Instance, property: string): number
		local value = read(object, property)
		return if type(value) == "number" then value else 0
	end
	local function bounds(object: Instance, horizontal: boolean): (number, number)
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint == nil then
			return 0, math.huge
		end
		local minimum, maximum = Values.vector(read(constraint, "MinSize")), Values.vector(read(constraint, "MaxSize"))
		return (if horizontal then minimum.X else minimum.Y) * content.scale,
			(if horizontal then maximum.X else maximum.Y) * content.scale
	end
	local horizontal = enum(list, "FillDirection", "Vertical") == "Horizontal"
	local crossFlex = enum(list, if horizontal then "VerticalFlex" else "HorizontalFlex", "None")
	local items: { Item } = {}
	for index, child in assert(list.Parent):GetChildren() do
		if child:IsA "GuiObject" and read(child, "Visible") ~= false then
			local item = child:FindFirstChildWhichIsA "UIFlexItem"
			local itemAlignment = if item then enum(item, "ItemLineAlignment", "Automatic") else "Automatic"
			if itemAlignment == "Automatic" then
				itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
			end
			local rectangle: Rectangle
			if
				not horizontal
				and crossFlex == "Fill"
				and reflow
				and (itemAlignment == "Automatic" or itemAlignment == "Stretch")
			then
				local minimum, maximum = bounds(child, true)
				rectangle = reflow(child, content, math.clamp(content.width, minimum, maximum))
			else
				rectangle = size(child, content)
			end
			table.insert(items, { object = child, rectangle = rectangle, index = index })
		end
	end
	local order = enum(list, "SortOrder", "Name")
	table.sort(items, function(left, right): boolean
		if order == "LayoutOrder" then
			local a, b = number(left.object, "LayoutOrder"), number(right.object, "LayoutOrder")
			return if a == b then left.index < right.index else a < b
		end
		local a, b = tostring(left.object.Name), tostring(right.object.Name)
		return if a == b then left.index < right.index else a < b
	end)
	local mainFlex = enum(list, if horizontal then "HorizontalFlex" else "VerticalFlex", "None")
	local mainAlignment = enum(
		list,
		if horizontal then "HorizontalAlignment" else "VerticalAlignment",
		if horizontal then "Left" else "Top"
	)
	local crossAlignment = enum(
		list,
		if horizontal then "VerticalAlignment" else "HorizontalAlignment",
		if horizontal then "Top" else "Left"
	)
	local available = if horizontal then content.width else content.height
	local availableCross = if horizontal then content.height else content.width
	local padding = Values.dimension(read(list, "Padding"))
	local gap = padding.Scale * available + padding.Offset * content.scale
	local gaps = math.max(0, #items - 1) * gap
	local flex: { Flex } = {}
	local cross = 0
	local enabled = mainFlex ~= "None"
		or crossFlex ~= "None"
		or enum(list, "ItemLineAlignment", "Automatic") ~= "Automatic"
	for _, item in items do
		local basis = if horizontal then item.rectangle.width else item.rectangle.height
		cross = math.max(cross, if horizontal then item.rectangle.height else item.rectangle.width)
		local child = item.object:FindFirstChildWhichIsA "UIFlexItem"
		enabled = enabled or child ~= nil
		local mode = if child then enum(child, "FlexMode", "None") elseif mainFlex == "Fill" then "Fill" else "None"
		local minimum, maximum = bounds(item.object, horizontal)
		table.insert(flex, {
			basis = basis,
			value = basis,
			minimum = minimum,
			maximum = maximum,
			grow = if mode == "Fill" or mode == "Grow"
				then 1
				elseif mode == "Custom" and child then number(child, "GrowRatio")
				else 0,
			shrink = if mode == "Fill" or mode == "Shrink"
				then 1
				elseif mode == "Custom" and child then number(child, "ShrinkRatio")
				else 0,
		})
	end
	local changed = distribute(flex, available - gaps)
	local main = gaps
	for _, item in flex do
		main += item.value
	end
	local cursor = alignment(mainAlignment, available, main)
	local spacing = mainFlex == "SpaceBetween" or mainFlex == "SpaceAround" or mainFlex == "SpaceEvenly"
	if spacing and not changed and #items > 0 then
		if main - gaps > available then
			error("unsupported_ui_layout: " .. list:GetFullName() .. " requires overflowing list spacing", 0)
		end
		local leading = if horizontal then "Left" else "Top"
		if mainAlignment ~= leading then
			error(
				"unsupported_ui_layout: " .. list:GetFullName() .. " requires list spacing with non-leading alignment",
				0
			)
		end
		local spaces = if mainFlex == "SpaceBetween"
			then #items - 1
			elseif mainFlex == "SpaceAround" then #items
			else #items + 1
		local extra = math.max(0, available - main + gaps)
		gap = if spaces > 0 then extra / spaces else 0
		cursor = if mainFlex == "SpaceAround" then gap / 2 elseif mainFlex == "SpaceEvenly" then gap else 0
	end
	local line = if crossFlex == "Fill" then availableCross else cross
	local lineOffset = alignment(crossAlignment, availableCross, line)
	if crossFlex == "SpaceAround" or crossFlex == "SpaceEvenly" then
		lineOffset = (availableCross - line) / 2
	elseif crossFlex == "SpaceBetween" then
		lineOffset = 0
	end
	for index, item in items do
		local rectangle = item.rectangle
		local extent = if horizontal then rectangle.height else rectangle.width
		local child = item.object:FindFirstChildWhichIsA "UIFlexItem"
		local itemAlignment = if child then enum(child, "ItemLineAlignment", "Automatic") else "Automatic"
		if itemAlignment == "Automatic" then
			itemAlignment = enum(list, "ItemLineAlignment", "Automatic")
		end
		if itemAlignment == "Automatic" then
			itemAlignment = if crossFlex == "Fill" then "Stretch" else crossAlignment
		end
		if itemAlignment == "Stretch" then
			local minimum, maximum = bounds(item.object, not horizontal)
			extent = math.clamp(line, minimum, maximum)
		end
		local offset = if enabled
			then lineOffset + alignment(itemAlignment, line, extent)
			else alignment(crossAlignment, availableCross, extent)
		rectangle.width = if horizontal then flex[index].value else extent
		rectangle.height = if horizontal then extent else flex[index].value
		rectangle.x = content.x + (if horizontal then cursor else offset)
		rectangle.y = content.y + (if horizontal then offset else cursor)
		cursor += flex[index].value + gap
	end
	return { items = items, width = if horizontal then main else line, height = if horizontal then line else main }
end

return table.freeze { measure = measure }
