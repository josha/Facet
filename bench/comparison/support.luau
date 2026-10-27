--!strict

local Types = require("./types")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local Facet = require("../../src")
type ScreenProps = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiNativeProps)

export type Node = Roblox.Instance & { Activated: Roblox.Signal<>, DragEnd: Roblox.Signal<> }
type Properties = {
	Text: string?,
	AutoLocalize: boolean?,
	BackgroundTransparency: number?,
	BorderSizePixel: number?,
	TextSize: number?,
	Size: UDim2?,
	TextXAlignment: Enum.TextXAlignment?,
	AutoButtonColor: boolean?,
	Selectable: boolean?,
	FillDirection: Enum.FillDirection?,
	SortOrder: Enum.SortOrder?,
	Padding: UDim?,
	ZIndexBehavior: Enum.ZIndexBehavior?,
	CellSize: UDim2?,
	CellPadding: UDim2?,
	FillDirectionMaxCells: number?,
	ClipsDescendants: boolean?,
	AutomaticCanvasSize: Enum.AutomaticSize?,
	PlaceholderText: string?,
	ClearTextOnFocus: boolean?,
	CanvasSize: UDim2?,
	CanvasPosition: Vector2?,
	Image: string?,
	AutomaticSize: Enum.AutomaticSize?,
	AspectRatio: number?,
	ScrollingDirection: Enum.ScrollingDirection?,
	Anchored: boolean?,
	Adornee: Roblox.Instance?,
}

local function model<T>(world: Types.World, lane: Types.Lane, value: T): Facet.Value<T>?
	return if lane == "facet" then world.Compose.cell(value) else nil
end

local function create(
	world: Types.World,
	class: string,
	name: string,
	parent: Roblox.Instance?,
	props: Properties?
): Node
	local node: Node = world.engine.new(class)
	node.Name = name
	if props then
		if props.Text ~= nil then
			node.Text = props.Text
		end
		if props.AutoLocalize ~= nil then
			node.AutoLocalize = props.AutoLocalize
		end
		if props.BackgroundTransparency ~= nil then
			node.BackgroundTransparency = props.BackgroundTransparency
		end
		if props.BorderSizePixel ~= nil then
			node.BorderSizePixel = props.BorderSizePixel
		end
		if props.TextSize ~= nil then
			node.TextSize = props.TextSize
		end
		if props.Size ~= nil then
			node.Size = props.Size
		end
		if props.TextXAlignment ~= nil then
			node.TextXAlignment = props.TextXAlignment
		end
		if props.AutoButtonColor ~= nil then
			node.AutoButtonColor = props.AutoButtonColor
		end
		if props.Selectable ~= nil then
			node.Selectable = props.Selectable
		end
		if props.FillDirection ~= nil then
			node.FillDirection = props.FillDirection
		end
		if props.SortOrder ~= nil then
			node.SortOrder = props.SortOrder
		end
		if props.Padding ~= nil then
			node.Padding = props.Padding
		end
		if props.ZIndexBehavior ~= nil then
			node.ZIndexBehavior = props.ZIndexBehavior
		end
		if props.CellSize ~= nil then
			node.CellSize = props.CellSize
		end
		if props.CellPadding ~= nil then
			node.CellPadding = props.CellPadding
		end
		if props.FillDirectionMaxCells ~= nil then
			node.FillDirectionMaxCells = props.FillDirectionMaxCells
		end
		if props.ClipsDescendants ~= nil then
			node.ClipsDescendants = props.ClipsDescendants
		end
		if props.AutomaticCanvasSize ~= nil then
			node.AutomaticCanvasSize = props.AutomaticCanvasSize
		end
		if props.PlaceholderText ~= nil then
			node.PlaceholderText = props.PlaceholderText
		end
		if props.ClearTextOnFocus ~= nil then
			node.ClearTextOnFocus = props.ClearTextOnFocus
		end
		if props.CanvasSize ~= nil then
			node.CanvasSize = props.CanvasSize
		end
		if props.CanvasPosition ~= nil then
			node.CanvasPosition = props.CanvasPosition
		end
		if props.Image ~= nil then
			node.Image = props.Image
		end
		if props.AutomaticSize ~= nil then
			node.AutomaticSize = props.AutomaticSize
		end
		if props.AspectRatio ~= nil then
			node.AspectRatio = props.AspectRatio
		end
		if props.ScrollingDirection ~= nil then
			node.ScrollingDirection = props.ScrollingDirection
		end
		if props.Anchored ~= nil then
			node.Anchored = props.Anchored
		end
		if props.Adornee ~= nil then
			node.Adornee = props.Adornee
		end
	end
	node.Parent = parent
	return node
