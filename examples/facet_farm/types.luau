--!strict

local Facet = require("../../src")
type Tool = "plow" | "plant" | "harvest"

local function exports(): {
	ToolCell: Facet.Value<Tool>,
	ToolPickerOption: Facet.PickerOption<Tool>,
	ToolRadialChoice: Facet.RadialChoice<Tool>,
	ToolRadialItem: Facet.RadialItem<Tool>,
}
	error("examples/facet_farm/types.luau holds types only")
end

return exports()
