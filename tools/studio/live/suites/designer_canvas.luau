--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Render = typeof(require("@repo/tools/designer/modules/design_render"))
type Templates = typeof(require("@repo/tools/designer/modules/templates"))
type Designer = typeof(require("@repo/tools/designer/modules/designer"))
type Document = typeof(require("@repo/tools/designer/modules/document"))
type Library = typeof(require("@repo/tools/designer/modules/library"))
type Live = {
	mount: ((FacetControls, RobloxHost, ComposeModule) -> Instance, { size: Vector2 }) -> Instance,
	settle: (number) -> (),
	find: (Instance, string) -> Instance?,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
}
type Probe = { width: (() -> number)?, expected: string?, read: () -> unknown, close: () -> () }
type Case = {
	id: string,
	contracts: { string },
	plan: string?,
	run: ((Live) -> ())?,
	setup: ((Live) -> Probe)?,
	steps: { [string]: (Live, Probe) -> () }?,
}
local loadRender: (ModuleScript) -> Render = require
local loadTemplates: (ModuleScript) -> Templates = require
local loadDesigner: (ModuleScript) -> Designer = require
local loadDocument: (ModuleScript) -> Document = require
local loadLibrary: (ModuleScript) -> Library = require
type FacetModule = typeof(require("@repo/src"))
type DesignEditorModule = typeof(require("@repo/src/vendor/compose/design-editor"))
local loadFacet: (ModuleScript) -> FacetModule = require
local loadEditor: (ModuleScript) -> DesignEditorModule = require
local Live = require(script.Parent.Parent)

local function module(name: string): ModuleScript
	local folder = ReplicatedStorage:WaitForChild("FacetDesignModules")
	local found = folder:WaitForChild(name)
	assert(found:IsA("ModuleScript"), `{name} is a ModuleScript`)
	return found
end

local function facetModule(): ModuleScript
	local found = ReplicatedStorage:WaitForChild("Facet")
	assert(found:IsA("ModuleScript"), "Facet is a ModuleScript")
	return found
end

