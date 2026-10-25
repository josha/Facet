--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Render = typeof(require("@repo/tools/designer/modules/design_render"))
type Templates = typeof(require("@repo/tools/designer/modules/templates"))
type Designer = typeof(require("@repo/tools/designer/modules/designer"))
type Document = typeof(require("@repo/tools/designer/modules/document"))
type Live = {
	mount: ((FacetControls, RobloxHost, ComposeModule) -> Instance, { size: Vector2 }) -> Instance,
	settle: (number) -> (),
	find: (Instance, string) -> Instance?,
	check: (string, boolean, unknown?) -> (),
}
local loadRender: (ModuleScript) -> Render = require
local loadTemplates: (ModuleScript) -> Templates = require
local loadDesigner: (ModuleScript) -> Designer = require
local loadDocument: (ModuleScript) -> Document = require
local Live = require(script.Parent.Parent)

local function module(name: string): ModuleScript
	local folder = ReplicatedStorage:WaitForChild("FacetDesignModules")
	local found = folder:WaitForChild(name)
	assert(found:IsA("ModuleScript"), `{name} is a ModuleScript`)
	return found
end

return {
	{
		id = "selection-overlay-follows-the-layer",
		contracts = {},
		run = function(t: Live)
			local render = loadRender(module("design_render"))
			local templates = loadTemplates(module("templates"))
			local value = templates[1]
			local child = value.root.children[1]
			local selected
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
				selected = Compose.cell(value.root.id)
				local ctx = {
					UI = UI,
					Host = Host,
					Compose = Compose,
					types = { UDim2 = UDim2, UDim = UDim, Vector2 = Vector2, Color3 = Color3, Enum = Enum, Font = Font },
				}
				return render.build(value, ctx, {
					selected = selected,
					interactive = Compose.cell(false),
					select = function(id: string)
						selected:set(id)
					end,
				})
			end, { size = Vector2.new(1024, 720) })
			t.settle(10)
			selected:set(child.id)
			t.settle(5)
			local frame = t.find(stage, "DesignSelected")
			local target: GuiObject? = nil
			for _, node in stage:GetDescendants() do
				if node:GetAttribute("FacetDesignNode") == child.id and node:IsA("GuiObject") then
					target = node
				end
			end
			assert(frame and frame:IsA("Frame") and target, "the selection outline and its layer exist")
			t.check("the selection outline is shown", frame.Visible)
			local delta = (frame.AbsolutePosition - target.AbsolutePosition).Magnitude
			local size = (frame.AbsoluteSize - target.AbsoluteSize).Magnitude
			t.check("the outline covers the selected layer", delta <= 1 and size <= 1, { delta = delta, size = size })
			local label = frame:FindFirstChild("Size")
			local text = if label and label:IsA("TextLabel") then label.Text else nil
			t.check(
				"the outline names the layer size",
				text == `{math.round(target.AbsoluteSize.X)} × {math.round(target.AbsoluteSize.Y)}`,
				text
			)
		end,
	},
	{
		id = "delete-key-removes-the-selected-layer",
		contracts = {},
		run = function(t: Live)
			local designer = loadDesigner(module("designer"))
			local document = loadDocument(module("document"))
			local screen = Instance.new("ScreenGui")
			screen.Name = "DesignerProbe"
			screen.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local session = designer.mount(require(ReplicatedStorage:WaitForChild("Facet")), screen, {})
			t.settle(20)
			local value = session.document()
			local child = value.root.children[1]
			session.actions.select(child.id)
			t.settle(5)
			local action: InputAction? = nil
			for _, node in screen:GetDescendants() do
				if
					node:IsA("InputAction")
					and node.Name == "Delete"
					and node.Parent
					and node.Parent.Name == "DesignShortcuts"
				then
					action = node
				end
			end
			local bound = assert(action, "DesignShortcuts has a Delete action")
			local binding = bound:FindFirstChildWhichIsA("InputBinding")
			t.check("Delete is bound to the Delete key", binding ~= nil and binding.KeyCode == Enum.KeyCode.Delete)
			Live.press({ "Delete" })
			t.settle(10)
			local found = document.find(session.document().root, child.id)
			t.check("Delete removes the selected layer", found == nil, child.id)
			session.dispose()
			screen:Destroy()
		end,
	},
}
