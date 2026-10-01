--!strict

local library = require("./library")
local document = require("./document")
local adapter = require("./adapter")

local render = {}

function render.build(value: document.Document, ctx: any, editing: any?): GuiObject
	document.validate(value)
	local UDim2 = if ctx.types then ctx.types.UDim2 else UDim2
	local locals = {}
	ctx.types = ctx.types or { UDim2 = UDim2, Color3 = Color3 }
	local build
	build = function(node: document.Node): GuiObject
		local definition = library.definitions[node.kind]
		local props = adapter.evaluate(adapter.properties(node), ctx, locals)
		if
			not definition.content
			and node.kind ~= "ErrorBoundary"
			and node.kind ~= "TabView"
			and node.kind ~= "PageView"
			and node.kind ~= "NavigationStack"
		then
			for _, child in node.children do
				table.insert(props, build(child))
			end
		end
		local instance = ctx.UI[node.kind](node.name)(props)
		if definition.anchor then
			instance =
				ctx.UI.VStack("__FacetDesignHost_" .. node.id) { gap = "s", locals["anchor_" .. node.id], instance }
		end
		if editing then
			instance:SetAttribute("FacetDesignNode", node.id)
			ctx.runtime.connect(instance, "InputBegan", function(input)
				if
					not editing.interactive:peek()
					and (
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					editing.select(node.id)
				end
			end)
			local stroke = ctx.Host.UIStroke {
				Color = Color3.fromRGB(53, 129, 247),
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				BorderStrokePosition = Enum.BorderStrokePosition.Inner,
				ZIndex = 10,
				Enabled = function(use)
					return not use(editing.interactive) and use(editing.selected) == node.id
				end,
			}
			stroke.Parent = instance
		end
		return instance
	end
	ctx.render = build
	local root = build(value.root)
	if editing then
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
		local capture = ctx.Host.Frame "DesignSelection" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Active = true,
			ZIndex = 2000,
			Visible = function(use)
				return not use(editing.interactive)
			end,
			[ctx.Compose.event("InputBegan")] = function(input)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local chosen, deepest = value.root.id, 0
				for _, instance in root:GetDescendants() do
					local id = instance:GetAttribute("FacetDesignNode")
					if type(id) == "string" and instance:IsA("GuiObject") and contains(instance, input.Position) then
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
				editing.select(chosen)
			end,
		}
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
