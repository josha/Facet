--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local NavigationProps = require("./navigation_props")
local surfaceParts = require("./nav_surface_parts")
local disclosure = require("./nav_disclosure")
local collapsible = require("./nav_collapsible")
local alert = require("./nav_alert")
local callout = require("./nav_callout")

type Controls = {
	DisclosureGroup: Types.Constructor<NavigationProps.DisclosureGroupSpec, Frame>,
	CollapsibleView: Types.Constructor<NavigationProps.CollapsibleViewSpec, TextButton>,
	Alert: ControlTypes.AlertConstructor,
	Callout: Types.Constructor<NavigationProps.CalloutSpec, Frame>,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
	Toggle: Types.Constructor<InputProps.ToggleProps, TextButton>,
	Picker: ControlTypes.PickerConstructor,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local kit = surfaceParts(ctx)
	disclosure(ctx, UI, surfaces, kit)
	collapsible(ctx, UI, surfaces, kit)
	alert(ctx, UI, surfaces, kit)
	callout(ctx, UI, surfaces, kit)
end
