--!strict
local Facet = require("../../src")
local Controls = require("../../src/ui/control_types")

return function(UI: Facet.Controls)
	local picker: (Facet.SinglePickerSpec<string>) -> GuiObject = UI.Picker "Language"
	local pickerFactory: (string) -> (Facet.SinglePickerSpec<string>) -> GuiObject = UI.Picker
	local list: (Facet.KeyedCollectionSpec<{ id: number }, number>) -> ScrollingFrame = UI.VirtualList "Ranks"
	local listFactory: (string) -> (Facet.KeyedCollectionSpec<{ id: number }, number>) -> ScrollingFrame =
		UI.VirtualList
	local grid: (Facet.KeyedCollectionSpec<string, string>) -> ScrollingFrame = UI.VirtualGrid "Tiles"
	local outline: (Facet.KeyedOutlineSpec<string, string>) -> ScrollingFrame = UI.Outline "Tree"
	local spatial: (Facet.SpatialGridSpec<string, string>) -> Frame = UI.SpatialGrid "Inventory"
	local menu: (Facet.MenuSpec<string>) -> GuiObject = UI.Menu "Commands"
	local split: (Facet.SplitButtonSpec<string>) -> Frame = UI.SplitButton "Actions"
	local alert: (Facet.AlertSpec<unknown>) -> Frame = UI.Alert "Confirm"
	local navigation: (Facet.NavigationStackSpec<string>) -> Frame = UI.NavigationStack "Pages"
	local radial: Controls.RadialMenuBuilder = UI.RadialMenu
	local direct: TextButton = UI.Button { label = "Save" }
	local named: TextButton = UI.Button "Save" { label = "Save" }
	local generic: Frame = (UI.Alert "Confirm")<<unknown>> {
		isPresented = Facet.Compose.cell(false),
		actions = {},
	}
	local radialNode: Frame = radial<<string>> { items = {} }
	return {
		picker,
		pickerFactory,
		list,
		listFactory,
		grid,
		outline,
		spatial,
		menu,
		split,
		alert,
		navigation,
		radial,
		direct,
		named,
		generic,
		radialNode,
	}
end
