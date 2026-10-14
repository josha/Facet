--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local Content = require("./content_types")
local ControlTypes = require("./control_types")
local InputProps = require("./input_props")
local MediaProps = require("./media_props")
local NavigationProps = require("./navigation_props")
local pageLayers = require("./nav_page_layers")
local tabView = require("./nav_tab_view")
local navigationStack = require("./nav_stack")
local pageView = require("./nav_page_view")

type Controls = {
	TabView: Types.Constructor<NavigationProps.TabViewSpec, Frame>,
	NavigationStack: ControlTypes.NavigationStackConstructor,
	PageView: Types.Constructor<NavigationProps.PageViewSpec, Frame>,
	Button: Types.Constructor<InputProps.ButtonProps, TextButton>,
	Menu: ControlTypes.MenuConstructor,
	Picker: ControlTypes.PickerConstructor,
	StatusIndicator: Types.Constructor<MediaProps.StatusIndicatorProps, TextLabel>,
	Badge: Types.Constructor<MediaProps.BadgeProps, GuiObject>,
	badged: Content.Badged,
}

return function(ctx: Types.Context, UI: Controls, surfaces: Nav.Surfaces): ()
	local layers = pageLayers(ctx)
	tabView(ctx, UI, surfaces, layers)
	navigationStack(ctx, UI, surfaces, layers)
	pageView(ctx, UI, surfaces, layers)
end
