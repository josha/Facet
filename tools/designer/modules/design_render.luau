--!strict
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T

local library = require("./library")
local document = require("./document")
local adapter = require("./adapter")

local render = {}

function render.build(value: document.Document, ctx: any, editing: any?): GuiObject
	document.validate(value)
	local UDim2 = if ctx.types then ctx.types.UDim2 else UDim2
	local locals = {}
	local nodes: { [string]: GuiObject } = {}
	local known: { [string]: document.Node } = {}
	ctx.types = ctx.types or { UDim2 = UDim2, Color3 = Color3 }
	local build
	build = function(node: document.Node, scope: any?): GuiObject
		local definition = library.definitions[node.kind]
		local state = scope or locals
		local props = adapter.evaluate(adapter.properties(node), ctx, state)
		if
			not definition.content
			and node.kind ~= "ErrorBoundary"
			and node.kind ~= "TabView"
			and node.kind ~= "PageView"
			and node.kind ~= "NavigationStack"
			and node.kind ~= "NavigationSplitView"
			and not table.find({ "Table", "VirtualList", "VirtualGrid", "Outline" }, node.kind)
		then
			for _, child in node.children do
				table.insert(props, build(child, scope))
			end
		end
		local instance = ctx.UI[node.kind](node.name)(props)
		if definition.anchor then
			instance =
				ctx.UI.VStack("__FacetDesignHost_" .. node.id)({ gap = "s", state["anchor_" .. node.id], instance })
		end
		if editing then
			instance:SetAttribute("FacetDesignNode", node.id)
			nodes[node.id] = instance
			known[node.id] = node
		end
		return instance
	end
	ctx.render = build
	local root = build(value.root)
	if editing then
		local Compose, Host, types = ctx.Compose, ctx.Host, ctx.types
		local Enum, UDim, UDim2, Vector2 =
			types.Enum or Enum, types.UDim or UDim, types.UDim2 or UDim2, types.Vector2 or Vector2
		local Color3, Font = types.Color3 or Color3, types.Font or Font
		local accent = Color3.fromRGB(53, 129, 247)
		local hovered = Compose.cell(nil :: string?)
		local function contains(instance: GuiObject, position: Vector2): boolean
			local current: Instance? = instance
			while current and current:IsA("GuiObject") do
				if not current.Visible then
					return false
				end
				if current == instance or current.ClipsDescendants then
					local p, size = current.AbsolutePosition, current.AbsoluteSize
					if
						position.X < p.X
						or position.Y < p.Y
						or position.X > p.X + size.X
						or position.Y > p.Y + size.Y
					then
						return false
					end
				end
				current = current.Parent
			end
			return true
		end
		local function pick(position: Vector2): string
			local chosen, deepest = value.root.id, 0
			for _, instance in root:GetDescendants() do
				local id = instance:GetAttribute("FacetDesignNode")
				if type(id) == "string" and instance:IsA("GuiObject") and contains(instance, position) then
					local depth, ancestor = 0, instance.Parent
					while ancestor and ancestor ~= root do
						depth += 1
						ancestor = ancestor.Parent
					end
					if depth >= deepest then
						deepest, chosen = depth, id
					end
				end
			end
			return chosen
		end
		local function pointer(input: InputObject): boolean
			return input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
		end
		local capture = Host.Frame("DesignSelection")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 2000,
			Visible = function(use: Use)
				return not use(editing.interactive)
			end,
			[Compose.event("InputBegan")] = function(input: InputObject)
				if pointer(input) then
					editing.select(pick(Vector2.new(input.Position.X, input.Position.Y)))
				end
			end,
			[Compose.event("InputChanged")] = function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					hovered:set(pick(Vector2.new(input.Position.X, input.Position.Y)))
				end
			end,
			[Compose.event("MouseLeave")] = function()
				hovered:set(nil)
			end,
		})
		local SNAP = 4
		local function scale(): number
			local factor, current: Instance? = 1, capture
			while current do
				local uiScale = current:FindFirstChildWhichIsA("UIScale")
				if uiScale then
					factor *= uiScale.Scale
				end
				current = current.Parent
			end
			return factor
		end
		local MOVE_SLOP = 6
		local function depthOf(instance: Instance): number
			local depth, ancestor = 0, instance.Parent
			while ancestor and ancestor ~= root do
				depth += 1
				ancestor = ancestor.Parent
			end
			return depth
		end
		local function containerAt(position: Vector2, moving: document.Node): document.Node?
			local chosen: document.Node?, deepest = nil, -1
			for id, instance in nodes do
				local node = known[id]
				if
					node
					and library.definitions[node.kind].container
					and document.find(moving, id) == nil
					and contains(instance, position)
				then
					local depth = depthOf(instance)
					if depth > deepest then
						chosen, deepest = node, depth
					end
				end
			end
			return chosen
		end
		local function slot(container: document.Node, moving: document.Node, position: Vector2): (number, UDim2, UDim2)
			local box = nodes[container.id]
			local siblings: { GuiObject } = {}
			for _, child in container.children do
				local instance = nodes[child.id]
				if child.id ~= moving.id and instance then
					table.insert(siblings, instance)
				end
			end
			local horizontal = #siblings >= 2
				and math.abs(siblings[2].AbsolutePosition.X - siblings[1].AbsolutePosition.X)
					> math.abs(siblings[2].AbsolutePosition.Y - siblings[1].AbsolutePosition.Y)
			local factor, origin = scale(), capture.AbsolutePosition
			local function line(at: number): (UDim2, UDim2)
				local start = (box.AbsolutePosition - origin) / factor
				local extent = box.AbsoluteSize / factor
				if horizontal then
					return UDim2.fromOffset((at - origin.X) / factor - 1, start.Y), UDim2.fromOffset(2, extent.Y)
				end
				return UDim2.fromOffset(start.X, (at - origin.Y) / factor - 1), UDim2.fromOffset(extent.X, 2)
			end
			for index, instance in siblings do
				local centre = instance.AbsolutePosition + instance.AbsoluteSize / 2
				if if horizontal then position.X < centre.X else position.Y < centre.Y then
					local at, size =
						line(if horizontal then instance.AbsolutePosition.X else instance.AbsolutePosition.Y)
					return index, at, size
				end
			end
			local last: GuiObject? = siblings[#siblings]
			local edge = if not last
				then (if horizontal then box.AbsolutePosition.X else box.AbsolutePosition.Y)
				elseif horizontal then last.AbsolutePosition.X + last.AbsoluteSize.X
				else last.AbsolutePosition.Y + last.AbsoluteSize.Y
			local at, size = line(edge)
			return #siblings + 1, at, size
		end
		if editing.move then
			local marker = Host.Frame("DesignDropMarker")({
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				Visible = false,
				Interactable = false,
				ZIndex = 2004,
			})
			marker.Parent = capture
			local moving: document.Node? = nil
			local origin = Vector2.zero
			local target: { container: string, before: number }? = nil
			local detector = Host.UIDragDetector({
				DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane,
				ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset,
			})
			detector.DragStart:Connect(function(position: Vector2)
				local id = pick(position)
				moving = if id == value.root.id then nil else known[id]
				origin, target = position, nil
			end)
			detector.DragContinue:Connect(function(position: Vector2)
				local node = moving
				if node == nil or (position - origin).Magnitude < MOVE_SLOP then
					return
				end
				local container = containerAt(position, node)
				if container == nil then
					target, marker.Visible = nil, false
					return
				end
				local before, at, size = slot(container, node, position)
				target = { container = container.id, before = before }
				marker.Position, marker.Size, marker.Visible = at, size, true
			end)
			detector.DragEnd:Connect(function()
				local node, chosen = moving, target
				moving, target, marker.Visible = nil, nil, false
				if node and chosen then
					editing.move(node.id, chosen.container, chosen.before)
				end
			end)
			detector.Parent = capture
		end
		local grips = {
			{ name = "ResizeEast", anchor = Vector2.new(1, 0.5), width = true, height = false },
			{ name = "ResizeSouth", anchor = Vector2.new(0.5, 1), width = false, height = true },
			{ name = "ResizeSouthEast", anchor = Vector2.new(1, 1), width = true, height = true },
		}
		local function outline(name: string, thickness: number, target: (Use) -> string?, sized: boolean)
			local readout = if sized
				then Host.TextLabel("Size")({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 1, 4),
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundColor3 = accent,
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 12,
					FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
					Interactable = false,
					Host.UIPadding({
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
						PaddingTop = UDim.new(0, 1),
						PaddingBottom = UDim.new(0, 1),
					}),
					Host.UICorner({ CornerRadius = UDim.new(0, 3) }),
				})
				else nil
			local frame = Host.Frame(name)({
				BackgroundTransparency = 1,
				Visible = false,
				Interactable = false,
				ZIndex = 2001,
				Host.UIStroke({ Color = accent, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
				readout,
			})
			local shown: GuiObject? = nil
			local shownId: string? = nil
			local preview: Vector2? = nil
			local handles = if sized and editing.resize
				then Host.Frame(name .. "Handles")({
					BackgroundTransparency = 1,
					Visible = false,
					ZIndex = 2002,
				})
				else nil
			local function place()
				local instance = shown
				if instance == nil or instance.Parent == nil then
					frame.Visible = false
					if handles then
						handles.Visible = false
					end
					return
				end
				local factor = scale()
				local at = (instance.AbsolutePosition - capture.AbsolutePosition) / factor
				local size = preview or instance.AbsoluteSize / factor
				frame.Position = UDim2.fromOffset(at.X, at.Y)
				frame.Size = UDim2.fromOffset(size.X, size.Y)
				frame.Visible = true
				if handles then
					handles.Position, handles.Size, handles.Visible = frame.Position, frame.Size, true
				end
				if readout then
					readout.Text = `{math.round(size.X)} × {math.round(size.Y)}`
				end
			end
			if handles then
				for _, grip in grips do
					local start, origin, travel = Vector2.zero, Vector2.zero, Vector2.zero
					local detector = Host.UIDragDetector({
						DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane,
						ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset,
					})
					local function dragged(): Vector2
						local function snap(extent: number, delta: number, active: boolean): number
							return if active then math.max(SNAP, math.round((extent + delta) / SNAP) * SNAP) else extent
						end
						return Vector2.new(snap(start.X, travel.X, grip.width), snap(start.Y, travel.Y, grip.height))
					end
					detector.DragStart:Connect(function(position: Vector2)
						origin, travel = position, Vector2.zero
						start = if shown then shown.AbsoluteSize / scale() else Vector2.zero
						preview = start
					end)
					detector.DragContinue:Connect(function(position: Vector2)
						travel = (position - origin) / scale()
						preview = dragged()
						place()
					end)
					detector.DragEnd:Connect(function()
						local id, size = shownId, dragged()
						preview = nil
						place()
						if id and size ~= start then
							editing.resize(id, {
								width = if grip.width then size.X else nil,
								height = if grip.height then size.Y else nil,
							})
						end
					end)
					local handle = Host.Frame(grip.name)({
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(grip.anchor.X, grip.anchor.Y),
						Size = UDim2.fromOffset(10, 10),
						BackgroundColor3 = Color3.new(1, 1, 1),
						Active = true,
						ZIndex = 2003,
						Host.UIStroke({ Color = accent, Thickness = 1.5 }),
						Host.UISizeConstraint({ MinSize = Vector2.new(10, 10) }),
						detector,
					})
					handle.Parent = handles
				end
			end
			local connections: { RBXScriptConnection } = {}
			local function release()
				for _, connection in connections do
					connection:Disconnect()
				end
				table.clear(connections)
			end
			Compose.watch(function(use: Use)
				local id = target(use)
				release()
				shownId = id
				shown = if id then nodes[id] else nil
				local instance = shown
				if instance then
					for _, property in { "AbsolutePosition", "AbsoluteSize" } do
						table.insert(connections, instance:GetPropertyChangedSignal(property):Connect(place))
					end
					table.insert(connections, capture:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
				end
				place()
			end)
			Compose.cleanup(release)
			frame.Parent = capture
			if handles then
				handles.Parent = capture
			end
		end
		outline("DesignHover", 1, function(use: Use): string?
			local id = use(hovered)
			return if use(editing.interactive) or id == use(editing.selected) then nil else id
		end, false)
		outline("DesignSelected", 2, function(use: Use): string?
			return if use(editing.interactive) then nil else use(editing.selected)
		end, true)
		capture.Parent = ctx.overlay or root
	end
	return root
end

function render.definition(value: document.Document, editing: any?): any
	return {
		name = value.name,
		previews = {
			{
				name = "Design",
				render = function(ctx)
					return render.build(value, ctx, editing)
				end,
			},
		},
	}
end

return render
