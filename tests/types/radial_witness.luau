--!strict
local Compose = require("../../src/vendor/compose/core")
local Radial = require("../../src/ui/radial_types")
local children: Compose.Cell<{ Radial.RadialItem<string> }> = Compose.cell({} :: { Radial.RadialItem<string> })
local selected = Compose.cell("first")
local checked = Compose.cell(false)
local items: { Radial.RadialItem<string> } = {
	{
		id = "choice",
		label = "Choice",
		selected = selected,
		value = "first",
		onChange = function(value: string)
			selected:set(value)
		end,
	},
	{
		id = "check",
		label = "Check",
		checked = checked,
		onChange = function(value: boolean)
			checked:set(value)
		end,
	},
	{ id = "children", label = "Children", children = children },
}
return items
