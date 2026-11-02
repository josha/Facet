--!strict
local Compose = require("../../src/vendor/compose/core")
local Radial = require("../../src/ui/radial_types")
type ChoiceValue = string | boolean | nil
local children: Compose.Value<{ Radial.RadialItem<ChoiceValue> }> = Compose.cell({})
local selected = Compose.cell<<ChoiceValue>>("first")
local checked = Compose.cell(false)
local choice: Radial.RadialChoice<ChoiceValue> = {
	id = "choice",
	label = "Choice",
	selected = selected,
	value = "first",
	onChange = function(value: ChoiceValue)
		selected:set(value)
	end,
}
local check: Radial.RadialCheck<ChoiceValue> = {
	id = "check",
	label = "Check",
	checked = checked,
	onChange = function(value: boolean)
		checked:set(value)
	end,
}
local parent: Radial.RadialAction<ChoiceValue> = { id = "children", label = "Children", children = children }
local items: { Radial.RadialItem<ChoiceValue> } = { choice, check, parent }
return items
