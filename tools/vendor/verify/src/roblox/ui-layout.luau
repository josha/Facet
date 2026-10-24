--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"
local Grid = require "./ui-grid-layout"
local List = require "./ui-list-layout"
local Float = require "./datatypes/float"
local Values = require "./ui-values"

type Instance = Environment.Instance
type Vector = { X: number, Y: number }
type TextMeasurement = { X: number, Y: number, intrinsicX: number, intrinsicY: number, fits: boolean }
type Dimension = { Scale: number, Offset: number }
type Dimensions = { X: Dimension, Y: Dimension }
type Rectangle = { x: number, y: number, width: number, height: number, scale: number }
export type Options = {
	roots: () -> { Instance },
	viewport: () -> Vector,
	origin: (() -> Vector)?,
	read: ((Instance, string) -> unknown)?,
	component: ((Instance, string, string) -> unknown)?,
	vector: ((number, number) -> unknown)?,
	measureBounds: ((Values.TextParameters) -> unknown)?,
}
export type Controller = {
	step: () -> (),
	objectsAtPosition: (root: Instance, x: number, y: number) -> { Instance },
}

local function attach(environment: Environment.Environment, options: Options): Controller
	local read: (Instance, string) -> unknown = options.read or environment.propertyOf
	local vector: (number, number) -> unknown = options.vector
		or function(x: number, y: number): unknown
			return Datatypes.Vector2.new(x, y)
		end
	local function optional(object: Instance, property: string): unknown
		return read(object, property)
	end
	local function enum(object: Instance, property: string, fallback: string): string
		local value = optional(object, property)
		return if value == nil then fallback else tostring(value):match "([^%.]+)$" or fallback
	end
	local function number(object: Instance, property: string, fallback: number): number
		local value = optional(object, property)
		return if type(value) == "number" then value else fallback
	end
	local function dimension(unit: Values.Dimension, extent: number, scale: number): number
		return unit.Scale * extent + unit.Offset * scale
	end
	local function paddingValue(object: Instance, property: string): unknown
		if options.component then
			return options.component(object, "UIPadding", property)
		end
		local padding = object:FindFirstChildWhichIsA "UIPadding"
		return if padding then read(padding, property) else nil
	end
	local function unsupported(object: Instance, mechanism: string)
		error("unsupported_ui_layout: " .. object:GetFullName() .. " requires " .. mechanism, 0)
	end
	local function isText(object: Instance): boolean
		return object:IsA "TextLabel" or object:IsA "TextButton" or object:IsA "TextBox"
	end
	local function validate(object: Instance)
		if object:IsA "LayerCollector" and not object:IsA "ScreenGui" then
			unsupported(object, object.ClassName)
		end
		if object:IsA "GuiObject" then
			if enum(object, "AutomaticSize", "None") ~= "None" then
				if isText(object) then
					if options.measureBounds == nil then
						unsupported(object, "AutomaticSize text measurement")
					end
				end
			end
			if number(object, "Rotation", 0) ~= 0 then
				unsupported(object, "Rotation")
			end
			if enum(object, "SizeConstraint", "RelativeXY") ~= "RelativeXY" then
				unsupported(object, "SizeConstraint")
			end
		end
		if object:IsA "StyleLink" and options.read == nil then
			unsupported(object, "StyleLink without a styled property reader")
		end
		if object:IsA "UITableLayout" or object:IsA "UIPageLayout" then
			unsupported(object, object.ClassName)
		end
		if object:IsA "UIAspectRatioConstraint" then
			local ratio = number(object, "AspectRatio", 1)
			if ratio <= 0 or ratio >= math.huge or ratio ~= ratio then
				unsupported(object, "invalid aspect ratio")
			end
			local parent = object.Parent
			if parent and parent:IsA "GuiObject" and enum(parent, "AutomaticSize", "None") ~= "None" then
				unsupported(parent, "aspect constraint with automatic size")
			end
		end
		for _, child in object:GetChildren() do
			validate(child)
		end
	end
	local function inset(object: Instance, rectangle: Rectangle): Rectangle
		local padding = paddingValue(object, "PaddingLeft")
		if padding == nil then
			return rectangle
		end
		local left = dimension(Values.dimension(padding), rectangle.width, rectangle.scale)
		local right =
			dimension(Values.dimension(paddingValue(object, "PaddingRight")), rectangle.width, rectangle.scale)
		local top = dimension(Values.dimension(paddingValue(object, "PaddingTop")), rectangle.height, rectangle.scale)
		local bottom =
			dimension(Values.dimension(paddingValue(object, "PaddingBottom")), rectangle.height, rectangle.scale)
		return {
			x = rectangle.x + left,
			y = rectangle.y + top,
			width = math.max(0, rectangle.width - left - right),
			height = math.max(0, rectangle.height - top - bottom),
			scale = rectangle.scale,
		}
	end
	local function textBounds(object: Instance, rectangle: Rectangle, intrinsic: boolean?): TextMeasurement?
		if options.measureBounds == nil or not (isText(object)) then
			return nil
		end
		if optional(object, "TextScaled") == true then
			unsupported(object, "TextScaled")
		end
		if enum(object, "TextTruncate", "None") ~= "None" then
			unsupported(object, "TextTruncate")
		end
		local size = number(object, "TextSize", 14)
		local rendered = size * rectangle.scale
		if size ~= math.floor(size) or rendered ~= math.floor(rendered) or rendered < 1 or rendered > 100 then
			unsupported(object, "fractional or out-of-range rendered text size")
		end
		local content = inset(object, rectangle)
		local automatic = enum(object, "AutomaticSize", "None")
		local autoX, autoY = automatic == "X" or automatic == "XY", automatic == "Y" or automatic == "XY"
		local maximumX, maximumY = math.huge, math.huge
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint then
			local maximum = Values.vector(read(constraint, "MaxSize"))
			maximumX = math.max(0, maximum.X * rectangle.scale - rectangle.width + content.width)
			maximumY = math.max(0, maximum.Y * rectangle.scale - rectangle.height + content.height)
		end
		local wrapped = optional(object, "TextWrapped") == true
		local parameters = {
			Text = Values.string(read(object, "Text")),
			Font = Values.font(read(object, "FontFace")),
			Size = rendered,
			Width = if wrapped then content.width else 0,
			RichText = optional(object, "RichText") == true,
		}
		local intrinsicX = content.width
		if intrinsic and autoX then
			parameters.Width = 0
			local unwrapped = Values.vector(options.measureBounds(parameters))
			intrinsicX = math.min(math.max(content.width, unwrapped.X), maximumX)
			parameters.Width = if wrapped then intrinsicX else 0
		end
		local measured = Values.vector(options.measureBounds(parameters))
		local strut =
			Values.vector(options.measureBounds { Text = "", Font = parameters.Font, Size = rendered, Width = 0 })
		local lines = measured.Y / strut.Y
		local step = Float.f32(Float.f32(number(object, "LineHeight", 1)) * strut.Y)
		local function height(count: number): number
			return Float.f32(strut.Y + Float.f32(step * (count - 1)))
		end
		local fullHeight = height(lines)
		local availableHeight = if intrinsic and autoY then maximumY else content.height
		local visible = lines
		if wrapped then
			local low, high = 1, lines
			while low < high do
				local middle = math.ceil((low + high) / 2)
				if height(middle) <= availableHeight then
					low = middle
				else
					high = middle - 1
				end
			end
			visible = low
		elseif not intrinsic and lines > 1 and fullHeight > content.height then
			unsupported(object, "unwrapped multiline text exceeds available height")
		end
		return {
			X = measured.X,
			Y = height(visible),
			intrinsicX = if intrinsic and autoX then intrinsicX else measured.X,
			intrinsicY = fullHeight,
			fits = measured.X <= content.width and fullHeight <= content.height,
		}
	end
	local size: (Instance, Rectangle, number?) -> Rectangle
	size = function(object: Instance, parent: Rectangle, widthOverride: number?): Rectangle
		local authored = Values.dimensions(read(object, "Size"))
		local scale = parent.scale
		local modifier = object:FindFirstChildWhichIsA "UIScale"
		if modifier then
			scale *= number(modifier, "Scale", 1)
		end
		local width = dimension(authored.X, parent.width, parent.scale)
		local height = dimension(authored.Y, parent.height, parent.scale)
		local constraint = object:FindFirstChildWhichIsA "UISizeConstraint"
		if constraint then
			local minimum = Values.vector(read(constraint, "MinSize"))
			local maximum = Values.vector(read(constraint, "MaxSize"))
			width = math.clamp(width, minimum.X * parent.scale, maximum.X * parent.scale)
			height = math.clamp(height, minimum.Y * parent.scale, maximum.Y * parent.scale)
		end
		local factor = if parent.scale == 0 then 0 else scale / parent.scale
		local rectangle: Rectangle = {
			x = 0,
			y = 0,
			width = math.max(0, width * factor),
			height = math.max(0, height * factor),
			scale = scale,
		}
		if widthOverride ~= nil then
			rectangle.width = widthOverride
		end
		local aspect = object:FindFirstChildWhichIsA "UIAspectRatioConstraint"
		if aspect then
			local ratio = number(aspect, "AspectRatio", 1)
			if ratio <= 0 or ratio >= math.huge then
				unsupported(aspect, "invalid aspect ratio")
			end
			if enum(aspect, "AspectType", "FitWithinMaxSize") == "FitWithinMaxSize" then
				rectangle.width = math.min(rectangle.width, rectangle.height * ratio)
				rectangle.height = rectangle.width / ratio
			elseif enum(aspect, "DominantAxis", "Width") == "Width" then
				rectangle.width = math.min(rectangle.width, parent.width * factor, parent.height * ratio * factor)
				rectangle.height = rectangle.width / ratio
			else
				rectangle.height = math.min(rectangle.height, parent.height * factor, parent.width / ratio * factor)
				rectangle.width = rectangle.height * ratio
			end
		end
		local automatic = enum(object, "AutomaticSize", "None")
		if automatic == "None" then
			return rectangle
		end
		local autoX, autoY = automatic == "X" or automatic == "XY", automatic == "Y" or automatic == "XY"
		local padding = paddingValue(object, "PaddingLeft")
		local paddingX, paddingY = 0, 0
		if padding then
			for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
				local unit = Values.dimension(paddingValue(object, property))
				if unit.Scale ~= 0 then
					unsupported(object, "AutomaticSize with scaled padding")
				end
			end
			paddingX = (
				(Values.dimension(padding)).Offset + (Values.dimension(paddingValue(object, "PaddingRight"))).Offset
			) * scale
			paddingY = (
				(Values.dimension(paddingValue(object, "PaddingTop"))).Offset
				+ (Values.dimension(paddingValue(object, "PaddingBottom"))).Offset
			) * scale
		end
		local content = inset(object, rectangle)
		local grid = object:FindFirstChildWhichIsA "UIGridLayout"
		if grid then
			local cell = Values.dimensions(read(grid, "CellSize"))
			if (autoX and cell.X.Scale ~= 0) or (autoY and cell.Y.Scale ~= 0) then
				unsupported(grid, "grid cells relative to an automatic parent axis")
			end
			local measured = Grid.measure(grid, content, read)
			if autoX then
				rectangle.width = math.max(rectangle.width, measured.width + paddingX)
			end
			if autoY then
				rectangle.height = math.max(rectangle.height, measured.height + paddingY)
			end
			return rectangle
		end
		local list = object:FindFirstChildWhichIsA "UIListLayout"
		local horizontal = list ~= nil and enum(list, "FillDirection", "Vertical") == "Horizontal"
		if list and optional(list, "Wraps") == true and not (if horizontal then autoX else autoY) then
			for _, child in object:GetChildren() do
				if child:IsA "GuiObject" and optional(child, "Visible") ~= false then
					local authoredChild = Values.dimensions(read(child, "Size"))
					if (autoX and authoredChild.X.Scale ~= 0) or (autoY and authoredChild.Y.Scale ~= 0) then
						unsupported(child, "size relative to an automatic parent axis")
					end
				end
			end
			local measured = List.measure(list, content, read, size, size)
			if autoX then
				rectangle.width = math.max(rectangle.width, measured.width + paddingX)
			end
			if autoY then
				rectangle.height = math.max(rectangle.height, measured.height + paddingY)
			end
			return rectangle
		end
		local gap = 0
		if list then
			local unit = Values.dimension(read(list, "Padding"))
			if unit.Scale ~= 0 then
				unsupported(object, "AutomaticSize with scaled list padding")
			end
			gap = unit.Offset * scale
		end
		if widthOverride ~= nil and isText(object) and autoX and optional(object, "TextWrapped") == true then
			unsupported(object, "wrapped automatic width controlled by a list")
		end
		local bounds = textBounds(object, rectangle, true)
		local intrinsicWidth, intrinsicHeight, count =
			if bounds then bounds.intrinsicX else 0,
			if bounds then (if widthOverride ~= nil and autoY then bounds.intrinsicY else bounds.Y) else 0,
			0
		for _, child in object:GetChildren() do
			if child:IsA "GuiObject" and optional(child, "Visible") ~= false then
				local authoredChild = Values.dimensions(read(child, "Size"))
				local position = Values.dimensions(read(child, "Position"))
				local anchor = Values.vector(read(child, "AnchorPoint"))
				if (autoX and authoredChild.X.Scale ~= 0) or (autoY and authoredChild.Y.Scale ~= 0) then
					unsupported(child, "size relative to an automatic parent axis")
				end
				if
					list == nil
					and (
						(autoX and (position.X.Scale ~= 0 or anchor.X ~= 0))
						or (autoY and (position.Y.Scale ~= 0 or anchor.Y ~= 0))
					)
				then
					unsupported(child, "position relative to an automatic parent axis")
				end
				local childSize = size(child, content)
				if list then
					intrinsicWidth = if horizontal
						then intrinsicWidth + childSize.width
						else math.max(intrinsicWidth, childSize.width)
					intrinsicHeight = if horizontal
						then math.max(intrinsicHeight, childSize.height)
						else intrinsicHeight + childSize.height
				else
					intrinsicWidth = math.max(intrinsicWidth, position.X.Offset * scale + childSize.width)
					intrinsicHeight = math.max(intrinsicHeight, position.Y.Offset * scale + childSize.height)
				end
				count += 1
			end
		end
		if list then
			if horizontal then
				intrinsicWidth += math.max(0, count - 1) * gap
			else
				intrinsicHeight += math.max(0, count - 1) * gap
			end
		end
		if autoX then
			rectangle.width = math.max(rectangle.width, intrinsicWidth + paddingX)
		end
		if autoY then
			rectangle.height = math.max(rectangle.height, intrinsicHeight + paddingY)
			if widthOverride ~= nil and isText(object) and constraint then
				rectangle.height = math.min(rectangle.height, (Values.vector(read(constraint, "MaxSize"))).Y * scale)
			end
		end
		return rectangle
	end
	local function step()
		local roots = options.roots()
		for _, root in roots do
			validate(root)
		end
		local viewport = options.viewport()
		local origin = if options.origin then options.origin() else { X = 0, Y = 0 }
		local screen: Rectangle = { x = origin.X, y = origin.Y, width = viewport.X, height = viewport.Y, scale = 1 }
		local measureTree: (Instance, Rectangle, Rectangle?) -> ()
		measureTree = function(object: Instance, parent: Rectangle, placed: Rectangle?)
			local rectangle = if object:IsA "GuiObject" then placed or size(object, parent) else parent
			if
				placed
				and (isText(object))
				and optional(object, "TextWrapped") == true
				and enum(object, "AutomaticSize", "None") ~= "None"
			then
				local list = if object.Parent then object.Parent:FindFirstChildWhichIsA "UIListLayout" else nil
				local reflowed = list ~= nil
					and optional(list, "Wraps") ~= true
					and enum(list, "FillDirection", "Vertical") == "Vertical"
					and enum(list, "HorizontalFlex", "None") == "Fill"
				if not reflowed and placed.width ~= size(object, parent).width then
					unsupported(object, "wrapped automatic text with an unmodeled flexed width")
				end
			end
			textBounds(object, rectangle)
			local content = inset(object, rectangle)
			local placements: { [Instance]: Rectangle } = {}
			local grid = object:FindFirstChildWhichIsA "UIGridLayout"
			local list = object:FindFirstChildWhichIsA "UIListLayout"
			if grid then
				for _, item in Grid.measure(grid, content, read).items do
					placements[item.object] = item.rectangle
				end
			elseif list then
				for _, item in List.measure(list, content, read, size, size).items do
					placements[item.object] = item.rectangle
				end
			end
			for _, child in object:GetChildren() do
				measureTree(child, content, placements[child])
			end
		end
		for _, root in roots do
			measureTree(root, screen, nil)
		end
		local function publish(object: Instance, rectangle: Rectangle)
			local bounds = textBounds(object, rectangle)
			if bounds then
				environment.poke(object, "TextBounds", vector(bounds.X, bounds.Y))
				environment.poke(object, "TextFits", bounds.fits)
			end
			environment.poke(object, "AbsolutePosition", vector(rectangle.x, rectangle.y))
			environment.poke(object, "AbsoluteSize", vector(rectangle.width, rectangle.height))
		end
		local visit: (Instance, Rectangle, Rectangle?) -> ()
		visit = function(object: Instance, parent: Rectangle, placed: Rectangle?)
			local rectangle = parent
			if object:IsA "GuiObject" then
				rectangle = placed or size(object, parent)
				if placed == nil then
					local position = Values.dimensions(read(object, "Position"))
					local anchor = Values.vector(read(object, "AnchorPoint"))
					rectangle.x = parent.x
						+ dimension(position.X, parent.width, parent.scale)
						- anchor.X * rectangle.width
					rectangle.y = parent.y
						+ dimension(position.Y, parent.height, parent.scale)
						- anchor.Y * rectangle.height
				end
				publish(object, rectangle)
			elseif object:IsA "ScreenGui" then
				publish(object, rectangle)
			end
			local content = inset(object, rectangle)
			if object:IsA "ScrollingFrame" then
				local canvas = Values.vector(read(object, "CanvasPosition"))
				content = table.clone(content)
				content.x -= canvas.X * content.scale
				content.y -= canvas.Y * content.scale
			end
			local list = object:FindFirstChildWhichIsA "UIListLayout"
			local grid = object:FindFirstChildWhichIsA "UIGridLayout"
			local children = object:GetChildren()
			local placements: { [Instance]: Rectangle } = {}
			if grid then
				local measured = Grid.measure(grid, content, read)
				for _, item in measured.items do
					placements[item.object] = item.rectangle
				end
				environment.poke(grid, "AbsoluteContentSize", vector(measured.width, measured.height))
				environment.poke(grid, "AbsoluteCellSize", vector(measured.cellWidth, measured.cellHeight))
				environment.poke(grid, "AbsoluteCellCount", vector(measured.columns, measured.rows))
			elseif list then
				local measured = List.measure(list, content, read, size, size)
				for _, item in measured.items do
					placements[item.object] = item.rectangle
				end
				environment.poke(list, "AbsoluteContentSize", vector(measured.width, measured.height))
			end
			for _, child in children do
				visit(child, content, placements[child])
			end
		end
		for _, root in roots do
			visit(root, screen, nil)
		end
	end
	local function objectsAtPosition(root: Instance, x: number, y: number): { Instance }
		assert(
			x == math.floor(x) and y == math.floor(y) and math.abs(x) < math.huge and math.abs(y) < math.huge,
			"hit testing requires finite integer coordinates"
		)
		validate(root)
		type Order = { z: number, index: number }
		type Hit = {
			object: Instance,
			screen: Instance,
			display: number,
			mode: string,
			z: number,
			index: number,
			path: { Order },
		}
		local hits: { Hit } = {}
		local index = 0
		local displays: { [number]: Instance } = {}
		local function contains(object: Instance): boolean
			local at = Values.vector(environment.propertyOf(object, "AbsolutePosition"))
			local size = Values.vector(environment.propertyOf(object, "AbsoluteSize"))
			assert(at ~= nil and size ~= nil, "hit testing requires published layout")
			return size.X > 0 and size.Y > 0 and x >= at.X and y >= at.Y and x <= at.X + size.X and y <= at.Y + size.Y
		end
		local visit: (Instance, Instance?, { Order }, number, boolean) -> ()
		visit = function(object: Instance, screen: Instance?, path: { Order }, sibling: number, clipped: boolean)
			if object:IsA "ScreenGui" then
				if optional(object, "Enabled") == false then
					return
				end
				screen = object
				path = {}
				local display = number(object, "DisplayOrder", 0)
				local prior = displays[display]
				if prior and prior ~= object then
					unsupported(object, "equal DisplayOrder across ScreenGuis")
				end
				displays[display] = object
			elseif object:IsA "LayerCollector" then
				unsupported(object, object.ClassName .. " hit testing")
			end
			if object:IsA "GuiObject" then
				if optional(object, "Visible") == false then
					return
				end
				if screen == nil then
					unsupported(object, "hit testing outside ScreenGui")
				end
				index += 1
				local branch = table.clone(path)
				table.insert(branch, { z = number(object, "ZIndex", 1), index = sibling })
				path = branch
				local inside = contains(object)
				if inside and not clipped then
					local mode = enum(assert(screen), "ZIndexBehavior", "Sibling")
					if mode ~= "Sibling" and mode ~= "Global" then
						unsupported(object, "ZIndexBehavior." .. mode)
					end
					table.insert(hits, {
						object = object,
						screen = assert(screen),
						display = number(assert(screen), "DisplayOrder", 0),
						mode = mode,
						z = number(object, "ZIndex", 1),
						index = index,
						path = path,
					})
				end
				clipped = clipped or optional(object, "ClipsDescendants") == true and not inside
			end
			for ordinal, child in object:GetChildren() do
				if child:IsA "GuiObject" and not object:IsA "GuiObject" and not object:IsA "ScreenGui" then
					unsupported(child, "non-GuiObject hit-testing parent")
				end
				visit(child, screen, path, ordinal, clipped)
			end
		end
		visit(root, nil, {}, 1, false)
		table.sort(hits, function(a: Hit, b: Hit): boolean
			if a.display ~= b.display then
				return a.display > b.display
			end
			if a.screen ~= b.screen then
				unsupported(a.screen, "equal DisplayOrder across ScreenGuis")
			end
			if a.mode == "Global" then
				return if a.z ~= b.z then a.z > b.z else a.index > b.index
			end
			for ordinal = 1, math.min(#a.path, #b.path) do
				local first, second = a.path[ordinal], b.path[ordinal]
				if first.z ~= second.z then
					return first.z > second.z
				end
				if first.index ~= second.index then
					return first.index > second.index
				end
			end
			return #a.path > #b.path
		end)
		local result: { Instance } = {}
		for _, hit in hits do
			table.insert(result, hit.object)
		end
		return result
	end
	return { step = step, objectsAtPosition = objectsAtPosition }
end

return { attach = attach }
