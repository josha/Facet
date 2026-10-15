--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ControlTypes = require("./control_types")
local pageLayers = require("./nav_page_layers")
local tabView = require("./nav_tab_view")
local navigationStack = require("./nav_stack")
local pageView = require("./nav_page_view")

return function(ctx: Types.Context, UI: ControlTypes.BuilderControls, surfaces: Nav.Surfaces): ()
	local layers = pageLayers(ctx)
	tabView(ctx, UI, surfaces, layers)
	navigationStack(ctx, UI, surfaces, layers)
	pageView(ctx, UI, surfaces, layers)
end