local cases: { Case } = {
	{
		id = "compose-design-edits-facet-controls",
		contracts = {},
		run = function(t: Live)
			local Facet = loadFacet(facetModule())
			local editorModule =
				facetModule():WaitForChild("vendor"):WaitForChild("compose"):WaitForChild("design-editor")
			assert(editorModule:IsA("ModuleScript"), "design-editor is a ModuleScript")
			local DesignEditor = loadEditor(editorModule)
			local screen = Instance.new("ScreenGui")
			screen.Name = "ComposeDesignProbe"
			screen.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local host = Instance.new("Frame")
			host.Size = UDim2.fromOffset(1200, 760)
			host.Parent = screen
			local runtime = Facet.Roblox.createRuntime()
			local library = Facet.design().library({
				UI = Facet.controls(runtime),
				rgb = Color3.fromRGB,
				udim2 = UDim2.new,
				offset = UDim2.fromOffset,
			})
			local editor =
				DesignEditor.create(library, Facet.design().Design.document.new("Probe", library, "VStack"), host, {
					runtime = runtime,
					environment = Facet.Roblox.designEnvironment(),
					stageSize = { X = 390, Y = 640 },
				})
			t.settle(10)
			t.check("the editor inserts a Facet Button", editor.session.insert("Button"))
			t.check("the editor relabels the Button", editor.session.change("label", { literal = "Buy" }))
			t.settle(10)
			local stage = t.find(host, "StagePanel")
			local button: GuiObject? = nil
			for _, node in (stage or host):GetDescendants() do
				if node:IsA("TextLabel") and node.Text == "Buy" then
					button = node
				end
			end
			local stageFrame = stage :: GuiObject?
			local inside = button ~= nil
				and stageFrame ~= nil
				and button.AbsoluteSize.X > 0
				and button.AbsolutePosition.X >= stageFrame.AbsolutePosition.X
				and button.AbsolutePosition.Y >= stageFrame.AbsolutePosition.Y
			t.check("the stage paints the relabelled Facet Button inside the stage", inside, {
				size = if button then button.AbsoluteSize else nil,
				position = if button then button.AbsolutePosition else nil,
			})
			local kinds = t.find(host, "Kinds")
			local entries = 0
			if kinds then
				for _, node in kinds:GetChildren() do
					if node:IsA("TextButton") then
						entries += 1
					end
				end
			end
			t.check("the Library panel lists every Facet control", entries >= 66, { entries = entries })
			editor.dispose()
			runtime:dispose()
			screen:Destroy()
		end,
	},
	{
		id = "drag-moves-a-layer-below-its-siblings",
		contracts = {},
		plan = "drag: drag from first to below",
		setup = function(t: Live): Probe
			local designer = loadDesigner(module("designer"))
			local document = loadDocument(module("document"))
			local value = document.new("Move probe")
			local first, second, third
			value, first = document.insert(value, value.root.id, "Text")
			value, second = document.insert(value, value.root.id, "Text")
			value, third = document.insert(value, value.root.id, "Text")
			local screen = Instance.new("ScreenGui")
			screen.Name = "DesignerMoveProbe"
			screen.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local session = designer.mount(require(ReplicatedStorage:WaitForChild("Facet")), screen, {
				read = function()
					return { draft = value }
				end,
			})
			t.settle(20)
			local layers: { GuiObject } = {}
			for _, child in value.root.children do
				for _, node in screen:GetDescendants() do
					if node:GetAttribute("FacetDesignNode") == child.id and node:IsA("GuiObject") and node.Visible then
						table.insert(layers, node)
						break
					end
				end
			end
			assert(#layers == 3, "the three layers are on the canvas")
			local from = layers[1].AbsolutePosition + layers[1].AbsoluteSize / 2
			local last = layers[3]
			t.note("points", {
				first = { math.floor(from.X + 0.5), math.floor(from.Y + 0.5) },
				below = { math.floor(from.X + 0.5), math.floor(last.AbsolutePosition.Y + last.AbsoluteSize.Y + 12.5) },
			})
			return {
				expected = table.concat({ second, third, first }, ","),
				read = function(): unknown
					local children = session.document().root.children
					local ids: { string } = {}
					for _, child in children do
						table.insert(ids, child.id)
					end
					return table.concat(ids, ",")
				end,
				close = function()
					session.dispose()
					screen:Destroy()
				end,
			}
		end,
		steps = {
			drag = function(t: Live, probe: Probe)
				t.settle(10)
				local order = probe.read()
				t.check(
					"dragging the first layer below the last one moves it to the end",
					order == probe.expected,
					{ order = order, expected = probe.expected }
				)
				probe.close()
			end,
		},
	},
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
	{
		id = "resize-handle-drag-sets-the-layer-width",
		contracts = {},
		plan = "drag: drag from east to past",
		setup = function(t: Live): Probe
			local designer = loadDesigner(module("designer"))
			local document = loadDocument(module("document"))
			local library = loadLibrary(module("library"))
			local screen = Instance.new("ScreenGui")
			screen.Name = "DesignerResizeProbe"
			screen.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local session = designer.mount(require(ReplicatedStorage:WaitForChild("Facet")), screen, {})
			t.settle(20)
			local value = session.document()
			local chosen: string? = nil
			for _, row in document.rows(value.root) do
				if chosen == nil and row.id ~= value.root.id and library.descriptor(row.kind, "width") then
					chosen = row.id
				end
			end
			local id = assert(chosen, "the template has a layer with a width")
			session.actions.select(id)
			t.settle(10)
			local grip = t.find(screen, "ResizeEast")
			assert(
				grip and grip:IsA("GuiObject") and grip.Parent and grip.Parent:IsA("GuiObject"),
				"the resize handle is shown"
			)
			local frame = grip.Parent
			local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
			assert(detector, "the handle has a drag detector")
			local function design(): number
				return frame.Size.X.Offset + 40 * frame.Size.X.Offset / frame.AbsoluteSize.X
			end
			local width = design()
			local started = detector.DragStart:Connect(function()
				width = design()
			end)
			local centre = grip.AbsolutePosition + grip.AbsoluteSize / 2
			t.note("points", {
				east = { math.floor(centre.X + 0.5), math.floor(centre.Y + 0.5) },
				past = { math.floor(centre.X + 40.5), math.floor(centre.Y + 0.5) },
			})
			return {
				width = function(): number
					return width
				end,
				read = function(): unknown
					local node = document.find(session.document().root, id)
					return if node then node.props.width else nil
				end,
				close = function()
					started:Disconnect()
					session.dispose()
					screen:Destroy()
				end,
			}
		end,
		steps = {
			drag = function(t: Live, probe: Probe)
				t.settle(10)
				local width = probe.read()
				local expected = math.round(assert(probe.width)() / 4) * 4
				t.check(
					"dragging the east handle 40 screen px sets the snapped design width",
					type(width) == "number" and math.abs(width - expected) <= 4 and width % 4 == 0,
					{ width = width, expected = expected }
				)
				probe.close()
			end,
		},
	},
}

return cases