end

local function find(world: Types.World, name: string): Node
	local node: Node? = world.target:FindFirstChild(name, true)
	assert(node, "missing node " .. name)
	return node
end

local function tag(node: Node, ...: string)
	for _, name in { ... } do
		node:AddTag(name)
	end
end

local prepareHold: (Types.World, Node) -> () = function(_world: Types.World, _node: Node) end

local function text(world: Types.World, parent: Node, name: string, value: string, bound: boolean?): Node
	local node = create(world, "TextLabel", name, nil, {
		Text = value,
		AutoLocalize = if bound then false else nil,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = world.types.UDim2.fromOffset(0, 0),
		AutomaticSize = world.types.Enum.AutomaticSize.XY,
		TextXAlignment = world.types.Enum.TextXAlignment.Left,
	})
	tag(node, "facet-text", "facet-type-body")
	node.Parent = parent
	if bound then
		prepareHold(world, node)
	end
	return node
end

local function button(world: Types.World, parent: Node, name: string, label: string, activate: () -> ()): Node
	local node = create(world, "TextButton", name, nil, {
		Text = label,
		AutoButtonColor = false,
		Selectable = true,
		Size = world.types.UDim2.fromOffset(0, 0),
		AutomaticSize = world.types.Enum.AutomaticSize.XY,
	})
	tag(node, "facet-button", "facet-role-default")
	node.Parent = parent
	node.Activated:Connect(function(...: unknown)
		activate()
	end)
	return node
end

type Hold = { constraint: Node, widest: number, length: number }
type Styled = { GetStyled: (Styled, string) -> unknown }

local function styled(node: Node, key: string): unknown
	return ((node :: unknown) :: Styled):GetStyled(key)
end
local holds = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Node]: Hold }
local widths: { [string]: number } = {}

local function widthOf(world: Types.World, node: Node, value: string, ready: (number) -> ()): number?
	local service = world.textService
	if service == nil then
		local bounds: unknown = node.TextBounds
		return if typeof(bounds) == "Vector2" then bounds.X else 0
	end
	local face, size = styled(node, "FontFace"), styled(node, "TextSize")
	local key = `{tostring(face)}|{tostring(size)}|{value}`
	local known = widths[key]
	if known ~= nil then
		return known
	end
	local params = world.engine.new("GetTextBoundsParams")
	params.Text, params.Font, params.Size, params.Width = value, face, size, 0
	task.spawn(function()
		local ok, measured: unknown = pcall(service.GetTextBoundsAsync, service, params)
		if ok and typeof(measured) == "Vector2" then
			widths[key] = measured.X
			ready(measured.X)
		end
	end)
	return widths[key]
end

local function widen(world: Types.World, held: Hold, length: number, width: number)
	if length == held.length and width > held.widest then
		held.widest = width
		held.constraint.MinSize = world.types.Vector2.new(width, 0)
	end
end

local function holdFor(world: Types.World, node: Node): Hold
	local hold = holds[node]
	if hold == nil then
		local current = tostring(node.Text)
		local length = utf8.len(current) or #current
		local created: Hold = {
			constraint = create(world, "UISizeConstraint", "Hold", node),
			widest = 0,
			length = length,
		}
		holds[node] = created
		hold = created
		local width = widthOf(world, node, current, function(measured: number)
			widen(world, created, length, measured)
		end)
		if width then
			widen(world, created, length, width)
		end
	end
	return assert(hold)
end

prepareHold = function(world: Types.World, node: Node)
	holdFor(world, node)
end

local function setText(world: Types.World, node: Node, value: string)
	local previous = tostring(node.Text)
	if previous == value then
		return
	end
	local held = holdFor(world, node)
	node.Text = value
	local length = utf8.len(value) or #value
	if length ~= held.length then
		held.widest, held.length = 0, length
		held.constraint.MinSize = world.types.Vector2.new(0, 0)
	end
	local width = widthOf(world, node, value, function(measured: number)
		widen(world, held, length, measured)
	end)
	if width then
		widen(world, held, length, width)
	end
end

local function stack(world: Types.World, parent: Node?, name: string, horizontal: boolean?): Node
	local node = create(world, "Frame", name, parent, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = world.types.UDim2.fromOffset(640, 480),
	})
	create(world, "UIListLayout", "Layout", node, {
		FillDirection = if horizontal
			then world.types.Enum.FillDirection.Horizontal
			else world.types.Enum.FillDirection.Vertical,
		SortOrder = world.types.Enum.SortOrder.LayoutOrder,
		Padding = world.types.UDim.new(0, 8),
	})
	return node
