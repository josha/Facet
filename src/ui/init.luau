--!strict
local context = require("@self/context")
local Types = require("@self/control_types")
local freeze = require("@self/freeze")
local controlEnvironment = require("@self/control_environment")

type Group = { names: { string }, install: () -> () }

local function once<T>(make: () -> T): () -> T
	local made: { value: T }? = nil
	return function(): T
		local box = made
		if box == nil then
			box = { value = make() }
			made = box
		end
		return (box :: { value: T }).value
	end
end

return function(Compose: Types.ComposeModule, runtime: Types.Runtime, options: Types.Config?): Types.Controls
	local environment = controlEnvironment(Compose)
	if options == nil then
		local inherited = environment.read()[runtime]
		if inherited ~= nil then
			return inherited
		end
	end
	local ctx = context(Compose, runtime, options)
	local installed = {} :: { [string]: unknown }
	local UI = (installed :: unknown) :: Types.Controls
	local controls: Types.Controls
	installed.provide = function<R...>(body: () -> R...): R...
		local inherited = table.clone(environment.read())
		inherited[runtime] = controls
		return environment.provide(inherited, body)
	end

	local surfaces = once(function()
		return require("@self/nav_modal")(ctx)
	end)
	local inputKit = once(function()
		return require("@self/input_kit")(ctx)
	end)
	local media = once(function()
		return require("@self/media_shared")(ctx)
	end)
	local surfaceParts = once(function()
		return require("@self/nav_surface_parts")(ctx)
	end)
	local pageLayers = once(function()
		return require("@self/nav_page_layers")(ctx)
	end)
	local lists = once(function()
		return require("@self/collections")(ctx, UI)
	end)
	local function deferredHelp(anchor: GuiObject, value: unknown, plate: unknown)
		surfaces()
		local show = ctx.showHelp
		if type(show) == "function" and show ~= deferredHelp then
			(show :: (GuiObject, unknown, unknown) -> ())(anchor, value, plate)
		end
	end
	ctx.showHelp = deferredHelp

	local loaders: { [string]: () -> () } = {}
	local groups: { Group } = {
		{
			names = {
				"VStack",
				"HStack",
				"Screen",
				"ZStack",
				"ScrollView",
				"Grid",
				"AdaptiveStack",
				"ViewThatFits",
				"ErrorBoundary",
				"Divider",
				"Spacer",
				"fill",
			},
			install = function()
				require("@self/layout")(ctx, UI)
			end,
		},
		{
			names = { "Region", "Composition" },
			install = function()
				require("@self/composition")(ctx, UI)
			end,
		},
		{
			names = { "Button" },
			install = function()
				require("@self/input_button")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "Toggle" },
			install = function()
				require("@self/input_toggle")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "TextInput", "NumberInput" },
			install = function()
				require("@self/text_field")(ctx, UI)
			end,
		},
		{
			names = { "Stepper" },
			install = function()
				require("@self/input_stepper")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "feedback", "adjustable" },
			install = function()
				require("@self/input_actions")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "Slider" },
			install = function()
				require("@self/slider")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "LevelPicker", "Rating" },
			install = function()
				require("@self/input_level")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "Chip" },
			install = function()
				require("@self/input_chip")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "ShortcutHint" },
			install = function()
				require("@self/input_shortcut_hint")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "ButtonGuide" },
			install = function()
				require("@self/input_button_guide")(ctx, UI, inputKit())
			end,
		},
		{
			names = { "commandScope" },
			install = function()
				require("@self/command_scope")(ctx, UI)
			end,
		},
		{
			names = { "Menu", "Picker", "SplitButton", "ComboBox" },
			install = function()
				require("@self/nav_menu")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "DisclosureGroup" },
			install = function()
				require("@self/nav_disclosure")(ctx, UI, surfaces(), surfaceParts())
			end,
		},
		{
			names = { "CollapsibleView" },
			install = function()
				require("@self/nav_collapsible")(ctx, UI, surfaces(), surfaceParts())
			end,
		},
		{
			names = { "Alert" },
			install = function()
				require("@self/nav_alert")(ctx, UI, surfaces(), surfaceParts())
			end,
		},
		{
			names = { "Callout" },
			install = function()
				require("@self/nav_callout")(ctx, UI, surfaces(), surfaceParts())
			end,
		},
		{
			names = { "Sheet" },
			install = function()
				require("@self/nav_sheet")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "Dialog" },
			install = function()
				require("@self/nav_dialog")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "Popover" },
			install = function()
				loaders.Sheet()
				require("@self/nav_popover")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "Notice", "NavBar" },
			install = function()
				require("@self/nav_notice")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "Toast" },
			install = function()
				require("@self/nav_toast")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "TabView" },
			install = function()
				require("@self/nav_tab_view")(ctx, UI, surfaces(), pageLayers())
			end,
		},
		{
			names = { "NavigationStack" },
			install = function()
				require("@self/nav_stack")(ctx, UI, surfaces(), pageLayers())
			end,
		},
		{
			names = { "PageView" },
			install = function()
				require("@self/nav_page_view")(ctx, UI, surfaces(), pageLayers())
			end,
		},
		{
			names = { "RadialMenu" },
			install = function()
				require("@self/nav_radial")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "Outline", "VirtualList", "VirtualGrid" },
			install = function()
				lists()
			end,
		},
		{
			names = { "RowActions" },
			install = function()
				require("@self/collection_row_actions")(ctx, UI)
			end,
		},
		{
			names = { "Table", "CellEditor" },
			install = function()
				require("@self/collection_table")(ctx, UI, lists())
			end,
		},
		{
			names = { "Text", "Label" },
			install = function()
				require("@self/media_text")(ctx, UI, media())
			end,
		},
		{
			names = { "Image" },
			install = function()
				require("@self/media_image")(ctx, UI, media())
			end,
		},
		{
			names = { "Badge", "StatusIndicator" },
			install = function()
				require("@self/media_badge")(ctx, UI, media())
			end,
		},
		{
			names = { "Path" },
			install = function()
				require("@self/media_path")(ctx, UI)
			end,
		},
		{
			names = { "ProgressView" },
			install = function()
				require("@self/media_progress")(ctx, UI, media())
			end,
		},
		{
			names = { "Skeleton" },
			install = function()
				require("@self/media_skeleton")(ctx, UI)
			end,
		},
		{
			names = { "AsyncImage" },
			install = function()
				require("@self/media_async_image")(ctx, UI, media())
			end,
		},
		{
			names = { "Avatar", "AvatarGroup" },
			install = function()
				require("@self/media_avatar")(ctx, UI)
			end,
		},
		{
			names = { "Stage" },
			install = function()
				require("@self/media_stage")(ctx, UI, media())
			end,
		},
		{
			names = { "Timer" },
			install = function()
				require("@self/timer")(ctx, UI)
			end,
		},
		{
			names = { "Typewriter" },
			install = function()
				require("@self/typewriter")(ctx, UI)
			end,
		},
		{
			names = { "Pagination" },
			install = function()
				require("@self/pagination")(ctx, UI)
			end,
		},
		{
			names = { "StepIndicator" },
			install = function()
				require("@self/step_indicator")(ctx, UI)
			end,
		},
		{
			names = { "Vote" },
			install = function()
				require("@self/vote")(ctx, UI)
			end,
		},
		{
			names = { "Card" },
			install = function()
				require("@self/card")(ctx, UI)
			end,
		},
		{
			names = { "badged" },
			install = function()
				require("@self/badge_seal")(ctx, UI)
			end,
		},
		{
			names = { "DateTimePicker" },
			install = function()
				require("@self/date_time_picker")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "ColorPicker" },
			install = function()
				require("@self/color_picker")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "focusRing", "environment", "responder", "focusSection", "worldAnchor" },
			install = function()
				require("@self/environment")(ctx, UI)
			end,
		},
		{
			names = { "gestureArbiter", "draggable", "dropTarget" },
			install = function()
				require("@self/drag")(ctx, UI)
			end,
		},
		{
			names = { "SpatialGrid" },
			install = function()
				require("@self/spatial_grid")(ctx, UI)
			end,
		},
		{
			names = { "scrollTo", "scrollToVisible" },
			install = function()
				require("@self/scrolling")(ctx, UI)
			end,
		},
		{
			names = { "NavigationSplitView" },
			install = function()
				require("@self/navigation_split_view")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "countUp", "follow", "toward", "sequence" },
			install = function()
				require("@self/effect_sequence")(ctx, UI)
			end,
		},
		{
			names = { "shake" },
			install = function()
				require("@self/effect_shake")(ctx, UI)
			end,
		},
		{
			names = { "Flash" },
			install = function()
				require("@self/effect_flash")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "ZoomView" },
			install = function()
				require("@self/zoom_view")(ctx, UI)
			end,
		},
		{
			names = { "Travel" },
			install = function()
				require("@self/travel")(ctx, UI, surfaces())
			end,
		},
		{
			names = { "DiegeticScreen" },
			install = function()
				require("@self/diegetic_screen")(ctx, UI)
			end,
		},
		{
			names = { "cameraRig" },
			install = function()
				require("@self/camera_rig")(ctx, UI)
			end,
		},
		{
			names = { "WorldMarker" },
			install = function()
				require("@self/world_marker")(ctx, UI)
			end,
		},
	}

	local all: { () -> () } = {}
	for _, group in groups do
		local started = false
		local function load()
			if started then
				return
			end
			started = true
			local ok, problem: unknown = pcall(function(): boolean
				group.install()
				return true
			end)
			if not ok then
				started = false
				error(problem, 0)
			end
		end
		for _, name in group.names do
			loaders[name] = load
		end
		table.insert(all, load)
	end
	local members = (installed :: unknown) :: { [string]: unknown }
	setmetatable(installed, {
		__index = function(_: unknown, name: unknown): unknown
			if type(name) ~= "string" then
				return nil
			end
			local load = loaders[name]
			if load == nil then
				return nil
			end
			load()
			return rawget(members, name)
		end,
	})
	loaders.scrollTo()
	local function iterate(): (typeof(next), { [string]: unknown })
		for _, load in all do
			load()
		end
		return next, members
	end
	controls = (freeze(setmetatable({}, { __index = installed, __iter = iterate })) :: unknown) :: Types.Controls
	return controls
end
