--!strict

local Facet = require("../../src")
type Tool = "plow" | "plant" | "harvest"
type Crop = "wheat" | "carrot" | "strawberry" | "pumpkin"

local function exports(): {
	ToolCell: Facet.Value<Tool>,
	ToolPickerOption: Facet.PickerOption<Tool>,
	ToolRadialChoice: Facet.RadialChoice<Tool>,
	SeedPickerOption: Facet.PickerOption<Crop>,
	ToolRadialItem: Facet.RadialItem<Tool>,
}
	error("examples/facet_farm/types.luau holds types only")
end

return exports()
