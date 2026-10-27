--!strict
local context = require("@self/context")
local Types = require("@self/control_types")
local freeze = require("@self/freeze")
local controlEnvironment = require("@self/control_environment")
return function(Compose: Types.ComposeModule, runtime: Types.Runtime, options: Types.Config?): Types.Controls
	local environment = controlEnvironment(Compose)
	if options == nil then
		local inherited = environment.read()[runtime]
		if inherited ~= nil then
			return inherited
		end
	end
	local ctx = context(Compose, runtime, options)
	local UI = ({} :: unknown) :: Types.Controls
	UI.provide = function<R...>(body: () -> R...): R...
		local inherited = table.clone(environment.read())
		inherited[runtime] = UI
		return environment.provide(inherited, body)
	end
	require("@self/layout")(ctx, UI)
	require("@self/composition")(ctx, UI)
	require("@self/inputs")(ctx, UI)
	require("@self/command_scope")(ctx, UI)
	local surfaces = require("@self/nav_modal")(ctx)
	require("@self/nav_menu")(ctx, UI, surfaces)
	require("@self/nav_surfaces")(ctx, UI, surfaces)
	require("@self/nav_sheet")(ctx, UI, surfaces)
	require("@self/nav_dialog")(ctx, UI, surfaces)
	require("@self/nav_popover")(ctx, UI, surfaces)
	require("@self/nav_notice")(ctx, UI, surfaces)
	require("@self/nav_toast")(ctx, UI, surfaces)
	require("@self/nav_pages")(ctx, UI, surfaces)
	require("@self/nav_radial")(ctx, UI, surfaces)
	local buildList = require("@self/collections")(ctx, UI)
	require("@self/collection_row_actions")(ctx, UI)
	require("@self/collection_table")(ctx, UI, buildList)
	require("@self/media")(ctx, UI)
	require("@self/timer")(ctx, UI)
	require("@self/typewriter")(ctx, UI)
	require("@self/pagination")(ctx, UI)
	require("@self/step_indicator")(ctx, UI)
	require("@self/vote")(ctx, UI)
	require("@self/card")(ctx, UI)
	require("@self/badge_seal")(ctx, UI)
	require("@self/date_time_picker")(ctx, UI, surfaces)
	require("@self/color_picker")(ctx, UI, surfaces)
	require("@self/environment")(ctx, UI)
	require("@self/drag")(ctx, UI)
	require("@self/spatial_grid")(ctx, UI)
	require("@self/scrolling")(ctx, UI)
	require("@self/navigation_split_view")(ctx, UI, surfaces)
	require("@self/effect_sequence")(ctx, UI)
	require("@self/effect_shake")(ctx, UI)
	require("@self/effect_flash")(ctx, UI, surfaces)
	require("@self/zoom_view")(ctx, UI)
	require("@self/travel")(ctx, UI, surfaces)
	require("@self/diegetic_screen")(ctx, UI)
	require("@self/camera_rig")(ctx, UI)
	require("@self/world_marker")(ctx, UI)
	return freeze(UI)
end
