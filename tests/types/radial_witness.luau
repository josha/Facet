--!strict
local Compose = require("../../src/vendor/compose/core")
local Radial = require("../../src/ui/radial_types")
local children: Compose.Value<{ Radial.RadialItem<string> }> = Compose.cell({})
local selected = Compose.cell("first")
local checked = Compose.cell(false)
local choice: Radial.RadialChoice<string> = {
	id = "choice",
	label = "Choice",
	selected = selected,
	value = "first",
	onChange = function(value: string)
		selected:set(value)
	end,
}
local check: Radial.RadialCheck<string> = {
	id = "check",
	label = "Check",
	checked = checked,
	onChange = function(value: boolean)
		checked:set(value)
	end,
}
local parent: Radial.RadialAction<string> = { id = "children", label = "Children", children = children }
local items: { Radial.RadialItem<string> } = { choice, check, parent }
return items
