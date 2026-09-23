--!strict
local context = require("@self/context")
local Types = require("@self/control_types")
return function(runtime: Types.Runtime, options: Types.Config?): Types.Controls
	local ctx = context(runtime, options)
	local UI = ({} :: unknown) :: Types.Controls
	require("@self/inputs")(ctx, UI)
	local surfaces = require("@self/nav_modal")(ctx)
	require("@self/nav_menu")(ctx, UI, surfaces)
	require("@self/nav_surfaces")(ctx, UI, surfaces)
	require("@self/nav_pages")(ctx, UI, surfaces)
	require("@self/nav_radial")(ctx, UI, surfaces)
	require("@self/collections")(ctx, UI)
	require("@self/collection_row_actions")(ctx, UI)
	require("@self/collection_table")(ctx, UI)
	require("@self/media")(ctx, UI)
	table.freeze(UI)
	return UI
end
