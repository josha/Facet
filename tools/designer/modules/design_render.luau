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
				ctx.UI.VStack("__FacetDesignHost_" .. node.id) { gap = "s", state["anchor_" .. node.id], instance }
		end
		if editing then
			instance:SetAttribute("FacetDesignNode", node.id)
			nodes[node.id] = instance
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
		local function contains(instance: GuiObject, position: Vector3): boolean
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
		local function pick(position: Vector3): string
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
		local capture = Host.Frame "DesignSelection" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 2000,
			Visible = function(use: Use)
				return not use(editing.interactive)
			end,
			[Compose.event("InputBegan")] = function(input: InputObject)
				if pointer(input) then
					editing.select(pick(input.Position))
				end
			end,
			[Compose.event("InputChanged")] = function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					hovered:set(pick(input.Position))
				end
			end,
			[Compose.event("MouseLeave")] = function()
				hovered:set(nil)
			end,
		}
		local function outline(name: string, thickness: number, target: (Use) -> string?, sized: boolean)
			local readout = if sized
				then Host.TextLabel "Size" {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 1, 4),
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundColor3 = accent,
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 12,
					FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
					Interactable = false,
					Host.UIPadding {
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
						PaddingTop = UDim.new(0, 1),
						PaddingBottom = UDim.new(0, 1),
					},
					Host.UICorner { CornerRadius = UDim.new(0, 3) },
				}
				else nil
			local frame = Host.Frame(name) {
				BackgroundTransparency = 1,
				Visible = false,
				Interactable = false,
				ZIndex = 2001,
				Host.UIStroke { Color = accent, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
				readout,
			}
			local shown: GuiObject? = nil
			local function place()
				local instance = shown
				if instance == nil or instance.Parent == nil then
					frame.Visible = false
					return
				end
				local origin, at, size = capture.AbsolutePosition, instance.AbsolutePosition, instance.AbsoluteSize
				frame.Position = UDim2.fromOffset(at.X - origin.X, at.Y - origin.Y)
				frame.Size = UDim2.fromOffset(size.X, size.Y)
				frame.Visible = true
				if readout then
					readout.Text = `{math.round(size.X)} × {math.round(size.Y)}`
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
