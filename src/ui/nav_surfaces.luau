--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ControlTypes = require("./control_types")
local surfaceParts = require("./nav_surface_parts")
local disclosure = require("./nav_disclosure")
local collapsible = require("./nav_collapsible")
local alert = require("./nav_alert")
local callout = require("./nav_callout")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces): ()
	local kit = surfaceParts(ctx)
	disclosure(ctx, UI, surfaces, kit)
	collapsible(ctx, UI, surfaces, kit)
	alert(ctx, UI, surfaces, kit)
	callout(ctx, UI, surfaces, kit)
end
