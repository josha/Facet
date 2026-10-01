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
local undoAction =
	plugin:CreatePluginAction("FacetDesign.Undo", "Facet Design: Undo", "Undo the last design edit", "", true)
undoAction.Triggered:Connect(function()
	if mounted then
		mounted.actions.undo()
	end
end)
plugin.Unloading:Connect(function()
	connection:Disconnect()
	if mounted then
		mounted.dispose()
	end
	widget:Destroy()
	toolbar:Destroy()
end)
show()
