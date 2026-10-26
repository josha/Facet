--!strict

local Facet = require(script.Facet)
local designer = require(script.Modules.designer)
local bridge = require(script.Modules.studio_bridge)
local toolbar = plugin:CreateToolbar("Facet Design")
local button = toolbar:CreateButton("FacetDesign", "Open the Facet visual UI builder", "", "Design")
button.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"FacetDesign.Canvas.v1",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1280, 850, 1050, 600)
)
widget.Title = "Facet Design"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local mounted
local function show()
	button:SetActive(widget.Enabled)
	if widget.Enabled then
		if not mounted then
			mounted = designer.mount(Facet, widget, bridge.new(plugin))
		end
	elseif mounted then
		mounted.dispose()
		mounted = nil
	end
end
local connection = widget:GetPropertyChangedSignal("Enabled"):Connect(show)
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
local DesignEditor = require(script.Facet.vendor.compose["design-editor"])
local composeButton =
	toolbar:CreateButton("ComposeDesign", "Author a Facet screen as a Compose Design document", "", "Compose Design")
composeButton.ClickableWhenViewportHidden = true
local composeWidget = plugin:CreateDockWidgetPluginGuiAsync(
	"FacetDesign.Compose.v1",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1280, 850, 1050, 600)
)
composeWidget.Title = "Compose Design"
composeWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local composed: { dispose: () -> () }? = nil
local function showCompose()
	composeButton:SetActive(composeWidget.Enabled)
	if composeWidget.Enabled and not composed then
		local runtime = Facet.Roblox.createRuntime()
		local library = Facet.design().library({
			UI = Facet.controls(runtime),
			rgb = Color3.fromRGB,
			udim2 = UDim2.new,
			offset = UDim2.fromOffset,
		})
		local editor = DesignEditor.create(
			library,
			Facet.design().Design.document.new("Screen", library, "Screen"),
			composeWidget,
			{
				runtime = runtime,
				environment = Facet.Roblox.designEnvironment(),
				stageSize = { X = 390, Y = 844 },
				onExport = function(source: string)
					local history = game:GetService("ChangeHistoryService")
					local storage = game:GetService("ReplicatedStorage")
					local recording = history:TryBeginRecording("ComposeDesign.Export", "Export Compose Design")
					local folder = storage:FindFirstChild("FacetDesigns") or Instance.new("Folder")
					folder.Name = "FacetDesigns"
					folder.Parent = storage
					local target = folder:FindFirstChild("Screen")
					if not (target and target:IsA("ModuleScript")) then
						target = Instance.new("ModuleScript")
						target.Name = "Screen"
						target.Parent = folder
					end
					local module = target :: ModuleScript
					game:GetService("ScriptEditorService"):UpdateSourceAsync(module, function()
						return source
					end)
					if recording then
						history:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
					end
				end,
			}
		)
		composed = {
			dispose = function()
				editor.dispose()
				runtime:dispose()
			end,
		}
	elseif not composeWidget.Enabled and composed then
		composed.dispose()
		composed = nil
	end
end
local composeConnection = composeWidget:GetPropertyChangedSignal("Enabled"):Connect(showCompose)
composeButton.Click:Connect(function()
	composeWidget.Enabled = not composeWidget.Enabled
end)
local undoAction =
	plugin:CreatePluginAction("FacetDesign.Undo", "Facet Design: Undo", "Undo the last design edit", "", true)
undoAction.Triggered:Connect(function()
	if mounted then
		mounted.actions.undo()
	end
end)
plugin.Unloading:Connect(function()
	connection:Disconnect()
	composeConnection:Disconnect()
	if composed then
		composed.dispose()
	end
	composeWidget:Destroy()
	if mounted then
		mounted.dispose()
	end
	widget:Destroy()
	toolbar:Destroy()
end)
show()