end

local function connect(_world: Types.World, node: Node, event: string, callback: (...unknown) -> ())
	assert(event == "DragEnd")
	node.DragEnd:Connect(callback)
end

local function fire(world: Types.World, name: string, event: string, ...: unknown)
	world.engine.environment.fire(find(world, name), event, ...)
end

local function snapshot(world: Types.World, names: { string }): string
	local rows: { string } = {}
	for _, name in names do
		local node = find(world, name)
		local value = node.Text
		table.insert(rows, name .. ":" .. tostring(value))
	end
	return table.concat(rows, "\n")
end

local function themed(world: Types.World, screen: Node): () -> ()
	local stop = world.runtime.mount(function()
		return Facet.themes.createStyleSheet(world.runtime, Facet.themes.neutralPackage(), { types = world.types })
	end, screen)
	local sheet = screen:FindFirstChildWhichIsA("StyleSheet")
	local link: Node = world.engine.new("StyleLink")
	link.StyleSheet = sheet
	link.Parent = screen
	local warm: Node = world.engine.new("Folder")
	warm.Name = "StateTags"
	for _, name in { "facet-selected", "facet-disabled", "facet-busy" } do
		warm:AddTag(name)
	end
	warm.Parent = screen
	return stop
end

local function mount(
	world: Types.World,
	lane: Types.Lane,
	facet: () -> Instance,
	bare: (Node) -> (),
	unthemed: boolean?
): () -> ()
	if lane == "facet" then
		local Host = world.Host
		local screen: Instance? = nil
		local stop = world.runtime.mount(function()
			return world.UI.provide(function()
				local props: ScreenProps = { Name = "Comparison", facet() }
				local made = Host.ScreenGui(props)
				screen = made
				return made
			end)
		end, world.target)
		local unstyle = if unthemed then nil else themed(world, (assert(screen) :: unknown) :: Node)
		return function()
			if unstyle then
				unstyle()
			end
			stop()
		end
	end
	local screen = create(world, "ScreenGui", "Comparison", world.target, {
		ZIndexBehavior = world.types.Enum.ZIndexBehavior.Sibling,
	})
	bare(screen)
	local unstyle = if unthemed then nil else themed(world, screen)
	for _, node in screen:GetDescendants() do
		if node:IsA("GuiObject") then
			((node :: unknown) :: Styled):GetStyled("Visible")
		end
	end
	return function()
		if unstyle then
			unstyle()
		end
		screen:Destroy()
	end
end

local function grid(world: Types.World, parent: Node, name: string, columns: number): Node
	local node = create(world, "Frame", name, parent, {
		BackgroundTransparency = 1,
		Size = world.types.UDim2.fromOffset(640, 480),
	})
	create(world, "UIGridLayout", "Layout", node, {
		CellSize = world.types.UDim2.fromOffset(640 / columns - 8, 44),
		CellPadding = world.types.UDim2.fromOffset(8, 8),
		FillDirectionMaxCells = columns,
		SortOrder = world.types.Enum.SortOrder.LayoutOrder,
	})
	return node
end

local function progress(world: Types.World, parent: Node, name: string, value: number): Node
	local root = stack(world, parent, name, true)
	local track = create(world, "Frame", "Track", root, { Size = world.types.UDim2.fromOffset(240, 6) })
	local clip = create(world, "Frame", "FillClip", track, {
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		Size = world.types.UDim2.fromScale(1, 1),
	})
	return create(world, "Frame", "Fill1", clip, { Size = world.types.UDim2.fromScale(value, 1) })
end

local function fraction(world: Types.World, name: string): string
	local clip = find(world, name):FindFirstChild("Fill1", true)
	assert(clip)
	local size: unknown = clip.Size
	assert(typeof(size) == "UDim2")
	return string.format("%.4f", size.X.Scale)
end

local function setProgress(world: Types.World, name: string, value: number)
	local fill = assert(find(world, name):FindFirstChild("Fill1", true))
	fill.Size = world.types.UDim2.fromScale(value, 1)
end

return {
	model = model,
	create = create,
	find = find,
	text = text,
	button = button,
	tag = tag,
	setText = setText,
	stack = stack,
	connect = connect,
	fire = fire,
	snapshot = snapshot,
	mount = mount,
	grid = grid,
	progress = progress,
	fraction = fraction,
	setProgress = setProgress,
}
